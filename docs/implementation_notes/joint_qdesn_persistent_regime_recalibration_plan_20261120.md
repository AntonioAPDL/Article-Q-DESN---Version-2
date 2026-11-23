# JOINT Persistent-Tail and Regime-Shift Recalibration Plan

## Decision

This campaign targets only `persistent_heavy_tail` and `regime_shift`. The current article authority remains unchanged unless a later protected confirmation succeeds. The campaign stops after an observational independent-median AL VB review and cannot launch joint, exAL, MCMC, dense-grid, article, or Overleaf work.

The continuation branch was created directly from authoritative `origin/main` at `d49b08e025056020cb12bbdcf85f046fac3f2f88`. Previously frozen JOINT branches were not rebased or rewritten because their commits are already ancestors of main.

## Diagnosis

The authoritative MCMC packet shows acceptable fit-window recovery but much poorer recursive protected forecasts in these two scenarios. Scalar MCMC diagnostics are not sufficiently pathological to make sampler repair the primary intervention. The earlier screen already covered 768 candidates per scenario across broad scalar `alpha`, `rho`, lag, sparsity, and input-scale ranges, so repeating that search would add little information.

The useful unexplored dimensions are:

- layer-specific rather than shared `alpha` and `rho` schedules;
- depths through six and full-state readouts through 600 states;
- response lags through 240;
- expanding as well as flat and tapered layers;
- three deterministic reservoir seeds;
- `tau0` beyond both boundaries of the earlier grid;
- an explicit independent median-AL transfer gate before expensive full quantile fitting.

## Frozen Workflow

1. Generate 1,024 deterministic candidates per scenario, including the exact authoritative v2 specification as a parity anchor.
2. Score Gaussian ridge fits on three protected-row-free selector realizations using 350 training rows and 150 internal calibration rows.
3. Advance the best 50 candidates per scenario by mean recursive calibration aCRPS, using worst-replicate score and between-replicate SD as tie-breakers.
4. Fit Gaussian RHS VB over `tau0 = 10, 1, ..., 1e-6` and advance eight architecture-scale pairs per scenario.
5. Refit each advanced pair as an independent median AL VB model. Rank by recursive median check loss; convergence is reported, while finite max-iteration fits remain review-level.
6. Stop for scientific review. A later contract may promote a scenario-specific winner to the seven-quantile independent AL, joint AL, exAL, and MCMC sequence.

## Forecast Contract

Selection uses only the observational window. Origins move through the internal calibration window with teacher forcing between origins. Within each 30-step origin, forecasts are recursive: the Gaussian mean or AL median is fed into future response lags. The readout is an intercept plus every reservoir state and contains no raw inputs. The 1,000-row article/protected window is not persisted in selector fixtures.

## Promotion Rule

The median-AL result is evidence for architecture transfer, not article evidence. Any finite mean improvement may be retained for later confirmation, but no replacement occurs until the full seven-level models are fit on a separately frozen protected design and compared with the authoritative parity model. Poor scalar mixing alone will not veto a later model if forecast functionals are stable; pathological or nonfinite fit/forecast behavior remains disqualifying.

## Reproducibility Checklist

- [x] Dedicated continuation branch starts exactly at current `origin/main`.
- [x] Current authoritative candidates are explicit parity anchors.
- [x] Candidate generation and seeds are deterministic.
- [x] Selection fixtures contain zero protected rows.
- [x] Gaussian ridge, Gaussian RHS, and median AL stages have separate plans and manifests.
- [x] One numerical thread is enforced per worker.
- [x] Runtime output remains under ignored `application/cache`.
- [x] Expensive launch requires `JOINT_PR_CONFIRM_LAUNCH=1`.
- [x] Automatic execution stops after median AL VB review.
- [x] Focused targeted, pure-recursive, expanded-screen, and quantile tests pass.
- [x] Prepared packet verifies 2,048 candidates, 6,144 ridge jobs, six selector fixtures, and zero protected rows.
- [x] Muscat preflight observed ample disk capacity; no campaign workers were launched.
- [ ] Recheck host CPU ownership immediately before an explicit launch.
- [ ] After completion, audit score robustness and decide whether full quantile confirmation is justified.
