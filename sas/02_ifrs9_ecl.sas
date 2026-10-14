/*======================================================================
  02_ifrs9_ecl.sas  -  IFRS 9 lifetime ECL for the Prestige facility
  ----------------------------------------------------------------------
  Goes beyond the simple PD x LGD x EAD of step 14:
    * amortisation schedule with a moratorium
    * constant-hazard marginal PD curve
    * discounting at the effective interest rate
    * three macro-economic scenarios, probability weighted
    * stage-based reporting (Stage 1 = 12m, Stage 2 = lifetime, Stage 3 = default)

  SAS concepts : CALL SYMPUTX, DATA step without SET, RETAIN-free DO loop,
                 PROC SQL (cross join, CASE, CALCULATED, INTO :macro),
                 SELECT/WHEN, PROC PRINT with formats
  Requires     : 01_project_lifecycle.sas
======================================================================*/

/*--- 1. Pull the facility parameters into macro variables -------------*/
data _null_;
  set cr.prestige_final;
  call symputx('p_disb',  Total_Disbursed_Cr);
  call symputx('p_tenor', Loan_Tenor_Yrs);
  call symputx('p_mor',   Moratorium_Yrs);
  call symputx('p_rate',  Interest_Rate / 100);
  call symputx('p_pdl',   PD_Lifetime);
  call symputx('p_lgd',   LGD);
run;

/*--- 2. Amortisation schedule + PD curve --------------------------------
  Hazard h solves 1-(1-h)^N = lifetime PD (= the 12-month PD for a constant
  hazard), so survival after t years is (1-h)^t. */
data cr.amort_schedule;
  length Year 8;
  Hazard       = 1 - (1 - &p_pdl) ** (1 / &p_tenor);
  Surv_Prev    = 1;
  Opening_Bal  = &p_disb;
  Annual_Principal = &p_disb / (&p_tenor - &p_mor);

  do Year = 1 to &p_tenor;
    Interest_Cr     = Opening_Bal * &p_rate;
    if Year <= &p_mor then Principal_Cr = 0;           /* interest-only */
    else Principal_Cr = Annual_Principal;
    Debt_Service_Cr = Interest_Cr + Principal_Cr;
    Closing_Bal     = Opening_Bal - Principal_Cr;

    Surv_End   = Surv_Prev * (1 - Hazard);
    Marginal_PD = Surv_Prev - Surv_End;                /* P(default in year t) */
    Cum_PD      = 1 - Surv_End;
    DF          = 1 / ((1 + &EIR) ** Year);            /* discount factor */

    output;
    Opening_Bal = Closing_Bal;
    Surv_Prev   = Surv_End;
  end;

  keep Year Opening_Bal Interest_Cr Principal_Cr Debt_Service_Cr Closing_Bal
       Marginal_PD Cum_PD DF;
  format Opening_Bal Interest_Cr Principal_Cr Debt_Service_Cr Closing_Bal comma12.2
         Marginal_PD Cum_PD 8.5 DF 6.4;
run;

/*--- 3. Macro-economic scenarios -------------------------------------*/
data cr.ifrs9_scenarios;
  length Scenario $10;
  input Scenario $ Weight PD_Mult LGD_Mult;
  datalines;
Base     0.50 1.00 1.00
Upside   0.20 0.80 0.90
Downside 0.30 1.50 1.20
;
run;

/*--- 3b. Consistency check: does the input debt service match the schedule?
  The case study supplies Annual_Debt_Service_Cr = 1,000. The repayment
  profile (10% interest, 3-year moratorium, equal principal) implies a higher
  peak. This table shows the DSCR if you size cover against that peak.      */
proc sql noprint;
  select max(Debt_Service_Cr) into :peak_ds trimmed from cr.amort_schedule;
quit;

data cr.peak_dscr_check;
  set cr.prestige_final(keep=Borrower Annual_CashFlow_Cr Annual_Debt_Service_Cr DSCR);
  Peak_Debt_Service_Cr = &peak_ds;
  Peak_DSCR            = Annual_CashFlow_Cr / Peak_Debt_Service_Cr;
  label Peak_Debt_Service_Cr = 'Peak debt service from schedule (Rs Cr)'
        Peak_DSCR            = 'DSCR on peak debt service';
  format Peak_Debt_Service_Cr comma12.2 Peak_DSCR 6.2 DSCR 6.2;
run;

/*--- 4. ECL per scenario and year (cross join) -------------------------*/
proc sql;
  create table work.ecl_paths as
  select s.Scenario,
         s.Weight,
         a.Year,
         a.Opening_Bal,
         a.DF,
         min(1, a.Marginal_PD * s.PD_Mult)  as PD_Adj,
         min(1, &p_lgd * s.LGD_Mult)        as LGD_Adj,
         calculated PD_Adj * calculated LGD_Adj * a.Opening_Bal * a.DF as ECL_t
  from cr.amort_schedule as a,
       cr.ifrs9_scenarios as s
  order by s.Scenario, a.Year;
quit;

/*--- 5. Summarise: 12-month vs lifetime, then probability-weight ------*/
proc sql;
  create table cr.ecl_by_scenario as
  select Scenario,
         Weight,
         sum(case when Year = 1 then ECL_t else 0 end) as ECL_12m,
         sum(ECL_t)                                     as ECL_Lifetime
  from work.ecl_paths
  group by Scenario, Weight;

  select sum(Weight * ECL_12m), sum(Weight * ECL_Lifetime)
    into :w12 trimmed, :wlt trimmed
  from cr.ecl_by_scenario;
quit;

%put NOTE: Probability-weighted ECL  12m = &w12  lifetime = &wlt;

/*--- 6. Stage-based reported ECL ---------------------------------------*/
data cr.ifrs9_result;
  set cr.prestige_final(keep=Borrower Project_Name IFRS9_Stage EAD LGD PD_Applied ECL);
  Wtd_ECL_12m      = &w12;
  Wtd_ECL_Lifetime = &wlt;
  select (IFRS9_Stage);
    when (1)  IFRS9_ECL_Cr = Wtd_ECL_12m;
    when (2)  IFRS9_ECL_Cr = Wtd_ECL_Lifetime;
    otherwise IFRS9_ECL_Cr = LGD * EAD;
  end;
  Simple_ECL_Cr = ECL;                         /* PD x LGD x EAD from step 14 */
  Difference_Cr = IFRS9_ECL_Cr - Simple_ECL_Cr;
  label IFRS9_ECL_Cr = 'Scenario-weighted IFRS 9 ECL (Rs Cr)'
        Simple_ECL_Cr = 'Simple ECL, step 14 (Rs Cr)'
        Difference_Cr = 'Difference (Rs Cr)';
  format Wtd_ECL_12m Wtd_ECL_Lifetime IFRS9_ECL_Cr Simple_ECL_Cr Difference_Cr comma12.2
         IFRS9_Stage stagef.;
  drop ECL;
run;

title "IFRS 9 - REPAYMENT SCHEDULE AND PD CURVE";
proc print data=cr.amort_schedule noobs;
run;

title "CONSISTENCY CHECK - INPUT VS SCHEDULE DEBT SERVICE";
proc print data=cr.peak_dscr_check noobs label;
run;

title "IFRS 9 - ECL BY SCENARIO (Rs Crore)";
proc print data=cr.ecl_by_scenario noobs;
  format ECL_12m ECL_Lifetime comma12.2;
run;

title "IFRS 9 - REPORTED ECL VS SIMPLE ECL";
proc print data=cr.ifrs9_result noobs label;
run;
title;
