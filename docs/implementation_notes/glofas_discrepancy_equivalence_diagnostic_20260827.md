# GloFAS Discrepancy-Forecast Equivalence Diagnostic

## Scope

This change implements the no-refit diagnostic stages in the ignored plan
`local_trackers/glofas_discrepancy_forecast_equivalence_ultimate_diagnostic_plan_20260827.md`
(SHA-256 `01c15d4188462c4d07a6e6e045de7de39afcda4fae2f543837b3530865aa4178`).
It addresses one narrow question: why materially different discrepancy-DESN
architectures produced almost identical 28-day posterior-mean discrepancy
paths in the completed GloFAS p50 campaign.

The implementation is diagnostic and behavior preserving. It does not change
the latent-path transition, likelihood, VB updates, RHS prior, reservoir
construction, score definition, or promotion rules. It launches no fit and
does not modify article text, tables, figures, or promoted application output.

## Frozen source evidence

The audit reads the strictly closed campaign at:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/runtime_configs/glofas_richer_discrepancy_initial_20260827
```

The terminal census is:

| State | Count |
|---|---:|
| Completed fits | 5 |
| Preflight rejected | 16 |
| Failed | 0 |
| Incomplete | 0 |
| Total terminal | 21 |

The diagnostic retains and verifies exactly three candidate fit/design pairs:

| Candidate | Role | Fit SHA-256 | Design SHA-256 |
|---|---|---|---|
| `richer_discrepancy_initial_017_56de1e1368` | Numerical p50 leader, D=32 | `50fc8a803ebb0f2f694994bd3afaddfc07815ece0677c570aa0b6806f59c1478` | `81b470f171fbbd1de06afc4f135f24b568f806dea1bb1bdcdca65ef59f01da95` |
| `richer_discrepancy_initial_014_91b5493969` | Converged deep anchor, D=16 | `68ae1c539d17ff46e84436f7edb4385e74c2bec994456ec6102a73ea26b1a062` | `c5a188229c93a3d2613c283cc62d56c163a160ddf55fb775d30e107a5ace26a5` |
| `richer_discrepancy_initial_001_bc57c0cae9` | Cold FR09 control, D=1 | `a6be5069cb343b0498d9dd2c1e1cd3ae4e6439ed5af8a2151468100e93406b74` | `dff8dfbc1705d9760c789cabb634055da95a76d61cc094bee76e2190682308f1` |

The diagnostic never copies these heavy objects. It loads one candidate at a
time, verifies the recorded hashes, writes compact ignored evidence, removes
the object from memory, and runs garbage collection before the next candidate.

## Implementation

### Diagnostic module and runner

`application/R/glofas_discrepancy_equivalence_audit.R` provides deterministic
helpers for:

- strict status-source precedence and campaign certification;
- semantic feature layouts and hashes;
- one-axis design mutations and cache-collision canaries;
- feature sentinels and paired/unpaired permutation checks;
- serialization/reload parity;
- state dynamic-range, effective-rank, conditioning, and duplication summaries;
- posterior-mean and posterior-draw contribution decomposition by direct block
  and reservoir layer;
- exact-versus-optimized future-design parity;
- posterior prediction identity and independent check-loss reconstruction;
- post-fit no-refit ablations; and
- a fail-closed root-cause decision.

`application/scripts/glofas_discrepancy_equivalence_audit.R` binds those helpers
to the completed campaign. A completion marker is written only after all
mandatory tables and figures exist, every source artifact hash matches, and
every white-box implementation check passes.

### Production observability

`application/R/fit_qdesn_latent_path.R` now exposes the component identity

```text
q_g = q_y + d_g,
d_g = discrepancy_baseline + X_alpha alpha
```

through one checked helper. Prediction summaries now report separate beta and
alpha feature counts, reservoir counts, and semantic prediction-design hashes.
The existing numerical prediction path is unchanged.

Reference feature-cache contracts now carry an explicit `reference` block
role. A discrepancy-role contract is rejected before it can enter the shared
reference cache.

### Seed observability

`application/R/model_contract.R` now reports wrapper, nested, fallback, and
effective block seeds together with their source and precedence rule. Existing
behavior is preserved: an explicit wrapper `reservoir_seed` precedes a nested
`reservoir.seed`, which precedes the model/config fallback. Conflicts can be
recorded for legacy configurations or rejected by new strict callers.

The retained configurations contain an inherited nested discrepancy seed that
differs from the intended wrapper seed. The audit confirms that the wrapper
seed `20261521` was the effective discrepancy seed in every retained fit; the
reference seed was `20260512`. This is representational ambiguity, not silent
reuse of the reference reservoir.

## Diagnostic result

All cache, feature-alignment, seed-resolution, serialization, transition,
prediction-identity, exact-parity, score-reconstruction, and retained-artifact
checks pass.

The retained discrepancy paths are genuinely nearly equivalent:

| Pair | Path RMSE | Maximum absolute difference | Correlation |
|---|---:|---:|---:|
| D32 versus D16 | 0.007965 | 0.018187 | 0.999792 |
| D32 versus FR09 | 0.015157 | 0.031951 | 0.999460 |
| D16 versus FR09 | 0.015571 | 0.034070 | 0.999358 |

A lightweight check of all five completed forecast exports reaches the same
conclusion: all ten pairwise path RMSE values lie between 0.005692 and
0.016867, while correlations lie between 0.999164 and 0.999902. The three
hash-retained candidates therefore span, rather than manufacture, the pattern
seen across the completed campaign.

This equivalence is not caused by identical inputs or reservoirs. Historical
discrepancy designs have 2,143, 1,567, and 843 readout columns, including 1,600,
1,024, and 300 reservoir states. Their semantic hashes differ, state profiles
differ, and one-axis architecture mutations change the design hash.

The fitted discrepancy readout is instead dominated by the common direct
features. For the numerical leader, the sum of layerwise forecast reservoir
RMS contributions is only about 1.39% of the corresponding total layer/group
RMS measure. Removing all reservoir contributions leaves a discrepancy MAE of
1.5901 versus 1.5854 for the complete fitted path. Reservoir coefficients are
therefore too suppressed to make architecture changes visible in the forecast.

The no-refit ablations also show that the fitted innovation is not fixing the
held-out level shift: last-observed persistence has discrepancy MAE 1.4767,
which is better than the complete fitted path. These ablations are mechanism
diagnostics, not refitted competitors and not promotion evidence.

The primary diagnosis is:

```text
rhs_readout_suppression_with_common_direct_feature_dominance
```

The secondary mechanism is:

```text
persistence_anchor_and_forecast_regime_shift
```

The deepest numerical leader stopped at 150 VB iterations just outside its
parameter tolerance, while the D16 and FR09 anchors converged. This does not
explain the equivalence: exact prediction checks pass and the nonconverged
leader differs from the anchors by only 0.008-0.015 path RMSE.

## Interpretation boundary

The configured future covariate policy is `gefs_realized_blend` and its source
contract reports realized-future use. Results from this campaign therefore
must retain their existing blended/retrospective interpretation and must not be
relabeled as a purely operational real-time forecast.

The audit does not establish that a richer discrepancy reservoir is useless.
It establishes that the current single alpha-block RHS readout gives those
reservoir features too little posterior influence for increasing depth alone
to be an informative experiment.

## Decision and next gate

No broad architecture screen, full-seven-quantile rerun, promotion, or article
update is authorized by this result. FR09 remains authoritative.

The next defensible experiment is a small, prospectively frozen p50 mechanism
campaign, after explicit review:

1. cold-repeat one control to establish numerical repeatability;
2. validate exact-design warm/cold equivalence for an RHS-only change;
3. compare the current alpha RHS scale with mathematically documented separate
   reservoir and direct-feature global scales;
4. include reservoir-only and direct-only fitted canaries as diagnostics;
5. preserve all historical guards and require a material held-out discrepancy
   improvement beyond the repeatability envelope; and
6. cold-confirm any survivor before a broader p50 screen or full7 run.

Transition alternatives remain behind a separate gate. They require explicit
generative definitions and synthetic fit/predict tests and must not be mixed
into the RHS mechanism experiment.

## Evidence location

The ignored diagnostic output is:

```text
local_trackers/runtime_configs/glofas_discrepancy_equivalence_audit_20260827
```

It contains compact CSV evidence, ten provenance-captioned PDF diagnostics,
source and artifact hashes, session information, storage accounting, and
`DIAGNOSTIC_COMPLETE.txt`. Heavy retained source objects remain only in the
closed source campaign.

The final evidence package is 7.3 MB, contains 53 passing white-box checks and
ten valid one-page PDFs, and contains no `.rds`, `.rda`, or `.RData` file. Its
completion-marker SHA-256 is
`f7b8523ab1337a7fa3c9a6b3f3613380a23ec9e5fc7b2695ac81bc2d4949671b`.

## Validation

- Changed R files parse successfully.
- The focused discrepancy-equivalence tests pass.
- The full application R harness passes through the new audit and all GloFAS
  tests, then stops at the known unrelated shared-validation assertion
  `nrow(promoted) == 18L`.
- `git diff --check` passes.

No Python orchestration code changed, so scheduler/watch tests are not required
for this change. No article file changed, so manuscript compilation is not a
scientific acceptance criterion for this diagnostic branch.
