#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

readiness_dir="${1:-application/cache/joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726}"
workers="${PHASE149_WORKERS:-12}"
registry="${readiness_dir}/phase149_case_specific_screening_registry.csv"
assessment="${readiness_dir}/phase149_readiness_assessment.csv"
screening_dir="application/cache/joint_qdesn_phase149_case_specific_exal_screening_20260726"
fixture_dir="application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"

Rscript --vanilla - "${assessment}" <<'RS'
args <- commandArgs(TRUE)
x <- utils::read.csv(args[[1L]], stringsAsFactors = FALSE)
if (nrow(x) != 1L || !identical(x$gate_status[[1L]], "pass")) {
  stop("Phase149 launch blocked because readiness gate is not pass.", call. = FALSE)
}
RS

bash application/scripts/123_launch_joint_qdesn_screening_parallel_chunks.sh \
  --registry "${registry}" \
  --canonical-output-dir "${screening_dir}" \
  --fixture-dir "${fixture_dir}" \
  --workers "${workers}" \
  --n-cores-per-worker 1 \
  --run-id phase149_case_specific_exal_20260726 \
  --session-prefix joint_qdesn_phase149_exal \
  --incomplete-only true
