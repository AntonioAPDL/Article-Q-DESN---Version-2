# PriceFM Stage-R93 Coarse-Winner Quantile Resume

## Decision

Stage-R93 will accept the fully converged coarse normal-RHS winner and skip the
pre-registered conditional `tau0` refinement. It will retain the required
outer Fold-1 normal confirmation and then run the complete seven-quantile AL
and structured-exAL validation ladder. This amendment changes no selected arm,
uses no test evidence, and leaves test scoring, registry mutation, article
mutation, joint fitting, and MCMC blocked.

The accepted arm is
`r93_se2_rhs_r08_t1em02_7b1d63a908`, with `tau0=0.01` and median inner-window
validation AQL `5.065631`. Its parent Ridge geometry is
`r93_se2_search_126_b512ee3d02` (Ridge rank 8): `graph_summary_mean`, lag 240,
depth 2, units `[120,64]`, `alpha=0.50`, `rho=0.95`, input scale `0.15`, and
final-layer readout.

## Evidence audit

The 240-candidate Ridge screen completed all 720 inner-window cells. The
30-geometry by three-`tau0` normal-RHS screen completed all 270 cells. The
launcher reported no failed experiments and every cell produced a finite
validation AQL. Of the 270 RHS cells, 182 met the strict coefficient-change
criterion; 88 reached the 100-iteration budget.

The accepted `tau0=0.01` arm converged in all three windows:

| Inner fold | Iterations | Final maximum beta change | Validation AQL |
|---:|---:|---:|---:|
| 101 | 83 | `9.5721e-6` | 6.329729 |
| 102 | 74 | `8.5770e-6` | 5.065631 |
| 103 | 74 | `9.7162e-6` | 4.027738 |

The normal-RHS public fit did not populate an ELBO trace; every saved ELBO
entry is `NA`. Its declared stopping diagnostic is maximum absolute beta
change. The selected arm passed that diagnostic on every inner window, while
its scale traces stabilized. No iteration-budget increase is warranted for the
selected arm.

The closeout failure was an accounting defect. It filtered nonconverged arms
before checking structural surface completeness, then treated the excluded
`tau0=0.001` sibling as missing. The repaired closeout first verifies that all
three coarse arms physically exist, records numerical eligibility separately,
and selects only among fully converged arms.

## Why refinement is waived

The pre-registered rule requested refinement because the winner was at the
upper coarse boundary and the two eligible endpoints were nearly tied. The
planned refinement values were `5e-5`, `5e-4`, and `2e-3`; none brackets or
exceeds the selected upper boundary `1e-2`. Running those nine additional
normal-likelihood cells would therefore not refine the winning side of the
surface. It would also add tuning under the normal objective before the target
AL/exAL quantile comparison.

The amendment accepts the winner produced by the existing deterministic
ranking. It does not substitute another candidate or consult a forecast/test
window. Accordingly, the defensible claim is that `tau0=0.01` is the coarse
validation-selected value, not a globally optimized value.

## Remaining execution contract

1. Close the complete coarse-RHS surface and freeze the exact winner ID,
   geometry, `tau0`, source grid hash, and amendment record.
2. Fit one normal-RHS model on original Fold 1 train/validation only. The test
   interval remains absent. This outer confirmation must be finite and
   converged and must write the beta and parameter summaries used for
   initialization.
3. Fit AL and structured exAL RHS_NS at quantiles
   `0.10,0.25,0.45,0.50,0.55,0.75,0.90` using the median-centered warm tree.
   Each exAL atom starts from the same-quantile AL state.
4. Compare AL and exAL only as complete seven-quantile families on reserved
   Fold-1 validation AQL. Per-quantile family mixing is forbidden.
5. Freeze the selected family and stop. An all-fold scoring-only test audit
   requires separate authorization.

The quantile runner is sequential because its warm-start graph has explicit
dependencies. It checkpoints every atom, so interruption resumes completed
work rather than refitting it.

## Safety and reproducibility gates

- The acceptance flag must be accompanied by the exact expected winner ID and
  expected `tau0`; any mismatch fails closed.
- The original pre-registered refinement decision and triggers remain in the
  generated JSON next to the explicit amendment.
- Completed Ridge and coarse-RHS grids are reused and must not be relaunched.
- The code worktree must be clean and at the exact pushed task-branch HEAD.
- Every process is pinned to one logical CPU and numerical libraries are fixed
  to one thread.
- At least 100 GiB disk and 32 GiB available memory are required.
- Test, registry, article, joint, and MCMC authorization remain false.

## Resume command

After focused tests, commit, and push on the dedicated R93 branch, resume with:

```bash
python application/scripts/pricefm/296_orchestrate_pricefm_stage_r93_overnight.py \
  --approval-token RUN_PRICEFM_R93_VALIDATION_LADDER \
  --expected-code-head <pushed-task-branch-head> \
  --accept-coarse-winner-without-refinement \
  --expected-coarse-winner-id r93_se2_rhs_r08_t1em02_7b1d63a908 \
  --expected-coarse-winner-tau0 0.01 \
  --workers 1 \
  --cpu-list <one-confirmed-idle-cpu>
```

The controller must quarantine only the incomplete prior closeout directory,
reuse the 240 Ridge and 90 RHS experiment statuses, launch one outer normal
confirmation, run the 14 checkpointed quantile atoms, close validation, and
stop before opening test evidence.
