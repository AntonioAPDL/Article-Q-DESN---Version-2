# JOINT stronger-window richer-screen implementation

Date: 2026-11-21

Branch: `work/joint-qdesn-stronger-window-richer-screen-20261121`

## Purpose

This lane implements the replacement, scenario-specific Q-DESN selection
campaign. It does not alter the current article authority. Selection uses a
500-row washout, 1,000-row internal fit window, and 300-row internal recursive
calibration window. The existing 1,000-row article evaluation realization is
preserved byte-for-byte and remains unavailable to every selection stage.

The campaign screens intercept-plus-reservoir readouts only. It varies depth,
layer widths and shapes, response lags, leakage, spectral radius, input scale,
input sparsity, and recurrent sparsity. Each scenario is selected separately;
no universal architecture is imposed.

## Implemented boundary

- frozen contract, axes, scenario registry, and anchor registry;
- exact protected-row identity audit;
- deterministic 4,096-candidate registry per scenario;
- exact primal/dual Gaussian ridge dispatch, including Woodbury predictive
  covariance without a dense parameter covariance for `p >= n`;
- six-point resource benchmark at 24, 300, 600, 1,200, 1,500, and 2,000
  retained states;
- resumable R1a, R1b, R2, and R3 worker plans and fail-closed finalizers;
- canonical-seed seed-robustness aggregation without seed shopping;
- H1, H2, and H3 normal-RHS plans, workers, and fail-closed finalizers;
- backend blocking that keeps dimensions above 600 as ridge evidence unless a
  separately tested scalable inference continuation is frozen;
- explicit physical-core affinity, one numerical thread per worker, durable
  storage and memory gates, and stage capacity receipts.

The H3 finalizer emits the frozen median-AL input plan. Median/seven-grid AL,
exAL, joint VB, and MCMC execution remain later scientific stages because the
contract requires measured benchmark and funnel evidence before those plans
can be finalized. Existing quantile and exact-M0 kernels are not modified in
this lane.

## Execution rule

Only the six-worker benchmark is authorized by the 2026-11-21 implementation
instruction. Its finalizer must stop at
`BENCHMARK_COMPLETE_READY_FOR_R1A_REVIEW`. Every later stage requires an exact
stage confirmation token and an explicit physical CPU list. Finalizers may
prepare the next plan but never launch it.

The ignored authoritative planning tracker is:

`local_trackers/joint_qdesn_stronger_window_richer_screen_plan_20261121/JOINT_QDESN_STRONGER_WINDOW_RICHER_SCREEN_ULTIMATE_PLAN_20261121.md`

Runtime remains ignored under:

`application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`

No manuscript, table, figure, Overleaf branch, `main`, historical runtime, or
unrelated scientific lane is modified by this implementation.
