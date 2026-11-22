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

The six-worker benchmark completed with six successes and no failures. Its
largest 2,000-state worker used about 0.52 GiB peak RSS and 19.6 seconds. The
frozen R1a plan projects about 33 CPU-hours, 1.32 wall-hours at 25 workers, and
1.98 conservative wall-hours. After that review, R1a was launched on 25
distinct physical Muscat cores from code commit `d90645a8`, at nice priority
and one numerical thread per worker. Its finalizer may prepare R1b but cannot
launch it.

Every later stage requires an exact stage confirmation token and an explicit
physical CPU list. Finalizers may prepare the next plan but never launch it.

## R1a closeout and R1b contract

R1a closed on 2026-11-21 at 07:44 EST with 32,768/32,768 workers complete,
zero failures, 32,768 finite scores, and zero protected rows. The finalizer
retained exactly 1,024 candidates per scenario, including all 16 anchors and
exactly 64 high-capacity sentinels per scenario. The five-file R1a manifest
verified completely.

Frozen hashes:

- `r1a_manifest.csv`: `e0417e076eb4c4793bbd6c3bbb26d9af0116a0bbdaff40166e6306d5e704266b`
- `r1a_scores.csv`: `559526528353d196b6966abaef3226fc5efb4edd7c5dd82895edd23122b9e355`
- `r1a_frontier.csv`: `6e2ec82e8c2b50999882e2ecc42cc4526bf9a22e4afa11a53d33803ee5582eb4`
- `r1b_worker_plan.csv`: `291c4a8aef40a8cb584f2ecbec202d175f41abf14578d97ab09999d7ea711278`

The best three-origin internal score improved over exact parity in every
scenario, from 7.2% to 28.7%. This is screening evidence only. No R1a score is
eligible for article promotion, and no protected realization was inspected.
The early winners use 20-150 retained states; no 1,500/2,000-state sentinel is
a scenario winner. The sentinel quota remains frozen through R1b so this
observation does not create an adaptive early deletion.

R1b evaluates the frozen 1,024 candidates per scenario on origins
`1,3,5,7,9,10`, giving 8,192 workers and 180 recursively forecast rows per
worker. Actual R1a timing projects 0.94 wall-hours at 25 workers, with a 1.27
hour conservative allowance. R1b must stop after preparing the 256-per-scenario
R2 plan. R2 cannot launch without a new score, manifest, runtime, warning, and
capacity audit.

R1b launched on 2026-11-21 at 20:58 EST from commit
`8ed0b063edc889486ea62758c577b066c7f5727d` on 25 distinct physical Muscat
cores, with one numerical thread per worker and reduced scheduling priority.
The launch receipt recorded 493 GiB available memory and 347 GiB free durable
storage.

R1b closed at 21:26 EST with 8,192/8,192 workers complete, zero failures,
8,192 finite scores, zero protected rows, and pipeline exit zero. The final
seven-entry manifest verifies completely. Two high-capacity sentinel workers
recorded an eigensolver warning; both produced complete finite outputs and are
noncompetitive, so the warnings are review-level rather than failure-level.

The finalizer retained exactly 256 candidates per scenario, including all
authoritative anchors and exactly 32 high-capacity sentinels per scenario. It
prepared a balanced R2 plan with 6,144 workers: 256 candidates x 3 selector
fixtures x 8 scenarios, using all ten internal origins. The R2 plan SHA-256 is
`7922d49e0f76ed209556dc6ba74a7aaa9b7175f20e8c78d36644fbcf0970c79d`.
The R1b manifest SHA-256 is
`37f846d77751d956833f61f3e86a69de1b4fdfcd87c80b27574e71c1c10f02bd`.

Every R1b numerical minimum improves on its matched authoritative architecture
anchor on the internal six-origin target, by 3.3% to 18.1%. Ranking stability
between R1a and R1b is nevertheless scenario-dependent: common-candidate
Spearman correlations range from 0.05 to 0.76 and top-20 overlap ranges from
zero to four. R2 is therefore required to measure full-origin,
three-replicate stability before freezing any architecture. These internal
scores are not article evidence and do not authorize protected evaluation.

The best R1b retained-state budgets are 20-48. No 1,500/2,000-state sentinel
wins. Their frozen quota remains in R2 as capacity evidence, but the campaign
does not expand the expensive inference backend unless later reproducible
evidence supports it.

Current decision: `R1B_COMPLETE_READY_FOR_R2_REVIEW`. R2 may launch only from
a clean, pushed branch after focused tests, exact manifest and plan-hash
verification, and a fresh CPU/memory/storage audit. Its finalizer may prepare
R3 but cannot launch it.

## R2 closeout and R3 contract

R2 launched on 2026-11-21 at 22:26 EST from commit
`9125fc2f227e8a4587468f2edb298d36af340bbf` on 25 distinct physical Muscat
cores, excluding unrelated busy cores 4 and 8. Its capacity receipt recorded
493 GiB available memory and 346 GiB free durable storage.

R2 closed with 6,144/6,144 workers complete, zero failures, 6,144 finite
scores, zero protected rows, and pipeline exit zero. Its seven-entry manifest
verifies completely. Six warning rows belong to exactly two high-capacity
sentinels across three selector fixtures each. Both candidates are finite,
complete, and noncompetitive; no ordinary-capacity worker warned.

The finalizer produced 2,048 cross-fixture aggregates and retained exactly 64
candidates per scenario, including the authoritative anchor and exactly eight
1,500/2,000-state sentinels per scenario. The R3 plan has 4,608 workers: 64
architectures x 3 fixtures x 3 frozen reservoir seeds x 8 scenarios.

Every scenario's numerical R2 minimum improves on the matched authoritative
anchor in mean internal aCRPS, by 2.6% to 14.1%. Seven minima improve in all
three fixtures. Gaussian mixture improves in two of three, with one fixture
0.7% worse and a 6.5% lower mean. R1b-to-R2 rank correlations remain only
0.19-0.50, so seed robustness is necessary before architecture freezing.

Frozen hashes:

- `r2_scores.csv`: `d825905c82ffbe9ed9f44d057cac7bc28e1c4492e742a00c4535dd12c1e698c8`
- `r2_frontier.csv`: `1f5810555ea6d66f8909313fadcfcc8ff30e01013e8ec0f87143b0050408a0a8`
- `r3_worker_plan.csv`: `e321c45f7fe75f5619e8a82102d3724159a8c91163edb9c65448ee848634ced1`
- `r2_manifest.csv`: `43c1d98f829555ccfbf9f5165a0561508ac70f949cf2dd20dfc9040a438b7c8e`

Current decision: `R2_COMPLETE_READY_FOR_R3_REVIEW`. R3 may launch only from a
clean, pushed task branch after exact hash and capacity checks. Its finalizer
may prepare H1 but cannot launch it. R3 aggregates across the predeclared seed
set and must never promote the empirically best reservoir seed.

The ignored authoritative planning tracker is:

`local_trackers/joint_qdesn_stronger_window_richer_screen_plan_20261121/JOINT_QDESN_STRONGER_WINDOW_RICHER_SCREEN_ULTIMATE_PLAN_20261121.md`

Runtime remains ignored under:

`application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`

No manuscript, table, figure, Overleaf branch, `main`, historical runtime, or
unrelated scientific lane is modified by this implementation.
