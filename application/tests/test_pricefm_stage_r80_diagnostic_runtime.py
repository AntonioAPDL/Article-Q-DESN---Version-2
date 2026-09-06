import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/264_materialize_pricefm_stage_r80_diagnostic_runtime.py"


def load():
    spec = importlib.util.spec_from_file_location("r80_runtime", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_instrumentation_is_exact_and_diagnostic_only(tmp_path):
    module = load()
    old = tmp_path / "old"
    (old / "R").mkdir(parents=True)
    (old / "DESCRIPTION").write_text(
        "Version: 1.1.1.9002\nConfig/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG\n"
    )
    (old / "R/exal_sigmagam_structured.R").write_text(
        "# Shared exAL scale-skewness helpers used by dynamic and static inference.\n\n"
        '  if (!length(logw)) stop("Structured exAL scale-skewness update has no finite gamma grid.", call. = FALSE)\n'
    )
    (old / "R/exalStaticLDVB.R").write_text(
        "    if (isTRUE(do_ld_update) && isTRUE(structured_sigmagam)) {\n      ld <- find_mode_structured(eta_hat)\n"
    )
    module.instrument(old)
    assert "Version: 1.1.1.9003" in (old / "DESCRIPTION").read_text()
    text = (old / "R/exal_sigmagam_structured.R").read_text()
    assert "exdqlm.pricefm_failure_callback" in text
    assert "coarse_logw = coarse_vals" in text
    assert "failure_diagnostics.json" not in text
    assert "pricefm_current_iter" in (old / "R/exalStaticLDVB.R").read_text()


def test_materializer_has_no_launch_or_mutation_authority():
    text = SCRIPT.read_text()
    assert '"launch_authorized": False' in text
    assert '"test_access_authorized": False' in text
    assert '"registry_mutation_authorized": False' in text
    assert '"article_mutation_authorized": False' in text
