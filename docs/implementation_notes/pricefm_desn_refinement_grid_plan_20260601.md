# PriceFM DESN Refinement Grid Plan, 2026-06-01

## Status

This note documents the PriceFM median refinement grid. Priority 1 was launched
and completed successfully after dry-run/config-generation checks passed.

Tracked grid:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml
```

The selected authoritative specification is documented in:

```text
docs/implementation_notes/pricefm_desn_authoritative_median_de_lu_20260601.md
```

and encoded as:

```text
application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_20260601.yaml
```

The existing broad screen remains documented separately:

```text
application/config/pricefm_desn_experiment_grid_median_de_lu_20260531.yaml
```

## Evidence From The Completed Screen

The completed `pricefm_median_de_lu_spec_screen_20260531` run supports a
focused refinement rather than a broad search:

- the overall test winner was the `L=96` flat-direct diagnostic with
  Q-DESN AL RHS_NS, AQL `11.237`;
- the best practical projected DESN cells were `L=96, m=240` with Q-DESN
  AL/exAL RHS_NS, test AQL around `12.31-12.35`;
- validation ranking also favored `L=96, m=240`;
- `L=192` was consistently weaker than `L=96`;
- feature capacity improved monotonically from `m=60` to `m=120` to `m=240`;
- projection scale `0.5` helped substantially at `m=120`, while `2.0` was
  worse;
- changing RHS_NS `tau0` over the screened range produced negligible Q-DESN
  prediction changes at fixed feature map.

The practical interpretation is that the bottleneck is primarily feature
representation, not RHS prior scale.

## Future-Run VB Defaults

The median warm-start base config now enforces bounded but non-trivial VB
iteration budgets for future generated PriceFM runs:

```yaml
normal:
  vb_control:
    min_iter: 50
    max_iter: 100

qdesn_vb:
  min_iter_elbo: 50
  max_iter: 100
```

The closed-form normal scaled-ridge fit remains a one-step exact fit. These
defaults target the iterative normal RHS_NS and Q-DESN AL/exAL RHS_NS fits.

## Refinement Grid

Scope:

- region: `DE_LU`;
- fold: `1`;
- quantile: `0.50`;
- horizons: all 96;
- ranking split: validation;
- audit split: test;
- models: normal scaled ridge, normal RHS_NS, Q-DESN AL RHS_NS exact chunked,
  Q-DESN exAL RHS_NS exact chunked;
- intercept shrinkage: disabled;
- train-origin request: `3000`, with selected/available counts recorded.

Priority 1:

| id pattern | lag window | features | projection scale | tau0 | purpose |
|---|---:|---:|---:|---:|---|
| `l072_m240_ps0p5` | 72 | 240 | 0.50 | 1e-3 | slightly shorter than one day |
| `l096_m240_ps0p35` | 96 | 240 | 0.35 | 1e-3 | low-scale near current winner |
| `l096_m240_ps0p5` | 96 | 240 | 0.50 | 1e-3 | main practical candidate |
| `l096_m240_ps0p75` | 96 | 240 | 0.75 | 1e-3 | moderate-scale neighbor |
| `l096_m360_ps0p35` | 96 | 360 | 0.35 | 1e-3 | capacity plus low scale |
| `l096_m360_ps0p5` | 96 | 360 | 0.50 | 1e-3 | main capacity step |
| `l096_m360_ps0p75` | 96 | 360 | 0.75 | 1e-3 | capacity plus moderate scale |
| `l096_m480_ps0p5` | 96 | 480 | 0.50 | 1e-3 | high-capacity practical cell |
| `l128_m240_ps0p5` | 128 | 240 | 0.50 | 1e-3 | mild context extension |
| `l144_m240_ps0p5` | 144 | 240 | 0.50 | 1e-3 | conservative L192 neighbor |

Priority 2:

- `L=96, m=480, projection_scale in {0.35, 0.75}`;
- `L=96, m=720, projection_scale = 0.5`;
- seed repeats for the main `m=240` and `m=360` candidates.

Flat-direct is excluded from this refinement grid because it already served its
diagnostic role and required roughly 170 minutes for one DE_LU/fold cell in the
previous screen.

## Priority-1 Results

The priority-1 grid completed with `10/10` experiments producing reports and
figures. The winning completed specification was:

| field | value |
|---|---:|
| experiment id | `l096_m480_ps0p5_tau1em3_seed20260601` |
| lag window | `96` |
| feature count | `480` |
| projection scale | `0.5` |
| tau0 | `1.0e-3` |
| seed | `20260601` |
| best model | Q-DESN exAL RHS_NS exact chunked |
| test AQL | `10.5046` |
| test MAE | `21.0091` |
| test RMSE | `30.6258` |

This improved on the previous flat-direct diagnostic winner, whose test AQL was
`11.2371`, and on the previous projected-feature winner, whose test AQL was
`12.3055`.

## Dry-Run Commands

Generate configs without launching:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/12_prepare_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml \
  --write
```

Dry-run the priority-1 launch selection:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/config/pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml \
  --priorities 1 \
  --experiment-jobs 10 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --force false \
  --dry-run true
```

Do not switch `--dry-run false` until the generated configs, selected IDs, and
window paths have been checked.

## Launch Policy

Priority 1 can use `--experiment-jobs 10 --cell-jobs 1`, but this should be
reconsidered if the `m=480` cells exceed the memory observed in the prior
`m=240` screen. Priority 2 should use `--experiment-jobs 3` or fewer because
the `m=720` cell is an expensive diagnostic.

## Validation Criteria

Each launched experiment must produce:

- completed `cell_status.csv`;
- finite validation and test metrics;
- converged iterative model summaries or explicit non-convergence notes;
- exact chunking equivalence gate for AL RHS_NS;
- warm-start diagnostics without fallback;
- model traces, parameter summaries, and fit figures;
- generated outputs only under ignored `application/data_local` paths.

Ranking remains validation AQL first. Test AQL is an audit, not the primary
selection criterion.
