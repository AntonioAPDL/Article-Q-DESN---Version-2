import importlib.util,sys
from pathlib import Path
import pandas as pd
SCRIPT=Path(__file__).parents[1]/"scripts/pricefm/173_prepare_pricefm_stage_r47_frozen_test_audit.py"; sys.path.insert(0,str(SCRIPT.parent))
def module(): s=importlib.util.spec_from_file_location("r47",SCRIPT);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def test_grid_changes_only_evaluation_scope():
 m=module(); source={"pricefm_desn_experiment_grid":{"grid_id":"r45","purpose":"x","base":{},"scope":{"splits":["train","val"],"quantiles":m.QUANTILES},"fixed":{},"launch":{},"experiments":[{"id":"r45_a","regions":["NO_3"],"folds":[2]}]}}; q=pd.DataFrame([{"source_r45_experiment_id":"r45_a"}]); g=m.build_grid(source,q,Path("o"),Path("g"),Path("r"),[1,2],True)["pricefm_desn_experiment_grid"]; assert g["scope"]["splits"]==["train","val","test"]; assert g["experiments"][0]["id"]=="r47_a"; assert g["experiments"][0]["factor_changed"]=="evaluation_split_only_add_test"
def test_prep_does_not_launch_or_mutate():
 s=SCRIPT.read_text(); assert "subprocess" not in s; assert 'manifest["mutates_registry"]=False' in s; assert 'manifest["mcmc_authorized"]=False' in s
