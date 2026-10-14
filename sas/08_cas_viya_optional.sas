/*======================================================================
  08_cas_viya_optional.sas  -  OPTIONAL: run the portfolio analytics in CAS
  ----------------------------------------------------------------------
  Needs SAS Viya (CAS server). Skip this file on SAS 9.4 / OnDemand for
  Academics. Not part of main.sas - run it on its own after 03.

  SAS concepts : CAS session, CASLIB, PROC CASUTIL (load / save),
                 DATA step executed in CAS, PROC MEANS and PROC FEDSQL
                 on in-memory tables
======================================================================*/

cas mysess;                         /* start a CAS session            */
caslib _all_ assign;                /* make CASUSER etc. visible      */

/* 1. Load the scored portfolio into memory */
proc casutil;
  load data=cr.portfolio_scored outcaslib="casuser" casout="portfolio_scored" replace;
quit;

/* 2. DATA step running in CAS: add an exposure-weighted risk score */
data casuser.portfolio_flags;
  set casuser.portfolio_scored;
  Risk_Weighted_Exposure = Loan_Amount_Cr * PD_Applied * LGD;
  if EWS_Flag = 'YES' and Rating in ('BBB', 'BB') then Watchlist = 1;
  else Watchlist = 0;
run;

/* 3. Distributed summary statistics */
proc means data=casuser.portfolio_flags sum mean maxdec=2;
  class Sector;
  var Loan_Amount_Cr ECL Risk_Weighted_Exposure;
run;

/* 4. FedSQL (ANSI SQL for CAS) */
proc fedsql sessref=mysess;
  create table casuser.sector_cas {options replace=true} as
  select Sector,
         count(*)             as N_Loans,
         sum(Loan_Amount_Cr)  as Exposure_Cr,
         sum(ECL)             as ECL_Cr,
         sum(Watchlist)       as N_Watchlist
  from casuser.portfolio_flags
  group by Sector;
quit;

/* 5. Bring the small result back to the client and save it */
data cr.sector_cas;
  set casuser.sector_cas;
run;

proc casutil;
  save casdata="sector_cas" incaslib="casuser" casout="sector_cas.sashdat" outcaslib="casuser" replace;
quit;

cas mysess terminate;
