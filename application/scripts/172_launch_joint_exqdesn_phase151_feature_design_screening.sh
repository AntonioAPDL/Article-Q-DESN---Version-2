#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

output_dir="application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728"
readiness_dir="application/cache/joint_qdesn_phase151_case_specific_feature_screening_readiness_20260728"
orchestration_dir="application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728_orchestration"
fixture_dir="application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
session_name="joint_exqdesn_phase151_feature_screen_20260728"
workers="${PHASE151_WORKERS:-8}"
execute="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) execute="true"; shift ;;
    --workers) workers="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

Rscript --vanilla application/scripts/169_prepare_joint_exqdesn_phase151_feature_design_screening.R \
  --output-dir "${readiness_dir}" \
  --screening-dir "${output_dir}" \
  --fixture-dir "${fixture_dir}"

mkdir -p "${orchestration_dir}"
log="${orchestration_dir}/phase151_screen.log"
time_log="${orchestration_dir}/phase151_screen.time"
exit_file="${orchestration_dir}/phase151_screen.exit"
wrapper="${orchestration_dir}/run_phase151.sh"

if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "Phase151 tmux session is already active: ${session_name}"
  exit 0
fi

Rscript --vanilla application/scripts/171_check_joint_exqdesn_phase151_feature_design_screening.R \
  --output-dir "${output_dir}" \
  --readiness-dir "${readiness_dir}" \
  --orchestration-dir "${orchestration_dir}" \
  --session-name "${session_name}" >/dev/null 2>&1 || true
health_state=""
if [[ -f "${orchestration_dir}/phase151_health_summary.csv" ]]; then
  health_state="$(
    Rscript --vanilla -e \
      'x <- read.csv(commandArgs(TRUE)[1], stringsAsFactors = FALSE); cat(x$lifecycle_state[[1L]])' \
      "${orchestration_dir}/phase151_health_summary.csv"
  )"
fi
if [[ "${health_state}" == "complete" ]]; then
  echo "Phase151 is already complete; no launch is needed."
  exit 0
fi

cat > "${wrapper}" <<EOF
#!/usr/bin/env bash
set -uo pipefail
cd $(printf '%q' "${repo_root}")
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
start=\$(date +%s)
echo "START_PHASE151 \$(date -Is)"
Rscript --vanilla application/scripts/170_run_joint_exqdesn_phase151_feature_design_screening.R \
  --output-dir $(printf '%q' "${output_dir}") \
  --readiness-dir $(printf '%q' "${readiness_dir}") \
  --fixture-dir $(printf '%q' "${fixture_dir}") \
  --n-cores $(printf '%q' "${workers}") \
  --incomplete-only true
code=\$?
end=\$(date +%s)
printf 'elapsed_seconds=%s\nexit_code=%s\n' "\$((end-start))" "\${code}" > $(printf '%q' "${time_log}")
echo "\${code}" > $(printf '%q' "${exit_file}")
echo "EXIT_CODE=\${code} END_PHASE151 \$(date -Is)"
exit "\${code}"
EOF
chmod +x "${wrapper}"

cat > "${orchestration_dir}/launch_config.csv" <<EOF
session_name,workers,output_dir,readiness_dir,fixture_dir,incomplete_only,blas_threads_per_worker
${session_name},${workers},${output_dir},${readiness_dir},${fixture_dir},true,1
EOF

if [[ "${execute}" != "true" ]]; then
  echo "Prepared Phase151 launch wrapper: ${wrapper}"
  echo "Run with --execute to start the full screen."
  exit 0
fi

rm -f "${exit_file}" "${time_log}"
tmux new-session -d -s "${session_name}" "bash $(printf '%q' "${wrapper}") 2>&1 | tee $(printf '%q' "${log}")"
echo "Launched Phase151 in tmux session: ${session_name}"
echo "Log: ${log}"
