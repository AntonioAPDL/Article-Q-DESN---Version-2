#!/usr/bin/env Rscript
# Independent compact-artifact decoding, not source authentication/admission.
args<-commandArgs(TRUE)
if(!length(args)) {cat("MQ_PRODUCTION_NOT_ADMITTED\n");quit(save="no",status=0)}
stopifnot(length(args)==2L,args[1]=="--generated-packet")
script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
root<-normalizePath(file.path(dirname(script),".."),mustWork=TRUE);setwd(root)
source("scripts/mq_typed_workflow_v2.R")
checked<-mqw2_validate_packet(args[2])
cat(jsonlite::toJSON(list(status="GENERATED_TYPED_PACKET_BOUND_AND_VALIDATED_NOT_PRODUCTION",
 member_keys=checked$wire$expected_member_keys,block_file_sha256=checked$wire$block_file_sha256,
 production_authorized=FALSE),auto_unbox=TRUE,digits=17),"\n")
