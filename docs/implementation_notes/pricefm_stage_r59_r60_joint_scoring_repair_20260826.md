# PriceFM Stage-R59/R60 scoring freeze and bounded joint repair

## Scope and authority

This note records the complete Stage-R57/R58 audit and the implemented path to a
frozen joint-model validation decision. It covers only the PriceFM lane on
`work/pricefm-joint-quantile-20260824`. Reproducibility code is maintained in the
dedicated Version-2 worktree. Runtime artifacts remain in
`/data/jaguir26/local/src/Article-Q-DESN`. No GloFAS, simulation-validation,
registry, article, `main`, or Overleaf files are in scope.

The scientific unit remains one region/fold-specific model. There is no shared
DESN selected across regions or folds. Every joint fit inherits the region/fold
winner's DESN geometry, lag window, local or graph information set, AL or exAL
likelihood family, and RHS-NS `tau0=0.001`.

## Completed R57/R58 surface

The final artifact audit found all 114 expected joint seven-quantile fits and all
114 postfit contracts complete. Checkpoint and source-manifest hashes verified
for every case, all split firewalls were train/validation only, and no test
outcome was opened. The old launch ledger reports 74 completed and 40 failed
because it records the recoverable generic-summarizer failure. It is not the
scientific completion ledger. The repaired per-case summaries and R58 audit are
the authority.

| Quantity | Final value |
| --- | ---: |
| Region/fold cases | 114 |
| AL / exAL cases | 27 / 87 |
| Postfit-complete / integrity failures | 114 / 0 |
| Raw and contract validation wins | 112 |
| Contract validation wins | 112 |
| Median contract relative gain | 17.686% |
| Mean contract relative gain among winners | 17.101% |
| Contract gain range | -154.173% to 21.323% |
| Raw cases with crossings | 106 |
| Contract cases with crossings | 0 |
| Strict `tol=1e-4` convergence | 0 |
| Test outcomes opened | 0 |

The deterministic equal-weight monotone projection improved or preserved AQL in
all cases: it improved 106 and was equal in 8. It never worsened AQL and removed
all output crossings. Because this rule acts on the seven outputs of one joint
fit rather than synthesizing separately fit quantile models, it is a legitimate
joint prediction contract. Stage-R59 freezes it before any test audit:

- primary score: monotone-contract original-scale validation AQL;
- raw joint AQL and crossings: audit diagnostics, not an alternative score;
- model choice: validation only;
- test, MCMC, registry, and article actions: blocked.

## Two validation nonwinners

### `NO_5` fold 2

The inherited AL target-only DESN uses depth 1, 120 units, 120 features,
`alpha=0.5`, `rho=0.9`, `input_scale=0.25`, final-layer readout, and
`tau0=0.001`. The current validation authority is AQL 5.834527. The first joint
fit produced raw AQL 6.263076 and contract AQL 6.183849, a 5.987% contract loss.
Its final maximum coordinate change was 9.00167 with a negative last-five slope
of -0.97448. The trace and partial objective were still moving in a favorable
direction at iteration 50. The leading diagnosis is insufficient optimization,
not a demonstrated information-set or likelihood failure.

### `SE_2` fold 2

The inherited exAL local-autoregressive DESN uses depth 2, 80 units per layer,
80 features, `alpha=0.5`, `rho=0.9`, `input_scale=0.2`, final-layer readout, and
`tau0=0.001`. The current validation authority is AQL 5.360348. The first joint
fit produced raw AQL 13.663765 and contract AQL 13.624549, a 154.173% contract
loss. Its final maximum change was 10.5456 with a negative last-five slope of
-2.9524. Scale and shape coordinates were comparatively quiet, while the
prediction surface remained poor. This can still contain an initialization or
optimization component, but a bad joint basin or case-specific mechanism
mismatch is more plausible here than for `NO_5` fold 2.

Both losses occur in fold 2, but fold 2 wins in 36 of 38 cells with a median
contract gain of about 17.65%. This is not evidence of a general fold-2 defect.

## Checkpoint diagnosis and correction

The historical `pricefm_stage_r57_joint_vb_initialization_v1` checkpoint stores
beta, alpha, sigma, gamma, RHS state, quantiles, and dimensions. It omits the
beta covariance and local variational states. Therefore it cannot support exact
coordinate-ascent continuation. R60 labels its use honestly as
`core_plus_rhs_warm_restart_v1`.

The new `pricefm_joint_vb_checkpoint_v2` stores the complete state needed by the
next update:

- beta mean and covariance;
- ordered intercepts;
- AL inverse-gamma scale shape/rate and latent first/inverse moments;
- exAL gamma, sigma, latent, half-normal, and structured scale-shape moments;
- the complete anchor and innovation RHS-NS state.

AL and exAL kernels now consume these fields when an initializer is explicitly
provided. A focused deterministic test compares an uninterrupted run with a
split run and verifies the same final beta, covariance, intercept, scale,
latent, shape, and RHS state for both likelihood families. During this audit the
structured exAL scale-shape moment block was found to be essential; omitting it
produced a small but real continuation discrepancy.

## Implemented stages

### R59 scoring contract freeze

`208_freeze_pricefm_stage_r59_joint_scoring_contract.py` requires the complete,
integrity-clean R58 surface. It materializes all 114 scoring decisions, the 112
provisional contract winners, the exact two-case repair queue, gates, hashes,
JSON, and Markdown. It writes no launch YAML and opens no test evidence.

### R60 bounded initializer-stability comparison

`209_prepare_pricefm_stage_r60_joint_repair.py` creates exactly four jobs:

| Target | Arm | Iteration contract |
| --- | --- | --- |
| `NO_5` fold 2 | v1 core-plus-RHS warm restart | 100 additional updates |
| `NO_5` fold 2 | cold extended reference | 150 total updates |
| `SE_2` fold 2 | v1 core-plus-RHS warm restart | 100 additional updates |
| `SE_2` fold 2 | cold extended reference | 150 total updates |

All arms hold DESN, information set, likelihood, quantiles, and `tau0` fixed.
They run one process per assigned CPU with numerical libraries restricted to one
thread. New fits write full-state v2 checkpoints.

`210_closeout_pricefm_stage_r60_joint_repair.py` ranks the two arms within each
cell using only the frozen monotone-contract validation AQL. A repair is stable
only if it beats the current validation authority, has final maximum change at
most 1, and has a nonpositive last-five change slope. A validation win that
misses this stability guard is continued exactly from its v2 checkpoint before
test audit. If neither arm wins, the current individual authority is retained
and a case-specific mechanism change is designed without opening test.

`211_monitor_pricefm_stage_r60_joint_repair.py` monitors only these four jobs,
runs the idempotent validation postfit repair after all fits complete, removes
only reconstructible adapter matrices after successful checks, and invokes the
R60 closeout. It launches no fit itself, opens no test artifact, and refits no
model.

## Why this is the efficient next experiment

A new broad DESN or `tau0` grid would confound model capacity, shrinkage,
likelihood, and optimizer state after 112 of 114 inherited case-specific
specifications already win. The four-run comparison isolates the most immediate
unresolved question: whether the two failures are consequences of a short or
poorly initialized joint optimization. The cold arm protects against a bad v1
state, while the warm arm tests whether retaining the learned core and RHS state
is useful. Only if this bounded comparison fails is a new case-specific DESN,
likelihood, or `tau0` design justified.

## Reproducible commands

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python

$PRICEFM_PY application/scripts/pricefm/206_audit_pricefm_stage_r58_joint_recovery.py \
  --force true

$PRICEFM_PY application/scripts/pricefm/208_freeze_pricefm_stage_r59_joint_scoring_contract.py

$PRICEFM_PY application/scripts/pricefm/209_prepare_pricefm_stage_r60_joint_repair.py

$PRICEFM_PY application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py \
  --manifest /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r60_joint_repair_20260826/launch_manifest.csv \
  --runner application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R \
  --cpu-list <four-audited-unused-logical-cpus> --workers 4 --resume true --force false

$PRICEFM_PY application/scripts/pricefm/211_monitor_pricefm_stage_r60_joint_repair.py \
  --poll-seconds 300 --workers 4
```

## Validation

```bash
Rscript application/tests/test_pricefm_joint_quantile_continuation.R
Rscript application/tests/test_pricefm_joint_quantile_compact_kernel.R

$PRICEFM_PY -m pytest -q -p no:cacheprovider \
  application/tests/test_pricefm_stage_r57_joint_vb_campaign.py \
  application/tests/test_pricefm_stage_r57_r58_recovery.py \
  application/tests/test_pricefm_stage_r59_r60_joint_repair.py
```

## Gates after R60

1. Freeze the full 114-cell validation decision only if both repair targets have
   a stable joint validation winner. If one remains unresolved, retain the
   current individual authority as a provisional fallback and design one
   case-specific joint mechanism change without opening test.
2. Open the sealed test ledger for audit only after the intended joint-model
   validation selection is immutable. Compare the selected joint candidate with
   both current Q-DESN and cached PriceFM for the same cell.
3. Build a bounded MCMC confirmation queue only from validation-selected joint
   candidates that pass integrity and stability review. Use the v2 VB state for
   initialization where available. exAL confirmation must use the collapsed
   `M0_v_collapsed_support_logit` gamma update.
4. Require full seven-quantile predictions, diagnostics, source hashes, and
   reproducible manifests before any registry proposal.
5. Update article tables, figures, and prose only through the separate
   integration lane after the dual-reference test and MCMC gates pass.

## Do not do yet

- Do not broaden DESN or `tau0` screening before the four-arm diagnosis.
- Do not describe a v1 warm restart as exact continuation.
- Do not open test outcomes while an R60 validation choice remains mutable.
- Do not launch MCMC, mutate the registry, or edit the article.
- Do not touch another lane's files, jobs, worktree, or runtime artifacts.
- Do not merge or push `main` or any Overleaf branch from this lane.
