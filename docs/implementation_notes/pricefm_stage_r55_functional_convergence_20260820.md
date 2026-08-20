# PriceFM Stage-R55 functional convergence and retention audit

## Objective

Stage R55 converts the completed R53/R54 collapsed-M0 evidence into a modern,
read-only inference diagnosis. It does not reopen model selection, use test
metrics to choose a new DESN specification, launch chains, mutate the PriceFM
registry, or modify article files.

R53 completed 2,436 chains for 87 case-specific exAL authority rows. R54 found
25 validation-selected collapsed-M0 bundles and 24 raw dual-reference test
wins, but no row passed the complete promotion contract. Every case failed the
classical scalar convergence gate, while lower-quantile validation harm and
chain-level prediction dispersion eliminated additional near-misses.

## Diagnostic contract

`187_audit_pricefm_stage_r55_functional_convergence.py` consumes only frozen
R53/R54 artifacts and computes:

- split rank-normalized and folded R-hat;
- rank-normalized bulk ESS and 5/95-percent tail ESS;
- scalar Monte Carlo standard errors;
- fixed chain-group prediction-path NRMSE;
- fixed chain-group AQL differences and four-chain spread;
- one case-level triage row for each of the 87 exAL authority cases.

The diagnostic comparison surface is frozen to rows that were selected on
validation and later beat both authoritative Q-DESN and cached PriceFM on the
test audit. Test values remain audit-only. A bounded confirmation-design row
additionally requires the pre-existing R54 validation harm guard and authority
replay gate. No R55 output authorizes a launch.

## Budget interpretation

R53 used 500 warmup and 500 retained draws per chain. That budget is far below
the established independent collapsed-M0 confirmation contract of 5,000
warmup and 20,000 retained draws. R55 therefore distinguishes numerical
correctness from confirmatory convergence. It records both the established
budget and a linear ESS projection, but does not silently lengthen or rerun any
chain.

Before a confirmation launch can be materialized, a separate capability audit
must establish whether exact sampler state can be checkpointed and resumed.
The R53 compact posterior payload contains beta and scalar draws but not the
full latent final state, so it is not an exact continuation checkpoint.

## Retention contract

R55 inventories storage without deleting files. It retains:

- R54 decisions, diagnostics, metrics, report, and hashes;
- R51--R53 manifests and orchestration provenance;
- all compact chain summaries, scalar draws, prediction means, logs, and
  ownership records;
- full posterior and case artifacts for any bounded confirmation target.

Noncandidate beta-draw payloads and regenerable case adapters/initializations
are marked `cleanup_review`, never `delete`. Cleanup requires a reviewed frozen
handoff and an explicit later authorization.

## Outputs

- `pricefm_stage_r55_modern_scalar_diagnostics.csv`
- `pricefm_stage_r55_functional_stability.csv`
- `pricefm_stage_r55_case_triage.csv`
- `pricefm_stage_r55_confirmation_design.csv`
- `pricefm_stage_r55_retention_inventory.csv`
- `pricefm_stage_r55_retained_evidence_hashes.csv`
- `summary.json`
- `source_manifest.json`
- `pricefm_stage_r55_functional_convergence_report.md`

There is deliberately no launch YAML, registry mutation, cleanup action, or
article mutation.
