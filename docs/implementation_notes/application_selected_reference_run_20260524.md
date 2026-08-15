# GloFAS Application Selected Reference Run, 2026-05-24

This note records the current manuscript-facing GloFAS application output set.
The selected run is a reproducible reference application, not a claim that this
specification is globally optimal across basins, forecast origins, quantile
levels, or reservoir architectures.

## Selected Run

```text
latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355
```

Tracked config:

```text
application/config/glofas_latent_path_al_vb_dec25_d1n300_tau3em3_main1000.yaml
```

Promotion manifest:

```text
tables/glofas_application_promotion_manifest__latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355.csv
```

Current-output registry:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_selection_manifest.csv
```

The registry provides stable manuscript aliases for the currently selected run.
Run-specific promoted artifacts remain immutable; changing the selected
application run should be done by regenerating the current-output registry from
the new run's promotion manifest.

## Selection Command

```sh
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355.csv
```

This command writes:

- a stable TeX macro registry for manuscript paths and scalar summaries;
- a manuscript-facing compact score table that excludes unavailable interval
  and CRPS columns;
- a CSV score summary with clean model labels;
- a current-selection manifest with hashes for the registry, selected figures,
  selected tables, promotion manifest, config snapshot, and diagnostic files.

## Audited Result

The selected run reports the median forecast only. Mean check loss over the 28
issued target dates is:

| Model | Mean check loss |
|---|---:|
| Q-DESN calibration | 0.6289 |
| Raw GloFAS median | 0.8754 |

This is a 28.2 percent reduction in mean check loss for this selected forecast
origin. Interval score, empirical coverage, and CRPS are intentionally not
reported for this median-only run.

## Reproducibility Checks

The promotion manifest records:

- promotion article SHA:
  `8bc4a88ff033d63376647f88fd9c76da4769d10b`;
- Q-DESN engine SHA:
  `d075941313186b15853e94c2a2cad7d0fec410d8`;
- 0 source/promoted hash mismatches at promotion time.

The current-selection manifest additionally records the Article git SHA used
when the registry was generated. Because the manifest itself is a generated
tracked artifact, its `selection_git_sha` should be interpreted as generation
provenance, not as a circular hash of the commit that contains the manifest.

Use:

```sh
Rscript application/tests/run_tests.R

Rscript -e 'source("application/R/00_packages.R"); m <- app_read_csv("tables/glofas_application_current_selection_manifest.csv"); stopifnot(all(file.exists(m$path)), all(vapply(m$path, app_sha256_file, character(1)) == m$sha256))'
```

## Future Replacement Protocol

For a new model specification:

1. run the design gate and launch-readiness checks;
2. run the full application workflow;
3. promote storage-light outputs with `08_promote_application_outputs.R`;
4. regenerate the current-output registry with `09_select_application_outputs.R`;
5. recompile the manuscript and update the application interpretation only for
   claims supported by the new promoted outputs.

Old promoted runs can remain in `tables/` and `figures/` as historical
artifacts. The manuscript should depend only on the current-output registry.
