# Extended calculations and complete numerical summaries

The shorter Online Appendix retains the statistical targets, implementable
updates and evidence needed for the article. This index locates longer
exposition and complete numerical displays that are no longer printed twice.
No fitted model, forecast, score, original scientific figure or evaluation
design is replaced by this editorial revision.

## Immutable source version

The complete preceding account is preserved at commit
`a9220a25e978b50180beabe3e243bcab963f2ca1` in the
[public article repository](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/tree/a9220a25e978b50180beabe3e243bcab963f2ca1).
It builds to a 37-page article and 70-page identified Online Appendix in the
documented review layout. Those counts include title pages and references.

**Known written correction.** The immutable preceding appendix contains one
incorrect source-specific exAL scale-kernel expression at line2063: its
`psi_c` omits the divisor `B_gamma`. The current appendix corrects that written
formula. The producer's **v augmentation** already used the divisor; no fit
or numerical result is changed. Do not use the archived formula as if it
were the corrected expression. See the correction and source trace below.

## Extended mathematics

| Material | Immutable source | Current reader account |
|---|---|---|
| Gaussian global-prior-scale reference and orthogonal-design expectation | [Earlier appendix, lines329–364](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex#L329-L364) | Reference formula, scope for correlated predictors, and transformed-intercept prior remain in AppendixA |
| Separate AL/exAL latent-variable statements | [Lines409–493](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex#L409-L493) | Common Gaussian/GIG updates and explicit AL specialization in AppendixA |
| Full repeated conjugate VB updates | [Lines609–738](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex#L609-L738) | Variational family, coefficient covariance, residual second moments and exact scale-update substitutions remain in AppendixA |
| Extended transformed Laplace–Delta exposition and iteration schedule | [Lines740–816](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex#L740-L816) | Transform, Jacobian, mode/Hessian approximation, induced density, moment approximation and compact schedule remain in AppendixA |
| Expanded forecast-score definitions | [Lines1210–1273](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/qdesn-supplement.tex#L1210-L1273) | Main Section4 defines general scores; AppendixC retains the actual forecast functional, ordering rule, study weights, expected-score construction and uncertainty interpretation |

The structured exAL scale integral, supported shape quadrature and mixed
moments remain in the reader appendix. So do the full NS joint-prior factors,
the scale-dependent Gaussian product mass, the anchored multiquantile
difference prior and its cross-level covariance. They were not replaced by
citations or by an assumption that conditional variances identify the entire
prior.

## Complete multiquantile tables

The single current score table reports both the averaged-predictor and
trajectory-specific means and95% intervals for all32 MCMC cells. The
following complete earlier displays remain byte-preserved:

- [Primary scores, medians and scores at posterior-mean grids](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/qdesn_multiquantile_score_display.tex).
- [Primary and trajectory-specific score comparison](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/qdesn_multiquantile_recursive_policy_display.tex).
- [Expanded design/computation table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/qdesn_multiquantile_design_display.tex).
- [Full-precision method/model score summaries](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/joint_qdesn_pure_desn_v2_forecast_score_summary.csv).

The complete data preserve medians and the score at the projected
posterior-mean grid, which is distinct from the posterior mean of the score.
Removing duplicate printed columns changes neither quantity. The current
appendix retains score-sequence diagnostics and their limitations; they must
not be interpreted as proof of complete scalar-parameter mixing.

## Historical global-scale catalogue

The [complete24-row historical prior and effective-global-scale table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/glofas_reference_discrepancy_priors_display.tex)
is retained unchanged. Its effective global scale is
`{E_q(tau^(-2))}^(-1/2)`, not the fixed prior hyperparameter`tau0`.
Ranges are across quantile or adjacent-difference blocks; singleton ranges
are still singleton measurements.

The reader appendix retains the fixed historical hyperparameters, slab
rules and family-specific exceptions. In particular, the discrepancy-only
Gaussian RHS model learns its slab whereas the other historical discrepancy
slabs are fixed at16. These historical specifications do not automatically
identify the priors of the issued-ensemble correction.

The [complete historical recursive score table](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/a9220a25e978b50180beabe3e243bcab963f2ca1/tables/glofas_reference_discrepancy_scores_display.tex)
also remains unchanged. The compact printed table keeps all12 scored rows;
its note replaces six identical all-dash discrepancy-only rows. Those models
remain unscored after the origin because retrospective GloFAS ends there.
Missing scores and crossing counts are not zero measurements.

## Issued-ensemble priors: authenticated source distinction

The current quantile producer is
`fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6`, with posterior-target hash
`72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03`.
Its published article lineage pins input-manifest hash
`f298dac4dd45479bd847528feab6d1104a8086f2c85116c8568acc53c871ae7f`.

A bounded read-only check verified all16 task configurations, each smaller
than8KiB, against that input manifest. Their coefficient/source-prior hash
is common:
`d7549e8287c6bf37ee1dafbdc70b0fcc5921307484e9c9658a8140a1926ed65b`.
No fitted object, posterior draws or future scoring observations were opened.

| Quantile-fit prior setting | Reference | Discrepancy |
|---|---:|---:|
| Fixed global hyperprior scale`tau0` | `5.2043087e-05` | `0.0001159` |
| Learned slab-variance prior | IG(2,4) | IG(2,4) |
| Gaussian intercept precision | `1e-9` | `1e-9` |
| Source likelihood-scale prior | IG(2,1) | IG(2,1) |

The configurations additionally contain`s2=4` for the RHS initialization;
the slab is subsequently learned, not fixed at4. The issued quantile-fit
constants are the rounded executed values above, not the more precise
historical-model constants. The separately reused Gaussian baselines have
their own authenticated configurations; this check does not claim that their
priors equal those of the16 quantile producers.

The [preparation procedure at the producer commit](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6/application/scripts/prepare_glofas_family_transition.R#L76-L101)
binds each configuration and prior digest into the target. The
[control mapping](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6/application/R/glofas_family_transition.R#L215-L238)
explicitly preserves the destination priors while resetting numerical
starting/stopping state.

## Written exAL kernel correction

For the defined conditional variance`sigma_c B_gamma v_i` and mean shift
`sigma_c D_gamma s_i`, expanding the Gaussian squared residual gives
`psi_c=(D_gamma^2/B_gamma) sum_i s_i^2/v_i`. The archived line2063 omitted
`1/B_gamma`.

- [Pinned source call requests the v augmentation](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6/application/R/latent_path_vb_exal.R#L118-L129).
- [Pinned structured helper includes the divisor](https://github.com/AntonioAPDL/Article-Q-DESN---Version-2/blob/fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6/application/R/joint_exqdesn_exact_structured_inference.R#L988-L1001).

The helper's distinct u-augmentation branch has a different expression;
it does not justify omitting the divisor in the written v hierarchy. The
editorial correction preserves the equation's identity and changes no
inference code or numerical result.

## Rebuilding the earlier account and the current presentation

Use a separate clean clone or detached worktree at the immutable commit to
rebuild the earlier account. Never switch or reset a worktree occupied by a
scientific task. Both documents use pdfLaTeX followed by BibTeX and enough
pdfLaTeX passes to stabilize references. The review-proof entry point is
`scripts/build_technometrics_review.sh`; it does not fit models or publish.

For the current compact table/caption derivatives:

```bash
/usr/bin/python3.11 scripts/build_appendix_compact_tables_20261106.py --check
```

The builder authenticates its enumerated public inputs and checks numerical
keys and rounding before comparing all new TeX outputs byte-for-byte. Its
write mode creates only the named compact derivatives. It never overwrites
the archived tables, scientific CSVs, original PDFs or model objects.

The current semantic successor, disposition map and implementation receipt
record which roles are printed, consolidated or archived. This index is not
scientific qualification of the paused GloFAS optimizer or a replacement for
the actual campaign contracts and data-access requirements.
