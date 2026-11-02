# Synthetic early admission failures and per-path CDF parity. No RDS/model read.
source("scripts/qualify_mq_batch_acceleration.R")
baq_n <- 0L
baq_check <- function(ok) {stopifnot(isTRUE(ok));baq_n <<- baq_n+1L}
baq_reject <- function(expr,text=NULL) {
  e <- tryCatch({force(expr);NULL},error=identity)
  baq_check(inherits(e,"error") && (is.null(text)||grepl(text,conditionMessage(e),fixed=TRUE)))
}
baq_close <- function(a,b,tol=1e-12) isTRUE(all.equal(a,b,tolerance=tol,check.attributes=FALSE))
set.seed(81140);baq_rng <- .Random.seed
help <- capture.output(mq_baq_main("--help"))
baq_check(length(help)==1L && grepl("Usage:",help,fixed=TRUE))
baq_reject(mq_baq_main(character()),"exact contract/hash/execute arguments required")
unit <- list(schema_version="integrated_quantile_qualification_contract_v1",purpose="MQ_Q2_ONE_DRAW_ORIGIN",
  source_schema="mq_native_worker_v1",model_cell_id="asymmetric_laplace_tail__joint_qdesn_rhs",
  chain_id=1L,source_row=1L,source_draw_index=1L,origin_id=1L,origin_time=11000L,
  horizons=30L,inner_paths=4096L,readout_slopes=20L,tau=c(.05,.10,.25,.50,.75,.90,.95),
  posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
  rng_namespace="original-scientific-rng-fixture",
  integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,
    max_split_absolute=.005,max_split_relative=.005,max_quantile_abs_error=.01,max_quantile_rel_error=.01))
spec <- list(schema_version="mq_batch_acceleration_qualification_v1",allow_qualification=TRUE,
  allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article=FALSE,
  training_paths=4096L,validation_paths=32768L,batch_size=128L,inversion_tolerance=1e-8,
  parity_absolute_tolerance=1e-10,parity_relative_tolerance=1e-10,rng_backend="r46_first_step",
  original_unit=unit,source_commit=paste(rep("0",40),collapse=""),source_tree=paste(rep("0",40),collapse=""),
  limits=list(cpu_seconds=600L,wall_term_seconds=899L,wall_kill_after_seconds=1L,
    address_space_bytes=16*1024^3,output_bytes=256*1024^2))
baq_check(isTRUE(mq_baq_scope(spec)))
for(key in c("allow_refit","allow_production","allow_scoring","allow_article")) {
  x <- spec;x[[key]] <- TRUE
  baq_reject(mq_baq_scope(x),"qualification-only scope required")
}
for(key in c("training_paths","validation_paths","batch_size")) {
  x <- spec;x[[key]] <- x[[key]]+.5
  baq_reject(mq_baq_scope(x),"fixed prospective geometry")
}
for(key in c("inversion_tolerance","parity_absolute_tolerance","parity_relative_tolerance")) {
  x <- spec;x[[key]] <- x[[key]]*10
  baq_reject(mq_baq_scope(x),"fixed prospective geometry")
}
x <- spec;x$rng_backend <- "different_stream"
baq_reject(mq_baq_scope(x),"fixed prospective geometry")
for(key in names(spec$limits)) {
  x <- spec;x$limits[[key]] <- x$limits[[key]]+1
  baq_reject(mq_baq_scope(x),"fixed finite qualification budgets required")
}
for(key in c("alpha_per_shard","max_split_absolute","max_split_relative","max_quantile_abs_error","max_quantile_rel_error")) {
  x <- spec;x$original_unit$integration_accuracy[[key]] <- x$original_unit$integration_accuracy[[key]]+1e-5
  baq_reject(mq_baq_scope(x),"original numerical thresholds must remain unchanged")
}
for(key in c("source_row","source_draw_index","chain_id","origin_id")) {
  x <- spec;x$original_unit[[key]] <- 2L
  baq_reject(mq_baq_scope(x),"qualification geometry must be the frozen original unit")
}

# Wrong hash and wrong source fail before a model/RDS path is required.
path <- tempfile("synthetic_mq_batch_contract_",fileext=".json")
jsonlite::write_json(spec,path,auto_unbox=TRUE,pretty=TRUE,digits=17)
baq_reject(mq_baq_main(c("--contract",path,"--sha256",paste(rep("0",64),collapse=""),"--execute")),
  "bounded external purpose contract SHA mismatch")
sha <- unname(tools::sha256sum(path))
baq_reject(mq_baq_main(c("--contract",path,"--sha256",sha,"--execute")),"clean frozen source commit/tree required")
unlink(path)

# Matrix helper must retain each path's CDF. The historical matrix helper
# averages rows; only column means of this helper may equal that result.
tau <- c(.05,.5,.95)
q <- rbind(c(0,0,1),c(-1,0,0),c(3,3,3),c(-2,0,5))
y <- c(-Inf,-2,-1,0,.1,1,3,5,Inf)
fast <- mq_baq_cdf_rows(y,q,tau)
ref <- t(vapply(seq_len(nrow(q)),function(i)app_iqf_mq_grid_cdf(y,q[i,],tau),numeric(length(y))))
baq_check(identical(dim(fast),c(4L,length(y))))
baq_check(baq_close(fast,ref))
baq_check(baq_close(colMeans(fast),app_iqf_mq_matrix_cdf(y,q,tau)))
baq_check(baq_close(mq_baq_cdf_rows(y,q[4:1,,drop=FALSE],tau),fast[4:1,,drop=FALSE]))
baq_check(baq_close(mq_baq_cdf_rows(0,matrix(c(0,0,0),1L),tau),matrix(1,1L,1L)))
baq_check(baq_close(mq_baq_cdf_rows(-1,matrix(c(0,0,0),1L),tau),matrix(0,1L,1L)))
baq_check(fast[1L,which(y==0)]==.5) # all flat mass included
baq_check(fast[2L,which(y==0)]==1) # upper endpoint atom included
for(expr in list(
  quote(mq_baq_cdf_rows(NA_real_,q,tau)),
  quote(mq_baq_cdf_rows(0,matrix(c(1,0,2),1L),tau)),
  quote(mq_baq_cdf_rows(0,q,c(.5,.05,.95))),
  quote(mq_baq_cdf_rows(0,q[,1:2,drop=FALSE],tau)),
  quote(mq_baq_cdf_rows(0,matrix(numeric(),0L,3L),tau)),
  quote(mq_baq_cdf_rows(0,matrix(c(0,NA,1),1L),tau))
)) baq_reject(eval(expr))
baq_check(identical(.Random.seed,baq_rng))
cat(sprintf("MQ_BATCH_QUALIFICATION_GUARD_CHECKS=%d PASS; protected_reads=0 scientific_runs=0\n",baq_n))
