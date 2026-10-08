# Advisor revision: complete-plan audit and submission preparation

Date: 2026-10-08. Starting authoritative main:
`3f85d92a3e70f1981264d43d4f1686c0db06ed67`.
Preparation checkpoint: `2ced97b4aeaebc76f09caf773f42f770080dce11`.

## Scope and authority

The final v3 advisor plan is the governing editorial specification, SHA-256
`851cf19e71b4db127ff956e7d054714717cbe72ddd2929ccf2caf8723d300cad`.
Its v1 and v2 predecessors are background, not additional conflicting
instructions. The author's subsequent requests authorize implementation and
the established Git integration workflow. This audit distinguishes manuscript
implementation, current numerical authority, journal submission requirements,
and remote publication; completion of one does not certify the others.

The previous advisor revision implemented the statistical reorganization but
left submission preparation separate. The formatting checkpoint was pushed
only to its task branch, not main or Overleaf. Six GloFAS lettering defects,
reference-style preparation, review packaging, and the representative
reproduction package were still open. The present pass addresses those gaps
and the bounded explanatory omissions found below.

No inference routine, fit, selected specification, posterior target, prior
setting, grid, forecast, scoring source, or numerical comparison is changed.
No scientific campaign, transfer, cleanup, or access to Jerez is performed.
The public academic profile governs exposition; official publisher evidence
governs verified formatting rules. No journal-compliance claim is inferred
from a legacy template or production typography.

## T01--T14 disposition

| Task | Implemented treatment | Evidence or remaining gate |
|---|---|---|
| T01 authority/dependencies | Fresh main; exact scientific sources retained; isolated source worktree; recorder-based article closure | Final source and publication receipts must identify the exact commit |
| T02 model/prior agreement | Conditional linear regression, full Gaussian-product prior, fitted zero-baseline anchor, common within-cell target; historical dispositions below | Unrelated historical obligations remain open |
| T03 model before features | Marginal AL/exAL model precedes DESN; reservoir bias and regression intercept separated | Main model/features labels; no dynamic coefficient claim |
| T04 computation | Generic VB--LD, structured quadrature, exact collapsed MCMC and GloFAS Gaussian--Delta distinguished | Supplement computation map and block derivations |
| T05 forecasting/selection | Quantile objects, recursion, integrated score, projection/coupling and initialization separated | Added explicit AQL definition and oracle-target qualification |
| T06 applications | Self-contained GloFAS four-part problem and PriceFM region-frozen design, actual information boundaries | Added authenticated Part 1 count/dates; unresolved metadata below |
| T07 simulations | Complete current packets, fitting/forecast placement, crossing denominators and qualified comparisons | All numerical CSVs and original figures unchanged |
| T08 opening/abstract | Problem-first contribution, predecessors and bounded findings; matching title; 173-word abstract | No operational/calibration/dominance claim |
| T09 supplement | Derivations separated from study details; one initialization diagram; complete product-prior factors | Added explicit joint increment moments retaining covariance |
| T10 discussion/references | Coherence/performance tradeoff, application limitations, focused extensions | Added latent GloFAS qualifier; tested local ASA-compatible bibliography |
| T11 review format | 12-point Letter, double spacing, 26 body baselines, five keywords, shared identified/anonymous sources | Journal-specific page limit/portal rules and author declarations unresolved |
| T12 printed presentation | Concrete GloFAS small-lettering defect addressed through separate vector derivatives, not refitting | Original PDFs/pins retained; separate presentation provenance and QA |
| T13 validation | Focused checks, combined registered harness, four review proofs, representative reproduction and isolated source bundle | Actual PASS/SKIP/BLOCKED receipts, not a blanket historical-test claim |
| T14 integration/publication | Source preparation only; fresh main-based no-ff integration, guarded Git publishers and remote read-back remain separate required steps | No integration/publication success claimed here; Overleaf requires owner sync confirmation/authentication |

## Corrections identified by the independent re-audit

1. Main names AQL but previously did not define it. Equation
   `eq:pricefm-aql-main` now states the equal-level average check loss in
   EUR/MWh, without a factor of two. Aggregation weights each of 114 cases
   equally. This is not trapezoidal aCRPS or a timestamp-pooled score.
2. Oracle fitting RMSE/forecast MAE recover the latent-state conditional
   quantile path; this is not generally an origin-marginal predictive quantile.
3. `eq:supp_joint_increment_moments` states the zero-baseline anchor's
   increment second moments as `(H m)^2 + diag(H Sigma H^T)`. Adjacent-level
   covariance is retained; mean-field separation from other blocks does not
   make all levels independent within the Gaussian slope factor.
4. Discussion now explicitly qualifies conditional coefficient linearity
   for GloFAS, whose future features depend on unknown reference responses.
5. The median position is `k_med`, not `m`, which already denotes lag memory.
6. The six frozen independent metric tables use locally overridden float-page
   placement. Their scientific source TeX and all values remain unchanged.
7. The local bibliography file retains the renamed plainnat LPPL license,
   all author names, author-year labels, quoted titles and DOI/URL support.
   It is **not** branded an official Technometrics template. One protected
   article title receives capitalization only; no bibliographic fact changes.

## Controlled compression/relocation ledger

| Passage/function | Treatment | Current reader pointer |
|---|---|---|
| Quantile target and marginal regression | Retain in main, before reservoir recursion | `sec:model`, `eq:qdesn-marginal-main` |
| Mixture/auxiliary exposition | Move principal explanation to computation; retain derivation in supplement | `sec:inference`, `eq:qdesn-aug`, supplementary likelihood section |
| DESN literature catalogue | Consolidate closest predecessors in introduction; omit repeated history | Introduction, DESN feature subsection |
| Fixed-feature/working-likelihood qualification | Define at the model; repeat only for materially different forecast/application objects | Main model, forecasting, GloFAS and discussion |
| Fit/design/competitor fragments | Consolidate independent simulation design while retaining metrics/selection scope | Single-quantile design and evaluation |
| Internal campaigns and debugging chronology | Remove from reader prose; retain scientific Git documentation | Current study design/results and provenance records |
| Selection/initialization repetition | One main summary; one detailed supplementary diagram and compatibility explanation | `sec:supp_selection_initialization` |
| Application scores | One compact main comparison; complete supplementary evidence | GloFAS Part 4 / PriceFM results and supplementary sections |
| Generic future-work catalogue | Retain only supported statistical/application extensions | Discussion |
| Historical five-chain/replicated evidence | Preserve distinct scope without asserting current initialization stability | Supplementary historical sensitivities |

Compression is not obtained through smaller fonts, narrower margins, dropped
adverse evidence, or a change of estimator. Double-spaced reviewer page counts
are not comparable with the earlier 11-point working-paper count.

## Internal notation dictionary

| Object | Manuscript notation | Distinction |
|---|---|---|
| Response | `Y_t` random; `y_t` observed | State-conditional versus forecast-origin marginal target |
| Time/forecast | `t`, origin `T`, horizon `h` | Observations available at an origin versus simulated future lags |
| Reservoir | layer `d`, state `h_{t,d}`, depth `D` | Fixed weights/realization, recurrent nonlinear state |
| Lag/feature dimension | `m`, slope dimension `r` | Neither is the number of probability levels |
| Quantile grid | `p_1,...,p_K`; median position `k_med` | Fitted/evaluation ranges and different study-specific grids |
| Regression | intercept `beta_0` / level-specific intercept; slopes `beta` | Regression intercept is not the reservoir-input bias |
| exAL | likelihood scale `sigma`, shape `gamma`, shift `D_{p_0}(gamma)` | Scale is not a Gaussian residual variance or an RHS local scale |
| RHS | local `lambda_j`, global `tau`, slab `zeta`, reference `tau_0` | Code `tau` can instead denote probability; record the mapping |
| Joint slopes | stacked `beta_st`, first difference `H`, increments `Delta` | Executed zero-baseline anchor versus optional estimated baseline |
| Gaussian update | covariance `Sigma`, precision `K_beta` | Covariance across probability blocks is retained |
| Forecast evidence | coefficient location, response trajectory, posterior-mean grid, score draws | Averaging, marginalization, projection and scoring do not commute |
| Score | check loss, finite-grid aCRPS, PriceFM AQL | Factor two/trapezoidal weights versus equal-level averaging |

Conventional information-set and Normal-distribution symbols are retained.
One-use calligraphic collections and ambiguous scale/intercept names are not
introduced. Brief left-hand display labels orient the reader; derivation
details remain in the supplement.

## Historical RHS disposition

The correction commit is `0ed0e8827755b9a1e6985da577692efc8105e186`.
The applicable d-dimensional half-Cauchy/product global-variance update is
`(d+1)/2`, excluding unshrunk intercepts. Current source tests alone do not
authenticate earlier fits.

| Packet | Frozen execution/correction proof | Global-update/source scope | Current article inclusion | Disposition |
|---|---|---|---|---|
| Independent rolling v14 | Tracked v14 manifest pins package source `6dba6f2863705e0e90f0ce19e0c75d106d022a52`; frozen `R/static_beta_prior.R` uses `(m_active+1)/2` | Separate exdqlm implementation, not the defective shared-QVP update | Complete point/interval projection | Retained; provenance is the frozen package source, not a current shared-QVP unit test |
| Historical Phase181 | Shared-engine exposure is preserved in the original correction/register records | Earlier global update was exposed, including nominally independent comparators | Not current headline authority | Superseded for the active comparison by the complete pure-DESN packet; old fits remain historical exposed results |
| Old Jerez confirmation | Exact old fitted-source/global-update disposition is not established by this bounded editorial audit | Potential earlier exposure remains a historical source-review obligation | Not current headline authority | The active expanded comparison has a complete verified successor; unrelated old confirmations are not certified |
| Expanded pure-DESN JOINT | Fitted source `e39b061e69e176c35369fae9df0657e7b484e443`, correction ancestor verified; tracked frozen contract pins the fitted-evidence source/inventory | Corrected shared-QVP update active for applicable RHS blocks | Complete 32 MCMC + 32 VB packet | Current authority; preserve scalar-mixing and bounded-review qualifications |
| Earlier GloFAS Part 1/Part 4 | Exposure/potential exposure listed in the original deferred register | Old shared-update activity must not be inferred from the current code or a later continuation | No stale sweep-10 headline assets | Replaced for current article by complete Search III; do not certify every old fit |
| GloFAS Search III Parts 1--3 | Execution source `82ca91811fc2c4242068e097dd4c05f66834f99c`, correction ancestor verified | Corrected shared-QVP code for applicable quantile fits; separate correct Normal/partitioned RHS implementations | Complete Parts 1--3 evidence | Retained; Part 2 unscored and Part 1 crossings disclosed |
| Current Part 4 Joint AL | Canonical b02 continuation provenance pins source `e5a8c7f7f2ec711b27cc718e581d8a66faed2923` and the partitioned RHS module hash below | Separate partitioned RHS solver; global scale updates active after warmup | Canonical corrected Joint AL comparator | Terminal-specific proof, not merely the Parts 1--3 base execution commit |
| Current Part 4 Joint exAL | Canonical fullstate b02 continuation provenance pins source `e2d8d81acedd7566d2d56b59fccca6706f9763c3` and the partitioned RHS module hash below | Separate partitioned RHS solver; active scale updates and retained full exAL state | Canonical corrected Joint exAL sensitivity comparator | Terminal-specific proof; earlier outer-20 and incomplete-state checkpoints remain superseded |
| PriceFM R98 | Frozen 114-case registry; R97/R96 independent-exdqlm runtime lineage and existing source audit; bounded R94 proof below | Separate implementation; no single Git execution commit is asserted for all R98 fits | Full R98, no favorable R92 substitutions | Retained complete protocol-valid comparison; the bounded source inspection is not a new full campaign audit |
| Earlier PriceFM R69B--R92 / GloFAS FR09 | Original correction record identifies their separate correct implementations | Not exposed to this specific shared-QVP shape defect | R92 only as labelled historical sensitivity; FR09 no longer current authority | Preserve the original no-rerun-for-this-correction disposition without promoting obsolete authorities |
| Historical replicated VB (Phase153) | Corrected-current-target equivalence unresolved | Earlier feature design/inference; no blanket corrected-target certification | Explicitly historical only | Not evidence of current posterior-target validity |
| Phase182 | Exact source/update activity not audited by this editorial pass | Potential historical exposure remains unresolved | Not added | Unresolved independent scientific obligation |

The pure-DESN and Search III Parts 1--3 execution sources have identical
joint-QVP module SHA-256
`7b5af331dea616d89b632832dbe5a9c7f0b99b923f21ca224bb5221ab9bf0c6e`.
The helper at lines 12114--12120 implements `(block_size+1)/2`; MCMC, VB and
objective usages at lines 12134, 12194 and 12316 retain the half-Cauchy term.

Current Part 4 joint inference instead calls
`app_glofas_part3_rhs_solve_fixed_moments`. Both canonical terminal sources
descend from the correction commit and pin
`application/R/glofas_part3_partitioned_rhs.R`, SHA-256
`361ccbdd52e89fffb79fc6461cffe313bbbc117c4b73df251369ec7fc5b7e21b`;
its line 182 uses `(length(idx)+1)/2`. The Joint AL continuation-provenance
CSV has SHA-256
`a09dd1660843371313b805531e52782f84b1cf7d9d48a18efdfd7e8c57c877f5`;
the Joint exAL fullstate counterpart has SHA-256
`7321ce90f004bb3a007f386d83fc0bb0e4b25b4c8b4cc30ecb2563d2af085c3d`.
The latter's RHS schedule metadata records reference/discrepancy global-scale
updates, so these terminal scales are not described as fixed throughout.

The independent v14 frozen package's `R/static_beta_prior.R` has SHA-256
`6f89caf7b25513be16159f6f044ee7d5b268ce06daa4043131f007827e9c0d68`;
initialization, VB and MCMC use the correct product-augmentation global shape.
The inspected PriceFM R94 runtime source has the same static-prior bytes.
Its runtime manifest has SHA-256
`da6a938f959a2e3f9e8554c4920bad5867c85310a5e5ea6d38379a368744b2bb`
and is pinned by inspected R97 frozen pipeline metadata. That manifest lists
the patched source files, not a separate static-prior file hash. This bounded
evidence supports the separate-implementation description; it must not be
inflated into one newly authenticated execution commit for every PriceFM fit.

The original `joint_qvp_rhs_deferred_rerun_register_20260908.md` remains open,
preserved and unmodified. No rerun is launched to complete this editorial task.

## Reproduction and review materials

`scripts/build_qdesn_reproducibility_example.sh` assembles a small standalone
example. Its only scientific input is the pinned current JOINT summary CSV;
the supplied R renderer and common visual specification reproduce the score
table exactly and the forecast figure's extracted text and 150-dpi appearance.
PDF creation timestamps are not treated as scientific differences. The example
contains no private filesystem paths, fit objects, posterior draws or caches.
It demonstrates presentation reproduction, not reconstruction of the scores
or the full fitting campaign.

The self-contained summary-only representative reproduction passed its
isolated check. Its supplied summary input and presentation code are sufficient
for that example; the result does not claim to reproduce model fitting,
posterior simulation, source-score computation or the entire scientific study.

`scripts/build_technometrics_review.sh` builds both manuscripts in identified
and anonymous modes from common source. It also assembles a PDF-only anonymous
review archive. Raw manuscript sources and the ordinary Overleaf authority
bundle remain identified and are not mislabeled anonymous. Neutral scholarly
self-citations remain; author blocks, acknowledgments, author-owned repository
links and document-level author metadata are absent from review PDFs.

The anonymous PDF-only bundle passed validation. This is local packaging
validation, not journal acceptance of the upload categories or certification
of unidentified raw sources. A local ASA-compatible bibliography style,
`tables/qdesn_asa_compatible.bst`, has also passed its rendered-reference check;
it is an adaptation, not an official journal class or publisher-certified BST.
Separate vector GloFAS display derivatives are being added with original
scientific PDFs, numerical inputs and curves preserved. Their final-size
visual checks, derivative hashes and publication receipts remain separate
gates to be recorded after completion.

## Facts that still require confirmation

- Current journal-specific page limit, count exclusions and portal categories:
  the official Technometrics endpoint remains inaccessible. Publisher-hosted
  ASA guidance supplies the verified baseline, not guessed journal exceptions.
- Corresponding author/email, full affiliation address, funding, competing
  interests and accurate writing-assistance version disclosure: author facts
  must not be invented, including a default no-conflicts declaration.
- Confirmed identified title-page/declaration fields and submission-account/
  portal roles remain author/portal facts, not inferred from local packaging.
- GloFAS issued-product version, exact weather product/units/depth/spatial extraction/
  missingness and Part 4 historical retained count: not inferred from unrelated
  historical metadata or raw input rows. Part 1's 12,455 dates are authenticated
  by a recovery-manifest-pinned forecast-path CSV, SHA-256
  `f9b00bfca644e5cfee4237cce18f14a7bfd20290d6943b91e1b747cda1ca018e`.
  Parts 2 and 3 independently retain 12,455 dates; Part 3 has 24,910 stacked
  design rows. These certificates do not establish Part 4's historical N.
- The historical RHS/project closeout obligations remain distinct from current
  editorial completion. Do not treat them as all resolved by this source pass.

Primary preparation sources: [ASA guide](https://files.taylorandfrancis.com/asa-style-guide.pdf),
[ASA reference guidance](https://files.taylorandfrancis.com/tf_r.pdf),
[journal instructions](https://www.tandfonline.com/action/authorSubmission?show=instructions&journalCode=utch20),
and [publisher AI policy](https://taylorandfrancis.com/our-policies/ai-policy/).
Submission readiness remains unclaimed while the applicable facts/rules above
are unresolved. Final build/test/source/remote receipts are recorded after
the validated source is frozen, not predicted by this audit.

## Local validation before the final integration gate

- The manuscript checker passes all 19 immutable scientific-file checks;
  the complete independent surface has 216 roles and the current JOINT
  MCMC score/oracle surfaces each have 32 cells. The abstract has 173 words.
- The independent figure checker passes 132 checks for four active vector
  figures. The independent warning count remains five in its provenance;
  no internal dagger or favorable-cell replacement is introduced.
- The unchanged JOINT and GloFAS article-projection tests pass. The PriceFM
  R98 article-projection pytest passes, one test.
- Both identified manuscripts and both anonymous manuscripts compile with
  clean final LaTeX and BibTeX logs: 35/78 identified pages and 33/77 anonymous
  pages. The full journal-specific length rule remains unverified.
- All six GloFAS derivatives reproduce byte for byte in a fresh directory.
  Original vector geometry/styles and complete wording are preserved; no
  raster image or clipped label enters them. Minimum effective lettering is
  8.4284 bp at the narrower main insertion. Representative manuscript pages
  and all six figure previews were inspected.
- The representative package passes both at creation and after extraction
  to a fresh directory: the table is byte-equal and the figure's text and
  150-dpi rendering are equal. This does not recreate fitted scores.
- Shell syntax and whitespace checks pass. Source provenance is refreshed
  without changing the scientific inputs, original figure binaries, or tables.

Two preliminary registered-harness attempts did not constitute final passes:
one encountered the expected stale manuscript-hash manifest before refresh;
the other stopped at repeat-artifact hashes while the worktree was being
edited. The unchanged focused repeatability test subsequently passed. Its
provenance records live Git-status hashes, which can change during additions
or staging; the failed artifact pair was not retained, so that explanation is
not claimed as conclusively proved. The final combined-tree harness must run
on a frozen, clean worktree. No test gate or scientific code is weakened to
obtain a pass.

The direct/alias dependency inventory and the fit/score execution map are
separate from the compact reproduction example. They identify manuscript
consumers, estimators, retained inputs and access gaps. Final integration and
remote read-back receipts belong to the coordinator's subsequent publication
record; this pre-freeze document makes no prediction of those outcomes.
