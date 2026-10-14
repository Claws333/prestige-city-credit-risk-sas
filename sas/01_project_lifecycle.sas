/*======================================================================
  01_project_lifecycle.sas
  PRESTIGE CITY BENGALURU - Rs 7,000 Cr infrastructure credit lifecycle
  ----------------------------------------------------------------------
  The original 17-step case study, rebuilt as ONE reusable macro that
  works on any number of projects (1 row = 1 project).

  SAS concepts : DATA step logic, ARRAYs, DO loops, SELECT/WHEN,
                 IF/ELSE, HASH object lookup, WHICHC, COALESCE, CATX,
                 IFC, labels, formats, macro parameters, %LOCAL,
                 %SYSFUNC / %SYSEVALF, PROC DATASETS, PROC PRINT /
                 MEANS / FREQ
======================================================================*/

/*---------------------------------------------------------------------
  PART A - Prestige input table (the "contract" every project follows)
---------------------------------------------------------------------*/
data cr.prestige_input;
  &INPUT_LENGTHS
  Borrower     = "Prestige Group";
  Project_Name = "Prestige City Bengaluru";
  Sector       = "Real Estate";

  /* Step 1 - origination */
  Project_Cost_Cr  = 10000;
  Debt_Cr          = 7000;
  Equity_Cr        = 3000;
  Project_IRR      = 18;       /* % */
  Industry_Risk    = 2;        /* 1=Low 2=Medium 3=High */
  Management_Score = 9;        /* 1-10 */

  /* Step 2 - due diligence */
  Land_Approval = "Y";  Legal_Clearance = "Y";
  Environmental_Clearance = "Y";  RERA_Approval = "Y";

  /* Steps 3-4 - feasibility and financial model */
  Expected_Units         = 10000;
  Expected_Price_Lakh    = 150;
  Annual_CashFlow_Cr     = 1500;
  Annual_Debt_Service_Cr = 1000;
  PV_Future_CashFlows_Cr = 12000;  /* PV of cash flow over LOAN life    */
  PV_Project_Life_Cr     = 14000;  /* PV over PROJECT life (assumption) */
  Revenue_Forecast       = 1800;

  /* Step 9 - structuring */
  Loan_Tenor_Yrs = 15;  Moratorium_Yrs = 3;
  Interest_Rate  = 10;  Security_Cover = 1.50;

  /* Step 10 - consortium (Rs Cr) */
  Lead_Bank = "SBI";   Lead_Bank_Share = 3000;
  Bank2     = "ICICI"; Bank2_Share     = 2000;
  Bank3     = "HDFC";  Bank3_Share     = 2000;

  /* Steps 11-12 - disbursement and monitoring */
  Milestones_Achieved       = 5;      /* 0-5 construction milestones met */
  Actual_Project_Cost       = 11500;
  Construction_Delay_Months = 8;

  /* Steps 15-17 - portfolio status */
  Days_Past_Due       = 0;
  Principal_Collected = 300;
  Interest_Collected  = 700;
  Default_Flag        = "N";
run;

/*---------------------------------------------------------------------
  PART B - The lifecycle engine
  Usage: %run_lifecycle(inds=<input>, outds=<output>, force_default=Y|N)
---------------------------------------------------------------------*/
%macro run_lifecycle(inds=, outds=, force_default=);
  %local t0;
  %let t0 = %sysfunc(datetime());

  /*=== STEP 1 : DEAL ORIGINATION ===================================
    Validate the funding structure: Debt + Equity must equal cost.   */
  data work.stg01_origination;
    length Default_Flag $1 Funding_Gap_Flag $1;
    set &inds;
    %if %length(&force_default) > 0 %then %do;
      Default_Flag = "&force_default";   /* stress-test override */
    %end;
    if Equity_Cr > 0 then DE_Ratio = Debt_Cr / Equity_Cr;
    if abs(Debt_Cr + Equity_Cr - Project_Cost_Cr) > 0.01 then Funding_Gap_Flag = 'Y';
    else Funding_Gap_Flag = 'N';
  run;

  /*=== STEP 2 : DUE DILIGENCE (ARRAY + DO loop) ====================
    Any single "N" fails the project.                                 */
  data work.stg02_diligence;
    set work.stg01_origination;
    length Due_Diligence_Flag $4;
    array chk{4} $ Land_Approval Legal_Clearance Environmental_Clearance RERA_Approval;
    Failed_Checks = 0;
    do i = 1 to dim(chk);
      if upcase(chk{i}) = 'N' then Failed_Checks = Failed_Checks + 1;
    end;
    if Failed_Checks > 0 then Due_Diligence_Flag = 'FAIL';
    else Due_Diligence_Flag = 'PASS';
    drop i;
  run;

  /*=== STEP 3 : FEASIBILITY ASSESSMENT =============================*/
  data work.stg03_feasibility;
    set work.stg02_diligence;
    Debt_to_Cost        = Debt_Cr / Project_Cost_Cr;
    Equity_Ratio        = Equity_Cr / Project_Cost_Cr;
    /* units x price in lakh / 100 = Rs Crore (1 Cr = 100 lakh) */
    Expected_Revenue_Cr = (Expected_Units * Expected_Price_Lakh) / 100;
    Revenue_to_Cost     = Expected_Revenue_Cr / Project_Cost_Cr;
  run;

  /*=== STEP 4 : FINANCIAL MODELLING ================================*/
  data work.stg04_financials;
    set work.stg03_feasibility;
    Operating_Cost    = Revenue_Forecast * &OPEX_RATIO;
    EBITDA            = Revenue_Forecast - Operating_Cost;
    if Revenue_Forecast > 0 then EBITDA_Margin_Pct = 100 * EBITDA / Revenue_Forecast;
  run;

  /*=== STEP 5 : CREDIT RISK METRICS ================================
    PLCR now uses PV over the full PROJECT life (the original file
    used the same numerator as LLCR, so the two ratios were identical). */
  data work.stg05_metrics;
    set work.stg04_financials;
    if Annual_Debt_Service_Cr > 0 then DSCR = Annual_CashFlow_Cr / Annual_Debt_Service_Cr;
    if Debt_Cr > 0 then do;
      LLCR = PV_Future_CashFlows_Cr / Debt_Cr;
      PLCR = PV_Project_Life_Cr     / Debt_Cr;
    end;
    LTV = Debt_Cr / Project_Cost_Cr;
  run;

  /*=== STEP 6 : INTERNAL CREDIT RATING =============================*/
  data work.stg06_rating;
    set work.stg05_metrics;
    length Rating $5;
    if DSCR >= &DSCR_AA and LLCR >= &LLCR_AA and Project_IRR >= &IRR_AA
       and Management_Score >= &MGMT_AA then Rating = 'AA';
    else if DSCR >= &DSCR_A and LLCR >= &LLCR_A then Rating = 'A';
    else if DSCR >= &DSCR_BBB then Rating = 'BBB';
    else Rating = 'BB';
    Rating_Rank = whichc(Rating, 'AA', 'A', 'BBB', 'BB');   /* 1 = best */
  run;

  /*=== STEP 7 : PROBABILITY OF DEFAULT =============================
    PD          : SELECT/WHEN (as in the original project)
    PD_12m      : HASH lookup into the master rating scale (cr.rating_master)
    PD_Lifetime : compounded from PD_12m over the loan tenor, so the 12-month
                  and lifetime numbers always tell the same story.            */
  data work.stg07_pd;
    length PD_12m 8;
    if _n_ = 1 then do;
      declare hash hrt(dataset: "cr.rating_master");
      hrt.defineKey('Rating');
      hrt.defineData('PD_12m');
      hrt.defineDone();
      call missing(PD_12m);
    end;
    set work.stg06_rating;
    rc = hrt.find();
    if rc ne 0 then PD_12m = 0.12;          /* unknown grade: treat as weakest */
    PD_Lifetime = 1 - (1 - PD_12m) ** coalesce(Loan_Tenor_Yrs, 15);
    select (Rating);
      when ('AA')  PD = 0.01;
      when ('A')   PD = 0.02;
      when ('BBB') PD = 0.05;
      otherwise    PD = 0.12;
    end;
    drop rc;
  run;

  /*=== STEP 8 : CREDIT APPROVAL (delegated-authority matrix) =======*/
  data work.stg08_approval;
    set work.stg07_pd;
    length Approval_Level $40;
    select;
      when (Debt_Cr >= 5000) Approval_Level = 'Board Credit Committee';
      when (Debt_Cr >= 1000) Approval_Level = 'Central Credit Committee';
      when (Debt_Cr >= 250)  Approval_Level = 'Zonal Credit Committee';
      otherwise              Approval_Level = 'Credit Manager';
    end;
  run;

  /*=== STEP 9 : LOAN STRUCTURING ===================================*/
  data work.stg09_structure;
    set work.stg08_approval;
    Loan_Amount_Cr = Debt_Cr;
    Loan_Tenor_Yrs = coalesce(Loan_Tenor_Yrs, 15);
    Moratorium_Yrs = coalesce(Moratorium_Yrs, 3);
    Interest_Rate  = coalesce(Interest_Rate, 10);
    Security_Cover = coalesce(Security_Cover, 1.50);
    Collateral_Required_Cr = Loan_Amount_Cr * Security_Cover;
    Repayment_Yrs = Loan_Tenor_Yrs - Moratorium_Yrs;
    if Repayment_Yrs > 0 then Annual_Principal_Cr = Loan_Amount_Cr / Repayment_Yrs;
  run;

  /*=== STEP 10 : CONSORTIUM FORMATION (ARRAY + HHI) ================*/
  data work.stg10_consortium;
    set work.stg09_structure;
    length Hold_Check $8;
    array sh{3} Lead_Bank_Share Bank2_Share Bank3_Share;
    Consortium_Total_Cr = sum(of sh{*});
    Consortium_Gap_Cr   = Loan_Amount_Cr - Consortium_Total_Cr;
    Largest_Share_Pct   = 100 * max(of sh{*}) / Loan_Amount_Cr;
    HHI_Consortium = 0;                       /* concentration of the club */
    do i = 1 to dim(sh);
      HHI_Consortium = HHI_Consortium + (sh{i} / Loan_Amount_Cr) ** 2;
    end;
    if abs(Consortium_Gap_Cr) < 0.01 then Hold_Check = 'OK';
    else Hold_Check = 'MISMATCH';
    drop i;
  run;

  /*=== STEP 11 : MILESTONE-BASED DISBURSEMENT ======================
    Milestone split (10/15/30/30/15 %) - original used 500/1000/2000/
    2500/1000 Cr, which is the same idea with different weights.      */
  data work.stg11_disbursement;
    set work.stg10_consortium;
    array mp{5} _temporary_ (0.10 0.15 0.30 0.30 0.15);
    array md{5} Land_Stage_Disbursed Foundation_Disbursed
                Mid_Construction_Disbursed Completion_Disbursed Final_Disbursed;
    do i = 1 to 5;
      if i <= coalesce(Milestones_Achieved, 0) then md{i} = round(Loan_Amount_Cr * mp{i}, 0.01);
      else md{i} = 0;
    end;
    Total_Disbursed_Cr = sum(of md{*});
    Undisbursed_Cr     = Loan_Amount_Cr - Total_Disbursed_Cr;
    Disbursed_Pct      = 100 * Total_Disbursed_Cr / Loan_Amount_Cr;
    drop i;
  run;

  /*=== STEP 12 : CONSTRUCTION MONITORING ===========================*/
  data work.stg12_monitoring;
    set work.stg11_disbursement;
    Original_Project_Cost = Project_Cost_Cr;
    Cost_Overrun_Cr  = Actual_Project_Cost - Original_Project_Cost;
    Cost_Overrun_Pct = 100 * Cost_Overrun_Cr / Original_Project_Cost;
  run;

  /*=== STEP 13 : EARLY WARNING SYSTEM ==============================
    Triggers counted individually and explained in plain English.     */
  data work.stg13_ews;
    set work.stg12_monitoring;
    length EWS_Flag $3 EWS_Reasons $120;
    EWS_Count   = 0;
    EWS_Reasons = '';
    if DSCR < &EWS_DSCR then do;
      EWS_Count = EWS_Count + 1;
      EWS_Reasons = catx('; ', EWS_Reasons, 'DSCR below threshold');
    end;
    if Cost_Overrun_Pct > &EWS_OVERRUN then do;
      EWS_Count = EWS_Count + 1;
      EWS_Reasons = catx('; ', EWS_Reasons, 'Cost overrun above limit');
    end;
    if Construction_Delay_Months > &EWS_DELAY then do;
      EWS_Count = EWS_Count + 1;
      EWS_Reasons = catx('; ', EWS_Reasons, 'Construction delay');
    end;
    if Days_Past_Due > 30 then do;
      EWS_Count = EWS_Count + 1;
      EWS_Reasons = catx('; ', EWS_Reasons, 'Days past due above 30');
    end;
    if EWS_Count > 0 then EWS_Flag = 'YES';
    else EWS_Flag = 'NO';
  run;

  /*=== STEP 14 : IFRS 9 ECL = PD x LGD x EAD (with staging) ========*/
  data work.stg14_ecl;
    set work.stg13_ews;
    if      Industry_Risk = 1 then LGD = 0.25;
    else if Industry_Risk = 2 then LGD = 0.35;
    else                           LGD = 0.45;

    /* Stage allocation (EWS / DPD used as the SICR proxy) */
    if Default_Flag = 'Y' or Days_Past_Due > 90 then IFRS9_Stage = 3;
    else if EWS_Flag = 'YES' or Days_Past_Due > 30 then IFRS9_Stage = 2;
    else IFRS9_Stage = 1;

    /* EAD = drawn amount + CCF x undrawn commitment */
    EAD = Total_Disbursed_Cr + &CCF * Undisbursed_Cr;

    select (IFRS9_Stage);
      when (1)  PD_Applied = PD;            /* 12-month PD */
      when (2)  PD_Applied = PD_Lifetime;   /* lifetime PD */
      otherwise PD_Applied = 1;             /* defaulted   */
    end;
    ECL = PD_Applied * LGD * EAD;
    if EAD > 0 then ECL_Coverage_Pct = 100 * ECL / EAD;
  run;

  /*=== STEP 15 : PORTFOLIO MONITORING ==============================
    Outstanding is now disbursed less principal collected (the original
    kept it at the full 7,000 even after 300 of principal was repaid).*/
  data work.stg15_portfolio;
    set work.stg14_ecl;
    Outstanding_Balance = Total_Disbursed_Cr - coalesce(Principal_Collected, 0);
    Interest_Due_Cr     = Total_Disbursed_Cr * Interest_Rate / 100;
    if Interest_Due_Cr > 0 then
      Collection_Efficiency_Pct = 100 * coalesce(Interest_Collected, 0) / Interest_Due_Cr;
  run;

  /*=== STEP 16 : RESTRUCTURING =====================================*/
  data work.stg16_restructuring;
    set work.stg15_portfolio;
    length Action $20;
    Action = 'NORMAL';
    New_Tenor_Yrs      = Loan_Tenor_Yrs;
    New_Moratorium_Yrs = Moratorium_Yrs;
    if EWS_Flag = 'YES' then do;
      Action = 'RESTRUCTURE';
      New_Tenor_Yrs      = max(Loan_Tenor_Yrs, 20);
      New_Moratorium_Yrs = max(Moratorium_Yrs, 5);
    end;
    if IFRS9_Stage = 3 then Action = 'RECOVERY';
  run;

  /*=== STEP 17 : DEFAULT AND RECOVERY ==============================
    Economic loss discounts the recovery back to today.               */
  data work.stg17_recovery;
    set work.stg16_restructuring;
    if Default_Flag = 'Y' then do;
      Recovery_Rate      = 1 - LGD;
      Recovery_Amount_Cr = Outstanding_Balance * Recovery_Rate;
      Loss_Amount_Cr     = Outstanding_Balance - Recovery_Amount_Cr;
      PV_Recovery_Cr     = Recovery_Amount_Cr / ((1 + &EIR) ** &RECOVERY_YEARS);
      Economic_Loss_Cr   = Outstanding_Balance - PV_Recovery_Cr;
    end;
  run;

  /*=== FINAL CREDIT DECISION =======================================*/
  data &outds;
    set work.stg17_recovery;
    length Credit_Decision $15 Decision_Reason $60;
    if Due_Diligence_Flag = 'FAIL' then do;
      Credit_Decision = 'REJECT';
      Decision_Reason = 'Due diligence failed';
    end;
    else if Default_Flag = 'Y' then do;
      Credit_Decision = 'RECOVERY';
      Decision_Reason = 'Borrower in default';
    end;
    else if Rating in ('AA', 'A') and EWS_Flag = 'NO' then do;
      Credit_Decision = 'APPROVE';
      Decision_Reason = 'Strong rating and no early-warning triggers';
    end;
    else if EWS_Flag = 'YES' then do;
      Credit_Decision = 'REVIEW';
      Decision_Reason = EWS_Reasons;
    end;
    else do;
      Credit_Decision = 'REJECT';
      Decision_Reason = 'Rating below approval threshold';
    end;

    label DSCR = 'Debt Service Coverage Ratio'
          LLCR = 'Loan Life Coverage Ratio'
          PLCR = 'Project Life Coverage Ratio'
          LTV  = 'Loan to Value'
          PD   = '12-month PD (select/when)'
          LGD  = 'Loss Given Default'
          EAD  = 'Exposure at Default (Rs Cr)'
          ECL  = 'Expected Credit Loss (Rs Cr)'
          IFRS9_Stage = 'IFRS 9 Stage';
    format PD LGD PD_12m PD_Lifetime PD_Applied pdpct.
           DSCR LLCR PLCR LTV 6.2
           ECL EAD comma12.2
           IFRS9_Stage stagef. Industry_Risk riskf.;
  run;

  /* Housekeeping: drop the 17 work tables (wildcard delete) */
  proc datasets lib=work nolist;
    delete stg: ;
  quit;

  %put NOTE: run_lifecycle finished in %sysfunc(round(%sysevalf(%sysfunc(datetime()) - &t0), 0.01)) seconds -> &outds;
%mend run_lifecycle;

/*---------------------------------------------------------------------
  PART C - Run the Prestige case and print the management summary
---------------------------------------------------------------------*/
%run_lifecycle(inds=cr.prestige_input, outds=cr.prestige_final);

title "PRESTIGE CITY BENGALURU - CREDIT APPROVAL SUMMARY";
proc print data=cr.prestige_final noobs label;
  var Borrower Project_Name Project_Cost_Cr Debt_Cr Equity_Cr DSCR LLCR PLCR
      Project_IRR Rating PD LGD ECL Approval_Level EWS_Flag Credit_Decision;
run;

title "KEY RISK METRICS";
proc means data=cr.prestige_final n mean min max maxdec=3;
  var Debt_Cr DSCR LLCR PLCR PD LGD ECL;
run;

title "FINAL CREDIT DECISION";
proc freq data=cr.prestige_final;
  tables Credit_Decision Rating IFRS9_Stage / nocum;
run;

title "PORTFOLIO SUMMARY";
proc print data=cr.prestige_final noobs;
  var Outstanding_Balance Interest_Collected Principal_Collected
      Collection_Efficiency_Pct Action;
run;
title;
