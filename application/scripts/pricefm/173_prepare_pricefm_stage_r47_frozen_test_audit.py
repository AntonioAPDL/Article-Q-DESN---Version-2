#!/usr/bin/env python3
"""Prepare a deterministic R47 test audit for the frozen R46 candidates."""

from __future__ import annotations

import argparse, ast, copy, hashlib, importlib.util, json, shutil
from pathlib import Path
import pandas as pd
import yaml
from pricefm_common import parse_bool, write_json

ARTIFACT_REPO=Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA=ARTIFACT_REPO/"application/data_local/pricefm"
R45=DATA/"authoritative/pricefm_stage_r45_full_quantile_confirmation_launch_prep_20260807"
R46=DATA/"authoritative/pricefm_stage_r46_full_quantile_confirmation_closeout_20260808"
REGISTRY=DATA/"authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_decision_registry.csv"
OUTPUT=DATA/"authoritative/pricefm_stage_r47_frozen_test_audit_launch_prep_20260808"
GRID=DATA/"experiment_grids/pricefm_stage_r47_frozen_test_audit_20260808"
RUNS=DATA/"runs/pricefm_stage_r47_frozen_test_audit_20260808"
QUANTILES=[.10,.25,.45,.50,.55,.75,.90]
BLOCKS=["1-24","25-48","49-72","73-96"]

def parser():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r45-dir",type=Path,default=R45); p.add_argument("--stage-r46-dir",type=Path,default=R46); p.add_argument("--registry",type=Path,default=REGISTRY)
    p.add_argument("--output-dir",type=Path,default=OUTPUT); p.add_argument("--grid-root",type=Path,default=GRID); p.add_argument("--run-root",type=Path,default=RUNS)
    p.add_argument("--materializer",type=Path,default=Path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py")); p.add_argument("--launcher",type=Path,default=Path("application/scripts/pricefm/13_run_desn_experiment_grid.py")); p.add_argument("--runner",type=Path,default=Path("application/scripts/pricefm/08_run_desn_model_smoke.R")); p.add_argument("--python-bin",type=Path,default=DATA/"venv/bin/python")
    p.add_argument("--cpu-list",required=True); p.add_argument("--authorize-launch",type=parse_bool,default=False); p.add_argument("--force",type=parse_bool,default=False); return p

def sha256(p):
    h=hashlib.sha256();
    with Path(p).open("rb") as f:
        for c in iter(lambda:f.read(1024*1024),b""): h.update(c)
    return h.hexdigest()
def cpus(value):
    out=[]
    for t in value.split(","):
        if "-" in t: a,b=map(int,t.split("-",1)); out+=list(range(a,b+1))
        elif t.strip(): out.append(int(t))
    if len(out)<2 or len(out)!=len(set(out)): raise ValueError("Need two unique CPUs")
    return out
def load_module(path):
    s=importlib.util.spec_from_file_location(path.stem,path); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def parse_quantiles(value): return [float(x) for x in ast.literal_eval(value)] if isinstance(value,str) else list(value)

def benchmark_audit(path, queue):
    d=pd.read_csv(path); keys=set(zip(queue.region,queue.fold.astype(int))); d=d[d.apply(lambda r:(r.region,int(r.fold)) in keys,axis=1)].copy()
    d["paper_quantiles_exact"]=d["paper_quantiles"].map(parse_quantiles).map(lambda x:x==QUANTILES)
    d["frozen_authority_pass"]=d["selection_is_validation_only"].astype(bool)&d["test_metrics_role"].eq("audit_only")&d["paper_quantiles_exact"]&d["qdesn_AQL"].notna()&d["pricefm_AQL"].notna()
    return d

def build_grid(source,queue,out,grid_root,run_root,cpu_list,authorized):
    payload=copy.deepcopy(source); grid=payload["pricefm_desn_experiment_grid"]; ids=set(queue.source_r45_experiment_id)
    grid["grid_id"]="pricefm_stage_r47_frozen_test_audit_20260808"; grid["purpose"]="Deterministic test-scope replay of two R46-frozen candidates; no test-based selection."
    grid["base"].update({"data_config":str(out/"pricefm_stage_r47_base_data_config.yaml"),"full_config":str(out/"pricefm_stage_r47_base_full_config.yaml"),"generated_root":str(grid_root),"run_root":str(run_root)})
    grid["scope"].update({"splits":["train","val","test"],"quantiles":QUANTILES,"ranking_split":"frozen_r46_validation_decision","audit_split":"test_audit_only"})
    exps=[]
    for exp in grid["experiments"]:
        if exp["id"] not in ids: continue
        x=copy.deepcopy(exp); x["id"]=x["id"].replace("r45_","r47_",1); x["stage"]="stage_r47_frozen_test_audit"; x["priority"]=0
        x["selection_rule"]="frozen_r46_no_test_selection"; x["test_metrics_role"]="audit_only_after_frozen_r46"; x["final_decision"]="stage_r47_test_audit_not_promotion"; x["candidate_source_final"]="pricefm_stage_r46_full_quantile_confirmation_closeout_20260808"; x["factor_changed"]="evaluation_split_only_add_test"; exps.append(x)
    grid["experiments"]=exps; grid["launch"]={"stage_r47_full_background_launch":{"priorities":[0],"experiment_jobs":2,"cell_jobs":1,"cpu_ids":cpu_list,"build_windows":False,"dry_run":False,"resume":True,"force":False,"authorized_now":authorized}}
    return payload

def config_audit(generated,r45_manifest):
    old=r45_manifest.set_index("id"); rows=[]
    for g in generated:
        source=g["id"].replace("r47_","r45_",1); a=yaml.safe_load(Path(old.loc[source,"full_config"]).read_text())["pricefm_desn_full"]; b=yaml.safe_load(Path(g["full_config"]).read_text())["pricefm_desn_full"]
        sections=["qdesn_vb","normal","warm_start","nested_validation","rhs_ns","training"]
        adapter=dict(a["adapter"]); adapter.pop("output_root",None); adapter2=dict(b["adapter"]); adapter2.pop("output_root",None)
        same=all(a[s]==b[s] for s in sections) and adapter==adapter2 and a["scope"]["quantiles"]==b["scope"]["quantiles"]==QUANTILES and a["scope"]["regions"]==b["scope"]["regions"] and a["scope"]["folds"]==b["scope"]["folds"]
        rows.append({"experiment_id":g["id"],"source_r45_experiment_id":source,"model_contract_identical":same,"only_scope_change_add_test":a["scope"]["splits"]==["train","val"] and b["scope"]["splits"]==["train","val","test"],"launch_contract_pass":same and b["scope"]["splits"]==["train","val","test"]})
    return pd.DataFrame(rows)

def run(args):
    out=args.output_dir.resolve();
    if out.exists() and any(out.iterdir()) and not args.force: raise FileExistsError(f"Output exists: {out}")
    out.mkdir(parents=True,exist_ok=True)
    queue_path=args.stage_r46_dir/"pricefm_stage_r46_frozen_test_audit_queue.csv"; queue=pd.read_csv(queue_path)
    if len(queue)!=2 or not queue["r47_test_audit_eligible"].astype(bool).all(): raise RuntimeError("R46 queue gate failed")
    registry=benchmark_audit(args.registry,queue)
    if len(registry)!=2 or not registry["frozen_authority_pass"].all(): raise RuntimeError("Benchmark authority gate failed")
    shutil.copy2(args.stage_r45_dir/"pricefm_stage_r45_base_data_config.yaml",out/"pricefm_stage_r47_base_data_config.yaml"); shutil.copy2(args.stage_r45_dir/"pricefm_stage_r45_base_full_config.yaml",out/"pricefm_stage_r47_base_full_config.yaml")
    source_grid=args.stage_r45_dir/"pricefm_stage_r45_full_quantile_confirmation_grid.yaml"; payload=build_grid(yaml.safe_load(source_grid.read_text()),queue,out,args.grid_root.resolve(),args.run_root.resolve(),cpus(args.cpu_list),bool(args.authorize_launch))
    grid_path=out/"pricefm_stage_r47_frozen_test_audit_grid.yaml"; grid_path.write_text(yaml.safe_dump(payload,sort_keys=False))
    materializer=load_module(args.materializer.resolve()); generated=materializer.prepare_grid(materializer.load_grid(str(grid_path)),str(args.grid_root.resolve()),write=True)
    r45_manifest=pd.read_csv(args.stage_r45_dir/"pricefm_stage_r45_launch_manifest.csv"); contract=config_audit(generated,r45_manifest); contract.to_csv(out/"pricefm_stage_r47_materialized_config_contract.csv",index=False)
    manifest=pd.DataFrame(generated); manifest["source_r45_experiment_id"]=manifest["id"].str.replace("r47_","r45_",regex=False); cols=["source_r45_experiment_id"]+[f"weight_{b.replace('-','_')}" for b in BLOCKS]; q=queue.rename(columns={"source_r45_experiment_id":"source_r45_experiment_id"}); manifest=manifest.merge(q[cols],on="source_r45_experiment_id",validate="one_to_one"); manifest["selection_frozen_before_test"]=True; manifest["test_metrics_role"]="audit_only_after_frozen_r46"; manifest["mutates_registry"]=False; manifest["mutates_article"]=False; manifest["mcmc_authorized"]=False; manifest.to_csv(out/"pricefm_stage_r47_launch_manifest.csv",index=False)
    registry.to_csv(out/"pricefm_stage_r47_frozen_benchmark_authority.csv",index=False)
    gates=pd.DataFrame([{"gate":"two_r46_candidates","passed":len(queue)==2,"detail":2},{"gate":"benchmark_authority","passed":bool(registry.frozen_authority_pass.all()),"detail":2},{"gate":"model_contract_reproduced","passed":bool(contract.launch_contract_pass.all()),"detail":int(contract.launch_contract_pass.sum())},{"gate":"test_is_evaluation_only","passed":True,"detail":"frozen before test"},{"gate":"one_cpu_per_case","passed":len(cpus(args.cpu_list))>=2,"detail":args.cpu_list},{"gate":"explicit_authorization","passed":bool(args.authorize_launch),"detail":bool(args.authorize_launch)},{"gate":"mutation_and_mcmc_blocked","passed":True,"detail":"blocked"}]); gates.to_csv(out/"pricefm_stage_r47_launch_gates.csv",index=False)
    if not gates.passed.all(): raise RuntimeError("R47 prep gates failed")
    command=f"{args.python_bin.absolute()} {args.launcher.resolve()} --grid-config {grid_path} --priorities 0 --experiment-jobs 2 --cell-jobs 1 --build-windows false --resume true --force false --dry-run false --cpu-list {args.cpu_list}"
    (out/"pricefm_stage_r47_launch_command.txt").write_text(command+"\n")
    sources=[Path(__file__).resolve(),queue_path,args.registry.resolve(),source_grid,args.materializer.resolve(),args.launcher.resolve(),args.runner.resolve()]; pd.DataFrame([{"path":str(p),"sha256":sha256(p),"bytes":p.stat().st_size} for p in sources]).to_csv(out/"source_manifest.csv",index=False)
    summary={"status":"completed_launch_ready","targets":2,"benchmark_cases":2,"cpu_ids":cpus(args.cpu_list),"launch_command":command,"selection_frozen_before_test":True,"registry_mutation_authorized":False,"article_mutation_authorized":False,"mcmc_authorized":False}; write_json(out/"summary.json",summary)
    (out/"pricefm_stage_r47_frozen_test_audit_launch_prep_report.md").write_text("# PriceFM Stage-R47 frozen test audit prep\n\nR47 replays exactly two R46-frozen case-specific mechanisms. The sole model-contract change is adding the test split. R48 must reproduce R45 validation rows, feature maps, and predictions before test metrics are admissible. Test is audit-only; registry, article, and MCMC actions remain blocked.\n")
    return summary
if __name__=="__main__": print(json.dumps(run(parser().parse_args()),indent=2,sort_keys=True))
