import importlib.util,sys
from pathlib import Path
import numpy as np
SCRIPT=Path(__file__).parents[1]/"scripts/pricefm/174_closeout_pricefm_stage_r48_frozen_test_audit.py";sys.path.insert(0,str(SCRIPT.parent))
def module():s=importlib.util.spec_from_file_location("r48",SCRIPT);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def test_pinball():m=module();assert np.allclose(m.pinball(np.array([0.,2.]),np.array([1.,1.]),.25),[.75,.25])
def test_test_is_audit_only_and_mcmc_not_launched():
 s=SCRIPT.read_text();assert '"test_role":"audit_only_after_frozen_r46"' in s;assert '"mcmc_launch_authorized":False' in s;assert "subprocess" not in s
