# Phase163b inference-matched correction and closure

## Purpose

Phase163b is a no-new-compute correction to the Phase163 case-specific upper-tail Joint exQDESN screening decision. The original Phase163 workers completed successfully, but the post-run promotion audit compared fresh VB/VB-LD candidates with Phase150 MCMC article rows. That comparison mixed inference procedures and made four regime-shift candidates appear eligible. The original audit also documented, but did not implement, a required improvement at `tau = 0.95`.

Phase163b does not refit a model, launch MCMC, or alter article assets. It reconstructs the decision from frozen, hash-verified artifacts using inference-matched Phase150 VB-LD comparators.

## Corrected contract

A Phase163 candidate can advance only if all of the following hold:

1. its exact Phase150 source candidate matches the frozen VB-LD benchmark;
2. all source and nested manifests verify, no worker failed, all metrics are finite, and fit/forecast contract crossings are zero;
3. aggregate forecast oracle MAE improves by at least `max(0.0025, 2.5%)` relative to Phase150 VB-LD;
4. forecast oracle MAE at `tau = 0.95` improves by at least `max(0.0025, 2.5%)`;
5. fit oracle MAE does not deteriorate by more than 5%;
6. forecast check loss and integrated grid CRPS do not deteriorate by more than 1%.

The aggregate and upper-tail improvements are simultaneous requirements. A tail-only gain cannot compensate for worse aggregate quantile-path recovery.

## Result

All 20 Phase163 candidates are implementation-clean, finite, hash-verified, and contract-noncrossing. None improves the corresponding Phase150 VB-LD aggregate forecast MAE. Consequently, zero candidates satisfy the corrected promotion contract and no Phase163 MCMC confirmation is authorized.

The best aggregate candidate in each scenario gives the following qualitative result:

| Scenario | Aggregate forecast MAE relative to Phase150 VB-LD | `tau = 0.95` result | Decision |
|---|---:|---:|---|
| Laplace bridge | slightly worse | small gain below the declared threshold | no promotion |
| Nonlinear reservoir-friendly | slightly worse | meaningful tail gain | no promotion |
| Normal bridge | materially worse | worse | no promotion |
| Regime shift | worse | worse | no promotion |
| Student-t location-scale | slightly worse | worse | no promotion |

The legacy count of four eligible candidates is therefore superseded. It reflected an MCMC-versus-VB comparison, not an improvement over the inference-matched VB calibration source.

## Artifacts

The default output is:

`application/cache/joint_qdesn_phase163b_corrected_closure_20260806`

It contains:

- source and nested-manifest verification;
- a complete Phase163 source inventory, including the three legacy audit files marked as superseded;
- inference-matched Phase150 VB-LD benchmarks;
- corrected candidate rankings and scenario winners;
- the explicit threshold table and per-candidate gate outcomes;
- the legacy-gate correction record;
- closed-direction and next-methodology readiness registries;
- the Phase163b assessment, provenance, README, and SHA-256 artifact manifest.

Generate the closure with:

```bash
Rscript application/scripts/215_close_joint_exqdesn_phase163b_corrected_audit.R
```

No model-fitting process is started by this command.

## Scientific decision and next boundary

Phase150 remains the article source of truth. The four scalar combined-control directions explored in Phase163 are closed for these five scenarios, and longer MCMC cannot rescue a VB specification that did not pass the inference-matched calibration gate.

A future campaign should not repeat scalar `tau0`, slab-width, alpha-spread, slice-width, or chain-length screens already exhausted in Phases149--163. Before any new compute, a separate methodology audit must define and test one genuinely new control with a common VB-LD/MCMC posterior target. Plausible directions are quantile-specific alpha prior scales or an explicit sampled-gamma regularization contract. Quantile-specific composite weighting is a deeper objective change and requires theory and score-alignment justification first.
