# PriceFM R134 pure-QDESN optimization

## Decision

R134 is a bounded development experiment on BG, HR, and DK_1. It answers whether the pure
QDESN family has been sufficiently optimized before any all-region rollout. It does not replace
authority, mutate an article or registry, or authorize wider deployment.

The current evidence does not justify jumping directly to more regions. Earlier experiments
sampled only a few architectural basins and then transferred them. R134 therefore expands the
training-only search over output and exogenous lags, depth, width, graph inputs, sparse-input
policy, leakage, spectral radius, input scale, recurrent sparsity, fan-in, and inter-layer gain.
The R98 regional specification and all inherited R123 basins remain explicit controls.

## Scientific boundary

All architecture and tau0 selection uses only three forward inner splits inside the first official
training window. Each inner origin is teacher-forced from observed history, while its 96-step
forecast is recursive. The seven-quantile AL finalist score, rather than the Normal proxy alone,
freezes one specification and tau0 per region. Official folds are evaluated only after freezing.

Because these official outcomes have already been inspected in prior development, their R134
scores are retrospective development evidence, not untouched confirmation. A new future window
is still required for a strict confirmatory claim.

## Staged campaign

1. Build immutable, training-only banks for four declared feature policies.
2. Score at least 640 admissible deterministic balanced candidates per region with Normal Ridge
   and deterministic recursive Normal-location drivers. This is an explicit broad-screen proxy,
   not the final estimand. Ridge outputs are compact scores only; no candidate-level Gram matrices
   are retained.
3. Retain the 30 best structures plus the exact R98 control. Materialize each shortlisted
   structure/split statistic once, then share it across dimension-aware tau0 multipliers
   0.1, 1, and 10 (also retaining the R98 tau0 for the protected control).
4. Fit certified Normal RHS VB on all three inner splits and score a bounded S=100 stochastic
   driver screen. Advance only the best two complete structure/tau0 groups per region.
5. Fit seven nested independent AL-RHS VB levels for each finalist and inner split using exact
   CRAN `exdqlm` 1.1.1. Warm starts initialize optimization only and never define a prior center.
6. Freeze the regional winner by mean seven-quantile AQL across all three inner splits, with the
   worst-split AQL as a deterministic tie-break diagnostic.
7. Refit Normal RHS and seven AL models on every official fold, produce S=500 recursive H96
   forecasts, and compare the complete cohort with R98 QDESN and both cached and local PriceFM.

## Search domain

- output lags: 32 through 2880 quarter-hours, including weekly and multi-week scales;
- exogenous lags: 0 through 672 quarter-hours;
- depth: 2 through 6 layers;
- readout dimension: at most 1537, with medium and large tapered widths;
- alpha: 0.05 through 0.90; rho: 0.40 through 0.99;
- input scale: 0.01 through 0.50; recurrent sparsity: 0.01 through 0.20;
- fan-in: 8 through 256; inter-layer gain: 0.10, 0.20, or 0.35;
- target-only, graph mean, graph mean+SD, and neighbor-exogenous inputs;
- coverage and balanced sparse input connectivity.

The reservoir seed is fixed. This isolates architecture effects and avoids spending the primary
budget on seed variation. Seed robustness is a later audit for the frozen winner, not a selection
dimension here.

## Execution and storage

The Jerez controller may use at most 30 physical cores, pins one single-threaded worker to each
core, and leaves two physical cores plus explicit memory and disk reserves. Heavy sufficient
statistics are created only after Ridge shortlisting and reused across tau0 fits. Interrupted task
directories are preserved separately before a task is retried. Every task, contract, input, source,
and completion seal is hashed; completed tasks are resumable and never silently overwritten.

## Decision after completion

Review the complete nine region-fold results, inner-selection stability, convergence, crossing,
coverage, and horizon diagnostics. Continue pure-QDESN refinement only if failures identify a
specific training-only weakness. Consider wider rollout only if the three-region cohort shows a
credible aggregate improvement or a scientifically useful region-dependent pattern. No single
fold result is a promotion gate.
