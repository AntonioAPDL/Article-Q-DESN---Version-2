#!/usr/bin/env python3
"""Build the hash-pinned R82 structured-exAL initialization repair runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R80_MANIFEST = DATA / (
    "runtime_libraries/exdqlm_pricefm_r80_failure_diagnostics/"
    "pricefm_stage_r80_failure_diagnostics_manifest.json"
)
SOURCE_ROOT = DATA / "runtime_sources/exdqlm_pricefm_r82_structured_init_repair"
LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair"
MANIFEST_NAME = "pricefm_stage_r82_structured_init_repair_manifest.json"
BASE_SHA = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
R80_STATIC_SHA = "3295f1b94090aeaf91113e8a3990efae9b9df849a5592d41369d9c26d2704460"
R80_STRUCTURED_SHA = "784510643276bfbbbe80f8449f98a825dcefdd8904f336a7c07ae85cf30e00d4"
VERSION = "1.1.1.9004"
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init"
)


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    if value.lower() in {"1", "true", "yes"}:
        return True
    if value.lower() in {"0", "false", "no"}:
        return False
    raise argparse.ArgumentTypeError(value)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r80-manifest", type=Path, default=R80_MANIFEST)
    p.add_argument("--source-root", type=Path, default=SOURCE_ROOT)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--install", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one R82 repair anchor, observed {count}: {old[:80]}")
    return text.replace(old, new)


def repair(source: Path) -> None:
    description = source / "DESCRIPTION"
    text = description.read_text()
    text = replace_once(text, "Version: 1.1.1.9003", f"Version: {VERSION}")
    text = replace_once(
        text,
        "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics",
        f"Config/PriceFM/repair: {REPAIR}",
    )
    description.write_text(text)

    static = source / "R/exalStaticLDVB.R"
    text = static.read_text()
    old_init = '''  # Initial xi from the Delta approximation. The static exAL VB path is
  # intentionally deterministic; MC xi fallback is not part of the production
  # algorithm anymore.
  xis_eval <- compute_xi(
    eta_hat,
    ell_hat,
    Sig_eta_ell
  )
  xis <- xis_eval$value
'''
    new_init = '''  sigmagam_cfg <- ld_ctrl$sigmagam %||% .exal_sigmagam_vb_controls(NULL)
  sigmagam_cfg <- .exal_clamp_vb_sigmagam_control(sigmagam_cfg, max_iter = max_iter)
  structured_sigmagam <- identical(sigmagam_cfg$factorization, "structured")

  # A Gaussian delta correction is not valid at gamma = 0 because the exAL
  # lambda term contains abs(gamma).  In particular, its numerical curvature
  # can make the initial likelihood precision negative.  A point-mass plug-in
  # is a valid CAVI initialization; the first active block update replaces it
  # with the exact structured q(gamma)q(sigma|gamma) grid/GIG moments.
  sigmagam_initialization <- if (isTRUE(structured_sigmagam)) {
    "plugin_at_warm_start_before_structured_update"
  } else {
    "laplace_delta"
  }
  initial_xi_covariance <- if (isTRUE(structured_sigmagam)) matrix(0, 2L, 2L) else Sig_eta_ell
  xis_eval <- compute_xi(eta_hat, ell_hat, initial_xi_covariance)
  xis <- xis_eval$value
  initial_xis <- xis
'''
    text = replace_once(text, old_init, new_init)
    duplicate = '''  sigmagam_cfg <- ld_ctrl$sigmagam %||% .exal_sigmagam_vb_controls(NULL)
  sigmagam_cfg <- .exal_clamp_vb_sigmagam_control(sigmagam_cfg, max_iter = max_iter)
  structured_sigmagam <- identical(sigmagam_cfg$factorization, "structured")
'''
    if text.count(duplicate) != 2:
        raise RuntimeError("R82 expected the relocated and original sigmagam control blocks")
    prefix, suffix = text.rsplit(duplicate, 1)
    text = prefix + suffix
    text = replace_once(
        text,
        "      sigmagam = sigmagam_cfg,\n      sigmagam_required_postwarmup_updates",
        "      sigmagam = sigmagam_cfg,\n"
        "      sigmagam_initialization = sigmagam_initialization,\n"
        "      sigmagam_initial_xi = initial_xis,\n"
        "      sigmagam_required_postwarmup_updates",
    )
    static.write_text(text)


def probe(library: Path) -> dict[str, Any]:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
desc <- utils::packageDescription("exdqlm", lib.loc = lib)
invisible(loadNamespace("exdqlm", lib.loc = lib))
set.seed(82)
n <- 80L
X <- cbind(1, matrix(stats::rnorm(n * 3L), nrow = n))
y <- as.numeric(X %*% c(0.2, -0.1, 0.15, 0.05) + stats::rnorm(n, sd = 0.2))
profile <- getExportedValue("exdqlm", "exal_make_vb_sigmagam_control")(
  factorization = "structured", structured_grid_size = 21L,
  structured_span_sd = 4, freeze_warmup_iters = 0L,
  min_postwarmup_updates = 1L
)
control <- getExportedValue("exdqlm", "exal_make_vb_control")(
  max_iter = 2L, tol = 1e-4, n_samp_xi = 5L,
  verbose = FALSE, sigmagam = profile
)
fit <- getExportedValue("exdqlm", "exalStaticLDVB")(
  y = y, X = X, p0 = 0.25, beta_prior = "rhs_ns",
  beta_prior_controls = list(tau0 = 0.001, init_tau = 1,
    freeze_tau_iters = 2L, freeze_tau_warmup_iters = 2L,
    shrink_intercept = FALSE),
  init = list(beta = rep(0, ncol(X)), sigma = 0.2, gamma = 0),
  dqlm.ind = FALSE, n.samp = 5L, vb_control = control, verbose = FALSE
)
initial <- fit$misc$sigmagam_initial_xi
cat(jsonlite::toJSON(list(
  version = as.character(desc$Version),
  repair = as.character(desc[["Config/PriceFM/repair"]]),
  initialization = fit$misc$sigmagam_initialization,
  xi1 = initial$xi1, xi_lambda = initial$xi_lambda,
  xi_lambda2 = initial$xi_lambda2,
  trace_finite = all(is.finite(as.matrix(fit$diagnostics$vb_trace[, c(
    "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"
  )])))
), auto_unbox = TRUE))
'''
    result = json.loads(
        subprocess.check_output(["Rscript", "-e", code, str(library)], text=True)
    )
    expected = "plugin_at_warm_start_before_structured_update"
    if (
        result.get("version") != VERSION
        or result.get("repair") != REPAIR
        or result.get("initialization") != expected
        or not result.get("trace_finite")
        or not float(result.get("xi1", -1)) > 0
        or not float(result.get("xi_lambda", -1)) >= 0
        or not float(result.get("xi_lambda2", -1)) >= 0
    ):
        raise RuntimeError(f"R82 structured initialization probe failed: {result}")
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    prior = json.loads(args.r80_manifest.read_text())
    if prior.get("status") != "installed_diagnostic_runtime":
        raise RuntimeError("R82 must derive from the installed R80 diagnostic runtime")
    if prior.get("base_tarball_sha256") != BASE_SHA:
        raise RuntimeError("R80 runtime does not derive from exact CRAN exdqlm 1.1.1")
    old_source = Path(prior["source"])
    expected = {
        "R/exalStaticLDVB.R": R80_STATIC_SHA,
        "R/exal_sigmagam_structured.R": R80_STRUCTURED_SHA,
    }
    observed = {name: sha256(old_source / name) for name in expected}
    if observed != expected:
        raise RuntimeError(f"R80 source hashes changed: {observed}")

    source_root, library = args.source_root.resolve(), args.library.resolve()
    manifest_path = library / MANIFEST_NAME
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        result = json.loads(manifest_path.read_text())
        result["probe"] = probe(library)
        return result
    if source_root.exists():
        if not args.force:
            raise FileExistsError(source_root)
        shutil.rmtree(source_root)
    if library.exists():
        if not args.force:
            raise FileExistsError(library)
        shutil.rmtree(library)

    source_root.mkdir(parents=True)
    source = source_root / "exdqlm"
    shutil.copytree(old_source, source)
    repair(source)
    payload: dict[str, Any] = {
        "status": "materialized_not_installed",
        "version": VERSION,
        "repair": REPAIR,
        "scientific_role": "bounded_structured_exal_initialization_repair",
        "base_tarball_sha256": BASE_SHA,
        "r80_manifest": str(args.r80_manifest.resolve()),
        "r80_manifest_sha256": sha256(args.r80_manifest),
        "source": str(source),
        "source_hashes": {
            str(path.relative_to(source)): sha256(path)
            for path in (
                source / "DESCRIPTION",
                source / "R/exal_sigmagam_structured.R",
                source / "R/exalStaticLDVB.R",
            )
        },
        "library": str(library),
        "launch_authorized": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    if args.install:
        library.mkdir(parents=True)
        log = library / "install.log"
        with log.open("w") as handle:
            subprocess.run(
                ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(source)],
                check=True,
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
        payload.update(
            status="installed_structured_initialization_repair_runtime",
            install_log=str(log),
            install_log_sha256=sha256(log),
            probe=probe(library),
        )
        manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    else:
        (source_root / MANIFEST_NAME).write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n"
        )
    return payload


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
