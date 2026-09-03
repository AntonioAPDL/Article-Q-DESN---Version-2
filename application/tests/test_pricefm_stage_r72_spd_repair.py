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
        "r72_materialize", SCRIPTS / "242_materialize_pricefm_stage_r72_exdqlm_spd_repair.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r72_patch_applies_only_to_hash_pinned_cran_source(tmp_path):
    module = load()
    args = module.parser().parse_args([
        "--tarball", str(TARBALL), "--source-root", str(tmp_path / "source"),
        "--library", str(tmp_path / "library"), "--install", "false",
    ])
    result = module.run(args)
    source = Path(result["patched_source"])
    assert result["base_tarball_sha256"] == module.CRAN_SHA256
    assert result["status"] == "materialized_source_not_installed"
    assert "Version: 1.1.1.9001" in (source / "DESCRIPTION").read_text()
    assert ".pricefm_safe_spd_chol" in (source / "R/pricefm_spd_repair.R").read_text()
    assert "spd_factorization" in (source / "R/utils.R").read_text()


def test_r72_spd_helper_preserves_direct_path_and_repairs_scale_failure(tmp_path):
    module = load()
    args = module.parser().parse_args([
        "--tarball", str(TARBALL), "--source-root", str(tmp_path / "source"),
        "--library", str(tmp_path / "library"), "--install", "false",
    ])
    result = module.run(args)
    helper = Path(result["patched_source"]) / "R/pricefm_spd_repair.R"
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
source(args[[1L]], local = TRUE)
good <- matrix(c(2, 0.25, 0.25, 1), 2)
direct <- .pricefm_safe_spd_chol(good, "good", 1L)
stopifnot(direct$diagnostics$factorization_path == "direct")
stopifnot(isTRUE(all.equal(direct$chol, chol(good), tolerance = 0)))

# A positive-semidefinite rank-one matrix at a scale where 1e-10 is not
# representable on its diagonal reproduces the R70 fixed-jitter failure mode.
u <- c(1, 2, 3, 4)
bad <- 1e10 * tcrossprod(u)
stopifnot(is.null(tryCatch(chol(bad), error = function(e) NULL)))
stopifnot(is.null(tryCatch(chol(bad + 1e-10 * diag(4)), error = function(e) NULL)))
repaired <- .pricefm_safe_spd_chol(bad, "stress", 2L)
stopifnot(repaired$diagnostics$factorization_path == "scale_aware_symmetric_relative")
stopifnot(repaired$diagnostics$relative_jitter <= 1e-8)
stopifnot(all(is.finite(repaired$chol)))

nonfinite <- bad
nonfinite[1, 1] <- Inf
err <- tryCatch(.pricefm_safe_spd_chol(nonfinite), error = identity)
stopifnot(inherits(err, "error"), grepl("non-finite", conditionMessage(err)))
'''
    subprocess.run(["Rscript", "-e", code, str(helper)], check=True)
