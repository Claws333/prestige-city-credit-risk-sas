/*======================================================================
  07_reporting.sas  -  Management report (Excel + PDF) with charts
  ----------------------------------------------------------------------
  SAS concepts : ODS EXCEL / ODS PDF (several destinations at once),
                 ODS GRAPHICS, PROC REPORT with COMPUTE blocks and
                 CALL DEFINE (traffic-light cells), PROC TABULATE,
                 PROC FREQ cross-tabs, PROC SGPLOT (VBAR, SCATTER,
                 VLINE + secondary axis), macro variables in titles
  Requires     : 01 - 04 (05 optional)
======================================================================*/

ods graphics on / width=7in height=4in;
ods excel file="&ROOT./output/credit_risk_report_&RUN_TAG..xlsx"
          options(sheet_interval="proc" embedded_titles="yes" sheet_name="Prestige");
ods pdf   file="&ROOT./output/credit_risk_report_&RUN_TAG..pdf" style=journal;

title1 "Prestige City Bengaluru - Credit Risk Report (&RUN_DATE_FMT)";
footnote1 "Illustrative case study. All figures are hypothetical and for learning purposes only.";

/*--- 1. Credit approval summary with traffic-light decision -----------*/
ods excel options(sheet_name="Approval");
title2 "1. Credit approval summary";
proc report data=cr.prestige_final nowd;
  column Borrower Project_Name Loan_Amount_Cr DSCR LLCR PLCR Rating PD LGD ECL
         IFRS9_Stage Approval_Level EWS_Flag Credit_Decision;
  define Borrower        / display 'Borrower';
  define Project_Name    / display 'Project';
  define Loan_Amount_Cr  / display 'Loan (Rs Cr)' format=comma12.0;
  define DSCR            / display format=6.2;
  define LLCR            / display format=6.2;
  define PLCR            / display format=6.2;
  define Rating          / display;
  define PD              / display format=pdpct.;
  define LGD             / display format=pdpct.;
  define ECL             / display 'ECL (Rs Cr)' format=comma12.2;
  define IFRS9_Stage     / display 'Stage' format=stagef.;
  define Approval_Level  / display 'Approval authority';
  define EWS_Flag        / display 'EWS';
  define Credit_Decision / display 'Decision';
  compute Credit_Decision;
    if Credit_Decision = 'APPROVE' then call define(_col_, 'style', 'style=[background=cxC6EFCE]');
    else if Credit_Decision in ('REVIEW', 'RECOVERY') then call define(_col_, 'style', 'style=[background=cxFFEB9C]');
    else call define(_col_, 'style', 'style=[background=cxFFC7CE]');
  endcomp;
run;

/*--- 2. Stress test table ----------------------------------------------*/
ods excel options(sheet_name="Stress");
title2 "2. Stress tests";
proc report data=cr.stress_results nowd;
  column Scenario_Name DSCR LLCR Rating PD IFRS9_Stage ECL ECL_vs_Base_Pct EWS_Flag Credit_Decision;
  define Scenario_Name   / display 'Scenario';
  define DSCR            / display format=6.2;
  define LLCR            / display format=6.2;
  define PD              / display format=pdpct.;
  define IFRS9_Stage     / display 'Stage' format=stagef.;
  define ECL             / display 'ECL (Rs Cr)' format=comma12.2;
  define ECL_vs_Base_Pct / display 'ECL vs base (%)' format=8.1;
  define Credit_Decision / display 'Decision';
  compute Credit_Decision;
    if Credit_Decision = 'APPROVE' then call define(_col_, 'style', 'style=[background=cxC6EFCE]');
    else if Credit_Decision in ('REVIEW', 'RECOVERY') then call define(_col_, 'style', 'style=[background=cxFFEB9C]');
    else call define(_col_, 'style', 'style=[background=cxFFC7CE]');
  endcomp;
run;

/*--- 3. Portfolio views -------------------------------------------------*/
ods excel options(sheet_name="Portfolio");
title2 "3. Portfolio exposure (Rs Cr) by sector and rating";
proc tabulate data=cr.portfolio_scored format=comma12.0;
  class Sector Rating;
  var Loan_Amount_Cr;
  table Sector='' all='Total',
        (Rating='' all='All ratings') * Loan_Amount_Cr='' * sum=''
        / box='Sector';
run;

title2 "Rating versus credit decision";
proc freq data=cr.portfolio_scored;
  tables Rating * Credit_Decision / nopercent norow nocol;
run;

ods excel options(sheet_name="Limits");
title2 "4. Sector limit monitoring";
proc report data=cr.sector_limit_check nowd;
  column Sector N_Loans Exposure_Cr Limit_Cr Utilisation_Pct Limit_Status ECL_Cr N_EWS;
  define Sector          / display;
  define N_Loans         / display 'Loans';
  define Exposure_Cr     / display 'Exposure (Rs Cr)' format=comma14.0;
  define Limit_Cr        / display 'Limit (Rs Cr)'    format=comma14.0;
  define Utilisation_Pct / display 'Utilisation (%)'  format=6.1;
  define Limit_Status    / display 'Status';
  define ECL_Cr          / display 'ECL (Rs Cr)' format=comma12.2;
  define N_EWS           / display 'Loans on EWS';
  compute Limit_Status;
    if Limit_Status = 'BREACH' then call define(_col_, 'style', 'style=[background=cxFFC7CE]');
    else if Limit_Status = 'WARNING' then call define(_col_, 'style', 'style=[background=cxFFEB9C]');
    else call define(_col_, 'style', 'style=[background=cxC6EFCE]');
  endcomp;
run;

/*--- 4. Charts -----------------------------------------------------------*/
ods excel options(sheet_name="Charts");
title2 "5. Exposure by sector, split by rating";
proc sgplot data=cr.portfolio_scored;
  vbar Sector / response=Loan_Amount_Cr group=Rating groupdisplay=stack stat=sum;
  yaxis label='Exposure (Rs Cr)';
run;

title2 "6. DSCR versus LLCR (each dot is a loan)";
proc sgplot data=cr.portfolio_scored;
  scatter x=DSCR y=LLCR / group=Rating markerattrs=(symbol=circlefilled size=8);
  refline &EWS_DSCR / axis=x lineattrs=(pattern=dash) label='EWS DSCR';
  refline &LLCR_A   / axis=y lineattrs=(pattern=dash) label='A-grade LLCR';
  xaxis label='DSCR';
  yaxis label='LLCR';
run;

title2 "7. Prestige repayment profile and cumulative PD";
proc sgplot data=cr.amort_schedule;
  vbar Year / response=Closing_Bal;
  vline Year / response=Cum_PD y2axis markers;
  yaxis label='Closing balance (Rs Cr)';
  y2axis label='Cumulative PD';
run;

title2 "8. Monte Carlo: simulated DSCR (default below &LOSS_DEF_DSCR)";
proc sgplot data=cr.mc_sim;
  histogram DSCR_s;
  refline &LOSS_DEF_DSCR / axis=x lineattrs=(color=red thickness=2) label='Default threshold';
  xaxis label='Simulated DSCR';
run;

/*--- 5. Control totals ----------------------------------------------------*/
ods excel options(sheet_name="Controls");
title2 "9. Quality-control log";
proc print data=cr.qc_log noobs;
run;

ods excel close;
ods pdf close;
ods graphics off;
title;
footnote;

%put NOTE: Reports written to &ROOT./output;
