# GloFAS richer-discrepancy campaign

This implementation turns the ignored scientific plan
`local_trackers/glofas_richer_discrepancy_desn_ultimate_plan_v2_20260826.md`
into a reproducible, discrepancy-first p50 campaign. FR09 remains authoritative.

The initial executable stage contains two cold controls, 15 geometry centers,
and four low-alpha health canaries. The reference block remains at FR09 while
the discrepancy reservoir varies. Every candidate uses the existing immutable
baseline contract, candidate-local configuration, reservoir preflight, one-core
worker, resumable scheduler, historical guardrails, and terminal cleanup.

Input sparsity is expressed as an expected fan-in target. For the first layer,
`pi_in = min(1, k / q)` with `q` equal to the actual lagged output/PPT/soil
input width. For later layers, `q` is the preceding reduced-state width. The
derived vector is written into every materialized candidate config and therefore
enters the existing design hash and provenance checks.

The initial stage uses `max_iter=150`, 20 single-threaded workers, a 50-iteration
global-scale freeze, and strict FR09 historical guards (3%, 3%, 5%, and 10% for
all, last-1000, last-200, and last-50 windows). A candidate cannot trigger a
full-seven-quantile run automatically. It must first improve p50 forecast check
loss by at least 5%, pass direct discrepancy diagnostics, survive cold/seed
confirmation, and receive a reviewed promotion decision.

CPU identifiers are frozen into the generated screening snapshot after a live
resource audit. They must be changed and the campaign regenerated if another
lane occupies any selected physical core before launch.

Preparation:

```bash
Rscript application/scripts/glofas_richer_discrepancy_prepare.R --authorize_launch true
```

The generated launch script and all run payloads live below the ignored
`local_trackers/runtime_configs/glofas_richer_discrepancy_initial_20260827`
root. Runtime artifacts must never be committed.
