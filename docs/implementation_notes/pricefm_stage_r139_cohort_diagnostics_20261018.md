# PriceFM R139 cohort diagnostics

R139 is a read-only closeout of completed R137 and R138 runtime evidence. It does not fit models or mutate PriceFM authority, registries, article assets, or prior campaign directories.

The program has two operations:

```bash
python application/scripts/pricefm/474_closeout_pricefm_stage_r139_cohort_diagnostics.py region \
  --config application/config/pricefm_stage_r139_cohort_diagnostics_20261018.json \
  --stage r137 --region EE --campaign-root /path/to/r137_EE --output /path/to/r139/regions/EE

python application/scripts/pricefm/474_closeout_pricefm_stage_r139_cohort_diagnostics.py aggregate \
  --config application/config/pricefm_stage_r139_cohort_diagnostics_20261018.json \
  --packet EE=/path/to/EE --packet HU=/path/to/HU \
  --packet SK=/path/to/SK --packet IT_NORD=/path/to/IT_NORD \
  --negative-control /path/to/DK_1 --output /path/to/r139/aggregate
```

Each regional operation verifies the source terminal state and SHA-256 evidence, reconstructs predictions in origin order, reproduces frozen fold metrics, and writes horizon-level diagnostics. The aggregate operation requires exactly the configured R137 cohort, gives every region equal weight, and keeps R138/DK_1 outside the cohort estimate.

The runtime outputs are intentionally ignored by Git. The tracked config and tests define the contract needed to reproduce them.
