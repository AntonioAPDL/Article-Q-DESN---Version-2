# Introduction transitions and scoped likelihood-coverage statement

Starting authority: `bd3233703e1b2a2672b336511e076086cf18236b`.
This editorial change connects fixed temporal predictors, linear quantile
regression, slope regularization, and across-quantile sharing. It introduces
Gibbs-based MCMC before describing VB for repeated fitting and initialization.
No model, prior, sampler, score, figure, or scientific result is changed.

## Coverage evidence and wording

The new request explicitly asks for a concise coverage motivation. It
supersedes the earlier preference to omit that topic from the introduction;
it does not authorize a post-hoc covariance-correction discussion or an
unqualified exAL coverage guarantee.

The summary in the [Yang, Wang, and He publisher record](https://doi.org/10.1111/insr.12114)
supports the concern that coefficient credible intervals under a misspecified
AL quantile likelihood need not attain nominal frequentist coverage. This
does not assert that AL is always misspecified or that all credible intervals
are incorrectly calibrated. An
[accepted author manuscript](https://deepblue.lib.umich.edu/bitstream/handle/2027.42/135059/insr12114_am.pdf)
is indexed, but its full PDF was not retrievable in this audit.

The [Yan, Zheng, and Kottas author manuscript](https://tr.soe.ucsc.edu/sites/default/files/technical-reports/UCSC-SOE-24-01.pdf),
Section 4.2 and Section 4.3 (PDF pages 13 and 16–19), evaluates coverage of
95% regression-coefficient credible intervals across repeated data sets.
The strongest improvement over AL occurs at probability 0.05, across the
reported coefficient/error-distribution combinations and both sample sizes.
At probability 0.25 and 0.50 the comparison is mixed and the differences
are smaller. Consequently, the article attributes the result to their
regression simulations and lower-tail settings, rather than presenting
coverage superiority as a general property of exAL.

The final published DOI is `10.1214/25-BA1507`. Its metadata is already in
`refs.bib`, under the 2026 issue assignment. The journal full text was not
accessible in this audit; the coverage passage was verified in the primary
author manuscript, not represented as a newly read final journal proof.

These empirical coefficient-interval results do not establish nominal
coverage for future-response bands, for DESN-dependent data, for composite
multiquantile posteriors, or for variational approximations. Those are
distinct targets and settings. The manuscript retains their existing
study-specific definitions and actual empirical coverage results.

## Editorial verification

The prose regression now verifies the new AL misspecification statement and
the interval target, simulation attribution, and lower-tail scope of the exAL
claim. The AL conditional-tractability assertion is insensitive to a line
break; its statistical condition is unchanged. The main dependency inventory
is regenerated after the final prose edit. Scientific hashes and the article
allowlist remain unchanged.

Validation and publication use the existing focused manuscript tests,
identified/anonymous main and supplementary builds, isolated article-bundle
checks, and guarded command-line Git integration/publication scripts.
No runtime or ignored audit payload belongs in the tracked revision.
