/*======================================================================
  03_portfolio_analytics.sas  -  Scale from 1 loan to a 50-loan portfolio
  ----------------------------------------------------------------------
  Builds a synthetic portfolio (reproducible via &SEED), appends Prestige,
  scores every loan with the SAME lifecycle macro, then analyses
  concentration, sector limits and rating mix.

  SAS concepts : RAND + CALL STREAMINIT, temporary ARRAYs, SET (stacking),
                 PROC SQL GROUP BY / CASE, PROC SORT, MERGE with IN=,
                 BY-group processing (FIRST. / LAST.), RETAIN & sum
                 statement, CALL SYMPUTX, PROC MEANS (CLASS/NWAY/OUTPUT),
                 PROC TRANSPOSE
  Requires     : 00_setup, 01_project_lifecycle
  NOTE         : all borrower data below is SIMULATED.
======================================================================*/

/*--- 1. Synthetic borrower generator ----------------------------------*/
%macro gen_portfolio(n=, out=);
  data &out;
    &INPUT_LENGTHS
    array sec{5} $20 _temporary_ ('Real Estate' 'Roads' 'Power' 'Ports' 'Renewables');
    array bnk{5} $20 _temporary_ ('SBI' 'ICICI' 'HDFC' 'Axis Bank' 'PNB');
    array cum{5} _temporary_ (0.10 0.25 0.55 0.85 1.00);   /* cumulative disbursement */
    call streaminit(&SEED);

    do i = 1 to &n;
      Borrower     = catx('_', 'Borrower', put(i, z3.));
      Project_Name = catx(' ', 'Project', put(i, z3.));
      Sector       = sec{1 + floor(rand('uniform') * 5)};

      Project_Cost_Cr  = round(500 + rand('uniform') * 7500, 10);
      Debt_Cr          = round(Project_Cost_Cr * (0.55 + rand('uniform') * 0.20), 10);
      Equity_Cr        = Project_Cost_Cr - Debt_Cr;
      Project_IRR      = round(10 + rand('uniform') * 12, 0.1);
      Industry_Risk    = 1 + floor(rand('uniform') * 3);
      Management_Score = 4 + floor(rand('uniform') * 7);

      if rand('uniform') < 0.98 then Land_Approval = 'Y'; else Land_Approval = 'N';
      if rand('uniform') < 0.98 then Legal_Clearance = 'Y'; else Legal_Clearance = 'N';
      if rand('uniform') < 0.98 then Environmental_Clearance = 'Y'; else Environmental_Clearance = 'N';
      if rand('uniform') < 0.98 then RERA_Approval = 'Y'; else RERA_Approval = 'N';

      Expected_Units      = round(500 + rand('uniform') * 9500, 100);
      Expected_Price_Lakh = round(80 + rand('uniform') * 170, 5);

      dscr_target            = 1.00 + rand('uniform') * 0.90;
      Annual_Debt_Service_Cr = round(Debt_Cr * 0.14, 1);
      Annual_CashFlow_Cr     = round(Annual_Debt_Service_Cr * dscr_target, 1);
      PV_Future_CashFlows_Cr = round(Debt_Cr * (1.05 + rand('uniform') * 0.85), 1);
      PV_Project_Life_Cr     = round(PV_Future_CashFlows_Cr * (1.05 + rand('uniform') * 0.15), 1);
      Revenue_Forecast       = round(Project_Cost_Cr * 0.18 * (0.7 + rand('uniform') * 0.6), 1);

      Loan_Tenor_Yrs = 10 + floor(rand('uniform') * 11);
      Moratorium_Yrs = 2 + floor(rand('uniform') * 3);
      Interest_Rate  = round(9 + rand('uniform') * 3, 0.25);
      Security_Cover = round(1.2 + rand('uniform') * 0.5, 0.05);

      k = 1 + floor(rand('uniform') * 5);              /* three DIFFERENT banks */
      Lead_Bank = bnk{k};
      Bank2     = bnk{mod(k, 5) + 1};
      Bank3     = bnk{mod(k + 1, 5) + 1};
      Lead_Bank_Share = round(Debt_Cr * 0.40, 1);
      Bank2_Share     = round(Debt_Cr * 0.30, 1);
      Bank3_Share     = Debt_Cr - Lead_Bank_Share - Bank2_Share;

      Milestones_Achieved       = 1 + floor(rand('uniform') * 5);
      Actual_Project_Cost       = round(Project_Cost_Cr * max(0.95, 1 + rand('normal', 0.08, 0.07)), 1);
      Construction_Delay_Months = floor(rand('uniform') * 20);

      if rand('uniform') < 0.10 then Days_Past_Due = 30 * (1 + floor(rand('uniform') * 4));
      else Days_Past_Due = 0;

      disb_est            = Debt_Cr * cum{Milestones_Achieved};
      Principal_Collected = round(disb_est * rand('uniform') * 0.04, 1);
      Interest_Collected  = round(disb_est * Interest_Rate / 100 * (0.80 + rand('uniform') * 0.20), 1);

      if rand('uniform') < 0.03 then Default_Flag = 'Y'; else Default_Flag = 'N';
      output;
    end;
    drop i k dscr_target disb_est;
  run;
%mend gen_portfolio;

%gen_portfolio(n=&N_BORROWERS, out=work.synth_portfolio);

/*--- 2. Stack Prestige + synthetic loans and score them all ----------*/
data cr.portfolio_input;
  set cr.prestige_input work.synth_portfolio;
run;

%run_lifecycle(inds=cr.portfolio_input, outds=cr.portfolio_scored);

/*--- 3. Sector view with PROC SQL -------------------------------------*/
proc sql;
  create table cr.sector_summary as
  select Sector,
         count(*)                          as N_Loans,
         sum(Loan_Amount_Cr)               as Exposure_Cr  format=comma14.0,
         sum(ECL)                          as ECL_Cr       format=comma12.2,
         calculated ECL_Cr / calculated Exposure_Cr as ECL_Rate format=percent8.2,
         avg(DSCR)                         as Avg_DSCR     format=6.2,
         sum(case when EWS_Flag = 'YES' then 1 else 0 end) as N_EWS
  from cr.portfolio_scored
  group by Sector
  order by calculated Exposure_Cr desc;
quit;

/*--- 4. MERGE with sector limits (IN= flags) ---------------------------*/
proc sort data=cr.sector_summary out=work.ss; by Sector; run;
proc sort data=cr.sector_limits  out=work.sl; by Sector; run;

data cr.sector_limit_check;
  length Limit_Status $8;
  merge work.ss(in=in_exp) work.sl(in=in_lim);
  by Sector;
  if in_exp;
  Utilisation_Pct = 100 * Exposure_Cr / Limit_Cr;
  if Utilisation_Pct > 100 then Limit_Status = 'BREACH';
  else if Utilisation_Pct >= 85 then Limit_Status = 'WARNING';
  else Limit_Status = 'OK';
  format Utilisation_Pct 6.1 Limit_Cr comma14.0;
run;

/*--- 5. Single-name concentration (RETAIN-style running totals + HHI) -*/
proc sql noprint;
  select sum(Loan_Amount_Cr) into :tot_exp trimmed from cr.portfolio_scored;
quit;

proc sort data=cr.portfolio_scored out=work.by_exposure;
  by descending Loan_Amount_Cr;
run;

data cr.concentration;
  set work.by_exposure(keep=Borrower Sector Loan_Amount_Cr Rating ECL) end=last;
  Rank = _n_;
  Cum_Exposure + Loan_Amount_Cr;                    /* sum statement = implicit RETAIN */
  Cum_Pct = 100 * Cum_Exposure / &tot_exp;
  HHI + (Loan_Amount_Cr / &tot_exp) ** 2;           /* Herfindahl-Hirschman index */
  if last then call symputx('hhi', put(HHI, 8.4));
  drop HHI;
run;
%put NOTE: Portfolio HHI = &hhi (below 0.15 is generally considered diversified);

/*--- 6. BY-group processing: largest loan per sector ------------------*/
proc sort data=cr.portfolio_scored out=work.sec_sorted;
  by Sector descending Loan_Amount_Cr;
run;

data cr.sector_top_borrower;
  set work.sec_sorted;
  by Sector;
  if first.Sector then Rank_in_Sector = 0;
  Rank_in_Sector + 1;
  if first.Sector;                                  /* keep only the largest */
  keep Sector Borrower Loan_Amount_Cr Rating ECL Rank_in_Sector;
run;

/*--- 7. Sector x rating matrix: PROC MEANS then PROC TRANSPOSE --------*/
proc means data=cr.portfolio_scored noprint nway;
  class Sector Rating;
  var Loan_Amount_Cr;
  output out=work.sec_rating(drop=_type_ _freq_) sum=Exposure_Cr;
run;

proc sort data=work.sec_rating; by Sector Rating; run;

proc transpose data=work.sec_rating out=cr.sector_rating_matrix(drop=_name_) prefix=R_;
  by Sector;
  id Rating;
  var Exposure_Cr;
run;

title "SECTOR LIMIT MONITORING";
proc print data=cr.sector_limit_check noobs;
  var Sector N_Loans Exposure_Cr Limit_Cr Utilisation_Pct Limit_Status ECL_Cr N_EWS;
run;

title "TOP 10 EXPOSURES";
proc print data=cr.concentration(obs=10) noobs;
  format Loan_Amount_Cr comma12.0 ECL comma12.2 Cum_Pct 6.1;
run;

title "LARGEST LOAN IN EACH SECTOR";
proc print data=cr.sector_top_borrower noobs;
run;

title "EXPOSURE (Rs Cr) BY SECTOR AND RATING";
proc print data=cr.sector_rating_matrix noobs;
run;
title;
