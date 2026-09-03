import importlib.util
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TARBALL = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/"
    "runtime_sources/exdqlm_cran_1p1p1/exdqlm_1.1.1.tar.gz"
)


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r75_materialize", SCRIPTS / "251_materialize_pricefm_stage_r75_exdqlm_large_n_gig_repair.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def materialize(tmp_path):
    module = load()
    args = module.parser().parse_args([
        "--tarball", str(TARBALL), "--source-root", str(tmp_path / "source"),
        "--library", str(tmp_path / "library"), "--install", "false",
    ])
    return module, module.run(args)


def test_r75_patches_exact_cran_source_after_r72(tmp_path):
    module, result = materialize(tmp_path)
    source = Path(result["patched_source"])
    assert result["base_tarball_sha256"] == module.CRAN_SHA256
    assert result["status"] == "materialized_source_not_installed"
    assert "Version: 1.1.1.9002" in (source / "DESCRIPTION").read_text()
    structured = (source / "R/exal_sigmagam_structured.R").read_text()
    assert ".pricefm_log_bessel_k_uniform" in structured
    assert ".pricefm_bessel_order_derivative" in structured
    assert "prev_E_s <- E_s" in (source / "R/exalStaticLDVB.R").read_text()


def test_r75_uniform_asymptotic_matches_direct_and_is_finite_at_pricefm_scale(tmp_path):
    _, result = materialize(tmp_path)
    source = Path(result["patched_source"])
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
source(file.path(args[[1L]], "R/exal_sigmagam_structured.R"), local = TRUE)
for (nu in c(10, 50, 100, 500)) {
  x <- 0.8 * nu
  exact <- log(besselK(x, nu = nu, expon.scaled = TRUE)) - x
  approx <- .pricefm_log_bessel_k_uniform(x, nu)
  stopifnot(is.finite(approx), abs(approx - exact) < 2e-4)
}
for (n in c(1000, 10000, 100000)) {
  k <- -(1 + 1.5 * n)
  chi <- 2 * n
  psi <- 5 * n
  z <- sqrt(chi * psi)
  repaired <- .pricefm_log_bessel_k(z, k)
  stopifnot(is.finite(repaired), identical(attr(repaired, "backend"), "uniform_large_order"))
  moments <- c(
    .exal_gig_moment(k, chi, psi, 1),
    .exal_gig_moment(k, chi, psi, -1),
    .exal_gig_moment(k, chi, psi, 2),
    .exal_gig_elog(k, chi, psi),
    .exal_gig_varlog(k, chi, psi),
    .exal_gig_log_integral(k, chi, psi)
  )
  stopifnot(all(is.finite(moments)), all(moments[1:3] > 0), moments[5] >= 0)
  stopifnot(moments[1] * moments[2] >= 1 - 1e-8)
}
'''
    subprocess.run(["Rscript", "-e", code, str(source)], check=True)


def test_r75_direct_path_preserves_moderate_order_gig_moments(tmp_path):
    _, result = materialize(tmp_path)
    source = Path(result["patched_source"])
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
source(file.path(args[[1L]], "R/exal_sigmagam_structured.R"), local = TRUE)
legacy <- function(k, chi, psi, r) {
  z <- sqrt(chi * psi)
  exp(0.5 * r * (log(chi) - log(psi)) +
    log(besselK(z, nu = k + r, expon.scaled = TRUE)) -
    log(besselK(z, nu = k, expon.scaled = TRUE)))
}
for (n in c(10, 50, 100)) {
  k <- -(1 + 1.5 * n); chi <- 2 * n; psi <- 5 * n
  for (r in c(-1, 1, 2)) {
    stopifnot(all.equal(.exal_gig_moment(k, chi, psi, r), legacy(k, chi, psi, r), tolerance = 1e-12))
  }
}
'''
    subprocess.run(["Rscript", "-e", code, str(source)], check=True)
