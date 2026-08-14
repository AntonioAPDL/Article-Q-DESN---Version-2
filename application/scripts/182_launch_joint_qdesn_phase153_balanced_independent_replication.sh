#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

readiness_dir="application/cache/joint_qdesn_phase153_balanced_independent_replication_readiness_20260729"
fixture_dir="application/cache/joint_qdesn_phase153_balanced_independent_replication_fixtures_20260729"
vb_dir="application/cache/joint_qdesn_phase153_balanced_independent_replication_vb_20260729"
orchestration_dir="application/cache/joint_qdesn_phase153_balanced_independent_replication_20260729_orchestration"
session_name="joint_qdesn_phase153_balanced_replication_20260729"
workers="${PHASE153_WORKERS:-20}"
n_dgp_replicates="${PHASE153_DGP_REPLICATES:-50}"
seed_base="${PHASE153_SEED_BASE:-153000000}"
bootstrap_replicates="${PHASE153_BOOTSTRAP_REPLICATES:-2000}"
execute="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) execute="true"; shift ;;
    --workers) workers="$2"; shift 2 ;;
    --n-dgp-replicates) n_dgp_replicates="$2"; shift 2 ;;
    --seed-base) seed_base="$2"; shift 2 ;;
    --bootstrap-replicates) bootstrap_replicates="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --vb-dir) vb_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! [[ "${workers}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--workers must be a positive integer." >&2
  exit 2
fi
if ! [[ "${n_dgp_replicates}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--n-dgp-replicates must be a positive integer." >&2
  exit 2
fi

mkdir -p "${orchestration_dir}"
log="${orchestration_dir}/phase153_workflow.log"
time_log="${orchestration_dir}/phase153_workflow.time"
exit_file="${orchestration_dir}/phase153_workflow.exit"
wrapper="${orchestration_dir}/run_phase153.sh"

if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "Phase153 tmux session is already active: ${session_name}"
  exit 0
fi

cat > "${wrapper}" <<EOF
#!/usr/bin/env bash
set -uo pipefail
cd $(printf '%q' "${repo_root}")
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export BLIS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
start=\$(date +%s)
echo "START_PHASE153 \$(date -Is)"
Rscript --vanilla application/scripts/178_prepare_joint_qdesn_phase153_balanced_independent_replication.R \
  --output-dir $(printf '%q' "${readiness_dir}") \
  --fixture-dir $(printf '%q' "${fixture_dir}") \
  --n-dgp-replicates $(printf '%q' "${n_dgp_replicates}") \
  --seed-base $(printf '%q' "${seed_base}") \
  --materialize-fixtures true
code=\$?
if [[ "\${code}" -eq 0 ]]; then
  Rscript --vanilla application/scripts/179_run_joint_qdesn_phase153_balanced_independent_replication.R \
    --output-dir $(printf '%q' "${vb_dir}") \
    --readiness-dir $(printf '%q' "${readiness_dir}") \
    --fixture-dir $(printf '%q' "${fixture_dir}") \
    --n-cores $(printf '%q' "${workers}") \
    --incomplete-only true \
    --bootstrap-replicates $(printf '%q' "${bootstrap_replicates}")
  code=\$?
fi
if [[ "\${code}" -eq 0 ]]; then
  Rscript --vanilla application/scripts/180_audit_joint_qdesn_phase153_balanced_independent_replication.R \
    --output-dir $(printf '%q' "${vb_dir}") \
    --readiness-dir $(printf '%q' "${readiness_dir}") \
    --bootstrap-replicates $(printf '%q' "${bootstrap_replicates}")
  code=\$?
fi
end=\$(date +%s)
printf 'elapsed_seconds=%s\nexit_code=%s\n' "\$((end-start))" "\${code}" > $(printf '%q' "${time_log}")
echo "\${code}" > $(printf '%q' "${exit_file}")
echo "EXIT_CODE=\${code} END_PHASE153 \$(date -Is)"
exit "\${code}"
EOF
chmod +x "${wrapper}"

expected_fixtures=$((8 * n_dgp_replicates))
expected_candidates=$((4 * expected_fixtures))
cat > "${orchestration_dir}/launch_config.csv" <<EOF
session_name,workers,n_dgp_replicates,expected_fixtures,expected_candidates,seed_base,bootstrap_replicates,readiness_dir,fixture_dir,vb_dir,blas_threads_per_worker
${session_name},${workers},${n_dgp_replicates},${expected_fixtures},${expected_candidates},${seed_base},${bootstrap_replicates},${readiness_dir},${fixture_dir},${vb_dir},1
EOF

if [[ "${execute}" != "true" ]]; then
  echo "Prepared Phase153 launch wrapper: ${wrapper}"
  echo "Run with --execute to start the resumable full campaign."
  exit 0
fi

rm -f "${exit_file}" "${time_log}"
tmux new-session -d -s "${session_name}" \
  "bash $(printf '%q' "${wrapper}") 2>&1 | tee $(printf '%q' "${log}")"
echo "Launched Phase153 in tmux session: ${session_name}"
echo "Log: ${log}"
echo "Expected fits: ${expected_candidates}"
