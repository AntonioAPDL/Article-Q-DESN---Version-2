# PriceFM Stage-R67: CRAN 1.1.1 authority and historical reuse

Date: 2026-08-30/31
Lane: PriceFM only
Branch: `work/pricefm-joint-quantile-20260824`
Baseline: `77d7dfbcf9a7897d019c6430e33fbc2122720b8d`

## Executive decision

Do not rerun the full PriceFM surface solely because `exdqlm` moved from CRAN
1.1.0 to CRAN 1.1.1.

The official source and a deterministic numerical probe show that the public
reduced-AL static regression path used with the RHS/RHS-NS coefficient prior is
unchanged between those two releases. In particular, the RHS/RHS-NS prior
implementation, the public AL dispatch prefix, and the static AL CAVI solver
are identical. A patch-version-only AL refit would therefore repeat the same
calculation without answering a new scientific question.

This is not a claim that the whole package is unchanged. CRAN 1.1.1 adds a
structured exAL scale-skewness approximation and reproducibility changes to
stochastic helpers. Stage-R66 also used a later fork-only correction to the
structured exAL tail moments. Consequently:

1. Stage-R62 remains the frozen complete 114-case PriceFM authority under its
   original package and engine provenance.
2. Stage-R65 and Stage-R66 do not replace R62 because neither produced a valid,
   complete, promotable structured-exAL surface.
3. Historical fork-engine fits must not be relabelled as CRAN 1.1.1 fits.
4. Every genuinely new PriceFM static AL/exAL fit must use the exact official
   CRAN 1.1.1 tarball and public API defined below.
5. No broad rerun, registry mutation, test opening, or article update is
   authorized by Stage-R67.

## Scientific question

Stage-R67 answers a narrow but consequential question:

> Does the move from CRAN `exdqlm` 1.1.0 to 1.1.1 invalidate the completed
> PriceFM AL/RHS-NS results and require the full application to be rerun?

The answer is no. The unchanged public AL/RHS-NS path supports reuse. The new
exAL machinery is relevant to future exAL work, but it does not create a valid
replacement for the already frozen authority by itself.

## Frozen input state

| Stage | Verified state | Scientific use after R67 |
|---|---|---|
| R62 | Complete 114-case seven-quantile authority; 27 AL and 87 legacy exAL selections; validation-only selection; test sealed | Retain as current historical authority |
| R65 | Mechanism-failure closeout; 440 hash-valid AL checkpoints; 426 exAL checkpoints; zero structured winners | AL checkpoints remain diagnostic or explicitly declared warm starts; exAL checkpoints stay excluded |
| R66 | One production-gate case attempted; three exAL components present, two eligible; gate case failed at the median; no active process | Retain as failed corrected-mechanism evidence; do not promote or fan out |

Authoritative inputs:

- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r65_early_stop_closeout_20260829`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r66_corrected_structured_exal_vb_20260829`
- `/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/pricefm_stage_r66_corrected_structured_exal_vb_20260829`

## Package evidence

### Immutable release identities

| Release | Official source | SHA-256 |
|---|---|---|
| CRAN 1.1.0 | `https://cran.r-project.org/src/contrib/Archive/exdqlm/exdqlm_1.1.0.tar.gz` | `51bc968f617721c9ab1dcfc6ec14857d30827fcd36659f3de45337cc3c82bd14` |
| CRAN 1.1.1 | `https://cran.r-project.org/src/contrib/exdqlm_1.1.1.tar.gz` | `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e` |

The runtime materializer additionally requires `Package: exdqlm`, `Version:
1.1.1`, and `Repository: CRAN` in `DESCRIPTION`. It rejects an installed
namespace that exposes fork-only functions.

### Source-level identity of the AL/RHS path

| Contract surface | CRAN 1.1.0 vs 1.1.1 result | Canonical hash |
|---|---|---|
| `R/static_beta_prior.R` | Byte-identical | `6f89caf7b25513be16159f6f044ee7d5b268ce06daa4043131f007827e9c0d68` |
| Public `exalStaticLDVB()` prefix through the reduced-AL return | Parsed-expression identical | `b90cf46bfffb0a3e5fc00796c467f9b3ed67ea1d064fb2ee2838a077e7f3242b` |
| Private `.run_static_dqlm_cavi` assignment | Parsed-expression identical | `b24214b2eb356b321a77048d039f505a670526091191020241485ca908abcbaf` |

The parsed-expression checks avoid false differences from comments or source
formatting while still comparing the executable R expression.

### Deterministic public-API probe

The probe fixes the design, response, quantile (`0.25`), RHS-NS `tau0`
(`1e-3`), controls, sample count, and seed (`7731`). The complete serialized
public outputs are exactly equal between official CRAN 1.1.0 and 1.1.1:

- `qbeta$m`: maximum absolute difference `0`;
- predictions: maximum absolute difference `0`;
- iteration count: `59` in both fits;
- convergence: `TRUE` in both fits;
- posterior sample arrays: exactly equal.

This establishes behavioral, not merely textual, equivalence for the relevant
reduced AL/RHS-NS path.

## Essential provenance caveat

The historical R65/R66 PriceFM runners did not call the official public AL path
for their QDESN fits. They called fork-only `beta_prior()` and
`exal_ldvb_fit()` functions and requested exact chunking. These functions are
not exported, or present, in the official CRAN 1.1.1 source tarball.

A deterministic probe confirms that the distinction is substantive:

| Comparison | Result |
|---|---:|
| Fork custom vs official public `qbeta$m`, maximum absolute difference | approximately `0.6976593` |
| Fork custom vs official public predictions, maximum absolute difference | approximately `0.7297367` |
| Prediction RMSE between engines | approximately `0.3086433` |
| Fork custom posterior sigma summary | approximately `0.1057098` |
| Official public posterior sigma sample mean | approximately `0.02563314` |

The custom engine's exact-chunked and non-chunked modes agree to numerical
precision (prediction maximum absolute difference about `2.73e-14`). Thus the
observed custom-vs-public difference is an engine/prior implementation issue,
not a chunk-size approximation and not a CRAN 1.1.0-to-1.1.1 patch change.

The R65 structured scale-skewness helper is byte-identical to CRAN 1.1.1. R66
then changed that helper under commit
`ab5741ceb854db9a53889a17c91d2d30f4d8c41d`; that corrected helper is not
byte-identical to official CRAN 1.1.1. R66 therefore remains fork-qualified
mechanism evidence and cannot be described as an official CRAN run.

## Reuse matrix

| Artifact class | Keep? | Refit now? | May call it CRAN 1.1.1? |
|---|---|---|---|
| R62 complete authority | Yes | No | No; retain original provenance |
| R62 selected AL cases | Yes | No version-only refit | No; retain original engine label |
| R62 selected legacy exAL cases | Yes, as frozen comparator | No automatic refit | No |
| R65 valid AL checkpoints | Yes, for diagnostics or declared warm starts | No | No |
| R65 exAL checkpoints | Keep only as failed-mechanism evidence | No; exclude from selection | No |
| R66 partial corrected exAL outputs | Keep only as failed-gate evidence | No broad continuation | No |
| Future new PriceFM fits | Not yet created | Only for a new pre-registered question | Yes, if the R67 package boundary passes |

## Implemented R67 wiring

### Runtime materializer

`application/scripts/pricefm/materialize_pricefm_stage_r67_cran111_package.py`

- downloads only the official 1.1.1 source URL when the cache is absent;
- verifies the immutable tarball SHA-256 and CRAN `DESCRIPTION` fields;
- installs into an isolated PriceFM runtime library;
- checks required public exports;
- rejects fork-only QDESN exports;
- records source, package, R, export, and install-log provenance;
- performs no fit or launch.

### Public API adapter

`application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R`

- verifies exact CRAN 1.1.1 at runtime;
- calls only `exalStaticLDVB()` and exported control constructors;
- maps AL to `dqlm.ind = TRUE` and exAL to `dqlm.ind = FALSE`;
- preserves case-specific `X`, `y`, quantile, RHS-NS `tau0`, sigma prior, gamma
  prior, and validation-only prediction semantics;
- uses the official structured `q(gamma)q(sigma|gamma)` control for new exAL
  fits;
- records that fork-only chunking/tolerance controls are ignored;
- never claims exact chunking.

### Source and numerical probes

- `application/scripts/pricefm/pricefm_stage_r67_source_contract.R`
- `application/scripts/pricefm/pricefm_stage_r67_cran_al_rhsns_probe.R`
- `application/scripts/pricefm/pricefm_stage_r67_fork_al_rhsns_probe.R`

These scripts isolate the executable source surfaces and deterministic numeric
comparison. They do not score test data or fit PriceFM cases.

### Decision audit

`application/scripts/pricefm/234_audit_pricefm_stage_r67_cran111_rhs_reuse.py`

The audit requires:

1. the exact complete R62 case count;
2. validation-only R62 selection and a closed test firewall;
3. exact frozen R65 AL/exAL checkpoint counts and mechanism-failure status;
4. the exact R66 launch-row count and no active R66 process;
5. source and numerical identity for official 1.1.0-to-1.1.1 AL/RHS-NS;
6. explicit non-equivalence between the fork-only custom engine and CRAN;
7. launch, registry, and article gates to remain closed.

It produces ignored, reproducible CSV/JSON/Markdown evidence under:

`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r67_cran111_rhs_reuse_audit_20260830`

No launch YAML is produced.

## Efficient forward plan

### Phase 1: freeze and validate R67

1. Run focused Python unit tests for package identity, provenance gates,
   validation-only reuse, and no-YAML behavior.
2. Run the R adapter integration test against an isolated official CRAN 1.1.1
   library.
3. Materialize the persistent hash-pinned official CRAN 1.1.1 library.
4. Run the source/numerical/artifact audit and verify all required gates.
5. Run existing focused R62/R65/R66 regression tests and `git diff --check`.

### Phase 2: preserve current scientific authority

1. Keep R62 as the 114-case historical authority.
2. Keep R65/R66 excluded from selection and promotion.
3. Do not reopen test data, mutate registries, or edit the article.
4. Do not relaunch all AL models to change only a package version label.

### Phase 3: permit only question-driven new work

A future new fit is justified only if it answers a pre-registered scientific
question that R62 cannot answer, such as evaluating official CRAN 1.1.1
structured exAL on a bounded unresolved case. Such a stage must:

- use the R67 materialized runtime and public adapter;
- declare whether it is AL or exAL before fitting;
- select only on validation data;
- preserve the R62 comparator and original provenance;
- start with one bounded real-case gate before any fan-out;
- avoid refitting unchanged AL components unless the design itself changes;
- require complete seven-quantile evidence before promotion;
- keep MCMC, registry, test, and article gates separately authorized.

The bounded gate is a future option, not an R67 launch authorization.

## Risks and controls

| Risk | Control |
|---|---|
| Treating all 1.1.1 changes as irrelevant | Limit equivalence claim to public static reduced AL/RHS-NS |
| Relabelling historical fork fits as official CRAN | Immutable artifact reuse ledger sets `may_relabel_as_cran111 = false` |
| Assuming R66's tail fix shipped on CRAN | Compare CRAN, R65, and R66 structured-helper hashes separately |
| Repeating 114 cases without a new estimand | `existing_authority_refit_required = false`; no launch configuration |
| Opening test data during package migration | Require validation-only R62 rows and a closed test firewall |
| Loading the wrong installed package | Verify version, repository, exports, tarball hash, and isolated library |
| Quietly using private functions | Adapter resolves exported public functions only and rejects fork-only exports |
| Mutating publication claims from failed mechanism work | Registry and article gates remain false |

## Explicitly prohibited by R67

- no broad PriceFM rerun;
- no R65 or R66 continuation;
- no fitting of PriceFM models;
- no launch YAML;
- no test-data opening;
- no registry mutation;
- no manuscript or article update;
- no relabelling of historical artifacts;
- no non-PriceFM file or process changes.

## Next decision

After R67 validates, the correct immediate action is to stop. The package
authority problem is resolved without spending compute. A subsequent PriceFM
stage should be created only when there is an explicit new scientific target;
its first action should be a bounded official-CRAN-1.1.1 case, not a replay of
the complete historical surface.

## Validation outcome

The completed R67 materialization and audit produced the following verified
state:

- official CRAN 1.1.1 runtime installed from the pinned tarball into
  `application/data_local/pricefm/runtime_libraries/exdqlm_cran_1p1p1`;
- installed package version `1.1.1`, repository `CRAN`, required public exports
  present, and fork-only exports absent;
- all R67 decision gates passed;
- official 1.1.0-to-1.1.1 deterministic AL/RHS-NS outputs exactly equal;
- custom historical engine vs official 1.1.1 prediction maximum absolute
  difference `0.7297366857232435`;
- `19` focused Python R62-R67 tests passed;
- R65, R66, and R67 R integration tests passed;
- no R65/R66/R67 PriceFM process remained active;
- no launch YAML was created.
