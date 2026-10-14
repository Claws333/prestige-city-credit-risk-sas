/*======================================================================
  05_pd_model.sas  -  Statistical PD model (logistic regression)
  ----------------------------------------------------------------------
  Master-scale PDs (AA = 1%, A = 2% ...) are expert judgement. This module
  shows how a data-driven PD would be built, validated and compared.
  The development sample is SIMULATED - no real default history is used.

  SAS concepts : RAND (bernoulli), PROC SORT, PROC SURVEYSELECT (stratified
                 train / validation split), PROC LOGISTIC (CLASS, stepwise,
                 OUTMODEL, SCORE, OUTROC), ODS OUTPUT, PROC RANK,
                 PROC SQL, AUC / Gini / KS from a ROC table
  Requires     : 03_portfolio_analytics (scores the portfolio at the end)
======================================================================*/

/*--- 1. Simulated development sample -----------------------------------*/
data work.pd_dev;
  call streaminit(%eval(&SEED + 1));
  do id = 1 to 5000;
    DSCR             = max(0.6, rand('normal', 1.35, 0.30));
    LLCR             = max(0.8, rand('normal', 1.55, 0.30));
    Cost_Overrun_Pct = max(0, rand('normal', 12, 9));
    Delay_Months     = max(0, round(rand('normal', 6, 5)));
    Mgmt_Score       = min(10, max(1, round(rand('normal', 7, 1.5))));
    Industry_Risk    = 1 + floor(rand('uniform') * 3);

    logit = -3.4 - 3.2 * (DSCR - 1.35) - 1.6 * (LLCR - 1.55)
            + 0.045 * (Cost_Overrun_Pct - 12) + 0.05 * (Delay_Months - 6)
            - 0.15 * (Mgmt_Score - 7) + 0.35 * (Industry_Risk - 2);
    p = 1 / (1 + exp(-logit));
    Def_Flag = rand('bernoulli', p);
    output;
  end;
  drop logit p;
run;

/*--- 2. Stratified 70 / 30 split ---------------------------------------*/
proc sort data=work.pd_dev; by Def_Flag; run;

proc surveyselect data=work.pd_dev out=work.pd_split
                  samprate=0.70 seed=&SEED outall method=srs;
  strata Def_Flag;
run;

data work.pd_train work.pd_valid;
  set work.pd_split;
  if Selected then output work.pd_train;
  else output work.pd_valid;
run;

/*--- 3. Fit the model --------------------------------------------------*/
ods output ParameterEstimates=cr.pd_coefficients Association=work.assoc_train;

proc logistic data=work.pd_train descending outmodel=cr.pd_model_store;
  class Industry_Risk(param=ref ref='1');
  model Def_Flag = DSCR LLCR Cost_Overrun_Pct Delay_Months Mgmt_Score Industry_Risk
        / selection=stepwise slentry=0.10 slstay=0.05 lackfit;
run;

/*--- 4. Out-of-sample validation: AUC, Gini, KS ------------------------*/
proc logistic inmodel=cr.pd_model_store;
  score data=work.pd_valid out=work.pd_valid_scored outroc=work.valid_roc;
run;

proc sort data=work.valid_roc; by _1MSPEC_ _SENSIT_; run;

data cr.pd_validation_metrics;
  set work.valid_roc end=last;
  retain prev_x 0 prev_y 0 AUC 0 KS 0;
  AUC = AUC + (_1MSPEC_ - prev_x) * (_SENSIT_ + prev_y) / 2;   /* trapezoid rule */
  KS  = max(KS, _SENSIT_ - _1MSPEC_);
  prev_x = _1MSPEC_;
  prev_y = _SENSIT_;
  if last then do;
    AUC  = AUC + (1 - prev_x) * (1 + prev_y) / 2;              /* close curve at (1,1) */
    Gini = 2 * AUC - 1;
    output;
  end;
  keep AUC Gini KS;
  format AUC Gini KS 6.3;
run;

/*--- 5. Risk-decile table (does PD rank-order defaults?) ----------------*/
proc rank data=work.pd_valid_scored out=work.pd_ranked groups=10 descending;
  var P_1;
  ranks Decile;
run;

proc sql;
  create table cr.pd_decile_table as
  select Decile + 1                  as Risk_Decile,
         count(*)                    as N,
         sum(Def_Flag)               as N_Defaults,
         mean(Def_Flag)              as Obs_Default_Rate format=percent8.2,
         mean(P_1)                   as Avg_Predicted_PD format=percent8.2,
         min(P_1)                    as Min_PD           format=percent8.2,
         max(P_1)                    as Max_PD           format=percent8.2
  from work.pd_ranked
  group by Decile
  order by Decile;
quit;

/*--- 6. Score the real portfolio and compare with master-scale PD -------*/
data work.port_for_pd;
  set cr.portfolio_scored;
  Delay_Months = Construction_Delay_Months;
  Mgmt_Score   = Management_Score;
run;

proc logistic inmodel=cr.pd_model_store;
  score data=work.port_for_pd out=work.port_pd_scored;
run;

data cr.portfolio_pd_compare;
  set work.port_pd_scored;
  Model_PD        = P_1;
  Master_Scale_PD = PD;
  keep Borrower Sector Rating DSCR LLCR Model_PD Master_Scale_PD;
  format Model_PD Master_Scale_PD pdpct.;
run;

title "PD MODEL - OUT-OF-SAMPLE DISCRIMINATION";
proc print data=cr.pd_validation_metrics noobs; run;

title "PD MODEL - COEFFICIENTS";
proc print data=cr.pd_coefficients noobs; run;

title "PD MODEL - RISK DECILES (VALIDATION SAMPLE)";
proc print data=cr.pd_decile_table noobs; run;

title "MODEL PD VS MASTER-SCALE PD BY RATING";
proc means data=cr.portfolio_pd_compare mean min max maxdec=4;
  class Rating;
  var Model_PD Master_Scale_PD;
run;
title;
