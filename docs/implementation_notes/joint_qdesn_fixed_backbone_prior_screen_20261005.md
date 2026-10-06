# JOINT Fixed-Backbone Prior Experiment

## Decision and Scope

Dedicated lane: JOINT. Branch:
work/joint-qdesn-fixed-backbone-prior-screen-20261005.
Base: e721bfddee81269864febea0eca0bbd0c5eba369.
The old dirty Muscat checkout is not an execution source.

This is an experiment, not a claim that the current joint models failed to
converge or that a globally optimal prior has been identified. The user
explicitly excludes additional DESN specification screening. Restrict the
experiment to A (Asymmetric Laplace Tail) and C (Laplace Bridge), the discussed
positive-control/problem cases. Retain eight-family article authority unchanged.

## Audit and Rationale

Completed expanded pure-DESN authority:
docs/implementation_notes/joint_qdesn_pure_recursive_expanded_score_closeout_20261004.md
and tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv.
The prior campaign completed; no old JOINT worker requires stopping.

On the published article fixture, MCMC score means were approximately:

| Case | Joint AL | Independent AL | Joint exAL | Independent exAL |
| --- | ---: | ---: | ---: | ---: |
| A | 0.3805 | 0.4160 | 0.3737 | 0.4323 |
| C | 0.5329 | 0.3800 | 0.5240 | 0.3810 |

A is already a joint-model success and must be protected against regression.
C has wider joint posterior score intervals and worse means. A wider credible
interval is not proof of nonconvergence. Read-only inspection of retained
five-chain draws found sampled quantile-functional maximum rank/folded Rhat
approximately 1.045 (A AL), 1.007 (A exAL), 1.020 (C AL), and 1.006 (C exAL).
Some C AL coefficients remain mild review cases (maximum about 1.057).
C leave-one-chain-out score means and widths were nearly unchanged. These are
targeted diagnostic probes, not proof that the whole posterior is converged.

Interpretation: do not spend the entire budget chasing gamma mixing. Separate
a real same-target sampling-budget control from genuine prior changes.

Existing API already supports anchor_tau0 and innovation_tau0. Phase158/159
tried split-scale ideas before exact M0 and before the present pure-DESN
recursive protocol. Phase178's pre-M0 authority ledger treats that evidence
as a separate hypothesis, not a decisive current rejection. This is a
new-context test, not an undisclosed novel sampler or a repeat architecture
screen.

The current common-posterior contract uses a fixed RHS slab variance of 1.
Preserve that slab, scale prior IG(2,1), intercept prior construction,
ordered joint intercepts, gamma prior, and scale support (0,Inf).
Do not vary a learned slab's starting value and call it a hyperprior change.

The global shrinkage scale matters scientifically; it changes the posterior
target, not merely initialization. See the primary references:
[Piironen and Vehtari](https://proceedings.mlr.press/v54/piironen17a.html),
[regularized horseshoe](https://arxiv.org/abs/1707.01694).
Rank/folded Rhat, ESS, and MCSE quantify different sampling properties:
[Stan diagnostic definitions](https://mc-stan.org/rstan/reference/Rhat.html).
Our relaxed 1.2 functional review boundary is an exploratory pathology flag,
not a conventional convergence certification.

## Frozen Controls and Experimental Arms

DESNs are copied exactly from:
tables/joint_qdesn_pure_desn_v1_selected_backbones.csv.

| Case | Layers / widths | Response lags | Alpha | Rho | Original tau0 |
| --- | --- | ---: | ---: | ---: | ---: |
| A | 1 / 20 | 5 | 0.97138749 | 0.7868366 | 0.0001 |
| C | 1 / 48 | 10 | 0.8 | 0.75 | 1 |

Input scale, input/recurrent sparsity, reservoir seed, input features and
intercept-plus-all-reservoir-state readout remain unchanged.

Factorial joint prior grid:
- anchor_tau0 = original case tau0 times {1/3, 1, 3};
- innovation_tau0 = original case tau0 times {0.1, 1/3, 1, 3, 10};
- 15 arms, including the exact {1,1} baseline (prior_08).

Smaller innovation scale encourages stronger adjacent-quantile similarity;
larger values allow greater quantile-specific slopes. Varying anchor separately
distinguishes this from changing the overall slope anchor. No one universal
winner across cases or likelihoods is required.

Independent controls retain original case tau0. Equal numeric tau0 does not
make the independent slope prior equivalent to anchor-plus-difference priors.

All exAL MCMC calls explicitly dispatch M0_v_collapsed_support_logit.
All exAL VB uses VB1_structured_v. No inference core is modified.
VB initializers are target-specific; compact MCMC starts contain only sampled
parameter starting values, never posterior-prior fields. Two actual scales
enter each new posterior-target hash.

## Stages and Budget

| Stage | Data / models | Parallel jobs |
| --- | --- | ---: |
| Screen dataset warmup | 2 cases x 2 fresh observational replicates; Gaussian + 14 independent VB fits and common oracle each | 4 |
| Joint VB warmup | 15 prior arms x 4 datasets; paired AL/exAL initializers | 60 |
| MCMC screen | 240 joint chains + 16 independent-control chains + 8 longer AL baseline chains | 264 |
| Screen score cells | 120 joint cells + 8 independent cells + 4 longer AL cells | 132 |
| Confirmation dataset warmup | 2 cases x 2 new protected replicates | 4 |
| Confirmation prior warmup | Baseline plus AL/exAL selected arms, deduplicated within each dataset | 4-12 |
| Fresh MCMC confirmation | 3 chains per cell; selected joint versus baseline plus independent controls | 48-72 |
| Confirmation score cells | Four model rows per dataset, plus genuine challengers | 16-24 |

Thus 312-336 chain workers in total. One independent worker fits seven
independent components sequentially, with independent component seeds.
Every chain worker is independent of neighboring quantile MCMC, initialized
from the corresponding completed VB. At most 15 single-threaded physical-core
slots are leased; heterogeneous jobs free their CPU on completion.

Screen AL: 2,000 iterations, 500 burn, thin 2 (750 retained).
Screen exAL: 4,000, 1,000 burn, thin 2 (1,500 retained).
Same-target AL longer control: 4,000, 1,000 burn, thin 4 (750 retained).
Confirmation AL: 4,000, 1,000 burn, thin 4 (750 retained).
Confirmation exAL: 8,000, 2,000 burn, thin 4 (1,500 retained).
These are bounded exploratory/confirmation budgets, not guaranteed ESS.
No defensible wall-clock ETA exists before these jobs have measured timings.

## Data Separation and Forecast Contract

Screen: unchanged DGP series geometry; persist only the observational prefix.
500 DESN washout rows, then 350 training and 150 internal calibration rows.
Gaussian reference, scaling, intercept prior, and all quantile fits use the
350 training rows only. Five internal origins, 30 recursive leads each.
Observed history updates between origins; unseen future responses never enter
a recursive trajectory. No protected article fixture is used for selection.

After all screen cells complete, freeze the selected-per-case/per-likelihood
receipt and hashes BEFORE generating fresh confirmation data. Confirmation
uses new DGP seeds, fits the full 500-row observational window, and evaluates
the original 1,000-row protected window/origin design. No additional selection
using that protected window or the published fixture.

Primary score: origin-marginal DGP-integrated expected finite-grid check-loss
score, reported as dgp_integrated_acrps. Seven levels
{0.05,0.10,0.25,0.50,0.75,0.90,0.95}.
Trapezoid weights {0.025,0.10,0.20,0.25,0.20,0.10,0.025}, sum 0.9,
unnormalized, factor 2; this is the frozen truncated-grid convention, not
continuous full CRPS.

Forecast: existing posterior-mean-reservoir design with endpoint-clamped
finite-grid inverse CDF, then readout posterior draws. 200 evenly distributed
state draws per chain, within-chain alternating half integration checks.
Reuse shared forecast random-number seeds across prior arms for each dataset.
All retained readout draws enter score summaries. Joint draws preserve their
dependence; independent quantile blocks use a deterministic within-chain
product-posterior permutation. Original parameter diagnostics are calculated
BEFORE product permutation; shuffled score ESS is not a convergence certificate
for independent component chains.

Shared DGP oracle: 2 x 4,096 trajectories initially; extend in paired shards up
to eight if split-half score tolerance 0.0025 or analytic horizon-one check
0.01 fails. Fail closed if numerical integration remains unverified.

## Decisions and Reporting

Report posterior mean, median, 95% equal-tail score interval, canonical
posterior-mean action score, realized aCRPS, fit/forecast oracle diagnostics,
raw/contract crossings, original-order parameter Rhat, score Rhat/ESS/MCSE,
state-half sensitivity, between-chain mean range, and timings.

Select the smallest matched-replicate mean per case/likelihood with ANY strict
mean improvement over baseline; epsilon 0 honors the user's small-gain policy.
Do not demand nonoverlapping credible intervals or perfect scalar mixing.
Require finite verified outputs, zero contract crossings, and no gross score
functional instability (review at Rhat >1.2 or >20% half/chain mean variation).
This is a deliberately relaxed pathology screen, not a claim of convergence.
Raw crossings, scalar Rhat and mild uncertainty are retained as reviews.

Fresh confirmation compares selected and baseline on the same new replicates.
A lower confirmation mean is a descriptive improvement for integration review,
not automatic article replacement or statistical superiority. Report how many
replicates improve, overlaps, canonical action and individual cases. A prior
can narrow intervals by adding bias; width alone is never the selection target.
A fresh article-fixture stage is required before published authority replacement.

## Code, Tests and Operations

Only new files are needed:
- application/R/joint_qdesn_fixed_backbone_prior_screen.R;
- application/config/joint_qdesn_fixed_backbone_prior_contract_v1.csv;
- bootstrap, action/health script, capacity preflight, launcher;
- application/tests/test_joint_qdesn_fixed_backbone_prior_screen.R;
- this tracked note and ignored local tracker.

Existing inference/design/score modules are reused without edits.
Essential tests cover exact priors and target hashes, counts, no-leakage
geometry, real nested VB, tiny AL and M0 joint/independent calls, original-order
diagnostics, frozen-source failure cases, scoring and shell syntax. No large
smoke campaign precedes the main run.

Pinned R 4.6.0; OMP/OpenBLAS/MKL threads all 1 BEFORE process startup.
Command-line Git commit/push this dedicated branch; clean synchronized Jerez
execution worktree at identical HEAD. No fetch/merge into an active execution
worktree after freeze.

Launch command (Jerez, from dedicated worktree):
bash application/scripts/launch_joint_qdesn_fixed_backbone_prior_screen.sh \
  "$PWD/application/cache/joint_fixed_backbone_prior_20261005" \
  1,2,3,9,10,12,13,14,15,16,17,18,19,20,21

CPU list is conditional on fresh preflight; never reserve occupied physical
siblings. Reject >15, duplicate physical cores, restricted-process conflicts,
busy cores, or <50 GiB free disk. Broad-affinity unrelated jobs cannot be
guaranteed not to migrate; this is an audited shared-capacity allocation, not
an exclusive server reservation. Do not modify their affinities.

Health:
Rscript --vanilla application/scripts/joint_qdesn_fixed_backbone_prior_screen.R \
  health "$PWD/application/cache/joint_fixed_backbone_prior_20261005"

Completion-aware queue, failure-isolated worker receipts, verified DONE
manifests, no overwriting preparation, controller lock, and explicit resume.
Stage failures block subsequent selection/confirmation; no silent substitution.
Completed runtime is excluded under application/cache. Retain draws,
initializers, source/target hashes, score outputs and final PDF, not giant
sampler dumps. No cleanup of previous authoritative evidence in this experiment.

## Checklist

- [x] Audit completed authority, case-specific backbones and prior APIs.
- [x] Separate prior hypothesis from convergence hypothesis.
- [x] Preserve fixed slab and exact M0; avoid architecture reruns.
- [x] Freeze selection, budgets, seeds, quadrature and reporting policy.
- [x] Implement isolated queue, provenance and current-grid scoring.
- [x] Pass essential inference/design/oracle/queue tests; final task rerun required before launch.
- [ ] Commit/push dedicated branch; mirror exact HEAD on Jerez.
- [ ] Pass fresh physical-core and storage preflight.
- [ ] Launch and observe startup; leave detached campaign running.
- [ ] Freeze internal selection; complete fresh confirmation.
- [ ] Review small gains without a perfect scalar-mixing requirement.
- [ ] Produce frozen scientific handoff; coordinator alone integrates.

## Verification Record

Pinned R 4.6.0 with one numerical thread, 2026-10-05:

- test_joint_qdesn_fixed_backbone_prior_screen.R: PASS (real nested warmup,
  all four tiny MCMC dispatches, score intervals, source tamper rejection;
  264 screen chains and up to 72 fresh confirmation chains).
- test_joint_qdesn_recursive_mean_design.R: PASS.
- test_joint_qdesn_recursive_dgp_oracle.R: PASS.
- test_joint_exqdesn_inference_dispatch.R: PASS.
- test_joint_exqdesn_cpu_queue.sh: PASS.
- bash -n application/scripts/launch_joint_qdesn_fixed_backbone_prior_screen.sh: PASS.
- git diff --check: PASS; dedicated lane files only.

Capacity review found 15 free physical cores at the revised allocation and
approximately 228 GiB free disk. The launcher repeats this gate immediately
before preparation. It excludes kernel housekeeping threads from application
reservations while honoring restricted userspace process masks.
