/*======================================================================
  00_setup.sas  -  Environment, parameters, formats and reference data
  ----------------------------------------------------------------------
  SAS concepts : OPTIONS, LIBNAME, global macro variables, %MACRO,
                 %SYSFUNC, DCREATE / FILEEXIST, PROC FORMAT (VALUE,
                 PICTURE, CNTLIN), DATALINES, lookup (reference) tables
  Prerequisite : &ROOT must be defined first (see main.sas)
======================================================================*/

/*--- 1. Session options ------------------------------------------------*/
options nodate nonumber validvarname=v7 msglevel=i ls=132 ps=60;

%global DEBUG LOG_TO_FILE QC_FAILS QC_N;

%macro init_defaults;
  %if %length(&DEBUG)       = 0 %then %let DEBUG = 0;
  %if %length(&LOG_TO_FILE) = 0 %then %let LOG_TO_FILE = 0;
%mend init_defaults;
%init_defaults

%let QC_FAILS = 0;
%let QC_N     = 0;

%macro set_debug;
  %if &DEBUG = 1 %then %do;
    options mprint mlogic symbolgen;
  %end;
  %else %do;
    options nomprint nomlogic nosymbolgen;
  %end;
%mend set_debug;
%set_debug

/*--- 2. Folders and libraries -----------------------------------------*/
%macro ensure_dir(parent=, name=);
  %if not %sysfunc(fileexist(&parent./&name)) %then %do;
    %let _rc = %sysfunc(dcreate(&name, &parent));
    %put NOTE: Created folder &parent./&name;
  %end;
%mend ensure_dir;

%ensure_dir(parent=&ROOT, name=data)
%ensure_dir(parent=&ROOT, name=output)
%ensure_dir(parent=&ROOT, name=logs)

libname cr "&ROOT./data";

/*--- 3. Run stamps (used in file names and titles) --------------------*/
%let RUN_TAG      = %sysfunc(today(), yymmddn8.);
%let RUN_DATE_FMT = %sysfunc(today(), date9.);

%macro log_start(name=run);
  %if &LOG_TO_FILE = 1 %then %do;
    proc printto log="&ROOT./logs/&name._&RUN_TAG..log" new;
    run;
  %end;
%mend log_start;

%macro log_stop;
  %if &LOG_TO_FILE = 1 %then %do;
    proc printto;
    run;
  %end;
%mend log_stop;

/*--- 4. Business parameters: change them HERE, never inside the logic --*/
/* Rating grid */
%let DSCR_AA  = 1.50;  %let LLCR_AA = 1.70;  %let IRR_AA  = 17;  %let MGMT_AA = 8;
%let DSCR_A   = 1.30;  %let LLCR_A  = 1.50;
%let DSCR_BBB = 1.20;

/* Early-warning triggers */
%let EWS_DSCR    = 1.20;   /* DSCR below this            */
%let EWS_OVERRUN = 20;     /* cost overrun % above this  */
%let EWS_DELAY   = 12;     /* delay in months above this */

/* Financial assumptions */
%let OPEX_RATIO     = 0.45;  /* operating cost as share of revenue       */
%let CCF            = 0.50;  /* credit conversion factor on undrawn debt */
%let EIR            = 0.10;  /* discount rate / effective interest rate  */
%let RECOVERY_YEARS = 3;     /* time to recover after default            */

/* Simulation settings */
%let N_BORROWERS   = 49;       /* synthetic borrowers (Prestige is the 50th) */
%let N_SIM         = 10000;    /* Monte Carlo paths                          */
%let SEED          = 20261014; /* reproducible random numbers                */
%let MC_CF_VOL     = 0.15;     /* cash-flow volatility for Monte Carlo       */
%let LOSS_DEF_DSCR = 1.00;     /* DSCR below this = default in simulation    */

/* DRY trick: the column lengths every project table must share.
   %STR masks the semicolons so the whole statement fits in one macro variable. */
%let INPUT_LENGTHS = %str(length Borrower $30 Project_Name $40 Sector $20
    Land_Approval Legal_Clearance Environmental_Clearance RERA_Approval Default_Flag $1
    Lead_Bank Bank2 Bank3 $20;);

/*--- 5. Formats --------------------------------------------------------*/
proc format;
  value riskf   1 = 'Low'  2 = 'Medium'  3 = 'High';
  value stagef  1 = 'Stage 1 - Performing'
                2 = 'Stage 2 - Under-performing'
                3 = 'Stage 3 - Credit-impaired';
  value dscrf   low-<1.00  = '< 1.00 Distressed'
                1.00-<1.20 = '1.00-1.19 Watch'
                1.20-<1.50 = '1.20-1.49 Adequate'
                1.50-high  = '>= 1.50 Strong';
  value $ratef  'AA' = 'AA - Strong'  'A' = 'A - Good'
                'BBB' = 'BBB - Adequate'  'BB' = 'BB - Weak'
                other = 'Unrated';
  picture pdpct    low-high = '009.99%' (mult=100);
  picture crorefmt low-high = '000,009.99' (prefix='Rs ');
run;

/*--- 6. Reference tables ----------------------------------------------*/
/* Master rating scale: 12-month PD per grade.
   Lifetime PD is derived per loan from its tenor (constant annual hazard). */
data cr.rating_master;
  length Rating $5;
  input Rating $ Rating_Rank PD_12m;
  label PD_12m = '12-month PD';
  datalines;
AA  1 0.01
A   2 0.02
BBB 3 0.05
BB  4 0.12
;
run;

/* Sector exposure limits (Rs Crore) */
data cr.sector_limits;
  length Sector $20;
  input Sector &$20. Limit_Cr;
  datalines;
Real Estate  40000
Roads  30000
Power  40000
Ports  25000
Renewables  30000
;
run;

/* Build a user-defined format FROM a table (PROC FORMAT + CNTLIN) */
data work.fmt_rating;
  length label $40;
  retain fmtname 'ratdesc' type 'C';
  set cr.rating_master;
  start = Rating;
  label = catx(' | ', Rating, cats('PD ', put(PD_12m, percent8.1)));
  keep fmtname type start label;
run;

proc format cntlin=work.fmt_rating;
run;

%put NOTE: 00_setup complete. Library CR -> &ROOT./data;
