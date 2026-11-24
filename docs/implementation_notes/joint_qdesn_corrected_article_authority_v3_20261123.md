# Corrected multiquantile article authority (v3)

## Decision and integration boundary

Promote the complete 32-row selected MCMC packet from the corrected JOINT
closeout, together with its matched VB summaries, protocol, diagnostics and
article projections. The scientific source is
`5ad779121e44330e5a08baee1a44d77ba722b5cd`, already integrated in main at
`76a85698eb06ac7d5e870e4fe98a7f7df47ac6f6`. This article revision performs no
new fitting, tuning, posterior sampling, forecast generation or scientific
rescoring. It does not change the independent single-quantile study, GloFAS or
PriceFM authorities.

Here v3 denotes the successor to the pure-DESN v2 article projection. It is
not the September `joint_qdesn_corrected_v4` score-contract version, whose
separate frozen numerical evidence remains checked as historical material.

The exact selected CSV has SHA-256
`69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3`.
The runtime inventory and handoff manifest remain bound by the scientific
closeout's tracked result receipt. Runtime/model objects remain ignored.

## Why the article changes despite the kernel closeout's unchanged packet

The corrected AL-kernel rerun leaves the preceding November selected packet
unchanged. That statement compares two scientific closeout packets, not the
published article, which still used the earlier v2 projection. All 32 selected
posterior-mean oracle scores are numerically lower than those in the article's
v2 MCMC comparison. These reductions are not a controlled estimate of a kernel
effect: the fitting window increases from 500 to 1,300 observations, and the
reservoir-selection procedure also changes. The article replaces the complete
comparison rather than mixing old and new rows.

The persistent-heavy-tail challenger failed its frozen functional gate. The
selected packet therefore retains all four reference-configuration models for
that scenario, including their less favorable scores. No rejected challenger
row is inserted into the article.

Execution-source inspection adds a qualification to the handoff's statement
that the evaluation realization was excluded from candidate selection.
Reservoir candidates were indeed screened on separate development series,
but `application/R/joint_qdesn_stronger_window_score.R` selects between the
complete candidate/reference comparisons using evaluation posterior score
means: at least one improvement and no mean more than 1% higher, followed by
the functional-stability qualification. Thus the final reported packet is
evaluation-selected; it is not an untouched-test comparison. The main article
and appendix state this distinction. Neither source history nor this adverse
finding is removed.

## Protocol and interpretation

- Eight scenarios, four regressions per scenario, common selected DESN/RHS
  specification within a scenario and the same seven quantile levels.
- Fitting uses original full-series times 9701--11000 (1,300 observations), or
  observation times 7701--9000 after discarding the first 2,000 observations.
- Evaluation retains 33 origins and 30 horizons, or 990 origin--horizon pairs.
- Three base chains per model: AL runs 2,000 iterations, discards 500 and
  retains every second draw (750 per chain); exAL runs 4,000, discards 1,000
  and retains every second draw (1,500 per chain).
  The Laplace MQ--DESN exAL primary summary combines eight chains, or 12,000
  retained draws.
- Gaussian-reference intercept prior standard deviations are four residual
  standard deviations, not the old article's two. These fixed calibrations
  are shared across compatible regressions/chains, separately from numerical
  initialization. RHS slab scales are learned, and the screened global
  hyperprior scale is retained with each selected specification.
- Primary posterior score summaries evaluate coefficient draws at saved
  averaged future features. They are not a newly reconstructed distribution of
  integrated multistep quantiles per parameter draw.
- Independent AL has nine raw mean-grid adjacent crossings out of 47,520
  comparisons; the other three model classes have none. Contract crossings
  are zero. Ordering is now nearly universal, not a large empirical advantage
  exclusive to multiquantile regression.
- Numerical mean-score leaders are independent in five scenarios and
  multiquantile in three. All eight winner/runner-up marginal intervals
  overlap; all sixteen within-likelihood independent/multiquantile interval
  pairs overlap. These are descriptive comparisons, not tests of equivalence
  or decisive superiority.

## Diagnostic provenance requiring care

The frozen Laplace MQ--DESN exAL row combines an eight-chain primary score
summary with inherited three-chain recursive-path and some state-diagnostic
fields. Preserve its exact bytes. The article projection records the
field-specific provenance and excludes this row from matched primary/path
width aggregates. For the remaining 31 comparisons, primary intervals are
narrower throughout, with median width ratio 0.449085 and range
0.158279--0.820207. This does not make the two forecast functionals equivalent.

The Laplace MQ--DESN exAL primary score distribution has a long right tail;
its mean exceeds its central 95% upper endpoint. Do not clamp the mean, trim
draws or alter interval construction to improve figure appearance. The frozen
functional precision and chain-removal checks pass. Functional stability
does not establish that every scalar parameter mixes well.

## Reproduction and publication

The v3 builder exports deterministic summaries from frozen inputs. Its
versioned article manifest binds each public companion file; source bindings
use runtime-relative identifiers and hashes rather than local host paths.
The v3 checker authenticates the complete scenario/model surface, protocol,
frozen score bytes, active routes and deterministic display identities, with
negative tests for stale, missing or mixed-authority inputs.

Earlier v1/v2 scientific assets and their historical numerical checks remain
unchanged in research Git. Only current article routes and article-only
publication inventory move to v3. Existing compression/nomenclature guards
receive an explicit versioned authority admission rather than a silent reset
of historical expectations. No production sampler or scoring implementation
is changed by this article revision.

Release requires combined-tree tests, clean article-only main and appendix
builds, visual inspection, and the established guarded command-line Git
publishers. Direct Overleaf authentication failure is a pending publication
step, not evidence that main or the previous publication was missing. Report
publication complete only after fresh GitHub and direct-Overleaf readbacks.
