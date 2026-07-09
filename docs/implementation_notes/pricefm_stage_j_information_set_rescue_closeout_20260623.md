# PriceFM Stage-J Information-Set Rescue Closeout

Date: 2026-06-23

## Scope

Stage J tested whether changing the input information set could rescue the
remaining weak PriceFM region-fold cases after the Stage-I unresolved closeout.
The stage used graph-neighbor and target-only guardrail variants, but kept the
selection protocol conservative:

- median-only screening first;
- validation AQL for selection;
- audit test metrics for risk labels only;
- seed robustness before any median-registry patch;
- seven-paper-quantile promotion only after seed robustness.

No paper-quantile promotion or authoritative registry freeze is valid unless a
median candidate first passes the seed-robustness gate.

## Setup

Tracked setup commits:

- `76b1796 Plan PriceFM Stage-J information-set rescue`
- `bd7525b Prepare PriceFM Stage-J information-set rescue`

Primary local execution plan:

```text
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/stage_j_next_stage_execution_plan_20260623.md
```

That file is intentionally under `application/data_local/`, which is ignored by
git, because it is an execution checklist tied to local generated artifacts.

## Priority-0 Median Screen

Inputs:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_20260623.yaml
application/data_local/pricefm/experiment_grids/pricefm_stage_j_information_set_rescue_20260623/manifest.csv
application/data_local/pricefm/runs/pricefm_stage_j_information_set_rescue_20260623
```

Launch:

```sh
tmux new-session -d -s pricefm_stage_j_p0_20260623 \
  "cd /data/jaguir26/local/src/Article-Q-DESN; \
   export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
          VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; \
   /usr/bin/time -v \
     -o application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_plan_20260623/priority0_launch.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
       --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_20260623.yaml \
       --priorities 0 \
       --experiment-jobs 18 \
       --cell-jobs 1 \
       --build-windows true \
       --resume true \
       --dry-run false \
     > application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_plan_20260623/priority0_launch.console.log 2>&1"
```

Results:

| quantity | value |
|---|---:|
| experiments | 105/105 |
| window builds | 22/22 |
| exit status | 0 |
| wall time | 2:36:54 |
| max RSS | 2,047,208 KB |
| missing metric files | 0 |
| retained `.rds`, `.rda`, `.RData`, `.rdata` artifacts | 0 |

Closeout output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623
```

Closeout command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/42_closeout_pricefm_graph_local_rescue.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_j_information_set_rescue_20260623/manifest.csv \
  --run-root application/data_local/pricefm/runs/pricefm_stage_j_information_set_rescue_20260623 \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/patched_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623 \
  --priority 0 \
  --robustness-seeds 20260624,20260625,20260626
```

Decision counts:

| closeout label | rows |
|---|---:|
| robustness_candidate | 2 |
| validation_candidate_audit_worse | 3 |
| validation_overfit_warning | 3 |
| keep_current | 1 |

Registry-level audit:

| scenario | mean median test AQL | median median test AQL | mean selection AQL |
|---|---:|---:|---:|
| current authoritative | 10.6319 | 9.7880 | 10.6658 |
| hypothetical validation-selected rescue | 10.7349 | 9.8053 | 10.5399 |
| hypothetical robustness-candidates only | 10.6264 | 9.7880 | 10.6612 |

The validation-selected rescue was not safe as a whole: it improved validation
selection AQL but worsened audit test AQL. The only candidates eligible for
seed robustness were `NL` fold 3 and `RO` fold 3.

## Priority-0 Fold Decisions

| region | fold | best candidate | method | validation delta | audit test delta | closeout label | action |
|---|---:|---|---|---:|---:|---|---|
| BE | 3 | `stagej_be_f3_graphd1_alpha_low` | `qdesn_exal_rhs_ns_exact_chunked` | -0.0108 | +0.0197 | validation candidate, audit worse | keep current |
| HU | 3 | `stagej_hu_f3_graphd2_d1_capacity` | `qdesn_al_rhs_ns_exact_chunked` | -0.0591 | +0.8635 | validation overfit warning | keep current |
| LV | 1 | `stagej_lv_f1_graphd2_input_low` | `qdesn_al_rhs_ns_exact_chunked` | -1.7288 | +2.4943 | validation overfit warning | keep current |
| LV | 2 | `stagej_lv_f2_graphd2_base` | `qdesn_exal_rhs_ns_exact_chunked` | +0.7797 | +0.7103 | keep current | keep current |
| NL | 3 | `stagej_nl_f3_graphd2_alpha_low` | `qdesn_exal_rhs_ns_exact_chunked` | -0.0729 | -0.1833 | robustness candidate | seedrob |
| PL | 1 | `stagej_pl_f1_graphd1_d1_capacity` | `normal_rhs_ns` | -0.5246 | +0.0797 | validation candidate, audit worse | keep current |
| RO | 3 | `stagej_ro_f3_graphd2_alpha_low` | `qdesn_exal_rhs_ns_exact_chunked` | -0.1191 | -0.0453 | robustness candidate | seedrob |
| SE_4 | 3 | `stagej_se4_f3_graphd1_alpha_low` | `qdesn_exal_rhs_ns_exact_chunked` | -1.0208 | +0.2669 | validation candidate, audit worse | keep current |
| SI | 1 | `stagej_si_f1_graphd2_input_low` | `qdesn_exal_rhs_ns_exact_chunked` | -1.7526 | +0.8331 | validation overfit warning | keep current |

## Seed-Robustness Grid

Seedrob config:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_seedrob_20260623.yaml
```

Seedrob run root:

```text
application/data_local/pricefm/runs/pricefm_stage_j_information_set_rescue_seedrob_20260623
```

Seedrob summary:

```text
application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_seedrob_summary_20260623
```

Grid preparation:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/43_prepare_pricefm_graph_local_rescue_seed_grid.py \
  --source-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_20260623.yaml \
  --seed-plan-csv application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/robustness_seed_plan.csv \
  --output-grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_seedrob_20260623.yaml \
  --grid-id pricefm_stage_j_information_set_rescue_seedrob_20260623 \
  --generated-root application/data_local/pricefm/experiment_grids/pricefm_stage_j_information_set_rescue_seedrob_20260623 \
  --run-root application/data_local/pricefm/runs/pricefm_stage_j_information_set_rescue_seedrob_20260623 \
  --summary-output application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_seedrob_prepare_20260623/prepare_summary.json \
  --priority 0 \
  --candidate-source stage_j_information_set_rescue_seedrob_20260623
```

Preparation output:

| quantity | value |
|---|---:|
| experiments | 6 |
| candidates | 2 |
| seeds | 20260624, 20260625, 20260626 |
| regions | NL, RO |
| folds | 3 |

Seedrob launch:

```sh
tmux new-session -d -s pricefm_stage_j_seedrob_20260623 \
  "cd /data/jaguir26/local/src/Article-Q-DESN; \
   export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
          VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1; \
   /usr/bin/time -v \
     -o application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_seedrob_prepare_20260623/seedrob_launch.time.log \
     application/data_local/pricefm/venv/bin/python \
     application/scripts/pricefm/13_run_desn_experiment_grid.py \
       --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_j_information_set_rescue_seedrob_20260623.yaml \
       --experiment-jobs 6 \
       --cell-jobs 1 \
       --build-windows true \
       --resume true \
       --dry-run false \
     > application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_seedrob_prepare_20260623/seedrob_launch.console.log 2>&1"
```

Seedrob launch results:

| quantity | value |
|---|---:|
| experiments | 6/6 |
| window builds | 2/2 |
| exit status | 0 |
| wall time | 1:19.20 |
| max RSS | 993,544 KB |
| run-root size | 251 MB |
| missing metric files | 0 |
| retained `.rds`, `.rda`, `.RData`, `.rdata` artifacts | 0 |

Seedrob summary command:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/44_summarize_pricefm_graph_local_rescue_seedrob.py \
  --manifest-csv application/data_local/pricefm/experiment_grids/pricefm_stage_j_information_set_rescue_seedrob_20260623/manifest.csv \
  --current-registry-csv application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/patched_selection_registry.csv \
  --output-dir application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_seedrob_summary_20260623 \
  --min-validation-win-rate 1.0 \
  --max-mean-test-delta 0.0 \
  --max-test-rel-deterioration 0.05
```

Gate:

- minimum validation win rate: 1.0
- maximum mean test AQL delta: 0.0
- maximum single-seed test relative deterioration: 0.05

## Seedrob Results

| region | fold | source candidate | seeds | validation wins | validation win rate | test wins | mean validation delta | mean test delta | max test relative delta | pass | action |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| NL | 3 | `stagej_nl_f3_graphd2_alpha_low` | 3 | 0 | 0.0000 | 1 | +0.0519 | -0.0185 | +0.0056 | no | keep current |
| RO | 3 | `stagej_ro_f3_graphd2_alpha_low` | 3 | 1 | 0.3333 | 2 | +0.1150 | -0.0037 | +0.0205 | no | keep current |

Seed-level details:

| region | fold | seed | validation delta | test delta | validation improved | test improved |
|---|---:|---:|---:|---:|---|---|
| NL | 3 | 20260624 | +0.0219 | +0.0473 | no | no |
| NL | 3 | 20260625 | +0.0102 | +0.0028 | no | no |
| NL | 3 | 20260626 | +0.1236 | -0.1055 | no | yes |
| RO | 3 | 20260624 | +0.2596 | -0.1932 | no | yes |
| RO | 3 | 20260625 | +0.2045 | +0.2274 | no | no |
| RO | 3 | 20260626 | -0.1191 | -0.0453 | yes | yes |

Neither candidate passed seed robustness. Both had negative mean audit test
delta, but neither was validation-stable. Under the validation-clean protocol,
test improvement without validation stability is not enough to patch the median
registry.

## Final Decision

Stage J does not change the authoritative registry.

No median registry patch was created, no seven-paper-quantile promotion was
launched, and no Stage-J authoritative registry was frozen. This is the correct
stop under the predeclared gate because `n_promotion_ready = 0`.

The current authoritative registry remains:

```text
application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623/authoritative_quantile_decision_registry.csv
```

The current median registry remains:

```text
application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/patched_selection_registry.csv
```

## Interpretation

Stage J answered an important question: graph information-set refinement can
produce isolated median improvements, but the two apparently safe priority-0
candidates were not stable across seeds under the validation-selection metric.

This reinforces the central Stage-I/Stage-J lesson:

- validation-only wins are common;
- many validation wins do not transfer to the audit split;
- even candidates that improve audit test once can fail validation stability;
- the conservative seedrob gate is necessary before paper-quantile promotion.

The strongest diagnostic signal is not "launch more of the same." The stronger
signal is that the unresolved rows need a different selection/representation
diagnostic before additional broad compute:

1. inspect why graph input expansions overfit validation for `HU-3`, `LV-1`,
   `SI-1`, `SE_4-3`, and `PL-1`;
2. compare validation/test period properties for the unresolved folds;
3. consider a multi-seed validation criterion directly in the median screen
   rather than after candidate selection;
4. consider smaller graph summaries or regularized neighbor aggregates instead
   of wider raw graph-khop inputs;
5. keep the current Stage-I authoritative registry as the stable baseline.

## Validation And Hygiene

Artifact checks:

- Priority-0 retained R binary artifacts: 0
- Seedrob retained R binary artifacts: 0
- Seedrob missing metric files: 0
- Seedrob launch exit status: 0

Tracked documentation was updated only after local generated outputs completed.
Generated PriceFM outputs remain under `application/data_local/` and are not
committed.

## Recommended Next Stage

Do not run Stage-J priority 1 immediately.

The best next stage is a smaller diagnostic design, not a broader sweep:

1. Build an unresolved-fold diagnostic report comparing validation and audit
   windows for the rows where graph expansion overfit.
2. Add a median-screen option that evaluates two or three seeds per candidate
   before closeout, so seed instability is detected earlier.
3. Test graph-neighbor summary features, for example mean/min/max or weighted
   neighbor summaries, instead of only wider graph-khop raw input expansion.
4. Relaunch only after those diagnostics specify a smaller candidate pool.

That stage should preserve the same final gates: validation-clean median
selection, seed robustness, seven-paper-quantile synthesis, cached PriceFM
comparison, and explicit authoritative registry freezing only after local wins.
