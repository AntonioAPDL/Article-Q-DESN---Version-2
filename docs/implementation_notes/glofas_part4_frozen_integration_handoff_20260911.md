# GloFAS Part 4 Frozen Integration Handoff

Date: 2026-09-11

## Integration Status

`READY_FOR_INTEGRATION`

The Part 4 scientific campaign and its deterministic publication package are
complete. No fit, sweep, screen, or forecast job remains. This lane did not
modify `main.tex`, `qdesn-supplement.tex`, an Overleaf branch, or
`origin/main`. The Article Q-DESN integration lane owns the merge, manuscript
rewrite, authoritative aliases, compilation, and article-only Overleaf
publication.

The selected result is the Joint AL/RHS VB Sweep 10 state. It is a
**cap-stabilized finite-iteration estimate**, not a strictly outer-converged
optimum. All inner fits converged, the RHS gate passed, and all 14 RHS blocks
responded after release. The final maximum parameter change was
`0.00415386593413292`, above the strict `0.001` outer tolerance. This status
must not be weakened or relabeled during integration.

## Lane Identity

| Item | Value |
| --- | --- |
| Scientific lane | GloFAS Part 4 latent-path ensemble-likelihood family |
| Transcript | `/home/jaguir26/.codex/sessions/2026/05/15/rollout-2026-05-15T18-07-11-019e2dad-e30e-7962-a77b-d327dd103143.jsonl` |
| Worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part4_fivecore_20260906` |
| Branch | `work/glofas-part4-fivecore-launch-20260906` |
| Upstream | `origin/work/glofas-part4-fivecore-launch-20260906` |
| Scientific/package freeze commit | `fe0bb98f76075a4c50757676656357ced43ee106` |
| Main observed during closeout | `edf751e663977a13ba4e5eebc42219723efcae68` |
| Main relationship before this handoff-only commit | 37 behind, 16 ahead |

The final branch HEAD is the subsequent handoff-only commit containing this
document. The coordinator must verify it with `git rev-parse HEAD` and remote
readback before integrating.

## Frozen Scientific Contract

| Item | Frozen value |
| --- | --- |
| Cutoff/origin/train end | `2022-12-25` |
| Requested window | `2022-12-26` through `2023-01-24`, 30 days |
| Issued/evaluable window | `2022-12-26` through `2023-01-22`, 28 days |
| GloFAS ensemble | 51 members at each issued horizon, weight `1/51` per member |
| Response scale | `log(USGS + 1)` |
| Future USGS | latent in fitting; withheld truth is scoring-only |
| Future weather | realized PRISM/ERA5 PPT and soil, oracle diagnostic |
| CEFS/GEFS | not used |
| Crossing correction | none |
| Separate forecast adapter | none; the future USGS path is inferred jointly |
| Quantiles | `0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95` |
| Reference DESN | `D=1, n=3000, m=360, alpha=0.5, rho=0.9, washout=500, seed=20260512, tau0=1` |
| Discrepancy DESN | `D=1, n=2500, m=360, alpha=0.8, rho=0.7, washout=500, seed=20261521, tau0=0.001` |
| Direct readout inputs | none in either component |

## Runtime Completion

| Runtime | Status | Storage |
| --- | --- | ---: |
| `local_trackers/runtime_configs/glofas_part4_latent_family_dec25_exactopt_r3_fivecore_20260906` | 18/18 complete, 0 failed/running/pending | 24G, ignored |
| `local_trackers/runtime_configs/glofas_part4_joint_convergence_closeout_20260907` | Joint AL Sweep 10 complete; optional Joint exAL continuation operator-stopped | 3.7G, ignored |

There are no active Part 4 processes or tmux sessions. Runtime objects,
posterior draws, design caches, logs, and status markers must remain excluded
from Git and Overleaf.

Key runtime evidence:

| Evidence | SHA256 |
| --- | --- |
| Original 18-job model manifest | `0a30942b923b45daba4d1544817f07a5070d5fc80837b5b86488827313084926` |
| Fixed-window audit | `29c5dd50bffd2535520249285f0d97ddbdd3963ae1dcc97bb6f71bb2144bd903` |
| Sweep 10 artifact manifest | `f65505803792819fcc6db7bda43594b7aff98834ab2d74354accbd5ead94c602` |
| Sweep 10 fit object | `493333b481e0897d5f0bc636aa8dce37f4d7326cb6a65d5175c30143a668bfec` |
| Sweep 10 predictions | `ee2ca497bb049da5c13cf2dcae3b9e333fcffe38abaa0155bacc30e09b18a1db` |
| Sweep 10 score summary | `4cbb5d2de3cff15a6d3a0e38960360d01062feef38857caa15fe5f738e28f74c` |
| Sweep 10 coefficients | `65b1e21037875cd4078c9849f5b8476aab10f9cd031b84c2b18997794b01d` |

## Scientific Decision

The selected Part 4 issued-window quantile model is Joint AL/RHS VB.

| Model | 7-q CRPS, log1p | 90% coverage | Status |
| --- | ---: | ---: | --- |
| Normal Ridge | `0.806241997` | `0.2500` | Lower score but severe undercoverage; Normal diagnostic only |
| Joint AL Sweep 10 | `0.837404277` | `0.9286` | Selected cap-stabilized quantile estimate |
| Independent AL | `0.860593184` | `0.9286` | Converged quantile comparator |
| Normal RHS/VB | `0.941192302` | `0.1786` | Normal diagnostic only |
| Joint exAL | `1.006301008` | `0.7857` | Nonconverged sensitivity |
| Independent exAL | `1.047788456` | `0.7500` | Converged comparator |
| Raw GloFAS | `1.435977103` | `0.0000` | Raw ensemble baseline |

Joint AL improves transformed-scale CRPS by `41.6840%` versus raw GloFAS and
by `2.6945%` versus Independent AL. Sweep 5 to Sweep 10 improved CRPS from
`0.8417650845` to `0.8374042767`, a `0.5181%` reduction. The mean absolute
path change was `0.1004755`; therefore the continuation was consequential and
must not be described as identical to Sweep 5.

The historical guardrail is negative. On the common six-quantile grid, Part 4
Joint AL is worse than FR09 by `68.6%` over all history, `104.2%` over the last
1000 dates, `51.4%` over the last 200, and `8.6%` over the last 50. FR09 must
remain the stronger historical-fit benchmark. Part 4 authority is limited to
the single-origin issued-window latent-path experiment.

## Publication Package

Publication tag:

`glofas_part4_joint_al_sweep10_20260911`

The controlling publication manifest is:

`tables/glofas_application_part4_publication_manifest__glofas_part4_joint_al_sweep10_20260911.csv`

It contains 18 payload rows. All hashes pass. Sixteen rows are article assets
eligible for Overleaf publication and two are Git-only reproduction code:

- `application/R/glofas_part4_publication_contract.R`
- `application/scripts/391_plot_glofas_part4_grouped_family_comparison.R`

Article-safe outputs include the seven-family score table, historical
guardrails, common-grid tradeoff, strict convergence record, RHS release
certificate, Sweep 5-to-10 stability table, model specification, selection
decision, TeX tables/macros, the Joint AL article figure, the three-page
grouped comparison, and the convergence-trace figure. The PDFs were inspected
page by page and contain no blank, clipped, overlapping, or wrong-scale panels.

## Exact Lane File Surface

Integrate the following 47 scientific/package paths plus this handoff document:

```text
application/R/engine_contract.R
application/R/fit_qdesn_discrepancy.R
application/R/fit_qdesn_latent_path.R
application/R/glofas_part4_ensemble_likelihood_contract.R
application/R/glofas_part4_latent_family.R
application/R/glofas_part4_publication_contract.R
application/R/joint_exqdesn_exact_structured_inference.R
application/R/latent_path_runtime_backend.R
application/R/latent_path_vb_al.R
application/R/latent_path_vb_exal.R
application/R/latent_path_vb_joint.R
application/R/latent_path_vb_normal.R
application/scripts/03_fit_models.R
application/scripts/386_run_glofas_part4_latent_family_job.R
application/scripts/387_launch_glofas_part4_latent_family_dag.py
application/scripts/388_check_glofas_part4_latent_family_dag.py
application/scripts/389_continue_glofas_part4_joint_fit.R
application/scripts/390_build_glofas_part4_authoritative_package.R
application/scripts/391_plot_glofas_part4_grouped_family_comparison.R
application/scripts/392_check_glofas_part4_authoritative_package.R
application/scripts/61_prepare_glofas_part4_ensemble_likelihood_launch.R
application/tests/README.md
application/tests/run_tests.R
application/tests/test_glofas_part4_ensemble_likelihood_contract.R
application/tests/test_glofas_part4_latent_family.R
application/tests/test_glofas_part4_latent_family_scheduler.py
application/tests/test_glofas_part4_publication_contract.R
application/tests/test_latent_path_design.R
docs/implementation_notes/glofas_part4_article_update_blueprint_20260907.md
docs/implementation_notes/glofas_part4_latent_family_implementation_20260906.md
figures/glofas_application/diagnostics/glofas_part4_grouped_family_comparison__glofas_part4_joint_al_sweep10_20260911.pdf
figures/glofas_application/diagnostics/glofas_part4_joint_al_convergence_trace__glofas_part4_joint_al_sweep10_20260911.pdf
figures/glofas_application/glofas_part4_joint_al_last30_issued28__glofas_part4_joint_al_sweep10_20260911.pdf
tables/glofas_application_part4_all_family_scores__glofas_part4_joint_al_sweep10_20260911.tex
tables/glofas_application_part4_common_grid_tradeoff__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_current_outputs__glofas_part4_joint_al_sweep10_20260911.tex
tables/glofas_application_part4_forecast_scores__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_forecast_scores__glofas_part4_joint_al_sweep10_20260911.tex
tables/glofas_application_part4_grouped_family_scores__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_historical_guardrail__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_historical_guardrail__glofas_part4_joint_al_sweep10_20260911.tex
tables/glofas_application_part4_joint_convergence__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_joint_sweep_stability__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_model_spec__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_publication_manifest__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_rhs_release_certificate__glofas_part4_joint_al_sweep10_20260911.csv
tables/glofas_application_part4_selection_decision__glofas_part4_joint_al_sweep10_20260911.csv
```

## Ordered Integration Route

The worktree has criss-crossed, stale base history. Do **not** merge its branch
wholesale and do not apply the merge commit `193b1cb98a9091605bc0203aed19b12b01e6e0f9`.
Create a fresh integration branch from fetched `origin/main`, then cherry-pick
these non-merge commits in order:

```text
9c02caa1552cb3283f4d22ae86cff5e7ee3856ff
9d1c9e9cde2e4eea01eeddf3a78cf3e88a0a7247
428c3c31faa35f1a72d7eb789b669b7aa6d95c11
c24a8140c16bbcb5af9fb2aa3d71e24f76044398
7d52cf80d417a679f146689dbcb34578dea69496
527a091072bfbb2e62d557403054957c6eb3660a
26636758af3476f8fa84f6e7203a5e67297645fd
00b5fcd90175964ac75e979532134d9f45cbe194
5d1c50b6caa44470adc1573f06dd3a300a8eb381
0d1fa74f6ed4d5a64045ae110200ea27a117b2b6
18fb1e5a4884d8df80cbb8db38b1a61dc0ef8016
dafed57d5a108828782ec317edcae43ec4582afa
4db1e58862f9b0ac7b97c353db91b1c80cb23e39
826958ab869ca5f839bb4d171694694ea0e8ac4f
fe0bb98f76075a4c50757676656357ced43ee106
```

Cherry-pick the handoff-only commit last if the coordinator wants this record
on main. Resolve shared inference and test-registry conflicts deliberately in
favor of current main plus the Part 4 observation-weight, continuation, and
publication-contract additions. Never accept tree-level deletions implied by
the stale branch comparison.

## Verification Completed

| Command/check | Result |
| --- | --- |
| Parse five new/modified closeout R files | 5/5 passed |
| `test_glofas_part4_publication_contract.R` | passed |
| `test_glofas_part4_ensemble_likelihood_contract.R` | passed |
| `test_glofas_part4_latent_family.R` | passed |
| `test_glofas_part4_latent_family_scheduler.py` | 4/4 passed |
| `388_check_glofas_part4_latent_family_dag.py` | 18/18 complete, 0 failed |
| `392_check_glofas_part4_authoritative_package.R` | 13/13 publication gates passed |
| Runtime artifact-manifest verification | all original and continuation hashes passed |
| PDF page inspection | 5/5 pages passed |
| `git diff --check` | passed |

The legacy combined `application/tests/run_tests.R` harness currently stops
before the Part 4 block in
`test_joint_qvp_qdesn_synthetic_artifacts.R` with an existing
`rbind` column-count mismatch. That test depends on prior harness setup and
does not run standalone. The coordinator must rerun the merged current-main
harness and distinguish this known shared-suite issue from Part 4 failures.

## Required Integration Work

1. Fetch with command-line Git and create an integration branch from current
   `origin/main`.
2. Apply the ordered Part 4 commits without the stale merge commit.
3. Verify the 48-path authorized surface and reject unrelated deletions,
   runtime payloads, or generated caches.
4. Run the focused tests and publication checker above, then the current-main
   combined R/Python harness.
5. Atomically update the GloFAS current aliases from the reviewed versioned
   Part 4 assets.
6. Rewrite the GloFAS sections in `main.tex` and `qdesn-supplement.tex` using
   the article-update blueprint. Preserve the finite-cap convergence
   disclosure and historical FR09 guardrail.
7. Compile and visually inspect both manuscripts.
8. Push authoritative `origin/main` only from the integration lane.
9. Publish only rows with `overleaf_publish=TRUE` plus the reviewed manuscript
   edits to the article-only Overleaf snapshot.

## Residual Risks And Claims Discipline

- Joint AL did not meet strict outer tolerance; do not call it converged.
- The result is one retrospective origin with oracle future weather; do not
  claim operational validation or broad generalization.
- Only 28 issued GloFAS days are evaluated; do not report 30 scored days.
- Part 4 historical fit is materially worse than FR09; do not claim universal
  superiority.
- Normal Ridge has lower transformed-scale CRPS but unusable 90% coverage for
  the quantile objective; explain why it remains a diagnostic baseline.
- Joint exAL is nonconverged and non-authoritative.
- No crossing correction, synthesis, MCMC application fit, CEFS, or GEFS was
  used.
- Runtime artifacts must remain in `local_trackers/` and outside Git/Overleaf.

With those disclosures and integration controls preserved, the lane is
`READY_FOR_INTEGRATION`.
