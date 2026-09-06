# GloFAS Part 4 Latent-Family Implementation

Date: 2026-09-06

## Status

Implementation and focused validation are complete on the dedicated Part 4
scientific lane. No production model fit has been launched. The production
launcher requires both an explicit execution flag and an approval token.

Part 4 is an ensemble-likelihood latent-path analysis. It is not a historical
fit followed by a separate forecast adapter. Future USGS values enter the
posterior as missing responses and are inferred jointly with the model
parameters. Observed future USGS values are permitted only in a physically
separate post-fit scoring sidecar.

## Fixed Scientific Contract

| Item | Frozen value |
| --- | --- |
| Historical cutoff/origin | `2022-12-25` |
| Requested evaluation start | `2022-12-26` |
| Requested evaluation end | `2023-01-24` |
| Requested horizon | 30 days |
| Available issued GloFAS horizon | 28 days |
| Executable Part 4 horizon | `1:28`, ending `2023-01-22` |
| Issued ensemble size | 51 members at every retained horizon |
| Future USGS role during fitting | Latent missing response |
| Future USGS role after fitting | Scoring only |
| Separate forecast stage | None |
| Crossing correction | None |
| CEFS inputs | Forbidden |
| GEFS inputs | Forbidden |
| Future PPT/soil | Realized PRISM/ERA5 oracle values; diagnostic, not operational |
| Rolling origin | Not part of Part 4 |

The implementation aborts if the cutoff, requested dates, issued horizons,
or member counts violate this contract. It does not extrapolate, pad, or
invent GloFAS members for requested days 29 and 30.

The inherited legacy YAML contains a GEFS covariate subtree. The Part 4 config
builder replaces that subtree rather than inheriting it: `future_policy` is
`oracle_realized`, the provider is `realized_future_oracle`, and the covariate
horizon is 28 days. These PRISM/ERA5 values make Part 4 a retrospective oracle-
covariate diagnostic. They are not claimed to be origin-available operational
weather forecasts.

## Model

On the transformed scale, let `q_t = x_t' beta` be the shared/reference
location and `d_t = z_t' alpha` the discrepancy location. Historical rows are

```text
Y_t       ~ F_Y(q_t,       source-specific nuisance parameters)
G_retro_t ~ F_G(q_t + d_t, source-specific nuisance parameters)
```

For each issued member `j` and horizon `h`,

```text
G_ens_hj ~ F_G(q_(T+h) + d_(T+h), source-specific nuisance parameters).
```

The unknown path `Y_(T+1:T+28)` is a latent variable. Its lagged values feed
the future reference reservoir recursively. The future discrepancy inputs use
the common weighted-mean issued GloFAS center and the current latent USGS path,
following the frozen two-block input contract. Future observed USGS values
never enter either reservoir, the readout, the initial path, or a variational
update.

All 51 issued members remain likelihood rows. Their weights are normalized to
`1/51` within each horizon, so the total issued-GloFAS contribution is one per
horizon rather than 51. The same weighted-mean ensemble center is used to
construct future state features for every quantile; quantile-specific empirical
ensemble summaries are diagnostics only.

## Implemented Families

| Family | Fits | Coefficient prior | Initialization |
| --- | ---: | --- | --- |
| Normal latent Ridge | 1 | Gaussian Ridge | Hash-validated Part 3 coefficients when supplied; otherwise cold |
| Normal latent RHS/VB | 1 | Block RHS | Normal Ridge |
| Independent AL/RHS VB | 7 | Block RHS | Normal RHS at `p=0.50`, then neighboring AL fits |
| Independent exAL/RHS VB | 7 | Block RHS | Matching completed AL quantile |
| Joint AL/RHS VB | 1 | Adjacent-quantile block RHS | All seven independent AL fits |
| Joint exAL/RHS VB | 1 | Adjacent-quantile block RHS | All seven independent exAL fits |

The quantile grid is exactly

```text
0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95
```

There are 18 production jobs in total.

## Dependency Graph

```text
Normal Ridge -> Normal RHS/VB -> AL 0.50

AL 0.50 -> AL 0.35 -> AL 0.20 -> AL 0.05
AL 0.50 -> AL 0.65 -> AL 0.80 -> AL 0.95

AL q -> exAL q, independently for each q

all seven AL fits   -> joint AL
all seven exAL fits -> joint exAL
```

The scheduler starts a job only when every dependency has a `.completed`
marker. A stale `.running` marker or any `.failed` marker stops the scheduler
for audit. Each worker is constrained to one numerical thread, and no more
than 18 model workers can be requested.

## Inference Details

### Normal

The Normal family uses separate unknown observation variances for USGS and
GloFAS. Conditional readout updates are Gaussian. The Ridge fit remains an
iterative latent-path VB fit because future USGS values, and therefore future
reservoir states, are unknown. The RHS fit uses separate reference and
discrepancy shrinkage blocks.

### AL

The AL implementation uses the normal-exponential augmentation and a
Laplace-Delta approximation for the nonlinear future-state recursion.
Observation weights are carried through local latent factors, coefficient
updates, source scales, the approximate objective, and future-path updates.
For issued members this is a complete-data fractional/power-likelihood
construction. It prevents 51-fold horizon weighting, but it must not be
described as an exact fractional marginal AL posterior without a separate
derivation.

### exAL

The exAL implementation keeps source-specific scale and shape terms and uses
the repository's structured quadrature kernels. Ensemble weights are included
in the structured sufficient statistics. The same nonlinear future-state and
complete-data weighting qualification as AL applies.

### Joint quantiles

The joint fits coordinate seven quantile-specific latent-path factors through
adjacent-quantile RHS priors, separately for reference and discrepancy
coefficients. They are implemented as mean-field quantile-block coordinate
updates initialized from completed independent fits. This is not a monolithic
exact joint posterior, and no post-hoc monotonicity correction is applied.

## Warm Starts And Coefficient Freeze

Production defaults are:

```text
max_iter = 100
min_iter = 30
tol = 0.01
freeze_beta_warmup_iters = 20
min_beta_updates = 10
n_draws = 500
progress_every = 1
```

During the first 20 iterations, compatible initialized readout coefficients
are held fixed while latent-path and nuisance quantities adapt. Coefficient
updates then begin, and at least 10 coefficient updates are required before
convergence. The freeze is applied only when an initializer exists; a cold
root fit is not frozen around arbitrary zeros.

An optional Part 3 initializer is accepted only when the selected-anchor
manifest contains both `fit_object_path` and `fit_object_sha256`. The loader
verifies the SHA256 digest, coefficient dimensions, and coefficient names.
It transfers compatible coefficient moments but initializes the new Part 4
future path from the Part 4 ensemble-likelihood design. Missing or incompatible
metadata causes a hard failure; it is never silently coerced.

## Truth Firewall

The fitting object contains:

- historical USGS through the cutoff;
- historical retrospective GloFAS through the cutoff;
- issued GloFAS ensemble values for horizons 1:28;
- realized PRISM/ERA5 oracle PPT and soil inputs required by the frozen design;
- latent future USGS placeholders and recursive state builders.

It does not contain finite post-cutoff USGS truth. A separate scoring sidecar
contains only `target_date` and transformed future USGS truth for the 28 scored
dates. The worker loads that sidecar only after the fit object has been
constructed. Fit artifacts record the truth policy, and prediction summaries
remain valid with missing scoring truth.

## Files

Core implementation:

- `application/R/glofas_part4_latent_family.R`
- `application/R/glofas_part4_ensemble_likelihood_contract.R`
- `application/R/latent_path_vb_normal.R`
- `application/R/latent_path_vb_al.R`
- `application/R/latent_path_vb_exal.R`
- `application/R/latent_path_vb_joint.R`
- `application/R/fit_qdesn_latent_path.R`

Execution surface:

- `application/scripts/61_prepare_glofas_part4_ensemble_likelihood_launch.R`
- `application/scripts/386_run_glofas_part4_latent_family_job.R`
- `application/scripts/387_launch_glofas_part4_latent_family_dag.py`
- `application/scripts/388_check_glofas_part4_latent_family_dag.py`

Focused tests:

- `application/tests/test_glofas_part4_ensemble_likelihood_contract.R`
- `application/tests/test_glofas_part4_latent_family.R`
- `application/tests/test_glofas_part4_latent_family_scheduler.py`
- `application/tests/test_latent_path_design.R`
- `application/tests/test_joint_exqdesn_exact_structured_inference.R`

## Preparation

Preparation requires a frozen three-row selected-anchor manifest with roles
`reference_anchor`, `discrepancy_anchor`, and `historical_joint_anchor`.
The reference and discrepancy rows provide their frozen DESN geometries,
lag contracts, seeds, and RHS `tau0` values. The historical joint row records
the selected Part 3 provenance and may optionally provide the exact fit path
and hash for coefficient initialization.

```bash
Rscript application/scripts/61_prepare_glofas_part4_ensemble_likelihood_launch.R \
  --base_config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --anchor_manifest /absolute/path/to/frozen_part4_anchor_manifest.csv \
  --run_label glofas_part4_latent_family_dec25_YYYYMMDD \
  --runtime_root local_trackers/runtime_configs/glofas_part4_latent_family_dec25_YYYYMMDD \
  --require_frozen true \
  --allow_forbidden_sources false \
  --write_candidate_configs true \
  --dry_run true \
  --max_iter 100 \
  --min_iter 30 \
  --tol 0.01 \
  --freeze_beta_warmup_iters 20 \
  --min_beta_updates 10 \
  --n_draws 500
```

Expected prepared state:

- 18 manifest rows;
- one root row marked `ready_after_operator_launch_approval`;
- 17 rows blocked by dependencies;
- no `.running`, `.completed`, or `.failed` production markers;
- copied selected-anchor manifest and one config/model grid per job;
- a `DO_NOT_RUN_WITHOUT_APPROVAL.txt` guard file.

## Health Check

```bash
python3 application/scripts/388_check_glofas_part4_latent_family_dag.py \
  --runtime-root local_trackers/runtime_configs/glofas_part4_latent_family_dec25_YYYYMMDD
```

Before launch, this should report 18 pending jobs and zero running, completed,
or failed jobs.

## Production Launch Gate

The following command is documented for a later explicitly approved launch.
It was not run during implementation.

```bash
python3 application/scripts/387_launch_glofas_part4_latent_family_dag.py \
  --runtime-root local_trackers/runtime_configs/glofas_part4_latent_family_dec25_YYYYMMDD \
  --workers 18 \
  --poll-seconds 60 \
  --session-prefix glofas_part4_latent_dec25 \
  --background \
  --execute \
  --approval-token RUN_GLOFAS_PART4_LATENT_FAMILY
```

The dual `--execute` and exact-token requirement prevents a preparation or
test command from starting production fits.

## Runtime Artifacts

The runtime root is intentionally ignored by Git. It contains:

- one shared, truth-free design object and its hash;
- one scoring-only truth sidecar;
- compact fit-side objects that reference rather than duplicate the design;
- posterior latent-path draws;
- by-horizon and aggregate scores;
- VB and joint-coordinate traces;
- coefficient summaries with 95% variational intervals;
- per-job artifact manifests and SHA256 hashes;
- scheduler and worker logs;
- atomic status markers.

No runtime object, prediction payload, score table, log, or generated figure
belongs in Git.

## Validation Contract

The focused test suite checks:

- exact date, horizon, and 51-member ensemble gates;
- future-USGS physical redaction from fit-side data;
- scoring-sidecar isolation and sensitivity to changed scoring truth;
- ensemble weights summing to one per horizon;
- Normal, AL, and exAL toy latent-path fits;
- general GIG moment compatibility at the historical half-order case;
- weighted exAL structured-statistic duplication invariance;
- preservation of adjacent-prior additions across RHS updates;
- coefficient-freeze and minimum-update behavior;
- exact compatible initialization and rejection of bad hashes;
- compact fit objects without duplicated designs;
- optimized empirical CRPS equivalence to the direct formula;
- all 18 dependency edges and launcher approval blocking;
- dry-run preparation without model execution.

## Remaining Risks Before Production

1. The frozen selected-anchor manifest must be supplied from verified Part 1,
   Part 2, and Part 3 outputs. Preparation should not proceed from prose IDs.
2. A real-data preflight should build and hash the design, verify the 28 x 51
   issued panel, and stop before calling any fitter.
3. A tiny production-shaped smoke fit should be explicitly approved before the
   18-job launch; toy tests do not measure full-design memory pressure.
4. AL/exAL ensemble weighting is the documented complete-data power-likelihood
   approximation. Manuscript claims must reflect that qualification.
5. Joint fits are coordinate mean-field approximations. Their convergence and
   raw crossing diagnostics must be inspected before scientific use.
6. The 28-day result cannot be labeled a complete 30-day Part 4 forecast.

These risks do not require repeating Part 1, Part 2, or Part 3 screening. They
are launch-readiness checks for the already selected geometries and priors.
