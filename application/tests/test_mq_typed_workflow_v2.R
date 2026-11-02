#!/usr/bin/env Rscript
# Generated numerical/serialization wiring only. No scientific fixture is read.
local({
 root<-if(exists("app_repo_root",mode="function"))app_repo_root() else {
  f<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
  normalizePath(file.path(dirname(f),"../.."),mustWork=TRUE)
 }
 setwd(root);source("scripts/mq_typed_workflow_v2.R",local=TRUE)
 checks<-0L;check<-function(ok){stopifnot(isTRUE(ok));checks<<-checks+1L}
 reject<-function(expr){e<-tryCatch({force(expr);NULL},error=base::identity);check(inherits(e,"error"))}
 before<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
 check(!mqw2_preflight()$allow_launch&&length(mqw2_preflight()$unresolved)==6L)
 reject(mqw2_context("production"));reject(mqw2_context(NULL))
 called<-FALSE
 reject(mqw2_run_unit(function(ids){called<<-TRUE},"d","o","m",list(),c(.1,.5,.9),1))
 check(!called)
 # Exact rowwise endpoint atoms, flat pieces and linear interpolation.
 tau<-c(.1,.5,.9);q<-rbind(c(-1,0,1),c(0,0,1),c(2,2,2));ys<-c(-2,-1,0,.5,1,2,3)
 got<-mqw2_cdf_rows(ys,q,tau)
 for(i in 1:3)for(j in seq_along(ys))check(abs(got[i,j]-app_iqf_mq_grid_cdf(ys[j],q[i,],tau))<1e-15)
 reject(mqw2_cdf_rows(0,rbind(c(0,-1,2)),tau))
 # Actual opt-in CLI -> typed block -> independent Python acceptance ->
 # independent R decode/validation -> typed score. Synthetic provider only.
 out<-tempfile("mqw2_generated_e2e_");request_path<-paste0(out,".request.json")
 worker<-system2("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
  c("--vanilla","scripts/run_integrated_quantile_forecast_v2.R","--generated-fixture-output",shQuote(out)),stdout=TRUE,stderr=TRUE)
 check(is.null(attr(worker,"status"))&&"GENERATED_TYPED_WORKER_COMPLETE_NOT_PRODUCTION"%in%worker)
 packet<-mqw2_validate_packet(out);check(length(packet$block$members)==2L)
 check(identical(vapply(packet$block$members,function(s)s$numerical_receipt$validation_count,0),c(65536,131072)))
 check(identical(vapply(packet$block$members,function(s)s$numerical_receipt$look_index,0L),1:2))
 check(file.info(file.path(out,"typed_block.rds"))$size<50000)
 receipt_path<-paste0(out,".acceptance.json")
 central<-system2("/usr/bin/python3.11",c("-I","-S","scripts/forecast_transition_typed_v2.py",
  "--generated-packet",shQuote(out),"--request",shQuote(request_path),"--receipt",shQuote(receipt_path)),stdout=TRUE,stderr=TRUE)
 if(!is.null(attr(central,"status"))){cat(paste(central,collapse="\n"),"\n");stop("generated acceptance failed")}
 check(is.null(attr(central,"status")))
 acceptance<-jsonlite::read_json(receipt_path,simplifyVector=FALSE)
 check(identical(acceptance$canonical_ledger_mutations,0L)&&identical(acceptance$production_authorized,FALSE))
 check(identical(acceptance$independent_numeric_recomputation,TRUE)&&identical(acceptance$independent_block_decoding,TRUE))
 oracle<-list(forecast_map=data.frame(origin_id="generated_o1",horizon=1L),observed_y=0,
  sorted_response=matrix(c(-2,-1,0,1,2),5,1),prefix_response=matrix(cumsum(c(-2,-1,0,1,2)),5,1),
  diagnostics=data.frame(status="pass"))
 scores<-mqw2_score_accepted(out,acceptance,oracle,tau,c(.2,.4,.2),"generated_fixture_only")
 check(nrow(scores)==2L&&all(is.finite(scores$score_sum))&&all(!scores$production_authorized))
 for(i in 1:2) {
  s<-iqr2_unpack(packet$block,i);y<-oracle$sorted_response[,1];expected<-2*sum(c(.2,.4,.2)*vapply(1:3,
   function(k)mean((tau[k]-(y<s$quantiles$quantile[k]))*(y-s$quantiles$quantile[k])),0))
  check(abs(scores$score_sum[i]-expected)<1e-12)
 }
 check(all(scores$numerical_quantile_error_score_bound>0))
 # No scorer may inspect an oracle until every typed member and binding pass.
 touched<-FALSE;bad<-acceptance;bad$wire_sha256<-strrep("0",64)
 reject(mqw2_score_accepted(out,bad,{touched<<-TRUE;oracle},tau,c(.2,.4,.2),"generated_fixture_only"));check(!touched)
 reject(mqw2_score_accepted(out,acceptance,{touched<<-TRUE;oracle},tau,c(.2,.4,.2)));check(!touched)
 reject(mqw2_score_member(iqr2_unpack(packet$block,1),{touched<<-TRUE;oracle},c(.5),1,"generated_fixture_only"));check(!touched)
 reject(mqw2_score_member(iqr2_unpack(packet$block,1),{touched<<-TRUE;oracle},c(.1,.5,.8),c(.2,.35,.15),"generated_fixture_only"));check(!touched)
 reject(mqw2_score_member(iqr2_unpack(packet$block,1),oracle,tau,c(.25,.5,.25),"generated_fixture_only"))
 # A structurally passing but unbound sidecar cannot hide altered R bytes.
 wire_path<-file.path(out,"numerical_wire.json");original_wire<-readBin(wire_path,"raw",n=file.info(wire_path)$size)
 wire<-jsonlite::read_json(wire_path,simplifyVector=FALSE)
 wire$members[[1]]$quantiles[[1]]$quantile<-wire$members[[1]]$quantiles[[1]]$quantile+.00001
 jsonlite::write_json(wire,wire_path,auto_unbox=TRUE,pretty=TRUE,digits=17)
 mpath<-file.path(out,"artifact_manifest.csv");m<-read.csv(mpath,stringsAsFactors=FALSE)
 at<-match("numerical_wire.json",m$relative_path);m$size_bytes[at]<-file.info(wire_path)$size;m$sha256[at]<-app_iqf_hash(wire_path,TRUE)
 write.csv(m,mpath,row.names=FALSE);reject(mqw2_validate_packet(out))
 writeBin(original_wire,wire_path);m$size_bytes[at]<-length(original_wire);m$sha256[at]<-app_iqf_hash(wire_path,TRUE)
 write.csv(m,mpath,row.names=FALSE);check(length(mqw2_validate_packet(out)$block$members)==2)
 # v1 remains deliberately incapable of treating v2 as a DKW PASS.
 reject(app_iqf_score_shard(iqr2_unpack(packet$block,1),{touched<<-TRUE;oracle},tau,c(.2,.4,.2)));check(!touched)
 # A failed training-half gate is REVIEW and generates no validation paths.
 identity<-packet$block$members[[1]]$identity;validation_calls<-0L
 provider<-function(ids){if(any(ids>65536))validation_calls<<-validation_calls+1L
  shift<-ifelse(ids<=32768,0,1);array(c(-1+shift,shift,1+shift),c(length(ids),3L,1L))}
 review<-mqw2_run_unit(provider,"review_d","review_o","generated_m",identity,tau,1L,"generated_fixture_only")
 check(identical(review$status,"REVIEW_TRAINING_SPLIT_NO_VALIDATION")&&validation_calls==0L&&is.null(review$shard))
 reject(mqw2_write_packet(packet$block$members,out,"generated_fixture_only"))
 after<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
 check(identical(before,after))
 cat(sprintf("MQ_TYPED_WORKFLOW_V2_PASS checks=%d production_launches=0 canonical_ledger_mutations=0\n",checks))
})
