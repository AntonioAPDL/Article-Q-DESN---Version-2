# JOINT Laplace-First Coefficient Coupling Experiment

## Evidence and Scope

The completed fixed-backbone run, source 199ed8f0, has 336/336 MCMC workers and
156/156 score cells, with no failures. Its score-width audit (a67faa5e) reproduced
24 confirmation cells and 81,000 posterior score rows. Laplace joint AL/exAL
interval widths remain about 3.99/3.14 times independent. The exAL challenger
improved the mean about 0.25%, but did not solve this discrepancy.

AL also shows the problem, so gamma is not a general explanation. Cross-level
loss covariance contributes 64-70% of joint score variance; between-chain mean
dispersion is at most about 1.2%. Some joint quantile variances are smaller,
while worse calibration increases loss sensitivity. Common-design and
coefficient/intercept comparisons localize most of the point-score gap to the
reservoir coefficient block. These do not prove a prior intervention will help.

Do not repeat the previous 15-arm tau0 search, alter the DESN, change the
likelihood, force shorter credible intervals, extend all gamma chains or fit a
denser quantile grid. Case A's geometry differs and is not included. Historical
Phase159 slab variation is not a novel idea by itself; this experiment uses a
distinct training-calibrated target on the current backbone, exact M0 and score
contract. The variance-budget rule is not any claim to fully match priors.

## Frozen Rules

Use the current Laplace backbone, intercept plus all retained reservoir states,
without direct raw-input readout. One layer, 48 states, response lags 10, no
exogenous inputs, alpha .8, rho .75, reservoir seed 202609250, input scale .5,
recurrent sparsity .2 and input sparsity .25. Baseline tau0 and fixed slab
variance are 1. This is case-specific, not a universal specification.

Three joint arm rules share the same controls under AL and exAL:

1. Baseline: unchanged anchor/difference RHS prior.
2. Innovation slab: keep tau0 and anchor slab unchanged; multiply innovation
   slab variance by clamp(1 + mean adjacent coefficient second-moment energy /
   mean marginal coefficient second-moment energy, 2, 4).
3. Conditional variance budget: keep both slab variances unchanged. With unit
   local scales and global scales initialized at tau0, let V be the independent
   conditional coefficient variance. Allocate a fraction s to the anchor and
   (1-s)/(K-1) to each innovation. Determine s from the training anchor energy /
   (anchor energy + sum adjacent energies), clipped to [.2,.8]. Solve the RHS
   conditional variance equation for each initial global scale/tau0. Terminal
   coefficient variance then equals V at this reference initialization.

For all rules, energy uses independent AL VB coefficient means/covariances and
training state-column mean squares only. Adjacent second moments include both
independent marginal variances. This is an explicit empirical-Bayes rule, not
an observation-independent prior or a globally optimal variance allocation.
Matching reference initialization variance does not match the full random-scale
prior or posterior. The bounded slab rule is a deliberately small hypothesis,
not a recommendation to universally relax or tighten shrinkage.

Per-dataset controls, training coefficient energies/readout diagnostics, source
hashes and baseline VB fits are sealed before any arm score is computed.
Confirmation repeats the predeclared rule on fresh training data; it does not
reuse calibration outcomes or retune the rule against protected scores.

Selection: two independent screen realizations; fit 350 observations and score
the next 150 within the observational window, five origins with 30 recursive
leads. Teacher force between origins, never within recursive unknown leads.
The final test window is excluded from selection. Gaussian RHS -> median-outward
independent AL -> paired structured exAL -> joint VB initializes each MCMC fit.
Baseline joint VB computed for training diagnostics is reused, not fitted twice.
MCMC chains initialize independently from the respective VB fit and run in
parallel; independent quantile components within a chain use distinct seeds.

Primary: posterior mean DGP-integrated expected finite-grid quantile score.
Report its median, 95% credible interval, canonical quantile-action score,
realized aCRPS, fit oracle MAE and raw/contract crossings. Grid .05,.10,.25,.50,
.75,.90,.95; trapezoid weights .025,.10,.20,.25,.20,.10,.025, sum .9, factor two.
Keep the mean-reservoir endpoint-clamp recursive design and independent
within-chain product coupling unchanged. Score intervals are not predictive
intervals for observations, MCSE or frequentist confidence intervals.

Select the lowest matched mean if it improves baseline by any positive amount.
Near/exact ties retain baseline. Full scalar mixing passes and nonoverlapping
intervals are not required. The old 1.2 functional-Rhat threshold remains a
visible review label, not a selection veto. Hard failure: incomplete manifests,
nonfinite scores/functionals, contract crossings, score/quantile-functional
Rhat >1.5 or state-half/chain-mean relative score differences >.2. These relaxed
thresholds are pathology safeguards, not a claim of conventional convergence.
Canonical recovery, raw crossings and interval widths remain visible, not
alternative post-hoc selection criteria. A smaller interval alone is not a gain.

## Budget and Automation

Screen: 16 score cells, 32 MCMC chain workers, two chains/cell. AL 2000 iterations,
500 burn, thin 2; exAL exact M0 4000 iterations, 1000 burn, thin 2.
Confirmation: two fresh realizations, baseline plus selected joint challenger
per likelihood and independent controls. 8-12 cells, 24-36 workers, three chains.
AL 4000 iterations, 1000 burn, thin 4; exAL M0 8000 iterations, 2000 burn, thin 4.
Total 56-68 workers, not another 336-worker campaign. VB max 960 iterations.
No long-chain duplicate arm, no additional tuning rounds or expensive smoke fits.

Jerez only, up to 15 distinct free physical cores; taskset affinity and one
numerical thread per worker. Gate on sibling-core load, restricted affinity
conflicts and >=50 GiB free disk. No launch if the gate is blocked. No other
lane job is stopped or modified. Controller runs in tmux, freezes selection
before confirmation, fails closed on errors, skips verified completed workers
on explicit resume and does not restart an already complete run.

## Files and API Boundary

New files only: coupling module/contract/bootstrap/worker/capacity/launcher,
one focused test, this note. The standalone module binds experiment-local
adapters to the prior-screen workflow only when its dedicated bootstrap is
sourced. Production defaults, original prior module, samplers, forecast and
score cores, article assets and other lanes are unchanged.

RHS initialization, AL/exAL VB and MCMC receive the same split tau0/slab controls;
the common target fingerprint includes all of them. Frozen nested initialization
and calibration receipts are verified at collection. Baseline equivalence,
training-only perturbation invariance, exact conditional covariance, distinct
targets, slab controls, M0 dispatch and relaxed positive-gain selection are
covered by one essential test with small test-only fitting budgets.

Commands from the new task worktree, numerical thread environment set first:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla application/tests/test_joint_qdesn_laplace_coupling.R
bash -n application/scripts/launch_joint_qdesn_laplace_coupling.sh
bash application/tests/test_joint_exqdesn_cpu_queue.sh
```

Commit/push only work/joint-qdesn-laplace-coupling-20261006 before deployment.
Create a separate clean Jerez worktree tracking that branch, run pinned tests,
capacity auto-discovery and a second explicit gate, then launch:

```bash
bash application/scripts/launch_joint_qdesn_laplace_coupling.sh "$ROOT" "$CPUS"
```

ROOT and CPUS must be concrete verified paths/IDs, not literal placeholders.
Keep the source HEAD frozen throughout. Monitor startup before leaving it in
the background. Health entry: joint_qdesn_laplace_coupling.R health "$ROOT".

## Closeout

One internal round -> one protected confirmation -> close. Preserve all draws,
initializers, controls, score summaries, 95% intervals, matched contrasts,
numerical repair diagnostics and hashes in ignored runtime. Any positive mean
gain with nonpathological forecasting is descriptive integration-review evidence;
otherwise retain baseline and document the accuracy/coherence tradeoff.
Do not force joint models to win or add unplanned rounds.

A matched article-fixture run and complete verified replacement packet are
still required for article authority. The integration coordinator owns merges,
main and article-only Overleaf publication. Hand off branch/upstream/full HEAD,
exact changes/tests/manifests/counts/storage/exclusions and remaining risks after
closure. Runtime, local trackers and generated figures remain ignored.
