# GloFAS Search III Part 1-4 Final Closeout Handoff

Date: 2026-10-07

## Integration Gate

`READY_FOR_COORDINATOR_INTEGRATION`

All authorized GloFAS Search III fitting, dependency rebuilding, Part 4
correction and closeout computation is complete. No GloFAS fit, continuation,
screen or controller remains active.

## Source Authority

- Branch: `work/glofas-search3-adjacent-tau-recovery-20260930`
- Closeout implementation commit: `fe2ca22c564bf240f5e566e920edd6c2a824fce1`
- Builder: `application/scripts/445_build_glofas_search3_final_closeout.R`
- Independent checker: `application/scripts/446_check_glofas_search3_final_closeout.R`
- Shared validation functions: `application/R/glofas_search3_final_closeout.R`
- Focused regression test: `application/tests/test_glofas_search3_final_closeout.R`

The closeout runtime is intentionally ignored and must remain outside tracked
article source:

`local_trackers/runtime_configs/glofas_search3_part1234_final_closeout_20261007`

## Reproduced Health

| Component | Complete | Failed | Active | Left |
|---|---:|---:|---:|---:|
| Search III Part 1-4 dependency DAG | 133/133 | 0 | 0 | 0 |
| Part 4 source family | 18/18 | 0 | 0 | 0 |
| Corrected Joint AL batches | 2/2 | 0 | 0 | 0 |
| Corrected Joint exAL batches | 2/2 | 0 | 0 | 0 |
| Fixed-state exAL quadrature certificate | 1/1 | 0 | 0 | 0 |
| Future-truth firewall | 1/1 | 0 | 0 | 0 |

The checker reproduced all 11 release gates, including source artifact hashes,
selection identity, strict joint convergence, family scores, calibration,
authority and supersession ledgers, and the vector-only six-page PDF.

## Frozen Search III Selection

| Component | Candidate | Decision | Key geometry |
|---|---|---|---|
| Reference | `search3_ref_001` | Retain Search II incumbent | `D=1`, `n=1500`, `m=540`, `mx=90`, `alpha=0.75`, `rho=0.60`, `m0=40` |
| Discrepancy | `search3_dis_007` | Adopt Search III rainy-season challenger | `D=1`, `n=1000`, `m=180`, `mx=180`, `alpha=0.85`, `rho=0.20`, `m0=60`, fixed `zeta2=16` |

This selection used internal training evidence. The final issued window was not
used to select or retune either reservoir.

## Corrected Joint Authorities

| Family | Stored outer iteration | Parameter change | Maximum RHS change | Consecutive passes | Fit SHA256 |
|---|---:|---:|---:|---:|---|
| Joint AL | 11 | `8.92797e-04` | `7.77484e-04` | 3 | `0ac25ad186fa660d7958484db822c0e2c7ce60ae933928498dfd42180e439274` |
| Joint exAL | 28 | `2.60806e-04` | `3.82535e-04` | 3 | `0784549437365dc239e123fe0fd660d4212fa0e7a72dc1034765b5ba73e6e823` |

Both satisfy the outer, inner, RHS and three-consecutive-full-state convergence
contract. The exAL correction retained complete local state and removed a
diagnostic-only discontinuous indicator from the operative quadrature stopping
norm. It did not change the likelihood, prior, ELBO or posterior target.

## Part 4 Descriptive Comparison

All values below use the same seven quantiles and 28 issued horizons on the
`log(1 + flow)` scale.

| Rank | Family | Grid CRPS | 90% coverage | Role |
|---:|---|---:|---:|---|
| 1 | Independent AL | `0.715603` | `0.750` | Descriptive issued-window leader |
| 2 | Independent exAL | `0.826575` | `0.536` | Quantile comparator |
| 3 | Normal Ridge | `0.847142` | `0.107` | Normal baseline |
| 4 | Joint AL | `0.949048` | `0.786` | Corrected joint comparator |
| 5 | Joint exAL | `1.176549` | `0.286` | Corrected sensitivity model |
| 6 | Raw GloFAS | `1.435977` | `0.000` | Raw ensemble baseline |
| 7 | Normal RHS/VB | `1.478985` | `0.107` | Normal baseline |

These are protected-window evaluation results. Describe Independent AL as the
descriptive leader, not as a model selected on the final window. Joint exAL is
numerically certified but remains scientifically weak in the upper tail.

## Residual Scientific Limitations

- Part 1 Independent AL has three adjacent-quantile crossing pairs and Part 1
  Independent exAL has one across the 30-day output grid. Part 1 Joint AL,
  Part 1 Joint exAL and every Part 3 family have zero. Preserve these raw
  results; do not apply an unregistered crossing correction during promotion.
- Part 2 post-cutoff discrepancy paths cannot be scored because retrospective
  GloFAS ends at the cutoff. They remain forecast products, not validation
  evidence.
- Part 4 has material upper-tail undercoverage, most severely for corrected
  Joint exAL (`q0.95` empirical coverage `0.286`). Numerical convergence does
  not imply competitive predictive calibration.
- Parts 1 and 3 use 30-day recursive paths; Part 4 is restricted to the 28
  issued GloFAS ensemble horizons. These scopes must not be conflated.

## Integration Inputs

Use these runtime files as the numerical and graphical source of truth:

- `tables/part123_family_scores.csv`
- `tables/part4_family_scores.csv`
- `tables/part4_quantile_calibration.csv`
- `tables/final_joint_convergence.csv`
- `manifests/authority_ledger.csv`
- `manifests/supersession_ledger.csv`
- `figures/glofas_search3_part1234_final_comparison.pdf`
- `reports/final_closeout_report.md`
- `reports/coordinator_integration_handoff.md`

Key hashes:

| Artifact | SHA256 |
|---|---|
| Output manifest | `968096fe310b61c4b05423890cad529e7c891e51691cd997ef253753c7c9de9f` |
| Comparison PDF | `799d05536f7331d80ff534f4198e5977c08344d97d8f83167c52b8534e82ae31` |
| Closeout report | `b5f8a82c1fe02a74d2dfc8c3b654361c67bc9a1c01bff32f11d4245aeea33eef` |
| Runtime coordinator handoff | `a02a663098c41004573992a9d91fd129b134044d978041f580fdbd5b21be416f` |

## Required Coordinator Procedure

1. Check out the source branch and verify the closeout implementation commit.
2. Run `Rscript application/scripts/446_check_glofas_search3_final_closeout.R`.
3. Require both terminal lines: `GLOFAS_SEARCH3_FINAL_CLOSEOUT_VERIFY_PASS 11/11`
   and `READY_FOR_COORDINATOR_INTEGRATION`.
4. Integrate reviewed tables and the comparison PDF; do not publish RDS files,
   logs or machine-local paths.
5. Preserve the distinction between recursive Parts 1-3 forecasts and the
   Part 4 latent-path issued-ensemble experiment.
6. State that Part 2 post-cutoff discrepancy paths are unscored because
   retrospective GloFAS ends at the cutoff.
7. Keep future USGS truth scoring-only and the Part 4 issued horizon at 28 days.
8. Do not retune from the final window or relabel corrected Joint exAL as the
   best-performing family.
9. Verify the integrated asset manifest before retiring any superseded runtime.

Two small package attempts with suffixes `quarantine_json_precision` and
`quarantine_visual_qa` are rejected closeout builds. They contain no unique
scientific fit and must not be integrated.
