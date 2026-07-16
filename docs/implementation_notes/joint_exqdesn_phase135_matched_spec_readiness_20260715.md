# Joint exQDESN Phase135 matched AL-spec exAL readiness

Date: 2026-07-15

## Purpose

Phase135 addresses an important fairness question exposed after Phase134:

> Are the Joint/Independent exQDESN exAL rows weaker because exAL is intrinsically worse for
> these validation scenarios, or because the exAL rows have not been evaluated under the same
> RHS/readout controls used by the corresponding AL rows?

The existing balanced validation uses the same synthetic fixtures, train/forecast windows,
quantile grid, and design matrix within each scenario. However, it does not generally use the
same selected RHS/readout controls between AL and exAL counterparts. In particular, `tau0`,
`zeta2`, `alpha_prior_sd`, and VB iteration/inner-loop controls differ in many scenario/model
pairs because the prior stages optimized each model family separately.

Phase135 therefore prepares an exAL-only matched-spec diagnostic. It does **not** rerun AL rows.
Instead, it copies the AL controls into the corresponding exAL model rows:

- `joint_qdesn_rhs_vb` controls copied to `joint_exqdesn_rhs_vb`;
- `qdesn_rhs_independent_vb` controls copied to `exqdesn_rhs_independent_vb`.

This creates a direct diagnostic for the hypothesis that exAL should be at least competitive
when the only material change is the exAL working likelihood and its gamma parameter.

## Inputs

Default sources:

- Phase134 targeted Joint exQDESN screen:
  `application/cache/joint_qdesn_phase134_exal_targeted_screening_20260715`;
- Phase121 case-specific VB/VB-LD winner freeze:
  `application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711`;
- Phase124c balanced MCMC completion controls:
  `application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711`;
- Phase125 balanced MCMC audit:
  `application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712`;
- formal simulation fixtures:
  `application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`.

All source artifact manifests are verified before writing the Phase135 readiness artifact.

## Implementation

New helper module:

```text
application/R/joint_exqdesn_phase135_matched_spec_readiness.R
```

New preparation script:

```bash
Rscript application/scripts/141_prepare_joint_exqdesn_phase135_matched_spec_readiness.R
```

Default output:

```text
application/cache/joint_qdesn_phase135_matched_exal_readiness_20260715
```

Default matched-spec screening root:

```text
application/cache/joint_qdesn_phase135_matched_exal_screening_20260715
```

## Generated artifacts

The readiness artifact writes:

- `phase135_run_config.csv`;
- source manifest verification tables for Phases 121, 124c, 125, and 134;
- `phase134_per_scenario_winners.csv`;
- `phase135_matched_spec_parity_audit.csv`;
- `phase135_matched_exal_screening_registry.csv`;
- `phase135_launch_commands.csv`;
- `phase135_assessment.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`.

## Phase134 freeze interpretation

Phase134 completed cleanly: all 70 targeted Joint exQDESN candidates passed implementation gates,
with zero raw/contract crossings and no VB max-iteration flags. The performance gains were limited:

- `normal_bridge` improved materially enough to preserve as a VB candidate;
- `regime_shift` improved modestly and remains a review-level promotion candidate;
- `laplace_bridge` and `student_t_location_scale` retained the Phase121 reference;
- `nonlinear_reservoir_friendly` did not materially improve and remains a model-design or matched-spec diagnostic case.

These Phase134 rows are still VB calibration evidence. They do not update manuscript tables by
themselves.

## Matched-spec launch policy

The Phase135 matched-spec screen should run only exAL rows:

- 8 `joint_exqdesn_rhs_vb` rows copied from `joint_qdesn_rhs_vb` controls;
- 8 `exqdesn_rhs_independent_vb` rows copied from `qdesn_rhs_independent_vb` controls.

The AL rows are not relaunched. They already exist in the balanced validation artifacts and serve
as the matched reference.

## Commands

Focused test:

```bash
Rscript application/tests/test_joint_exqdesn_phase135_matched_spec_readiness.R
```

Prepare readiness:

```bash
Rscript application/scripts/141_prepare_joint_exqdesn_phase135_matched_spec_readiness.R
```

Launch matched exAL screen after the readiness manifest passes:

```bash
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry application/cache/joint_qdesn_phase135_matched_exal_readiness_20260715/phase135_matched_exal_screening_registry.csv \
  --canonical-output-dir application/cache/joint_qdesn_phase135_matched_exal_screening_20260715 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --workers 8 \
  --n-cores-per-worker 1 \
  --run-id phase135_matched_exal_20260715 \
  --session-prefix joint_qdesn_phase135_matched_exal
```

Canonical audit after the workers finish:

```bash
Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
  --registry application/cache/joint_qdesn_phase135_matched_exal_readiness_20260715/phase135_matched_exal_screening_registry.csv \
  --output-dir application/cache/joint_qdesn_phase135_matched_exal_screening_20260715 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --n-cores 1 \
  --reuse-completed true \
  --audit-only true
```

Completed result audit:

```bash
Rscript application/scripts/142_audit_joint_exqdesn_phase135_matched_spec_results.R
```

Default result-audit artifact:

```text
application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit
```

## Decision rule after the screen

If matched exAL performs similarly to AL, then the previous exAL weakness was primarily a
calibration/comparison-contract issue, and selected matched exAL rows should be promoted to
VB-initialized MCMC confirmation.

If matched exAL remains much worse than AL, then the next diagnosis should focus on the exAL gamma
geometry and likelihood/readout behavior under the same controls, not on broader DESN feature
changes.

Article tables should not be changed until matched-spec VB results are audited and any promoted
rows are confirmed by MCMC with manifests and zero contract crossings.

## Completed Phase135 outcome

The Phase135 matched-spec exAL screen completed and the canonical audit passed:

- 16 / 16 matched exAL rows completed;
- 8 Joint exQDESN rows and 8 Independent exQDESN rows;
- 13 rows passed and 3 rows were review-level due to VB max-iteration flags;
- 0 raw forecast crossings;
- 0 contract forecast crossings;
- all nested candidate manifests verified.

The formal result audit compares each matched exAL row against the exact AL row whose controls it
copied. Matching the AL DESN/RHS/tau0 controls did **not** rescue exAL at the VB layer:

- exAL had larger fit MAE than AL in all 16 matched comparisons;
- exAL had larger forecast MAE than AL in all 16 matched comparisons;
- mean Joint forecast MAE increased from 0.0962 under AL to 0.1476 under matched exAL;
- mean Independent forecast MAE increased from 0.0975 under AL to 0.1366 under matched exAL.

This result is implementation-clean but not article-promotable. It shows that the current exAL
gap is not explained only by unmatched DESN/RHS/tau0 controls. The working interpretation for the
next article-evidence attempt is that exAL needs a stronger MCMC approximation for the gamma layer.

## Promotion decision

Phase135 VB results should **not** update manuscript tables and should **not** be promoted directly
to article-facing MCMC evidence. The explicit artifact decision is:

```text
do_not_update_article_tables_from_phase135_vb
do_not_promote_phase135_exal_vb_rows_to_article_mcmc_until_gamma_mixing_mcmc_protocol_is_prepared
```

The next exAL MCMC stage, when launched, should keep the matched DESN/RHS/tau0 controls and focus
the MCMC approximation on gamma mixing. A reasonable launch policy is:

- initialize from the matched exAL VB rows;
- use several independent chains, for example eight chains per case;
- tune the gamma slice-sampling width/kernel before simply increasing chain length;
- assess posterior quality through quantile-grid performance, zero contract crossings, gamma/sigma
  trace behavior, and adequate posterior approximation rather than requiring perfect gamma mixing.
