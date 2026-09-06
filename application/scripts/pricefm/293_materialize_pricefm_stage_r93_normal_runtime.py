#!/usr/bin/env python3
"""Materialize and probe the hash-pinned R93 normal Ridge/RHS runtime repair."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

from pricefm_common import parse_bool


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
SOURCE = Path("/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0")
OUTPUT = (
    ARTIFACT_REPO
    / "application/data_local/pricefm/runtime_sources/exdqlm_pricefm_r93_normal_exact_names"
)
SOURCE_HEAD = "741c06e9b71566b4880ee1f948b0e3553ced0339"
SOURCE_NORMAL_SHA256 = "d5c58d1fca67b02a3ccd24444257e35bda49d4304a2425b9f342280d03c08468"
VERSION = "1.1.1.9093"
REPAIR = "pricefm-r93-normal-scaled-ridge-prior-exact-name-access"
COPY_DIRS = ("R", "src", "inst", "man")
COPY_FILES = (
    "DESCRIPTION", "NAMESPACE", "LICENSE", "NEWS.md", "README.md", "README.Rmd",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, default=SOURCE)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--rscript", default="/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--allow-fixture-source", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"expected exactly one runtime repair anchor: {old}")
    return text.replace(old, new)


def prepare_source(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True)
    for name in COPY_DIRS:
        src = source / name
        if not src.is_dir():
            raise FileNotFoundError(src)
        shutil.copytree(src, destination / name)
    for name in COPY_FILES:
        src = source / name
        if src.is_file():
            shutil.copy2(src, destination / name)


def patch_source(package: Path) -> None:
    normal = package / "R/qdesn_normal.R"
    text = normal.read_text()
    text = replace_once(
        text,
        "  b <- prior$mean %||% prior$b %||% rep(0, p)\n",
        "  b <- prior[[\"mean\", exact = TRUE]]\n"
        "  if (is.null(b)) b <- prior[[\"b\", exact = TRUE]]\n"
        "  b <- b %||% rep(0, p)\n",
    )
    normal.write_text(text)

    description = package / "DESCRIPTION"
    text = description.read_text()
    text = replace_once(text, "Version: 1.1.1\n", f"Version: {VERSION}\n")
    if "Config/PriceFM/repair:" in text:
        raise RuntimeError("source DESCRIPTION already contains a PriceFM repair marker")
    text = text.rstrip() + f"\nConfig/PriceFM/repair: {REPAIR}\n"
    description.write_text(text)


def probe(package: Path, rscript: str) -> dict[str, Any]:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
source_path <- normalizePath(args[[1L]], mustWork = TRUE)
suppressPackageStartupMessages(pkgload::load_all(source_path, quiet = TRUE))
set.seed(93)
X <- cbind(1, matrix(stats::rnorm(360), 120L, 3L))
y <- as.numeric(X %*% c(0.4, -0.2, 0.1, 0.3) + stats::rnorm(120L, sd = 0.7))
ridge <- exdqlm::normal_desn_fit(
  X, y, beta_prior_type = "scaled_ridge",
  prior = list(beta_ridge_tau2 = 1e4, intercept_var = 1e6),
  omega_prior = list(a = 2, b = 1)
)
expected_b <- 1 + 0.5 * (
  ridge$stats$yty +
  as.numeric(crossprod(ridge$prior$mean, ridge$prior$precision %*% ridge$prior$mean)) -
  as.numeric(crossprod(ridge$beta$mean, ridge$beta$precision %*% ridge$beta$mean))
)
rhs <- exdqlm::normal_desn_fit(
  X, y, beta_prior_type = "rhs_ns", omega_prior = list(a = 2, b = 1),
  rhs = list(tau0 = 0.001, shrink_intercept = FALSE,
             freeze_tau_iters = 5L, freeze_tau_warmup_iters = 5L),
  control = list(max_iter = 100L, min_iter = 20L, tol = 1e-5, verbose = FALSE)
)
Xn <- X[1:4, , drop = FALSE]
taus <- c(0.1, 0.25, 0.5, 0.75, 0.9)
ridge_location <- as.numeric(Xn %*% ridge$beta$mean)
ridge_leverage <- rowSums((Xn %*% ridge$beta$precision_inv) * Xn)
ridge_scale <- sqrt((ridge$omega2$b / ridge$omega2$a) * (1 + ridge_leverage))
ridge_quantiles <- sweep(
  outer(ridge_scale, stats::qt(taus, df = 2 * ridge$omega2$a)),
  1L, ridge_location, `+`
)
rhs_location <- as.numeric(Xn %*% rhs$beta$mean)
rhs_parameter_variance <- rowSums((Xn %*% rhs$beta$cov) * Xn)
rhs_scale <- sqrt(rhs$omega2$mean + rhs_parameter_variance)
rhs_quantiles <- sweep(outer(rhs_scale, stats::qnorm(taus)), 1L, rhs_location, `+`)
payload <- list(
  version = as.character(utils::packageDescription("exdqlm")$Version),
  repair = as.character(utils::packageDescription("exdqlm")[["Config/PriceFM/repair"]]),
  ridge_prior_mean_max_abs = max(abs(ridge$prior$mean)),
  ridge_rate_abs_error = abs(ridge$omega2$b - expected_b),
  ridge_sigma2_mean = ridge$omega2$mean,
  ridge_quantiles_finite = all(is.finite(ridge_quantiles)),
  rhs_converged = isTRUE(rhs$converged),
  rhs_sigma2_mean = rhs$omega2$mean,
  rhs_quantiles_finite = all(is.finite(rhs_quantiles)),
  rhs_beta_finite = all(is.finite(rhs$beta$mean)) && all(is.finite(rhs$beta$cov))
)
cat(jsonlite::toJSON(payload, auto_unbox = TRUE))
'''
    result = json.loads(
        subprocess.check_output(
            [rscript, "-e", code, str(package)], text=True, stderr=subprocess.PIPE
        )
    )
    passed = (
        result.get("version") == VERSION
        and result.get("repair") == REPAIR
        and float(result.get("ridge_prior_mean_max_abs", 1)) == 0
        and float(result.get("ridge_rate_abs_error", 1)) < 1e-8
        and 0 < float(result.get("ridge_sigma2_mean", 0)) < 10
        and result.get("ridge_quantiles_finite") is True
        and result.get("rhs_converged") is True
        and 0 < float(result.get("rhs_sigma2_mean", 0)) < 10
        and result.get("rhs_quantiles_finite") is True
        and result.get("rhs_beta_finite") is True
    )
    if not passed:
        raise RuntimeError(f"R93 normal runtime probe failed: {result}")
    result["passed"] = True
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    source = args.source.resolve()
    source_normal = source / "R/qdesn_normal.R"
    if not source_normal.is_file():
        raise FileNotFoundError(source_normal)
    head = git_head(source) if (source / ".git").exists() else "fixture"
    normal_sha = sha256(source_normal)
    if not args.allow_fixture_source:
        if head != SOURCE_HEAD or normal_sha != SOURCE_NORMAL_SHA256:
            raise RuntimeError(
                f"normal runtime source changed: head={head}, qdesn_normal_sha256={normal_sha}"
            )

    output = args.output_dir.resolve()
    package = output / "exdqlm"
    manifest_path = output / "pricefm_stage_r93_normal_runtime_manifest.json"
    if package.is_dir() and manifest_path.is_file() and not args.force:
        manifest = json.loads(manifest_path.read_text())
        expected = manifest.get("patched_files", {}).get("R/qdesn_normal.R", {}).get("sha256")
        if (
            manifest.get("status") != "materialized_and_probed"
            or manifest.get("repair") != REPAIR
            or not expected
            or sha256(package / "R/qdesn_normal.R") != expected
        ):
            raise RuntimeError("existing R93 normal runtime fails its frozen manifest")
        manifest["probe"] = probe(package, args.rscript)
        return manifest
    if output.exists():
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    prepare_source(source, package)
    patch_source(package)
    probe_result = probe(package, args.rscript)
    manifest = {
        "status": "materialized_and_probed",
        "stage": "pricefm_stage_r93_normal_runtime_repair",
        "repair": REPAIR,
        "version": VERSION,
        "scientific_role": "PriceFM normal Ridge screen and normal RHS initialization/refit only",
        "source": str(source),
        "source_head": head,
        "source_qdesn_normal_sha256": normal_sha,
        "package_path": str(package),
        "copied_directories": list(COPY_DIRS),
        "copied_files": [name for name in COPY_FILES if (package / name).is_file()],
        "excluded_source_artifacts": [
            ".git", "build", "config", "data", "docs", "logs", "reports", "results",
            "scripts", "tests", "tools", "validation",
        ],
        "patched_files": {
            "DESCRIPTION": {"sha256": sha256(package / "DESCRIPTION")},
            "R/qdesn_normal.R": {"sha256": sha256(package / "R/qdesn_normal.R")},
        },
        "probe": probe_result,
        "launch_authorized": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    manifest["manifest_path"] = str(manifest_path)
    manifest["manifest_sha256"] = sha256(manifest_path)
    return manifest


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
