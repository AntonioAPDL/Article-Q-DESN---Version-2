# PriceFM Stage-R Selection Diagnostics Closeout

Date: 2026-06-27

## Purpose

Stage R is a diagnostic-only closeout after the Stage-Q near-miss refinement.
It does not fit any DESN/Q-DESN model, does not mutate the Stage-M article
decision surface, and does not write launch grids.  Its role is to turn the
existing Stage-M/N/O/P/Q run history into a reproducible failure-mode map before
spending compute on a new search.

The implementation is:

```text
application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py
application/tests/test_pricefm_stage_r_selection_diagnostics.py
```

The local ignored output directory is:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r_selection_diagnostics_20260627/
```

## Command

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py
```

The script records a SHA-256 input manifest and writes compact CSV/Markdown/JSON
diagnostics under the ignored output directory.  It deliberately does not write
any YAML launch configuration.

## Inputs

Stage R consumes these already-produced authoritative artifacts:

| Stage | Input role |
|---|---|
| Stage M | Current 42-row article decision surface, validation/test alignment, and split diagnostics |
| Stage N | Underperformance closeout, validation-selected rows, instability audit, and horizon-block gaps |
| Stage O | Selection-rule audit and selected rows by validation-only rule |
| Stage P | Seven-paper-quantile competitiveness flags |
| Stage Q | Near-miss refinement closeout, transfer diagnostics, validation-selected rows, test-oracle audit rows, and horizon diagnostics |

The generated `stage_r_input_manifest.csv` is the authoritative local record of
paths, row counts, column counts, and file hashes.

## Health

| Check | Result |
|---|---:|
| Stage-M rows | 42 |
| Candidate transfer rows harmonized | 210 |
| Diagnostic only | TRUE |
| Writes launch configs | FALSE |
| Stage-M surface changed | FALSE |
| Stage-Q run clean | TRUE |
| Stage-Q priority-1 launch recommended | FALSE |

## Selection Transfer

| Source | Rows | Region/folds | Test win rate | PriceFM win rate | Disagree rate | Mean test delta vs PriceFM | Mean Spearman validation/test rank |
|---|---:|---:|---:|---:|---:|---:|---:|
| Stage M alignment | 104 | 9 | 0.423 | 0.000 | 0.394 | NA | 0.383 |
| Stage N validation-selected | 17 | 17 | 0.412 | 0.000 | 0.412 | 3.008 | NA |
| Stage O selection-rule rows | 68 | 17 | 0.412 | 0.000 | 0.412 | 3.069 | -0.094 |
| Stage Q validation-selected | 2 | 2 | 0.000 | 0.000 | 0.000 | 2.085 | NA |
| Stage Q test-oracle audit | 2 | 2 | 0.000 | 0.000 | 0.000 | 1.666 | NA |

The core finding is unchanged from the Stage-Q closeout: validation-only
selection is not transferring reliably enough to justify a larger search in the
same family.  Test metrics remain audit-only and are not used for promotion.

## Information-Set Parity

| Information set | Rows | Q-DESN wins | Win rate | Mean delta AQL | Median delta AQL |
|---|---:|---:|---:|---:|---:|
| PriceFM graph inputs | 27 | 20 | 0.741 | -0.719 | -0.677 |
| Target only | 15 | 5 | 0.333 | 0.377 | 0.315 |

This split is the main actionable signal.  The current target-only rows are much
less competitive than rows where the Q-DESN input vector already includes the
PriceFM graph information set.  A future search should therefore prioritize
graph-parity input construction for target-only underperformers, rather than
blindly increasing reservoir capacity everywhere.

## Failure Modes

Stage R assigns one primary failure mode per region/fold.

| Failure mode | Count | Action |
|---|---:|---|
| `no_action` | 25 | Keep the current Stage-M row; it already beats cached PriceFM. |
| `graph_parity_gap` | 10 | Candidate Stage-S graph-parity targeted grid after review. |
| `late_horizon_gap` | 3 | Candidate Stage-S horizon-block selection pilot after review. |
| `pricefm_far_ahead` | 2 | Defer; existing rescue stages did not close comparable gaps. |
| `selection_instability` | 2 | No launch; Stage-Q showed near-zero validation/test transfer. |

Candidate Stage-S priority-0 rows after review:

| Action | Region/fold rows |
|---|---|
| Graph-parity targeted grid | LT-1, FI-1, AT-3, SE_4-1, PL-3, LV-1, SI-1, PL-1, LV-2, SE_4-3 |
| Horizon-block selection pilot | RO-3, HU-3, BE-3 |

Rows explicitly not eligible for the next launch:

| Reason | Region/fold rows |
|---|---|
| Stage-Q instability | RO-1, NL-3 |
| PriceFM far ahead | HU-2, SK-3 |
| Current selected row already beats PriceFM | all 25 current-win rows |

## Decision

Stage R is complete and supports a conservative decision:

1. Do not launch Stage-Q priority 1.
2. Do not mutate the Stage-M article decision surface.
3. Do not promote any Stage-Q row.
4. Use Stage-R as the gate for a future Stage-S only after review.
5. Stage-S, if authorized, should be a small diagnostic launch focused on
   graph-parity target-only rows and horizon-block selection pilots, not another
   broad capacity-only sweep.

## Validation

Focused validation:

```sh
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py

application/data_local/pricefm/venv/bin/python -m pytest \
  application/tests/test_pricefm_stage_r_selection_diagnostics.py -q
```

The test file checks:

- normal diagnostic output generation;
- no launch configuration writes;
- missing-input failure;
- duplicate region/fold failure;
- non-finite metric failure;
- expected assignment of graph-parity, selection-instability, and no-action
  failure modes on a synthetic 42-row fixture.

## Remaining Work

The next implementation stage should not fit models automatically.  It should
first build a Stage-S candidate manifest from this diagnostic output with
explicit authorization gates, row-level rationale, expected cost, and an
artifact-cleaning contract.
