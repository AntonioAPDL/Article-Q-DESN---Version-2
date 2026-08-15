#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

readiness_dir="application/cache/joint_qdesn_phase154_mcmc_evidence_reconciliation_readiness_20260730"
freeze_dir="application/cache/joint_qdesn_phase154_article_grade_mcmc_rerun_freeze_20260730"
fixture_dir="application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
joint_al_dir="application/cache/joint_qdesn_phase154_mcmc_joint_al_20260730"
independent_al_dir="application/cache/joint_qdesn_phase154_mcmc_independent_al_20260730"
independent_exal_dir="application/cache/joint_qdesn_phase154_mcmc_independent_exal_20260730"
final_dir="application/cache/joint_qdesn_phase154_balanced_mcmc_final_20260730"
orchestration_dir="application/cache/joint_qdesn_phase154_article_grade_mcmc_20260730_orchestration"
workers_per_block="${PHASE154_WORKERS_PER_BLOCK:-8}"
execute="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) execute="true"; shift ;;
    --workers-per-block) workers_per_block="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --freeze-dir) freeze_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --joint-al-dir) joint_al_dir="$2"; shift 2 ;;
    --independent-al-dir) independent_al_dir="$2"; shift 2 ;;
    --independent-exal-dir) independent_exal_dir="$2"; shift 2 ;;
    --final-dir) final_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! [[ "${workers_per_block}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--workers-per-block must be a positive integer." >&2
  exit 2
fi

mkdir -p "${orchestration_dir}"

Rscript --vanilla \
  application/scripts/183_prepare_joint_qdesn_phase154_mcmc_evidence_reconciliation.R \
  --output-dir "${readiness_dir}" \
  --freeze-dir "${freeze_dir}" \
  --fixture-dir "${fixture_dir}" \
  --verify-source-manifests true

readiness_gate="$(Rscript --vanilla - "${readiness_dir}/readiness_assessment.csv" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- read.csv(args[[1L]], stringsAsFactors = FALSE)
cat(x$gate_status[[1L]])
RS
)"
if [[ "${readiness_gate}" != "pass" ]]; then
  echo "Phase154 readiness gate is ${readiness_gate}; refusing launch." >&2
  exit 1
fi

cat > "${orchestration_dir}/launch_config.csv" <<EOF
block_id,model_id,n_cases,n_chains,n_iter,burn,thin,workers,output_dir
joint_al,joint_qdesn_rhs_vb,8,4,4000,1000,4,${workers_per_block},${joint_al_dir}
independent_al,qdesn_rhs_independent_vb,8,4,4000,1000,4,${workers_per_block},${independent_al_dir}
independent_exal,exqdesn_rhs_independent_vb,8,8,8000,2000,4,${workers_per_block},${independent_exal_dir}
EOF

if [[ "${execute}" != "true" ]]; then
  echo "Phase154 readiness passed and launch files were prepared."
  echo "Re-run with --execute to start the three model blocks."
  exit 0
fi

blocks=(joint_al independent_al independent_exal)
models=(joint_qdesn_rhs_vb qdesn_rhs_independent_vb exqdesn_rhs_independent_vb)
outputs=("${joint_al_dir}" "${independent_al_dir}" "${independent_exal_dir}")
chains=(4 4 8)
iters=(4000 4000 8000)
burns=(1000 1000 2000)
offsets=(154100 154200 154300)

for ii in "${!blocks[@]}"; do
  block="${blocks[$ii]}"
  session="joint_qdesn_phase154_${block}_20260730"
  output="${outputs[$ii]}"
  wrapper="${orchestration_dir}/${block}_wrapper.sh"
  log="${orchestration_dir}/${block}.log"
  exit_file="${orchestration_dir}/${block}.exit"
  time_file="${orchestration_dir}/${block}.time"

  if tmux has-session -t "${session}" 2>/dev/null; then
    echo "Refusing duplicate active session: ${session}" >&2
    exit 1
  fi
  if [[ -d "${output}" ]] &&
     [[ -n "$(find "${output}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "Refusing to overwrite non-empty output directory: ${output}" >&2
    exit 1
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
echo "PHASE154_${block}_START=\$(date -Is)"
set +e
/usr/bin/time -v -o $(printf '%q' "${time_file}") \
  Rscript --vanilla application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \
  --output-dir $(printf '%q' "${output}") \
  --phase121-dir $(printf '%q' "${freeze_dir}") \
  --fixture-dir $(printf '%q' "${fixture_dir}") \
  --model-ids $(printf '%q' "${models[$ii]}") \
  --n-chains $(printf '%q' "${chains[$ii]}") \
  --mcmc-n-iter $(printf '%q' "${iters[$ii]}") \
  --mcmc-burn $(printf '%q' "${burns[$ii]}") \
  --mcmc-thin 4 \
  --mcmc-seed-offset $(printf '%q' "${offsets[$ii]}") \
  --chain-seed-stride 1009 \
  --sigma-upper-multiplier 50 \
  --distance-pass 5 \
  --chain-pass 5 \
  --n-cores $(printf '%q' "${workers_per_block}") > $(printf '%q' "${log}") 2>&1
code=\$?
echo "\${code}" > $(printf '%q' "${exit_file}")
echo "PHASE154_${block}_EXIT=\${code} END=\$(date -Is)" >> $(printf '%q' "${log}")
exit "\${code}"
EOF
  chmod +x "${wrapper}"
  rm -f "${exit_file}" "${time_file}"
done

for ii in "${!blocks[@]}"; do
  block="${blocks[$ii]}"
  session="joint_qdesn_phase154_${block}_20260730"
  wrapper="${orchestration_dir}/${block}_wrapper.sh"
  tmux new-session -d -s "${session}" "bash $(printf '%q' "${wrapper}")"
  echo "Launched ${block}: ${session}"
done

watcher="${orchestration_dir}/finalizer_wrapper.sh"
watcher_log="${orchestration_dir}/finalizer.log"
watcher_exit="${orchestration_dir}/finalizer.exit"
watcher_session="joint_qdesn_phase154_finalizer_20260730"
cat > "${watcher}" <<EOF
#!/usr/bin/env bash
set -uo pipefail
cd $(printf '%q' "${repo_root}")
echo "PHASE154_FINALIZER_START=\$(date -Is)"
while true; do
  ready=true
  for block in joint_al independent_al independent_exal; do
    [[ -f $(printf '%q' "${orchestration_dir}")/\${block}.exit ]] || ready=false
  done
  [[ "\${ready}" == "true" ]] && break
  sleep 60
done
code=0
for block in joint_al independent_al independent_exal; do
  block_code=\$(cat $(printf '%q' "${orchestration_dir}")/\${block}.exit)
  if [[ "\${block_code}" -ne 0 ]]; then code="\${block_code}"; fi
done
if [[ "\${code}" -eq 0 ]]; then
  Rscript --vanilla application/scripts/185_finalize_joint_qdesn_phase154_balanced_mcmc.R \
    --output-dir $(printf '%q' "${final_dir}") \
    --readiness-dir $(printf '%q' "${readiness_dir}") \
    --joint-al-dir $(printf '%q' "${joint_al_dir}") \
    --independent-al-dir $(printf '%q' "${independent_al_dir}") \
    --independent-exal-dir $(printf '%q' "${independent_exal_dir}") \
    >> $(printf '%q' "${watcher_log}") 2>&1
  code=\$?
fi
echo "\${code}" > $(printf '%q' "${watcher_exit}")
echo "PHASE154_FINALIZER_EXIT=\${code} END=\$(date -Is)"
exit "\${code}"
EOF
chmod +x "${watcher}"
rm -f "${watcher_exit}"
tmux new-session -d -s "${watcher_session}" \
  "bash $(printf '%q' "${watcher}") 2>&1 | tee $(printf '%q' "${watcher_log}")"
echo "Launched finalizer watcher: ${watcher_session}"
echo "Health: Rscript application/scripts/186_check_joint_qdesn_phase154_balanced_mcmc.R"
