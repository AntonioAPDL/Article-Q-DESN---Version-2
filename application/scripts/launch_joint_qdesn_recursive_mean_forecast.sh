#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/_joint_exqdesn_cpu_queue.sh"

RSCRIPT="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"
ROOT="${JOINT_RECURSIVE_MEAN_RUNTIME_ROOT:-${REPO_ROOT}/application/cache/joint_qdesn_recursive_mean_forecast_jerez_20260924}"
SOURCE_ROOT="${JOINT_RECURSIVE_MEAN_SOURCE_ROOT:-${REPO_ROOT}/application/cache/source/joint_qdesn_corrected_article_comparison_muscat_11core_20260909}"
CONTRACT="${JOINT_RECURSIVE_MEAN_CONTRACT:-${REPO_ROOT}/application/config/joint_qdesn_recursive_mean_forecast_contract_v1.csv}"
CPU_LIST="${JOINT_RECURSIVE_MEAN_CPU_LIST:-}"
WORKERS="${JOINT_RECURSIVE_MEAN_WORKERS:-8}"
SESSION="${JOINT_RECURSIVE_MEAN_SESSION:-joint_qdesn_recursive_mean_forecast_jerez_8core_20260924}"
MODE="${1:---preflight}"

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

require_execution_contract() {
  [[ "${JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION:-}" == "JEREZ_8_PHYSICAL" ]] || {
    echo "Refusing production without JEREZ_8_PHYSICAL authorization." >&2
    exit 64
  }
  [[ "$WORKERS" == "8" ]] || { echo "Execution contract requires exactly 8 workers." >&2; exit 64; }
  [[ -n "$CPU_LIST" ]] || { echo "JOINT_RECURSIVE_MEAN_CPU_LIST is required." >&2; exit 64; }
}

preflight_capacity() {
  require_execution_contract
  mkdir -p "$ROOT/logs" "$ROOT/exits" "$ROOT/failures"
  local host free_kib free_mem_kib topology selected allowed busy_count
  host="$(hostname -s)"
  [[ "$host" == jerez* ]] || { echo "This campaign is frozen for Jerez, observed: $host" >&2; exit 64; }
  IFS=',' read -r -a selected <<< "$CPU_LIST"
  [[ "${#selected[@]}" == "8" ]] || { echo "CPU list must contain exactly 8 logical CPUs." >&2; exit 64; }
  [[ "$(printf '%s\n' "${selected[@]}" | sort -nu | wc -l)" == "8" ]] || {
    echo "CPU list contains duplicates." >&2; exit 64;
  }
  topology="$(lscpu -p=CPU,CORE,SOCKET | grep -v '^#')"
  printf '%s\n' "$topology" >"$ROOT/physical_core_inventory.csv"
  printf '%s\n' "$topology" | awk -F, -v list=",${CPU_LIST}," '
    index(list, "," $1 ",") { key=$3 ":" $2; found++; seen[key]=1 }
    END { if (found != 8 || length(seen) != 8) exit 1 }
  ' || { echo "CPU affinity does not map to 8 distinct physical cores." >&2; exit 64; }
  allowed="$(taskset -pc $$ | sed 's/.*: //')"
  for cpu in "${selected[@]}"; do
    taskset -c "$cpu" true || { echo "CPU $cpu is outside the allowed affinity." >&2; exit 64; }
  done
  busy_count="$(ps -eLo psr=,pcpu=,pid=,comm= | awk -v list=",${CPU_LIST}," '
    index(list, "," $1 ",") && $2 + 0 >= 20 { seen[$3]=1 }
    END { print length(seen) }
  ')"
  [[ "$busy_count" == "0" ]] || {
    echo "At least one selected CPU currently carries another >=20% CPU process." >&2
    exit 64
  }
  free_kib="$(df -Pk "$REPO_ROOT" | awk 'NR==2 {print $4}')"
  free_mem_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
  (( free_kib >= 10 * 1024 * 1024 )) || { echo "Jerez disk gate requires 10 GiB free." >&2; exit 64; }
  (( free_mem_kib >= 16 * 1024 * 1024 )) || { echo "Jerez memory gate requires 16 GiB available." >&2; exit 64; }
  [[ -x "$RSCRIPT" && -d "$SOURCE_ROOT" && -f "$CONTRACT" ]] || {
    echo "Pinned R, source runtime, or contract is unavailable." >&2; exit 64;
  }
  [[ -z "$(git -C "$REPO_ROOT" status --short --untracked-files=no)" ]] || {
    echo "Tracked Jerez worktree changes block production." >&2; exit 64;
  }
  {
    echo "slot,logical_cpu"
    local slot=1 cpu
    for cpu in "${selected[@]}"; do echo "${slot},${cpu}"; slot=$((slot + 1)); done
  } >"$ROOT/cpu_affinity_plan.csv"
  {
    echo "host,workers,cpu_list,free_disk_kib,available_memory_kib,git_head,checked_at,status"
    printf '%s,%s,"%s",%s,%s,%s,%s,pass\n' "$host" "$WORKERS" "$CPU_LIST" \
      "$free_kib" "$free_mem_kib" "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$(date -Is)"
  } >"$ROOT/host_preflight.csv"
}

run_r() {
  "$RSCRIPT" "$@"
}

plan_ids() {
  local plan="$1" expression="$2"
  "$RSCRIPT" - "$plan" "$expression" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- read.csv(args[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
keep <- eval(parse(text = args[[2L]]), envir = x)
cat(as.integer(x$worker_id[keep]), sep = "\n")
RS
}

run_queue() {
  local kind="$1"; shift
  local worker_script prefix worker cpu pid code failure=0
  local -a ids=("$@")
  [[ "${#ids[@]}" -gt 0 ]] || return 0
  if [[ "$kind" == "oracle" ]]; then
    worker_script="$SCRIPT_DIR/run_joint_qdesn_recursive_dgp_oracle_worker.R"
    prefix="oracle"
  else
    worker_script="$SCRIPT_DIR/run_joint_qdesn_recursive_mean_forecast_worker.R"
    prefix="cell"
  fi
  joint_exqdesn_cpu_queue_init "$CPU_LIST" "$WORKERS"
  for worker in "${ids[@]}"; do
    joint_exqdesn_cpu_queue_acquire; cpu="$QUEUE_CPU"
    (
      set +e
      taskset -c "$cpu" "$RSCRIPT" "$worker_script" \
        --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT" \
        --worker-id "$worker" >"$ROOT/logs/${prefix}_$(printf '%04d' "$worker").log" 2>&1
      code=$?
      printf '%s\n' "$code" >"$ROOT/exits/${prefix}_$(printf '%04d' "$worker").exit"
      exit "$code"
    ) &
    pid=$!
    joint_exqdesn_cpu_queue_register "$pid" "$cpu"
  done
  joint_exqdesn_cpu_queue_wait_all
  for worker in "${ids[@]}"; do
    code="$(cat "$ROOT/exits/${prefix}_$(printf '%04d' "$worker").exit" 2>/dev/null || echo 99)"
    if [[ "$code" != "0" ]]; then
      echo "$kind worker $worker failed with exit $code" >&2
      failure=1
    fi
  done
  (( failure == 0 ))
}

run_internal() {
  preflight_capacity
  run_r "$SCRIPT_DIR/prepare_joint_qdesn_recursive_mean_forecast.R" \
    --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT"

  mapfile -t primary_oracles < <(plan_ids "$ROOT/oracle_plan.csv" 'is_primary %in% c(TRUE, "TRUE", "true", 1)')
  run_queue oracle "${primary_oracles[@]}"
  set +e
  run_r "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
    --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT" \
    --aggregate-oracles true
  aggregate_code=$?
  set -e
  if [[ "$aggregate_code" == "20" ]]; then
    mapfile -t extension_oracles < <(plan_ids "$ROOT/oracle_extension_plan.csv" 'rep(TRUE, nrow(.GlobalEnv$x))')
    run_queue oracle "${extension_oracles[@]}"
    run_r "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
      --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT" \
      --aggregate-oracles true
  elif [[ "$aggregate_code" != "0" ]]; then
    exit "$aggregate_code"
  fi

  mapfile -t sentinels < <(plan_ids "$ROOT/cell_plan.csv" 'sentinel %in% c(TRUE, "TRUE", "true", 1)')
  run_queue cell "${sentinels[@]}"
  run_r "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
    --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT" \
    --require-sentinels true

  mapfile -t all_cells < <(plan_ids "$ROOT/cell_plan.csv" 'rep(TRUE, nrow(.GlobalEnv$x))')
  run_queue cell "${all_cells[@]}"
  run_r "$SCRIPT_DIR/check_joint_qdesn_recursive_mean_forecast.R" \
    --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT" \
    --require-complete true
  run_r "$SCRIPT_DIR/finalize_joint_qdesn_recursive_mean_forecast.R" \
    --root "$ROOT" --contract-path "$CONTRACT"
}

case "$MODE" in
  --preflight)
    preflight_capacity
    run_r "$SCRIPT_DIR/prepare_joint_qdesn_recursive_mean_forecast.R" \
      --root "$ROOT" --source-root "$SOURCE_ROOT" --contract-path "$CONTRACT"
    ;;
  --internal)
    run_internal
    ;;
  --run-all|--resume)
    require_execution_contract
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Session already exists: $SESSION" >&2
      exit 64
    fi
    tmux new-session -d -s "$SESSION" \
      "env JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION=JEREZ_8_PHYSICAL \
        JOINT_RECURSIVE_MEAN_CPU_LIST=$(printf '%q' "$CPU_LIST") \
        JOINT_RECURSIVE_MEAN_WORKERS=8 \
        JOINT_RECURSIVE_MEAN_RUNTIME_ROOT=$(printf '%q' "$ROOT") \
        JOINT_RECURSIVE_MEAN_SOURCE_ROOT=$(printf '%q' "$SOURCE_ROOT") \
        JOINT_RECURSIVE_MEAN_CONTRACT=$(printf '%q' "$CONTRACT") \
        bash $(printf '%q' "$0") --internal >$(printf '%q' "$ROOT/controller.log") 2>&1"
    echo "Launched $SESSION with eight physical-core workers."
    ;;
  *)
    echo "Usage: $0 [--preflight|--run-all|--resume|--internal]" >&2
    exit 64
    ;;
esac
