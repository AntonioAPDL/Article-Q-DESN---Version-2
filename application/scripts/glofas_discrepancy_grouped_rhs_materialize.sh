#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 CAMPAIGN_YAML OUTPUT_ROOT [AUTHORIZE_LAUNCH]" >&2
  exit 2
fi

CAMPAIGN_YAML="$1"
OUTPUT_ROOT="$2"
AUTHORIZE_LAUNCH="${3:-false}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$CAMPAIGN_YAML" != /* ]]; then CAMPAIGN_YAML="${REPO_ROOT}/${CAMPAIGN_YAML}"; fi
if [[ "$OUTPUT_ROOT" != /* ]]; then OUTPUT_ROOT="${REPO_ROOT}/${OUTPUT_ROOT}"; fi
CAMPAIGN_YAML="$(readlink -f "$CAMPAIGN_YAML")"
OUTPUT_ROOT="$(readlink -m "$OUTPUT_ROOT")"
OWNED_ROOT="$(readlink -m "${REPO_ROOT}/local_trackers/runtime_configs")"
case "$OUTPUT_ROOT" in
  "$OWNED_ROOT"/*) ;;
  *) echo "Refusing materialization outside the task-owned runtime tree: $OUTPUT_ROOT" >&2; exit 64 ;;
esac
if [[ -d "$OUTPUT_ROOT" ]] && [[ -n "$(find "$OUTPUT_ROOT" -mindepth 1 -print -quit)" ]]; then
  echo "Refusing to materialize into a nonempty output root: $OUTPUT_ROOT" >&2
  exit 66
fi
if [[ "${AUTHORIZE_LAUNCH,,}" == "true" ]]; then
  BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  UPSTREAM="$(git -C "$REPO_ROOT" rev-parse '@{upstream}')"
  case "$BRANCH" in
    main|overleaf/article-snapshot|overleaf-direct/main)
      echo "Authorized materialization requires a dedicated task branch." >&2
      exit 67
      ;;
  esac
  if [[ "$HEAD" != "$UPSTREAM" ]] ||
     ! git -C "$REPO_ROOT" diff --quiet --ignore-submodules -- ||
     ! git -C "$REPO_ROOT" diff --cached --quiet --ignore-submodules -- ||
     [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]]; then
    echo "Authorized materialization requires a clean task branch synchronized with upstream." >&2
    exit 68
  fi
fi

IFS=$'\t' read -r BACKEND THREADS LIBRARY LIBRARY_SHA256 < <(
  Rscript - "$CAMPAIGN_YAML" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
if (!requireNamespace("yaml", quietly = TRUE)) stop("Package 'yaml' is required.")
x <- yaml::read_yaml(args[[1L]])
values <- c(
  x$execution$numerical_backend,
  x$execution$backend_threads,
  x$execution$backend_library,
  x$execution$backend_library_sha256
)
cat(paste(values, collapse = "\t"), "\n", sep = "")
RS
)
if [[ "$BACKEND" != "openblas_serial" || "$THREADS" != "1" ]]; then
  echo "Grouped-RHS materialization requires the reviewed serial OpenBLAS target." >&2
  exit 65
fi

TMP_DIR="$(mktemp -d /tmp/glofas_grouped_rhs_materialize.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
SOURCE_SNAPSHOT="${TMP_DIR}/source_future_snapshot.rds"
SOURCE_EXECUTION="${TMP_DIR}/source_backend_execution.json"
TARGET_EXECUTION="${TMP_DIR}/target_backend_execution.json"

cd "$REPO_ROOT"
python3 application/scripts/glofas_numerical_backend_exec.py \
  --backend bundled_rblas \
  --threads 1 \
  --manifest "$SOURCE_EXECUTION" \
  -- Rscript application/scripts/glofas_discrepancy_grouped_rhs_warm_source_snapshot.R \
    --campaign "$CAMPAIGN_YAML" \
    --output "$SOURCE_SNAPSHOT"

SOURCE_SNAPSHOT_SHA256="$(sha256sum "$SOURCE_SNAPSHOT" | awk '{print tolower($1)}')"
python3 application/scripts/glofas_numerical_backend_exec.py \
  --backend "$BACKEND" \
  --threads "$THREADS" \
  --library "$LIBRARY" \
  --sha256 "$LIBRARY_SHA256" \
  --manifest "$TARGET_EXECUTION" \
  -- Rscript application/scripts/glofas_discrepancy_grouped_rhs_prepare.R \
    --campaign "$CAMPAIGN_YAML" \
    --output_root "$OUTPUT_ROOT" \
    --authorize_launch "$AUTHORIZE_LAUNCH" \
    --source_future_snapshot "$SOURCE_SNAPSHOT" \
    --source_future_snapshot_sha256 "$SOURCE_SNAPSHOT_SHA256"

mkdir -p "${OUTPUT_ROOT}/preparation"
cp "$SOURCE_EXECUTION" "${OUTPUT_ROOT}/preparation/source_backend_execution.json"
cp "$TARGET_EXECUTION" "${OUTPUT_ROOT}/preparation/target_backend_execution.json"
printf '%s  %s\n' \
  "$(sha256sum "${OUTPUT_ROOT}/preparation/source_backend_execution.json" | awk '{print tolower($1)}')" \
  "preparation/source_backend_execution.json" \
  > "${OUTPUT_ROOT}/preparation/backend_execution_sha256.txt"
printf '%s  %s\n' \
  "$(sha256sum "${OUTPUT_ROOT}/preparation/target_backend_execution.json" | awk '{print tolower($1)}')" \
  "preparation/target_backend_execution.json" \
  >> "${OUTPUT_ROOT}/preparation/backend_execution_sha256.txt"

echo "Materialized grouped-RHS campaign with a cross-backend numerical-design certificate at: $OUTPUT_ROOT"
