#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"
parallel_workers="${1:-32}"
if ! [[ "${parallel_workers}" =~ ^[1-9][0-9]*$ ]] || [[ "${parallel_workers}" -gt 48 ]]; then
  echo "parallel workers must be between 1 and 48" >&2
  exit 2
fi

export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Refusing to launch Phase169R from an uncommitted worktree." >&2
  exit 1
fi

cache_root="${JOINT_EXQDESN_CACHE_ROOT:-/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache}"
freeze_dir="${cache_root}/joint_exqdesn_phase169r_corrected_mcmc_method_selection_freeze_20260807"
output_dir="${cache_root}/joint_exqdesn_phase169r_corrected_mcmc_method_selection_20260807"
orchestration_dir="${cache_root}/joint_exqdesn_phase169r_corrected_mcmc_method_selection_20260807_orchestration"
session="joint_exqdesn_phase169r_mcmc_20260807"

for blocked_session in joint_exqdesn_phase169_mcmc_20260807 "${session}"; do
  if tmux has-session -t "${blocked_session}" 2>/dev/null; then
    echo "Refusing launch while tmux session ${blocked_session} exists." >&2
    exit 1
  fi
done
if ps -eo args= | grep -Eq '[2](22_run_joint_exqdesn_phase169_chain|27_run_joint_exqdesn_phase169r_chain)[.]R'; then
  echo "Refusing launch while a Phase169/169R worker process exists." >&2
  exit 1
fi

mkdir -p "${orchestration_dir}/logs" "${orchestration_dir}/exits" "${orchestration_dir}/failures"
Rscript application/scripts/226_prepare_joint_exqdesn_phase169r_recovery.R
Rscript -e '
  x <- read.csv(commandArgs(TRUE)[[1L]], stringsAsFactors = FALSE)
  if (nrow(x) != 1L || x$gate_status[[1L]] != "pass" || x$planned_workers[[1L]] != 240L) quit(status = 1L)
' "${freeze_dir}/readiness_assessment.csv"

runner="${orchestration_dir}/run_committed_campaign.sh"
cat > "${runner}" <<EOF
#!/usr/bin/env bash
set -uo pipefail
cd $(printf '%q' "${repo_root}")
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
freeze_dir=$(printf '%q' "${freeze_dir}")
logs=$(printf '%q' "${orchestration_dir}/logs")
exits=$(printf '%q' "${orchestration_dir}/exits")
failures=$(printf '%q' "${orchestration_dir}/failures")
run_one() {
  worker_id="\$1"
  tag="\$(printf '%03d' "\${worker_id}")"
  log="\${logs}/worker_\${tag}.log"
  Rscript application/scripts/227_run_joint_exqdesn_phase169r_chain.R \
    --freeze-dir "\${freeze_dir}" --worker-id "\${worker_id}" \
    --failure-dir "\${failures}" > "\${log}" 2>&1
  code=\$?
  printf '%s\\n' "\${code}" > "\${exits}/worker_\${tag}.exit"
  printf 'EXIT_CODE=%s\\n' "\${code}" >> "\${log}"
  if [[ "\${code}" -ne 0 ]]; then return 255; fi
  return 0
}
export -f run_one
export freeze_dir logs exits failures
seq 1 240 | xargs -P $(printf '%q' "${parallel_workers}") -n 1 bash -c 'run_one "\$1"' _
campaign_code=\$?
if [[ "\${campaign_code}" -ne 0 ]]; then
  echo "Phase169R stopped dispatching after a worker failure; finalization withheld."
  echo EXIT_CODE=\${campaign_code}
  exit "\${campaign_code}"
fi
Rscript application/scripts/228_finalize_joint_exqdesn_phase169r_mcmc_method_selection.R
final_code=\$?
echo EXIT_CODE=\${final_code}
exit "\${final_code}"
EOF
chmod +x "${runner}"

cat > "${orchestration_dir}/run_config.csv" <<EOF
run_id,parallel_workers,threads_per_worker,planned_workers,scenarios,fit_structures,methods,chains_per_cell,n_iter,burn,thin,launch_commit,launch_source,fail_fast
phase169r_corrected_mcmc_method_selection_20260807,${parallel_workers},1,240,5,2,3,8,12000,3000,3,$(git rev-parse HEAD),committed_versioned_scripts,true
EOF
cat > "${orchestration_dir}/README.md" <<EOF
# Phase169R Corrected Production Launch

- Session: ${session}
- Concurrent chains: ${parallel_workers}
- Planned chains: 240
- Threads per chain: 1
- Every chain writes a verified post-fit checkpoint before scoring.
- Dispatch is fail-fast after the first worker error.
- Finalization occurs only after all 240 workers verify successfully.
EOF

campaign_log="${orchestration_dir}/campaign.log"
tmux new-session -d -s "${session}" \
  "bash $(printf '%q' "${runner}") > $(printf '%q' "${campaign_log}") 2>&1"

echo "Launched Phase169R in tmux session ${session}."
echo "Freeze: ${freeze_dir}"
echo "Output: ${output_dir}"
echo "Log: ${campaign_log}"
