#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="${1:?runtime root required}"
CPUS="${2:?comma-separated physical CPU ids required}"
MODE="${3:-launch}"
SOURCE_ROOT="${4:-/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_expanded_screen_20260925/application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925}"
RSCRIPT="${RSCRIPT:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}"
SCRIPT=application/scripts/joint_qdesn_laplace_quantile_architecture.R
CAPACITY=application/scripts/joint_qdesn_laplace_quantile_architecture_capacity.R
BRANCH=work/joint-qdesn-laplace-quantile-architecture-20261008
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
source application/scripts/_joint_exqdesn_cpu_queue.sh
IFS=',' read -r -a cpu_array <<< "$CPUS"
(( ${#cpu_array[@]} > 0 && ${#cpu_array[@]} <= 15 )) || exit 2
assert_git() {
  [[ "$(git branch --show-current)" == "$BRANCH" ]]
  [[ -z "$(git status --porcelain)" ]]
  [[ "$(git rev-list --left-right --count HEAD...@{upstream})" == $'0\t0' ]]
}
start_controller() {
  local session="joint_laplace_arch_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && bash application/scripts/launch_joint_qdesn_laplace_quantile_architecture.sh '$ROOT' '$CPUS' controller '$SOURCE_ROOT' > '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Launched $session with ${#cpu_array[@]} distinct physical-core slots."
}
if [[ "$MODE" == launch ]]; then
  assert_git
  "$RSCRIPT" --vanilla "$CAPACITY" "$CPUS" /tmp/joint_arch_capacity_$$.csv
  [[ ! -e "$ROOT" ]] || { echo "Use resume for an existing root." >&2; exit 2; }
  "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT" "$SOURCE_ROOT"
  mv /tmp/joint_arch_capacity_$$.csv "$ROOT/capacity_preflight.csv"
  printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
  start_controller
  exit 0
fi
if [[ "$MODE" == schedule ]]; then
  assert_git
  [[ ! -e "$ROOT" ]] || { echo "Schedule requires a new root." >&2; exit 2; }
  "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT" "$SOURCE_ROOT"
  printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
  session="joint_laplace_arch_wait_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && while ! '$RSCRIPT' --vanilla '$CAPACITY' '$CPUS' '$ROOT/capacity_preflight.pending.csv' >> '$ROOT/capacity_wait.log' 2>&1; do sleep 120; done; mv '$ROOT/capacity_preflight.pending.csv' '$ROOT/capacity_preflight.csv'; bash application/scripts/launch_joint_qdesn_laplace_quantile_architecture.sh '$ROOT' '$CPUS' controller '$SOURCE_ROOT' >> '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Scheduled $session; no model worker starts until the capacity gate passes."
  exit 0
fi
if [[ "$MODE" == resume ]]; then
  assert_git
  "$RSCRIPT" --vanilla "$CAPACITY" "$CPUS" /tmp/joint_arch_resume_$$.csv
elif [[ "$MODE" != controller ]]; then
  exit 2
fi
[[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
exec 9>"$ROOT/controller.lock"
flock -n 9 || { echo "An architecture controller is already active." >&2; exit 2; }
joint_exqdesn_cpu_queue_init "$CPUS" "${#cpu_array[@]}"
run_group() {
  local stage="$1" kind="$2" action="$3" id cpu log
  local -a ids
  mapfile -t ids < <("$RSCRIPT" --vanilla "$SCRIPT" ids "$ROOT" "$stage" "$kind")
  (( ${#ids[@]} > 0 )) || return 2
  mkdir -p "$ROOT/$stage/logs"
  for id in "${ids[@]}"; do
    joint_exqdesn_cpu_queue_acquire; cpu="$QUEUE_CPU"; log="$ROOT/$stage/logs/${action}_${id}.log"
    (
      if nice -n 10 taskset -c "$cpu" "$RSCRIPT" --vanilla "$SCRIPT" "$action" "$ROOT" "$stage" "$id" > "$log" 2>&1; then
        printf '0\n' > "$log.exit"
      else
        printf '1\n' > "$log.exit"
      fi
    ) &
    joint_exqdesn_cpu_queue_register "$!" "$cpu"
  done
  joint_exqdesn_cpu_queue_wait_all
  for id in "${ids[@]}"; do
    [[ "$(cat "$ROOT/$stage/logs/${action}_${id}.log.exit")" == 0 ]] || {
      echo "Stage $stage/$action failed; later stages blocked and completed work preserved." >&2; return 1;
    }
  done
}
trap 'printf "Controller failed at %s UTC\n" "$(date -u +%FT%T)" > "$ROOT/CONTROLLER_FAILED"' ERR
run_group vb datasets vb
"$RSCRIPT" --vanilla "$SCRIPT" select-vb "$ROOT"
if [[ ! -f "$ROOT/screen/plan_manifest.csv" ]]; then
  printf 'COMPLETE_NO_QUANTILE_VB_ARCHITECTURE_CHALLENGER\n' > "$ROOT/COMPLETE"
  rm -f "$ROOT/CONTROLLER_FAILED"; exit 0
fi
for action in dataset warmup chain score; do
  kind="${action}s"; [[ "$action" == score ]] && kind=cells
  run_group screen "$kind" "$action"
done
"$RSCRIPT" --vanilla "$SCRIPT" select-mcmc "$ROOT"
if [[ ! -f "$ROOT/confirmation/plan_manifest.csv" ]]; then
  "$RSCRIPT" --vanilla "$SCRIPT" finalize "$ROOT"
  rm -f "$ROOT/CONTROLLER_FAILED"; exit 0
fi
for action in dataset warmup chain score; do
  kind="${action}s"; [[ "$action" == score ]] && kind=cells
  run_group confirmation "$kind" "$action"
done
"$RSCRIPT" --vanilla "$SCRIPT" finalize "$ROOT"
rm -f "$ROOT/CONTROLLER_FAILED"
echo "Campaign complete; scientific integration review required. No article publication performed."
