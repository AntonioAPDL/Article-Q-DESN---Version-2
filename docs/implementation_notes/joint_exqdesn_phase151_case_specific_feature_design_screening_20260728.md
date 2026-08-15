# Joint exQDESN Phase151 Case-Specific Feature-Design Screening

Date: 2026-07-28

## Decision

Phase150 completed eight-chain MCMC confirmation of the scenario-specific
Phase149 Joint exQDESN RHS winners. All implementation gates passed, but the
new exAL rows beat the article Joint QDESN AL forecast MAE only for Persistent
Heavy Tail. Small readout-prior changes and additional gamma-sampler work are
not the next experiment: those dimensions were already studied in Phases
128--150.

Phase151 changes the remaining untested model component: the deterministic
feature map supplied to the joint readout. Candidate selection remains
scenario-specific. There is no global reservoir specification.

## Non-Duplication Audit

The readiness artifact writes
`phase151_prior_experiment_novelty_audit.csv`. It records why Phase151 does not
repeat:

- gamma slice widths, stepping limits, chain counts, thinning, or chain length;
- gamma priors, initialization basins, fixed-gamma controls, or hybrid kernels;
- posterior mean/median/trimmed quantile summaries;
- RHS `tau0`, `zeta2`, ordered-intercept fan, or VB-effort screens;
- the old Phase4n engineered-feature proposal.

Phase4n targeted raw crossings under AL on an earlier replicated registry. It
proposed standardization, winsorization, interactions, and lag proxies, but did
not generate reservoir states and did not materialize its default artifact.
Phase151 excludes those transformations.

Readiness also generates every candidate design against the complete frozen
fixtures before any VB fit is launched. The resulting
`phase151_design_preflight.csv` records actual readout dimensions, spectral
radius diagnostics, inactive-feature fractions, effective rank, condition
number, and a pass/review/fail assessment.

## Candidate Design

The formal fixture, truth quantiles, split, forecast-origin plan, monotone
quantile contract, and Phase150 case-specific exAL/RHS controls remain frozen.

Seven scenarios where Phase150 exAL trails Joint AL receive five candidates:

1. the exact frozen direct-feature map as a parity anchor;
2. a compact reservoir-only map;
3. a compact direct-plus-reservoir map;
4. a balanced direct-plus-reservoir map;
5. one scenario-tailored direct-plus-reservoir map.

Persistent Heavy Tail already beats the Joint AL reference. It receives only
the direct parity anchor and is treated as a frozen success control. The full
screen therefore contains 36 candidates, not another indiscriminate global
grid.

Reservoir inputs are centered and scaled using only the 500 DESN-washout and
500 fit rows. Reservoir states are rolled deterministically from the beginning
of each 12,000-row fixture and standardized using only the 500 fit rows.
Candidate seeds are explicit. Joint dense dimensions remain at or below 300.

## Forecast Interpretation

The runner fits each candidate once on the 500 declared fit rows and scores the
unchanged lead 1--30 no-refit forecast-origin plan. Target-row features remain
the frozen conditional design supplied by the formal fixture. This is not
presented as recursive operational forecasting.

Raw quantiles remain diagnostic. Reported fit and forecast scores use the
monotone quantile-grid contract. Phase151 validates posterior quantile readout
paths; it does not claim a scalar posterior predictive density.

## Selection Gates

Hard failures include:

- source-manifest or checkpoint hash failure;
- nonfinite design, trace, RHS, sigma, gamma, quantiles, or scores;
- nonpositive sigma;
- dense dimension above the declared limit;
- an excessively inactive design;
- any crossing after the monotone contract.

Review flags include:

- VB reaching its adaptive iteration limit;
- raw crossings before the contract;
- nontrivial monotone adjustment;
- review-level inactive-feature fraction, rank deficiency, or conditioning.

Rank deficiency alone is not an implementation failure. In particular, the
frozen regime-shift design contains a training-inactive structural feature.
The regularized readout can still be evaluated, so Phase151 preserves direct
feature parity and reports this condition transparently as review evidence.

A new design is eligible for MCMC only if it:

- improves forecast truth MAE by at least `max(0.0025, 2%)` relative to the
  exact direct-feature VB parity anchor;
- keeps fit truth MAE within 5% of the anchor;
- keeps forecast check loss within 2% of the anchor;
- passes all implementation gates.

No article asset is changed from Phase151 VB evidence.

## Reproducibility And Resumption

Prepare:

```bash
Rscript application/scripts/169_prepare_joint_exqdesn_phase151_feature_design_screening.R
```

Launch the complete screen:

```bash
application/scripts/172_launch_joint_exqdesn_phase151_feature_design_screening.sh --execute
```

Health check:

```bash
Rscript application/scripts/171_check_joint_exqdesn_phase151_feature_design_screening.R
```

Each candidate writes a compact independently hashed checkpoint under
`candidates/<candidate_id>/`. Interrupted runs resume incomplete candidates
only. Raw `.RData`/`.rds` fit objects are not retained.

Default artifacts:

- readiness:
  `application/cache/joint_qdesn_phase151_case_specific_feature_screening_readiness_20260728`
- screen:
  `application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728`
- orchestration:
  `application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728_orchestration`

The final root artifact includes candidate/tau/interval summaries, design and
VB diagnostics, scenario-specific ranking, a conservative MCMC confirmation
plan, provenance, and SHA-256 manifests.

## Next Decision

If no new design clears the practical-gain and guard gates, stop screening this
lane and retain Phase150. If one or more scenario-specific designs clear the
gates, freeze only those winners and run eight-chain VB-initialized MCMC
confirmation. Article integration remains blocked until that MCMC layer is
complete and audited.
