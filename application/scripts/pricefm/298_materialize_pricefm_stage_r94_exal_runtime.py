#!/usr/bin/env python3
"""Build the hash-pinned R94 coherent AL-to-exAL initialization runtime."""

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
R82_MANIFEST = DATA / (
    "runtime_libraries/exdqlm_pricefm_r82_structured_init_repair/"
    "pricefm_stage_r82_structured_init_repair_manifest.json"
)
SOURCE_ROOT = DATA / "runtime_sources/exdqlm_pricefm_r94_coherent_exal_init"
LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
MANIFEST_NAME = "pricefm_stage_r94_coherent_exal_init_manifest.json"
BASE_SHA = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
R82_DESCRIPTION_SHA = "20f4292ee640aec942eaa4e2fdf6c911ea4af26076a86f34e571d5637790a229"
R82_STATIC_SHA = "2da85327df6cb9a616024f27cc49886280ae43564de76f816c2ad2f50cf1d90b"
R82_STRUCTURED_SHA = "784510643276bfbbbe80f8449f98a825dcefdd8904f336a7c07ae85cf30e00d4"
VERSION = "1.1.1.9005"
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
WARM_START_MODE = "al_qbeta_rhs_latent_first"


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
    p.add_argument("--r82-manifest", type=Path, default=R82_MANIFEST)
    p.add_argument("--source-root", type=Path, default=SOURCE_ROOT)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--install", type=parse_bool, default=True)
    p.add_argument("--force", action="store_true")
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
        raise RuntimeError(f"Expected exactly one R94 repair anchor, observed {count}: {old[:90]}")
    return text.replace(old, new)


def prepare_source(source: Path, destination: Path) -> None:
    shutil.copytree(source, destination)


def patch_source(source: Path) -> None:
    description = source / "DESCRIPTION"
    text = description.read_text()
    text = replace_once(text, "Version: 1.1.1.9004", f"Version: {VERSION}")
    old_repair = (
        "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG-plus-"
        "failure-diagnostics-plus-structured-plugin-init"
    )
    text = replace_once(text, old_repair, f"Config/PriceFM/repair: {REPAIR}")
    description.write_text(text)

    static = source / "R/exalStaticLDVB.R"
    text = static.read_text()
    old_beta_init = '''  m_beta  <- if (is.null(init$beta)) rep(0, p) else as.numeric(init$beta)
  V_beta  <- V0
  sigma0  <- ld_setup$sigma0
  gamma0  <- ld_setup$gamma0
  beta_state <- beta_prior_obj$init_vb()
'''
    new_beta_init = '''  m_beta  <- if (is.null(init$beta)) rep(0, p) else as.numeric(init$beta)
  warm_start_mode <- as.character(init$warm_start_mode %||% "legacy")[1L]
  coherent_al_init <- identical(warm_start_mode, "al_qbeta_rhs_latent_first")
  V_beta <- V0
  beta_covariance_source <- "prior_V0"
  if (isTRUE(coherent_al_init) && !is.null(init$beta_cov_diag)) {
    beta_cov_diag <- as.numeric(init$beta_cov_diag)
    if (length(beta_cov_diag) != p || any(!is.finite(beta_cov_diag)) ||
        any(beta_cov_diag <= 0)) {
      stop("coherent AL initialization requires p finite positive beta covariance entries")
    }
    V_beta <- diag(beta_cov_diag, nrow = p, ncol = p)
    beta_covariance_source <- "al_beta_cov_diag"
  }
  sigma0  <- ld_setup$sigma0
  gamma0  <- ld_setup$gamma0
  beta_state <- beta_prior_obj$init_vb()
  if (isTRUE(coherent_al_init)) {
    beta_state <- beta_prior_obj$update_vb(
      beta_state,
      list(m = as.numeric(m_beta), V = V_beta)
    )
    # The warm-start update initializes local RHS moments but is not a model
    # iteration. Preserve the original freeze/update schedule for iteration 1.
    beta_state$iter <- 0L
    beta_state$freeze_tau <- FALSE
    beta_state$update_tau_only <- FALSE
    beta_state$tau_update_count <- 0L
    beta_state$has_post_warmup_tau_update <- FALSE
    beta_state$last_schedule <- list()
  }
'''
    text = replace_once(text, old_beta_init, new_beta_init)

    old_latent_anchor = '''  initial_xis <- xis
  elbo_trace <- numeric(0)
'''
    new_latent_anchor = '''  initial_xis <- xis
  latent_first_initialized <- FALSE
  if (isTRUE(coherent_al_init)) {
    # Complete the AL warm start before the first q(beta) update.  R82 only
    # imported the coefficient mean; its generic q(v), q(s), covariance, and
    # RHS states made the first coefficient transition a scale-dependent jump.
    xb_init <- drop(X %*% m_beta)
    t_init <- y - xb_init
    q_init <- rowSums((X %*% V_beta) * X)
    psi_init <- max(xis$xi_A2 + 2 * xis$xi_siginv, 1e-12)
    chi_init <- xis$xi1 * (t_init^2 + q_init) -
      2 * xis$xi_lambda * (y * E_s) +
      xis$xi_lambda2 * E_s2 +
      2 * xis$xi_lambda * (xb_init * E_s)
    chi_init <- pmax(chi_init, 1e-12)
    E_v <- gig_moment(k = 0.5, chi = chi_init, psi = psi_init, r = 1)
    E_inv_v <- gig_moment(k = 0.5, chi = chi_init, psi = psi_init, r = -1)
    qs_tau2 <- 1 / (1 + xis$xi_lambda2 * E_inv_v)
    qs_mu <- qs_tau2 * (xis$xi_lambda * (E_inv_v * t_init) - xis$zeta_lam)
    s_init <- tn_moments(qs_mu, qs_tau2)
    E_s <- s_init$Es
    E_s2 <- s_init$Es2
    latent_first_initialized <- TRUE
  }
  elbo_trace <- numeric(0)
'''
    text = replace_once(text, old_latent_anchor, new_latent_anchor)
    text = replace_once(
        text,
        "  delta_beta <- numeric(0)\n  delta_sigma <- numeric(0)",
        "  delta_beta <- numeric(0)\n"
        "  delta_beta_relative <- numeric(0)\n"
        "  delta_prediction_scaled <- numeric(0)\n"
        "  delta_sigma <- numeric(0)",
    )
    text = replace_once(
        text,
        "    d_beta <- max(abs(m_beta_new - prev_m_beta))\n"
        "    d_sigma <- abs(sigma_cur - sigma_prev)",
        "    d_beta <- max(abs(m_beta_new - prev_m_beta))\n"
        "    d_beta_relative <- d_beta / max(1, max(abs(prev_m_beta)))\n"
        "    d_prediction_scaled <- sqrt(mean(drop(X %*% (m_beta_new - prev_m_beta))^2)) /\n"
        "      max(ld_setup$y_scale, sqrt(.Machine$double.eps))\n"
        "    d_sigma <- abs(sigma_cur - sigma_prev)",
    )
    text = replace_once(
        text,
        "    delta_beta <- c(delta_beta, d_beta)\n    delta_sigma <- c(delta_sigma, d_sigma)",
        "    delta_beta <- c(delta_beta, d_beta)\n"
        "    delta_beta_relative <- c(delta_beta_relative, d_beta_relative)\n"
        "    delta_prediction_scaled <- c(delta_prediction_scaled, d_prediction_scaled)\n"
        "    delta_sigma <- c(delta_sigma, d_sigma)",
    )
    text = replace_once(
        text,
        "      sigmagam_initial_xi = initial_xis,\n"
        "      sigmagam_required_postwarmup_updates",
        "      sigmagam_initial_xi = initial_xis,\n"
        "      warm_start_mode = warm_start_mode,\n"
        "      coherent_al_init = coherent_al_init,\n"
        "      beta_covariance_source = beta_covariance_source,\n"
        "      latent_first_initialized = latent_first_initialized,\n"
        "      sigmagam_required_postwarmup_updates",
    )
    text = replace_once(
        text,
        "          delta_state = if (length(delta_beta)) utils::tail(delta_beta, 1L) else NA_real_,\n"
        "          delta_sigma",
        "          delta_state = if (length(delta_beta)) utils::tail(delta_beta, 1L) else NA_real_,\n"
        "          delta_state_relative = if (length(delta_beta_relative)) utils::tail(delta_beta_relative, 1L) else NA_real_,\n"
        "          delta_prediction_scaled = if (length(delta_prediction_scaled)) utils::tail(delta_prediction_scaled, 1L) else NA_real_,\n"
        "          delta_sigma",
    )
    text = replace_once(
        text,
        "        state = delta_beta,\n        sigma = delta_sigma,",
        "        state = delta_beta,\n"
        "        state_relative = delta_beta_relative,\n"
        "        prediction_scaled = delta_prediction_scaled,\n"
        "        sigma = delta_sigma,",
    )
    static.write_text(text)


def probe(library: Path) -> dict[str, Any]:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
desc <- utils::packageDescription("exdqlm", lib.loc = lib)
invisible(loadNamespace("exdqlm", lib.loc = lib))
set.seed(94)
n <- 90L
X <- cbind(1, matrix(stats::rnorm(n * 4L), nrow = n))
beta0 <- c(0.4, -0.3, 0.2, 0.1, -0.15)
y <- as.numeric(X %*% beta0 + stats::rnorm(n, sd = 0.25))
profile <- getExportedValue("exdqlm", "exal_make_vb_sigmagam_control")(
  factorization = "structured", structured_grid_size = 21L,
  structured_span_sd = 4, freeze_warmup_iters = 0L,
  min_postwarmup_updates = 1L
)
control <- getExportedValue("exdqlm", "exal_make_vb_control")(
  max_iter = 3L, tol = 1e-4, n_samp_xi = 5L,
  verbose = FALSE, sigmagam = profile
)
fit <- getExportedValue("exdqlm", "exalStaticLDVB")(
  y = y, X = X, p0 = 0.25, beta_prior = "rhs_ns",
  beta_prior_controls = list(tau0 = 0.001, init_tau = 1,
    freeze_tau_iters = 2L, freeze_tau_warmup_iters = 2L,
    shrink_intercept = FALSE),
  init = list(beta = beta0, beta_cov_diag = rep(0.02, ncol(X)), sigma = 0.25,
    gamma = 0, warm_start_mode = "al_qbeta_rhs_latent_first"),
  dqlm.ind = FALSE, n.samp = 5L, vb_control = control, verbose = FALSE
)
deltas <- fit$diagnostics$deltas
cat(jsonlite::toJSON(list(
  version = as.character(desc$Version),
  repository = as.character(desc$Repository),
  repair = as.character(desc[["Config/PriceFM/repair"]]),
  warm_start_mode = fit$misc$warm_start_mode,
  coherent_al_init = fit$misc$coherent_al_init,
  beta_covariance_source = fit$misc$beta_covariance_source,
  latent_first_initialized = fit$misc$latent_first_initialized,
  structured_initialization = fit$misc$sigmagam_initialization,
  rhs_state_iter = fit$beta_prior$state$iter,
  relative_delta_finite = all(is.finite(deltas$state_relative)),
  prediction_delta_finite = all(is.finite(deltas$prediction_scaled)),
  trace_finite = all(is.finite(as.matrix(fit$diagnostics$vb_trace[, c(
    "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"
  )])))
), auto_unbox = TRUE))
'''
    result = json.loads(subprocess.check_output(["Rscript", "-e", code, str(library)], text=True))
    if (
        result.get("version") != VERSION
        or result.get("repository") != "PriceFM-local"
        or result.get("repair") != REPAIR
        or result.get("warm_start_mode") != WARM_START_MODE
        or result.get("coherent_al_init") is not True
        or result.get("beta_covariance_source") != "al_beta_cov_diag"
        or result.get("latent_first_initialized") is not True
        or result.get("structured_initialization") != "plugin_at_warm_start_before_structured_update"
        or int(result.get("rhs_state_iter", -1)) != 3
        or result.get("relative_delta_finite") is not True
        or result.get("prediction_delta_finite") is not True
        or result.get("trace_finite") is not True
    ):
        raise RuntimeError(f"R94 coherent initialization probe failed: {result}")
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    prior = json.loads(args.r82_manifest.read_text())
    if (
        prior.get("status") != "installed_structured_initialization_repair_runtime"
        or prior.get("base_tarball_sha256") != BASE_SHA
        or prior.get("version") != "1.1.1.9004"
    ):
        raise RuntimeError("R94 must derive from the installed hash-pinned R82 runtime")
    old_source = Path(prior["source"])
    expected = {
        "DESCRIPTION": R82_DESCRIPTION_SHA,
        "R/exalStaticLDVB.R": R82_STATIC_SHA,
        "R/exal_sigmagam_structured.R": R82_STRUCTURED_SHA,
    }
    observed = {name: sha256(old_source / name) for name in expected}
    if observed != expected:
        raise RuntimeError(f"R82 source hashes changed: {observed}")

    source_root, library = args.source_root.resolve(), args.library.resolve()
    manifest_path = library / MANIFEST_NAME
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        result = json.loads(manifest_path.read_text())
        result["probe"] = probe(library)
        result["materializer"] = str(Path(__file__).resolve())
        result["materializer_sha256"] = sha256(Path(__file__).resolve())
        result["test_opened"] = False
        result["test_access_authorized"] = False
        manifest_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        return result
    for path in (source_root, library):
        if path.exists():
            if not args.force:
                raise FileExistsError(path)
            shutil.rmtree(path)
    source_root.mkdir(parents=True)
    source = source_root / "exdqlm"
    prepare_source(old_source, source)
    patch_source(source)
    payload: dict[str, Any] = {
        "status": "materialized_not_installed",
        "version": VERSION,
        "repair": REPAIR,
        "warm_start_mode": WARM_START_MODE,
        "scientific_role": "coherent_al_to_structured_exal_initialization",
        "materializer": str(Path(__file__).resolve()),
        "materializer_sha256": sha256(Path(__file__).resolve()),
        "base_tarball_sha256": BASE_SHA,
        "r82_manifest": str(args.r82_manifest.resolve()),
        "r82_manifest_sha256": sha256(args.r82_manifest),
        "source": str(source),
        "source_hashes": {
            str(path.relative_to(source)): sha256(path)
            for path in (
                source / "DESCRIPTION",
                source / "R/exalStaticLDVB.R",
                source / "R/exal_sigmagam_structured.R",
            )
        },
        "library": str(library),
        "launch_authorized": False,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    if args.install:
        library.mkdir(parents=True)
        install_log = library / "install.log"
        with install_log.open("w") as handle:
            subprocess.run(
                ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(source)],
                check=True,
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
        payload.update(
            status="installed_coherent_exal_initialization_runtime",
            install_log=str(install_log),
            install_log_sha256=sha256(install_log),
            probe=probe(library),
        )
        manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    else:
        (source_root / MANIFEST_NAME).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return payload


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
