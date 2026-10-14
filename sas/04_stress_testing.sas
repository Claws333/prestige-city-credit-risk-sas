/*======================================================================
  04_stress_testing.sas  -  Deterministic stress tests + Monte Carlo
  ----------------------------------------------------------------------
  A) Scenario table drives a macro loop that re-runs the WHOLE lifecycle
     on shocked inputs (cash-flow down, cost overrun, delay, default).
  B) Monte Carlo: simulate cash-flow uncertainty and read off expected
     loss, 99% loss quantile and economic capital.

  SAS concepts : DATALINES with & modifier, PROC SQL INTO :var1-:varN,
                 %DO loops, indirect macro references (&&var&i),
                 SET with dataset lists, RAND (normal / beta),
                 PROC UNIVARIATE OUTPUT, PROC SGPLOT
  Requires     : 01_project_lifecycle
======================================================================*/

/*--- A. Deterministic stress scenarios --------------------------------*/
data cr.stress_scenarios;
  length Scenario_Name $30 Force_Default $1;
  input Scenario_ID CF_Shock Cost_Shock Delay_Add Force_Default $ Scenario_Name &$30.;
  datalines;
1 0.00 0.00 0  N  Base case
2 0.15 0.00 0  N  Cash flow down 15%
3 0.30 0.10 6  N  Severe downturn
4 0.00 0.30 14 N  Cost overrun and delay
5 0.40 0.25 12 Y  Default scenario
;
run;

%macro run_stress;
  %local i n_scen;

  proc sql noprint;
    select count(*) into :n_scen trimmed from cr.stress_scenarios;
    select strip(put(Scenario_ID, best12.)),
           strip(put(CF_Shock,    best12.)),
           strip(put(Cost_Shock,  best12.)),
           strip(put(Delay_Add,   best12.)),
           strip(Force_Default),
           strip(Scenario_Name)
      into :id1-:id&n_scen,
           :cf1-:cf&n_scen,
           :cost1-:cost&n_scen,
           :dly1-:dly&n_scen,
           :fd1-:fd&n_scen,
           :nm1-:nm&n_scen
    from cr.stress_scenarios
    order by Scenario_ID;
  quit;

  %do i = 1 %to &n_scen;
    /* apply this scenario's shocks to the Prestige inputs */
    data work.shocked;
      set cr.prestige_input;
      Annual_CashFlow_Cr        = Annual_CashFlow_Cr * (1 - &&cf&i);
      PV_Future_CashFlows_Cr    = PV_Future_CashFlows_Cr * (1 - &&cf&i);
      PV_Project_Life_Cr        = PV_Project_Life_Cr * (1 - &&cf&i);
      Actual_Project_Cost       = Actual_Project_Cost * (1 + &&cost&i);
      Construction_Delay_Months = Construction_Delay_Months + &&dly&i;
    run;

    %run_lifecycle(inds=work.shocked, outds=work.stress_&i, force_default=&&fd&i)

    data work.stress_&i;
      length Scenario_ID 8 Scenario_Name $30;
      Scenario_ID   = &&id&i;
      Scenario_Name = "&&nm&i";
      set work.stress_&i;
    run;
  %end;

  /* stack all scenarios: dataset list stress_1 - stress_N */
  data cr.stress_results;
    set work.stress_1-work.stress_&n_scen;
    retain Base_ECL;
    if Scenario_ID = 1 then Base_ECL = ECL;
    if Base_ECL > 0 then ECL_vs_Base_Pct = 100 * (ECL / Base_ECL - 1);
    drop Base_ECL;
  run;
%mend run_stress;

%run_stress

title "STRESS TEST RESULTS - PRESTIGE CITY BENGALURU";
proc print data=cr.stress_results noobs;
  var Scenario_Name DSCR LLCR Rating PD IFRS9_Stage ECL ECL_vs_Base_Pct
      EWS_Flag Credit_Decision;
  format ECL_vs_Base_Pct 8.1;
run;

/*--- B. Monte Carlo on cash-flow uncertainty ---------------------------*/
data _null_;
  set cr.prestige_final;
  call symputx('mc_cf',  Annual_CashFlow_Cr);
  call symputx('mc_ds',  Annual_Debt_Service_Cr);
  call symputx('mc_lgd', LGD);
  call symputx('mc_ead', EAD);
run;

data cr.mc_sim;
  call streaminit(&SEED);
  do sim = 1 to &N_SIM;
    cf     = rand('normal', &mc_cf, &mc_cf * &MC_CF_VOL);
    lgd_s  = rand('beta', 6 * &mc_lgd, 6 * (1 - &mc_lgd));   /* mean = base LGD */
    DSCR_s = cf / &mc_ds;
    Def_Flag = (DSCR_s < &LOSS_DEF_DSCR);
    Loss_Cr  = Def_Flag * lgd_s * &mc_ead;
    output;
  end;
  keep sim DSCR_s Def_Flag Loss_Cr;
run;

proc univariate data=cr.mc_sim noprint;
  var Loss_Cr;
  output out=cr.mc_summary mean=Expected_Loss std=Loss_Std
         pctlpts=95 99 pctlpre=P_;
run;

proc sql noprint;
  select mean(Def_Flag) into :sim_pd trimmed from cr.mc_sim;
quit;

data cr.mc_summary;
  set cr.mc_summary;
  Simulated_PD     = &sim_pd;
  Economic_Capital = P_99 - Expected_Loss;     /* unexpected loss at 99% */
  label Expected_Loss = 'Expected loss (Rs Cr)'
        P_95 = '95th percentile loss' P_99 = '99th percentile loss (VaR)'
        Economic_Capital = 'Unexpected loss at 99% (Rs Cr)'
        Simulated_PD = 'Simulated PD';
  format Expected_Loss Loss_Std P_95 P_99 Economic_Capital comma12.2 Simulated_PD percent8.2;
run;

title "MONTE CARLO LOSS DISTRIBUTION (&N_SIM paths)";
proc print data=cr.mc_summary noobs label;
run;

title "SIMULATED DSCR DISTRIBUTION";
proc sgplot data=cr.mc_sim;
  histogram DSCR_s;
  density DSCR_s / type=normal;
  refline &LOSS_DEF_DSCR / axis=x lineattrs=(color=red thickness=2) label='Default threshold';
  xaxis label='Simulated DSCR';
run;
title;
