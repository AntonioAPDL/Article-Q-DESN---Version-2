#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="${1:?recovery runtime root required}"
SOURCE_ROOT="${2:?completed source runtime root required}"
CPUS="${3:?comma-separated physical CPU ids required}"
RSCRIPT="${RSCRIPT:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}"
MODE="${4:-launch}"
PREDECESSOR_ROOT="${5:-}"
SCRIPT=application/scripts/joint_qdesn_laplace_coupling_recovery.R
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
source application/scripts/_joint_exqdesn_cpu_queue.sh
IFS=',' read -r -a cpu_array <<< "$CPUS"
(( ${#cpu_array[@]} > 0 && ${#cpu_array[@]} <= 15 )) || exit 2
if [[ "$MODE" == launch || "$MODE" == continuation || "$MODE" == resume ]]; then
  [[ "$(git branch --show-current)" == work/joint-qdesn-laplace-coupling-recovery-20261007 ]]
  [[ -z "$(git status --porcelain)" ]]
  [[ "$(git rev-list --left-right --count HEAD...@{upstream})" == $'0\t0' ]]
  [[ "$(hostname -s)" == jerez ]] || { echo "This recovery is assigned to Jerez." >&2; exit 2; }
  receipt=$(mktemp /tmp/joint_coupling_recovery_capacity_XXXXXX.csv)
  "$RSCRIPT" --vanilla application/scripts/joint_qdesn_laplace_coupling_capacity.R "$CPUS" "$receipt"
  if [[ "$MODE" == launch || "$MODE" == continuation ]]; then
    [[ ! -e "$ROOT" ]] || { echo "Use resume for an existing recovery root." >&2; exit 2; }
    "$RSCRIPT" --vanilla "$SCRIPT" validate-source "$ROOT" "$SOURCE_ROOT"
    if [[ "$MODE" == continuation ]]; then
      [[ -n "$PREDECESSOR_ROOT" ]] || { echo "Continuation requires a predecessor runtime." >&2; exit 2; }
      "$RSCRIPT" --vanilla "$SCRIPT" prepare-continuation "$ROOT" "$SOURCE_ROOT" "$PREDECESSOR_ROOT"
    else
      "$RSCRIPT" --vanilla "$SCRIPT" prepare "$ROOT" "$SOURCE_ROOT"
    fi
    mv "$receipt" "$ROOT/capacity_preflight.csv"
    printf '%s\n' "$CPUS" > "$ROOT/cpu_list.txt"
    launch_receipt=$(mktemp /tmp/joint_coupling_recovery_launch_capacity_XXXXXX.csv)
    "$RSCRIPT" --vanilla application/scripts/joint_qdesn_laplace_coupling_capacity.R "$CPUS" "$launch_receipt"
    mv "$launch_receipt" "$ROOT/capacity_launch.csv"
  else
    [[ ! -f "$ROOT/COMPLETE" ]] || { echo "Recovery is already complete." >&2; exit 2; }
    [[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
    mv "$receipt" "$ROOT/capacity_resume_$(date -u +%Y%m%d_%H%M%S).csv"
  fi
  session="joint_coupling_recovery_$(date -u +%Y%m%d_%H%M%S)"
  tmux new-session -d -s "$session" \
    "cd '$PWD' && taskset -c '$CPUS' bash application/scripts/launch_joint_qdesn_laplace_coupling_recovery.sh '$ROOT' '$SOURCE_ROOT' '$CPUS' controller >> '$ROOT/pipeline.log' 2>&1"
  printf '%s\n' "$session" > "$ROOT/tmux_session.txt"
  echo "Launched $session with ${#cpu_array[@]} physical-core slots."
  exit 0
fi
[[ "$MODE" == controller ]]
[[ "$(cat "$ROOT/cpu_list.txt")" == "$CPUS" ]]
exec 9>"$ROOT/controller.lock"
flock -n 9 || { echo "A recovery controller is already active." >&2; exit 2; }
[[ ! -f "$ROOT/COMPLETE" ]] || exit 0
joint_exqdesn_cpu_queue_init "$CPUS" "${#cpu_array[@]}"
run_group() {
  local stage="$1" kind="$2" action="$3" id cpu log ids_file
  local -a ids
  ids_file=$(mktemp /tmp/joint_coupling_recovery_ids_XXXXXX)
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
      echo "Stage $stage/$action failed; later stages blocked." >&2
      return 1
    }
  done
}
trap 'printf "Controller failed at %s UTC\n" "$(date -u +%FT%T)" > "$ROOT/CONTROLLER_FAILED"' ERR
if [[ ! -f "$ROOT/screen/SELECTION_FROZEN" ]]; then
  run_group screen chains chain
  run_group screen cells score
  "$RSCRIPT" --vanilla "$SCRIPT" adjudicate "$ROOT"
fi
for action in dataset calibrate warmup chain score; do
  case "$action" in
    dataset|calibrate) kind=datasets ;;
    warmup) kind=warmups ;;
    chain) kind=chains ;;
    score) kind=cells ;;
  esac
  run_group confirmation "$kind" "$action"
done
"$RSCRIPT" --vanilla "$SCRIPT" finalize "$ROOT"
rm -f "$ROOT/CONTROLLER_FAILED"
echo "Recovery complete; scientific integration review required. No article publication."
