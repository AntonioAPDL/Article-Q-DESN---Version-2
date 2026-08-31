# Joint QDESN Phase181 Final Closeout and Dense-Grid Plan

Date: 2026-08-30

Status: the seven-level Phase178--181 scientific lane is complete and ready
for integration review. No current-grid rerun, new calibration screen, or
manuscript mutation is authorized by this document. The next scientific
campaign is a separately frozen dense-grid refit, and it begins only after the
integration coordinator accepts the current seven-level authority.

## 1. Executive Decision

Phase181 closes the current seven-level joint-versus-independent validation
study. The optimal immediate action is to hand the verified scientific branch
and staged article assets to the integration coordinator. It is not useful to
run another seven-level DESN or `tau0` screen:

1. Phase179 already selected controls separately by scenario and readout.
2. Phase180 completed a balanced 32-cell, draw-backed article packet.
3. Phase181 extended only the 19 cells with formal score-functional or
   chain-allocation triggers, without changing any model specification.
4. Every implementation hard gate passes, every contract grid is
   noncrossing, and all source and artifact manifests verify.
5. The remaining reviews concern Monte Carlo precision, alpha/readout
   geometry, and raw pre-contract coherence. They do not identify an
   untested seven-level specification dimension.

The seven-level result is scientifically usable with descriptive wording.
It does not establish universal superiority of a joint readout or of exAL.
The later 19-level study is justified by a different question: whether a
denser issued quantile vector reveals a clearer coherence advantage for joint
estimation while preserving forecast-score competitiveness.

## 2. Frozen Lineage and Precedence

The stages answer different questions and must not be collapsed into one
retrospective ranking.

| Stage | Frozen purpose | Final role |
|---|---|---|
| Phase178 | Exact-M0 candidate ranking under forecast oracle-quantile MAE | Immutable historical ranking provenance |
| Post-Phase178 score audit | Define and test the known-DGP finite-grid score on protected Phase178 draws | Authoritative score definition and computational contract |
| Phase179 | Fresh-replicate, case-specific control confirmation | Authoritative case-specific DESN and `tau0` controls |
| Phase180 | Complete all 32 article cells with retained posterior draws | Balanced seven-level source packet |
| Phase181 | Same-specification extension for 19 unstable or chain-sensitive cells | Final selected seven-level estimator packet |

The precedence for interpretation is therefore:

1. preserve Phase178 under its original contract;
2. use the post-Phase178 score definition for the multi-quantile action;
3. preserve Phase179 case-specific controls;
4. use the Phase181 selected packet for current article integration;
5. treat a dense grid as a new fitted-model campaign, never as
   interpolation or post-processing of seven fitted quantiles.

This precedence resolves the apparent conflict between the earlier
half-percent near-tie policy and the later user-directed any-positive-gain
policy. Both remain reproducible. Phase181 applies the prospectively frozen
strictly-lower finite posterior-mean rule after hard eligibility; it does not
rewrite the earlier sensitivity result.

## 3. Final Current-Grid Contract

The issued quantile levels are

```text
0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95
```

The primary action metric is internally named `dgp_integrated_acrps`. It is
the DGP expectation of the finite-grid integrated quantile score,

\[
  R(q)=\frac{1}{H}\sum_{h=1}^{H}\sum_{k=1}^{K}
  w_k\,2\,\mathbb{E}_{Y_h\sim F_{0,h}}
  \{\rho_{\tau_k}(Y_h-q_{h,k})\}.
\]

The trapezoidal weights are

```text
0.025, 0.10, 0.20, 0.25, 0.20, 0.10, 0.025
```

They sum to 0.90 and are not renormalized because the fitted interval is
`[0.05, 0.95]`. Article-facing text should call this the
"DGP-integrated finite-grid quantile score." It is closely related to a
finite-grid aCRPS, but it is not the closed-form CRPS of a fitted scalar
predictive distribution.

The reportable summaries are:

- posterior score mean and equal-tailed 95% credible interval;
- posterior median as sensitivity evidence;
- score of the canonical posterior-mean monotone quantile action;
- realized finite-grid aCRPS and check loss as secondary compatibility
  evidence;
- fit and forecast MAE/RMSE as oracle quantile-path recovery diagnostics;
- raw crossings, contract crossings, and monotone-adjustment burden.

Joint posterior draws retain learned within-draw dependence across quantiles.
Independent quantile posteriors use the frozen seeded, chain-balanced product
coupling. Neither construction normalizes or samples from the product of the
AL/exAL working likelihood factors as though it were a scalar predictive
density.

## 4. Phase181 Completion and Integrity

| Check | Result |
|---|---:|
| Extension cells | 19 |
| Planned chain workers | 152 |
| Completed chain workers | 152 |
| Failed workers | 0 |
| Final scenario-model cells | 32 |
| Phase181 lower-mean promotions | 13 |
| Phase180 baselines retained after comparison | 6 |
| Unaffected Phase180 cells retained | 13 |
| Joint-minus-independent contrasts | 16 |
| Finite final score cells | 32/32 |
| Contract crossing pairs | 0 |
| Score-functional pass/review | 21/11 |
| Implementation hard gate | pass |
| Overall diagnostic gate | review |

Independent verification on 2026-08-30 found:

- final packet manifest: 40/40 entries present and SHA-256 matched;
- article staging manifest: 12/12 entries present and SHA-256 matched;
- integration handoff manifest: 9/9 entries present and SHA-256 matched;
- inherited source verification: 73/73 entries passed;
- no Phase178, Phase179, Phase180, or Phase181 process was active.

The old tmux session named
`joint_qdesn_phase112_vb_screening_20260708_resumed_clean` has no matching
JOINT worker process. It is outside this lane and must remain untouched.

## 5. Source Promotion Result

Phase181 did not select new DESN or prior specifications. It compared a longer
same-specification posterior run with the corresponding Phase180 estimator.
A source was promoted only when all hard gates passed and the finite
Phase181 posterior score mean was strictly lower.

Thirteen of 19 extension cells were promoted. The largest changes repaired
three highly chain-sensitive independent exAL baselines:

- Laplace bridge: absolute mean reduction about 13.31, or 97.63%;
- persistent heavy tail: absolute mean reduction about 1.002, or 73.41%;
- regime shift: absolute mean reduction about 0.0379, or 8.07%.

The remaining promoted changes are small, from roughly 0.012% to 0.237%.
They are retained because the lower-mean rule was frozen before finalization,
not because they establish practical or statistical superiority. Six
extension cells retained their Phase180 baseline because the longer run did
not lower the posterior score mean.

## 6. Final Scenario-Level Result

The numerical minimum by scenario under the final selected packet is:

| Scenario | Numerical winner | Posterior mean | 95% credible interval |
|---|---|---:|---:|
| Asymmetric Laplace tail | Joint exQDESN RHS | 0.3163480 | [0.3143442, 0.3200059] |
| Gaussian-mixture bridge | Independent QDESN RHS | 0.3865448 | [0.3843670, 0.3894919] |
| Laplace bridge | Joint QDESN RHS | 0.3220167 | [0.3203583, 0.3251574] |
| Nonlinear reservoir friendly | Joint QDESN RHS | 0.4272814 | [0.4246811, 0.4305256] |
| Normal bridge | Joint QDESN RHS | 0.3100956 | [0.3079504, 0.3134763] |
| Persistent heavy tail | Independent exQDESN RHS | 0.3629181 | [0.3600516, 0.3677267] |
| Regime shift | Independent QDESN RHS | 0.4310831 | [0.4263327, 0.4416523] |
| Student-t location-scale | Joint QDESN RHS | 0.3361858 | [0.3343084, 0.3395168] |

Joint models are numerical winners in five of eight scenarios. Independent
models are numerical winners in three. This is the appropriate compact
article pattern, but it remains descriptive:

- joint readouts have a lower mean score in 9/16 within-likelihood contrasts;
- the split is 4/8 under AL and 5/8 under exAL;
- all 16 joint-minus-independent 95% contrast intervals include zero;
- average scores across the eight scenarios are very close: 0.36210 to
  0.36350 across the four model classes.

The result supports competitiveness and a coherence advantage in selected
settings. It does not support saying that Joint exQDESN is universally the
best model or that exAL must dominate AL in every DGP.

## 7. Crossing and MCMC Interpretation

Canonical forecast raw crossings are concentrated in the independent AL
readout:

| Model | Raw forecast crossings | Contract forecast crossings |
|---|---:|---:|
| Joint QDESN RHS | 1 | 0 |
| Independent QDESN RHS | 25 | 0 |
| Joint exQDESN RHS | 0 | 0 |
| Independent exQDESN RHS | 0 | 0 |

This 1-versus-25 AL contrast is the strongest current coherence result.
Draw-aggregated crossing counts in posterior diagnostic files are different
objects and must not be substituted for these canonical article counts.

Exact M0 has addressed the earlier exAL gamma/sigma bottleneck. Across the
final exAL packet:

- maximum gamma rank R-hat is about 1.020 for independent fits and 1.015 for
  joint fits;
- minimum gamma bulk ESS is about 410 for independent fits and 849 for joint
  fits;
- maximum sigma rank R-hat is about 1.016 for independent fits and 1.012 for
  joint fits;
- minimum sigma bulk ESS is about 472 for independent fits and 959 for joint
  fits.

The remaining review burden is concentrated in alpha/readout coordinates and
some score functionals. Under the frozen contract, review-level scalar mixing
does not veto a lower finite mean when quantile actions are finite, source
complete, and contract noncrossing. It does require descriptive rather than
definitive winner language.

## 8. Forecast-Protocol Audit

The separate exDQLM rolling-state defect reported in another lane is not
present here. QDESN forecast quantiles are readout actions of the form
`alpha + Z beta`; there is no latent DQLM filtering state whose transition
requires posterior gamma/sigma predictive moments. Gamma and sigma shape the
exAL posterior but are not an omitted additive forecast-state correction.

One manuscript nuance must nevertheless be explicit. The current validation
uses fitted coefficients held fixed while lagged realized outcomes become
available sequentially in the forecast window. It is a sequential conditional
forecast evaluation, not an open-loop 30-step recursive forecast from one
fixed origin. This applies symmetrically to AL and exAL and does not invalidate
the frozen score comparison, but the article must not describe it as a fully
recursive path simulation.

## 9. Article Integration Contract

The scientific lane stages article-safe assets but does not edit or publish
the manuscript. The integration coordinator should:

1. merge the dedicated JOINT branch after combined-repository tests;
2. copy the eight `article_safe=TRUE` files listed in the frozen handoff into
   the article projection with source hashes preserved;
3. replace the stale forecast-MAE-centered joint table with the staged
   Phase181 DGP-integrated score table;
4. report posterior mean and 95% credible interval as the headline entries;
5. retain canonical raw and contract crossings as coherence diagnostics;
6. move fit/forecast MAE and RMSE to oracle-recovery diagnostics;
7. state that numerical winners are descriptive because all 16 paired
   joint-minus-independent score intervals include zero;
8. state the sequential conditional forecast protocol accurately;
9. avoid scalar posterior predictive-density claims for the joint composite
   likelihood;
10. compile both `main.tex` and `qdesn-supplement.tex`, run focused article
    tests, and publish only after hash and row-count checks pass.

Required article checks are:

- exactly 32 scenario-model rows and eight scenarios;
- all 32 posterior score means and intervals finite;
- boldface chosen by the final posterior score mean within scenario;
- one table row per scenario and four model columns;
- zero contract crossings in every row;
- canonical raw crossing totals of 1, 25, 0, and 0 in model order above;
- no stale Table 7 prose that calls forecast MAE the headline metric;
- no visible `Grid CRPS` label for the new DGP-integrated score;
- no claim that nonoverlap of marginal model intervals is a paired contrast;
- no runtime cache, checkpoint, posterior-draw payload, or local tracker in
  article Git.

The current authoritative article checkout is on an unrelated GloFAS branch.
This lane intentionally leaves it unchanged. The coordinator must reconcile
current `origin/main` before applying these assets.

## 10. Proposed Dense-Grid Stage

The dense-grid study is the only scientifically useful next simulation stage,
but it is not launched by this closeout. It changes the fitted readout
dimension and therefore requires a new branch, contract, seeds, initialization
audit, retained-draw plan, and article-fixture confirmation.

### 10.1 Question

Test whether joint estimation reduces raw adjacent-level crossings more
clearly than independent estimation when the issued quantile grid is denser,
while remaining competitive under the same DGP-integrated finite-grid score.
The target is not to force a universal joint winner.

### 10.2 Grid contract

The natural candidate is the 19-level equidistant grid from 0.05 through 0.95
in increments of 0.05. It contains every current endpoint and has trapezoidal
weights 0.025 at the endpoints and 0.05 in the interior. The exact grid and
weights must be frozen before any protected score is inspected.

Crossing comparisons across seven and 19 levels must use both counts and
opportunity-normalized rates. The reported monotone contract must remain
noncrossing, while raw crossings remain visible evidence.

### 10.3 Case-specific model policy

No universal DESN or `tau0` is allowed. The Phase179 controls are starting
anchors for their corresponding scenario/readout cells. Because changing the
quantile dimension can change optimization and prior geometry, each cell may
receive a narrowly bounded, predeclared calibration on non-article fixtures.
Any finite lower primary score may be promoted under a prospectively frozen
rule, provided implementation, provenance, oracle-safeguard, and contract-
crossing gates pass. Article fixtures remain untouched during calibration.

### 10.4 Ordered implementation

1. Create a new JOINT branch from the coordinator-integrated `origin/main`.
2. Freeze the 19-level grid, quadrature, score, crossing-opportunity,
   posterior-coupling, seed, compute, and storage contracts.
3. Extend fixture and design audits to prove the 19 oracle quantiles are
   finite, ordered, aligned, and leakage-free.
4. Verify that joint and independent APIs accept the 19-level grid without
   changing the AL/exAL or RHS contracts.
5. Run case-specific VB/VB-LD initialization and bounded calibration only on
   the designated calibration partition.
6. Freeze one selected specification per scenario/model cell. Preserve exact
   M0 for exAL and the structured-v initialization.
7. Run balanced MCMC confirmation for all four model classes across all eight
   scenarios with retained compact posterior draws and independent chain
   seeds.
8. Reconstruct posterior DGP-integrated score means, medians, 95% intervals,
   canonical-action scores, paired contrasts, oracle diagnostics, and raw/
   contract crossing rates.
9. Compare seven- and 19-level conclusions as grid-resolution sensitivity.
   Do not interpret the numerical score-level shift caused by quadrature
   refinement as a fitted-model improvement by itself.
10. Stage a separate dense-grid article supplement only if its manifests,
    functionals, and contract crossings pass.

### 10.5 Dense-grid gates

Hard failure includes missing sources, nonfinite or unordered oracle grids,
leakage, seed collisions, nonfinite score draws, source/hash defects, or any
contract crossing. Review includes high raw crossing rates, material isotonic
adjustments, unstable score functionals, or concentration of a result in one
chain or one fixture. Scalar gamma/sigma review remains nonfatal when the
reported quantile functionals are stable.

The dense-grid campaign should be sized only after the initialization and
storage contracts are frozen. This closeout does not guess a worker count or
consume protected fixtures prematurely.

## 11. Frozen Artifacts

Final packet:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_score_stability_extension_packet_20260826
```

Top-level manifest SHA-256:

```text
e392c717c060636ec8ebadb51842b7abfe3fb531b99de3659cee8875d26d0292
```

Article staging:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_article_assets_staging_20260826
```

Top-level manifest SHA-256:

```text
96a54710059002fa1f23aa86b515d6b2f9fc60505888d8f8eb7b79bc7578a69e
```

Generated integration handoff:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/
joint_qdesn_phase181_integration_handoff_20260826
```

Top-level manifest SHA-256:

```text
46e5ae840712c1b31b15b0d61fd711523ab7058e33917e8359f92d0a35a3cea0
```

The packet is about 35 MB; article staging and handoff are under 200 KB
combined. They are small, authoritative evidence and should be retained.
Heavy chain/checkpoint directories remain ignored runtime evidence and must
not be copied into Git or Overleaf.

## 12. Reproducible Verification

```bash
Rscript application/tests/test_joint_qdesn_phase181_score_stability_extension.R
Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
git diff --check
git status --short --branch
```

Manifest verification must recompute each declared SHA-256 rather than merely
checking that a manifest file exists.

## 13. Final Checklist

- [x] Preserve Phase178 under its original oracle-MAE contract.
- [x] Freeze and test the known-DGP finite-grid score contract.
- [x] Complete fresh, case-specific Phase179 confirmation.
- [x] Preserve one DESN and `tau0` specification per case rather than one
  universal specification.
- [x] Complete the balanced 32-cell Phase180 draw packet.
- [x] Complete 152/152 Phase181 extension chains with zero failures.
- [x] Apply the frozen strictly-lower mean source-selection rule.
- [x] Verify 32 finite cells, 16 contrasts, and zero contract crossings.
- [x] Verify packet, staging, handoff, and source manifests.
- [x] Stage article-safe assets without changing the manuscript.
- [x] Document the exDQLM non-applicability and forecast-protocol nuance.
- [x] Freeze this final scientific interpretation and coordinator handoff.
- [ ] Integration coordinator merges and tests the dedicated JOINT branch.
- [ ] Integration coordinator projects and compiles article-safe assets.
- [ ] Create a new main-based JOINT branch for the separately frozen
  19-level campaign.

## 14. Final State

`READY_FOR_INTEGRATION`

No seven-level run remains. No worker should be restarted. The coordinator,
not this lane, owns the merge and article publication. After that handoff, the
next JOINT scientific task is the dense-grid contract and refit campaign on a
new branch from the integrated `origin/main`.
