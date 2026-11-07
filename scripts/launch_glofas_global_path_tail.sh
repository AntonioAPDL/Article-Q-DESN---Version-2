#!/usr/bin/env bash
# Exact one-core process envelope for a purpose-bound AL-tail diagnostic.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "exact purpose and SHA256 are required" >&2; exit 2; }
PURPOSE=$1
SHA256=$2
[[ $SHA256 =~ ^[a-f0-9]{64}$ ]] || { echo "invalid purpose SHA256" >&2; exit 2; }
echo "$SHA256  $PURPOSE" | /usr/bin/sha256sum -c - >/dev/null
mapfile -t BOUNDS < <(/usr/bin/python3 -I -B - "$PURPOSE" <<'PY'
import json, os, sys
with open(os.path.realpath(sys.argv[1]), encoding="utf-8") as stream:
    value = json.load(stream)
limits = value["limits"]
print(value["metadata_scratch_root"], limits["logical_cpu"],
      limits["cpu_seconds"], limits["wall_seconds"],
      limits["memory_bytes"], limits["output_bytes"], sep="\n")
PY
)
[[ ${#BOUNDS[@]} -eq 6 ]] || { echo "incomplete purpose limits" >&2; exit 2; }
SCRATCH=${BOUNDS[0]}; CPU=${BOUNDS[1]}; CPU_SECONDS=${BOUNDS[2]}
WALL_SECONDS=${BOUNDS[3]}; MEMORY_BYTES=${BOUNDS[4]}; OUTPUT_BYTES=${BOUNDS[5]}
[[ -d $SCRATCH ]] || { echo "private scratch root is absent" >&2; exit 2; }
export TMPDIR=$SCRATCH OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
exec /usr/bin/taskset -c "$CPU" \
  /usr/bin/timeout --signal=TERM --kill-after=1s "$((WALL_SECONDS - 1))s" \
  /usr/bin/prlimit --cpu="$CPU_SECONDS" --as="$MEMORY_BYTES" \
    --fsize="$OUTPUT_BYTES" -- \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/glofas_global_path_tail_reader.R \
  --contract "$PURPOSE" --sha256 "$SHA256" --execute
