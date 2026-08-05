# PriceFM Stage-R34 Lean Capacity/History Closeout Plan

Date: 2026-07-28

## Objective

Stage-R34 is the guarded closeout for the 480-experiment Stage-R33 run. It
selects a separate specification for each of the 20 region/fold cases using
validation AQL only, then uses test metrics strictly as a post-selection audit
against the current authoritative Q-DESN result and cached PriceFM.

The stage is PriceFM-only and read-only with respect to fitted runs. It does not
fit models, invoke the experiment launcher, mutate the registry, update an
article or manuscript, launch full-quantile work, or launch MCMC.

## Why This Is the Correct Next Step

Stage-R33 is still running. A second broad experiment would compete for
resources and would be scientifically premature because ten target cases have
not yet produced evidence. The required next action is therefore to let R33
continue and prepare a closeout that cannot consume partial results as final
evidence.

The closeout answers three distinct questions:

1. Did all 480 Stage-R33 experiments and launcher records finish cleanly?
2. Which candidate wins within each region/fold under validation-only
   selection?
3. After freezing those winners, does any winner beat both current Q-DESN and
   cached PriceFM on test?

## Implementation

- Script:
  `application/scripts/pricefm/158_closeout_pricefm_stage_r34_lean_capacity_history.py`
- Tests:
  `application/tests/test_pricefm_stage_r34_lean_capacity_history_closeout.py`
- Future output root:
  `application/data_local/pricefm/authoritative/pricefm_stage_r34_lean_capacity_history_closeout_20260728`

The script supports `--health-only true` for a non-materializing live check.
Finalization is fail-closed: it refuses to write closeout outputs until the
manifest, run directories, metric summaries, method rows, launcher status, and
exit code all prove a complete clean run.

## Reproducible Outputs

When and only when R33 is complete, Stage-R34 writes:

- completion audit;
- normalized AL/exAL metric rows;
- validation-selected case winners;
- test-oracle diagnostics marked non-selectable;
- case outcomes and validation-transfer gaps;
- full-quantile promotion queue;
- blocked MCMC confirmation queue;
- explicit decision gates;
- SHA-256 source manifest;
- JSON summary and Markdown report.

## Promotion Contract

A Stage-R33 candidate enters the full-quantile queue only when its
validation-selected case winner beats both current Q-DESN and cached PriceFM on
test. A test-oracle candidate cannot enter the queue.

Full-quantile work remains a separate launch requiring explicit authorization.
MCMC remains blocked until a candidate passes full-quantile validation-only
confirmation and reproducibility/hash checks. Registry and article mutation
remain blocked until confirmatory MCMC evidence is complete.

## Commands

Live health check:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/158_closeout_pricefm_stage_r34_lean_capacity_history.py \
  --health-only true
```

Final closeout after R33 completion:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/158_closeout_pricefm_stage_r34_lean_capacity_history.py
```

The second command is expected to refuse execution while R33 is incomplete.

## Validation

Validated with:

```bash
application/data_local/pricefm/venv/bin/python -m py_compile \
  application/scripts/pricefm/158_closeout_pricefm_stage_r34_lean_capacity_history.py \
  application/tests/test_pricefm_stage_r34_lean_capacity_history_closeout.py

application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r34_lean_capacity_history_closeout.py
```

Result: `2 passed`.

The live `--health-only true` check reported 213 of 480 experiments complete
and 267 remaining. A live finalization attempt exited nonzero with the expected
incomplete-run error and created no Stage-R34 output directory. Stage-R33
remained active with 16 concurrent experiments.

## 2026-08-03 R33A Repair Reconciliation Addendum

The base launcher subsequently ended with 456 successful experiments and 24
failed experiments. All failures are the same `SE_1` fold-3 case and stopped
before model fitting because the requested horizon-weight expansion was 6.5
while `max_expansion_factor` was 6. This is an orchestration/resource-guard
failure, not an observed model-performance result.

R34 now requires two immutable launch ledgers:

1. the original 480-row R33 ledger, whose 24 failed IDs must exactly match the
   R33A repair manifest; and
2. the separate 24-row R33A ledger, whose IDs must all complete with return
   code zero.

The effective 480-row completion state is assembled from the 456 successful
base rows plus the 24 successful repair rows. R34 refuses to materialize if an
ID is missing, duplicated, substituted, or repaired outside `SE_1` fold 3, or
if either launcher exit file is absent/nonzero. The original R33 YAML and
`launch_status.csv` are not rewritten.
