# PriceFM Stage-K Regularized Graph Run Closeout

Date: 2026-06-23

## Purpose

This note closes the Stage-K regularized graph median screen.  Stage K tested
compact graph-summary inputs after Stage J showed that raw graph-khop expansion
could improve isolated validation rows without enough seed stability.

The run is a median-only screen over selected unresolved or unstable
region/fold cases.  It is not a promotion step by itself.  Validation metrics
drive the multi-seed gate; test metrics are audit-only.

## Run Inputs

Grid config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml
```

Materialized manifest:

```text
application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/manifest.csv
```

Run outputs:

```text
application/data_local/pricefm/runs/pricefm_stage_k_regularized_graph_20260623/
```

Summary outputs:

```text
application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623/
```

The summary baseline is the Stage-J priority-0 median closeout registry:

```text
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv
```

The broader Stage-I authoritative quantile registry contains the same HU/RO
region-fold keys, but its median comparison fields are missing for those rows.
It should not be used as the completed Stage-K comparison baseline.

## Commands

Launch command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_k_regularized_graph_20260623.yaml \
  --priorities 0 \
  --experiment-jobs 18 \
  --cell-jobs 1 \
  --build-windows true \
  --resume true \
  --dry-run false
```

Closeout summary command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623 \
  --require-complete true
```

## Launch Result

The launcher completed all planned rows:

| kind | rows | status |
|---|---:|---|
| window_build | 8 | completed |
| experiment | 87 | completed |
| total | 95 | completed |

Materialized model outputs:

| artifact | count |
|---|---:|
| metric summaries | 87 |
| model directories | 87 |
| adapter manifests | 87 |

No Stage-K log error signatures were found for:

```text
Traceback|Error|FAILED|failed|Exception|Killed
```

No Stage-K fit processes remained after the run.  Existing unrelated GloFAS
processes were not modified.

## Multi-Seed Gate Result

The summary completed with:

| quantity | value |
|---|---:|
| manifest rows | 87 |
| seed metric rows | 87 |
| geometry rows | 44 |
| missing metric rows | 0 |
| pre-closeout rows | 0 |

No geometry passed the Stage-K multi-seed validation gate.  Therefore no
Stage-K candidate should be promoted from this run.

The closest geometry was SI fold 1 with graph-summary mean degree 2:

| region | fold | method | feature policy | graph degree | seeds | validation wins | mean validation delta | max validation delta | mean test delta | action |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---|
| SI | 1 | qdesn_exal_rhs_ns_exact_chunked | graph_summary_mean | 2 | 3 | 2 | -0.133520 | 0.098492 | -1.671689 | do_not_promote |

This was not promotable because the maximum single-seed validation delta was
positive and above the gate tolerance.  The result is useful evidence that SI
fold 1 may deserve later targeted work, not an authoritative replacement.

Other best-per-region rows also failed the validation gate:

| region | fold | best mean validation delta | validation win rate | recommended action |
|---|---:|---:|---:|---|
| BE | 3 | 0.327135 | 0.000000 | do_not_promote |
| HU | 3 | 0.583508 | 0.000000 | do_not_promote |
| LV | 1 | 0.055652 | 0.333333 | do_not_promote |
| NL | 3 | 0.729938 | 0.000000 | do_not_promote |
| PL | 1 | 0.391646 | 0.000000 | do_not_promote |
| RO | 3 | 0.195805 | 0.000000 | do_not_promote |
| SE_4 | 3 | 0.210520 | 0.000000 | do_not_promote |
| SI | 1 | -0.133520 | 0.666667 | do_not_promote |

Only three seed-level rows improved validation against the Stage-J baseline:

| region | fold | experiment | method | validation delta | test delta |
|---|---:|---|---|---:|---:|
| LV | 1 | stagek_lv_f1_graphd2_summary_mean_seed20260625 | qdesn_al_rhs_ns_exact_chunked | -0.662705 | -1.268705 |
| SI | 1 | stagek_si_f1_graphd2_summary_mean_seed20260626 | qdesn_exal_rhs_ns_exact_chunked | -0.322898 | -1.836559 |
| SI | 1 | stagek_si_f1_graphd2_summary_mean_seed20260625 | qdesn_exal_rhs_ns_exact_chunked | -0.176153 | -1.428922 |

These isolated wins are not enough for promotion under the validation-stability
rule.

## Interpretation

Stage K answered the specific question it was designed to test: compact graph
summary channels do not produce a stable, validation-backed improvement over
the current Stage-J local/graph registry for this candidate pool.

The graph-summary design remains useful as infrastructure, but it should not be
treated as the next default PriceFM input policy.  The current authoritative
registry should remain unchanged.

## Recommended Next Step

Do not promote any Stage-K row.  The next high-value move is to keep the
current local/graph registry authoritative and plan a narrower targeted rescue
only for the few still-unresolved cases, with SI fold 1 and LV fold 1 as the
only Stage-K-informed candidates worth revisiting.  Any future graph-summary
relaunch should use a stricter design question, such as a targeted SI/LV-only
screen or a different neighbor regularization family, rather than another broad
Stage-K repetition.

