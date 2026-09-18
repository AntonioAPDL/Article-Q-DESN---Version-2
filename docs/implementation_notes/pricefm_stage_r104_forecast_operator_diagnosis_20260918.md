# PriceFM Stage-R104 forecast-operator diagnosis

## Purpose

Stage R104 is a bounded, validation-only diagnosis of the recursive forecast
operator used by Stage R103. It reuses fitted AL/exAL readouts and frozen Normal
driver artifacts. It does not refit models, inspect test outcomes, launch a
campaign, mutate the PriceFM registry, or modify article assets.

R103 was paused with 27/114 complete region-fold cases and 401/1,596 completed
atoms. All 401 atom terminals pass the stored formal-convergence and numerical
gates. The pause preserves completed and partial artifacts so no fitting work
is discarded.

## Diagnosed estimand error

The original R103 operator paired 500 recursive Normal-driver paths with 500
coefficient draws, evaluated each conditional quantile path, and averaged those
paths at each horizon. For quantile level `tau`, this estimates

```text
E[Q_tau(Y | future path, parameters)],
```

which is not generally the marginal predictive quantile

```text
Q_tau(Y).
```

Increasing the number of paths would estimate the former quantity more
precisely; it would not correct the target. This explains why the original
R103 intervals were unusually tight even though the VB fits converged.

## Bounded no-refit comparison

The audit is limited to BG and BE, all three folds, and 500 paths. BG uses the
`target_only` information policy and isolates target self-recursion. BE uses
`graph_summary_mean` and separates target recursion from the choice of Normal
neighbor driver. The likelihood family is chosen once from Fold-1 validation
and then held fixed across all folds: AL for BG and exAL for BE.

The corrected diagnostic keeps path identity. At each horizon it samples one
target price from the fitted seven-quantile curve, inserts that sampled target
price into the next endogenous lag, and finally computes empirical marginal
quantiles over recursive paths. Quantile curves are monotonically rearranged
before interpolation. Because only quantiles 0.10 through 0.90 are fitted, the
diagnostic uses bounded endpoint behavior outside that interval. That tail rule
is explicit and is not yet a production contract.

For BE, the fixed-policy aggregate validation results are:

| Forecast operator | AQL | 10--90 coverage | Mean 10--90 width |
|---|---:|---:|---:|
| Original Normal-RHS driver + mean conditional quantile | 13.3905 | 0.1609 | 10.45 |
| Ridge driver + mean conditional quantile | 13.0314 | 0.1658 | 11.03 |
| Quantile self-recursion + Normal-RHS neighbors | 10.2952 | 0.6142 | 54.55 |
| Quantile self-recursion + Ridge neighbors | 9.5325 | 0.6312 | 51.99 |

For BG, quantile self-recursion lowers aggregate validation AQL from 32.7160 to
29.7450 and raises 10--90 coverage from 0.3098 to 0.3880. It improves every
fold, although Fold 3 remains weak. The BE result shows that correcting target
self-recursion is the dominant improvement; changing only the Normal neighbor
driver is secondary.

These results confirm a forecast-operator defect but not a complete remedy.
The corrected diagnostic remains worse than the older direct-fit validation
benchmarks, and its bounded tail interpolation requires sensitivity checks.
No operator is selected separately by fold.

## Raw total ELBO audit

The initial convergence PDF displayed distance from the terminal ELBO, which
is not by itself sufficient evidence of convergence. A separate read-only
packet therefore plots the raw total ELBO for every BG/BE fold, family, and
quantile on both the complete iteration range and the final 30 iterations.

The complete traces show a large upward transition immediately after the
50-iteration RHS global-scale freeze. Inspection of the executed `exdqlm`
runtime confirms that AL and exAL evaluate the same full ELBO on both sides of
that transition; the change is the release and update of the frozen variational
block, not a replacement of the objective. All 84 focus atoms run for at least
97 iterations, so none terminates during the frozen phase.

Across those 84 raw traces:

- none has a raw ELBO decrease larger than `1e-10`;
- none terminates below an earlier ELBO maximum;
- the largest last-10-iteration increase is `5.76e-5`;
- the largest last-25-iteration increase is `0.2268`, from BG Fold 3 AL at
  quantile 0.50, whose final increment is `4.64e-7`;
- every terminal increment is below the runtime ELBO tolerance of `1e-5` and
  the runtime requires three consecutive jointly stable iterations.

The raw terminal-window plots visibly flatten. This supports numerical
convergence to a stationary variational solution for the inspected atoms, but
does not establish a global optimum and does not repair the independently
identified forecast-operator estimand error.

## Implementation and evidence

- `application/scripts/pricefm/pricefm_recursive_quantile_marginal.py`
- `application/scripts/pricefm/350_audit_pricefm_stage_r104_forecast_operator.py`
- `application/scripts/pricefm/351_plot_pricefm_stage_r104_raw_elbo.py`
- `application/tests/test_pricefm_recursive_quantile_marginal.py`
- `application/tests/test_pricefm_stage_r104_forecast_operator_diagnosis.py`
- `application/tests/test_pricefm_stage_r104_raw_elbo.py`
- Runtime packet:
  `application/data_local/pricefm/authoritative/pricefm_stage_r104_forecast_operator_diagnosis_20260918`
- Raw-ELBO packet:
  `application/data_local/pricefm/authoritative/pricefm_stage_r104_raw_elbo_diagnostics_20260918`

The packet contains fold and aggregate metrics, horizon diagnostics, frozen
case and atom ledgers, source hashes, forecast PDFs for BG and BE, and a
12-page VB convergence PDF. The JSON summary records
`broad_relaunch_authorized = false`, `test_opened = false`, and the required
next gate.

## Decision gate

Before any broad campaign resumes, the forecast and convergence PDFs must be
reviewed explicitly. Acceptance requires scientifically plausible trajectories,
coverage and width, stable horizon behavior, bounded paths, low curve crossing,
and a defensible fixed operator across folds. AQL improvement alone is not
sufficient. The next bounded stage, if the visual review is accepted, is tail
treatment and path-count stability; it is not a broad refit.
