# JOINT Forecast Score Width Audit

Read-only post-processing of the completed `joint_fixed_backbone_prior_20261005`
experiment. This package never fits models, changes a sampler, rewrites a
frozen selection, or publishes an article asset.

The execution source must remain at
`199ed8f0bb7a947c0a51800c466f9c458f25f238`. The audit code is separately
versioned so that the execution HEAD and its 515-file source freeze stay valid.
Merge the prior-screen scientific implementation before this audit package
when integrating; neither branch publishes article results.

## Contents

- `audit_and_plot.R`: exact per-quantile score reconstruction; covariance and
  chain-allocation identities; native/common readout projections; Laplace plots.
- `test_audit.R`: essential reconstruction, covariance and projection tests.
- `loss_sensitivity.R`: DGP expected-loss derivatives and native-posterior
  first-order sensitivity, including isotonic pool derivatives.
- `test_loss_sensitivity.R`: derivative check against the frozen scorer.
- `common_design_action.R`: unchanged-readout point-action comparisons on a
  common mean reservoir design; not a replacement forecast.
- `readout_component_audit.R`: two-by-two intercept/coefficient point-action
  swaps, exact symmetric gap allocation and first-lead state invariants.
- `summarize_audit.R`: manifest-verified comparison and attribution tables.
- `finalize_render.R`: historical recovery of headless plot export from
  completed CSVs without reconstructing posterior scores again.
- `run_audit.sh`: pinned-source test/reproduction entry point.

## Essential Test

On Muscat, with the retained frozen source and compact freeze receipts:

```bash
bash application/analysis/joint_qdesn_score_width_audit_20261006/run_audit.sh \
  --test \
  /data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_fixed_backbone_prior_20261005 \
  /data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_fixed_backbone_prior_20261005/local_trackers/joint_fixed_backbone_prior_closeout_20261006/evidence
```

The test mode checks the actual source freeze and does not require full model
objects or launch any worker. It also verifies the anchor/increment conditional
prior covariance directly against the frozen implementation.

## Full Reproduction

Requires the retained Jerez source worktree and its complete ignored runtime.
Run `run_audit.sh --reproduce EXECUTION_WORKTREE RUNTIME_ROOT NEW_OUTPUT_ROOT`.
The output root must be new and outside the protected runtime. All generated
results must remain ignored, for example under `local_trackers/` in the audit
worktree. Use the pinned R 4.6.0 environment and one numerical thread.

The runner verifies/stages only byte-identical audit scripts in the owned
execution worktree's ignored sidecar. Existing mismatched files cause a hard
failure; frozen runtime and application source are never overwritten. Its R
process runs with `-e` from the frozen worktree so the established bootstrap
resolves the correct immutable source, rather than the newer audit branch.

The initial audit's PNG export failed because X11 was absent. The scientific
CSV reconstruction was retained; `finalize_render.R` exported the figures with
cairo and sealed the outputs. Full reproduction sets cairo before rendering,
so no reconstruction retry is needed for that graphics issue.

## Interpretation and Evidence

Score intervals describe posterior uncertainty of the frozen DGP-integrated
finite-grid action score, not MCSE or predictive intervals for observations.
Joint dependence is never shuffled. Independent coupling exactly preserves
the predeclared within-chain product rule. Independent score temporal halves
after that permutation are descriptive only.

All 24 confirmation cells and 81,000 retained rows reproduced their frozen
scores within 6.67e-16. The core Laplace conclusion is not that every joint
quantile posterior is wider: forecast bias and cross-quantile loss dependence
largely explain wider score intervals. Common-design and coefficient/intercept
diagnostics localize the accuracy deficit mainly to the reservoir readout.
They do not prove that a particular prior change will improve the model.

The ignored Muscat packet, including the detailed scientific plan, six-page
PDF, PNG previews, CSVs and manifests, is retained at:

```
/data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_fixed_backbone_prior_20261005/local_trackers/joint_score_width_audit_20261006
```

Original runtime stays on Jerez. Runtime/model objects, figures and the
scientific next-launch plan are not tracked in this package. Integration of
this reproducibility code does not authorize article replacement or a new
production launch.

The six-page PDF is `results/laplace_forecast_and_uncertainty_audit.pdf`.
Its SHA-256 is:

```
4a8fa3029346f34eeceacc133fda4bf2a7bffc9d9890e649d392266e57d3e499
```

The retained output subdirectories each have a verified artifact manifest.
Laplace plots compare matched fresh confirmation realizations, not the article
fixture. The four baseline models are joint/independent Q-DESN under AL/exAL
with RHS priors. Selected joint challengers appear separately in the score
comparison; they are not automatically substituted for a baseline.

The wider-score-interval issue remains unresolved. Its next-launch rationale
and bounded checklist are in the ignored `AUDIT_AND_NEXT_STEPS.md`, not in an
active launch configuration. Changing the prior can change the model; matching
numerical tau0 values does not equate anchor/increment and independent priors.
Neither tighter intervals alone nor a reparameterization that preserves the
target is a justification for replacing article results.
