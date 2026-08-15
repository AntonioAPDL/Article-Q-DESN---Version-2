# Joint exQDESN Phase142 Post-Geometry Synthesis

Phase142 follows the Phase140/Phase141 gamma diagnostics for the joint exQDESN
validation study.

Phase140 showed that fixing the exAL shape parameter at the AL-like value
substantially recovered fit and forecast performance. Phase141 then tested
sampled-gamma geometry changes: bounded and logit slice updates with several
widths. Those runs completed without worker failures and removed raw and
contract crossings, but the best sampled-gamma variants still did not beat the
fixed-gamma-zero reference on the common high-priority cases.

## Implemented Scope

This stage adds:

- `application/R/joint_exqdesn_phase142_post_geometry_synthesis.R`;
- `application/scripts/151_prepare_joint_exqdesn_phase142_post_geometry_synthesis.R`;
- `application/tests/test_joint_exqdesn_phase142_post_geometry_synthesis.R`;
- optional logit-normal gamma shrinkage controls in
  `app_joint_qvp_fit_exal_mcmc_tiny()`;
- Phase136 packet registry support for `logit_prior_sd_*` variants.

Default MCMC behavior is unchanged. The new gamma prior is only active when a
variant explicitly requests `gamma_prior_type = "logit_normal"`.

## Phase142A Synthesis Artifact

Generated artifact:

`application/cache/joint_qdesn_phase142_post_geometry_synthesis_20260722`

Key outputs:

- `phase140_141_packet_summary.csv`;
- `gamma_geometry_decision_table.csv`;
- `phase142_decision_summary.csv`;
- `phase142_regularized_gamma_registry.csv`;
- `phase142_regularized_gamma_launch_plan.csv`;
- `phase142_regularized_gamma_launch_command.txt`;
- `artifact_manifest.csv`.

The synthesis decision is:

`reject_geometry_only_for_article_promotion`

The next-stage decision is:

`prepare_regularized_gamma_screen`

## Overnight Phase142B Launch

The Phase142B launch tests whether sampled gamma can be made useful through
explicit shrinkage around the AL-like gamma-zero reference rather than through
slice geometry alone.

Launched packet:

`application/cache/joint_qdesn_phase142_regularized_gamma_screen_20260722`

tmux session:

`joint_qdesn_phase142_regularized_gamma_screen_20260722`

Variants:

- `logit_prior_sd_0p25`;
- `logit_prior_sd_0p5`;
- `logit_prior_sd_1p0`.

Cases:

- nonlinear reservoir, independent exQDESN;
- nonlinear reservoir, joint exQDESN;
- regime shift, joint exQDESN;
- Student-t location-scale, joint exQDESN.

This is a 96-chain packet:

`4 cases x 3 variants x 8 chains`

The packet uses `save_rdata = false`; no raw model objects are retained.

## Interpretation Rules

The regularized-gamma packet should be promoted only if at least one shrinkage
variant materially closes the gap to fixed-gamma-zero while preserving the
quantile-grid contract:

- no worker or preparation failures;
- source manifests verify;
- finite fit and forecast scores;
- zero contract crossings;
- forecast MAE or forecast check loss competitive with fixed-gamma-zero;
- gamma diagnostics no worse than review-level.

If no regularized sampled-gamma variant matches fixed-gamma-zero, sampled gamma
should remain a diagnostic layer rather than an article-facing exAL result.

