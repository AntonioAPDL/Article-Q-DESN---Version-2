# JOINT persistent-heavy-tail V6 targeted calibration

Date: 2026-11-26

## Decision

One further experiment is scientifically justified, but another global reservoir search is not.
V4 already evaluated 8,192 previously unseen architectures after excluding 9,722 historical
signatures and 31,902 prior fits. V5 then confirmed candidate 3242 on five fresh fixtures. Its
mean three-level DGP-integrated score improved by 2.32 percent over the exact control, while its
lower and upper fit MAE improved by 33.9 and 27.0 percent and its lower and upper horizon-one MAE
improved by 40.0 and 26.2 percent. These are meaningful fit gains, not evidence that the reservoir
class is exhausted.

The remaining evidence gap is narrower:

1. only 12 of the 8,192 V4 architectures received tail-quantile fits;
2. the lower and upper fits inherited the median-selected AL scale;
3. candidate 3242 reached the upper explored fixed-slab boundary (`zeta2 = 64`).

V6 therefore replays the strongest existing normal-RHS profiles and calibrates lower, median, and
upper AL priors separately. It does not generate new reservoirs, change the data split, inspect the
protected evaluation window, or alter the V5 packet.

## Frozen scientific contract

- Scenario: `persistent_heavy_tail` only.
- Models during selection: independent AL RHS VB only.
- Reservoirs: 24 existing V4 H2 architectures, at most two normal-RHS profiles per architecture.
- Added slab checks: candidate 3242 at 128, 256, and 512; candidate 2430 at 0.0001, 0.001, 0.03,
  and 0.1.
- Tail AL multipliers: 0.0001 through 1000 on a 15-point logarithmic grid.
- Median AL multipliers: 0.001, 0.01, 0.1, 1, and 100.
- Selection metrics: quantile-path fit MAE first, then horizon-one behavior and recursive
  DGP-integrated finite-grid quantile score.
- Convergence is review-level when functionals are finite and stable; it is not a score-improvement
  veto by itself.
- Any strict eligible mean-score improvement may advance. Interval overlap is not formal
  equivalence.
- The evaluation realization remains excluded from selection.

## Sequential evidence gates

1. **Sentinel (26 workers).** Exercise the boundary slabs and local AL scales on one fresh fixture.
   Require finite functionals, valid connectivity, finite recursion, no protected rows, and complete
   manifests.
2. **Component screen (1,890 workers).** Fit all 54 frozen profiles at lower, median, and upper
   levels on one fresh fixture and origins 1, 5, and 10. Select at most 12 architecture-specific
   triplets, while retaining the exact V5 controls.
3. **Qualification (at most 108 workers).** Refit each triplet at all three levels on three fresh
   fixtures and all ten internal origins. Lower and upper fits use the selected median feedback path.
   Advance at most one forecast frontier and one fit frontier.
4. **Sealed confirmation (at most 120 workers).** Compare the selected challengers with V5-3242
   and the exact control on ten newly materialized fixtures. Require a strict eligible matched mean
   score improvement over V5-3242.
5. **Seven-level confirmation (at most 15 workers).** Refit the sealed winner, V5-3242, and the exact
   control on five fresh fixtures at 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95. The lower,
   middle, and upper prior profiles remain distinct.

Every stage finalizes and stops. Later fixtures are not materialized until the predecessor selection
is frozen and hashed. No article, JOINT model, exAL model, or MCMC run is authorized by an earlier
gate.

## Runtime and reproducibility

- Production host: `jerez.be.ucsc.edu`.
- Maximum concurrency: 15 distinct physical cores, one numerical thread each.
- Minimum preflight: 80 GiB free on `/data`, 128 GiB available RAM, no competing JOINT/GloFAS/
  PriceFM R processes, clean and upstream-synchronized V6 execution branch.
- Runtime is ignored. Worker summaries, details, compact initializers, warnings, DONE markers, and
  SHA-256 manifests are written atomically.
- V4 and V5 inputs are accepted only at the six hashes pinned in the V6 contract.
- Production outputs are not article authority and are not integrated while the campaign is active.

## Promotion boundary

If V6 confirms a seven-level improvement, that result authorizes a separate, frozen continuation
for the remaining independent/joint AL and exAL VB comparison and then MCMC initialized from those
VB fits. Every exAL MCMC continuation must use exact M0. Imperfect scalar mixing remains review-level
unless fit or forecast functionals are pathological. Only the final complete multi-model packet may
be offered to the integration coordinator.

## Checklist

- [x] Preserve and hash-pin V4/V5 evidence.
- [x] Build architecture-complete profile library.
- [x] Separate lower, median, and upper prior mappings.
- [x] Add atomic workers and immutable plan/fixture receipts.
- [x] Add fit, H1, recursive-score, crossing, and functional gates.
- [x] Add Jerez physical-core and capacity preflight.
- [x] Add focused tests and real disposable sentinel/seven-level smoke fits.
- [ ] Commit and push the dedicated V6 source branch.
- [ ] Prepare and verify the ignored production root on Jerez.
- [ ] Run and finalize the sentinel.
- [ ] Launch the component screen only if the sentinel authorizes it.
- [ ] Continue later stages only after their frozen predecessor decisions.
- [ ] Freeze the terminal scientific packet and provide one final integration handoff if warranted.
