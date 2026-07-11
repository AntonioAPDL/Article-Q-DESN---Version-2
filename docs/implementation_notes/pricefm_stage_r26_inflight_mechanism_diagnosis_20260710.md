# PriceFM Stage-R26 In-Flight Mechanism Diagnosis

Date: 2026-07-10

## Scope

Implemented a read-only Stage-R26 in-flight mechanism diagnosis for the active
Stage-R25 broad horizon-weighted PriceFM run. The stage is intentionally not a
final closeout: it can be run while R25 is incomplete, labels partial evidence
as non-final, and writes diagnostic ledgers only.

No launcher was invoked. No models were fit. No registry, manuscript, article,
or non-PriceFM files were mutated by the script.

## Script

- `application/scripts/pricefm/150_audit_pricefm_stage_r26_inflight_mechanism_diagnosis.py`

The script joins:

- Stage-R21 failure atlas;
- Stage-R22D case-specific screening closeout;
- Stage-R23 mechanism-capability audit;
- Stage-R24 postfit calibration materialization/readiness;
- Stage-R25 launch prep manifest, arm plan, live run artifacts, metrics, horizon
  summaries, cell statuses, and training-weight summaries.

## Outputs

Materialized under:

`application/data_local/pricefm/authoritative/pricefm_stage_r26_inflight_mechanism_diagnosis_20260710`

Key outputs:

- `pricefm_stage_r26_r25_health.csv`
- `pricefm_stage_r26_case_progress.csv`
- `pricefm_stage_r26_partial_metric_rows.csv`
- `pricefm_stage_r26_partial_validation_selected_case.csv`
- `pricefm_stage_r26_partial_test_oracle_case.csv`
- `pricefm_stage_r26_arm_mechanism_summary.csv`
- `pricefm_stage_r26_horizon_mechanism_summary.csv`
- `pricefm_stage_r26_failure_decomposition_map.csv`
- `pricefm_stage_r26_mcmc_confirmation_gate.csv`
- `pricefm_stage_r26_next_action_plan.csv`
- `pricefm_stage_r26_diagnosis_gates.csv`
- `source_manifest.csv`
- `summary.json`
- `pricefm_stage_r26_inflight_mechanism_diagnosis_report.md`

## Current Findings From Materialized Run

At materialization time, Stage-R25 was still running:

- 171 / 200 experiments had completed metric summaries.
- 29 experiments remained to metric completion.
- 342 Q-DESN/exQDESN method rows were parsed.
- 2 method rows beat current authoritative Q-DESN.
- 0 method rows beat cached PriceFM.
- 0 method rows beat both current Q-DESN and cached PriceFM.
- 18 validation-selected cases were available.
- 0 validation-selected rows beat PriceFM.
- 0 validation-selected rows beat both.
- 0 rows entered the MCMC confirmation gate.

Best observed partial row:

- `NO_4` fold 2, `alt_information_set_weighted`,
  `qdesn_al_rhs_ns_exact_chunked`
- test AQL gap vs current Q-DESN: `+0.277693`
- test AQL gap vs cached PriceFM: `+0.377406`

Best validation-selected current-Q-DESN improvement:

- `NO_4` fold 1, `alt_information_set_weighted`,
  `qdesn_exal_rhs_ns_exact_chunked`
- test AQL gap vs current Q-DESN: `-0.076193`
- test AQL gap vs cached PriceFM: `+0.585464`

These are mechanism-learning signals, not promotion signals.

## Main Diagnosis

The partial R25 evidence continues the pattern from R22D:

1. True horizon weighting and broader readout/capacity variants can improve some
   rows relative to prior Q-DESN or R22D.
2. The same variants are not closing the cached PriceFM gap.
3. MCMC is not justified yet because no validation-selected candidate beats
   PriceFM or reaches the configured near-miss gate.
4. Internal Q-DESN improvements should remain diagnostic only.
5. If final R25 remains negative, the next expensive work should pivot away from
   simply widening the same horizon-weight/readout family.

## Gates

All read-only diagnosis gates passed:

- Stage-R25 manifest is validation-selection-only.
- Test metrics remain audit-only.
- Registry and manuscript mutation remain blocked.
- Incomplete R25 evidence is explicitly labeled in-flight.
- Parsed metrics joined to current Q-DESN and cached PriceFM baselines.
- No article or registry promotion gate is opened.
- Completed metric rows have completed cell statuses.

## Recommended Next Action

Wait for R25 to finish, then run a final Stage-R26 closeout over the complete
200-experiment surface.

Final closeout should:

1. verify exit code zero;
2. verify 200 / 200 metric summaries and cell statuses;
3. freeze winner selection using validation AQL only;
4. audit test performance against current authoritative Q-DESN and cached
   PriceFM;
5. admit MCMC only for validation-selected candidates that beat both, or for an
   explicitly approved near-miss after final closeout discussion;
6. keep registry and article mutation blocked unless full-quantile and MCMC
   confirmation gates pass.

If no candidate beats PriceFM after full R25 completion, the next mechanism
family should target information-set parity, calibration artifacts, or a
different objective/model-family design rather than a larger repeat of R25.
