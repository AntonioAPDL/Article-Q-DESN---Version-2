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

## R3 closeout and H1 contract

R3 launched on 2026-11-21 at 22:58 EST from commit
`e6d7dcb54bc90266e1219f0ff43cdd777907c7cf` on the same reviewed 25-core
allocation. Its capacity receipt recorded 493 GiB available memory and 346 GiB
free durable storage.

R3 closed with 4,608/4,608 workers complete, zero failures, 4,608 finite
scores, zero protected rows, and pipeline exit zero. Its eight-entry manifest
verifies completely. Three warning rows are from the known 1,500-state
persistent-tail sentinel at the canonical seed; they are finite, reproducible,
poor-scoring, and capacity-bound. No supported architecture warned.

The finalizer aggregated 512 architectures across all three selector fixtures
and three frozen reservoir seeds. It retained exactly 50 backend-supported
architectures per scenario, recorded 67 capacity-bound architectures, and
prepared 4,400 H1 workers across the 11-point `tau0` grid.

Every supported seed-aggregated winner improves the authoritative anchor mean,
by 3.0% to 21.4%. Five improve all nine matched fixture/seed comparisons; the
remaining three improve seven or eight, with worst reversals below 1%. Every
global winner uses 20-48 retained states and is supported by the current RHS
backend. No capacity-bound architecture wins.

Frozen hashes:

- `r3_scores.csv`: `8e8be643da4e8b3e895a99f083ebf08acdeb5bd0f12786d51ebd6b0c381bdc56`
- `r3_seed_robustness_aggregate.csv`: `c56a38cd22d5250270f587a7bc67c3508645b7425dce506ec0a083f1125cab59`
- `r3_rhs_frontier.csv`: `2935806165bf3c32543a9f4702a497a2f189874835b3e40328da6b6e15c1bfc7`
- `h1_worker_plan.csv`: `ec8b662e77c61c7054a6c3d5653f8eab0f8c5adc38196cc0018a2237858537ed`
- `r3_manifest.csv`: `e3ee7668a9110c70dac98951478cefb44b2d6a620cace0de3a8abfae15624fd4`

Current decision: `R3_COMPLETE_READY_FOR_H1_REVIEW`. H1 may launch only from a
clean, pushed task branch after exact hash and capacity checks. It must use the
frozen 11-point `tau0` grid for all 400 architectures on selector fixture 1
and stop after preparing H2.

## H1 closeout and H2 contract

H1 completed all 4,400 normal-RHS VB workers with zero failures, zero
warnings, finite scores throughout, and zero protected rows. Of the fits,
4,397 met the ordinary convergence rule and three reached the frozen maximum
iteration count with finite, nonpathological outputs. These three are retained
for replicate review rather than silently deleted.

The H1 finalizer retained exactly two `tau0` values for each of the 400
scenario-architecture pairs, producing 800 retained pairs and a balanced H2
plan of 2,400 workers across three selector fixtures. The best H1 value lies
at one of the two grid boundaries for 262/400 architectures. This is evidence
for the predeclared local H3 refinement after cross-fixture confirmation, not
permission to expand or rerank H1 adaptively.

A provenance audit found that the original H1/H2 finalizers returned their
stage decision to standard output but did not manifest it. Commit `55ff614b`
adds durable, manifested decision receipts to both stages. The H1 finalizer
was then replayed deterministically without refitting any worker. The H2 plan
hash remained identical, proving that this was a provenance-only correction.

Frozen H1 hashes after that replay:

- `h1_scores.csv`: `65647cc4347cd6d26ef1ff6ee31c1aa268d162f14aaff762fa7f7cefa9d60f76`
- `h1_aggregate.csv`: `4806f8fbfa4d1eff74511493301c0dbf44f86508d36ec601a6ee2a728706d122`
- `h1_retained_tau_pairs.csv`: `db2fd1a66f12f52f4603e0161fbeb9aa263cc4b66dc3cd02e9f8118569858b91`
- `h2_worker_plan.csv`: `1055285daa9962445de75fedf6dffd9eb9d7e6331b5bbf3ed9c5a1aebf5b4644`
- `h1_decision.csv`: `3d9b2eacaa65c759fb03d631a3a025146d413ceac6b7c9797282a3f086f5ba4f`
- `h1_manifest.csv`: `51530716bcf197eb8a9a48347f0a5647fd1729567c18c8a3e7e91f8a94b9ebbe`

Current decision: `H1_COMPLETE_READY_FOR_H2_REVIEW`. H2 may launch only after
the seven-entry manifest, exact H2 plan hash, clean pushed source, and fresh
capacity receipt pass. H2 evaluates the two retained values for every
architecture on all three selector fixtures. Its finalizer may prepare H3 but
cannot launch it.

## H2 closeout and H3 contract

H2 launched from clean pushed commit `7cbcb7e6` on 25 distinct physical
Muscat cores, excluding the physical core occupied by an unrelated PriceFM
verification process. The receipt recorded 492 GiB available memory and 345
GiB free durable storage.

H2 closed with 2,400/2,400 complete workers, zero failures, zero warnings,
finite score and runtime fields throughout, zero protected rows, and pipeline
exit zero. Six fits reached the frozen 400-iteration limit; all had finite
scores and final deltas between `1.56e-4` and `2.70e-4`. They remain
review-level evidence rather than being deleted or retried.

The finalizer produced 800 cross-fixture architecture-`tau0` aggregates,
retained exactly 20 pairs per scenario (160 total), preserved all eight
authoritative architecture anchors, and prepared 960 H3 workers. Each H3 pair
evaluates the two predeclared log-scale neighbors on all three selector
fixtures. Among the 400 architecture-level H2 optima, 245 lie at a frozen H1
grid boundary. H3 therefore answers a real boundary-resolution question, but
does so only through the rule frozen before H1.

Every H2 scenario winner improves its matched best authoritative anchor in
all three fixtures. Mean improvements range from 0.58% to 11.49%. This remains
internal selection evidence and cannot enter the article or protected-model
comparison.

Frozen H2 hashes:

- `h2_scores.csv`: `eddfe65cda6396af64944221678f5ad50b05d900267eed5118a91be04a501251`
- `h2_aggregate.csv`: `c13afc3e7f14fb1de7a7e01ea27d130df9d98afb82fcd1b7cdd74097eb282fc9`
- `h2_refinement_shortlist.csv`: `3823d9fa74c755b9b2744dd4200a0d33330983fa9cd17ab21b2348aba9896721`
- `h3_worker_plan.csv`: `39f64e374dde8f3945f6491560f64651147e094c01060d71d31e0b50a90b9e46`
- `h2_decision.csv`: `240c8c3f0db04ee2c0c562032777fcdac33ecbf5d878a3323871d32f17ccbd44`
- `h2_manifest.csv`: `07c3b08884d3b874bd0444fe3c340749dcb584ad3b6318561178795bd89a351f`

Current decision: `H2_COMPLETE_READY_FOR_H3_REVIEW`. H3 may launch only from a
clean pushed branch after exact plan and manifest verification plus a fresh
capacity audit. Its finalizer must combine H2 and H3, select exactly 20
architecture-`tau0` pairs per scenario, emit the median-AL worker plan, and
stop. It cannot start quantile fitting.

The ignored authoritative planning tracker is:

`local_trackers/joint_qdesn_stronger_window_richer_screen_plan_20261121/JOINT_QDESN_STRONGER_WINDOW_RICHER_SCREEN_ULTIMATE_PLAN_20261121.md`

Runtime remains ignored under:

`application/cache/joint_qdesn_stronger_window_richer_screen_20261121/`

No manuscript, table, figure, Overleaf branch, `main`, historical runtime, or
unrelated scientific lane is modified by this implementation.
