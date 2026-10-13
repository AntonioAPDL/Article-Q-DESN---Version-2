# Reader-focused Q–DESN editorial revision

## Scope and scientific authority

Starting authority: `1c95187013b6eb9fe04f7c641e90de6afb784337`.
This revision changes statistical exposition and a visible score name, not
models, priors, selection rules, scientific evidence, or numerical results.
It does not authorize changes to active campaigns or any model rerun.

The article now introduces Q–DESN explicitly as Bayesian linear quantile
regression conditional on fixed nonlinear DESN features. It explains the
joint multiquantile extension, AL full conditional tractability, and the
roles of forecasting, scoring, and DESN specification selection separately.
The supplementary mathematics, initialization protocol, and study-specific
posterior approximations remain available in their existing sections.

The closest predecessors receive distinct credit: Bayesian spatiotemporal
DESN, quantile-regression/bootstrap ESN ensembles, and simultaneous residual
quantile sheets with calibration. No priority claim is made for Bayesian
reservoir regression or simultaneous quantile fitting by themselves. The
literature access boundaries are recorded in the preceding
`qdesn_quantile_reservoir_literature_comparison_20261009.md` audit.

## Decisions preserved

- AL and exAL are called likelihoods. The joint posterior remains composite,
  with the same proportional negative-log-likelihood update.
- Standard full conditionals support Gibbs-based AL computation; the
  supplement records the actual GIG log-scale slice transition.
- The Gaussian reference for tau0 is a hyperprior-scale recommendation,
  distinct from numerical starting values. The prior hierarchy, product
  factors, corrected global shape, and fixed common targets are unchanged.
- “Oracle finite-grid aCRPS” names the existing DGP-integrated score. The
  symbol `S_DGP`, columns, quantiles, unnormalized trapezoidal weights,
  numerical values, and scientific source identity are unchanged.
- Scoring still uses isotonically projected grids. Raw crossing rates remain
  separate. The main projection display is removed because the supplement
  already defines it; a short main definition remains.
- Primary JOINT score intervals still condition on averaged recursive
  features. Draw-specific sensitivity and fixed-intercept VB uncertainty
  remain specified in the supplement.
- The four compared JOINT regressions share the selected DESN specification
  and reservoir realization, not necessarily their model-specific future
  feature trajectories.
- Reservoir diagnostics are described without claiming an unverified
  initial-state sensitivity experiment or a proof of the echo state property.
- Actual GloFAS coverage, future-truth exclusion, Part 2 no-score boundary,
  realized-weather information, and the adverse PriceFM aggregate result
  remain. All three abstract findings placeholders remain.

## Presentation invariance

Only the active forecast figure's axis name and associated reader captions
change. A deterministic builder regenerates them from the same authenticated
tabular inputs. The 32 plotted means, intervals, crossing-label coordinates,
axis scales, order, and numerical table bodies were compared unchanged.
The fitting figure remains byte-identical.

Only regenerable article-presentation hashes are refreshed. Original
scientific manifests, scientific CSVs, model code, and the scientific
source-lane identity are not rewritten. The article allowlist is unchanged.

## Reproducible checks

Use pinned R 4.6.0 for the R checks. From the repository root:

```bash
Rscript application/tests/test_qdesn_reader_focused_editorial_revision.R
Rscript application/tests/test_pro_review_supplement_math.R
Rscript application/tests/test_pro_review_bibliography_initialization.R
Rscript application/tests/test_joint_qvp_rhs_global_shape.R
Rscript -e 'source("application/R/00_packages.R"); source("application/R/rhs_global_scale_reference.R"); source("application/tests/test_rhs_global_scale_reference.R")'
Rscript application/tests/test_joint_qdesn_case_a_width_closure.R
Rscript application/tests/test_joint_qdesn_pure_desn_article_projection_v2.R
Rscript application/tests/test_glofas_search3_article_projection.R
Rscript scripts/check_qdesn_final_manuscript_revision.R
python3.11 -m pytest -q application/tests/test_pro_review_presentation.py application/tests/test_glofas_figure4_common_window.py application/tests/test_pricefm_r98_article_projection.py
python3.11 scripts/audit_qdesn_article_dependencies.py --check docs/reproducibility/article_dependency_inventory.csv
bash scripts/build_technometrics_review.sh
git diff --check
```

Python presentation tests require pytest and PyMuPDF in the selected Python
3.11 environment. The new read-only editorial regression is registered in
the existing repository harness. The prior-reference test now checks the
meaning of the prose rather than a particular newline; its numerical checks
are unchanged.

Checks cover the edited article, mathematical invariants, scientific hashes,
presentation provenance, and both identified/anonymous review builds. A pass
does not certify every historical external fixture or resolve all
journal-specific submission requirements. The repository-wide historical
suite is not represented as a newly complete campaign.

## Integration and publication

Freeze and push the editorial branch, then merge it with `--no-ff` in a fresh
integration worktree based on freshly fetched `origin/main`. Verify the exact
two parents and rerun the combined-tree checks. Compile the article-only
allowlist bundle from the committed merge before publication.

Use only `scripts/publish_integration_main_git_only.sh` and
`scripts/publish_overleaf_article_snapshot.sh`, with exact source/merge IDs.
Verify authoritative main and both article deployment refs by fresh Git
readback. No cache, fit object, posterior draw, log, or ignored editorial
receipt belongs in the commit or the Overleaf projection.
