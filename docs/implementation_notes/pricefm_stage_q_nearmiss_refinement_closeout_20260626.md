# PriceFM Stage-Q near-miss refinement closeout

Date: 2026-06-26

## Scope

Stage Q was a median-only refinement screen for the two Stage-P near misses:
`NL` fold 3 and `RO` fold 1.  The run was validation-selected and test-audited.
It did not mutate the Stage-M article-facing decision surface, and no Stage-Q
candidate can be promoted without a later seven-paper-quantile confirmation.

This closeout records the completed priority-0 run and freezes the decision:
Stage Q is clean negative evidence, not a promotion source.

## Implemented closeout tooling

New tracked script:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/77_closeout_pricefm_stage_q_nearmiss_refinement.py
```

New focused test:

```sh
application/data_local/pricefm/venv/bin/python \
  -m pytest application/tests/test_pricefm_stage_q_closeout.py -q
```

Ignored closeout output root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_q_nearmiss_refinement_closeout_20260626/
```

Important generated outputs:

- `stage_q_priority0_health.csv`
- `stage_q_priority0_closeout_summary.csv`
- `stage_q_target_best_by_validation.csv`
- `stage_q_target_best_by_test_audit.csv`
- `stage_q_selection_transfer_diagnostics.csv`
- `stage_q_family_diagnostics.csv`
- `stage_q_method_class_baseline_summary.csv`
- `stage_q_selected_horizon_group_diagnostics.csv`
- `stage_q_best_horizon_group_diagnostics.csv`
- `stage_q_closeout_report.md`
- `summary.json`

## Health checks

| Check | Value |
|---|---:|
| Priority-0 experiments | 84 |
| Metric files | 84 |
| Launch rows completed | 96 / 96 |
| Nonzero launch return codes | 0 |
| Binary fit artifacts | 0 |
| Log error/traceback/non-finite/NaN/warning hits | 0 |
| Wall time | 4:19:18 |
| Peak RSS | 2,075,232 KB |
| Run clean | TRUE |

The run used 12 experiment jobs and wrote metrics under:

```text
application/data_local/pricefm/runs/pricefm_stage_q_nearmiss_refinement_20260626/
```

## Target-level result

| Region | Fold | PriceFM AQL | Stage-P AQL | Validation-selected Stage-Q | Stage-Q selected test AQL | Best Stage-Q test AQL | Decision |
|---|---:|---:|---:|---|---:|---:|---|
| NL | 3 | 6.4117 | 6.5443 | `stageq_nl_f3_g2_lowin_rhi`, exAL RHS_NS | 8.1305 | 7.8058 | do not promote |
| RO | 1 | 7.5680 | 7.8900 | `stageq_ro_f1_g2_in0p23625`, AL RHS_NS | 10.0195 | 9.5057 | do not promote |

The validation-selected rows slightly improved median validation AQL relative to
the Stage-P source rows, but both were substantially worse on test AQL than the
Stage-P candidates and cached fold-aligned PriceFM.

## Selection-transfer diagnostics

| Region | Fold | Q-DESN candidates | Spearman validation/test rank | Validation-selected test regret | Selected delta vs Stage-P | Selected delta vs PriceFM | Oracle delta vs Stage-P | Oracle delta vs PriceFM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NL | 3 | 84 | -0.0163 | 0.3247 | +1.5862 | +1.7188 | +1.2615 | +1.3941 |
| RO | 1 | 84 | 0.0938 | 0.5138 | +2.1295 | +2.4516 | +1.6157 | +1.9378 |

The validation/test rank association is effectively absent.  This is the main
scientific reason not to launch more of the same family blindly.  Stage Q did
not fail because a test-strong row was hidden behind the validation-selection
contract; even the test-oracle Q-DESN rows were worse than Stage P and PriceFM.

## Baseline context

| Region | Fold | Best Q-DESN AQL | Best Normal-DESN AQL | Best naive AQL |
|---|---:|---:|---:|---:|
| NL | 3 | 7.8058 | 9.3287 | 12.3465 |
| RO | 1 | 9.5057 | 11.9065 | 12.8689 |

Stage-Q Q-DESN remains better than Normal-DESN and simple naive baselines, but
that is not enough for promotion because the relevant comparison is against the
already stronger Stage-P candidates and cached PriceFM rows.

## Horizon-block audit

The closeout writes horizon-group diagnostics for the validation-selected and
test-oracle rows.  The failures are not just a single isolated horizon:

- NL validation-selected AQL by horizon block: `5.2164`, `8.3928`, `9.6636`,
  `9.2492`.
- NL test-oracle AQL by horizon block: `5.2863`, `8.1230`, `9.3598`,
  `8.4540`.
- RO validation-selected AQL by horizon block: `6.0451`, `11.4281`,
  `12.5826`, `10.0222`.
- RO test-oracle AQL by horizon block: `5.2079`, `10.9204`, `11.9970`,
  `9.8975`.

The middle and late horizon blocks are the dominant weak points.  Future
diagnostics should look at horizon-block-specific selection and graph input
parity rather than only global reservoir capacity.

## Decision

- Do not promote any Stage-Q priority-0 candidate.
- Do not mutate the Stage-M decision surface.
- Keep `SE_4` fold 1 as the existing Stage-P positive article candidate.
- Keep `NL` fold 3 and `RO` fold 1 unresolved rather than rescued.
- Do not launch Stage-Q priority 1 from this refinement family.
- Treat Stage-Q as clean negative evidence about this local graph-Q-DESN search
  neighborhood.

## Recommended next step

The next useful step is not another broad hyperparameter launch.  First run a
diagnostic stage focused on:

1. validation/test transfer across the broader PriceFM registry;
2. horizon-block-specific errors and selection instability;
3. graph-neighbor information-set parity with PriceFM;
4. whether a more stable selection rule should use multiple validation blocks
   or horizon-block summaries before any further rescue launch.

Only after that diagnostic stage should a new grid be designed.

## Validation

Commands run:

```sh
application/data_local/pricefm/venv/bin/python \
  -m pytest application/tests/test_pricefm_stage_q_closeout.py -q

application/data_local/pricefm/venv/bin/python \
  -m py_compile application/scripts/pricefm/77_closeout_pricefm_stage_q_nearmiss_refinement.py

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/77_closeout_pricefm_stage_q_nearmiss_refinement.py
```

Results:

- focused closeout test: 1 passed;
- script compile: passed;
- real closeout: `run_clean = true`,
  `no_stage_q_promotions_recommended = true`,
  `stage_m_surface_changed = false`.
