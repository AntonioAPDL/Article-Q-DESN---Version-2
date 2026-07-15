# Joint exQDESN Phase134 targeted exAL screening

Date: 2026-07-15

## Purpose

Phase134 is the next validation step after Phase133B. Phase133B showed that posterior qhat summary choice is not the main reason Joint exQDESN exAL-RHS underperforms: posterior mean, median, and trimmed-mean qhat summaries were nearly tied across the five high-priority scenarios.

Therefore Phase134 changes the search target. It treats the remaining gap as primarily a Joint exQDESN exAL-RHS specification-calibration problem, with sampler/optimization geometry added for the nonlinear reservoir-friendly scenario.

## Inputs

Phase134 consumes:

- Phase133B qhat summary sensitivity:
  `application/cache/joint_qdesn_phase133b_qhat_summary_sensitivity_20260714`;
- Phase121 case-specific VB/VB-LD winner freeze:
  `application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711`;
- long-series simulation fixtures:
  `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`.

All source manifests are verified before the candidate registry is written.

## Design

The Phase134 registry targets only:

```text
joint_exqdesn_rhs_vb
```

for the five Phase133B high-priority scenarios:

1. `regime_shift`;
2. `nonlinear_reservoir_friendly`;
3. `normal_bridge`;
4. `student_t_location_scale`;
5. `laplace_bridge`.

The candidate design emphasizes:

- wider exAL fan/readout priors, through larger `alpha_prior_sd`;
- looser RHS shrinkage options, through larger `tau0`;
- weaker finite beta caps where needed, through larger `zeta2`;
- gamma initialization variants: zero, quarter-default, half-default, and default;
- higher VB inner-loop and outer-iteration budgets for high-priority or sampler-geometry cases.

The nonlinear reservoir-friendly case is explicitly marked as `specification_plus_sampler_geometry`. Other cases are treated as specification/tail-compression calibration unless the diagnostics say otherwise.

## Implementation

New helper module:

```text
application/R/joint_exqdesn_phase134_targeted_screening.R
```

New preparation script:

```bash
Rscript application/scripts/140_prepare_joint_exqdesn_phase134_targeted_screening.R
```

Default readiness artifact:

```text
application/cache/joint_qdesn_phase134_exal_targeted_screening_readiness_20260715
```

Default screening artifact root:

```text
application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715
```

The preparation script writes:

- `phase134_run_config.csv`;
- `phase133b_source_manifest_verification.csv`;
- `phase121_source_manifest_verification.csv`;
- `phase133b_assessment.csv`;
- `phase133b_recommendations.csv`;
- `phase134_scenario_diagnosis.csv`;
- `phase134_candidate_design_by_case.csv`;
- `phase134_candidate_design_by_role.csv`;
- `phase134_targeted_exal_screening_registry.csv`;
- `phase134_launch_commands.csv`;
- `phase134_assessment.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Gates

Hard fail:

- missing or failing Phase133B hash manifest;
- missing or failing Phase121 hash manifest;
- malformed or empty candidate registry;
- invalid Phase106 screening registry schema.

Pass:

- source manifests verify;
- five target scenarios are present;
- every row targets `joint_exqdesn_rhs_vb`;
- launch command is reproducible and points to the frozen registry.

Review after screening:

- target scenarios still trail the current winners;
- raw crossings or monotone adjustments appear;
- VB max-iteration or objective diagnostics remain review-level;
- nonlinear reservoir-friendly remains sampler-sensitive.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_exqdesn_phase134_targeted_screening.R
```

Prepare readiness:

```bash
Rscript application/scripts/140_prepare_joint_exqdesn_phase134_targeted_screening.R
```

Launch targeted screening from the generated readiness artifact:

```bash
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry application/cache/joint_qdesn_phase134_exal_targeted_screening_readiness_20260715/phase134_targeted_exal_screening_registry.csv \
  --canonical-output-dir application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --workers 10 \
  --n-cores-per-worker 1 \
  --run-id phase134_exal_targeted_20260715 \
  --session-prefix joint_qdesn_phase134_exal
```

Canonical audit after all worker chunks finish:

```bash
Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
  --registry application/cache/joint_qdesn_phase134_exal_targeted_screening_readiness_20260715/phase134_targeted_exal_screening_registry.csv \
  --output-dir application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-cores 1 \
  --reuse-completed true \
  --audit-only true
```

## Interpretation

Phase134 is still a VB/VB-LD calibration stage. It should not directly change manuscript tables. If Phase134 finds improved Joint exQDESN exAL-RHS winners, the next step is to freeze the selected case-specific controls and run balanced VB-initialized MCMC confirmation before article promotion.
