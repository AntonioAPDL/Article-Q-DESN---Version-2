# Joint QDESN Phase 114 VB Article-Candidate Freeze

Date: 2026-07-08

## Purpose

Phase 113 completed the focused top-candidate verification after the broad Phase 112 VB screen. The selected candidate was:

```text
zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5
```

Phase 114 freezes this selected VB specification as the article-candidate initializer for the primary joint QDESN MCMC layer. The freeze is intentionally conservative: it marks the candidate as `review_ready_for_mcmc_initialization`, not as an unconditional final pass.

## Evidence From Phase 113

Phase 113 verified the two Phase 112 references and two finite-`zeta2`/inner-loop hybrids. The zero-gamma hybrid won the focused screen:

| candidate | rank | score | mean forecast MAE | max scenario MAE | raw crossings |
|---|---:|---:|---:|---:|---:|
| `zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5` | 1 | 0.2733 | 0.1180 | 0.2000 | 73 |
| `zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5` | 2 | 0.2956 | 0.1184 | 0.2012 | 90 |
| `inner10_iter1440_alpha0p5_tau0_0p5` | 3 | 0.2984 | 0.1208 | 0.2104 | 90 |
| `zeta2_16_alpha0p5_tau0_0p5` | 4 | 0.3323 | 0.1190 | 0.2012 | 111 |

The selected candidate improves over both Phase 112 references in screening score, mean forecast truth error, maximum scenario error, and raw crossing burden. The hard implementation gates are clean:

- top-level manifest rows verify;
- nested candidate manifest rows verify;
- scenario worker failures are absent;
- selected fit and forecast contract quantiles are noncrossing;
- selected scorecard metrics are finite.

The selected candidate remains review-level because raw pre-rearrangement crossings and some independent-comparator max-iteration flags remain diagnostic qualifications.

## Model Interpretation

The primary article row is:

```text
JOINT QDESN RHS
```

under the AL likelihood with the RHS prior. For the selected candidate this row has the strongest joint forecast recovery, no forecast max-iteration flag, and only two raw forecast crossing pairs before the monotone contract.

The exQDESN rows remain important comparison rows, but they should be interpreted carefully. Joint exQDESN is raw-noncrossing and numerically stable, but its tail fan remains compressed relative to QDESN, especially in the upper tail. exQDESN should therefore remain VB-only until a separate exAL MCMC layer is implemented and validated.

## Implemented Freeze Layer

New helper:

```r
app_joint_qdesn_run_phase114_vb_article_candidate_freeze()
```

New script:

```bash
Rscript application/scripts/113_freeze_joint_qdesn_phase114_vb_article_candidate.R
```

Default freeze output:

```text
application/cache/joint_qdesn_phase114_vb_article_candidate_freeze_20260708
```

The freeze writes:

- `phase114_run_config.csv`
- `freeze_decision_summary.csv`
- `freeze_gate_audit.csv`
- `selected_candidate_controls.csv`
- `selected_candidate_scorecard.csv`
- `selected_candidate_health.csv`
- `selected_vb_model_summary.csv`
- `selected_vb_scenario_summary.csv`
- `selected_vb_tau_summary.csv`
- `candidate_delta_summary.csv`
- `phase113_source_manifest_verification.csv`
- `phase113_candidate_manifest_verification.csv`
- `phase114_launch_plan.csv`
- `provenance.csv`
- `artifact_manifest.csv`
- `README.md`

## Commands

Freeze:

```bash
Rscript application/scripts/113_freeze_joint_qdesn_phase114_vb_article_candidate.R
```

The freeze writes the exact MCMC launch command to:

```text
application/cache/joint_qdesn_phase114_vb_article_candidate_freeze_20260708/phase114_launch_plan.csv
```

The article-candidate MCMC command uses:

- Phase 113 as the frozen VB source;
- the selected zero-gamma hybrid as `candidate_id`;
- two chains;
- 1200 iterations, 600 burn-in, thinning 10;
- all nine synthetic scenarios;
- the primary `JOINT QDESN RHS` AL model only.

After MCMC completes and passes audit, rebuild article assets from the frozen Phase 113 VB source and the Phase 114 MCMC output:

```bash
Rscript application/scripts/110_build_joint_qdesn_article_validation_assets.R \
  --phase107-dir application/cache/joint_qdesn_vb_spec_screening_phase113_20260708 \
  --phase109-dir application/cache/joint_qdesn_mcmc_article_phase114_20260708 \
  --output-dir application/cache/joint_qdesn_article_validation_assets_phase115_20260708
```

## Decision Rules

Proceed with MCMC if:

- `freeze_decision_summary.csv` has no `fail`;
- source manifests verify;
- worker failures are absent;
- contract crossings are zero;
- selected metrics are finite.

After MCMC:

- pass implementation gates before rebuilding manuscript assets;
- treat MCMC as fit-window posterior/reference evidence, not held-out forecast validation;
- keep exQDESN MCMC out of the article unless a separate exAL sampler is validated.

## Next Step

Run the Phase 114 freeze, launch the Phase 114 article-candidate MCMC in the background, then audit the MCMC output before regenerating final article tables and figures.
