import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/273_materialize_pricefm_stage_r82_structured_init_runtime.py"


def load():
    spec = importlib.util.spec_from_file_location("r82_runtime", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_repair_replaces_invalid_delta_initialization_only(tmp_path):
    module = load()
    source = tmp_path / "exdqlm"
    (source / "R").mkdir(parents=True)
    (source / "DESCRIPTION").write_text(
        "Version: 1.1.1.9003\n"
        "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics\n"
    )
    (source / "R/exalStaticLDVB.R").write_text(
        '''  # Initial xi from the Delta approximation. The static exAL VB path is
  # intentionally deterministic; MC xi fallback is not part of the production
  # algorithm anymore.
  xis_eval <- compute_xi(
    eta_hat,
    ell_hat,
    Sig_eta_ell
  )
  xis <- xis_eval$value
  sigmagam_cfg <- ld_ctrl$sigmagam %||% .exal_sigmagam_vb_controls(NULL)
  sigmagam_cfg <- .exal_clamp_vb_sigmagam_control(sigmagam_cfg, max_iter = max_iter)
  structured_sigmagam <- identical(sigmagam_cfg$factorization, "structured")
      sigmagam = sigmagam_cfg,
      sigmagam_required_postwarmup_updates
'''
    )
    module.repair(source)
    text = (source / "R/exalStaticLDVB.R").read_text()
    assert "matrix(0, 2L, 2L)" in text
    assert "plugin_at_warm_start_before_structured_update" in text
    assert "sigmagam_initial_xi = initial_xis" in text
    assert text.count("structured_sigmagam <-") == 1
    assert "Version: 1.1.1.9004" in (source / "DESCRIPTION").read_text()


def test_runtime_is_hash_pinned_and_cannot_authorize_mutation():
    text = SCRIPT.read_text()
    assert "R80_STATIC_SHA" in text and "R80_STRUCTURED_SHA" in text
    assert 'invisible(loadNamespace("exdqlm", lib.loc = lib))' in text
    assert '"launch_authorized": False' in text
    assert '"test_access_authorized": False' in text
    assert '"registry_mutation_authorized": False' in text
    assert '"article_mutation_authorized": False' in text
