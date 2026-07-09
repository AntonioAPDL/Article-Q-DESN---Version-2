# PriceFM Data Pipeline Implementation

Date: 2026-05-27

## Scope

This note records the article-side PriceFM data-layer implementation. The
pipeline prepares local, ignored PriceFM artifacts for future experiments. It
does not add a Q-DESN modeling adapter and does not produce manuscript-facing
tables or figures.

## Tracked Entry Points

Configuration:

```text
application/config/pricefm_data_pipeline.yaml
```

Scripts:

```text
application/scripts/pricefm/00_download_pricefm.py
application/scripts/pricefm/01_convert_raw_to_parquet.py
application/scripts/pricefm/02_audit_pricefm.py
application/scripts/pricefm/03_make_splits.py
application/scripts/pricefm/04_fit_scalers.py
application/scripts/pricefm/05_build_windows.py
application/scripts/pricefm/06_make_region_feature_figures.py
application/scripts/pricefm/run_pricefm_data_pipeline.py
```

Tests:

```text
application/tests/test_pricefm_config.py
application/tests/test_pricefm_audit.py
application/tests/test_pricefm_splits.py
application/tests/test_pricefm_windows.py
application/tests/test_pricefm_eda.py
```

Documentation:

```text
application/scripts/pricefm/README.md
PRICEFM_DATA_PIPELINE_REPORT.md   # ignored local planning report
```

## Local Artifact Policy

Generated data stay ignored under:

```text
application/data_local/pricefm/
application/cache/pricefm/
application/logs/pricefm/
```

The first implemented target is deliberately narrow:

```text
region: DE_LU
fold: 1
lag window: 96
lead window: 96
training window mode: contained_half_open
validation/test window mode: operational_half_open
scaling: per-region RobustScaler, fitted on training split only
```

## Source Snapshot

The live build pinned:

```text
Hugging Face dataset revision: 68b032a923e518bcf88edde906035ea223870aee
PriceFM GitHub commit: c72d1228bde80417d5cc782521328e02ab5401c3
FINAL.csv SHA256: 98f596deba7ffaf0edd21e78e1a779256ab24dda5463d445f081e1ee4ab3a54a
```

The audited raw file has:

```text
rows: 140257
raw columns: 191
raw timestamp range: 2021-12-31 23:00:00+00:00 to 2025-12-31 23:00:00+00:00
market_time convention: time_utc + 1 hour
market_time range: 2022-01-01 00:00:00+00:00 to 2026-01-01 00:00:00+00:00
```

## Reproducibility Commands

Create the ignored local Python environment:

```sh
python3.11 -m venv application/data_local/pricefm/venv
. application/data_local/pricefm/venv/bin/activate
python -m pip install --upgrade pip
python -m pip install huggingface_hub pandas pyarrow numpy scikit-learn joblib pyyaml pytest
```

Run the metadata-only gate:

```sh
python -m pytest application/tests/test_pricefm_config.py
```

Build the pilot:

```sh
python application/scripts/pricefm/run_pricefm_data_pipeline.py \
  --config application/config/pricefm_data_pipeline.yaml \
  --stage all \
  --pilot-only true
```

Run data-present gates:

```sh
PRICEFM_REQUIRE_DATA=1 python -m pytest \
  application/tests/test_pricefm_audit.py \
  application/tests/test_pricefm_splits.py \
  application/tests/test_pricefm_windows.py
```

## Validation Status

The initial pilot build completed end to end. It wrote:

```text
application/data_local/pricefm/interim/FINAL.parquet
application/data_local/pricefm/interim/audit_time.json
application/data_local/pricefm/interim/audit_columns.csv
application/data_local/pricefm/interim/audit_missingness_ranges.csv
application/data_local/pricefm/interim/schema_manifest.json
application/data_local/pricefm/processed/splits/split_registry.csv
application/data_local/pricefm/processed/scalers/fold_1/per_region_separate_xy_scalers.joblib
application/data_local/pricefm/processed/windows/fold_1/region=DE_LU/train_L96_H96_contained_half_open.npz
application/data_local/pricefm/processed/windows/fold_1/region=DE_LU/val_L96_H96_operational_half_open.npz
application/data_local/pricefm/processed/windows/fold_1/region=DE_LU/test_L96_H96_operational_half_open.npz
```

Tests passed:

```text
metadata-only PriceFM config tests: 6 passed
data-present PriceFM tests: 20 passed
```

## Exploratory Region Figures

The reproducible exploratory-analysis stage creates one all-feature figure per
region under:

```text
application/data_local/pricefm/figures/region_feature_overview/
```

Each figure uses the full clean `market_time` window and displays five stacked
daily-summary panels:

```text
generation
load
price
solar
wind
```

These figures are local review artifacts, not manuscript figures. They are
intended for region-by-region exploratory inspection before any PriceFM Q-DESN
modeling adapter is designed.

The first complete figure build wrote 38 PNG files and the index:

```text
application/data_local/pricefm/figures/region_feature_overview/region_feature_overview_index.csv
application/data_local/pricefm/figures/region_feature_overview/region_feature_overview_<REGION>.png
```

The optimized figure stage precomputes daily summaries across all configured
region-feature series, then renders each region. The validated build completed
in about two minutes on Muscat and produced 2540 x 2000 pixel PNGs at 180 dpi.

Updated tests passed:

```text
PriceFM config/audit/split/window/EDA tests: 30 passed
```

## Remaining Work

Before using PriceFM in Q-DESN examples, add a separate modeling adapter that
defines how PriceFM windows map into Q-DESN feature construction, responses,
quantiles, and evaluation targets. Do not treat the current `.npz` windows as
article-ready model inputs until that adapter is specified and tested.

Potential next steps:

```text
1. Add all-region or all-fold window expansion only after DE_LU/fold-1 remains stable.
2. Add optional adjacency metadata extraction from the pinned PriceFM repo.
3. Design the Q-DESN PriceFM adapter and associated no-leakage tests.
4. Add small synthetic/model smoke tests before any manuscript-scale PriceFM run.
```
