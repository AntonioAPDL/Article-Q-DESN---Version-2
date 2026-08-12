# PriceFM operational public-architecture full-shot campaign

Date: 2026-08-12

## Objective

Reproduce the public PriceFM Phase-I/Phase-II graph-gated architecture on the
fold-aligned 365-day PriceFM surface used by the current Q-DESN decision
registry. The campaign supplies a reproducible operational benchmark. It does
not claim to reproduce the paper's unpublished Table 4 ensemble protocol.

## Evidence and frozen inputs

- Raw `FINAL.csv` SHA-256:
  `98f596deba7ffaf0edd21e78e1a779256ab24dda5463d445f081e1ee4ab3a54a`.
- Upstream PriceFM commit:
  `c72d1228bde80417d5cc782521328e02ab5401c3`.
- Q-DESN comparison registry SHA-256:
  `d45c43b6d2dd3b163ca1d3cd0b140ce0e582797aaea0a3db012a7d74293e4802`.
- Calendar: fixed-CET normalization, `market_time = time_utc + 1 hour`.
- Folds: three train/validation/test folds from
  `application/config/pricefm_data_pipeline.yaml`.
- Windows: 96 lag quarters and 96 forecast quarters; seven manuscript
  quantiles; train-only per-region robust scaling.

Preparation regenerates numeric windows in the pinned TensorFlow environment
and checks them against the existing 342 reference window files at tolerance
`1e-6`. Scalers are regenerated rather than loading a version-drifted joblib
object.

## Model and search contract

- Public `build_graph_gated_quantile_model` architecture.
- Embedding width 168, four experts, 341,044 trainable parameters.
- Phase I: three seeds per fold, 50 epochs, validation-only initializer
  selection by equal-region mean AQL.
- Phase II: 20 epochs for every unique target-region graph mask.
- Public graph: 38 nodes and 65 undirected non-self edges.
- Public degrees 0 through 10 yield 1,254 nominal region-fold arms, but only
  1,047 unique masks. Duplicate degrees are aliases and are not refit.
- Primary selector: independent region-fold validation winner for all 114
  cells.
- Sensitivity selector: one graph degree per region selected across folds.
- Stability gate: if the best two validation candidates are within one percent,
  Phase-II candidates receive two additional deterministic seeds. The maximum
  is 456 extra fits.

The winner manifests and their SHA-256 hashes are frozen before any test window
is loaded. Test scoring is implemented in a separate script.

## Promotion gate

The read-only closeout compares operational PriceFM with both current
authoritative Q-DESN and cached PriceFM for each region-fold row. A row enters a
future promotion queue only when the operational candidate beats both. The
campaign cannot mutate a registry or article file.

## Scheduling and resource safety

`197_launch_pricefm_operational_campaign.py` is a restartable scheduler with a
single-owner lock and atomic health JSON. It waits until all of these gates pass:

- 20 whole physical cores have no logical sibling above 10 percent utilization;
- at least 128 GiB memory is available;
- at least 150 GiB disk is free;
- one-minute load is no more than 36.

It then runs exactly one model process per selected physical core, with 20
workers for stages containing at least 20 tasks. BLAS, OpenMP, NumExpr, and
TensorFlow intra/inter-op thread counts are fixed to one. Phase I contains only
nine fits, so nine of the reserved cores are used there; Phase II and test
scoring use up to all 20. The scheduler resumes hash-valid completed rows and
retries a failed row once.

## Stage wiring

1. `190_prepare_pricefm_operational_fullshot.py`: sources, scaling, windows,
   graph masks, Phase-I manifest.
2. `191_run_pricefm_operational_fullshot_trial.py`: one validation-only fit.
3. `192_select_pricefm_operational_phase1.py`: freeze three fold initializers.
4. `193_prepare_pricefm_operational_phase2.py`: materialize 1,047 canonical
   Phase-II rows.
5. `194_select_pricefm_operational_winners.py`: bounded stability plan and
   frozen primary/sensitivity winners.
6. `195_score_pricefm_operational_test.py`: post-freeze test tasks and metrics.
7. `196_closeout_pricefm_operational_fullshot.py`: read-only dual-baseline
   decision ledger.
8. `197_launch_pricefm_operational_campaign.py`: resource-gated orchestration.

## Explicit exclusions

- No manuscript or article mutation.
- No Q-DESN registry mutation.
- No use of test metrics for model, seed, degree, or selector choice.
- No claim that cached Table 4 values are reproduced by this operational
  benchmark.
- No edits to GloFAS, joint-QDESN, validation, or other workstreams.
