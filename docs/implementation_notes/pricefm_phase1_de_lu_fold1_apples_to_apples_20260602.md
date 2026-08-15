# PriceFM Phase-I DE_LU Fold-1 Apples-To-Apples Comparison

Date: 2026-06-02

## Objective

Regenerate local PriceFM Phase-I quantile forecasts for `DE_LU`, fold `1`, and
compare them directly with the Article-Q-DESN paper-quantile DESN/Q-DESN
outputs on the same region, fold, horizons, and quantile grid.

The upstream `phase1_pretraining.csv` file contains only aggregate metrics. It
does not contain per-origin, per-horizon, per-quantile forecasts. Therefore the
predictive-distribution comparison requires local PriceFM model inference from
the released `PhaseI_best.keras` checkpoint.

## Source Artifacts

```text
PriceFM repo:
application/data_local/pricefm/external/PriceFM

PriceFM commit:
c72d1228bde80417d5cc782521328e02ab5401c3

Released Phase-I model:
application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras

Released aggregate metrics:
application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv
```

The local released aggregate row for `DE_LU` is:

```text
AQL:  5.675211
RMSE: 24.339258
MAE:  14.211875
```

This row is a reference benchmark, not a predictive-distribution file.

## Comparison Geometry

The Article-Q-DESN paper-quantile run uses:

```text
region: DE_LU
fold: 1
test window: 2025-01-01 to 2025-05-01
horizons: 1:96
quantiles: 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90
DESN output root:
application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602
```

The exact apples-to-apples grid is the Article operational test grid:

```text
120 test origins x 96 horizons x 7 quantiles
```

The upstream tutorial's split-only rolling-window helper drops boundary anchors
when the lag or full lead window is not contained inside the split. For fold-1
test this gives 118 origins. That mode is useful as a paper-code-faithfulness
diagnostic, but it is not the row grid used by the current Article-Q-DESN
paper-quantile outputs.

## Tracked Scripts

Generate local PriceFM Phase-I predictions:

```text
application/scripts/pricefm/17_run_pricefm_phase1_predictions.py
```

Compare PriceFM Phase-I predictions with DESN/Q-DESN outputs:

```text
application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py
```

## TensorFlow Environment

Use an isolated TensorFlow environment. Do not mutate the lightweight PriceFM
data/DESN environment.

```bash
python3.11 -m venv application/data_local/pricefm/venv_pricefm_tf
. application/data_local/pricefm/venv_pricefm_tf/bin/activate
python -m pip install --upgrade pip
python -m pip install \
  numpy==2.0.2 \
  pandas==2.2.2 \
  scikit-learn==1.6.1 \
  scipy==1.15.3 \
  tensorflow==2.18.0 \
  h5py==3.14.0 \
  joblib==1.5.1 \
  setuptools==75.2.0 \
  pyyaml==6.0.2 \
  pyarrow \
  matplotlib
```

## Operational Apples-To-Apples Run

This is the direct comparison to the Article-Q-DESN output grid.

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/17_run_pricefm_phase1_predictions.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-repo application/data_local/pricefm/external/PriceFM \
  --model-path application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_apples_to_apples_20260602 \
  --region DE_LU \
  --fold 1 \
  --splits test \
  --window-mode operational \
  --batch-size 128
```

Expected local outputs:

```text
pricefm_phase1_predictions_scaled.csv
pricefm_phase1_predictions_original.csv
pricefm_phase1_metrics.csv
pricefm_phase1_metric_by_horizon.csv
pricefm_phase1_row_audit.csv
pricefm_phase1_report.md
summary.json
```

Then compare against the merged DESN/Q-DESN paper-quantile outputs:

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/18_compare_pricefm_phase1_desn_quantiles.py \
  --pricefm-output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_apples_to_apples_20260602 \
  --desn-output-dir application/data_local/pricefm/authoritative/pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602 \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602 \
  --region DE_LU \
  --fold 1 \
  --split test \
  --fan-horizon 1 \
  --max-origins 120
```

Expected comparison outputs:

```text
pricefm_vs_desn_predictions_scaled.csv
pricefm_vs_desn_predictions_original.csv
pricefm_vs_desn_metric_summary.csv
pricefm_vs_desn_metric_by_horizon.csv
pricefm_vs_desn_metric_by_horizon_group.csv
pricefm_vs_desn_row_alignment_audit.csv
pricefm_vs_desn_report.md
figures/pricefm_vs_desn_quantile_fans_h01.png
figures/pricefm_vs_qdesn_exal_fans_h001_h024_h048_h096.png
figures/pricefm_vs_desn_aql_by_horizon.png
figures/pricefm_vs_desn_mae_by_horizon.png
figures/pricefm_vs_desn_rmse_by_horizon.png
summary.json
```

## Optional Paper-Code-Faithfulness Diagnostic

To mimic the upstream tutorial's split-contained test-window construction:

```bash
application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/17_run_pricefm_phase1_predictions.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --pricefm-repo application/data_local/pricefm/external/PriceFM \
  --model-path application/data_local/pricefm/external/PriceFM/Model/PhaseI_best.keras \
  --output-dir application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_upstream_split_only_20260602 \
  --region DE_LU \
  --fold 1 \
  --splits test \
  --window-mode upstream_split_only \
  --batch-size 128
```

This mode should be reported separately because it uses 118 fold-1 test origins
instead of the 120 Article operational origins.

## Validation Criteria

- TensorFlow environment records package versions in `summary.json`.
- Released `PhaseI_best.keras` SHA256 is recorded.
- PriceFM predictions have all seven quantiles.
- Operational comparison aligns exactly on the shared test response grid.
- Row-alignment audit reports the aligned response-row count.
- Metrics are computed on both scaled and original price units.
- Figures compare predictive distributions, not only aggregate metrics.
- Generated predictions and figures remain under ignored local paths.

## Interpretation Rules

The operational comparison is the apples-to-apples comparison for the current
Article-Q-DESN run. The upstream split-only diagnostic is useful for checking
the released PriceFM code path, but it is not the same row target as the
Article-Q-DESN operational comparison.

The released `phase1_pretraining.csv` row remains a useful external reference,
but the local regenerated predictions are the authoritative object for the
distribution-level comparison.

## Completed Local Run

The operational apples-to-apples inference completed locally under:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_apples_to_apples_20260602
```

Key provenance:

```text
PriceFM repo commit: c72d1228bde80417d5cc782521328e02ab5401c3
PhaseI_best.keras SHA256: 387f1ba06dc42235d23267d0b2228225e33efffb20aeca9c94094f9fef4d19a5
TensorFlow: 2.18.0
Keras: 3.14.1
window mode: operational
test origins: 120
horizons: 96
prediction rows: 80640
```

The operational local PriceFM Phase-I metrics on the Article fold-1 grid were:

| method_id | split | unit | AQL | AQCR | MAE | RMSE |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| pricefm_phase1_pretraining | test | original | 5.323540 | 0.000000 | 13.123400 | 22.066193 |
| pricefm_phase1_pretraining | test | scaled | 0.051801 | 0.000000 | 0.127698 | 0.214716 |

The optional upstream split-only diagnostic completed under:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_de_lu_fold1_upstream_split_only_20260602
```

It used 118 fold-1 test origins, from `2025-01-02` through `2025-04-29`,
and produced original-scale metrics:

| method_id | split | unit | AQL | AQCR | MAE | RMSE |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| pricefm_phase1_pretraining | test | original | 5.341806 | 0.000000 | 13.155765 | 22.171695 |

## Completed DESN/Q-DESN Alignment

The direct PriceFM-vs-DESN comparison completed locally under:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602
```

The comparison aligned exactly on:

```text
11520 response rows = 120 origins x 96 horizons
403200 prediction rows = 5 methods x 11520 response rows x 7 quantiles
```

Original-scale test metrics on the common grid were:

| method_id | AQL | AQCR | MAE | RMSE |
| --- | ---: | ---: | ---: | ---: |
| qdesn_exal_rhs_ns_exact_chunked | 5.074280 | 0.000391 | 12.621029 | 20.029264 |
| qdesn_al_rhs_ns_exact_chunked | 5.119166 | 0.006004 | 12.662026 | 20.053755 |
| pricefm_phase1_pretraining | 5.323540 | 0.000000 | 13.123400 | 22.066193 |
| normal_rhs_ns | 6.690491 | 0.000000 | 15.858182 | 22.086782 |
| normal_scaled_ridge | 40.479678 | 0.000000 | 28.022764 | 35.936957 |

Generated comparison figures:

```text
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602/figures/pricefm_vs_desn_quantile_fans_h01.png
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602/figures/pricefm_vs_qdesn_exal_fans_h001_h024_h048_h096.png
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602/figures/pricefm_vs_desn_aql_by_horizon.png
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602/figures/pricefm_vs_desn_mae_by_horizon.png
application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602/figures/pricefm_vs_desn_rmse_by_horizon.png
```

Runtime and peak memory:

| step | wall time | max RSS |
| --- | ---: | ---: |
| operational PriceFM inference | 0:16.87 | 925980 KB |
| upstream split-only diagnostic | 0:22.14 | 1389840 KB |
| PriceFM-vs-DESN comparison/figures | 0:29.20 | 523496 KB |

## Notes

The TensorFlow environment follows the upstream PriceFM package pins. The
existing Article PriceFM scalers were created in the local lightweight venv with
a newer Scikit-Learn, so loading them in the upstream-pinned TensorFlow venv
emits an `InconsistentVersionWarning`. The comparison intentionally uses those
existing scalers because they are the scalers used by the Article-Q-DESN
outputs. The warning is recorded as an environment reproducibility note rather
than treated as a failed comparison gate.
