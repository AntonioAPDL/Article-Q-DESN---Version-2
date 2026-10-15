# Article dependencies and execution map

Prepared 2026-10-08 for the Technometrics editorial/review pass. This record
implements the v3 plan's T01 inventory and separates presentation reproduction
from the fitting and scoring workflows. It does not certify journal submission
readiness, complete scientific reproducibility, or historical-project closeout.
No fitting or scoring workflow below was launched to create this map. The
bounded presentation and build checks were repeated during the subsequent
editorial revision.

## Independent evaluation reporting revision

The 2026-10-15 independent revision supersedes the earlier full-period
forecast presentation: 300 scored targets are primary, 500 are supplementary
sensitivity, and 1,000-target numerical reporting is deprecated. This is a
retrospective scope change, not an improvement to a fitted model. Historical
selection and full-period evidence remain archived. Fit summaries and fit
graphics are unchanged; VB forecasts are explicitly omitted because retained
aggregate draws cannot recover prefix intervals. See
`docs/implementation_notes/independent_forecast_300_500_reporting_20261015.md`.

Use `scripts/build_independent_forecast_300_500_v1.R` and
`scripts/check_independent_forecast_300_500_v1.R` for current IND assets.
The policy, source summaries and current manifest are separately named; old
v14 drivers are historical reconstruction entry points, not the current
forecast publisher. The shared presentation builder delegates its IND work
to the new renderer. No inference or other-lane rendering is needed.

The subsequent forecast-focus revision keeps check loss in the main article
and moves primary quantile-path MAE to the supplement. Existing 144 forecast
and 72 fitting summaries and all four forecast PDFs are unchanged. A separate
empirical-frequency diagnostic uses the existing 36 check-loss specifications,
all three retained chains, and a target-wise pooled posterior median. It
reports observed fractions below these point summaries for both target ranges,
not posterior or sampling confidence bands. No fitting, forecast simulation or
new source selection is involved.

`application/config/independent_forecast_calibration_v1.json` fixes that rule
before extraction. `scripts/extract_independent_forecast_calibration_v1.R`
reads the protected forecast-path objects through their frozen validation
registry and verifies source hashes. It emits compact summary/source receipts
only; draws and individual target forecasts are not published. The
read-only `scripts/check_independent_forecast_calibration_v1.R` validates the
compact evidence without loading runtime objects. The usual IND renderer
creates the supplementary figure/table from those summaries, reusing the
frozen forecast figures unless explicit regeneration is requested.

## Dependency inventory

[article_dependency_inventory.csv](article_dependency_inventory.csv) contains
one row for every approved file in `overleaf/article_files.txt`: file, reader
role, symbolic current scientific authority, source-contract pointer, estimator
scope, current SHA-256, source-inferred manuscript consumer, and direct/alias
input edges. The `source_contract` is a provenance entry point, not a claim that
each row independently authenticates its underlying fits. Estimator scopes are
family-level descriptions; the named numerical source determines a particular
row's exact estimator. Historical Phase153 and five-chain point-path assets are
explicitly distinguished from current headline authorities.

The read-only standard-library script
`scripts/audit_qdesn_article_dependencies.py` resolves the current literal
`input`, `includegraphics`, bibliography, and file-alias conventions, applying
the GloFAS review overrides after the original aliases. It rejects missing
files, unresolved file aliases and source-inferred dependencies omitted from
the sorted allowlist. It writes CSV only to stdout and does not change assets,
compile TeX, inspect model payloads, or fit/score a model. Validate the checked-in
inventory from the repository root with:

```bash
python3.11 scripts/audit_qdesn_article_dependencies.py --check docs/reproducibility/article_dependency_inventory.csv
```

Without `--check`, stdout is the deterministic replacement CSV. Regenerate it
after any final manuscript, alias, allowlist, bibliography or display edit;
otherwise its current-file hashes are intentionally stale. The script does
not interpret arbitrary TeX conditionals or macro expansion. Its consumers
are therefore labelled **source-inferred**, not recorder-certified. The final
identified/anonymous builds' `.fls` files remain the stronger proof of actual
compile inputs. Check them and the isolated article snapshot before publication.
The inventory and audit script are repository/reproduction documentation, not
new mandatory TeX dependencies; no change to the article allowlist is needed.

Original scientific PDFs and wrappers remain frozen in the research repository.
The MQ--DESN nomenclature revision selects separately named, label-only display
derivatives for the multiquantile simulation and full-family GloFAS figures and
tables. Superseded display files are not uploaded merely because they remain
in Git. Independent fitting graphics and the common-window main GloFAS figure
are unchanged; current independent forecast graphics follow the scope revision
above. CSV/provenance companions are not mislabelled direct TeX
inputs. This distinction also covers the PriceFM PNG companion and inactive
independent wrapper files retained by the approved projection.

### Reader-facing model names

`tables/qdesn_model_display_names.csv` maps the existing model identifiers to
Q--DESN for independent quantile regressions and MQ--DESN for multiquantile
regressions, with AL/exAL qualifiers. It is a display registry, not a new model
definition. Original identifiers, statistical targets, numerical summaries,
and source hashes are unchanged. Generic uses of “joint,” including a joint
posterior or the GloFAS historical reference--discrepancy model, remain valid.

The bounded renderers `scripts/build_joint_qdesn_mq_presentation.R` and
`scripts/build_glofas_mq_review_figures.py` authenticate their frozen sources
and generate only presentation copies. Their `--check` modes rebuild in
temporary directories and compare against the published outputs. The GloFAS
renderer requires the pinned PyMuPDF environment identified in its receipt.
`scripts/build_qdesn_historical_display_overlays.py` separately preserves the
historical scope of the replicated-VB comparison and updates the independent
metric-dependence note without editing its frozen source.

`scripts/check_qdesn_mq_nomenclature.py` verifies the registry semantics,
original scientific manifests, derivative hashes, effective TeX inputs and
aliases, and the selected PDF legends. Thus an unchanged old source asset is
not mistaken for the display currently used by the manuscript. The isolated
mutation tests include stale inputs, swapped likelihood labels, independent
models renamed as MQ--DESN, and missing or modified presentation receipts.

## Reader-centered simulation and application presentation

The earlier Sections 5--7 presentation revision left numerical and execution
authority unchanged; the subsequent independent reporting revision above is
a separately declared change of evaluation scope.
`tables/qdesn_sections5_7_presentation_manifest.json` authenticates the original
assets and their descriptive-label derivatives. The bounded builder
`scripts/build_qdesn_sections5_7_presentation.py` generates these copies; its
companion checker verifies permitted changes and the effective TeX selections.
Document-specific override files distinguish the four-column main GloFAS
score table from the full supplementary component comparisons. Only the
main reduction-versus-raw column is omitted; all seven families and retained
values are unchanged. The common-window Figure 4 is byte-identical.

Supplementary GloFAS graphics use reference, discrepancy, combined-history,
and issued-ensemble descriptions instead of development-stage numbers.
The PriceFM regional display distinguishes the fixed-regional comparison
from historical case-specific selection without campaign codes. Its vector
marks are preserved under the recorded page-placement transformation; no
forecast, score, region ordering, or comparison identity is changed.

The main article now pairs design and results subsections for each simulation.
Exact single-quantile generating parameters and metric formulas are in the
supplement. The independent comparison remains criterion-specific and retains
historical forecast-guided selection; the multiquantile selection uses
separate source series. The package-paper citation does not relabel execution
versions. The supplemental execution account retains the scoped exDQLM
1.1.1 refresh and earlier inherited Q--DESN source records. Primary
multiquantile intervals still condition on averaged future features, with
draw-recursive sensitivity separate. These distinctions are not changed by
editing prose or figure captions.

## Prominent-result presentation reproduction

The self-contained example assembled by
`scripts/build_qdesn_reproducibility_example.sh` supplies
`scripts/reproduce_qdesn_joint_forecast.R`,
`scripts/qdesn_evaluation_figure_style.R`, and the frozen
`tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv` (SHA-256
`a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c`).
It selects the complete 32 MCMC cells and reproduces:

- `tables/joint_qdesn_pure_desn_v1_score_table.tex`, byte for byte;
- `figures/joint_qdesn_simulation/joint_qdesn_pure_desn_v1_forecast_dgp_acrps.pdf`,
  with equal extracted text and 150-dpi appearance under the tested renderer.

This example reproduces the frozen scientific projection, not the later
typographic derivative. The supplied summary also contains VB rows, but they are not substituted for
the main MCMC comparison. `scripts/reproduce_qdesn_representative_result.sh`
verifies input hashes and compares against the supplied expected outputs. PDF
container timestamps are not a scientific difference. Dependency/font changes
can produce a reported visual mismatch. See `representative_result_README.md`
for requirements and the exact command delivered with the standalone example.

The broader tracked projection driver
`scripts/build_joint_qdesn_pure_desn_article_projection.R --published-sources`
verifies fifteen immutable public source CSVs and regenerates the corresponding
article tables/figures without fitting or scoring. Its default mode instead
requires the original authenticated 54-file handoff. Neither mode reconstructs
posterior draws or integrated scores. The summary-only example does not claim
to satisfy an inaccessible current journal-specific code/data requirement.

### Active presentation derivatives

The main GloFAS figure now uses
`scripts/build_glofas_figure4_common_window.R`. All three panels share the
30 historical dates and 28 issued forecast dates. The two model panels add
posterior-mean fitted conditional quantiles from the same retained Part 4
fits; their forecast ordinates are unchanged. A separate input provenance
record and `tables/glofas_figure4_common_window_manifest.json` authenticate
this presentation-only extension. No fit, score, model choice, or prior is
changed. The model panels repeat the historical and held-out USGS values and
share identical date limits, tick positions, and plotting-area widths.

The compact historical-quantile CSV suffices for public reproduction. Its
read-only extraction checks the retained fit and design hashes before using
historical features. For AL it averages the conditional quantile readout;
for Normal Ridge it averages the conditional Normal response quantile,
including the posterior mean residual standard deviation. These are fitted
conditional quantiles, not coefficient credible limits. The original 28-date
forecast summaries are used directly and are not reconstructed or rescored.

`scripts/build_qdesn_pro_review_presentation.R` reads the pinned public
simulation summaries, frozen GloFAS quantile table, and compact authenticated
plotting inputs. It creates the six larger-label simulation PDFs, three-panel
GloFAS PDF, five table/figure wrappers, and seven-family main score table listed
in `tables/qdesn_pro_review_presentation_manifest.json`. Its thirteen outputs
reproduce byte for byte in the recorded environment. It does not fit a model,
reconstruct posterior draws, rescore a forecast, or change a scientific grid.
This historical builder and its thirteen outputs remain unchanged; the new
common-window main figure is generated separately.

The compact GloFAS history, member and truth CSVs and their provenance record
are public repository inputs, not required TeX files. The extraction script
`scripts/extract_glofas_pro_review_plot_inputs.R` requires the authentic frozen
design object and verifies its hash before extracting 30 historical dates,
51 members over 28 target dates, and 28 held-out truth values. The public
extracts suffice to reproduce the new drawing without redistributing the
runtime design object. Their derivation does not authenticate unavailable
issued-product metadata or covariate vintages.

The exact extraction checks, geometry, font-size checks and standalone commands
are documented in
`docs/implementation_notes/pro_review_presentation_revision_20261008.md`.
The older `scripts/build_glofas_review_figures.py --check` still verifies its
six frozen-vector display derivatives; its override now points to the new main
figure and retains a separate full-family supplementary alias.

## Fit and score workflow map

These are verified-existing tracked entry points and their source-contract
roles, **not commands to run during editorial preparation**. Exact historical
execution is determined by frozen provenance, configuration, source commits
and payload hashes; the existence of current code alone is not proof that a
new execution reproduces a historical result.

| Current authority | Fitting/selection and forecast-score lineage | Article projection and checks | Retained evidence and access boundary |
|---|---|---|---|
| Independent 300 primary / 500 sensitivity | Frozen case-specific v14 sources reconstructed at recovery HEAD `bba23c9317a37ee1c0b6ac181c7cc37bbd4e1513`; three-chain draws repooled by `validation/fitforecast_v2/scripts/build_independent_forecast_reporting_v1.R`. No inference, forecast resimulation or winner reselection occurs. Historical package runtimes are preserved. | `scripts/build_independent_forecast_300_500_v1.R`; `scripts/check_independent_forecast_300_500_v1.R`; policy `application/config/independent_forecast_300_500_v1.json`. | 144 current MCMC forecast cells, 72 unchanged MCMC/VB fit cells, numerical replay, DGP references, VB omission ledger and source/asset manifests. Raw fitted samples and joint paths remain protected in the separate validation tracker. Current intervals condition on selected sources, simulated data, native model-specific dependence and evaluation windows. |
| Independent rolling-state v14 historical lineage | Frozen compatibility authority `5b85bb3a3894a88968e4987f330e3ec66711f9c7`, scoped exDQLM 1.1.1 refresh and earlier Q-DESN runtimes; configuration `application/config/independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.yaml`. | Original `build_independent_validation_...v14.R` and matching check/finalize drivers remain historical entry points, not the current forecast publisher. | Original full-period summaries and manifests remain archived. They cannot supply prefix intervals without retained joint paths or sufficient draw-level sums; obsolete numerical panels are excluded from the current article projection. |
| Expanded pure-DESN JOINT | `application/scripts/prepare_joint_qdesn_pure_recursive_campaign.R`, `prepare_joint_qdesn_pure_recursive_expanded_screen.R`, `run_joint_qdesn_pure_recursive_worker.R`, `prepare_joint_qdesn_pure_recursive_confirmation.R`, and `run_joint_qdesn_pure_recursive_article_vb.R` / `run_joint_qdesn_pure_recursive_article_mcmc.R` map selection and fitting. `prepare_joint_qdesn_pure_recursive_quantiles.R` and `run_joint_qdesn_pure_recursive_quantile_worker.R` map selected quantile fitting. `prepare_joint_qdesn_pure_recursive_score_packet.R` prepares the score contract; `run_joint_qdesn_recursive_mean_forecast_worker.R` and `run_joint_qdesn_recursive_dgp_oracle_worker.R` execute recursive cell scoring and oracle shards. Implementations are in `application/R/joint_qdesn_pure_recursive_campaign.R` and `application/R/joint_qdesn_recursive_mean_score_packet.R`. Fitted source is `e39b061e69e176c35369fae9df0657e7b484e443`; article handoff lane is separately identified by projection provenance. | `scripts/build_joint_qdesn_pure_desn_article_projection.R` and `scripts/check_joint_qdesn_pure_desn_article_projection.R`; the small standalone example above is a subset of this presentation layer. | Fifteen pinned public CSVs retain selected backbones, full summaries, sampler/target hashes, contrasts, crossings and review qualifications. Full fit/score reconstruction additionally needs simulation fixtures, exact frozen cell contracts, retained fits/draws, recursive score/oracle shards and the original handoff manifests. Large payloads are not in the article-only projection; current posterior score intervals are not repeated-DGP uncertainty. No new campaign or recovery is authorized here. |
| GloFAS Search III Parts 1--4 | `application/scripts/427_prepare_glofas_search3.R`, `428_run_glofas_search3_worker.R`, `429_score_glofas_search3.R` and `431_check_glofas_search3.R` map protected development/confirmation. `423_run_glofas_quantile_certification_continuation.R`, `386_run_glofas_part4_latent_family_job.R` and `389_continue_glofas_part4_joint_fit.R` are fitting/continuation entry points, not display renderers. `445_build_glofas_search3_final_closeout.R` and `446_check_glofas_search3_final_closeout.R` assemble/check the complete scientific authority. Current Part 4 AL/exAL terminal sources and partitioned RHS hashes are separately recorded in the completion audit; they must not be replaced by a generic Parts 1--3 base commit. | `application/scripts/447_build_glofas_search3_article_projection.R`, `448_check_glofas_search3_article_projection.R`, and `application/R/glofas_search3_article_projection.R`. The separate `scripts/build_glofas_review_figures.py` derives display lettering from authenticated vector sources without loading fit/forecast payloads. | Tracked publication/source-hash manifests, full-precision score/calibration/prior/quantile summaries and original vector panels preserve the complete comparison. Full analysis needs frozen USGS/GloFAS/weather materialization, the executed oracle-covariate design, reservoir inputs, latent-path and fit/continuation state plus original closeout sources. Public quantile summaries lack Part 2's complete display input history and are not enough for all original figures. Part 2 remains unscored; Part 4's 1/51 augmented-member weighting, latent path and driver prior must be reproduced, not replaced by a known-future-design fit. Unauthenticated issued-product/weather metadata and Part 4 historical N remain explicit gaps. |
| PriceFM R98 | `application/scripts/pricefm/316_prepare_pricefm_stage_r97_global_region_campaign.py`, `317_prepare_pricefm_stage_r97_region_quantile_surface.py`, `318_closeout_pricefm_stage_r97_region_quantile_surface.py` and `319_orchestrate_pricefm_stage_r97_global_campaign.py` map frozen region fitting/selection. `320_score_pricefm_stage_r97_frozen_case.py` performs scoring without refitting/reselection; `312_run_pricefm_stage_r96_scoring_only_fold.py` records the separate R96 scoring/reuse path. `329_prepare_pricefm_stage_r98_validity_first_authority.py` and `330_closeout_pricefm_stage_r98_validity_first_authority.py` reconcile the complete 114-case authority, not a new 114-case fitting campaign. | `scripts/build_pricefm_r98_article_projection.py` and `scripts/check_pricefm_r98_article_projection.py`; focused test `application/tests/test_pricefm_r98_article_projection.py`. | Tracked registry, transition ledger, region/fold/global comparisons and projection manifest retain all 38 regions x 3 folds and labelled R92 sensitivity. Full reconstruction needs the frozen released `FINAL.csv`, matched PriceFM predictions, exact region/window/preprocessing manifests, selected seven-level coefficients/fits and R97/R96 scoring terminals, including reused SE_2 evidence. Private runtime payloads are not in the article ZIP. Released lead-covariate vintages were not separately verified; no operational information-parity or joint PriceFM claim follows. |

The map distinguishes current scientific-source provenance from presentation
generation. Existing campaign launchers can mutate caches, produce large jobs,
or require guarded runtime authority; they must not be run just to validate
the manuscript. Reproduction access, resource needs and third-party-data
conditions require a separate deliberate arrangement before full scientific
reruns. No private absolute filesystem paths, credentials or runtime payloads
are disclosed in the standalone example or added by this record.

## Finalization gates

After all current edits, verify inventory equality, unchanged scientific
sources, authentic manifest/finalizer receipts, the four review proofs and
recorder closure, final-size graphics, and the committed isolated source
projection. Author contact details have been checked against official UCSC
sources; the authors confirmed no specific funding and no competing interests.
Anonymous portal handling and current journal length/upload rules remain
subject to the current official instructions. Record exact final
source/publication commits elsewhere; a locally generated CSV cannot establish
remote publication or close a historical scientific obligation.
