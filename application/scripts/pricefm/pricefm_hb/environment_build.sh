#!/bin/bash
# Run only inside the separately admitted one-CPU HB Slurm compute allocation.
set -euo pipefail
if [[ ! ${SLURM_JOB_ID:-} =~ ^[0-9]+$ || ${SLURM_CPUS_PER_TASK:-} != 1 ]]; then
  echo 'environment build requires an admitted one-CPU Slurm compute allocation' >&2
  exit 2
fi
if ! type module >/dev/null 2>&1; then
  set +u
  source /etc/profile
  set -u
fi
module purge
module load ohpc miniconda3/3.13
conda_root=${CONDA_ROOT:-/software/utils/miniconda3/3.13}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
exec "$conda_root/bin/python" -B "$script_dir/environment.py" build \
  --conda-executable "$conda_root/bin/conda" "$@"
