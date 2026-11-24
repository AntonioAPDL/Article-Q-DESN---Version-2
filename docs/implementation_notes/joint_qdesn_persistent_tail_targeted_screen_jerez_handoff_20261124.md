# Jerez handoff: persistent-heavy-tail targeted screen

## Source identity

- Repository: `Article-Q-DESN---Version-2`
- Branch: `work/joint-qdesn-persistent-tail-targeted-screen-20261124`
- Base authority: `origin/main` at
  `ce54c280153723f97a2ad46dce33cedefbd8a505`
- Production runtime tag:
  `joint_qdesn_persistent_tail_targeted_screen_20261124`
- Production host: `jerez.be.ucsc.edu`
- Pinned R: `/data/jaguir26/local/opt/R/4.6.0/bin/Rscript`

The exact task-branch HEAD must be obtained from a fresh command-line fetch
before creating the Jerez worktree. Do not use a browser merge, GitHub CLI,
Overleaf synchronization, or `main` for execution.

## Create the isolated Jerez worktree

From the Jerez authoritative clone:

```bash
git fetch origin --prune
git rev-parse origin/work/joint-qdesn-persistent-tail-targeted-screen-20261124
git worktree add --track -b work/joint-qdesn-persistent-tail-targeted-screen-20261124 \
  /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_screen_20261124 \
  origin/work/joint-qdesn-persistent-tail-targeted-screen-20261124
cd /data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_persistent_tail_screen_20261124
```

If that local branch already exists, stop and audit its worktree and upstream;
do not reset or overwrite it.

## Mandatory preflight and preparation

```bash
R_BIN=/data/jaguir26/local/opt/R/4.6.0/bin/Rscript
ROOT=$PWD/application/cache/joint_qdesn_persistent_tail_targeted_screen_20261124

git status --short --branch
git rev-list --left-right --count '@{upstream}...HEAD'
$R_BIN application/tests/test_joint_qdesn_persistent_tail_targeted_screen.R
$R_BIN application/scripts/prepare_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
$R_BIN application/scripts/check_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
```

Expected preparation cardinalities are 1,536 R1a workers, 1,152 R1b workers,
288 R2 workers, 1,656 H1 workers, at most 216 H2 workers and 24 median-AL
workers. Preparation must report zero protected rows and must not create a
running worker.

## Capacity selection

Remeasure capacity immediately before every stage. The launcher requires at
least 80 GiB free under `/data`, 128 GiB available RAM, no competing model
`Rscript`, and a clean branch exactly synchronized with its upstream.

```bash
CPU_LIST=$(lscpu -p=CPU,CORE,SOCKET,ONLINE | \
  awk -F, '$1 !~ /^#/ && $4=="Y" {k=$2":"$3; if (!seen[k]++) print $1}' | \
  head -30 | paste -sd, -)
printf 'CPU_LIST=%s\n' "$CPU_LIST"
```

The list must contain 30 distinct physical cores. Fewer may be used if Jerez
capacity changes; more than 30 are prohibited.

## Stage execution

Launch one stage only, beginning with R1a:

```bash
STAGE=r1a
SESSION=joint_pht_${STAGE}_20261124
tmux new-session -d -s "$SESSION" \
  "cd '$PWD' && CPU_LIST='$CPU_LIST' R_BIN='$R_BIN' \
   application/scripts/launch_joint_qdesn_persistent_tail_targeted_stage.sh \
   '$ROOT' '$STAGE' 2>&1 | tee '$ROOT/${STAGE}_pipeline.log'"
```

After completion:

```bash
$R_BIN application/scripts/check_joint_qdesn_persistent_tail_targeted_screen.R "$ROOT"
$R_BIN application/scripts/finalize_joint_qdesn_persistent_tail_targeted_stage.R "$ROOT" "$STAGE"
```

Verify the stage manifest and decision before launching the next stage. The
ordered stages are `r1a`, `r1b`, `r2`, `h1`, `h2`, and `m1`. Finalizers never
launch successors. Resume uses the same command; completed workers are
manifest-checked and skipped.

## Required stop

Stop after M1. Report the selected and authority median-AL internal scores,
fixture variability, selected architecture, `rho`, `tau0`, saturation,
warnings, manifests, storage and runtime. Do not launch seven-grid AL/exAL VB,
joint fitting, MCMC, protected scoring, article regeneration, integration or
Overleaf publication from this handoff.

The ignored runtime must remain on Jerez until a frozen scientific closeout is
reviewed. Only reproducibility code and metadata belong in Git.
