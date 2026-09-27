#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925}"
CONFIRMATION_ROOT="${2:-application/cache/joint_qdesn_pure_recursive_article_confirmation_jerez_15core_20260925}"
SCORE_ROOT="${3:-application/cache/joint_qdesn_pure_recursive_score_packet_jerez_15core_20260925}"
CONTROL_ROOT="${4:-application/cache/joint_qdesn_pure_recursive_shared_capacity_v4_20260927}"
POLL_SECONDS="${JOINT_CAPACITY_POLL_SECONDS:-120}"
REQUIRED_CLEAN_POLLS="${JOINT_CAPACITY_CLEAN_POLLS:-5}"
BRANCH="work/joint-qdesn-pure-desn-recursive-selection-20260925"
TARGET_CPU_LIST="1,8,9,12,13,15,19,20,24,25,27,28,29,30,31"
PRICEFM_CPU_LIST="2,3,4,5,6,7,10,11,14,17,18,21,22,23,26"
SPARE_CPU_LIST="0,16"
PRICEFM_TAG="pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"

[[ "$(hostname -s)" == "jerez" ]] || { echo "Shared recovery may run only on jerez." >&2; exit 2; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || { echo "Wrong execution branch." >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Tracked worktree is dirty." >&2; exit 2; }
[[ "$(git rev-list --left-right --count '@{upstream}'...HEAD)" == $'0\t0' ]] || {
  echo "Execution branch is not synchronized." >&2
  exit 2
}

mkdir -p "$CONTROL_ROOT"
printf 'checked_at_utc,blocker_count,clean_poll_count,pricefm_partition_verified,pricefm_controller_verified\n' \
  >"$CONTROL_ROOT/capacity_history.csv"
clean_polls=0
while (( clean_polls < REQUIRED_CLEAN_POLLS )); do
  blocker_file="$CONTROL_ROOT/capacity_blockers.csv"
  affinity_file="$CONTROL_ROOT/pricefm_affinity_audit.csv"
  printf 'pid,last_cpu,pcpu,reason,command\n' >"$blocker_file"
  printf 'pid,allowed_cpu_list,partition_verified,command\n' >"$affinity_file"

  topology_file="$CONTROL_ROOT/cpu_physical_topology.csv"
  printf 'logical_cpu,physical_key\n' >"$topology_file"
  for topology_path in /sys/devices/system/cpu/cpu[0-9]*/topology; do
    cpu="${topology_path%/topology}"
    cpu="${cpu##*cpu}"
    package="$(<"$topology_path/physical_package_id")"
    core="$(<"$topology_path/core_id")"
    printf '%s,%s:%s\n' "$cpu" "$package" "$core" >>"$topology_file"
  done
  target_physical=""
  IFS=',' read -r -a target_ids <<<"$TARGET_CPU_LIST"
  for cpu in "${target_ids[@]}"; do
    key="$(awk -F, -v cpu="$cpu" '$1 == cpu {print $2}' "$topology_file")"
    target_physical="${target_physical}${target_physical:+,}${key}"
  done

  ps -u "$USER" -o pid=,psr=,pcpu=,args= | awk \
    -v targets="$target_physical" -v self="$$" -v parent="$PPID" '
      NR == FNR && FNR > 1 { split($0,row,","); physical[row[1]]=row[2]; next }
      NR == FNR { next }
      BEGIN { n=split(targets,a,","); for(i=1;i<=n;i++) target[a[i]]=1 }
      {
        pid=$1; cpu=$2; pcpu=$3; $1=$2=$3=""; sub(/^ +/,""); command=$0
        if(pid==self || pid==parent || command ~ /^awk -v targets=/) next
        if(target[physical[cpu]] && pcpu+0>=20) {
          gsub(/,/,";",command)
          printf "%s,%s,%s,hot_on_joint_physical_core,%s\n",pid,cpu,pcpu,command
        }
      }
    ' "$topology_file" - >>"$blocker_file"

  pricefm_partition_verified=true
  pricefm_controller_verified=true
  pricefm_controller_seen=false
  pricefm_process_count=0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    pid="${row%% *}"
    command="${row#* }"
    pricefm_process_count=$((pricefm_process_count + 1))
    if [[ "$command" == *"414_run_pricefm_stage_r120_explicit_lag_search.py"* &&
          "$command" != *"--mode"* ]]; then
      pricefm_controller_seen=true
      declared="$(sed -n 's/.*--cpu-list \([^ ]*\).*/\1/p' <<<"$command")"
      if [[ "$declared" != "$PRICEFM_CPU_LIST" ]]; then
        pricefm_controller_verified=false
        safe_command="${command//,/;}"
        printf '%s,%s,%s,pricefm_controller_cpu_list_mismatch,%s\n' \
          "$pid" "$(ps -p "$pid" -o psr= | tr -d ' ')" \
          "$(ps -p "$pid" -o pcpu= | tr -d ' ')" "$safe_command" >>"$blocker_file"
      fi
    fi
    if [[ "$command" =~ 415_fit_pricefm|414_run_pricefm.*--mode ]]; then
      allowed="$(taskset -pc "$pid" 2>/dev/null | sed 's/.*: //' | tr -d '[:space:]')"
      verified=true
      IFS=',' read -r -a ids <<<"$allowed"
      for id in "${ids[@]}"; do
        [[ ",$PRICEFM_CPU_LIST," == *",$id,"* ]] || verified=false
      done
      safe_command="${command//,/;}"
      printf '%s,%s,%s,%s\n' "$pid" "$allowed" "$verified" "$safe_command" >>"$affinity_file"
      if [[ "$verified" != true ]]; then
        pricefm_partition_verified=false
        printf '%s,%s,%s,pricefm_affinity_outside_partition,%s\n' \
          "$pid" "$(ps -p "$pid" -o psr= | tr -d ' ')" \
          "$(ps -p "$pid" -o pcpu= | tr -d ' ')" "$safe_command" >>"$blocker_file"
      fi
    fi
  done < <(pgrep -af "$PRICEFM_TAG" || true)
  if (( pricefm_process_count > 0 )) && [[ "$pricefm_controller_seen" != true ]]; then
    pricefm_controller_verified=false
    printf '0,NA,NA,pricefm_controller_missing,PriceFM processes exist without the verified top-level controller\n' \
      >>"$blocker_file"
  fi

  blocker_count="$(($(wc -l <"$blocker_file") - 1))"
  if (( blocker_count == 0 )) && [[ "$pricefm_partition_verified" == true ]] &&
      [[ "$pricefm_controller_verified" == true ]]; then
    clean_polls=$((clean_polls + 1))
  else
    clean_polls=0
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s,%s,%s,%s,%s\n' "$now" "$blocker_count" "$clean_polls" \
    "$pricefm_partition_verified" "$pricefm_controller_verified" \
    >>"$CONTROL_ROOT/capacity_history.csv"
  printf 'status,source_root,joint_cpu_list,pricefm_cpu_list,spare_cpu_list,blocker_count,clean_poll_count,required_clean_polls,pricefm_process_count,updated_at_utc\nWAITING_FOR_DISJOINT_CAPACITY,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$SOURCE_ROOT" "$TARGET_CPU_LIST" "$PRICEFM_CPU_LIST" "$SPARE_CPU_LIST" \
    "$blocker_count" "$clean_polls" "$REQUIRED_CLEAN_POLLS" \
    "$pricefm_process_count" "$now" >"$CONTROL_ROOT/resume_status.csv"
  (( clean_polls >= REQUIRED_CLEAN_POLLS )) || sleep "$POLL_SECONDS"
done

printf 'status,source_root,joint_cpu_list,pricefm_cpu_list,spare_cpu_list,released_at_utc\nDISJOINT_CAPACITY_RELEASED_RESUMING_CONFIRMATION,%s,%s,%s,%s,%s\n' \
  "$SOURCE_ROOT" "$TARGET_CPU_LIST" "$PRICEFM_CPU_LIST" "$SPARE_CPU_LIST" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CONTROL_ROOT/resume_status.csv"

exec bash application/scripts/launch_joint_qdesn_pure_recursive_confirmation_shared_jerez.sh \
  "$SOURCE_ROOT" "$CONFIRMATION_ROOT" "$SCORE_ROOT"
