#!/usr/bin/env bash
# Exact bounded process envelope for the purpose-bound native global-path
# reader. This script does not choose an operation; the signed purpose does.
set -euo pipefail

if [[ ${1:-} == "--help" ]]; then
  echo "Usage: scripts/launch_glofas_global_path_native.sh PURPOSE.json SHA256"
  exit 0
fi
[[ $# -eq 2 ]] || { echo "exact purpose and SHA256 are required" >&2; exit 2; }
PURPOSE=$1
SHA256=$2
[[ $SHA256 =~ ^[a-f0-9]{64}$ ]] || { echo "invalid purpose SHA256" >&2; exit 2; }
echo "$SHA256  $PURPOSE" | /usr/bin/sha256sum -c - >/dev/null

mapfile -t BOUNDS < <(/usr/bin/python3 -I -B - "$PURPOSE" <<'PY'
import json, os, sys
path = os.path.realpath(sys.argv[1])
with open(path, "r", encoding="utf-8") as stream:
    value = json.load(stream)
limits = value["limits"]
items = (
    value["metadata_scratch_root"],
    limits["logical_cpu"], limits["cpu_seconds"], limits["wall_seconds"],
    limits["memory_bytes"], limits["output_bytes"],
)
if not isinstance(items[0], str) or not items[0].startswith("/tmp/"):
    raise SystemExit("invalid scratch root")
if not all(isinstance(x, int) and x > 0 for x in items[2:]):
    raise SystemExit("invalid positive limits")
if not isinstance(items[1], int) or items[1] < 0 or items[1] > 63:
    raise SystemExit("invalid logical CPU")
print(*items, sep="\n")
PY
)
[[ ${#BOUNDS[@]} -eq 6 ]] || { echo "incomplete purpose limits" >&2; exit 2; }
SCRATCH=${BOUNDS[0]}
CPU=${BOUNDS[1]}
CPU_SECONDS=${BOUNDS[2]}
WALL_SECONDS=${BOUNDS[3]}
MEMORY_BYTES=${BOUNDS[4]}
OUTPUT_BYTES=${BOUNDS[5]}
[[ -d $SCRATCH ]] || { echo "private scratch root is absent" >&2; exit 2; }
(( WALL_SECONDS >= 10 )) || { echo "wall limit is too short" >&2; exit 2; }

export TMPDIR=$SCRATCH
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
exec /usr/bin/taskset -c "$CPU" \
  /usr/bin/timeout --signal=TERM --kill-after=1s "$((WALL_SECONDS - 1))s" \
  /usr/bin/prlimit --cpu="$CPU_SECONDS" --as="$MEMORY_BYTES" \
    --fsize="$OUTPUT_BYTES" -- \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  scripts/glofas_global_path_native_reader.R \
  --contract "$PURPOSE" --sha256 "$SHA256" --execute
