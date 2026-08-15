import importlib.util, sys
from pathlib import Path
import numpy as np

SCRIPT=Path(__file__).parents[1]/"scripts/pricefm/172_closeout_pricefm_stage_r46_full_quantile_confirmation.py"
sys.path.insert(0,str(SCRIPT.parent))
def module():
    s=importlib.util.spec_from_file_location("r46",SCRIPT); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def test_pinball_and_paper_surface_contract():
    m=module(); y=np.array([0.,2.]); p=np.array([1.,1.]); assert np.allclose(m.pinball(y,p,.25),[.75,.25]); assert m.QUANTILES==[.10,.25,.45,.50,.55,.75,.90]
def test_crossing_audit_detects_violation():
    import pandas as pd
    m=module(); d=pd.DataFrame({"origin_id":[1,1,1],"horizon":[1,1,1],"tau":[.1,.5,.9],"p":[0.,2.,1.]}); assert m.crossing(d,"p")[0]==1
def test_closeout_never_reads_test_or_mutates_authorities():
    s=SCRIPT.read_text(); assert "rows_test.csv" not in s; assert '"test_inspected":False' in s; assert '"mcmc_authorized":False' in s
