#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CACHE_ROOT="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
SESSION="joint_exqdesn_phase172_m0_article_20260809"
JOBS=""
CPU_LIST=""
FOREGROUND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --cpu-list) CPU_LIST="$2"; shift 2 ;;
    --cache-root) CACHE_ROOT="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --foreground) FOREGROUND=1; shift ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ ! "$JOBS" =~ ^(24|25|26|27|28|29|30|31|32)$ ]]; then
  printf '%s\n' '--jobs must be an integer from 24 through 32.' >&2
  exit 2
fi
if [[ -z "$CPU_LIST" ]]; then
  printf '%s\n' '--cpu-list is required.' >&2
  exit 2
fi

IFS=',' read -r -a CPUS <<< "$CPU_LIST"
if (( ${#CPUS[@]} < JOBS )); then
  printf 'CPU list has %d slots but --jobs=%d.\n' "${#CPUS[@]}" "$JOBS" >&2
  exit 2
fi
declare -A SEEN=()
ONLINE=$(nproc)
for cpu in "${CPUS[@]:0:JOBS}"; do
  if [[ ! "$cpu" =~ ^[0-9]+$ ]] || (( cpu >= ONLINE )); then
    printf 'Invalid or offline CPU: %s\n' "$cpu" >&2
    exit 2
  fi
  if [[ -n "${SEEN[$cpu]:-}" ]]; then
    printf 'Duplicate CPU: %s\n' "$cpu" >&2
    exit 2
  fi
  SEEN[$cpu]=1
done

FREEZE="$CACHE_ROOT/joint_exqdesn_phase171_m0_balanced_article_freeze_20260809"
ORCH="$CACHE_ROOT/joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809_orchestration"
LOG="$CACHE_ROOT/joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809_tmux.log"
WORKER_SCRIPT="$ROOT/application/scripts/233_run_joint_exqdesn_phase172_m0_chain.R"
if [[ ! -f "$FREEZE/artifact_manifest.csv" ]]; then
  printf 'Missing Phase171 freeze: %s\n' "$FREEZE" >&2
  exit 3
fi

mkdir -p "$ORCH/logs" "$ORCH/exits" "$ORCH/failures"
MEM_GIB=$(awk '/MemAvailable:/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GIB=$(df -Pk "$CACHE_ROOT" | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
if (( MEM_GIB < 100 || DISK_GIB < 10 )); then
  printf 'Resource gate failed: available RAM=%s GiB, free disk=%s GiB.\n' "$MEM_GIB" "$DISK_GIB" >&2
  exit 4
fi

BUSY=$(ps -eLo psr=,pcpu=,pid=,comm=,args= | awk -v cpus=",${CPU_LIST}," '
  {
    cpu=$1; usage=$2; pid=$3;
    if (usage + 0 >= 25 && index(cpus, "," cpu ",") > 0) print $0;
  }')
if [[ -n "$BUSY" ]]; then
  printf '%s\n' 'CPU-isolation gate failed; selected CPUs currently host high-CPU processes:' >&2
  printf '%s\n' "$BUSY" >&2
  exit 4
fi

ps -eLo pid=,ppid=,psr=,pcpu=,pmem=,etime=,comm=,args= > "$ORCH/process_inventory_before_launch.txt"
printf 'phase_id,jobs,cpu_list,cache_root,available_ram_gib,free_disk_gib,session,launched_at\n' > "$ORCH/launch_config.csv"
printf 'phase172_m0_balanced_article_confirmation,%s,"%s","%s",%s,%s,%s,%s\n' \
  "$JOBS" "$CPU_LIST" "$CACHE_ROOT" "$MEM_GIB" "$DISK_GIB" "$SESSION" "$(date -Is)" >> "$ORCH/launch_config.csv"

if (( FOREGROUND == 0 )); then
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    printf 'tmux session already exists: %s\n' "$SESSION" >&2
    exit 5
  fi
  printf -v CMD '%q ' "$0" --jobs "$JOBS" --cpu-list "$CPU_LIST" --cache-root "$CACHE_ROOT" --session "$SESSION" --foreground
  tmux new-session -d -s "$SESSION" "bash -lc '$CMD > $(printf %q "$LOG") 2>&1; code=\$?; echo EXIT_CODE=\$code; exit \$code'"
  printf 'session=%s\nlog=%s\n' "$SESSION" "$LOG"
  exit 0
fi

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

for wave in 1 2 3 4; do
  mapfile -t IDS < <(awk -F, -v wave="$wave" 'NR > 1 && $2 == wave {print $1}' "$FREEZE/chain_plan.csv")
  if (( ${#IDS[@]} != 32 )); then
    printf 'Wave %d has %d workers, expected 32.\n' "$wave" "${#IDS[@]}" >&2
    exit 6
  fi
  for ((offset=0; offset<${#IDS[@]}; offset+=JOBS)); do
    PIDS=()
    ACTIVE_IDS=()
    for ((slot=0; slot<JOBS && offset+slot<${#IDS[@]}; slot++)); do
      worker_id=${IDS[$((offset+slot))]}
      cpu=${CPUS[$slot]}
      worker_log="$ORCH/logs/worker_$(printf '%03d' "$worker_id").log"
      taskset -c "$cpu" Rscript "$WORKER_SCRIPT" \
        --worker-id "$worker_id" --freeze-dir "$FREEZE" \
        --failure-dir "$ORCH/failures" > "$worker_log" 2>&1 &
      PIDS+=("$!")
      ACTIVE_IDS+=("$worker_id")
    done
    batch_failed=0
    for index in "${!PIDS[@]}"; do
      worker_id=${ACTIVE_IDS[$index]}
      if wait "${PIDS[$index]}"; then code=0; else code=$?; batch_failed=1; fi
      printf '%d\n' "$code" > "$ORCH/exits/worker_$(printf '%03d' "$worker_id").exit"
    done
    if (( batch_failed != 0 )); then
      printf 'Wave %d batch at offset %d failed; no later batch was submitted.\n' "$wave" "$offset" >&2
      exit 7
    fi
  done
done

printf 'Phase172 workers completed: 128/128\n'
