#!/usr/bin/env Rscript
root<-normalizePath(file.path(dirname(sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])),"..",".."));source(file.path(root,"application/R/00_packages.R"));app_set_repo_root(root)
for(f in c("input_contract.R","synthesize_quantiles.R","score_forecasts.R","joint_qvp_qdesn.R","joint_qdesn_simulation_readiness.R","joint_qdesn_simulation_fixtures.R","joint_qdesn_simulation_validation.R","joint_qdesn_vb_spec_screening.R","joint_exqdesn_phase162_scenario_classification.R","joint_exqdesn_phase163_tail_calibration.R"))source(app_path("application/R",f))
d<-app_joint_exqdesn_phase163_dirs(); x<-app_joint_exqdesn_phase163_registry(d)
stopifnot(nrow(x)==20L,length(unique(x$scenario_ids))==5L,!any(x$prior_duplicate),all(x$no_global_specification),all(x$upper_tail_target))
o<-tempfile("phase163_");d$readiness<-o;y<-app_joint_exqdesn_phase163_prepare(d);stopifnot(y$assessment$gate_status=="pass",file.exists(file.path(o,"artifact_manifest.csv")))
cat("Phase163 tail-calibration tests passed.\n")
