#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

readiness_dir="application/cache/joint_qdesn_phase152_independent_confirmation_readiness_20260729"
fixture_dir="application/cache/joint_qdesn_phase152_independent_confirmation_fixtures_20260729"
vb_dir="application/cache/joint_qdesn_phase152_independent_confirmation_vb_20260729"
mcmc_dir="application/cache/joint_qdesn_phase152_independent_confirmation_mcmc_20260729"
orchestration_dir="application/cache/joint_qdesn_phase152_independent_confirmation_20260729_orchestration"
session_name="joint_exqdesn_phase152_confirmation_20260729"
workers="${PHASE152_WORKERS:-16}"
execute="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) execute="true"; shift ;;
    --workers) workers="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --vb-dir) vb_dir="$2"; shift 2 ;;
    --mcmc-dir) mcmc_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "${orchestration_dir}"
log="${orchestration_dir}/phase152_workflow.log"
time_log="${orchestration_dir}/phase152_workflow.time"
exit_file="${orchestration_dir}/phase152_workflow.exit"
wrapper="${orchestration_dir}/run_phase152.sh"

if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "Phase152 tmux session is already active: ${session_name}"
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
echo "START_PHASE152 \$(date -Is)"
Rscript --vanilla application/scripts/173_prepare_joint_exqdesn_phase152_independent_confirmation.R \
  --output-dir $(printf '%q' "${readiness_dir}") \
  --fixture-dir $(printf '%q' "${fixture_dir}")
code=\$?
if [[ "\${code}" -eq 0 ]]; then
  Rscript --vanilla application/scripts/174_run_joint_exqdesn_phase152_vb_confirmation.R \
    --output-dir $(printf '%q' "${vb_dir}") \
    --readiness-dir $(printf '%q' "${readiness_dir}") \
    --fixture-dir $(printf '%q' "${fixture_dir}") \
    --n-cores $(printf '%q' "${workers}") \
    --incomplete-only true
  code=\$?
fi
if [[ "\${code}" -eq 0 ]]; then
  Rscript --vanilla application/scripts/175_run_joint_exqdesn_phase152_mcmc_confirmation.R \
    --output-dir $(printf '%q' "${mcmc_dir}") \
    --vb-dir $(printf '%q' "${vb_dir}") \
    --readiness-dir $(printf '%q' "${readiness_dir}") \
    --n-cores $(printf '%q' "${workers}")
  code=\$?
fi
end=\$(date +%s)
printf 'elapsed_seconds=%s\nexit_code=%s\n' "\$((end-start))" "\${code}" > $(printf '%q' "${time_log}")
echo "\${code}" > $(printf '%q' "${exit_file}")
echo "EXIT_CODE=\${code} END_PHASE152 \$(date -Is)"
exit "\${code}"
EOF
chmod +x "${wrapper}"

cat > "${orchestration_dir}/launch_config.csv" <<EOF
session_name,workers,readiness_dir,fixture_dir,vb_dir,mcmc_dir,vb_jobs,mcmc_chains_per_survivor,blas_threads_per_worker
${session_name},${workers},${readiness_dir},${fixture_dir},${vb_dir},${mcmc_dir},80,8,1
EOF

if [[ "${execute}" != "true" ]]; then
  echo "Prepared Phase152 launch wrapper: ${wrapper}"
  echo "Run with --execute to start the resumable workflow."
  exit 0
fi

rm -f "${exit_file}" "${time_log}"
tmux new-session -d -s "${session_name}" \
  "bash $(printf '%q' "${wrapper}") 2>&1 | tee $(printf '%q' "${log}")"
echo "Launched Phase152 in tmux session: ${session_name}"
echo "Log: ${log}"
