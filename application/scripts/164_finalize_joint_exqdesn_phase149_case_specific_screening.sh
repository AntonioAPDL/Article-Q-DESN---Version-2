#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

prefix="joint_qdesn_phase149_exal_chunk_"
screening_dir="application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726"
readiness_dir="application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726"
registry="${readiness_dir}/phase149_case_specific_screening_registry.csv"
fixture_dir="application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
log="${screening_dir}/phase149_finalizer.log"

{
  echo "START $(date -Is)"
  while tmux ls 2>/dev/null | grep -q "${prefix}"; do
    echo "WAIT $(date -Is) active_workers=$(tmux ls 2>/dev/null | grep -c "${prefix}" || true)"
    sleep 60
  done

  failure=0
  for worker_log in "${screening_dir}"/parallel_phase149_case_specific_exal_20260726/logs/chunk_*.log; do
    if ! grep -q '^EXIT_CODE=0$' "${worker_log}"; then
      echo "WORKER_FAILURE ${worker_log}"
      failure=1
    fi
  done
  if [ "${failure}" -ne 0 ]; then
    echo "EXIT_CODE=1"
    echo "END $(date -Is)"
    exit 1
  fi

  Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \
    --registry "${registry}" \
    --output-dir "${screening_dir}" \
    --fixture-dir "${fixture_dir}" \
    --n-cores 1 \
    --reuse-completed true \
    --audit-only true
  Rscript application/scripts/163_audit_joint_exqdesn_phase149_case_specific_screening.R
  echo "EXIT_CODE=0"
  echo "END $(date -Is)"
} > "${log}" 2>&1
