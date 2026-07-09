# PriceFM Corrected Reservoir Overnight Grid, 2026-06-02

## Status

This note records the corrected PriceFM reservoir-feature overnight grid prepared
after the reservoir-control propagation fix.

Completion and promotion note: priority `0` and priority `1` completed
successfully, and the promoted authoritative result is documented in:

```text
docs/implementation_notes/pricefm_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.md
```

Tracked grid config:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml
```

Ignored generated configs:

```text
application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_corrected_20260602
```

Ignored run root:

```text
application/data_local/pricefm/runs/pricefm_median_de_lu_reservoir_corrected_20260602
```

## Scientific Goal

The previous reservoir run improved the DE_LU fold-1 median test AQL to `6.4964`
against the best naive baseline near `14.0090`, but that run was affected by a
full-run-to-cell reservoir-control propagation bug. Its fitted artifacts are
valid, but they represent default single-layer reservoir features rather than
the intended depth/control grid.

This corrected grid keeps the model side fixed and searches the actual
reservoir feature-map controls. The highest-priority evidence is around small
one-layer reservoirs, because the pre-fix winner was actually `[80]` and the
near tie was `[120]`.

## Fixed Model Scope

| item | value |
|---|---:|
| region | `DE_LU` |
| fold | `1` |
| quantile | `0.50` |
| horizons | `1:96` |
| selected training origins | tail `3000` |
| prior | `RHS_NS` |
| RHS_NS `tau0` | `1.0e-3` |
| intercept shrinkage | disabled |
| likelihoods | Q-DESN AL and exAL |
| VB iterations | min `50`, max `100` |
| chunking | exact, chunk size `2048` |
| warm starts | normal scaled ridge -> normal RHS_NS -> Q-DESN AL -> Q-DESN exAL |
| artifact hygiene | enabled |

## Grid Shape

| priority | role | cells |
|---:|---|---:|
| `0` | corrected smoke gate | `5` |
| `1` | overnight main screen | `92` |
| `2` | optional tail diagnostics | `45` |

Priority `0` and `1` are intended for the overnight launch. Priority `2` is
defined but should wait until priority `1` identifies a stable region.

## Priority 0 Smoke Gate

The smoke cells verify the repaired full-config -> cell-config -> adapter
manifest path before the main screen starts.

| id pattern | units | alpha | rho | input scale |
|---|---:|---:|---:|---:|
| `rc_p0_d1n80...` | `[80]` | `0.70` | `0.90` | `0.50` |
| `rc_p0_d1n120...` | `[120]` | `0.70` | `0.90` | `0.50` |
| `rc_p0_d2n40x40...` | `[40, 40]` | `0.70` | `0.90` | `0.50` |
| `rc_p0_d2n80x80...` | `[80, 80]` | `0.70` | `0.90` | `0.50` |
| `rc_p0_d1n80...in0p25...` | `[80]` | `0.70` | `0.90` | `0.25` |

Smoke gate requirements:

- generated full configs contain intended reservoir controls;
- per-cell configs contain the same controls;
- completed feature manifests contain `reservoir_config_sha256`;
- distinct specs have distinct design hashes where expected;
- model summaries and figures are produced.

## Priority 1 Main Screen

Priority `1` focuses on small and compact reservoirs:

- D1 capacity curve: `[40]`, `[60]`, `[80]`, `[120]`, `[180]`, `[240]`;
- D1 core dynamics around `[80]` and `[120]`;
- high-input-scale checks for `[80]` and `[120]`;
- D2 compact base: `[40, 40]`, `[60, 60]`, `[80, 80]`, `[120, 120]`;
- D2 core dynamics around `[40, 40]` and `[80, 80]`;
- context checks for `[80]` and `[120]` at `L = 48, 72, 128`.

This deliberately avoids making `[480]`, `[720]`, or wide D2 reservoirs part of
the main overnight screen. Those are lower-probability after the pre-fix
evidence and should be tail diagnostics only.

## Validation Helper

New helper:

```text
application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py
```

It validates generated full configs, per-cell configs, and completed
`feature_manifest.json` files against the intended reservoir controls. It can
write compact JSON/CSV reports under ignored local paths.

## Commands

Generate configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --write
```

Validate generated configs:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 0,1 \
  --write-generated \
  --output-json application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_corrected_20260602/prelaunch_validation.json \
  --output-csv application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_corrected_20260602/prelaunch_validation.csv
```

Dry-run smoke:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume false \
  --force false \
  --dry-run true
```

Real smoke:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

Validate completed smoke:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/14_validate_reservoir_grid_artifacts.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 0 \
  --require-cell-configs \
  --require-feature-manifests \
  --output-json application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_corrected_20260602/smoke_validation.json \
  --output-csv application/data_local/pricefm/experiment_grids/pricefm_median_de_lu_reservoir_corrected_20260602/smoke_validation.csv
```

Launch priority `1` overnight after the smoke passes:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml \
  --priorities 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run false
```

## Promotion Rule

Do not promote a post-fix winner unless:

1. its feature manifest records the intended reservoir controls;
2. `reservoir_config_sha256` is present;
3. metrics, method summaries, trace summaries, predictions, and figures exist;
4. exact chunking checks pass;
5. heavy loser artifacts are cleaned only after the winner/reference artifacts
   are frozen.
