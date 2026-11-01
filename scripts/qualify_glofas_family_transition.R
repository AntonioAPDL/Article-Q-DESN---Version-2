#!/usr/bin/env Rscript
# Bounded numerical qualification only; never an article-result producer.
gftq_require <- function(ok,message) if (!isTRUE(ok)) stop(paste("GFT_QUALIFICATION:",message),call.=FALSE)
gftq_hash <- function(path) unname(tools::sha256sum(path))
gftq_json <- function(path) jsonlite::read_json(path,simplifyVector=FALSE)
gftq_scalar <- function(x) is.numeric(x)&&length(x)==1L&&is.finite(x)&&x>0
gftq_no_symlinks <- function(path) {
  gftq_require(is.character(path)&&length(path)==1L&&nzchar(path)&&
    !grepl("(^|/)\\.\\.(/|$)",path),"unsafe namespace")
  absolute<-if(startsWith(path,"/"))path else file.path(getwd(),path)
  current<-"/"
  for(part in strsplit(absolute,"/",fixed=TRUE)[[1L]])if(nzchar(part)) {
    current<-file.path(current,part);link<-Sys.readlink(current)
    gftq_require(is.na(link)||!nzchar(link),"symlink namespace component")
  }
  invisible(TRUE)
}
gftq_bounded_path <- function(root,relative) {
  gftq_require(is.character(relative)&&length(relative)==1L&&nzchar(relative)&&
    !grepl("(^/|(^|/)\\.\\.(/|$)|[\\\\\r\n])",relative),"unsafe relative input")
  path<-root
  for (part in strsplit(relative,"/",fixed=TRUE)[[1L]]) {
    path<-file.path(path,part); link<-Sys.readlink(path)
    gftq_require(is.na(link)||!nzchar(link),"symlink input component")
  }
  path<-normalizePath(path,mustWork=TRUE)
  gftq_require(startsWith(path,paste0(normalizePath(root,mustWork=TRUE),"/")),"input escaped root")
  path
}
gftq_contract <- function(path,expected_sha,repo,now=Sys.time(),verify_files=TRUE) {
  gftq_require(file.exists(path)&&identical(gftq_hash(path),expected_sha),"external purpose contract digest")
  gftq_require(!startsWith(normalizePath(path),paste0(normalizePath(repo),"/")),"purpose contract must be external")
  c<-gftq_json(path)
  gftq_require(identical(c$schema_version,"glofas_transition_qualification_v1")&&
    identical(c$purpose,"qualification_not_article")&&isTRUE(c$allow_real_qualification)&&
    identical(c$allow_production,FALSE)&&nzchar(c$approved_by),"not an explicit qualification-only approval")
  expiry<-as.POSIXct(c$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  gftq_require(!is.na(expiry)&&expiry>now,"purpose approval expired")
  gftq_require(c$iterations %in% 1:3&&identical(c$diagnostic_freeze_beta_warmup_iters,0L),
    "qualification must include coefficient updates in only 1–3 iterations")
  gftq_require(identical(as.integer(unlist(c$causality_probe_columns)),c(1L,14L,28L)),
    "representative real causality probes must be predeclared as columns 1,14,28")
  lim<-c$limits
  gftq_require(all(vapply(lim[c("memory_bytes","cpu_seconds_per_backend","wall_seconds_per_backend",
    "total_cpu_seconds","total_output_bytes")],gftq_scalar,logical(1L)))&&
    lim$memory_bytes<=32*1024^3&&lim$cpu_seconds_per_backend<=600&&
    lim$wall_seconds_per_backend<=1800&&lim$total_cpu_seconds<=1200&&
    2*lim$cpu_seconds_per_backend<=lim$total_cpu_seconds&&lim$total_output_bytes<=2*1024^3,
    "qualification limits exceed the reviewed finite scope")
  gftq_require(all(vapply(c$tolerances[c("linalg_absolute","moment_absolute","moment_relative")],gftq_scalar,logical(1L))),
    "predeclared numerical tolerances are required")
  outer<-c$outer_boundary
  gftq_require(is.list(outer)&&gftq_scalar(outer$wall_seconds)&&outer$wall_seconds+1<=lim$total_cpu_seconds&&
    identical(unlist(outer$timeout_prefix,use.names=FALSE),c("/usr/bin/timeout","--signal=TERM","--kill-after=1",
      as.character(outer$wall_seconds))),"whole-purpose timeout boundary is not explicit and finite")
  # Authorization must cover the complete bounded purpose, including the
  # final forced-termination second, not merely be valid at admission.
  purpose_deadline<-now+outer$wall_seconds+1
  gftq_require(expiry>=purpose_deadline,"purpose approval does not cover the whole execution boundary")
  gftq_require(all(vapply(c[c("source_manifest_sha256","input_manifest_sha256","resource_grant_sha256")],
    function(x)is.character(x)&&length(x)==1L&&grepl("^[0-9a-f]{64}$",x),logical(1L))),"missing source/input/grant pins")
  gftq_require(file.exists(c$resource_grant_path)&&identical(gftq_hash(c$resource_grant_path),c$resource_grant_sha256),
    "physical-core grant is absent or changed")
  grant<-gftq_json(c$resource_grant_path)
  grant_expiry<-as.POSIXct(grant$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  gftq_require(identical(grant$schema_version,"glofas_qualification_resource_grant_v1")&&
    identical(grant$purpose,c$purpose)&&identical(grant$host,c$host)&&isTRUE(grant$ownership_verified)&&
    isTRUE(grant$smt_siblings_checked)&&length(grant$logical_cpus)==1L&&
    !is.na(grant_expiry)&&grant_expiry>=purpose_deadline&&nzchar(grant$owner)&&
    grant$memory_bytes>=lim$memory_bytes&&grant$total_output_bytes>=lim$total_output_bytes,
    "missing bounded physical-core ownership/resource grant")
  c$verified_resource_grant<-grant
  gftq_no_symlinks(c$output_root)
  output<-normalizePath(c$output_root,mustWork=FALSE)
  allowed<-paste0(normalizePath(repo,mustWork=TRUE),"/local_trackers/")
  gftq_require(startsWith(output,allowed)&&!grepl("(^|/)\\.\\.(/|$)",output)&&
    !startsWith(output,paste0(normalizePath(c$input_root,mustWork=TRUE),"/")),
    "qualification output must remain in the fresh ignored lane, not source evidence")
  if (!isTRUE(verify_files)) return(c)
  gftq_require(identical(as.character(getRversion()),"4.6.0"),"qualification requires pinned R 4.6.0")
  git<-function(arg) system2("git",c("-C",shQuote(repo),arg),stdout=TRUE,stderr=FALSE)
  gftq_require(identical(git(c("rev-parse","HEAD")),c$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),c$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=normal"))),"source commit/tree must be exact and clean")
  gftq_require(identical(gftq_hash(c$source_manifest_path),c$source_manifest_sha256),"source inventory digest")
  src<-read.csv(c$source_manifest_path,colClasses="character")
  gftq_require(all(c("path","role","mode","sha256","blob")%in%names(src))&&
    "scripts/qualify_glofas_family_transition.R"%in%src$path,"qualification source is not explicitly inventoried")
  for(i in seq_len(nrow(src))) {
    actual<-gftq_bounded_path(repo,src$path[i])
    gftq_require(identical(gftq_hash(actual),src$sha256[i]),"source file bytes changed")
  }
  gftq_require(identical(gftq_hash(c$input_manifest_path),c$input_manifest_sha256),"input inventory digest")
  inputs<-read.csv(c$input_manifest_path,stringsAsFactors=FALSE)
  gftq_require(all(c("relative_path","size_bytes","sha256","role")%in%names(inputs))&&
    !anyDuplicated(inputs$relative_path)&&
    all(c("truth_free_shared_design","normal_moment_initializer","frozen_median_configuration")%in%inputs$role)&&
    !any(grepl("scoring|truth_sidecar",inputs$role)),"qualification input roles are incomplete or unsafe")
  for(i in seq_len(nrow(inputs))) {
    actual<-gftq_bounded_path(c$input_root,inputs$relative_path[i])
    gftq_require(file.info(actual)$size==inputs$size_bytes[i]&&identical(gftq_hash(actual),inputs$sha256[i]),"input bytes changed")
  }
  for(name in c("bundled","openblas")) {
    lib<-c$libraries[[name]]
    gftq_require(file.exists(lib$path)&&identical(gftq_hash(lib$path),lib$sha256),"numeric library pin changed")
  }
  open_path<-normalizePath(c$libraries$openblas$path)
  gftq_require(!grepl("(openblas64|openblasp64|openblaso64|ilp64)",tolower(open_path)),"ILP64 library cannot replace R LP64 BLAS")
  c
}
gftq_actual_boundary <- function(contract) {
  clean<-c(R_PROFILE_USER="/dev/null",R_ENVIRON_USER="/dev/null",R_MAKEVARS_USER="/dev/null",
    R_LIBS_USER="",R_LIBS_SITE="")
  gftq_require(identical(unname(Sys.getenv(names(clean),unset="")),unname(clean)),"parent/worker startup environment is not explicitly clean")
  status<-readLines("/proc/self/status",warn=FALSE)
  affinity<-trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",status,value=TRUE)))
  cpu<-as.character(unlist(contract$verified_resource_grant$logical_cpus,use.names=FALSE))
  gftq_require(identical(affinity,cpu),"parent/worker affinity differs from the physical-core grant")
  limits<-readLines("/proc/self/limits",warn=FALSE)
  hard<-function(label) {
    row<-grep(paste0("^",label,"[[:space:]]+"),limits,value=TRUE)
    gftq_require(length(row)==1L,"missing actual OS resource limit")
    fields<-strsplit(trimws(sub(paste0("^",label,"[[:space:]]+"),"",row)),"[[:space:]]+")[[1L]]
    suppressWarnings(as.numeric(fields[2L]))
  }
  observed<-c(memory_bytes=hard("Max address space"),cpu_seconds=hard("Max cpu time"),file_bytes=hard("Max file size"))
  gftq_require(all(is.finite(observed))&&all(observed>0)&&
    observed[["memory_bytes"]]<=contract$limits$memory_bytes&&
    observed[["cpu_seconds"]]<=contract$limits$total_cpu_seconds&&
    observed[["file_bytes"]]<=contract$limits$total_output_bytes,"actual OS boundaries exceed purpose contract")
  prefix<-unlist(contract$outer_boundary$timeout_prefix,use.names=FALSE)
  pid<-Sys.getpid();matched<-FALSE
  for(i in 1:20) {
    pstatus<-tryCatch(readLines(sprintf("/proc/%d/status",pid),warn=FALSE),error=function(e)character())
    parent<-grep("^PPid:",pstatus,value=TRUE)
    if(!length(parent))break
    pid<-as.integer(trimws(sub("^PPid:","",parent)))
    if(!is.finite(pid)||pid<=1L)break
    cmd<-tryCatch(readBin(sprintf("/proc/%d/cmdline",pid),"raw",n=65536L),error=function(e)raw())
    if(length(cmd)) {
      text<-rawToChar(cmd,multiple=TRUE)
      argv<-strsplit(paste0(ifelse(text=="","\n",text),collapse=""),"\n",fixed=TRUE)[[1L]]
      if(length(argv)>=length(prefix)&&identical(argv[seq_along(prefix)],prefix)){matched<-TRUE;break}
    }
  }
  gftq_require(matched,"whole-purpose outer timeout is not present in this process ancestry")
  list(affinity=affinity,actual_hard_limits=as.list(observed),outer_timeout_prefix=as.list(prefix),startup_environment=as.list(clean),
    whole_purpose_single_cpu_bound=TRUE)
}
gftq_linalg <- function() {
  A<-matrix(sin(seq_len(193L*47L)/13),193L,47L)
  M<-crossprod(A)+diag(2,47L);b<-cos(seq_len(47L))
  solution<-solve(M,b)
  list(crossprod=crossprod(A),solution=as.numeric(solution),
    residual=max(abs(as.numeric(M%*%solution)-b)),inverse=solve(M))
}
gftq_compare <- function(a,b,tolerances) {
  fields<-c("theta_mean","theta_cov","future_mean","future_cov","sigma_shape","sigma_rate")
  rows<-lapply(fields,function(name) {
    x<-as.numeric(a[[name]]);y<-as.numeric(b[[name]])
    gftq_require(length(x)==length(y)&&all(is.finite(c(x,y))),"incompatible/nonfinite qualification moments")
    absolute<-max(abs(x-y));relative<-max(abs(x-y)/pmax(1,abs(x),abs(y)))
    data.frame(quantity=name,max_absolute=absolute,max_relative=relative,
      pass=absolute<=tolerances$moment_absolute||relative<=tolerances$moment_relative)
  })
  do.call(rbind,rows)
}
gftq_symbol_probe <- function(cache) {
  gftq_require(requireNamespace("Rcpp",quietly=TRUE),"Rcpp is needed for actual dladdr symbol provenance")
  env<-new.env(parent=baseenv())
  Rcpp::cppFunction('Rcpp::List gftq_symbols() {
    void *p=dlsym(RTLD_DEFAULT,"dgemm_"); Dl_info info;
    std::string provider="";
    if(p && dladdr(p,&info) && info.dli_fname) provider=info.dli_fname;
    typedef const char* (*config_t)(); typedef int (*threads_t)();
    config_t config=(config_t)dlsym(RTLD_DEFAULT,"openblas_get_config");
    threads_t threads=(threads_t)dlsym(RTLD_DEFAULT,"openblas_get_num_threads");
    return Rcpp::List::create(Rcpp::Named("dgemm_provider")=provider,
      Rcpp::Named("openblas_config")=config ? std::string(config()) : std::string("not_loaded"),
      Rcpp::Named("openblas_threads")=threads ? threads() : 0);
  }',includes="#include <dlfcn.h>",plugins="cpp11",env=env,cacheDir=cache,
    showOutput=FALSE,verbose=FALSE)
  env$gftq_symbols()
}
gftq_usage <- function(root) {
  paths<-list.files(root,all.files=TRUE,recursive=TRUE,full.names=TRUE,no..=TRUE)
  sum(as.numeric(file.info(paths)$size))
}
gftq_worker <- function(contract,backend,repo,output) {
  gftq_require(backend%in%c("bundled","openblas"),"unknown qualification backend")
  gftq_require(identical(strsplit(tolower(Sys.info()[["nodename"]]),".",fixed=TRUE)[[1L]][1L],contract$host),"qualification on wrong host")
  boundary<-gftq_actual_boundary(contract)
  cpu<-as.integer(unlist(contract$verified_resource_grant$logical_cpus))
  status<-readLines("/proc/self/status",warn=FALSE)
  affinity<-trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",status,value=TRUE)))
  gftq_require(identical(affinity,as.character(cpu))&&
    Sys.getenv("OPENBLAS_NUM_THREADS")=="1"&&Sys.getenv("OMP_NUM_THREADS")=="1","worker is not single-thread/core granted")
  gftq_require(!file.exists(output)&&dir.exists(dirname(output)),"qualification output must be new and bounded")
  dir.create(output,recursive=FALSE)
  probe<-gftq_symbol_probe(file.path(output,"symbol_probe_cache"))
  expected_lib<-normalizePath(contract$libraries[[backend]]$path)
  gftq_require(identical(normalizePath(probe$dgemm_provider),expected_lib),"actual dgemm symbol does not use pinned backend")
  if(backend=="openblas") gftq_require(!grepl("USE64BITINT",probe$openblas_config)&&probe$openblas_threads==1L,
    "OpenBLAS integer ABI/thread count failed")
  linear<-gftq_linalg()
  gftq_require(linear$residual<=contract$tolerances$linalg_absolute,"deterministic linear solve residual failed")
  source(file.path(repo,"application/scripts/_glofas_unit_member_bootstrap.R"))
  source(file.path(repo,"application/R/glofas_family_transition.R"))
  app_qdesn_engine_function<-function(...)stop("Qualification cannot load a moving external feature engine.")
  assign("app_qdesn_engine_function",app_qdesn_engine_function,envir=.GlobalEnv)
  input<-read.csv(contract$input_manifest_path,stringsAsFactors=FALSE)
  bind<-function(role) {
    row<-input[input$role==role,,drop=FALSE]
    gftq_require(nrow(row)==1L,"qualification role is ambiguous")
    gftq_bounded_path(contract$input_root,row$relative_path)
  }
  design_path<-bind("truth_free_shared_design");normal_path<-bind("normal_moment_initializer")
  frozen<-readRDS(design_path);normal<-readRDS(normal_path)
  initial_probe<-frozen$future_builder(as.numeric(frozen$y_future_init))
  attr(frozen,"future_probe_init")<-initial_probe
  gftq_require(identical(normal$shared_design_reference$sha256,gftq_hash(design_path))&&
    identical(normal$fit$likelihood_family,"normal")&&isTRUE(normal$fit$vb_diagnostics$converged)&&
    identical(normal$state_contract_hash,app_glofas_part4_state_contract_hash(frozen)),"Normal initializer provenance mismatch")
  started<-proc.time()
  # Same metadata-only construction as the production materializer, but no
  # duplicate 28-column finite-difference sweeps in this bounded cost pilot.
  design<-frozen
  design$historical_unit_member_contract<-design$unit_member_contract
  design$unit_member_contract<-NULL
  design$family_transition_contract<-app_glofas_family_transition_contract()
  design$design_version<-paste0(design$design_version,"__same_family_transition_v1")
  protected<-c("H_fixed","z_fixed","source_fixed","weight_fixed","future_key","beta_index","alpha_index","intercept_index")
  gftq_require(all(vapply(protected,function(k)identical(design[[k]],frozen[[k]]),logical(1L))),"qualification changed protected geometry")
  counts<-app_glofas_family_transition_validate_design(design,check_finite_difference=FALSE)
  for(j in as.integer(unlist(contract$causality_probe_columns))) {
    path<-as.numeric(design$y_future_init);path[j]<-path[j]+.03125
    changed<-design$future_builder(path)
    gftq_require(max(abs(changed$H_y[seq_len(j),,drop=FALSE]-initial_probe$H_y[seq_len(j),,drop=FALSE]))<=1e-10&&
      max(abs(app_latent_future_H_g_key(changed)[seq_len(j),,drop=FALSE]-
        app_latent_future_H_g_key(initial_probe)[seq_len(j),,drop=FALSE]))<=1e-10&&
      identical(as.numeric(changed$z_g),as.numeric(initial_probe$z_g)),"representative actual-builder causality probe failed")
  }
  builder_elapsed<-unname((proc.time()-started)[["elapsed"]])
  cfg<-app_read_config(bind("frozen_median_configuration"))
  original<-app_glofas_family_transition_controls(app_make_qdesn_discrepancy_vb_args(cfg,"rhs_ns",
    seed=as.integer(contract$seed),likelihood_family="al"),cfg$unit_member_execution)
  diagnostic<-original
  diagnostic$max_iter<-as.integer(contract$iterations)
  diagnostic$max_iter_hard_cap<-diagnostic$max_iter
  diagnostic$min_iter_elbo<-diagnostic$max_iter
  diagnostic$freeze_beta_warmup_iters<-0L
  diagnostic$min_beta_updates<-diagnostic$max_iter
  diagnostic$diagnostics<-list(fixed_iterations=TRUE,profile_substeps=TRUE)
  diagnostic$initial_state<-app_gft_moment_initializer(normal,design)
  gftq_require(identical(original[c("beta_rhs","alpha_rhs","prior_sigma")],
    diagnostic[c("beta_rhs","alpha_rhs","prior_sigma")]),"qualification changed a prior")
  fit_started<-proc.time()
  fit<-app_fit_latent_path_al_vb_core(design,.5,"rhs_ns",diagnostic,seed=as.integer(contract$seed))
  fit_elapsed<-unname((proc.time()-fit_started)[["elapsed"]])
  gftq_require(isTRUE(fit$vb_diagnostics$future_y_working_likelihood_used)&&
    !isTRUE(fit$vb_diagnostics$future_gaussian_prior_used)&&
    fit$vb_diagnostics$beta_update_count==contract$iterations,"qualification executed wrong target/froze coefficients")
  expected_shapes<-c(Y=original$prior_sigma$a+1.5*(counts$historical_Y+counts$future_Y),
    G=original$prior_sigma$a+1.5*(counts$historical_G+counts$future_G))
  gftq_require(max(abs(fit$variational_state$sigma$shape[c("Y","G")]-expected_shapes))<1e-10,
    "AL future/historical source-count shapes differ from the frozen target")
  moments<-list(theta_mean=fit$summary$theta_mean,theta_cov=fit$summary$theta_cov,
    future_mean=fit$summary$y_future_mean,future_cov=fit$summary$y_future_cov,
    sigma_shape=fit$variational_state$sigma$shape,sigma_rate=fit$variational_state$sigma$rate)
  gftq_require(all(is.finite(unlist(moments)))&&all(diag(moments$future_cov)>0),"nonfinite qualification moments")
  raw<-serialize(moments,NULL,version=3L)
  gftq_require(gftq_usage(dirname(output))+length(raw)+1024^2<=contract$limits$total_output_bytes,"qualification output cap before moments write")
  writeBin(raw,file.path(output,"moments.rds"))
  saveRDS(linear,file.path(output,"linalg.rds"),compress=FALSE)
  receipt<-list(schema_version="glofas_transition_qualification_receipt_v1",purpose="qualification_not_article",
    backend=backend,source_commit=contract$source_commit,source_manifest_sha256=contract$source_manifest_sha256,
    input_manifest_sha256=contract$input_manifest_sha256,library_sha256=contract$libraries[[backend]]$sha256,
    symbol_probe=probe,loaded_numeric_libraries=app_latent_runtime_loaded_numeric_libraries(),
    numerical_backend=app_latent_runtime_backend_manifest(fail_closed=TRUE),counts=counts,
    actual_boundary=boundary,
    real_causality_scope="PARTIAL_REAL_CAUSALITY_PROBE_NOT_PRODUCTION_VALIDATION",
    finite_difference_columns=contract$causality_probe_columns,all_declared_horizon_jacobians_checked=TRUE,
    full_real_production_validation_still_required=TRUE,
    builder_elapsed_seconds=builder_elapsed,fit_elapsed_seconds=fit_elapsed,
    requested_iterations=contract$iterations,actual_iterations=fit$vb_diagnostics$iterations,
    beta_updates=fit$vb_diagnostics$beta_update_count,production_controls=original[c("max_iter","min_iter_elbo",
      "freeze_beta_warmup_iters","min_beta_updates")],diagnostic_override=list(freeze_beta=0L,fixed_iterations=TRUE),
    prior=original[c("beta_rhs","alpha_rhs","prior_sigma")],
    theta_precision_repaired=fit$vb_diagnostics$theta_precision_repaired,
    numerical_regularization="unchanged_source_path_jitter_1e-8",
    converged_scientific_result=FALSE,article_promotion_authorized=FALSE,
    iteration_timing=fit$vb_diagnostics$iteration_timing,session_info=capture.output(sessionInfo()))
  jsonlite::write_json(receipt,file.path(output,"receipt.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
  gftq_require(gftq_usage(dirname(output))<=contract$limits$total_output_bytes,"qualification cumulative output cap")
  invisible(receipt)
}

gftq_main <- function(argv=commandArgs(TRUE)) {
  arg<-function(name,default=NULL) {i<-match(paste0("--",name),argv);if(is.na(i))default else argv[i+1L]}
  mode<-arg("mode","synthetic")
  if(mode=="synthetic") {
    result<-gftq_linalg()
    gftq_require(result$residual<1e-10,"synthetic linear algebra check")
    cat("SYNTHETIC_QUALIFICATION_ONLY: no production evidence, model or subprocess loaded.\n")
    return(invisible(result))
  }
  gftq_require(mode%in%c("real","worker"),"unknown qualification mode")
  file<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
  repo<-normalizePath(file.path(dirname(file),".."),mustWork=TRUE);setwd(repo)
  contract_path<-arg("purpose-contract");contract_sha<-arg("purpose-contract-sha256")
  gftq_require(!is.null(contract_path)&&!is.null(contract_sha),"real qualification needs pinned external purpose contract")
  contract<-gftq_contract(contract_path,contract_sha,repo)
  boundary<-gftq_actual_boundary(contract)
  output<-normalizePath(contract$output_root,mustWork=FALSE)
  if(mode=="worker") return(gftq_worker(contract,arg("backend"),repo,file.path(output,arg("backend"))))
  gftq_require(!file.exists(output)&&dir.exists(dirname(output)),"qualification output root must be new")
  dir.create(output,recursive=FALSE)
  jsonlite::write_json(list(schema_version="glofas_qualification_entry_receipt_v1",purpose="qualification_not_article",
    purpose_contract_sha256=contract_sha,resource_grant_sha256=contract$resource_grant_sha256,
    actual_boundary=boundary,source_commit=contract$source_commit),file.path(output,"entry_receipt.json"),
    auto_unbox=TRUE,pretty=TRUE,digits=17)
  script<-normalizePath(file,mustWork=TRUE)
  for(backend in c("bundled","openblas")) {
    lib<-contract$libraries[[backend]]
    env<-c("OMP_NUM_THREADS=1","OMP_THREAD_LIMIT=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
      "GOTO_NUM_THREADS=1","BLIS_NUM_THREADS=1","VECLIB_MAXIMUM_THREADS=1","NUMEXPR_NUM_THREADS=1",
      "R_PROFILE_USER=/dev/null","R_ENVIRON_USER=/dev/null","R_MAKEVARS_USER=/dev/null","R_LIBS_USER=","R_LIBS_SITE=",
      "MAKEFLAGS=-j1",paste0("QDESN_NUMERICAL_BACKEND=",if(backend=="bundled")"bundled_rblas"else"openblas_pthread"))
    env_args<-if(backend=="bundled")c("-u","LD_PRELOAD","-u","QDESN_BLAS_LIBRARY_PATH","-u","QDESN_BLAS_LIBRARY_SHA256") else
      c(paste0("LD_PRELOAD=",lib$path),paste0("QDESN_BLAS_LIBRARY_PATH=",lib$path),paste0("QDESN_BLAS_LIBRARY_SHA256=",lib$sha256))
    limits<-contract$limits
    command<-c(paste0("--as=",format(limits$memory_bytes,scientific=FALSE)),
      paste0("--cpu=",limits$cpu_seconds_per_backend),paste0("--fsize=",format(limits$total_output_bytes,scientific=FALSE)),
      "--","/usr/bin/taskset","-c",as.character(unlist(contract$verified_resource_grant$logical_cpus)),
      # One inherited CPU plus this stricter wall bound limits aggregate worker
      # and compiler CPU, rather than counting only the parent R process.
      "/usr/bin/timeout","--signal=TERM","--kill-after=1",as.character(min(
        limits$wall_seconds_per_backend,limits$cpu_seconds_per_backend-1)),
      "/usr/bin/time","-v","-o",file.path(output,paste0(backend,".time.txt")),
      "/usr/bin/env",env_args,env,file.path(R.home("bin"),"Rscript"),script,"--mode","worker",
      "--backend",backend,"--purpose-contract",contract_path,"--purpose-contract-sha256",contract_sha)
    status<-system2("/usr/bin/prlimit",vapply(command,shQuote,character(1L)),
      stdout=file.path(output,paste0(backend,".stdout.log")),stderr=file.path(output,paste0(backend,".stderr.log")))
    gftq_require(status==0L,paste(backend,"qualification failed; partial receipts retained, no automatic retry"))
    gftq_require(gftq_usage(output)<=limits$total_output_bytes,"cumulative qualification output budget")
  }
  a<-readRDS(file.path(output,"bundled/moments.rds"));b<-readRDS(file.path(output,"openblas/moments.rds"))
  comparison<-gftq_compare(a,b,contract$tolerances)
  la<-readRDS(file.path(output,"bundled/linalg.rds"));lb<-readRDS(file.path(output,"openblas/linalg.rds"))
  linalg_error<-max(abs(unlist(la)-unlist(lb)))
  passed<-all(comparison$pass)&&linalg_error<=contract$tolerances$linalg_absolute
  write.csv(comparison,file.path(output,"moment_comparison.csv"),row.names=FALSE)
  jsonlite::write_json(list(status=if(passed)"QUALIFICATION_PASS_NOT_ARTICLE_AUTHORITY"else"QUALIFICATION_FAIL",
    purpose="qualification_not_article",source_commit=contract$source_commit,iterations=contract$iterations,
    linalg_max_absolute=linalg_error,article_promotion_authorized=FALSE,new_production_fits=0L),
    file.path(output,"decision.json"),auto_unbox=TRUE,pretty=TRUE)
  gftq_require(passed,"predeclared backend-parity tolerance failed; no production promotion")
  cat("QUALIFICATION_PASS_NOT_ARTICLE_AUTHORITY\n")
}
if(sys.nframe()==0L)gftq_main()
