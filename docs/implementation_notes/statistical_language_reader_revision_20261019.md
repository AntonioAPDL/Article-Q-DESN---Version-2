# Statistical-language revision: evidence and reproduction

## Scope and authority

Base Article main: a96e661613ec7e733196a0b994f45350a3078332.

This is an editorial and display-label revision. It changes no model,
posterior target, selected specification, fit, forecast, score, plotting
datum, prior, or scientific authority. The independent and multiquantile
simulation and GloFAS results remain fixed. PriceFM is still pending;
its main/supplement application sections, output blobs, aliases and
per-role presentation receipts are preserved.

The full 51-item audit and execution record are retained in ignored
local_trackers storage. All 47 non-PriceFM recommendations are addressed;
P01–P04 are explicitly deferred to the incoming PriceFM authority.

## Statistical meaning preserved

- Conditional quantile locations are distinguished from marginal predictive
  quantiles, and score intervals from response intervals or empirical
  quantile frequencies.
- Primary multiquantile score intervals condition on future predictors
  averaged over simulated response paths. Draw-specific recursive forecasts
  are a separate sensitivity analysis.
- The first slope vector and adjacent differences retain their RHS
  hierarchy. The optional additional random baseline remains an unfitted
  mathematical extension.
- Gaussian product-prior factors, transformation Jacobians, structured
  scale–shape dependence and cross-level slope covariance are unchanged.
- Intercepts held fixed in the variational approximation do not acquire
  posterior uncertainty through a wording change.
- Numerical stopping criteria do not establish posterior mixing or a
  globally optimal variational solution.
- The 300-target primary period remains a retrospective reporting choice;
  the 500-target period is its nested extension, not independent replication.

## Historical disclosures relocated from reader-facing exposition

### Independent forecast reconstruction and selection

The following statement is retained here from the previous supplementary
dependence note:

> The forecast draws used here were reconstructed under frozen source-specific
> configurations because the original granular paths were no longer available.
> New posterior realizations need not be numerically identical to the earlier
> ones. Both evaluation periods use the same reconstructed draws; no realization
> was excluded or retried for an unfavorable score. The fitting summaries retain
> their previous metric-specific sources and values.

The public summaries still use those same reconstructed draws. This revision
does not reconstruct them again. Historical alternative-coupling calculations
are not silently relabeled as current 300/500-target calculations. The
supplement retains the statistical explanation of cross-target draw coupling
and the fact that the original target-level draws were unavailable.

Criterion-specific historical refinement used forecast performance on the
evaluation series. The primary reporting period was shortened after
inspection of longer-period results. These limitations remain in the article
and supplement, rather than being hidden in this note.

The removed archival paragraph is preserved here:

> Historical five-chain point-path and alternative-coupling numerical
> comparisons are not carried into the revised forecast tables because their
> retained summaries do not establish intervals on the current target ranges.
> They remain archived as historical analyses, not evidence of stability of
> the revised draw-wise criteria.

### Historical 50-replicate variational sensitivity

The preserved historical table is:

    tables/joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex

It remains in Git with its original numerical content and source provenance.
It is no longer an active manuscript input or article-upload dependency.
The original qualification is retained in full:

> The separate 50-replicate variational sensitivity analysis below uses the
> earlier feature design and inference implementation. It has not been verified
> under the corrected current posterior target. Its paired AL-minus-exAL
> forecast-MAE differences assess quantile-path recovery and are not pooled
> with the present reservoir-only forecast comparison.

In particular, it is not verified under the corrected current posterior
target. Removing the live historical table does not turn it into replication
evidence for the current model. Its original source and nomenclature receipts
remain unchanged.

### Common posterior target and chain verification

All chains for a given reported model use the same data, likelihood and
prior hyperparameters; only their starting values differ. Target-hash
verification and the history of prior/initialization corrections remain in
the existing scientific handoffs and manifests. They are not model
definitions or numerical convergence proofs.

### GloFAS prior settings and selection history

The original implementation distinction was:

> The three historical Normal Ridge fits use coefficient prior variance
> 10^4 and intercept variance 10^6; the selected-candidate setting of 100
> is not their executed coefficient prior variance.

The fitted variances remain 10^4 and 10^6. The issued-ensemble Gaussian
ridge fit retains coefficient precision one and intercept precision 10^-9.
No earlier candidate setting is substituted for a fitted prior.

Code inspection of the historical shortlist procedure confirmed that the
additional periods previously called guardrail folds were selection checks:
their mean scores impose an eligibility threshold against excessive forecast
deterioration. They must not be re-described as independent post-selection
evaluation. The final issued window remains excluded from selection.

## Display corrections

The updated labels describe the same quantities and paths:

- GloFAS discrepancy is transformed retrospective GloFAS minus transformed
  USGS, not log discharge itself.
- The maximum response lag is not an estimated reservoir-memory length.
- Empirical quantile-frequency columns are labeled by probability level p,
  not by quantile values q_p.
- Fixed ridge prior variance kappa_beta^2 is not a posterior RHS global
  scale; the learned effective-scale range remains a separate summary.
- Gaussian DESN model names identify ridge or RHS regularization; VB is
  reported as the inference method rather than attached to only one label.
- Q–DESN/MQ–DESN display names remain distinct from internal lookup keys.

Frozen scientific source PDFs and tables are retained. Label-only
derivatives and caption transformations carry explicit source hashes and
scientific-vector/numerical invariance checks.

## Reproduction and validation

Use pinned R 4.6.0 and Python 3.11 with a PDF-capable environment. The bounded
Sections 5–7 renderer supports exclusion of PriceFM regeneration; excluded
output hashes and role receipts must still verify.

    python scripts/build_qdesn_sections5_7_presentation.py --exclude-pricefm
    Rscript scripts/build_independent_forecast_300_500_v1.R
    python3.11 scripts/audit_qdesn_article_dependencies.py \
      > docs/reproducibility/article_dependency_inventory.csv

Use the semantic, mathematical, independent-authority, nomenclature and
presentation checks named in the execution record, then build identified
and anonymous main/supplement proofs and the isolated article-only source.
No historical fit builder or scientific scheduler is needed.

Git integration and Overleaf publication follow AGENTS.md and CONTRIBUTING.md.
Remote completion requires fresh commit/tree/source-marker readback, not
merely a local build or successful fetch.
