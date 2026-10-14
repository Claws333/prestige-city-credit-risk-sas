/*======================================================================
  main.sas  -  Run the whole Prestige City Bengaluru credit-risk project
  ----------------------------------------------------------------------
  1. Upload / clone this repo into your SAS environment
       e.g. SAS OnDemand for Academics:  /home/u12345678/prestige-city-credit-risk-sas
  2. Edit the ONE line below (ROOT)
  3. Open this file in SAS Studio / Enterprise Guide and click Run
======================================================================*/

%let ROOT = /home/YOUR_USER_ID/prestige-city-credit-risk-sas;   /* <-- EDIT ME */
%let DEBUG = 0;           /* 1 = show MPRINT / MLOGIC / SYMBOLGEN in the log   */
%let LOG_TO_FILE = 0;     /* 1 = write the log to &ROOT/logs instead of screen */

%include "&ROOT./sas/00_setup.sas";
%log_start(name=prestige_run)

%include "&ROOT./sas/01_project_lifecycle.sas";    /* the 17-step case study  */
%include "&ROOT./sas/02_ifrs9_ecl.sas";            /* lifetime ECL            */
%include "&ROOT./sas/03_portfolio_analytics.sas";  /* 50-loan portfolio       */
%include "&ROOT./sas/04_stress_testing.sas";       /* stress + Monte Carlo    */
%include "&ROOT./sas/05_pd_model.sas";             /* logistic PD model       */
%include "&ROOT./sas/06_validation_qc.sas";        /* automated checks        */
%include "&ROOT./sas/07_reporting.sas";            /* Excel + PDF report      */

%log_stop
%put NOTE: Project complete. Open &ROOT./output for the report.;
