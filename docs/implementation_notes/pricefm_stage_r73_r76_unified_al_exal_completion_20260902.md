# PriceFM Stages R73-R76: independent-VB completion and repaired exAL plan

Date: 2026-09-02

## Decision

Complete the independent PriceFM VB comparison without repeating valid AL work.
R73 is the frozen complete AL surface. R74 is a diagnostic bound on postfit
monotonicity/calibration and is not a selector. R75 repairs two demonstrated
numerical/observability defects in the structured exAL path. R75B establishes
late-iteration stability on real PriceFM designs. R76 may then fit only the 294
missing scientific atoms needed for the 42 historical exAL-anchor cases.

R76 is not a promotion. Validation-only AL-versus-exAL selection, test audit,
registry mutation, article mutation, joint fitting, and MCMC remain separate
downstream gates.

## Scope and authority

- lane: PriceFM independent seven-quantile VB;
- code worktree:
  `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824`;
- branch: `work/pricefm-joint-quantile-20260824`;
- pre-change HEAD: `09943ca0b32d4c5f6e320f8fd1cee2d81d450aae`;
- artifact context: `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm`;
- exact base package: CRAN `exdqlm` 1.1.1, tarball SHA-256
  `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`.

This work does not modify GloFAS, joint-QVP, validation, a registry, or an
article repository. The locally repaired package is derived from exact CRAN
1.1.1 and is explicitly labelled `PriceFM-local` version `1.1.1.9002`; it is
not represented as an unmodified CRAN build.

## Audited state before repair

### R70 and R72

R70 attempted a 56-case, seven-quantile AL/exAL surface. It materialized 250 of
392 quantile atoms before 31 cases failed. R71 froze and audited those outputs.
R72 repaired the precision-matrix factorization and atomically completed the
142 missing AL atoms. Its runner used one `(case, quantile, likelihood)` unit,
hash-validated outputs, no binary model files, and a validation-only firewall.

### R73 complete AL surface

R73 combined 250 reusable R70 AL atoms and 142 R72 AL replacements:

| Quantity | Result |
|---|---:|
| Cases | 56 |
| AL atoms | 392 / 392 |
| Converged atoms | 127 / 392 |
| Cases with all seven convergence flags | 1 / 56 |
| Mean validation AQL | 6.846415 |
| Prior authoritative Q-DESN mean AQL | 6.679514 |
| Operational PriceFM mean AQL | 6.152574 |
| Cached PriceFM mean AQL | 6.968932 |
| Cases beating prior Q-DESN | 3 / 56 |
| Cases beating operational PriceFM | 0 / 56 |
| Cases beating cached PriceFM | 26 / 56 |
| Validation promotion candidates | 0 |

The convergence flag is reported rather than hidden, but finite complete
predictions permit the mechanism audits. It cannot be used to claim promotion.

### R74 no-refit feasibility

Deterministic rowwise rearrangement reduced full-validation AQL in all 56 cases
by a mean `0.092361` AQL, but still produced zero operational PriceFM wins.
Forward-block offset diagnostics recommended rearrangement alone in 31 cases,
horizon-block offset plus rearrangement in 19, and global offset plus
rearrangement in 6. These are mechanism diagnostics only: their forward blocks
do not define a frozen final selector and therefore authorize no test or
promotion action.

## Root-cause diagnosis

Two independent failures were demonstrated.

### Scale-insensitive Cholesky fallback

The exact CRAN solver tried an absolute `1e-10` diagonal jitter after a failed
Cholesky factorization. On a real weighted PriceFM design, the matrix diagonal
scale was about `3.62e10`, whose floating-point spacing was about `7.63e-6`.
Adding `1e-10` changed no represented diagonal value. R72 retained the original
zero-jitter and absolute-jitter paths, then added an auditable symmetric,
scale-aware relative-jitter ladder.

### Large-order Bessel-K failure in structured exAL

The structured sigma/gamma update evaluates Bessel-K functions at order

`k = -(a_sigma + 1.5 n)`.

For PriceFM training sizes near `n=100,000`, the magnitude of the order is near
150,000. Base R's direct scaled Bessel-K call becomes non-finite at this scale.
This explains why small tests could run while production exAL fits failed or
diverged. R75 adds a uniform large-order log-Bessel approximation, retains the
original direct path through order 500, and uses adaptive finite differences
for order derivatives. Numerical tests verified agreement with direct Bessel-K
at moderate orders and finite GIG moments through `n=100,000`.

R75 also corrects convergence observability: the public runner previously
overwrote `E_s` before calculating its change, making `delta_s` identically
zero. The repair compares against the previous state.

## Validation evidence for the repair

### Package and isolated checks

- exact tarball and sequential R72/R75 patch hashes are recorded in the runtime
  manifest;
- Python numerical/source tests pass;
- installed-package R integration tests pass at `n=100,000` for the structured
  update and at `n=2,000` through the exported `exalStaticLDVB` API;
- a real FR fold 1, tau 0.5, 5,000-row, 12-iteration check completed with finite
  beta, sigma, gamma, nonzero `delta_s`, and the large-order backend active.

### R75 nine-cell mechanism probe

The probe crossed three mechanism classes (FR fold 1 local, EE fold 1 graph,
and historically problematic SE_2 fold 2) at tau 0.1, 0.5, and 0.9. All nine
completed, all required states were finite, all used the large-order backend,
all performed ten structured updates, and no test or binary artifact was used.

The initial probe also found that 12 iterations are not enough to judge model
quality: exAL training pinball ratios versus the AL warm start ranged above one.
The first launch was falsely marked failed because the harness included the
expected first-iteration `delta_elbo=NA` in a finite-state assertion. The
assertion was corrected to inspect only state quantities that must be finite;
the identical nine hash-frozen tasks then completed 9/9.

### R75B late-iteration stability gate

R75B extended the same nine cells to 100 iterations, used the production
temporal schedule (`RHS freeze=50`, sigma/gamma warm-up 10, damping through 30,
at least 35 post-warm-up updates), and remained train-only.

| Gate diagnostic | Result |
|---|---:|
| Completed probes | 9 / 9 |
| Failed probes | 0 |
| Structured updates per probe | 90 |
| Maximum absolute gamma | 1.717146 |
| Maximum sigma/AL-sigma ratio | 1.615848 |
| Maximum exAL/AL training pinball ratio | 1.233175 |
| Maximum final-ten-iteration state change | 0.074317 |
| Package convergence flags | 0 / 9 |

The strict package convergence flag did not fire by iteration 100. This is an
explicit uncertainty, not a hidden pass. The broad-launch decision rests on
finite late trajectories, small bounded tail changes, positive ELBO progress,
and absence of the catastrophic scale/coefficient behavior seen in R70. R76
must retain full traces and report convergence; scientific selection must not
silently treat non-convergence as success.

## R76 production design

### Why 294 tasks rather than repeating 784 fits

R73 already provides all 392 AL atoms. Refitting AL would add compute without
new information. Of the 56 R69A case-specific family anchors, 42 selected exAL
and 14 selected AL. R76 therefore targets the unresolved exAL evidence for the
42 exAL-anchor cases only:

`42 cases x 7 quantiles x 1 exAL likelihood = 294 atomic fits`.

The 14 AL-anchor cases remain represented by their complete R73 AL surface.
Reopening those family decisions would require a separately justified design;
it is not smuggled into this repair campaign.

### Frozen task contract

Each task:

1. preserves the R69B case-specific region, fold, DESN depth, units, lags,
   feature policy, graph radius when applicable, alpha, rho, input scale, and
   `rhs_tau0`;
2. initializes beta and sigma from the corresponding hash-frozen R73 AL atom;
3. fits one independent exAL VB model at one quantile;
4. uses the repaired structured sigma/gamma update, 150 maximum iterations,
   200 beta samples, 200 xi samples, a 151-point structured grid, RHS freeze 50,
   sigma/gamma warm-up 10, and damped updates through iteration 30;
5. reads train and validation only;
6. writes validation predictions, method/parameter/beta summaries, full VB/SPD
   traces, structured-grid diagnostics, RHS diagnostics, warm-start provenance,
   and a terminal hash manifest;
7. writes no `.rds`, `.rda`, `.RData`, or `.rdata` model object;
8. authorizes no test access, registry/article mutation, joint model, or MCMC.

The launcher is resumable only from a `completed` terminal whose every output
hash still matches. Failed, partial, missing, or changed tasks are rerun. Each R
process is single-threaded and pinned to one logical CPU.

## Downstream closeout, not yet authorized

After all 294 tasks finish, the next read-only stage should:

1. verify all task/config/input/output hashes and the absence of test access;
2. combine each seven-quantile exAL case and compute validation AQL,
   calibration, crossings, convergence, and horizon diagnostics;
3. compare R76 exAL against the same-case R73 AL surface using validation only;
4. freeze one family per case only when the candidate is finite, complete, and
   passes the registered convergence/stability policy;
5. apply rearrangement or calibration only under a separately frozen forward
   selector informed by R74;
6. open test metrics only after the validation selection manifest is immutable;
7. require the selected candidate to beat both the current authoritative Q-DESN
   and operational PriceFM on test before any full-quantile confirmation queue;
8. mutate neither registry nor article until reproducibility/hash and final
   confirmation gates pass.

## Commands and evidence locations

Core validation commands:

```bash
/tmp/pricefm_health_py311/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r71_r70_closeout.py \
  application/tests/test_pricefm_stage_r72_atomic_runner.py \
  application/tests/test_pricefm_stage_r72_launcher_monitor.py \
  application/tests/test_pricefm_stage_r72_mechanism_gates.py \
  application/tests/test_pricefm_stage_r72_missing_al_repair_prep.py \
  application/tests/test_pricefm_stage_r72_rhs_schedule_gate.py \
  application/tests/test_pricefm_stage_r72_spd_repair.py \
  application/tests/test_pricefm_stage_r73_completed_al_surface.py \
  application/tests/test_pricefm_stage_r74_no_refit_feasibility.py \
  application/tests/test_pricefm_stage_r75_large_n_gig_repair.py \
  application/tests/test_pricefm_stage_r75_exal_mechanism_probe.py \
  application/tests/test_pricefm_stage_r75b_exal_stability.py \
  application/tests/test_pricefm_stage_r76_repaired_exal_surface.py
Rscript application/tests/test_pricefm_stage_r72_spd_repair.R
Rscript application/tests/test_pricefm_stage_r75_large_n_gig_repair.R
```

Observed result: 30 Python tests passed and both R integration tests passed.

Authoritative generated evidence:

- `application/data_local/pricefm/authoritative/pricefm_stage_r73_completed_al_surface_20260902`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r74_no_refit_feasibility_20260902`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r75_large_n_gig_mechanism_gate_20260902`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r75b_large_n_gig_stability_gate_20260902`;
- `application/data_local/pricefm/authoritative/pricefm_stage_r76_repaired_exal_launch_prep_20260902`;
- `application/data_local/pricefm/experiment_grids/pricefm_stage_r76_repaired_exal_surface_20260902`;
- `application/data_local/pricefm/runs/pricefm_stage_r76_repaired_exal_surface_20260902`.

## Explicitly blocked

- no test-set selection;
- no registry mutation;
- no article, table, figure, or prose update;
- no joint QDESN fit;
- no MCMC fit;
- no claim that the repaired exAL family improves validation or test AQL before
  R76 and its read-only closeout complete;
- no deletion of R69B, R72, R73, R75, or R75B evidence needed for provenance.
