#!/usr/bin/env Rscript
cache<-"/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"; r<-file.path(cache,"joint_qdesn_phase163_tail_calibration_readiness_20260806"); s<-file.path(cache,"joint_qdesn_phase163_tail_calibration_vb_20260806")
reg<-read.csv(file.path(r,"phase163_candidate_registry.csv"),stringsAsFactors=FALSE); done<-file.exists(file.path(reg$fit_dir,"artifact_manifest.csv"))&file.exists(file.path(reg$forecast_dir,"artifact_manifest.csv"))
cat(sprintf("Phase163 candidates complete: %d/%d; remaining: %d\n",sum(done),nrow(reg),sum(!done)))
if(file.exists(file.path(s,"phase163_result_assessment.csv"))) print(read.csv(file.path(s,"phase163_result_assessment.csv")),row.names=FALSE)
