# Direct quantile regression and crossing exposition

Starting authority: `a8168fcf23c054dd486e9cc372270f8dfec74bb4`.
This is an editorial revision of the introduction. Scientific models,
initializers, priors, posterior targets, numerical evidence, and ordering
rules remain unchanged.

## Requested distinctions

- Remove the detailed McDermott–Wikle model contrast while retaining credit
  for Bayesian spatiotemporal DESN.
- Explain interval forecasts as pairs of fitted response quantiles, without
  a separate residual-calibration regression or bootstrap construction.
- Present joint conditional-quantile readouts as estimated within one Bayesian
  regression, with MCMC and model-specific VB derivations. “One regression”
  is a statistical formulation, not a single numerical iteration or absence
  of preliminary starting-value fits.
- Retain the documented simultaneous residual-quantile estimation of Bonas
  et al.; do not claim that joint quantile estimation itself is new.
- Organize crossing methods by whether ordering is performed after fitting,
  enforced during estimation, or encouraged through shrinkage.

The direct-estimation contrast does not imply that the reported joint grids
avoid post-estimation ordering. The actual score still uses isotonic-projected
quantile ordinates, as defined in the main methods and supplement.

## Primary evidence

The author's [hydrologic paper, Section 2.4](https://arxiv.org/html/2608.11222v2#S2.SS4)
first applies isotonic regression to independently fitted quantile anchors,
then monotone rearrangement to the interpolated synthesized curve. The
existing DeLeon–Prado–Sansó citation therefore supports both ordering
operations. This audit does not change its bibliographic publication status.

[Kohns and Szendrei, Section 2.2 and Appendix D](https://arxiv.org/pdf/2506.13257)
motivate difference shrinkage through near-parallel quantile functions and
explicitly note that exact noncrossing is not assured. Their “continuous
approximation” language is a soft-regularization interpretation, not an
identity between an unrestricted prior and an ordered parameter space.

[Szendrei, Bhattacharjee, and Schaffer, Section 2.3, Theorem 1](https://arxiv.org/pdf/2403.14036)
relate domain-scaled noncrossing restrictions to intercept-dependent fused
shrinkage bounds. This does not establish equivalence for the Q–DESN RHS
hierarchy or an arbitrary continuous shrinkage penalty. No such equivalence
is claimed in the article, and no new citation is needed solely to assert one.

## Independent mathematical check

For adjacent levels at common predictors, write
`g_k = beta_0k - beta_0,k-1` and `Delta_k = beta_k - beta_k-1`.
The location gap is `g_k + x' Delta_k`. By Hölder's inequality it is at least
`g_k - ||x||_infinity ||Delta_k||_1`.
On a bounded predictor domain with maximum norm `M`, the sufficient condition
`M ||Delta_k||_1 <= g_k` ensures noncrossing for that pair. The present prior
does not enforce that condition. Ordered intercepts and small slope
differences explain a tendency toward ordering; they do not guarantee it.

The introductory explanation therefore describes continuous shrinkage toward
similar slopes, reduced predictor-dependent gap variation, and the remaining
possibility of crossings. The complete existing gap expression and
bounded-domain condition in the supplement are unchanged. The source paper's
text-extracted Appendix D formula is not copied as a replacement derivation.

## Verification and publication boundary

The editorial regression now verifies direct interval construction, joint
regression/VB context, accurate predecessor credit, the hydrologic citation,
and the shrinkage-versus-constraint distinction. Its former exact prose
assertions are replaced by equally strong statistical checks rather than
requiring deleted commentary. The dependency inventory is regenerated.

Validate focused manuscript checks, four identified/anonymous proofs, and
the isolated article-only bundle. Integrate with `--no-ff` in a new main-based
worktree and use the guarded command-line Git publishers. No runtime,
posterior draw, model object, ignored receipt, or new scientific result is
part of this revision.

Completed source-tree checks:

- `test_qdesn_reader_focused_editorial_revision.R`: 43 checks passed.
- `test_pro_review_bibliography_initialization.R`: passed.
- `check_qdesn_final_manuscript_revision.R`: passed; 19 scientific-file
  identities, 216 independent interval roles, and 32 joint oracle/forecast
  roles retained.
- Article dependency inventory: all 103 allowlisted files verified.
- `git diff --check`: passed.
- Identified manuscripts: main 36 pages, supplement 83 pages.
- Anonymous manuscripts: main 34 pages, supplement 82 pages; identifying
  text and PDF metadata checks passed.
- All four final LaTeX logs passed the build script's warning, reference,
  and box-overflow gates.

An independent editorial review accepted the direct-estimation distinction,
predecessor credit, and qualified noncrossing mechanism. These are bounded
editorial and publication checks, not a claim that every historical
scientific fixture or the complete repository test suite has been rerun.
