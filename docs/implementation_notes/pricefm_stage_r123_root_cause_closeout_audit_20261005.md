# PriceFM R123 Root-Cause And Evidence-Closeout Audit

## Scope And Frozen Sources

This audit concerns only the BG Fold-1 training-internal connectivity successor.
It does not alter the PriceFM application authority, article, official validation
or test data. It does not authorize exAL, joint, MCMC or another screening.

- Scientific parent: `work/pricefm-r123-certified-successor-20261005`, full HEAD
  `40d42d15a477c2f9d50dbc69b4eb9885da91ec29`.
- Scientific tag: `pricefm_stage_r123_certified_successor_20261005`.
- Original observer: `work/pricefm-r123-validation-boundary-20261005`, full HEAD
  `bde255a362052b1667acdc2dc9676938d77307a3`.
- Frozen historical reservoir/input source:
  `7ae8d6f578000ab17cd30567a23f7b806028cee0`.
- Diagnostic continuation source: `f41ec727492244792f8c2d5f6381550a0239d690`.
- Preparation identity SHA256:
  `dfef3743300b9a986d314bfcd2ae9edf1828f7b29769ca35db61ec4f1b7919bd`.
- Exact CRAN exdqlm 1.1.1 source archive SHA256:
  `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`.

The audit branch changes only evidence checking and its tests/documentation.
Neither active source worktree is edited. The original observer remains intact.
The hardened observer uses a separate campaign namespace and writes no parent
artifacts. Its final receipt is not an article-promotion decision.

## Findings And Consequences

| Finding | Evidence | Consequence |
| --- | --- | --- |
| Historical Normal convergence was too permissive | `pricefm_recursive_normal_fit.R`, `app_pricefm_rhs_convergence_status`; stationarity regressions | Already corrected in the scientific parent; all eligible Normal initializers require full-state certification |
| Some old designs were extremely ill-conditioned | Preserved stationarity diagnosis; accuracy/jitter rejection tests | Excluded, not repaired by changing the posterior; no duplicate screening |
| RHS global shape is correct for the executed independent block | Normal and exact CRAN prior gate; intercept excluded, d=p-1 | `(d+1)/2=p/2`; adding another 0.5 would be incorrect |
| Warm starts do not define destination prior centres | Public CRAN AL initializer/seed tests, prior gate and Normal continuation tests | No identified target-changing initializer defect in this successor |
| H96 was misinterpreted as 96 hours | All 940x96 saved BG labels match quarter-hourly parquet rows | It is one day; no target-overlap embargo or rescore is required |
| AL formal convergence is narrower than full-state stationarity | CRAN `utils.R`, `.run_static_dqlm_cavi`, coefficient/sigma/ELBO stop inputs | Report the actual criterion, not a full RHS/latent-state certificate |
| Interrupted observer finalization could not resume | Two regression failures reproduced before the fix: terminal installed, final ledger absent | Evidence-only repair; no scientific refitting |
| Old observer independently checked hashes but trusted some identity/count claims | Old expected AL target came from the same terminal; group counts did not prove exact identities | Reconstruct contracts from frozen authorization and verify exact splits, levels and acceptance declarations |
| Wide fits are slow but active | Jerez CPU near one full core per worker; completed timings below | No deadlock evidence; do not restart valid fits merely because they are slow |

### RHS Algebra And Modeling Convention

For each shrunk coefficient, this project's NS product-Gaussian convention
retains the horseshoe factor's Gaussian normalizer and a separate slab factor.
Writing `s=tau^2`, the global half-Cauchy auxiliary hierarchy is
`s|xi ~ IG(1/2,1/xi)`, `xi ~ IG(1/2,1/tau0^2)`.
The inverse-gamma convention is `s^(-a-1) exp(-b/s)`.
The d horseshoe Gaussian factors contribute `s^(-d/2)`; the slab factors do
not involve s. Thus the conditional kernel is
`s^(-(d/2+3/2)) exp(-(1/xi + sum(beta_j^2/lambda_j^2)/2)/s)`.
The shape is `(d+1)/2`, and VB replaces the rate terms by expectations.
With an unshrunk intercept, d=p-1 and the shape is p/2.

This is an algebraic check of the implemented product convention, not a claim
that any normalized regularized-horseshoe parameterization has the same update.
The exact CRAN factory's active-index set and retained ELBO Gaussian terms are
checked against its archived source. No joint block is mechanically classified
using this independent-model derivation.

Normal noise variance uses the frozen IG(2,1) prior; the AL likelihood scale
uses IG(1,1). These quantities have different meanings and their fixed priors
are deliberate, not inherited from upstream sigma summaries. Normal posterior
beta and a mapped scale initialize median AL; adjacent AL fits initialize the
outward ladder. The destination RHS tau0, zero centres and unshrunk intercept
remain fixed. All tau alternatives are training-internal empirical-Bayes
choices; no official forecast score is used for selection.

### What AL Convergence Does And Does Not Establish

The exact public AL dispatch is `exalStaticLDVB(..., dqlm.ind=TRUE)` into
`.run_static_dqlm_cavi`. This is an AL special case, not a fitted exAL model.
Its convergence step receives maximum beta-mean change, sigma change and ELBO
change. It does not receive separate RHS-rate, covariance or latent-state
changes. The external saved gate adds a 25-iteration, scale-aware beta/sigma/
ELBO check. A predeclared 750/1000 cap companion may establish fitted-function
stability without selecting by validation performance.

The compact atom export contains beta mean/covariance, trace, scale and terminal
metadata, but not the full RHS/latent state needed for exact continuation or
post-hoc full-state certification. The public returned object does contain
those states; they are simply not exported by frozen script 420. Therefore:

- no posterior-target defect has been established for the current AL fits;
- formal/external convergence must not be renamed full-state convergence;
- the audit cannot retroactively invent missing state evidence;
- no blanket rerun follows from this evidence gap;
- a later explicitly justified full-state requirement would need a new export
  contract and bounded confirmation, not a silent replacement of current fits.

The new small R test fits only 80x7 synthetic data for three iterations. It
verifies identical priors under different seeds and beta/sigma starts, different
initial trajectories, and exact installed-versus-archived function bodies.
This is a software diagnostic, not another scientific campaign or MCMC fit.

## Smallest Complete Repair

`pricefm_r123_closeout_evidence.py` independently reconstructs each declared AL
contract from selected candidate, split, fixed tau0, quantile, cap, design and
nested initializer. A self-consistent but wrong terminal/contract is rejected.
Each ladder must have the exact predeclared levels in nested order. Raw and
paired-cap acceptance must match the saved diagnostic evidence. Normal groups
must contain the exact distinct split set {1,2,3}.

The final receipt hashes only four immutable scientific-audit files:
source identity, cadence audit, parent evidence ledger and terminal. Mutable
live progress, logs and later validation receipts are not part of this closure.
The commit ledger is written last. If interruption occurs after terminal but
before that ledger, restart first verifies the previously frozen parent and
cadence evidence, then writes the missing ledger. It never rehashes altered
parent evidence as valid, reruns a model or regenerates a score.
The observer also waits for matching numerical writer processes, not just the
controller lock, so an orphaned fit cannot be frozen while still writing.

The new observer has tag `pricefm_stage_r123_closeout_hardening_20261005`.
It polls every 60 seconds and may use one otherwise-idle physical core.
The scientific parent retains its 15-core maximum, currently nine independent
single-threaded ladders. The prior observer is not stopped or repurposed.

## Progress Snapshot, Not A Final Result

At 2026-10-05 07:14 UTC on Jerez: 15/63 primary AL atoms completed; all 15
formal-converged and externally eligible, 48 remaining, no full ladder yet.
Normal centre checks: 53 certified, 10 uncertified. All 60 bounded tau
alternatives finished; 37 complete candidate/scale groups provide 111 scores.
Two other certified centre cells lack a complete three-split group and cannot
be selected by themselves.

Completed p=385 AL fits took 13.55-21.00 seconds/iteration, versus 24.22-36.64
for p=513, depending also on training size (48,576-73,536 observations).
The p=577 fits were still active. These measurements are consistent with
repeated dense `X'WX` and `XV` work, approximately O(np^2+p^3), rather than a
proof that increasing cores can shorten a single one-core fit. Initializer
quality and conditioning also affect iteration count. No precise final ETA is
claimed before a complete ladder exists.

## Validation And Next Gates

1. Run all inherited Python tests plus closeout fault-injection regressions.
2. Run recursive Normal, full-state stationarity, prior-shape/separation and
   exact CRAN AL public-API/source-body tests using pinned R 4.6.0.
3. Repeat on Jerez, verify the dedicated source HEAD and compact receipts.
4. Audit already completed real AL atoms against the actual frozen contracts;
   do not inspect mutable binary arrays while their fits are being written.
5. Start only the separate evidence observer if its source/tests/resource gate
   pass. Preserve the old parent and observer; no new scientific launch.
6. On controller exit, verify all complete groups and ladders, freeze evidence
   and report incomplete panels honestly. Compare internal scores only after
   all comparable ladders are available.
7. An official held-out comparison or expansion requires a new explicit
   scientific protocol. Code readiness is not article-result readiness.

The ignored master tracker contains exact commands and validation receipts.
Runtime campaign/preparation paths, models, archives, PDFs and local trackers
remain excluded from Git. Only dedicated task code/tests/notes are pushed.
Scientific integration status remains `NOT_READY_FOR_INTEGRATION`.
