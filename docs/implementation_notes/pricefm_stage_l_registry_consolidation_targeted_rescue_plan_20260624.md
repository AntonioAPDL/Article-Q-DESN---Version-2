# PriceFM Stage-L Registry Consolidation And Targeted Rescue Plan

Date: 2026-06-24

## Purpose

Stage K completed the regularized graph-summary median screen and produced no
promotable candidate.  The next move should not be another broad grid.  The
main risk now is registry drift: different local artifacts are being used for
median baselines, paper-quantile decisions, seed robustness, and Stage-K
summaries.  Stage K exposed this directly when the broad Stage-I authoritative
quantile registry contained `HU` fold 3 and `RO` fold 3 rows but had missing
median `selection_AQL` and `test_AQL` values for those rows.

Stage L therefore has two goals:

1. consolidate the current PriceFM decision surface into a reproducible,
   finite, auditable baseline;
2. only then run a narrow targeted rescue if the evidence is strong enough.

No Stage-L step should promote a row from test performance alone.

## Current Evidence

Authoritative tracked closeout:

```text
docs/implementation_notes/pricefm_stage_k_regularized_graph_run_closeout_20260623.md
```

Completed Stage-K materialized run:

```text
application/data_local/pricefm/runs/pricefm_stage_k_regularized_graph_20260623/
```

Stage-K multi-seed summary:

```text
application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623/
```

Stage-K facts:

| item | value |
|---|---:|
| experiments completed | 87/87 |
| window builds completed | 8/8 |
| geometry rows | 44 |
| missing metrics | 0 |
| promotable rows | 0 |

Best Stage-K geometry:

| region | fold | method | feature policy | graph degree | validation wins | mean validation delta | max validation delta | mean test delta | action |
|---|---:|---|---|---:|---:|---:|---:|---:|---|
| SI | 1 | `qdesn_exal_rhs_ns_exact_chunked` | `graph_summary_mean` | 2 | 2/3 | -0.133520 | 0.098492 | -1.671689 | do not promote |

Other isolated validation-improving seed rows:

| region | fold | experiment | validation delta | test delta |
|---|---:|---|---:|---:|
| LV | 1 | `stagek_lv_f1_graphd2_summary_mean_seed20260625` | -0.662705 | -1.268705 |
| SI | 1 | `stagek_si_f1_graphd2_summary_mean_seed20260626` | -0.322898 | -1.836559 |
| SI | 1 | `stagek_si_f1_graphd2_summary_mean_seed20260625` | -0.176153 | -1.428922 |

Interpretation:

- `SI` fold 1 is the only Stage-K row close enough to justify an expanded
  seed-stability check.
- `LV` fold 1 is test-helpful but validation-unstable.  It should be treated as
  a diagnostic, not a promotion candidate.
- `graph_summary_mean_std` and broad regularized graph summaries do not deserve
  another broad launch from the current evidence.

## Critical Assessment

### Is another broad graph-summary grid optimal?

No.  Stage K already ran 87 experiments across the intended unstable cases and
returned zero promotable geometries.  Repeating or broadening the same family
would likely spend compute on variance rather than new signal.

### Is immediate seven-quantile promotion optimal?

No.  The only near-miss, `SI` fold 1, failed the predeclared validation gate
because one seed had a positive validation delta.  Promotion before expanded
seed evidence would violate the current validation-first protocol.

### Is registry consolidation necessary before more modeling?

Yes.  The completed Stage-K summary had to use the Stage-J priority-0 closeout
registry rather than the broader Stage-I authoritative quantile registry
because the latter has missing median baseline fields for some Stage-K rows.
Future scripts need a single current baseline with finite selection/test fields
and explicit provenance.

### Is targeted SI/LV work justified?

Partly.  `SI` fold 1 has enough validation evidence for a focused seed
expansion.  `LV` fold 1 does not; it should only receive diagnostics unless the
validation/test split investigation shows a clear selection mismatch that can
be addressed without peeking at test.

## Stage-L Checklist

### L0. Synchronize And Freeze State

- [ ] Verify branch, remote, HEAD, dirty state, and latest origin.
- [ ] Confirm Stage-K run outputs are complete:
  - [ ] `launch_status.csv` has 95 completed rows;
  - [ ] 87 `metric_summary.csv` files exist;
  - [ ] 87 `adapter_manifest.json` files exist;
  - [ ] no Stage-K fit processes remain.
- [ ] Confirm generated artifacts remain under ignored
      `application/data_local/pricefm/`.
- [ ] Confirm no large `.rds`, `.rda`, `.RData`, or `.rdata` artifacts remain
      in Stage-K run roots.

Recommended checks:

```sh
git status --short --branch
git diff --check

python3 - <<'PY'
import csv
from collections import Counter
p = "application/data_local/pricefm/experiment_grids/pricefm_stage_k_regularized_graph_20260623/launch_status.csv"
with open(p) as f:
    rows = list(csv.DictReader(f))
print(len(rows), Counter(r["status"] for r in rows), Counter(r["kind"] for r in rows))
PY

find application/data_local/pricefm/runs/pricefm_stage_k_regularized_graph_20260623 \
  \( -name '*.rds' -o -name '*.rda' -o -name '*.RData' -o -name '*.rdata' \) -print
```

### L1. Build A Current Decision Surface

Create a local ignored baseline package, for example:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_current_decision_surface_20260624/
```

It should include:

- [ ] `current_median_registry.csv`
- [ ] `current_quantile_decision_registry.csv`
- [ ] `registry_health.csv`
- [ ] `baseline_paths.json`
- [ ] `current_decision_surface_report.md`

Baseline inputs:

| role | path |
|---|---|
| current median registry | `application/data_local/pricefm/authoritative/pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/patched_selection_registry.csv` |
| current paper-quantile decision registry | `application/data_local/pricefm/authoritative/pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623/authoritative_quantile_decision_registry.csv` |
| Stage-J closeout baseline for Stage-K candidates | `application/data_local/pricefm/authoritative/pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/rescue_closeout_decisions.csv` |
| Stage-K summary | `application/data_local/pricefm/authoritative/pricefm_stage_k_regularized_graph_multiseed_summary_20260623/multiseed_geometry_summary.csv` |

Validation criteria:

- [ ] all 42 region/fold rows have one current quantile decision row;
- [ ] current median rows have finite `selection_AQL` and `test_AQL`;
- [ ] paper-quantile decision rows have finite `local_AQL`, `pricefm_AQL`,
      and `delta_abs` where applicable;
- [ ] any intentionally missing median fields in the broad quantile registry
      are documented and resolved through the current median registry;
- [ ] duplicate `(region, fold)` keys fail early;
- [ ] all paths used in later scripts are recorded in `baseline_paths.json`.

Implementation note:

If a new helper is needed, prefer a small script such as:

```text
application/scripts/pricefm/65_validate_pricefm_current_decision_surface.py
```

Add focused tests for missing metrics, duplicate keys, non-finite values, and
path provenance.  Do not silently fill values from the wrong split or unit.

### L2. Harden Multi-Seed Summaries

The Stage-K summarizer worked after the correct registry was supplied, but its
failure mode repeated missing `(region, fold)` pairs many times.  Improve this
before future launches.

Target script:

```text
application/scripts/pricefm/62_summarize_pricefm_multiseed_median_screen.py
```

Checklist:

- [ ] report unique missing baseline keys, not one row per seed;
- [ ] fail early when current `selection_AQL` or `test_AQL` is non-finite;
- [ ] record `current_registry_csv` and a `current_registry_label` in
      `summary.json`;
- [ ] preserve validation-only promotion semantics;
- [ ] add tests for an incomplete broad registry and for a complete Stage-J
      closeout registry.

This is tooling hardening, not a modeling stage.

### L3. Decide Whether To Run A Targeted SI Fold 1 Seed Expansion

Only `SI` fold 1 is close enough to warrant a targeted launch.

Candidate geometry:

| field | value |
|---|---|
| region/fold | `SI` / `1` |
| method | `qdesn_exal_rhs_ns_exact_chunked` |
| feature policy | `graph_summary_mean` |
| graph degree | `2` |
| lag window | `96` |
| feature map | `window_reservoir_v1` |
| depth/units | `1` / `[120]` |
| alpha/rho | `0.5` / `0.9` |
| input scale | `0.350` |
| projection scale | `1.0` |
| tau0 | `0.001` |

Recommended seed expansion:

- [ ] reuse existing seeds `20260624`, `20260625`, `20260626` if present;
- [ ] add at least five new seeds, for example
      `20260627,20260628,20260629,20260630,20260631`;
- [ ] run only median first;
- [ ] use exact chunked RHS_NS fits;
- [ ] keep target-only guardrail optional but do not let it promote from test.

Suggested gate:

- [ ] validation win rate at least `0.75`;
- [ ] mean validation delta `< 0`;
- [ ] maximum validation delta `<= 0.05`;
- [ ] mean audit test delta `<= 0`;
- [ ] no single-seed audit test deterioration above `5%` relative;
- [ ] no non-finite metrics or convergence failures.

If this gate fails, stop and keep current registry unchanged.

### L4. Keep LV Fold 1 As Diagnostic Only

`LV` fold 1 had one validation-improving Stage-K seed but all Stage-K rows were
validation-unstable.  Test improvements alone are not enough.

Recommended work:

- [ ] produce a validation/test split diagnostic for LV fold 1;
- [ ] compare response scale, volatility, and level shifts across train,
      validation, and test windows;
- [ ] inspect whether the validation window is a poor proxy for test;
- [ ] do not launch a promotion grid for LV until the diagnostic defines a
      validation-clean objective.

Possible helper output:

```text
application/data_local/pricefm/authoritative/pricefm_stage_l_split_diagnostics_20260624/
```

### L5. Promote Only After The Median Gate

If and only if `SI` fold 1 passes the expanded seed gate:

- [ ] patch a one-row median registry for SI fold 1;
- [ ] launch seven PriceFM paper quantiles:
      `0.10,0.25,0.45,0.50,0.55,0.75,0.90`;
- [ ] summarize synthesized quantile predictions;
- [ ] compare against cached fold-aligned PriceFM Phase-I outputs;
- [ ] freeze a decision registry only if the local seven-quantile result beats
      or is close to PriceFM under the predeclared decision thresholds.

Relevant scripts:

```text
application/scripts/pricefm/45_patch_pricefm_median_registry_from_seedrob.py
application/scripts/pricefm/21_prepare_pricefm_quantile_grid_from_median_registry.py
application/scripts/pricefm/35_summarize_pricefm_region_panel_quantiles.py
application/scripts/pricefm/36_compare_pricefm_region_panel_quantiles.py
application/scripts/pricefm/53_freeze_pricefm_stage_c_quantile_decisions.py
application/scripts/pricefm/57_freeze_pricefm_authoritative_quantile_decisions.py
```

### L6. Freeze Or Explicitly No-Change

At the end of Stage L, create one of:

- `pricefm_stage_l_no_change_freeze_20260624`, if no candidate passes;
- `pricefm_stage_l_targeted_patch_20260624`, if one candidate passes all
  median and paper-quantile gates.

In either case, write a tracked closeout note with:

- [ ] exact commands;
- [ ] baseline registry path;
- [ ] candidates considered;
- [ ] gate outcomes;
- [ ] decision counts;
- [ ] whether the authoritative registry changed;
- [ ] where cached PriceFM comparisons were read from;
- [ ] cleanup status.

## What Not To Do Next

- Do not run another broad graph-summary grid.
- Do not promote from test-only improvements.
- Do not use the broad Stage-I authoritative quantile registry as a median
  baseline unless its missing median fields are resolved.
- Do not add more regions before the current decision surface is finite and
  auditable.
- Do not launch paper-quantile synthesis for Stage-K rows that failed the
  multi-seed median gate.

## Reproducibility Standards

For every launch:

- [ ] use explicit grid id and date-stamped output directories;
- [ ] set `OMP_NUM_THREADS=1`, `OPENBLAS_NUM_THREADS=1`,
      `MKL_NUM_THREADS=1`, `VECLIB_MAXIMUM_THREADS=1`,
      and `NUMEXPR_NUM_THREADS=1`;
- [ ] use `--resume true`;
- [ ] run a dry run before a real launch;
- [ ] store console and `/usr/bin/time -v` logs;
- [ ] write `launch_status.csv`;
- [ ] require complete metric files before summary;
- [ ] keep generated outputs under `application/data_local/pricefm/`;
- [ ] remove disposable `.rds`, `.rda`, `.RData`, and `.rdata` fit artifacts
      after metrics and figures are materialized.

## Tests And Checks

Minimum tests after tooling changes:

```sh
application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_k_summarizers.py \
  application/tests/test_pricefm_stage_j_information_set_rescue.py \
  application/tests/test_pricefm_desn_adapter_graph_summary.py \
  application/tests/test_pricefm_desn_adapter_graph_khop.py \
  application/tests/test_pricefm_graph.py
```

If a new Stage-L current-decision-surface validator is added, include a focused
test file such as:

```text
application/tests/test_pricefm_stage_l_current_decision_surface.py
```

Required git checks:

```sh
git diff --check
git status --short
```

## Stop Gates

Stop and report instead of launching more fits if:

- baseline registry fields are missing or non-finite;
- duplicate region/fold keys appear;
- Stage-K or Stage-L metric files are incomplete;
- a candidate only improves test but not validation;
- expanded seed results fail the predeclared gate;
- paper-quantile synthesis is required before median seed evidence exists;
- generated binary artifacts would need to be committed;
- a launch would interfere with unrelated GloFAS or validation jobs.

## Recommended Immediate Implementation Order

1. Implement and test the current decision-surface validator.
2. Harden the multi-seed summarizer failure messages and summary metadata.
3. Generate the Stage-L current decision surface.
4. Decide from that report whether to run the SI fold 1 expanded seed screen.
5. Run no paper-quantile promotion unless SI passes the expanded seed gate.

