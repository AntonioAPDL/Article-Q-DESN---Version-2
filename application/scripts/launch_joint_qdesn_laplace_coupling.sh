#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="${1:?runtime root required}"
CPUS="${2:?comma-separated physical CPU ids required}"
RSCRIPT="${RSCRIPT:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}"
MODE="${3:-launch}"
SCRIPT=application/scripts/joint_qdesn_laplace_coupling.R
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
source application/scripts/_joint_exqdesn_cpu_queue.sh
IFS=',' read -r -a cpu_array <<< "$CPUS"
(( ${#cpu_array[@]} > 0 && ${#cpu_array[@]} <= 15 )) || exit 2
if [[ "$MODE" == launch || "$MODE" == resume ]]; then
  [[ "$(git branch --show-current)" == work/joint-qdesn-laplace-coupling-20261006 ]]
  [[ -z "$(git status --porcelain)" ]]
  [[ "$(git rev-list --left-right --count HEAD...@{upstream})" == $'0\t0' ]]
  [[ "$(hostname -s)" == jerez ]] || { echo "This experiment is assigned to Jerez." >&2; exit 2; }
  receipt=$(mktemp /tmp/joint_coupling_capacity_XXXXXX.csv)
  "$RSCRIPT" --vanilla application/scripts/joint_qdesn_laplace_coupling_capacity.R "$CPUS" "$receipt"
  if [[ "$MODE" == launch ]]; then
    [[ ! -e "$ROOT" ]] || { echo "Use resume for an existing root." >&2; exit 2; }
    "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT"
    mv "$receipt" "$ROOT/capacity_preflight.csv"
    printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
  else
    [[ ! -f "$ROOT/COMPLETE" ]] || { echo "Run is already complete; no relaunch." >&2; exit 2; }
    [[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
    mv "$receipt" "$ROOT/capacity_resume_$(date -u +%Y%m%d_%H%M%S).csv"
  fi
  session="joint_coupling_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && bash application/scripts/launch_joint_qdesn_laplace_coupling.sh '$ROOT' '$CPUS' controller >> '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Launched $session with ${#cpu_array[@]} physical-core slots."
  exit 0
fi
[[ "$MODE" == controller ]]
[[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
exec 9>"$ROOT/controller.lock"
flock -n 9 || { echo "An experiment controller is already active." >&2; exit 2; }
[[ ! -f "$ROOT/COMPLETE" ]] || exit 0
joint_exqdesn_cpu_queue_init "$CPUS" "${#cpu_array[@]}"
run_group() {
  local stage="$1" kind="$2" action="$3" id cpu log ids_file
  local -a ids
  ids_file=$(mktemp /tmp/joint_coupling_ids_XXXXXX)
  "$RSCRIPT" --vanilla "$SCRIPT" ids "$ROOT" "$stage" "$kind" "$action" > "$ids_file"
  mapfile -t ids < "$ids_file"
  rm -f "$ids_file"
  (( ${#ids[@]} > 0 )) || return 0
  mkdir -p "$ROOT/$stage/logs"
  for id in "${ids[@]}"; do
    joint_exqdesn_cpu_queue_acquire
    cpu="$QUEUE_CPU"; log="$ROOT/$stage/logs/${action}_${id}.log"
    (
      if taskset -c "$cpu" "$RSCRIPT" --vanilla "$SCRIPT" "$action" "$ROOT" "$stage" "$id" > "$log" 2>&1; then
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
      echo "Stage $stage/$action failed; later stages blocked and completed work preserved." >&2
      return 1
    }
  done
}
trap 'printf "Controller failed at %s UTC\n" "$(date -u +%FT%T)" > "$ROOT/CONTROLLER_FAILED"' ERR
for stage in screen confirmation; do
  run_group "$stage" datasets dataset
  run_group "$stage" datasets calibrate
  run_group "$stage" warmups warmup
  run_group "$stage" chains chain
  run_group "$stage" cells score
  if [[ "$stage" == screen && ! -f "$ROOT/screen/SELECTION_FROZEN" ]]; then
    "$RSCRIPT" --vanilla "$SCRIPT" select "$ROOT"
  fi
done
"$RSCRIPT" --vanilla "$SCRIPT" finalize "$ROOT"
rm -f "$ROOT/CONTROLLER_FAILED"
echo "Campaign complete; scientific integration review required. No article publication."
