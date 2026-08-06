#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"
cache=/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache
readiness="${cache}/joint_qdesn_phase163_tail_calibration_readiness_20260806"
screening="${cache}/joint_qdesn_phase163_tail_calibration_vb_20260806"
registry="${readiness}/phase163_candidate_registry.csv"
fixture="${cache}/joint_qdesn_simulation_dgp_fixtures_20260706"
Rscript application/scripts/211_prepare_joint_exqdesn_phase163_tail_calibration.R
Rscript --vanilla - "${readiness}/phase163_readiness_assessment.csv" <<'RS'
x<-read.csv(commandArgs(TRUE)[1]);stopifnot(nrow(x)==1L,x$gate_status[[1]]=="pass",x$prior_duplicates[[1]]==0)
RS
bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry "${registry}" --canonical-output-dir "${screening}" --fixture-dir "${fixture}" \
  --workers 20 --n-cores-per-worker 1 --run-id phase163_tail_calibration_20260806 \
  --session-prefix joint_exqdesn_phase163 --incomplete-only true
finalizer="${screening}/phase163_finalizer.sh"
log="${screening}/phase163_finalizer.log"
cat > "${finalizer}" <<RUNNER
#!/usr/bin/env bash
set -u
cd $(printf '%q' "${repo_root}") || exit 1
{
  echo "START \$(date -Is)"
  while tmux ls 2>/dev/null | grep -q 'joint_exqdesn_phase163_chunk_'; do sleep 60; done
  fail=0
  for f in "${screening}"/parallel_phase163_tail_calibration_20260806/logs/chunk_*.log; do
    grep -q '^EXIT_CODE=0$' "\${f}" || fail=1
  done
  if [ "\${fail}" -ne 0 ]; then echo EXIT_CODE=1; exit 1; fi
  Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R --registry "${registry}" --output-dir "${screening}" --fixture-dir "${fixture}" --n-cores 1 --reuse-completed true --audit-only true
  Rscript application/scripts/212_audit_joint_exqdesn_phase163_tail_calibration.R
  echo EXIT_CODE=0
  echo "END \$(date -Is)"
} > $(printf '%q' "${log}") 2>&1
RUNNER
chmod +x "${finalizer}"
tmux new-session -d -s joint_exqdesn_phase163_finalizer "bash $(printf '%q' "${finalizer}")"
