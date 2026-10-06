#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || ( "$1" != --test && "$1" != --reproduce ) ]]; then
  printf '%s\n' 'Usage: run_audit.sh --test EXECUTION_WORKTREE RUNTIME_ROOT' \
    '       run_audit.sh --reproduce EXECUTION_WORKTREE RUNTIME_ROOT NEW_OUTPUT_ROOT' >&2
  exit 2
fi
mode=$1
if [[ "$mode" == --test && $# != 3 ]]; then
  printf '%s\n' 'Test mode accepts exactly an execution worktree and runtime root.' >&2
  exit 2
fi
execution=$(realpath "$2")
runtime=$(realpath "$3")
package=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
expected=199ed8f0bb7a947c0a51800c466f9c458f25f238
observed=$(git -C "$execution" rev-parse HEAD)
[[ "$observed" == "$expected" ]] || { printf '%s\n' 'Execution HEAD differs from the frozen experiment.' >&2; exit 1; }
[[ -f "$runtime/COMPLETE" ]] || { printf '%s\n' 'Runtime is not complete.' >&2; exit 1; }

output=
if [[ "$mode" == --reproduce ]]; then
  [[ $# == 4 ]] || { printf '%s\n' 'Full reproduction requires a new output root.' >&2; exit 2; }
  output=$(realpath -m "$4")
  [[ ! -e "$output" ]] || { printf '%s\n' 'Output already exists; refusing overwrite.' >&2; exit 1; }
  [[ "$output" != "$runtime" && "$output" != "$runtime/"* ]] || {
    printf '%s\n' 'Do not write analysis inside protected runtime.' >&2; exit 1;
  }
fi

sidecar="$execution/local_trackers/joint_score_width_audit_20261006"
mkdir -p "$sidecar"
for file in "$package"/*.R; do
  destination="$sidecar/$(basename "$file")"
  if [[ -e "$destination" ]]; then
    cmp -s "$file" "$destination" || {
      printf 'Audit script mismatch; no overwrite: %s\n' "$destination" >&2
      exit 1
    }
  else
    cp -p "$file" "$destination"
  fi
done

Rscript=${RSCRIPT_BIN:-/data/jaguir26/local/opt/R/4.6.0/bin/Rscript}
[[ -x "$Rscript" ]] || { printf '%s\n' 'Pinned Rscript not found.' >&2; exit 1; }
cd "$execution"
env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  JOINT_AUDIT_PACKAGE="$package" JOINT_AUDIT_RUNTIME="$runtime" \
  JOINT_AUDIT_OUTPUT="$output" JOINT_AUDIT_MODE="$mode" \
  "$Rscript" --vanilla -e '
    source("application/scripts/_joint_qdesn_recursive_mean_forecast_bootstrap.R")
    source("application/R/joint_qdesn_fixed_backbone_prior_screen.R")
    runtime <- Sys.getenv("JOINT_AUDIT_RUNTIME")
    package <- Sys.getenv("JOINT_AUDIT_PACKAGE")
    output <- Sys.getenv("JOINT_AUDIT_OUTPUT")
    stopifnot(getRversion() == "4.6.0")
    app_joint_prior_verify_freeze(runtime)
    for (file in c("audit_and_plot.R", "loss_sensitivity.R", "common_design_action.R",
      "readout_component_audit.R", "summarize_audit.R")) source(file.path(package, file))
    source(file.path(package, "test_audit.R"))
    source(file.path(package, "test_loss_sensitivity.R"))
    b <- list(lambda2 = 1, tau2 = 1, zeta2 = 1)
    V <- solve(as.matrix(app_joint_qvp_build_prior_precision(7, 1, b, b)$P_beta))
    stopifnot(max(abs(V - outer(1:7, 1:7, pmin) / 2)) < 1e-10)
    cat("PASS: frozen source and anchor/increment prior covariance.\n")
    if (Sys.getenv("JOINT_AUDIT_MODE") == "--reproduce") {
      options(bitmapType = "cairo")
      joint_width_main(runtime, file.path(output, "results"))
      joint_width_tables(file.path(output, "results"), file.path(output, "tables"))
      joint_width_sensitivity_main(runtime, file.path(output, "loss_sensitivity"))
      joint_width_common_action(runtime, file.path(output, "common_design"))
      joint_width_components(runtime, file.path(output, "components"))
    }
    cat("JOINT_AUDIT_ENTRYPOINT_COMPLETE\n")
  '
