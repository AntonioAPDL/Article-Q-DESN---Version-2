# PriceFM Stage-R111A: EE neighbor-driver completion

## Purpose

Stage R110D isolated the unresolved EE recursive error to the active neighbor panel. EE uses the frozen active set `EE|FI|LV`; replacing only the EE target driver left pooled EE AQL at `16.03315`, while the exact-all-active diagnostic was `40.20%` better than the exact-target-only diagnostic. R111A therefore completes only the missing FI and LV direct drivers and replays the already-fitted EE quantile readout.

This is not an all-region campaign. BG readout exposure remains a separate, unauthorized design question, and BE remains a frozen control.

## Scientific contract

- Fit regions: FI and LV only.
- Selection data: three embargoed pseudo-folds contained entirely within outer fold 1 training.
- Ridge readouts: shared and 24-hour horizon blocks.
- RHS candidates: the frozen regional `tau0` and one quarter of that value, evaluated only after selecting the Ridge readout.
- Final regional policy: one readout/prior/`tau0` choice per region, frozen across outer folds 1-3.
- Predictive paths: 500 raw posterior paths per region-fold.
- EE replay: existing R110 EE target paths + new R111A FI/LV paths + frozen R103 EE AL/exAL family and coefficient posterior.
- Scale contract: each regional driver remains on its own processed response scale, matching the per-region windows consumed by the synchronous EE feature builder.
- Evaluation: outer validation only. Test access is forbidden.

The frozen FI and LV specifications come from the R98 region authority:

| Region | Policy | DESN | Lag | alpha | rho | input scale | tau0 |
|---|---|---:|---:|---:|---:|---:|---:|
| FI | target only | 2 x 96 | 240 | 0.50 | 0.82 | 0.15 | 0.01 |
| LV | graph mean | 3 x 40 | 96 | 0.35 | 0.90 | 0.20 | 0.01 |

## Dependency graph

1. Build six train/validation adapters for FI/LV x folds 1-3.
2. Run 12 Ridge inner-training tasks.
3. Select one readout per region.
4. Run 12 RHS inner-training tasks.
5. Select one final policy per region across Ridge and RHS candidates.
6. Run six outer-validation driver fits.
7. Run three no-refit EE all-active replay cases.
8. Materialize the closeout, source ledger, and decision gates.

No downstream phase can start before its dependency is complete. Every fit is single-threaded and pinned to one distinct idle physical core. The largest concurrent phase has 12 tasks; requesting 30 workers does not create more than 12 simultaneous fits.

RHS fits use a convergence ceiling ladder of 750 then 1,500 iterations. A completed 750-iteration fit is retained by exact task-contract hash; only a task that reaches the first ceiling without convergence is repeated at 1,500. Final selected RHS fits use a 1,500-iteration ceiling. The tolerance, objective, data, and model are unchanged by this computational continuation rule.

## Promotion gate

R111A is a mechanism experiment, not a registry promotion. The EE mechanism passes only if:

- all three EE replay folds and all six FI/LV driver folds complete with 500 paths;
- pooled EE AQL improves by at least 10% over the R110 target-only replay;
- no EE fold is harmed by more than 5% relative to that replay;
- pooled EE AQL is at most 10% above the frozen R97 direct reference;
- late-horizon AQL improves by at least 10% over R110 target-only replay;
- all metrics are finite.

Even a pass does not authorize registry, article, test, joint-model, MCMC, or broad all-region work. It only resolves the EE neighbor-driver mechanism and permits a separately reviewed BG readout-design stage.

## Reproducibility and resumption

The preparation script records the task surface, frozen configurations, git HEAD, campaign contract, and SHA-256 source ledger. The orchestrator refuses to run if HEAD or any frozen source hash changes. Each completed task records a contract hash and is reused only when that exact hash matches. Outputs are written through temporary directories and atomically installed.

Entrypoints:

```bash
PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
ROOT=/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r101_recursive_20260916

$PY $ROOT/application/scripts/pricefm/373_prepare_pricefm_stage_r111a_ee_neighbor_driver.py --code-root $ROOT
$PY $ROOT/application/scripts/pricefm/376_orchestrate_pricefm_stage_r111a_ee_neighbor_driver.py --code-root $ROOT --workers 30
```

The second command is the only launch command. Re-running it is a hash-checked resume, not a blind restart.
