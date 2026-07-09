# GloFAS Stage C Full-Seven Confirmation Launch, 2026-06-22

This note records the controlled Stage C confirmation launched for the
Article-Q-DESN GloFAS application. The scope is limited to the GloFAS
application workflow in the Article-Q-DESN repository. It does not touch the
shared validation worktree or PriceFM work.

## Baseline To Beat

The current manuscript-facing GloFAS candidate remains:

```text
glofas_cal07_scorebalanced_spread140_add050_synthesis_final
```

Its current score-balanced metrics are:

| metric | value |
| --- | ---: |
| mean check loss | 0.3818 |
| CRPS on quantile grid | 0.7915 |
| mean interval score | 4.1930 |
| mean empirical coverage | 0.583 |

The replacement gate is intentionally conservative. A Stage C challenger should
improve mean check loss, avoid material CRPS and interval-score degradation,
retain credible coverage, pass launch/synthesis/diagnostic readiness checks,
and survive visual review before promotion.

## Candidate Set

Stage C expands the visually acceptable Stage B gate candidates to the full
seven quantiles:

| candidate | Stage B reason for confirmation |
| --- | --- |
| `arch08_d3w200` | near-tie gate score with strong empirical coverage |
| `arch04_a035` | near-tie gate score with slower leak dynamics |
| `arch07_w140` | wider D4 state with favorable gate coverage tradeoff |

For each candidate, the completed Stage B p05, p50, and p95 fits are reused.
Only p15, p35, p65, and p80 are launched. This avoids unnecessary recomputation
while preserving a full-seven synthesis for comparison.

## Runtime Package

The ignored runtime package is:

```text
local_trackers/runtime_configs/glofas_stage_c_full7_confirmations_20260622
```

Key files:

```text
stage_c_candidate_manifest.csv
stage_c_component_manifest.csv
stage_c_scheduler_manifest.csv
stage_c_prelaunch_validation.csv
launch_glofas_stage_c_full7_confirmations_20260622_scheduler.sh
watch_and_finalize_glofas_stage_c_full7_confirmations_20260622.sh
finalize_glofas_stage_c_full7_confirmations_20260622_candidates.sh
```

The preparation script is:

```bash
Rscript application/scripts/47_prepare_glofas_stage_c_full7_confirmations_20260622.R \
  --first_core 24 \
  --n_cores 12 \
  --max_active 12
```

The launch command used was:

```bash
bash local_trackers/runtime_configs/glofas_stage_c_full7_confirmations_20260622/launch_glofas_stage_c_full7_confirmations_20260622_scheduler.sh
```

The watcher was launched as:

```bash
tmux new-session -d -s glofas_stage_c_full7_confirmations_20260622_watch \
  'bash local_trackers/runtime_configs/glofas_stage_c_full7_confirmations_20260622/watch_and_finalize_glofas_stage_c_full7_confirmations_20260622.sh'
```

## Cleanup

Before launch, old non-authoritative GloFAS heavy objects were removed using a
manifested cleanup under the Stage C runtime package. The cleanup preserved:

- the current `cal07` score-balanced outputs;
- the underlying `cal07_shared003_disc006` full-seven source fits;
- the reused Stage B gate fits for `arch08_d3w200`, `arch04_a035`, and
  `arch07_w140`;
- any new Stage C output paths.

The cleanup reduced `application/runs` from about 117 GB to about 47 GB.

## Expected Finalization

After all 21 source rows per candidate are ready, the watcher runs, for each
candidate:

1. raw full-seven synthesis;
2. raw diagnostic figures;
3. score-balanced synthesis using factor 1.4 and additive half-width 0.5;
4. score-balanced diagnostic figures.

The score-balanced version is the fair comparison against the current
manuscript-facing baseline.

## Decision Rule

Do not promote a Stage C candidate automatically. After completion, compare:

- raw and score-balanced `score_summary.csv`;
- `score_by_quantile.csv`;
- `score_by_interval.csv`;
- `score_by_crps.csv`;
- launch readiness;
- diagnostic readiness;
- VB ELBO and parameter-change traces;
- discrepancy pre/post cutoff figures;
- synthesized bands and monotone quantile paths.

Promotion is appropriate only if a challenger beats the current baseline under
the agreed balanced metric gate and visual diagnostics.

## Closeout And Promotion

Stage C completed cleanly on 2026-06-22. All 21 component fits completed:
three candidates times seven quantile levels, with no failed component runs.
The watcher then produced raw and score-balanced full-seven syntheses and
diagnostic figures for each candidate.

The score-balanced `arch04_a035` candidate was selected as the Stage C winner:

```text
glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_synthesis_final
```

The selected model uses the same full-seven quantile set as the previous
manuscript-facing candidate, with a D4 reservoir, width 100 in each layer,
memory 300, leak rate 0.035 in each layer, shared RHS `tau0 = 0.001`, and
discrepancy RHS `tau0 = 0.03`. The synthesis keeps the score-balanced spread
calibration used for the fair comparison: multiplicative factor 1.4, additive
half-width 0.5, centered at quantile 0.50.

The final comparison against the previous current `cal07` candidate was:

| candidate | check loss | CRPS | interval score | coverage |
| --- | ---: | ---: | ---: | ---: |
| previous `cal07` score-balanced | 0.3818 | 0.7915 | 4.1930 | 0.583 |
| Stage C `arch04_a035` score-balanced | 0.3777 | 0.7833 | 4.0349 | 0.643 |

The improvement is modest but directionally clean: Stage C `arch04_a035`
improves mean check loss, CRPS, interval score, and empirical coverage for the
audited Dec. 25 GloFAS forecast origin. Raw Stage C syntheses were not promoted;
the score-balanced synthesis is the selected manuscript-facing output.

The selected outputs were promoted with:

```bash
Rscript application/scripts/21_promote_glofas_synthesis_outputs.R \
  --config local_trackers/runtime_configs/glofas_stage_c_full7_confirmations_20260622/arch04_a035/synthesis_config_scorebalanced.yaml \
  --synthesis_run_id glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_synthesis_final \
  --diagnostic_run_id glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_diagnostic_figures \
  --output_slug glofas_stage_c_arch04_a035_scorebalanced_20260622 \
  --allow_ignored_config TRUE

Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
```

The stable manuscript-facing aliases now point to:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_selection_manifest.csv
```

The complete promoted artifact manifest is:

```text
tables/glofas_application_promotion_manifest__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
```

The next architecture search should use this promoted Stage C candidate as the
baseline. New searches should remain local to the winning neighborhood
(`D = 4`, width about 100, memory about 300, leak rate about 0.035) unless a
specific diagnostic motivates a broader departure.
