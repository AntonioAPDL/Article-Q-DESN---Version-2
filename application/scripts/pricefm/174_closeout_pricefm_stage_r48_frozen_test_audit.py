#!/usr/bin/env python3
"""Close out the frozen R47 test audit against Q-DESN and PriceFM."""

from __future__ import annotations
import argparse, ast, hashlib, json
from pathlib import Path
import numpy as np
import pandas as pd
from pricefm_common import parse_bool, write_json

ARTIFACT_REPO=Path("/data/jaguir26/local/src/Article-Q-DESN"); DATA=ARTIFACT_REPO/"application/data_local/pricefm"
PREP=DATA/"authoritative/pricefm_stage_r47_frozen_test_audit_launch_prep_20260808"; GRID=DATA/"experiment_grids/pricefm_stage_r47_frozen_test_audit_20260808"; R45=DATA/"authoritative/pricefm_stage_r45_full_quantile_confirmation_launch_prep_20260807"; R46=DATA/"authoritative/pricefm_stage_r46_full_quantile_confirmation_closeout_20260808"; REGISTRY=DATA/"authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_decision_registry.csv"; OUTPUT=DATA/"authoritative/pricefm_stage_r48_frozen_test_audit_closeout_20260808"
BLOCKS=["1-24","25-48","49-72","73-96"]; SHARED="qdesn_exal_rhs_ns_exact_chunked"; SEPARATE=SHARED+"_horizon_separate"
def parser():
 p=argparse.ArgumentParser(description=__doc__); p.add_argument("--prep-dir",type=Path,default=PREP);p.add_argument("--grid-root",type=Path,default=GRID);p.add_argument("--stage-r45-dir",type=Path,default=R45);p.add_argument("--stage-r46-dir",type=Path,default=R46);p.add_argument("--registry",type=Path,default=REGISTRY);p.add_argument("--output-dir",type=Path,default=OUTPUT);p.add_argument("--harm-margin",type=float,default=.005);p.add_argument("--replay-tolerance",type=float,default=1e-10);p.add_argument("--force",type=parse_bool,default=False);return p
def sha256(p):
 h=hashlib.sha256();
 with Path(p).open("rb") as f:
  for c in iter(lambda:f.read(1024*1024),b""):h.update(c)
 return h.hexdigest()
def scalar(v): return ast.literal_eval(v)[0] if isinstance(v,str) else v[0]
def pinball(y,p,t): return np.where(y>=p,t*(y-p),(1-t)*(p-y))
def weights(r): return {b:float(getattr(r,f"weight_{b.replace('-','_')}")) for b in BLOCKS}
def model(row,stage):
 region,fold=scalar(row.regions),int(scalar(row.folds)); return Path(row.run_dir)/"cells"/f"region={region}"/f"fold={fold}"/"model",region,fold
def surface(model_dir,split,w):
 pred=pd.read_csv(model_dir/"model_predictions_scaled.csv"); truth=pd.read_csv(model_dir.parent/"adapter"/f"rows_{split}.csv")[["origin_id","horizon","y_scaled"]]; sh=pred[(pred.method_id.eq(SHARED))&(pred.split.eq(split))];sp=pred[(pred.method_id.eq(SEPARATE))&(pred.split.eq(split))];d=sh.merge(sp,on=["split","origin_id","horizon","tau"],suffixes=("_shared","_separate")).merge(truth,on=["origin_id","horizon"]);d["block"]=pd.cut(d.horizon,[0,24,48,72,96],labels=BLOCKS).astype(str);d["weight"]=d.block.map(w).astype(float);d["pooled"]=d.pred_scaled_shared*(1-d.weight)+d.pred_scaled_separate*d.weight;d["shared_loss"]=pinball(d.y_scaled,d.pred_scaled_shared,d.tau);d["pooled_loss"]=pinball(d.y_scaled,d.pooled,d.tau);return d
def normalized_val(frame): return frame.sort_values(["method_id","split","origin_id","horizon","tau"]).reset_index(drop=True)
def run(args):
 out=args.output_dir.resolve();
 if out.exists() and any(out.iterdir()) and not args.force:raise FileExistsError(f"Output exists: {out}")
 out.mkdir(parents=True,exist_ok=True); manifest_path=args.prep_dir/"pricefm_stage_r47_launch_manifest.csv"; manifest=pd.read_csv(manifest_path);status=pd.read_csv(args.grid_root/"launch_status.csv");complete=status.status.eq("completed")&status.return_code.astype(int).eq(0)
 if len(manifest)!=2 or len(status)!=2 or not complete.all():raise RuntimeError("R47 incomplete")
 r45=pd.read_csv(args.stage_r45_dir/"pricefm_stage_r45_launch_manifest.csv").set_index("id");r46=pd.read_csv(args.stage_r46_dir/"pricefm_stage_r46_frozen_test_audit_queue.csv").set_index(["region","fold"]);registry=pd.read_csv(args.registry).set_index(["region","fold"])
 cases=[];quantiles=[];horizons=[];replay=[];sources=[Path(__file__).resolve(),manifest_path,args.grid_root/"launch_status.csv",args.registry]
 for row in manifest.itertuples(index=False):
  m47,region,fold=model(row,"r47"); source_id=row.source_r45_experiment_id; old=r45.loc[source_id];m45=Path(old.run_dir)/"cells"/f"region={region}"/f"fold={fold}"/"model";w=weights(row)
  artifact_checks={name:sha256(m47.parent/"adapter"/name)==sha256(m45.parent/"adapter"/name) for name in ["rows_train.csv","rows_val.csv","feature_map_matrix.npz"]}
  p47=pd.read_csv(m47/"model_predictions_scaled.csv");p45=pd.read_csv(m45/"model_predictions_scaled.csv");cols=["method_id","split","origin_id","horizon","tau","pred_scaled"];a=normalized_val(p47[p47.split.eq("val")][cols]);b=normalized_val(p45[p45.split.eq("val")][cols]);val_equal=a[["method_id","split","origin_id","horizon","tau"]].equals(b[["method_id","split","origin_id","horizon","tau"]]) and np.allclose(a.pred_scaled,b.pred_scaled,rtol=0,atol=args.replay_tolerance)
  val=surface(m47,"val",w);test=surface(m47,"test",w);metric=pd.read_csv(m47/"metric_summary.csv");shared_test_original=float(metric[(metric.method_id.eq(SHARED))&(metric.split.eq("test"))&(metric.unit.eq("original"))].AQL.iloc[0]);scale=shared_test_original/test.shared_loss.mean();pooled_test=test.pooled_loss.mean()*scale
  qrows=[];hrows=[]
  for tau,g in test.groupby("tau"):
   x=g.shared_loss.mean()*scale;y=g.pooled_loss.mean()*scale;rec={"region":region,"fold":fold,"tau":tau,"shared_test_AQL":x,"pooled_test_AQL":y,"delta":y-x,"relative_delta":y/x-1,"harm_guard_pass":y/x-1<=args.harm_margin+1e-12};quantiles.append(rec);qrows.append(rec)
  for (tau,block),g in test.groupby(["tau","block"]):
   x=g.shared_loss.mean()*scale;y=g.pooled_loss.mean()*scale;rec={"region":region,"fold":fold,"tau":tau,"horizon_group":block,"weight":w[block],"shared_test_AQL":x,"pooled_test_AQL":y,"delta":y-x,"relative_delta":y/x-1,"harm_guard_pass":y/x-1<=args.harm_margin+1e-12};horizons.append(rec);hrows.append(rec)
  auth=registry.loc[(region,fold)]; qref=float(auth.qdesn_AQL); pref=float(auth.pricefm_AQL); validation_replay=all(artifact_checks.values()) and val_equal and abs(val.pooled_loss.mean()-surface(m45,"val",w).pooled_loss.mean())<=args.replay_tolerance
  beats_q=pooled_test<qref;beats_p=pooled_test<pref;harm=all(x["harm_guard_pass"] for x in qrows+hrows);eligible=validation_replay and harm and beats_q and beats_p
  replay.append({"region":region,"fold":fold,**artifact_checks,"validation_predictions_equal":val_equal,"validation_replay_pass":validation_replay})
  cases.append({"source_r47_experiment_id":row.id,"region":region,"fold":fold,"pooled_test_AQL":pooled_test,"shared_test_AQL":shared_test_original,"authoritative_qdesn_AQL":qref,"cached_pricefm_AQL":pref,"pooled_minus_qdesn":pooled_test-qref,"pooled_minus_pricefm":pooled_test-pref,"beats_authoritative_qdesn":beats_q,"beats_cached_pricefm":beats_p,"test_harm_guard_pass":harm,"validation_replay_pass":validation_replay,"mcmc_confirmation_eligible":eligible,"decision":"eligible_for_mcmc_confirmation" if eligible else "blocked_r48_dual_reference_gate","test_role":"audit_only_after_frozen_r46","registry_mutation_authorized":False,"article_mutation_authorized":False,"mcmc_launch_authorized":False})
  sources += [m47/"metric_summary.csv",m47/"model_predictions_scaled.csv",m47.parent/"adapter/rows_test.csv",m45/"model_predictions_scaled.csv"]
 case=pd.DataFrame(cases);queue=case[case.mcmc_confirmation_eligible].copy();pd.DataFrame(replay).to_csv(out/"pricefm_stage_r48_validation_replay_audit.csv",index=False);case.to_csv(out/"pricefm_stage_r48_case_closeout.csv",index=False);pd.DataFrame(quantiles).to_csv(out/"pricefm_stage_r48_quantile_metrics.csv",index=False);pd.DataFrame(horizons).to_csv(out/"pricefm_stage_r48_horizon_metrics.csv",index=False);queue.to_csv(out/"pricefm_stage_r48_mcmc_confirmation_queue.csv",index=False)
 gates=pd.DataFrame([{"gate":"r47_completed","passed":bool(complete.all()),"observed":int(complete.sum())},{"gate":"validation_replay","passed":bool(case.validation_replay_pass.all()),"observed":int(case.validation_replay_pass.sum())},{"gate":"test_harm_guards","passed":bool(case.test_harm_guard_pass.all()),"observed":int(case.test_harm_guard_pass.sum())},{"gate":"registry_article_blocked","passed":True,"observed":"blocked"},{"gate":"mcmc_not_launched","passed":True,"observed":"blocked_pending_capability_audit"}]);gates.to_csv(out/"pricefm_stage_r48_decision_gates.csv",index=False)
 if not gates.passed.all():raise RuntimeError("R48 integrity gates failed")
 unique=list(dict.fromkeys(Path(x).resolve() for x in sources));pd.DataFrame([{"path":str(p),"sha256":sha256(p),"bytes":p.stat().st_size} for p in unique]).to_csv(out/"source_manifest.csv",index=False)
 summary={"status":"completed_frozen_test_audit","cases":2,"cases_beating_qdesn":int(case.beats_authoritative_qdesn.sum()),"cases_beating_pricefm":int(case.beats_cached_pricefm.sum()),"mcmc_confirmation_candidates":len(queue),"registry_mutation_authorized":False,"article_mutation_authorized":False,"mcmc_launch_authorized":False};write_json(out/"summary.json",summary);(out/"pricefm_stage_r48_frozen_test_audit_closeout_report.md").write_text("# PriceFM Stage-R48 frozen test audit closeout\n\nThis read-only closeout accepts test metrics only after exact validation replay, compares each frozen case against authoritative Q-DESN and cached PriceFM, and queues only dual-reference winners for a separate MCMC capability audit. It never mutates the registry or article and never launches MCMC.\n");return summary
if __name__=="__main__":print(json.dumps(run(parser().parse_args()),indent=2,sort_keys=True))
