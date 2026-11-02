# Negative guided-CLI admission checks; no original evidence is opened.
source("scripts/qualify_ind_guided_filter.R")
gq_n <- 0L
gq_check <- function(x){stopifnot(isTRUE(x));gq_n <<- gq_n+1L}
gq_error <- function(expr,message) {
  e <- tryCatch({force(expr);NULL},error=identity)
  gq_check(inherits(e,"error") && grepl(message,conditionMessage(e),fixed=TRUE))
}
set.seed(12983);gq_seed <- .Random.seed
help <- capture.output(ind_gaf_qualify("--help"))
gq_check(length(help)==1L && grepl("Usage:",help,fixed=TRUE))
gq_error(ind_gaf_qualify(character()),"length(args)")
contract <- list(schema_version="ind_guided_filter_qualification_v1",allow_qualification=TRUE,
  allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article_promotion=FALSE,
  allow_training_only_h1_diagnostics=TRUE,posterior_column=1L,observed_prefix_length=500L,
  particle_resolutions=c(64L,256L,1024L),seeds=c(71521L,71522L),
  checkpoint_indices=c(100L,250L,500L),probabilities=c(.05,.5,.95),ess_fraction=.5,
  inversion_absolute_tolerance=1e-8,agreement_absolute_tolerance=.005,
  agreement_relative_tolerance=.005,limits=list(cpu_seconds=1200L,wall_term_seconds=1199L,
    wall_kill_after_seconds=1L,address_space_bytes=16*1024^3,output_bytes=96*1024^2),
  source_commit=paste(rep("0",40),collapse=""))
path <- tempfile("synthetic_guided_filter_contract_",fileext=".json")
call <- function(x,sha=NULL) {
  jsonlite::write_json(x,path,auto_unbox=TRUE,pretty=TRUE,digits=17)
  if(is.null(sha))sha <- unname(tools::sha256sum(path))
  ind_gaf_qualify(c("--contract",path,"--sha256",sha,"--execute"))
}
gq_error(call(contract,paste(rep("0",64),collapse="")),"bounded external guided purpose contract")
for(mutate in list(
  function(x){x$allow_qualification <- FALSE;x},
  function(x){x$allow_refit <- TRUE;x},
  function(x){x$allow_production <- TRUE;x},
  function(x){x$allow_scoring <- TRUE;x},
  function(x){x$allow_article_promotion <- TRUE;x},
  function(x){x$allow_training_only_h1_diagnostics <- FALSE;x},
  function(x){x$posterior_column <- 2L;x},
  function(x){x$observed_prefix_length <- 501L;x},
  function(x){x$particle_resolutions[1L] <- 64.9;x},
  function(x){x$particle_resolutions <- c(32L,64L,128L);x},
  function(x){x$seeds[1L] <- 71521.5;x},
  function(x){x$seeds <- c(71421L,71422L);x},
  function(x){x$checkpoint_indices <- c(100L,251L,500L);x},
  function(x){x$probabilities <- c(.05,.5,.9);x},
  function(x){x$ess_fraction <- .1;x},
  function(x){x$inversion_absolute_tolerance <- 1e-7;x},
  function(x){x$agreement_absolute_tolerance <- .01;x},
  function(x){x$agreement_relative_tolerance <- .01;x}
))gq_error(call(mutate(contract)),"fixed prospective guided training-only diagnostic")
for(key in names(contract$limits)) {
  x <- contract;x$limits[[key]] <- x$limits[[key]]+1
  gq_error(call(x),"unchanged externally enforced finite guided limits")
}
gq_error(call(contract),"clean frozen guided qualification source")
unlink(path)
gq_check(identical(.Random.seed,gq_seed))
cat(sprintf("IND_GUIDED_QUALIFICATION_GUARD_CHECKS=%d PASS; protected_reads=0 guided_probes=0\n",gq_n))
