# JOINT expanded pure-DESN article integration decision

Date: 2026-10-05. This record covers integration review and presentation of an already completed scientific campaign. Verification is summarized below. Remote publication is a separate guarded step and is not established by a successful fetch alone.

## Authority and scope

| Item | Frozen identity |
|---|---|
| Source branch | `work/joint-qdesn-pure-desn-expanded-score-closeout-20261004` |
| Source HEAD | `de83993e89fc085df8799a5f43ca71fd64dcb77b` |
| Pre-integration main and merge base | `757522db0f85815244370ec92a194de132268883` |
| Relationship | Main is an ancestor; 43 unique source commits; 104 source files |
| Integration branch | `integration/joint-pure-desn-expanded-20261005` |
| Integration worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__integrate_joint_pure_desn_expanded_20261005` |

Preserve all 43 source commits in the merge. The 104-file scientific surface is authenticated by the handoff's `changed_files.tsv`, `changed_file_hashes.csv`, and `unique_commits.tsv`; presentation derivatives are additional coordinator-owned changes. Integration occurs in the dedicated worktree, with command-line Git and the repository's guarded publishers.

The compact evidence directory is:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_expanded_score_closeout_20261004/local_trackers/joint_qdesn_pure_recursive_expanded_score_closeout_20261004/integration_handoff_20261005
```

Its transfer inventory verifies 54 files and 2,256,689 bytes. The frozen handoff SHA-256 is `16047c001451e6f14a5319e9e6942ed8829d861a237761fe8c413dc8ee695301`; the inventory SHA-256 is `e14362daf92ad2b8b750fef3519e21fc4a968e7fbb3edc010ddadfcf2603ad9e`. Check every listed file's size and digest locally before copying publication sources.

The Jerez closeout reports verification of 232 manifests and 4,808 payload records, including the 32 five-chain targets. Those authenticated audit receipts are retained in the compact packet. Verification of the compact Muscat copy is distinct from a new live inspection of Jerez's heavy evidence. No Jerez access, worker launch, rescore, refit, cleanup, deletion, or runtime relocation belongs to this integration.

## Scientific replacement decision

Adopt the complete 32-cell MCMC comparison from `final_packet/forecast_score_summary.csv`, filtered by `inference_method == "mcmc"`. Preserve all four model classes in all eight scenarios. The decision follows the complete declared forecast procedure and common-posterior safeguards; it does not select cells by whether their scores improve.

The published corrected-v4 comparison and this packet differ in the reservoir readout and forecasting construction. The new readout contains an intercept and the full retained states from all layers, with response lags entering through the reservoir rather than as separate regression columns. Unknown responses are generated recursively within each origin. The DGP expectation integrates future dynamics conditional on the observed history at that origin. Consequently, direct numerical changes relative to published v4 do not isolate an algorithmic improvement.

The closeout's three improved means and five worsened means compare the expanded packet with the previous narrow pure-DESN packet. This is a separate baseline: six scenario specifications and their scores are unchanged; two specifications changed, and all eight changed old/new intervals overlap. Preserve that comparison as provenance/sensitivity evidence, without presenting the three gains as gains over the former published article authority or combining favorable old and new rows.

## Forecast score and uncertainty interpretation

The evaluation uses seven levels `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`, weights `0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025`, and 33 origins with 30 horizons each. The weights sum to 0.90 and are not normalized. Primary reporting is DGP-integrated finite-grid check loss; realized aCRPS is secondary, and MAE/RMSE are recovery diagnostics.

At each origin, observed history reconstructs the reservoir. Future lags are simulated from the projected quantile grid using linear interpolation and endpoint clamping beyond the fitted probabilities. Each model averages its resulting future features over its own trajectories. Coefficient and intercept draws evaluated at this averaged feature matrix give the primary score distribution. The shared scenario reservoir therefore does not imply identical future feature rows across models.

The primary 95% intervals describe posterior readout uncertainty conditional on the estimated averaged recursive features. They omit recursive-feature uncertainty, repeated-realization uncertainty, and selection uncertainty. This forecast-location construction is not generally the exact quantile function of the full posterior predictive distribution. Draw-specific recursion is retained as a sensitivity analysis. Conditional intervals are narrower in 28/32 MCMC cells, with median width ratio 0.7364; that comparison does not establish improved calibration. VB intervals additionally omit intercept covariance and are partial summaries.

Each MCMC cell contains five chains. AL retains 750 draws per chain and exAL retains 1,500; scoring uses 750 draws from each chain, giving 3,750 score draws per cell. Every exAL worker uses exact `M0_v_collapsed_support_logit`. Prior centers and hyperparameters are fixed within each cell; initialization does not define its prior. The corrected RHS global shape remains `(d_beta + 1)/2` for the applicable coefficient block and hierarchy.

The executed joint prior anchors the first quantile slope directly and regularizes adjacent differences. It is the specialization with the general manuscript's latent baseline fixed at zero, not an additional estimated baseline hierarchy. Joint intercepts are ordered. Intercept centers and scales are calibrated once from the Gaussian reference fit and fixed across the comparison and its chains; this calibration is separate from subsequent warm-start transfers. The new exAL variational initializers use `VB1_structured_v`, with the structured factor `q(gamma)q(sigma|gamma)` evaluated by quadrature. Generic VB--LD derivations remain available, but are not presented as this campaign's executed approximation.

Independent-level draws are permuted within chains to form the declared product coupling. Serial ESS/MCSE of the resulting score sequences should not be interpreted as mixing diagnostics for the original parameter chains. Cross-model contrast intervals use deterministic index matching and remain descriptive; their dependence structure is not a uniquely defined joint posterior over different models.

## Findings and retained qualifications

Numerical posterior-mean winners are joint exAL for asymmetric tails, joint AL for Gaussian innovations, independent exAL for regime shifts, and independent AL for the other five mechanisms. All winner/runner-up marginal intervals overlap. Descriptive joint-minus-independent intervals favor joint fits in both families for asymmetric tails, independent fits in both families for Laplace, and include zero in the remaining twelve comparisons. A general joint predictive-superiority claim is unsupported.

| Model | Mean-grid raw crossings | Mean-grid rate | Average draw-grid rate |
|---|---:|---:|---:|
| Joint AL | 11 | 0.023148% | 1.427581% |
| Independent AL | 2,645 | 5.566077% | 12.049584% |
| Joint exAL | 0 | 0% | 0.351475% |
| Independent exAL | 288 | 0.606061% | 11.765080% |

The denominator is 47,520 adjacent-level comparisons per model for posterior-mean forecast grids and 178,200,000 for the 3,750 draw-specific grids in each of eight scenarios. Zero mean-grid crossings do not imply ordered raw grids for every posterior draw. Scored grids are ordered by isotonic projection. Adjustment magnitudes remain separate from crossing frequency.

The averaged recursive-design stability assessment has 63 strict passes and one review across 64 VB/MCMC cells; within MCMC it has 31 passes and one review. Laplace joint AL's split-score difference is 0.5194%, exceeding the original 0.5% threshold and falling below the versioned 0.525% review ceiling. Preserve the review, original strict-failure receipt, recovery-failure receipt, and closeout receipt. This is an integration-stability qualification rather than scalar posterior convergence. Imperfect scale/asymmetry mixing remains a scientific limitation; finite scores alone do not prove complete posterior mixing.

## Article presentation and protected evidence

Replace the old live JOINT forecast/fit figures, score and diagnostic tables, and corresponding prose together. The main forecast figure reports posterior means and 95% intervals at averaged recursive features. Preserve AL/exAL colors and joint/independent symbols. Do not restore the previously removed canonical-action plot markers. The supplement may label the retained point-action quantity as the "posterior-mean forecast score" and explain its distinction from the mean of draw-specific scores.

The fitting figure contains point RMSE diagnostics only; `fit_oracle_diagnostics.csv` does not supply posterior RMSE intervals. Retain the fit result in the supplement and forecast comparison in the main article. Supply compact tables for score intervals, descriptive contrasts, mean/draw crossing rates and adjustments, draw-specific recursive sensitivity, and partial VB summaries. The separate historical 50-replicate VB analysis must retain its different feature-design scope.

Protect existing independent-validation evidence, the authoritative GloFAS result, and the R98 PriceFM result, including their numerical assets and scientific claims. Broad manuscript-reference or projection-manifest hashes may require updates when JOINT text changes; these are documentation dependencies, not changes to the other scientific packets. Preserve Phase182 and all unrelated worktrees and active jobs.

Only compact publication CSVs, derivative TeX tables, vector figures/previews, provenance manifests, code/tests, and this integration record are publication candidates. Exclude `application/cache`, `local_trackers`, model RDS/RDA/RData objects, posterior draws, oracle banks, runtime logs, and queue receipts from Git and the article snapshot. Retain the original ignored evidence in place.

## Historical fixture dependency

The lane closeout accurately recorded `test_joint_qdesn_shared_backbone_article_confirmation.R` as blocked by its missing immutable September fixture. During coordinator integration, eight authentic archived CSVs were restored for that historical fixture and the focused test passed. This restores the dependency without inventing evidence or altering the current scientific results. The archived files must retain their original immutable contract hashes and remain ignored. Record the restoration verification and passing-test log with the final integration receipts. This focused restoration pass is distinct from the still-required combined repository suite.

## Reproduction and completion gates

Use pinned R 4.6.0 in the dedicated integration worktree. The builder projects the frozen evidence and does not run scientific fits or rescore models.

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript scripts/build_joint_qdesn_pure_desn_article_projection.R
# Rebuild article derivatives using only the public immutable source CSVs:
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript scripts/build_joint_qdesn_pure_desn_article_projection.R --published-sources
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript scripts/check_joint_qdesn_pure_desn_article_projection.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/test_joint_qdesn_pure_desn_article_projection.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/test_joint_qdesn_shared_backbone_article_confirmation.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
git diff --check
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
bibtex qdesn-supplement
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
pdflatex -interaction=nonstopmode -halt-on-error qdesn-supplement.tex
```

Also rerun the eleven current-campaign tests listed in the authenticated `test_results.csv`, parse the changed R files, and check shell syntax for changed launchers. Expected gates are: 32 MCMC score rows, 8 scenarios, 16 descriptive joint/independent contrasts, correct score weights, preserved review, copied-source hashes, publication derivative manifests, no runtime artifacts, and unchanged other-lane evidence.

Visually inspect the regenerated forest plots and tables at manuscript size. Verify metric labels, interval scope, fit-versus-forecast placement, and all main/supplement references. Build and validate the article-only snapshot after the main merge is published. Use `scripts/publish_integration_main_git_only.sh` and `scripts/publish_overleaf_article_snapshot.sh` under their documented contracts; read back both GitHub and direct Overleaf references and verify the final article tree.

## Coordinator verification

| Gate | Result |
|---|---|
| Frozen source and compact transfer | 43 commits, 104 source files, 54 compact files / 2,256,689 bytes; all specified hashes verified |
| Focused current-campaign tests | Eleven tests passed under pinned R 4.6.0 |
| Historical fixture dependency | Eight authentic CSVs restored under the detached archive; original hashes verified; historical confirmation test passed |
| Combined application R harness | Passed; one pre-existing optional discrepancy-adapter test reports unavailable engine and is explicitly skipped |
| Active JOINT projection checker | 164 checks passed; 15 immutable sources, 29 manifest-listed assets, 32 MCMC cells, retained review |
| Historical v4 preservation | All numerical/hash, 17 asset, and vector/visible-label checks preserved; current reader checker must separately pass |
| Failure propagation | Mocked nonzero subprocess with success-like output and zero subprocess without validation marker are both rejected |
| Independent article checker | 132 checks passed; all four existing vector figures and 216 roles preserved |
| Protected application assets | 416 PriceFM/GloFAS files unchanged against pre-integration main |
| Manuscript builds | Main: 22 pages; supplement: 51 pages; final logs free of unresolved references, overfull/underfull boxes, and LaTeX warnings |
| Visual inspection | Both vector plots and regenerated score/sensitivity tables inspected at manuscript size; annotation spacing and small-range tick precision corrected |
| Git-only publisher regression suites | Main publisher: 9/9; article-only publisher fixtures passed, including divergence, read-back, and partial-publication recovery cases |

The initial combined run reached the independent figure checker while manuscript hashes were still being updated. It stopped as intended on a stale dependency; after final manuscript-hash refresh the full harness passed. No independent scientific value or figure was regenerated. The original lane's bounded score review and historical failure receipts remain unchanged.

Both article-generation modes verify the same immutable scientific CSVs. Public-source reproduction does not require an ignored handoff directory. Compact hashes, readout-score means and limits, model rankings, and selection boundaries are never recalculated from local model objects.

The exact complete tracked integration surface is recoverable with `git diff --name-status 757522db0f85815244370ec92a194de132268883 <integration-merge>`. The intended merge has first parent `757522db0f85815244370ec92a194de132268883` and second parent `de83993e89fc085df8799a5f43ca71fd64dcb77b`. Remote hashes and publication outcome are reported by the guarded publishers and retained in the coordinator's ignored receipts; do not claim Overleaf synchronization until direct remote read-back succeeds.
