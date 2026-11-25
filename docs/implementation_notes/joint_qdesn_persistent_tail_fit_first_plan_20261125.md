# JOINT persistent-heavy-tail fit-first continuation

Date: 2026-11-25

## Decision addressed

The frozen V3 campaign selected a one-layer 48-state model because its mean
realized aCRPS was 0.43% below a three-layer 64-state alternative. The selected
model's fit MAE was approximately 0.198, compared with 0.068 for the layered
alternative and 0.059 for the exact V2 fallback. This continuation corrects
that decision rule without rewriting V3, using article outcomes, or rerunning
18,612 completed discovery workers.

## Frozen scientific contract

- Scenario: `persistent_heavy_tail` only.
- Source: all ten architectures that reached the V3 outer-tail stage.
- Data: five fresh internal fixtures disjoint from V3 discovery, V3 sealed
  confirmation, and the article fixture.
- Validation: teacher forcing between ten rolling origins and recursive
  multi-step forecasting within each origin.
- Readout: intercept plus all reservoir layers; no raw input in the readout.
- Forecast score: origin-marginal DGP-integrated finite-grid aCRPS from eight
  independent 4,096-path oracle shards per fixture.
- Fit competence: training quantile-path MAE, outer-tail MAE, and
  teacher-forced horizon-one quantile-path MAE.

## Selection order

1. Reject nonfinite outputs, nonfinite recursive states, provenance failures,
   and nonzero post-contract crossings.
2. Retain only candidates within frozen absolute/relative margins of the best
   fit, horizon-one fit, and outer-tail fit.
3. Rank fit-eligible candidates by origin-marginal DGP-integrated aCRPS.
4. Within the frozen 1% or 0.005 aCRPS near-tie region, require acceptable
   horizons 1--5 and select the stronger fit.
5. Freeze and stop. A separate four-model AL/exAL, joint/independent VB/MCMC
   confirmation is authorized only by the resulting decision. Every exAL MCMC
   fit in that later stage must use exact M0.

The final article fixture is never materialized by this lane. Realized aCRPS,
raw crossings, convergence flags, and horizon summaries remain visible but do
not override the fit-competence gate. Scalar mixing is a review diagnostic
unless predictive functionals are pathological.

## Work and resources

| Component | Workers | Work per worker |
|---|---:|---|
| DGP oracle | 40 | 4,096 recursive paths |
| Full-grid fit | 50 | Seven nested independent AL VB fits |
| Total | 90 | At most 30 distinct Jerez physical cores |

All workers are atomic and manifest-verified. The launcher requires pinned R
4.6.0, a clean synchronized branch, explicit physical-core affinity, at least
80 GiB free under `/data`, at least 128 GiB available memory, one numerical
thread per worker, and no competing Jerez model process.

## Checklist

- [x] Preserve the closed V3 branch and runtime unchanged.
- [x] Freeze the complete V3 tail shortlist rather than cherry-picking results.
- [x] Freeze fresh seeds, oracle budgets, fit margins, and near-tie behavior.
- [x] Implement atomic preparation, workers, health checks, and finalization.
- [x] Add fit, horizon-one, tail, recursive, crossing, and DGP score diagnostics.
- [x] Add focused synthetic selection tests.
- [ ] Verify the frozen V3 runtime on Jerez and prepare the new runtime.
- [ ] Launch the 90-worker fit-first campaign after the capacity gate passes.
- [ ] Finalize and audit the candidate decision.
- [ ] Only then freeze the separate four-model confirmation contract.

No article file, main branch, Overleaf branch, or unrelated scientific lane is
modified by this continuation.
