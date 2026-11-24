# Persistent-heavy-tail targeted DESN and RHS screening

Date: 2026-11-24

Branch: `work/joint-qdesn-persistent-tail-targeted-screen-20261124`

Base: freshly fetched `origin/main` at `ce54c280153723f97a2ad46dce33cedefbd8a505`

Execution host: Jerez only

Status: prepared and tested; no production worker launched

## Scientific reason

The corrected 1,300-row design improves contract-adjusted fit RMSE over the
previous 500-row authority in every scenario. Persistent heavy tail remains the
clear exception in absolute quality: its four-model native-window mean fit RMSE
is 0.268, and all four models lie between 0.258 and 0.288. This is therefore a
scenario-wide representation problem rather than a single joint/independent or
AL/exAL anomaly.

The earlier stronger-window campaign already searched 4,096 architectures per
scenario, depths 1--8, response lags through 360 and state budgets through
2,000. Its high-capacity sentinels were noncompetitive and supported winners
used only 20--48 retained states. This follow-up does not increase width. It
densifies a single difficult scenario around the corrected authority, extends
the requested spectral-radius boundary to 1.20, and searches the RHS global
scale more finely.

## Frozen scientific contract

- Scenario: `persistent_heavy_tail` only.
- Development design: 500 reservoir washout rows, 1,000 internal training
  rows, and 300 internal recursive-calibration rows.
- Protected evaluation: 1,000 rows, never loaded by selection fixtures.
- Origins: teacher forcing between origins; recursive central-action feedback
  within each 30-step origin.
- Readout: intercept plus all reservoir states; no raw input columns.
- Selection score: realized finite-grid aCRPS on internal calibration.
- Oracle quantile errors remain diagnostics and cannot select a candidate.
- Any positive mean improvement may advance if finite-state, saturation,
  provenance and protected-data gates pass.
- The current corrected article specification is retained as an exact anchor
  at every funnel stage.

## Targeted architecture space

The unchanged axes are depth 1--8, response lags 1--360, widths/shapes,
leakage 0.005--0.995, input scale, input sparsity and recurrent expected
degree. Supported state budgets stop at 600.

The spectral-radius range is 0.10--1.20. Exactly 512 of 1,536 R1a candidates
belong to the explicit `rho >= 1` allocation. Supercritical targets are an
opt-in experimental contract: the ordinary generator still rejects
`rho >= 1`; only labeled candidates may request at most 1.20 and bypass the
leaky-radius contraction that would otherwise silently undo the experiment.
Tanh states remain bounded, but echo-state stability is not assumed. Finite
scores and maximum state saturation of 0.25 are advancement gates.

## Funnel and exact workload

| Stage | Work | Expected jobs | Stop condition |
|---|---|---:|---|
| R1a | 1,536 ridge candidates, one fixture, three origins | 1,536 | retain 384, including 96 supercritical |
| R1b | 384 candidates, three fixtures, all ten origins | 1,152 | retain 32, including 8 supercritical |
| R2 | 32 candidates, three fixtures and three reservoir seeds | 288 | retain 24, including 6 supercritical |
| H1 | 24 architectures x 23 half-decade `tau0` values x 3 fixtures | 1,656 | retain 12 pairs |
| H2 | six new eighth-decade neighbors x 12 pairs x 3 fixtures | at most 216 | retain 8 pairs |
| M1 | eight architecture-scale pairs x three fixtures, median AL VB | 24 | stop for scientific review |

The coarse `tau0` grid spans `1e-8` through `1e3`. H2 evaluates new
log10 offsets `+-0.125`, `+-0.25`, and `+-0.375` around H1 winners. No
seven-quantile VB, exAL VB, joint fit or MCMC is authorized by this lane.
Those expensive stages require evidence that median AL improves the authority.

## Jerez execution boundary

The launcher fails closed unless:

- hostname is exactly `jerez.be.ucsc.edu`;
- pinned R is 4.6.0;
- the task branch is clean and exactly synchronized with its upstream;
- no competing JOINT, GloFAS or PriceFM `Rscript` is active;
- the supplied CPU IDs represent distinct physical cores;
- at most 30 physical workers are requested;
- `/data` has at least 80 GiB free and available RAM is at least 128 GiB;
- the preparation manifest, fixture hashes and protected-row gates verify.

The 2026-11-24 read-only audit observed 32 physical cores, 489 GiB available
RAM, 106 GiB free under `/data`, and no active model `Rscript`. Capacity must be
remeasured at launch. Thirty workers reserve two physical cores for the host.
Worker artifacts contain summaries, calibration details, traces and compact
median initializers only; full state matrices are not persisted.

## Jerez preparation and launch sequence

After the branch is pushed, create a dedicated Jerez worktree from the exact
remote branch. Run the focused test, then prepare the production runtime on
Jerez so fixture paths are host-local:

```bash
R_BIN=/data/jaguir26/local/opt/R/4.6.0/bin/Rscript
ROOT=$PWD/application/cache/joint_qdesn_persistent_tail_targeted_screen_20261124
$R_BIN application/tests/test_joint_qdesn_persistent_tail_targeted_screen.R
$R_BIN application/scripts/prepare_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
$R_BIN application/scripts/check_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
```

At each reviewed stage, derive one online logical representative from each
physical core, retain the first 30, and launch in a named tmux session:

```bash
CPU_LIST=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | awk -F, '$1 !~ /^#/ && $4=="Y" {k=$2":"$3; if (!seen[k]++) print $1}' | head -30 | paste -sd, -)
tmux new-session -d -s joint_pht_r1a_20261124 \
  "cd '$PWD' && CPU_LIST='$CPU_LIST' R_BIN='$R_BIN' application/scripts/launch_joint_qdesn_persistent_tail_targeted_stage.sh '$ROOT' r1a 2>&1 | tee '$ROOT/r1a_pipeline.log'"
```

After workers close, run the checker and the stage finalizer. Inspect its
manifest and decision before separately launching the next stage. Repeat for
`r1b`, `r2`, `h1`, `h2`, and `m1`. No finalizer launches its successor.

## Decision after M1

Continue to seven-grid AL/exAL VB only when the selected median-AL pair has a
finite lower mean internal score than the exact authority and does not owe the
improvement to one fixture, one reservoir seed, state saturation, or a failed
manifest. Otherwise retain the corrected authority and close this experiment.
Any later seven-grid result must still receive protected VB and MCMC
confirmation before article promotion.
