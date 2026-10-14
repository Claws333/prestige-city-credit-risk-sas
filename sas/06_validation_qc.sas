/*======================================================================
  06_validation_qc.sas  -  Data quality, reconciliation and model checks
  ----------------------------------------------------------------------
  Every number a risk report shows must reconcile. This module runs a
  battery of automated checks, logs PASS/FAIL to cr.qc_log and can stop
  the batch if anything fails.

  SAS concepts : custom macro with %SYSEVALF(boolean), %EVAL counters,
                 PROC SQL INTO / INSERT, PROC CONTENTS, PROC MEANS NMISS,
                 PROC COMPARE + &SYSINFO bit-flags, %SYSFUNC(BAND),
                 %PUT NOTE / ERROR, %ABORT CANCEL
  Requires     : 01 - 04 (05 optional)
======================================================================*/

%macro assert(cond=, msg=);
  %let QC_N = %eval(&QC_N + 1);
  %local status;
  %if %sysevalf(&cond, boolean) %then %do;
    %let status = PASS;
    %put NOTE: [QC &QC_N] PASS - &msg;
  %end;
  %else %do;
    %let status = FAIL;
    %let QC_FAILS = %eval(&QC_FAILS + 1);
    %put ERROR: [QC &QC_N] FAIL - &msg;
  %end;
  proc sql noprint;
    insert into cr.qc_log
    values(&QC_N, "&msg", "&status", %sysfunc(datetime()));
  quit;
%mend assert;

%macro require_ds(ds=);
  %if not %sysfunc(exist(&ds)) %then %do;
    %put ERROR: Required dataset &ds does not exist. Run the earlier modules first.;
    %abort cancel;
  %end;
%mend require_ds;

%macro run_qc(abort_on_fail=0);
  %local n_rows n_exp v_disb v_cons v_fund v_miss v_pd v_ecl v_pdchk wdiff v_rate cmp_rc v_tot_loan v_tot_debt;

  %require_ds(ds=cr.portfolio_scored)
  %require_ds(ds=cr.ifrs9_scenarios)
  %require_ds(ds=cr.prestige_final)

  %let n_exp   = %eval(&N_BORROWERS + 1);
  %let QC_N    = 0;
  %let QC_FAILS = 0;

  proc sql;
    create table cr.qc_log
      (Check_No num, Check_Description char(100), Status char(4), Run_Time num format=datetime20.);
  quit;

  /*--- gather the numbers once ---*/
  proc sql noprint;
    select count(*) into :n_rows trimmed from cr.portfolio_scored;
    select count(*) into :v_disb trimmed from cr.portfolio_scored
      where Total_Disbursed_Cr > Loan_Amount_Cr + 0.01;
    select count(*) into :v_cons trimmed from cr.portfolio_scored where Hold_Check = 'MISMATCH';
    select count(*) into :v_fund trimmed from cr.portfolio_scored where Funding_Gap_Flag = 'Y';
    select count(*) into :v_miss trimmed from cr.portfolio_scored where missing(Rating);
    select count(*) into :v_pd   trimmed from cr.portfolio_scored where PD < 0 or PD > 1;
    select count(*) into :v_ecl  trimmed from cr.portfolio_scored where ECL < 0 or ECL > EAD + 0.000001;
    select count(*) into :v_pdchk trimmed from cr.portfolio_scored where abs(PD - PD_12m) > 0.000001;
    select round(abs(sum(Weight) - 1), 0.000001) into :wdiff trimmed from cr.ifrs9_scenarios;
    select sum(Loan_Amount_Cr), sum(Debt_Cr) into :v_tot_loan trimmed, :v_tot_debt trimmed
      from cr.portfolio_scored;
  quit;

  /*--- completeness and integrity ---*/
  %assert(cond=&n_rows = &n_exp,        msg=Portfolio has the expected number of loans)
  %assert(cond=&v_miss = 0,             msg=Every loan has a rating)
  %assert(cond=&v_fund = 0,             msg=Debt plus equity equals project cost for every loan)
  %assert(cond=&v_cons = 0,             msg=Consortium shares add up to the loan amount)
  %assert(cond=&v_disb = 0,             msg=Disbursed amount never exceeds the sanctioned loan)
  %assert(cond=&v_tot_loan = &v_tot_debt, msg=Total sanctioned loans reconcile to total debt)

  /*--- risk-parameter sanity ---*/
  %assert(cond=&v_pd = 0,               msg=All PDs are between 0 and 1)
  %assert(cond=&v_ecl = 0,              msg=ECL is non-negative and never exceeds EAD)
  %assert(cond=&v_pdchk = 0,            msg=SELECT-based PD equals master-scale PD from the hash lookup)
  %assert(cond=&wdiff = 0,              msg=IFRS 9 scenario weights sum to 100 percent)

  /*--- reproducibility: Prestige alone must equal Prestige inside the portfolio ---*/
  data work.p_from_port;
    set cr.portfolio_scored;
    where Borrower = "Prestige Group";
  run;

  proc compare base=cr.prestige_final compare=work.p_from_port criterion=0.000000001 noprint;
  run;
  %let cmp_rc = &sysinfo;
  %assert(cond=%sysfunc(band(&cmp_rc, 4096)) = 0, msg=Prestige results identical when run alone or in the portfolio)

  /*--- data profile for the log / report ---*/
  proc contents data=cr.portfolio_scored out=work.contents noprint;
  run;

  title "QC - MISSING VALUES IN KEY RISK FIELDS";
  proc means data=cr.portfolio_scored n nmiss min max maxdec=3;
    var DSCR LLCR PD LGD EAD ECL;
  run;

  title "QC - CHECK LOG";
  proc print data=cr.qc_log noobs;
  run;
  title;

  %put NOTE: QC finished. Checks run = &QC_N, failed = &QC_FAILS;
  %if &QC_FAILS > 0 and &abort_on_fail = 1 %then %do;
    %put ERROR: &QC_FAILS QC check(s) failed - stopping the batch.;
    %abort cancel;
  %end;
%mend run_qc;

%run_qc(abort_on_fail=0)
