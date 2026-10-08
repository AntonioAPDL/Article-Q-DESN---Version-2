# Article dependencies and execution map

Prepared 2026-10-08 for the Technometrics editorial/review pass. This record
implements the v3 plan's T01 inventory and separates presentation reproduction
from the fitting and scoring workflows. It does not certify journal submission
readiness, complete scientific reproducibility, or historical-project closeout.
No workflow below was launched to create this map.

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

Original GloFAS PDFs are approved companions and scientific sources of the new
separately named review derivatives; only the latter are active after the
review override. CSV/provenance companions are not mislabelled direct TeX
inputs. This distinction also covers the PriceFM PNG companion and inactive
independent wrapper files retained by the approved projection.

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

The supplied summary also contains VB rows, but they are not substituted for
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

## Fit and score workflow map

These are verified-existing tracked entry points and their source-contract
roles, **not commands to run during editorial preparation**. Exact historical
execution is determined by frozen provenance, configuration, source commits
and payload hashes; the existence of current code alone is not proof that a
new execution reproduces a historical result.

| Current authority | Fitting/selection and forecast-score lineage | Article projection and checks | Retained evidence and access boundary |
|---|---|---|---|
| Independent rolling-state v14 | Separate exdqlm validation repository at frozen authority `5b85bb3a3894a88968e4987f330e3ec66711f9c7`; package source `6dba6f2863705e0e90f0ce19e0c75d106d022a52`, version 1.1.1. The tracked article configuration `application/config/independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.yaml` identifies the compatibility and rolling replacement packets, replay code and draw hashes. Fitting/calibration precedes rolling-origin filtering and draw-wise metric assessment; the article driver is not the original fit launcher. | `scripts/build_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R`; `scripts/build_independent_validation_dgp_oracle_figures_v14.R`; matching `check_...` drivers and `scripts/finalize_independent_validation_dgp_oracle_figures_v14.R`. | Tracked article summaries/oracle figure data and manifests preserve 72 point rows, 216 interval roles and estimator separation. Complete regeneration needs the authentic separate validation source/packet/replay inputs through `QDESN_VALIDATION_ROOT`, including retained metric draws. The separate promotion verifier is `validation/fitforecast_v2/scripts/verify_independent_exdqlm_mcmc_rolling_state_fix_v1_promotion.R` in that validation repository, not in the article-only bundle. Missing fixtures are SKIP/BLOCKED, not an article-only reproduction success. |
| Expanded pure-DESN JOINT | `application/scripts/prepare_joint_qdesn_pure_recursive_campaign.R`, `prepare_joint_qdesn_pure_recursive_expanded_screen.R`, `run_joint_qdesn_pure_recursive_worker.R`, `prepare_joint_qdesn_pure_recursive_confirmation.R`, and `run_joint_qdesn_pure_recursive_article_vb.R` / `run_joint_qdesn_pure_recursive_article_mcmc.R` map selection and fitting. `prepare_joint_qdesn_pure_recursive_score_packet.R`, `prepare_joint_qdesn_pure_recursive_quantiles.R`, and `run_joint_qdesn_pure_recursive_quantile_worker.R` map the frozen score/recursive-quantile stage; implementation is in `application/R/joint_qdesn_pure_recursive_campaign.R`. Fitted source is `e39b061e69e176c35369fae9df0657e7b484e443`; article handoff lane is separately identified by projection provenance. | `scripts/build_joint_qdesn_pure_desn_article_projection.R` and `scripts/check_joint_qdesn_pure_desn_article_projection.R`; the small standalone example above is a subset of this presentation layer. | Fifteen pinned public CSVs retain selected backbones, full summaries, sampler/target hashes, contrasts, crossings and review qualifications. Full fit/score reconstruction additionally needs simulation fixtures, exact frozen cell contracts, retained fits/draws, recursive score/oracle shards and the original handoff manifests. Large payloads are not in the article-only projection; current posterior score intervals are not repeated-DGP uncertainty. No new campaign or recovery is authorized here. |
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
projection. Keep author declarations, anonymous portal handling and current
journal length/upload rules unresolved until confirmed. Record exact final
source/publication commits elsewhere; a locally generated CSV cannot establish
remote publication or close a historical scientific obligation.
