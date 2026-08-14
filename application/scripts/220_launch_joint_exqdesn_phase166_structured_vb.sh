#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"
workers="${1:-20}"
if ! [[ "${workers}" =~ ^[1-9][0-9]*$ ]]; then
  echo "workers must be a positive integer" >&2
  exit 2
fi

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Refusing to launch Phase166 from an uncommitted worktree." >&2
  exit 1
fi
cache_root="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
output_dir="${cache_root}/joint_exqdesn_phase166_structured_vb_method_development_20260806"
orchestration_dir="${output_dir}/orchestration"
mkdir -p "${orchestration_dir}"

Rscript application/scripts/216_prepare_joint_exqdesn_phase164_165_exact_structured.R

finalizer_session="joint_exqdesn_phase166_finalizer"
if tmux has-session -t "${finalizer_session}" 2>/dev/null; then
  echo "Refusing to replace active tmux session ${finalizer_session}" >&2
  exit 1
fi

for worker_id in $(seq 1 "${workers}"); do
  session="joint_exqdesn_phase166_w$(printf '%03d' "${worker_id}")"
  log="${orchestration_dir}/worker_$(printf '%03d' "${worker_id}").log"
  if tmux has-session -t "${session}" 2>/dev/null; then
    echo "Refusing to replace active tmux session ${session}" >&2
    exit 1
  fi
  tmux new-session -d -s "${session}" \
    "cd $(printf '%q' "${repo_root}") && Rscript application/scripts/217_run_joint_exqdesn_phase166_worker.R --worker-id ${worker_id} --worker-count ${workers} > $(printf '%q' "${log}") 2>&1; code=\$?; echo EXIT_CODE=\${code} >> $(printf '%q' "${log}"); exit \${code}"
done

finalizer_log="${orchestration_dir}/finalizer.log"
finalizer="${orchestration_dir}/finalize_when_complete.sh"
cat > "${finalizer}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "${repo_root}")
while tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -q '^joint_exqdesn_phase166_w'; do sleep 60; done
failed=0
for log in $(printf '%q' "${orchestration_dir}")/worker_*.log; do
  grep -q '^EXIT_CODE=0$' "\${log}" || failed=1
done
if [[ "\${failed}" -ne 0 ]]; then
  echo 'At least one Phase166 worker failed; finalization withheld.'
  echo EXIT_CODE=1
  exit 1
fi
Rscript application/scripts/218_finalize_joint_exqdesn_phase166_structured_vb.R
echo EXIT_CODE=0
EOF
chmod +x "${finalizer}"
tmux new-session -d -s "${finalizer_session}" \
  "bash $(printf '%q' "${finalizer}") > $(printf '%q' "${finalizer_log}") 2>&1"

cat > "${orchestration_dir}/run_config.csv" <<EOF
run_id,workers,threads_per_worker,registry_rows,scenario_structure_groups,reused_vb0_rows,new_structured_rows,launch_commit,launch_source
phase166_structured_vb_20260806,${workers},1,480,160,160,320,$(git rev-parse HEAD),committed_versioned_scripts
EOF
cat > "${orchestration_dir}/README.md" <<EOF
# Phase166 Parallel Launch

- Workers: ${workers}
- One numerical thread per worker
- Total registry rows: 480
- Verified reused VB0 rows: 160
- New structured-VB rows: 320
- Finalization is automatic only when every worker records EXIT_CODE=0.
EOF

echo "Launched ${workers} Phase166 workers plus ${finalizer_session}."
echo "Output: ${output_dir}"
