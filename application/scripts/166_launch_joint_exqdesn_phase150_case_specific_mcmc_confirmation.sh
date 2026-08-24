#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "${repo_root}"

freeze_dir="application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727"
mcmc_dir="application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"
phase149_dir="application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726"
readiness_dir="application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726"
fixture_dir="application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
orchestration_dir="application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727_orchestration"
session_name="joint_qdesn_phase150_exal_mcmc_20260727"
n_chains="8"
mcmc_n_iter="8000"
mcmc_burn="2000"
mcmc_thin="4"
mcmc_seed_offset="9500"
chain_seed_stride="100"
sigma_upper_multiplier="50"
distance_pass="5"
chain_pass="5"
n_cores="8"
prepare_only="false"
execute_mode="false"
allow_existing="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --freeze-dir) freeze_dir="$2"; shift 2 ;;
    --mcmc-dir|--output-dir) mcmc_dir="$2"; shift 2 ;;
    --phase149-dir) phase149_dir="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    --n-chains) n_chains="$2"; shift 2 ;;
    --mcmc-n-iter) mcmc_n_iter="$2"; shift 2 ;;
    --mcmc-burn) mcmc_burn="$2"; shift 2 ;;
    --mcmc-thin) mcmc_thin="$2"; shift 2 ;;
    --mcmc-seed-offset) mcmc_seed_offset="$2"; shift 2 ;;
    --chain-seed-stride) chain_seed_stride="$2"; shift 2 ;;
    --sigma-upper-multiplier) sigma_upper_multiplier="$2"; shift 2 ;;
    --distance-pass) distance_pass="$2"; shift 2 ;;
    --chain-pass) chain_pass="$2"; shift 2 ;;
    --n-cores) n_cores="$2"; shift 2 ;;
    --prepare-only) prepare_only="$2"; shift 2 ;;
    --allow-existing) allow_existing="$2"; shift 2 ;;
    --execute) execute_mode="true"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "${orchestration_dir}"

Rscript application/scripts/165_freeze_joint_exqdesn_phase150_case_specific_mcmc_winners.R \
  --output-dir "${freeze_dir}" \
  --phase149-dir "${phase149_dir}" \
  --readiness-dir "${readiness_dir}" \
  --mcmc-dir "${mcmc_dir}" \
  --fixture-dir "${fixture_dir}" \
  --n-chains "${n_chains}" \
  --mcmc-n-iter "${mcmc_n_iter}" \
  --mcmc-burn "${mcmc_burn}" \
  --mcmc-thin "${mcmc_thin}" \
  --mcmc-seed-offset "${mcmc_seed_offset}" \
  --chain-seed-stride "${chain_seed_stride}" \
  --sigma-upper-multiplier "${sigma_upper_multiplier}" \
  --distance-pass "${distance_pass}" \
  --chain-pass "${chain_pass}" \
  --n-cores "${n_cores}"

freeze_gate="$(Rscript --vanilla - "${freeze_dir}" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- utils::read.csv(file.path(args[[1L]], "phase150_freeze_assessment.csv"), stringsAsFactors = FALSE)
cat(x$gate_status[[1L]])
RS
)"
if [[ "${freeze_gate}" == "fail" ]]; then
  echo "Phase150 freeze gate failed; refusing MCMC launch." >&2
  exit 1
fi

if [[ "${prepare_only}" == "true" ]]; then
  echo "Phase150 prepare-only complete; MCMC was not launched."
  exit 0
fi

if [[ "${execute_mode}" != "true" ]]; then
  echo "Phase150 launch prepared. Re-run with --execute to start tmux session ${session_name}."
  exit 0
fi

if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "tmux session already exists: ${session_name}" >&2
  exit 1
fi

if [[ -d "${mcmc_dir}" ]] && [[ "${allow_existing}" != "true" ]] && [[ -n "$(find "${mcmc_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "Refusing to overwrite non-empty MCMC output directory: ${mcmc_dir}" >&2
  exit 1
fi

wrapper="${orchestration_dir}/phase150_mcmc_wrapper.sh"
log="${orchestration_dir}/phase150_mcmc_tmux.log"
time_log="${orchestration_dir}/phase150_mcmc_time.log"
exit_file="${orchestration_dir}/phase150_mcmc.exit"

cat > "${wrapper}" <<EOF
#!/usr/bin/env bash
set -u
cd "$(printf '%q' "${repo_root}")"
echo "PHASE150_MCMC_START=\$(date -Is)"
set +e
/usr/bin/time -v -o "$(printf '%q' "${time_log}")" Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \\
  --output-dir "$(printf '%q' "${mcmc_dir}")" \\
  --phase121-dir "$(printf '%q' "${freeze_dir}")" \\
  --fixture-dir "$(printf '%q' "${fixture_dir}")" \\
  --model-ids "joint_exqdesn_rhs_vb" \\
  --n-chains "$(printf '%q' "${n_chains}")" \\
  --mcmc-n-iter "$(printf '%q' "${mcmc_n_iter}")" \\
  --mcmc-burn "$(printf '%q' "${mcmc_burn}")" \\
  --mcmc-thin "$(printf '%q' "${mcmc_thin}")" \\
  --mcmc-seed-offset "$(printf '%q' "${mcmc_seed_offset}")" \\
  --chain-seed-stride "$(printf '%q' "${chain_seed_stride}")" \\
  --sigma-upper-multiplier "$(printf '%q' "${sigma_upper_multiplier}")" \\
  --distance-pass "$(printf '%q' "${distance_pass}")" \\
  --chain-pass "$(printf '%q' "${chain_pass}")" \\
  --n-cores "$(printf '%q' "${n_cores}")" > "$(printf '%q' "${log}")" 2>&1
code=\$?
echo "\${code}" > "$(printf '%q' "${exit_file}")"
echo "PHASE150_MCMC_EXIT=\${code}"
if [[ "\${code}" -eq 0 ]]; then
  Rscript application/scripts/167_audit_joint_exqdesn_phase150_case_specific_mcmc_confirmation.R \\
    --mcmc-dir "$(printf '%q' "${mcmc_dir}")" \\
    --freeze-dir "$(printf '%q' "${freeze_dir}")" >> "$(printf '%q' "${log}")" 2>&1
  audit_code=\$?
  echo "PHASE150_AUDIT_EXIT=\${audit_code}" >> "$(printf '%q' "${log}")"
  if [[ "\${audit_code}" -ne 0 ]]; then
    echo "\${audit_code}" > "$(printf '%q' "${exit_file}")"
    code="\${audit_code}"
  fi
fi
echo "PHASE150_MCMC_END=\$(date -Is)"
exit "\${code}"
EOF
chmod +x "${wrapper}"

Rscript --vanilla - "${orchestration_dir}" "${freeze_dir}" "${mcmc_dir}" "${wrapper}" "${log}" "${time_log}" "${exit_file}" "${session_name}" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
out_dir <- args[[1L]]
plan <- data.frame(
  session_name = args[[8L]],
  freeze_dir = args[[2L]],
  mcmc_dir = args[[3L]],
  wrapper = args[[4L]],
  log = args[[5L]],
  time_log = args[[6L]],
  exit_file = args[[7L]],
  launch_status = "prepared_for_tmux",
  stringsAsFactors = FALSE
)
utils::write.csv(plan, file.path(out_dir, "phase150_orchestration_plan.csv"), row.names = FALSE)
readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Phase150 case-specific Joint exQDESN MCMC orchestration",
  "",
  "This directory records the background tmux launch wrapper for the Phase150 MCMC confirmation.",
  "The artifact manifest hashes static launch files only; logs are mutable until the job exits.",
  sprintf("- Session: `%s`", args[[8L]]),
  sprintf("- Freeze: `%s`", args[[2L]]),
  sprintf("- MCMC output: `%s`", args[[3L]]),
  sprintf("- Runtime log: `%s`", args[[5L]]),
  sprintf("- Time log: `%s`", args[[6L]]),
  sprintf("- Exit file: `%s`", args[[7L]])
), readme_path, useBytes = TRUE)
manifest_paths <- c(file.path(out_dir, "phase150_orchestration_plan.csv"), args[[4L]], readme_path)
hash_or_na <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  unname(tools::sha256sum(path))
}
manifest <- data.frame(
  label = c("phase150_orchestration_plan", "phase150_mcmc_wrapper", "readme"),
  relative_path = basename(manifest_paths),
  size_bytes = ifelse(file.exists(manifest_paths), as.numeric(file.info(manifest_paths)$size), NA_real_),
  sha256 = vapply(manifest_paths, hash_or_na, character(1L)),
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, file.path(out_dir, "artifact_manifest.csv"), row.names = FALSE)
RS

tmux new-session -d -s "${session_name}" "${wrapper}"
echo "Launched Phase150 MCMC in tmux session ${session_name}"
echo "Log: ${log}"
echo "Output: ${mcmc_dir}"
