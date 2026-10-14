# SAS concepts covered, by file

| Area | Concept | Where |
|---|---|---|
| **Environment** | `OPTIONS`, `LIBNAME`, `%GLOBAL`, `%LET`, `%SYSFUNC(DCREATE/FILEEXIST)` | 00 |
| | Macro-variable "config file" for business thresholds | 00 |
| | `PROC FORMAT`: `VALUE`, `PICTURE`, `CNTLIN` (format built from a table) | 00 |
| | `DATALINES` lookup tables, `PROC PRINTTO` logging | 00 |
| **DATA step** | `ARRAY` (regular and `_TEMPORARY_`), `DO` loops, `DIM` | 01, 03 |
| | `IF/ELSE`, `SELECT/WHEN` (with and without expression) | 01 |
| | `HASH` object lookup | 01 |
| | `COALESCE`, `CATX`, `WHICHC`, `ROUND`, `MAX/MIN/SUM(OF array{*})` | 01 |
| | Sum statement (implicit `RETAIN`), `RETAIN`, `FIRST.` / `LAST.` | 03, 05 |
| | `SET` stacking, dataset lists (`stress_1-stress_N`), `END=`, data set options (`KEEP=`, `DROP=`, `WHERE=`) | 03, 04 |
| | `MERGE` with `IN=` flags | 03 |
| | `RAND` (uniform, normal, beta, bernoulli) + `CALL STREAMINIT` | 03, 04, 05 |
| | `CALL SYMPUTX`, `LABEL`, `FORMAT`, `LENGTH` | 01-05 |
| **Macro language** | Parameterised macros, `%LOCAL`, `%DO` loops, `&&var&i` | 01, 04, 06 |
| | `%IF/%THEN`, `%EVAL`, `%SYSEVALF`, `%SYSFUNC`, `%PUT NOTE/ERROR`, `%ABORT CANCEL` | 00, 06 |
| | `%STR` to store a statement in a macro variable | 00 |
| **PROC SQL** | `GROUP BY`, `CASE`, `CALCULATED`, cross join, `INTO :var`, `INTO :v1-:vN` | 02, 03, 04, 05, 06 |
| | `CREATE TABLE` with column definitions, `INSERT INTO ... VALUES` | 06 |
| **Base procedures** | `SORT`, `MEANS` (CLASS / NWAY / OUTPUT), `FREQ`, `TRANSPOSE`, `RANK` | 03, 05 |
| | `UNIVARIATE` (percentiles to an output table), `CONTENTS`, `DATASETS`, `COMPARE` | 01, 04, 06 |
| **Statistics** | `PROC SURVEYSELECT` stratified train/validation split | 05 |
| | `PROC LOGISTIC` (CLASS, stepwise, OUTMODEL, SCORE, OUTROC, lack-of-fit) | 05 |
| | AUC, Gini, KS from a ROC table; risk-decile table | 05 |
| | Monte Carlo simulation, VaR, economic capital | 04 |
| **Credit risk** | DSCR, LLCR, PLCR, LTV, internal rating, master scale PD | 01 |
| | IFRS 9 staging, 12-month vs lifetime ECL, CCF, discounting, scenario weighting | 01, 02 |
| | Early-warning system, restructuring, recovery, economic LGD | 01 |
| | Sector limits, single-name concentration, HHI | 03 |
| | Deterministic stress testing | 04 |
| **Quality** | Automated assertions, reconciliation, `PROC COMPARE` + `&SYSINFO` flags | 06 |
| **Reporting** | `ODS EXCEL`, `ODS PDF`, `ODS GRAPHICS` | 07 |
| | `PROC REPORT` with `COMPUTE` + `CALL DEFINE`, `PROC TABULATE` | 07 |
| | `PROC SGPLOT`: `VBAR`, `SCATTER`, `VLINE` + secondary axis, `HISTOGRAM` | 07, 04 |
| **Viya (optional)** | `CAS` session, `CASLIB`, `PROC CASUTIL`, DATA step in CAS, `PROC FEDSQL` | 08 |
