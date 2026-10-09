#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="${1:?runtime root required}"
CPUS="${2:?comma-separated physical CPU ids required}"
MODE="${3:-launch}"
RSCRIPT="${RSCRIPT:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}"
SCRIPT=application/scripts/joint_qdesn_laplace_architecture_article_confirmation.R
CAPACITY=application/scripts/joint_qdesn_laplace_quantile_architecture_capacity.R
BRANCH=work/joint-qdesn-laplace-article-confirmation-20261008
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
source application/scripts/_joint_exqdesn_cpu_queue.sh
IFS=',' read -r -a cpu_array <<< "$CPUS"
(( ${#cpu_array[@]} > 0 && ${#cpu_array[@]} <= 15 )) || exit 2

assert_git() {
  [[ "$(git branch --show-current)" == "$BRANCH" ]]
  [[ -z "$(git status --porcelain)" ]]
  [[ "$(git rev-list --left-right --count HEAD...@{upstream})" == $'0\t0' ]]
}

start_controller() {
  local session="joint_laplace_article_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && bash application/scripts/launch_joint_qdesn_laplace_architecture_article_confirmation.sh '$ROOT' '$CPUS' controller > '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Launched $session with ${#cpu_array[@]} distinct physical-core slots."
}

if [[ "$MODE" == launch ]]; then
  assert_git
  "$RSCRIPT" --vanilla "$CAPACITY" "$CPUS" /tmp/joint_laplace_article_capacity_$$.csv
  [[ ! -e "$ROOT" ]] || { echo "Use resume for an existing root." >&2; exit 2; }
  "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT"
  mv /tmp/joint_laplace_article_capacity_$$.csv "$ROOT/capacity_preflight.csv"
  printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
  start_controller
  exit 0
fi

if [[ "$MODE" == schedule ]]; then
  assert_git
  [[ ! -e "$ROOT" ]] || { echo "Schedule requires a new root." >&2; exit 2; }
  "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT"
  printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
  session="joint_laplace_article_wait_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && while ! '$RSCRIPT' --vanilla '$CAPACITY' '$CPUS' '$ROOT/capacity_preflight.pending.csv' >> '$ROOT/capacity_wait.log' 2>&1; do sleep 120; done; mv '$ROOT/capacity_preflight.pending.csv' '$ROOT/capacity_preflight.csv'; bash application/scripts/launch_joint_qdesn_laplace_architecture_article_confirmation.sh '$ROOT' '$CPUS' controller >> '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Scheduled $session; no model worker starts until the capacity gate passes."
  exit 0
fi

if [[ "$MODE" == resume ]]; then
  assert_git
  "$RSCRIPT" --vanilla "$CAPACITY" "$CPUS" /tmp/joint_laplace_article_resume_$$.csv
elif [[ "$MODE" != controller ]]; then
  exit 2
fi

[[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
exec 9>"$ROOT/controller.lock"
flock -n 9 || { echo "An article-confirmation controller is already active." >&2; exit 2; }
joint_exqdesn_cpu_queue_init "$CPUS" "${#cpu_array[@]}"

run_group() {
  local kind="$1" action="$2" id cpu log
  local -a ids
  mapfile -t ids < <("$RSCRIPT" --vanilla "$SCRIPT" ids "$ROOT" "$kind")
  (( ${#ids[@]} > 0 )) || return 2
  mkdir -p "$ROOT/article/logs"
  for id in "${ids[@]}"; do
    joint_exqdesn_cpu_queue_acquire
    cpu="$QUEUE_CPU"
    log="$ROOT/article/logs/${action}_${id}.log"
    (
      if nice -n 10 taskset -c "$cpu" "$RSCRIPT" --vanilla "$SCRIPT" "$action" "$ROOT" "$id" > "$log" 2>&1; then
        printf '0\n' > "$log.exit"
      else
        printf '1\n' > "$log.exit"
      fi
    ) &
    joint_exqdesn_cpu_queue_register "$!" "$cpu"
  done
  joint_exqdesn_cpu_queue_wait_all
  for id in "${ids[@]}"; do
    [[ "$(cat "$ROOT/article/logs/${action}_${id}.log.exit")" == 0 ]] || {
      echo "Article stage $action failed; later stages blocked and completed work preserved." >&2
      return 1
    }
  done
}

trap 'printf "Controller failed at %s UTC\n" "$(date -u +%FT%T)" > "$ROOT/CONTROLLER_FAILED"' ERR
run_group datasets dataset
run_group warmups warmup
run_group chains chain
run_group cells score
"$RSCRIPT" --vanilla "$SCRIPT" finalize "$ROOT"
rm -f "$ROOT/CONTROLLER_FAILED"
echo "Matched Laplace article-fixture confirmation complete; integration review required."
