#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Launch or dry-run a Phase 119 case-specific joint QDESN screening shard.

Required input is normally produced by:
  Rscript application/scripts/119_prepare_joint_qdesn_phase119_case_specific_calibration_readiness.R

Options:
  --shard NAME                  Shard name, e.g. exal_high_priority, al_high_priority,
                                high_priority, moderate_priority, context_priority.
  --readiness-dir PATH          Phase 119 readiness artifact directory.
  --screening-output-dir PATH   Phase 119 screening output root.
  --fixture-dir PATH            Joint QDESN simulation fixture directory.
  --phase118-log PATH           Phase 118 log used for clean-exit verification.
  --n-cores N                   Cores passed to the Phase 106 screening runner.
  --session-name NAME           tmux session name.
  --log PATH                    Detached launch log path.
  --skip-phase118-check true|false
                                Skip the Phase 118 EXIT_CODE=0 check.
  --dry-run true|false          Print resolved settings and command without launching.
  --foreground true|false       Run in the current shell instead of detached tmux.
  --help                        Show this message.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
shard="exal_high_priority"
readiness_dir="${repo_root}/application/cache/joint_qdesn_phase119_case_specific_calibration_readiness_20260709"
screening_output_dir="${repo_root}/application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709"
fixture_dir="${repo_root}/application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
phase118_log="${repo_root}/application/cache/joint_qdesn_phase118_exal_tail_screen_20260709_tmux.log"
n_cores="1"
session_name=""
log_path=""
skip_phase118_check="false"
dry_run="false"
foreground="false"

bool_value() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|t|1|yes|y) printf 'true' ;;
    false|f|0|no|n) printf 'false' ;;
    *) echo "Expected boolean value, got '$1'." >&2; exit 2 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shard) shard="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --screening-output-dir) screening_output_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --phase118-log) phase118_log="$2"; shift 2 ;;
    --n-cores) n_cores="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    --log) log_path="$2"; shift 2 ;;
    --skip-phase118-check) skip_phase118_check="$(bool_value "$2")"; shift 2 ;;
    --dry-run) dry_run="$(bool_value "$2")"; shift 2 ;;
    --foreground) foreground="$(bool_value "$2")"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "${repo_root}"

readiness_dir="$(realpath -m "${readiness_dir}")"
screening_output_dir="$(realpath -m "${screening_output_dir}")"
fixture_dir="$(realpath -m "${fixture_dir}")"
phase118_log="$(realpath -m "${phase118_log}")"

case "${shard}" in
  high_priority|exal_high_priority|al_high_priority|moderate_priority|context_priority) ;;
  *) echo "Unknown Phase 119 shard '${shard}'." >&2; exit 2 ;;
esac

if ! [[ "${n_cores}" =~ ^[0-9]+$ ]] || [ "${n_cores}" -lt 1 ]; then
  echo "--n-cores must be a positive integer." >&2
  exit 2
fi

registry_path="${readiness_dir}/phase119_${shard}_registry.csv"
output_dir="${screening_output_dir}/${shard}"

if [ ! -d "${readiness_dir}" ]; then
  echo "Missing readiness directory: ${readiness_dir}" >&2
  exit 2
fi
if [ ! -f "${registry_path}" ]; then
  echo "Missing Phase 119 registry shard: ${registry_path}" >&2
  exit 2
fi
if [ ! -d "${fixture_dir}" ]; then
  echo "Missing fixture directory: ${fixture_dir}" >&2
  exit 2
fi

if [ "${skip_phase118_check}" != "true" ]; then
  if [ ! -f "${phase118_log}" ]; then
    echo "Missing Phase 118 log: ${phase118_log}" >&2
    exit 2
  fi
  if ! grep -Fq "EXIT_CODE=0" "${phase118_log}"; then
    echo "Phase 118 log does not contain EXIT_CODE=0: ${phase118_log}" >&2
    exit 2
  fi
fi

mkdir -p "${screening_output_dir}" "$(dirname "${log_path:-${screening_output_dir}/.placeholder}")"

if [ -z "${session_name}" ]; then
  session_name="joint_qdesn_phase119_${shard}_$(date +%Y%m%d_%H%M%S)"
fi
if [ -z "${log_path}" ]; then
  log_path="${screening_output_dir}/phase119_${shard}_$(date +%Y%m%d_%H%M%S).log"
fi
log_path="$(realpath -m "${log_path}")"
mkdir -p "$(dirname "${log_path}")" "${output_dir}"

run_command=(
  Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R
  --registry "${registry_path}"
  --output-dir "${output_dir}"
  --fixture-dir "${fixture_dir}"
  --n-cores "${n_cores}"
  --reuse-completed true
  --audit-only false
)

printf 'repo_root=%s\n' "${repo_root}"
printf 'shard=%s\n' "${shard}"
printf 'registry=%s\n' "${registry_path}"
printf 'output_dir=%s\n' "${output_dir}"
printf 'fixture_dir=%s\n' "${fixture_dir}"
printf 'phase118_log=%s\n' "${phase118_log}"
printf 'session_name=%s\n' "${session_name}"
printf 'log=%s\n' "${log_path}"
printf 'command='
printf '%q ' "${run_command[@]}"
printf '\n'

if [ "${dry_run}" = "true" ]; then
  exit 0
fi

runner="$(mktemp "${screening_output_dir}/phase119_${shard}_runner_XXXXXX.sh")"
cat > "${runner}" <<RUNNER
#!/usr/bin/env bash
set -u
cd "$(printf '%q' "${repo_root}")" || exit 1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
{
  echo "START \$(date -Is)"
  printf 'SHARD=%s\n' "$(printf '%q' "${shard}")"
  printf 'REGISTRY=%s\n' "$(printf '%q' "${registry_path}")"
  printf 'OUTPUT_DIR=%s\n' "$(printf '%q' "${output_dir}")"
  printf 'FIXTURE_DIR=%s\n' "$(printf '%q' "${fixture_dir}")"
  $(printf '%q ' "${run_command[@]}")
  ec=\$?
  echo "EXIT_CODE=\${ec}"
  echo "END \$(date -Is)"
  exit "\${ec}"
} > "$(printf '%q' "${log_path}")" 2>&1
RUNNER
chmod +x "${runner}"

if [ "${foreground}" = "true" ]; then
  bash "${runner}"
else
  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is required for detached launch; rerun with --foreground true." >&2
    exit 2
  fi
  if tmux has-session -t "${session_name}" 2>/dev/null; then
    echo "tmux session already exists: ${session_name}" >&2
    exit 2
  fi
  tmux new-session -d -s "${session_name}" "bash $(printf '%q' "${runner}")"
  echo "Launched tmux session: ${session_name}"
fi
