#!/usr/bin/env Rscript
# There is deliberately no production/run authorization route in this scaffold.
args<-commandArgs(TRUE)
if(!length(args)) {cat("MQ_PRODUCTION_NOT_ADMITTED\n");quit(save="no",status=0)}
stopifnot(length(args)==2L,args[1]=="--generated-fixture-output")
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
root<-normalizePath(file.path(dirname(script),".."),mustWork=TRUE);setwd(root)
source("scripts/mq_typed_workflow_v2.R")
mqw2_generated_fixture(args[2])
cat("GENERATED_TYPED_WORKER_COMPLETE_NOT_PRODUCTION\n")
