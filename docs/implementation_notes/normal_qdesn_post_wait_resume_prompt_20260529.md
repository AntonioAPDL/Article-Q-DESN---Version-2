# Post-Wait Resume Prompt For Normal DESN And Q-DESN Integration

Date: 2026-05-29

## Purpose

This is the prompt to give Codex after the parallel Q-DESN mode work finishes
and the package repo is clean. It continues from the current Normal DESN and
Q-DESN progress without interfering with dirty package changes from another
active chat.

## Prompt

```text
We are continuing the Normal DESN and Q-DESN integration work after the
parallel Q-DESN comparison/hybrid work has finished.

Primary article repo:

/data/jaguir26/local/src/Article-Q-DESN

Article branch:
application-ensemble-likelihood-redesign

Package/shared validation repo:

/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

Package branch:
validation/shared-fitforecast-v2-1.0.0

Do not edit Overleaf/main:

/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514

First, synchronize and verify current state. Do not trust older commit hashes
until after fetch.

Read these article docs first:

- docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
- docs/implementation_notes/normal_qdesn_unified_comparison_contract_20260529.md
- docs/implementation_notes/normal_desn_end_to_end_roadmap_20260529.md
- docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
- docs/implementation_notes/normal_desn_source_median_comparison_20260529.md
- docs/implementation_notes/normal_desn_initialization_comparison_20260529.md
- docs/implementation_notes/qdesn_vb_modes_gap_analysis_todo_20260528.md
- docs/implementation_notes/qdesn_vb_implemented_modes_source_median_comparison_20260528.md

Part 0: Synchronize And Orient

1. Fetch and verify both repos:
   - branch
   - remote
   - HEAD
   - upstream
   - dirty/untracked state
   - stashes
   - latest origin state
   - recent git log

2. If the package repo is dirty, stop and report. Do not implement anything
   until the dirty state is understood and explicitly accepted.

3. Inspect package files:
   - R/qdesn_normal.R
   - R/qdesn_vb_warm_start.R
   - NAMESPACE
   - tests/testthat/test-qdesn-normal.R
   - tests/testthat/test-qdesn-normal-init-comparison.R
   - man/qdesn_normal.Rd
   - scripts/run_normal_desn_source_median_comparison_20260529.R
   - scripts/run_normal_desn_init_comparison_20260529.R
   - any final Q-DESN implemented-mode comparison scripts.

Part 1: Baseline Test Freeze

Before package edits, run focused tests:

cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-warm-start.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'

Stop if any baseline test fails.

Part 2: Implement Normal DESN Warm-Start Metadata

Implement the contract in:

docs/implementation_notes/normal_desn_warm_start_contract_20260529.md

Scope:

- Normal DESN warm-start object only.
- No new posterior target.
- No Q-DESN engine changes.
- No changes to exAL engine/config files.
- No article application adapter.

Required package API:

qdesn_normal_make_warm_start()
qdesn_normal_validate_warm_start()
qdesn_normal_warm_start_to_vb_init()
qdesn_normal_warm_start_to_mcmc_init()

Implementation requirements:

- support qdesn_normal_fit and normal_desn_readout inputs;
- record beta mean/cov and omega2 posterior;
- record target label and exact/approximate status;
- record prior family and RHS/RHS_NS state if available;
- record design hash and feature settings hash when available;
- record package SHA and package version;
- validate design mismatch, feature mismatch, beta dimension, covariance
  positive-definiteness, finite numeric state, omega positivity, and optional
  package SHA;
- conversion helpers must preserve source metadata;
- existing qdesn_normal_to_vb_init() and qdesn_normal_to_mcmc_init() behavior
  must remain unchanged.

Suggested files:

- R/qdesn_normal.R or R/qdesn_normal_warm_start.R
- NAMESPACE
- tests/testthat/test-qdesn-normal-warm-start.R
- man/qdesn_normal.Rd

Part 3: Test Normal Warm Starts

Run:

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-warm-start.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-warm-start.R")'

Run git diff checks:

git diff --check

Commit package change:

Add Normal DESN warm-start metadata

Part 4: Update Article Docs

Update:

- docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
- docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
- docs/implementation_notes/normal_desn_end_to_end_roadmap_20260529.md

If only article docs changed, run:

cd /data/jaguir26/local/src/Article-Q-DESN
git diff --check

Commit article change:

Document Normal DESN warm-start metadata

Part 5: Final Unified Comparison

Only after package warm-start tests pass and both repos are clean, implement or
update a comparison harness following:

docs/implementation_notes/normal_qdesn_unified_comparison_contract_20260529.md

Use dataset:

/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500

Output generated results under:

results/normal_qdesn_unified_source_median_20260529/

Required generated files:

- repo_state.csv
- method_summary.csv
- prediction_metrics.csv
- exact_equivalence.csv
- approximate_diagnostics.csv
- target_changing_diagnostics.csv
- forbidden_modes.csv
- normal_qdesn_unified_comparison_summary.md
- console.log
- time.log

Do not commit large generated results.

Create tracked article summary:

docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md

Part 6: Validation

Before final comparison, rerun focused tests for every method class included in
the comparison. At minimum:

- Normal DESN tests;
- Normal warm-start tests;
- Q-DESN batching modes;
- exact chunking stats;
- inference config;
- subset tests;
- any hybrid exAL tests if hybrid exAL landed;
- any online/posterior-as-prior tests if those rows are included.

Record pass/fail counts in the article summary.

Part 7: Stop Gates

Stop and report if:

- either repo is dirty before implementation;
- package tests fail before changes;
- Normal warm-start validation cannot be made compatible with Q-DESN hashes;
- implementation requires touching exAL engine/config files;
- final comparison method rows cannot be labeled as exact, approximate,
  target-changing, workflow, or forbidden;
- exact chunking equivalence breaks;
- large generated result files would need to be committed;
- another process is writing the same result directory.

Part 8: Final Report

Report:

1. Repo status, branch, HEAD, and pushed commits for both repos.
2. Baseline tests before changes.
3. Normal warm-start API implemented.
4. Warm-start validation and conversion tests.
5. Package files changed.
6. Article docs changed.
7. Unified comparison dataset and command.
8. Methods compared.
9. Exact equivalence results.
10. Approximate diagnostics.
11. Target-changing diagnostics.
12. Runtime and memory.
13. Whether default behavior changed.
14. Whether generated results were committed.
15. Remaining gated work.

Be explicit that divide-and-combine VB and variational coresets remain deferred.
```

