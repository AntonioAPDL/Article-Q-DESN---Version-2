#!/usr/bin/env Rscript
# Explicit software/runtime inventory only; no scientific payload or forecast.
source("scripts/mq_native_source_qualification.R",local=TRUE)
source("scripts/mq_native_qualification_backend.R",local=TRUE)
mqnr_scope <- function(s) {
  q<-mqns_require;mqa_unique_json_objects(s)
  expected<-c("schema_version","purpose","actor_nonce","expires_utc","source_commit","source_tree",
    "origin_remote_url","published_ref","source_files","source_manifest","retained_build_receipt",
    "retained_build_terminal","output_root","limits","allow_runtime_inventory","allow_qualification",
    "allow_refit","allow_scoring","allow_prepared_read","allow_future_truth","allow_production","allow_article")
  q(is.list(s)&&setequal(names(s),expected)&&length(s)==length(expected)&&
    identical(s$schema_version,"mq_native_runtime_enrollment_purpose_v1")&&
    identical(s$purpose,"RETAINED_DLL_AND_RUNTIME_INVENTORY_ONLY")&&identical(s$allow_runtime_inventory,TRUE),
    "separate runtime-only purpose required")
  for(k in c("allow_qualification","allow_refit","allow_scoring","allow_prepared_read",
    "allow_future_truth","allow_production","allow_article"))q(identical(s[[k]],FALSE),"runtime inventory cannot grant scientific reads/execution")
  q(is.character(s$actor_nonce)&&length(s$actor_nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$actor_nonce),"fresh metadata nonce required")
  for(k in c("source_commit","source_tree"))q(mqa_hex(s[[k]],40),"exact metadata source identity required")
  q(identical(s$origin_remote_url,"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git")&&
    is.character(s$published_ref)&&length(s$published_ref)==1L&&!is.na(s$published_ref)&&
    grepl("^refs/heads/[A-Za-z0-9][A-Za-z0-9_./-]*$",s$published_ref)&&
    !grepl("\\.\\.|//|/$",s$published_ref),"approved origin and safe published source ref required")
  l<-s$limits
  q(is.list(l)&&setequal(names(l),c("cpu_seconds","wall_term_seconds","wall_kill_after_seconds",
    "address_space_bytes","output_bytes","logical_cpu"))&&mqa_equal(l$cpu_seconds,120)&&
    mqa_equal(l$wall_term_seconds,119)&&mqa_equal(l$wall_kill_after_seconds,1)&&
    mqa_equal(l$address_space_bytes,2*1024^3)&&mqa_equal(l$output_bytes,64*1024^2)&&
    mqa_equal(l$logical_cpu,27),"fixed finite runtime-enrollment limits required")
  invisible(TRUE)
}
mqnr_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/enroll_mq_native_runtime.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q<-mqns_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),"explicit external metadata purpose/hash required")
  for(p in c("digest","jsonlite","tools","compiler"))q(requireNamespace(p,quietly=TRUE),"metadata package missing")
  root<-normalizePath(getwd(),mustWork=TRUE);cp<-normalizePath(args[2L],mustWork=TRUE);q2_regular(cp)
  q(!startsWith(cp,paste0(root,"/"))&&file.info(cp)$size<=1024^2&&
    identical(unname(tools::sha256sum(cp)),args[4L]),"external exact metadata purpose bytes required")
  s<-jsonlite::read_json(cp,simplifyVector=FALSE);mqnr_scope(s)
  q(q2_time(s$expires_utc)>Sys.time()+120,"purpose must cover whole metadata budget")
  q(identical(as.character(getRversion()),"4.6.0")&&
    identical(normalizePath(R.home()),"/data/jaguir26/local/opt/R/4.6.0/lib64/R")&&
    "--vanilla"%in%commandArgs(FALSE)&&!nzchar(Sys.getenv("LD_PRELOAD"))&&!nzchar(Sys.getenv("LD_AUDIT"))&&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),"native single-thread clean software runtime required")
  q2_limits(list(logical_cpu=27L,max_cpu_seconds=120,max_wall_seconds=120,
    max_memory_bytes=2*1024^3,max_output_bytes=64*1024^2))
  timeout<-mqa_timeout_ancestor(119L)
  mqns_source_guard(s,root)
  output<-s$output_root;q2_regular(output)
  q(is.character(output)&&length(output)==1L&&
    startsWith(output,"/home/jaguir26/.local/state/qdesn_forecast_transition/")&&
    !file.exists(output)&&dir.exists(dirname(output))&&
    identical(dirname(output),normalizePath(dirname(output),mustWork=TRUE)),"fresh canonical private metadata output required")
  q(dir.create(output,mode="0700"),"metadata output creation failed")
  build<-mqns_build_receipt(s,root)
  # This public registered-symbol routine loads code only. No numerical handle
  # is created, and no authentic array, parameter, history or truth is read.
  symbols<-mqnk_registered_symbols(build,may_load=TRUE)
  for(f in mqns_native_files())source(file.path(root,f),local=.GlobalEnv)
  mqns_lapack_warmup()
  before<-runtime_ic_snapshot();files<-mqa_runtime_paths()
  pins<-lapply(files,function(path)list(path=path,size_bytes=as.numeric(file.info(path)$size),sha256=unname(tools::sha256sum(path))))
  q(!anyDuplicated(files)&&all(vapply(pins,function(x)is.finite(x$size_bytes)&&x$size_bytes>0&&mqa_hex(x$sha256),logical(1L))),"complete runtime pins required")
  rows<-data.frame(path=files,size_bytes=vapply(pins,`[[`,0,"size_bytes"),sha256=vapply(pins,`[[`,"","sha256"))
  write.csv(rows,file.path(output,"mq_native_runtime_files.csv"),row.names=FALSE)
  maps<-readLines("/proc/self/maps",warn=FALSE)
  writeLines(maps,file.path(output,"runtime_process_maps.txt"))
  mqns_source_guard(s,root)
  mqns_build_receipt(s,root)
  q(q2_time(s$expires_utc)>Sys.time(),"metadata purpose expired")
  receipt<-list(schema_version="mq_native_runtime_enrollment_receipt_v1",status="RUNTIME_METADATA_ENROLLED_NOT_NUMERICAL_QUALIFICATION",
    source_commit=s$source_commit,source_tree=s$source_tree,purpose_contract_sha256=args[4L],
    retained_build_receipt=s$retained_build_receipt,retained_build_terminal=s$retained_build_terminal,
    timeout=timeout,runtime_files=length(files),runtime_bytes=sum(rows$size_bytes),
    observational_os_state_before=before$observational_os_state,
    observational_os_state_after=runtime_ic_snapshot()$observational_os_state,
    role="SDK_PACKAGE_LIBRARY_METADATA_AND_VERIFIED_DLL_LOADING_ONLY",numerical_handles_created=0L,
    scientific_parameter_or_history_reads=0L,scientific_forecasts=0L,fits=0L,truth_reads=0L,
    C_ABI_qualified=FALSE,production_authorized=FALSE,article_promotion_authorized=FALSE)
  jsonlite::write_json(receipt,file.path(output,"RUNTIME_ENROLLMENT.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
  q(sum(file.info(list.files(output,full.names=TRUE))$size)<64*1024^2,"metadata output exceeds finite cap")
  cat("MQ_NATIVE_RUNTIME_METADATA_ENROLLED scientific_reads=0 forecasts=0 production=FALSE\n")
}
if(sys.nframe()==0L)mqnr_main()
