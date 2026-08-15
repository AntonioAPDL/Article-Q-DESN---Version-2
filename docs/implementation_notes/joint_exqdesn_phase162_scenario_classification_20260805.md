# Phase162 eight-scenario exAL classification

Phase162 is a no-new-sampling audit of the eight article-facing Joint exQDESN cases. It verifies the Phase150 exAL, Phase154 AL, and Phase161 decision manifests; compares fit and forecast oracle-path errors, check loss, and grid CRPS; and decomposes forecast error by quantile level.

Diagnostic evidence is graded. Phase150 retains compact chain summaries for all eight cases but no posterior draws. Phase160 retains draw-level modern diagnostics for nonlinear-reservoir and Student-t cases. The audit therefore does not label the other six cases sampler-limited without direct evidence.

The classification closes directions already explored without article gains: global specifications, another split-RHS screen, longer chains as a substitute for specification work, repeated slice-width-only screening, and fixed-gamma sensitivity as an article model. Future computation must be scenario-specific and must beat the current article row before MCMC promotion.

Run:

```bash
Rscript application/scripts/209_audit_joint_exqdesn_phase162_scenario_classification.R
```
