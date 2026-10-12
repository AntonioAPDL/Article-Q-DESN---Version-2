# PriceFM R135: target-preserving completion of R134

## Purpose

R134 completed its comprehensive, training-only pure-QDESN Ridge and Normal-RHS
screening, then stopped safely during the seven-quantile confirmation stage. This
successor does not repeat screening and does not change a statistical model. It
independently certifies the 14 finite median AL fits that reached the public-CRAN
iteration cap, resumes only the 98 withheld internal tasks, freezes one winner per
region using the three internal training-window splits, and evaluates those frozen
winners on the official three-fold cohort.

R135 is evidence-generating work on a dedicated task branch. It cannot promote a
model, mutate the article or registry, authorize MCMC/joint/exAL work, or expand to
all regions.

## Frozen diagnosis

- Parent campaign: `pricefm_stage_r134_pure_qdesn_optimization_20261011`.
- Parent source: `5f8510c73236907aaf32ea3dd725e72bf24620b0`.
- Completed parent tasks: 3,112 of 3,387.
- Ridge: 1,923 complete; Normal RHS: 1,125 complete.
- Quantile stage: 64 of 162 tasks complete, with 98 descendants withheld.
- Median AL fits: 18 executed, four formally converged and 14 finite but capped at
  1,000 iterations.
- Official tasks: not materialized and official test values were not used for
  selection.

The capped fits had flat ELBO and likelihood-scale traces but their absolute state
change remained slightly above `1e-5`. A bounded pre-implementation probe applied
the corrected R129b same-state certificate to all 14 fits. All 14 passed every
beta, covariance, predictor, sigma, RHS, initialization-invariance, and ELBO gate.
No model was refitted by that probe.

## Scientific contract

1. The original `formal_converged=false` value is retained permanently.
2. Certification is recorded separately as
   `independent_same_state_AL_RHS_NS_block_stationarity_not_original_formal_flag`.
3. The fixed zero-centered RHS prior, `tau0`, AL likelihood, sigma prior, DESN
   design, training rows, and posterior target hash are unchanged.
4. Upstream Normal-RHS or adjacent-quantile values remain initialization only.
5. The exact public CRAN `exdqlm` 1.1.1 API remains the production fitter.
6. Any new AL fit that reaches the same iteration cap must pass the independent
   fixed-point certificate. R135 does not relax `tol=1e-5` or silently accept a cap.
7. Region-specific winners are selected by equal aggregation over all three inner
   training-only splits. Official fold forecasts are produced only after freezing.

## Execution graph

1. Verify the parent task inventory, hashes, blocked marker, raw-data identity,
   dependency head, and absence of live parent workers.
2. Run 14 median fixed-point certificate tasks. Derived compact fit wrappers copy
   the frozen beta mean/covariance/trace and attach the certificate; they do not fit.
3. Resume the 84 missing adjacent AL fits and 14 internal scores. Existing certified
   HR work is reused.
4. Freeze one candidate and `tau0` per region from complete three-split AQL.
5. Materialize nine official designs and Normal-RHS fits, 63 nested AL fits, and the
   chunked official forecasts.
6. Produce fold- and region-level comparisons against the frozen QDESN and PriceFM
   references. Close as `R135_COMPLETE_NOT_PROMOTED`.

## Parallelism and storage

The controller accepts at most 30 idle physical cores. Every worker is pinned to one
physical CPU and all BLAS/OpenMP thread counts are one. Preparation fails if parent
workers are active. Runtime guards retain at least 180 GiB available memory and 170
GiB free disk and cap new campaign output at 28 GiB. The 12 GiB R134 evidence is
referenced and hash-checked rather than duplicated.

## Failure behavior

Every output is written atomically and sealed. A false certificate, failed worker,
dependency deadlock, source/hash change, or resource violation writes `blocked.json`
and preserves all evidence. Interrupted unsealed attempts are moved under
`interrupted_attempts/`. No budget, prior, convergence tolerance, selection rule, or
authority is changed automatically.

## Required validation before launch

```bash
python3 -m py_compile application/scripts/pricefm/468_run_pricefm_stage_r135_r134_completion.py
PRICEFM_R134_DEPENDENCY=<pinned-r127-worktree> \
PRICEFM_R135_PARENT_CAMPAIGN=<frozen-r134-campaign> \
pytest -q application/tests/test_pricefm_stage_r135_r134_completion.py
Rscript application/tests/test_pricefm_stage_r129_al_fixedpoint.R \
  application/R/pricefm_r129_al_fixedpoint_certificate.R \
  <cran-exdqlm-1.1.1-library>
```

The background controller additionally requires
`PRICEFM_R135_LAUNCH_APPROVED=true`; this is an execution gate, not model authority.
