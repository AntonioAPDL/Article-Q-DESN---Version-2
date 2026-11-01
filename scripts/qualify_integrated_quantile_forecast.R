#!/usr/bin/env Rscript
# One authentic MQ draw/origin qualification only. No fitting, scoring or promotion.
q2_require <- function(ok, why) if (!isTRUE(ok)) stop(paste("IQF_Q2:",why),call.=FALSE)
q2_sha <- function(path) digest::digest(file=path,algo="sha256",serialize=FALSE)
q2_json <- function(path) jsonlite::fromJSON(path,simplifyVector=FALSE)
q2_time <- function(value) as.POSIXct(value,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
q2_regular <- function(path) {
  q2_require(length(path)==1L && startsWith(path,"/") && !grepl("(^|/)\\.\\.(/|$)",path),"unsafe absolute path")
  current<-"/"
  for(piece in strsplit(path,"/",fixed=TRUE)[[1L]]) if(nzchar(piece)) {
    current<-file.path(current,piece); link<-Sys.readlink(current)
    q2_require(is.na(link)||!nzchar(link),"symlink input/output ancestry")
  }
  invisible(TRUE)
}
q2_geometry <- function(c) {
  q2_require(identical(c$schema_version,"integrated_quantile_qualification_contract_v1") &&
    identical(c$purpose,"MQ_Q2_ONE_DRAW_ORIGIN") && identical(c$source_schema,"mq_native_worker_v1"),"wrong qualification scope/schema")
  q2_require(identical(c$model_cell_id,"asymmetric_laplace_tail__joint_qdesn_rhs") &&
    c$chain_id==1L && c$source_row==1L && c$source_draw_index==1L && c$origin_id==1L &&
    c$origin_time==11000L && c$horizons==30L && c$inner_paths==4096L && c$readout_slopes==20L &&
    identical(as.numeric(unlist(c$tau)),c(.05,.10,.25,.50,.75,.90,.95)),"qualification geometry must be the frozen original unit")
  q2_require(identical(c$posterior_target_sha256,"45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c"),"wrong retained posterior target")
  a<-c$integration_accuracy
  q2_require(identical(a$method,"dkw_response_cdf")&&length(a$alpha_per_shard)==1L&&
    is.finite(a$alpha_per_shard)&&a$alpha_per_shard>0&&a$alpha_per_shard<1&&
    all(vapply(a[c("max_split_absolute","max_split_relative","max_quantile_abs_error","max_quantile_rel_error")],
      function(x)is.numeric(x)&&length(x)==1L&&is.finite(x)&&x>0,logical(1L)))&&
    all(c("max_split_absolute","max_split_relative","max_quantile_abs_error","max_quantile_rel_error")%in%names(a))&&
    is.character(c$rng_namespace)&&length(c$rng_namespace)==1L&&nzchar(c$rng_namespace),"predeclared accuracy/scientific RNG identity required")
  invisible(TRUE)
}
q2_metadata <- function(c) {
  q2_geometry(c)
  required<-c("design","fixture","posterior","target_contract","worker_manifest","cell_target_audit")
  q2_require(setequal(names(c$assets),required),"exact six-source inventory required")
  rows<-lapply(required,function(role) {
    x<-c$assets[[role]]; q2_regular(x$path)
    q2_require(file.exists(x$path)&&!dir.exists(x$path)&&file.info(x$path)$size==x$size_bytes&&
      identical(q2_sha(x$path),x$sha256),paste("source size/hash mismatch",role))
    data.frame(role=role,path=x$path,size_bytes=x$size_bytes,sha256=x$sha256)
  })
  manifest<-utils::read.csv(c$assets$worker_manifest$path,stringsAsFactors=FALSE)
  for(role in c("posterior","target_contract")) {
    x<-c$assets[[role]]; at<-which(manifest$relative_path==basename(x$path))
    q2_require(length(at)==1L&&manifest$size_bytes[at]==x$size_bytes&&manifest$sha256[at]==x$sha256,"worker manifest does not authenticate source")
  }
  audit<-utils::read.csv(c$assets$cell_target_audit$path,stringsAsFactors=FALSE)
  audit<-audit[audit$model_cell_id==c$model_cell_id,,drop=FALSE]
  q2_require(nrow(audit)==1L&&isTRUE(audit$verified)&&audit$n_chains==5L&&
    identical(audit$posterior_target_sha256,c$posterior_target_sha256),"cell target differs from current article authority")
  target<-utils::read.csv(c$assets$target_contract$path,stringsAsFactors=FALSE)
  q2_require(identical(names(target),c("field","value"))&&!anyDuplicated(target$field)&&
    identical(target$value[target$field=="fit_structure"],"joint")&&
    identical(target$value[target$field=="likelihood_family"],"AL")&&
    identical(digest::digest(enc2utf8(paste0(paste(paste(target$field,target$value,sep="="),collapse="\n"),"\n")),
      algo="sha256",serialize=FALSE),c$posterior_target_sha256),"original worker target canonical hash differs")
  do.call(rbind,rows)
}
q2_source <- function(c,repo) {
  git<-function(...) system2("git",c("-C",shQuote(repo),...),stdout=TRUE)
  q2_require(identical(git("rev-parse","HEAD"),c$source_commit)&&
    identical(git("rev-parse","HEAD^{tree}"),c$source_tree)&&
    !length(git("status","--porcelain","--untracked-files=normal")),"source must be committed, clean and exactly pinned")
  q2_regular(c$source_manifest_path)
  q2_require(identical(q2_sha(c$source_manifest_path),c$source_manifest_sha256),"source-manifest hash mismatch")
  m<-utils::read.csv(c$source_manifest_path,stringsAsFactors=FALSE)
  q2_require(all(c("path","sha256","mode","blob")%in%names(m))&&!anyDuplicated(m$path),"source manifest schema")
  for(i in seq_len(nrow(m))) {
    path<-app_iqf_safe_path(repo,m$path[i])
    q2_require(identical(q2_sha(path),m$sha256[i]),paste("source changed",m$path[i]))
    tracked<-git("ls-files","--stage","--",shQuote(m$path[i]))
    q2_require(length(tracked)==1L&&startsWith(tracked,paste(m$mode[i],m$blob[i])),"source blob/mode mismatch")
  }
  invisible(TRUE)
}
q2_authorize <- function(c,contract_sha,auth_path,auth_sha,mode,repo) {
  q2_regular(auth_path)
  q2_require(!startsWith(normalizePath(auth_path),paste0(normalizePath(repo),"/"))&&identical(q2_sha(auth_path),auth_sha),"external authority missing/changed")
  a<-q2_json(auth_path)
  q2_require(identical(a$schema_version,"integrated_quantile_qualification_authorization_v1")&&
    isTRUE(a$allow_qualification)&&!isTRUE(a$allow_production)&&nzchar(a$approved_by)&&
    mode%in%unlist(a$allowed_operations)&&q2_time(a$expires_utc)>Sys.time(),"qualification not explicitly authorized or expired")
  for(n in c("source_commit","source_tree","source_manifest_sha256","posterior_target_sha256"))
    q2_require(identical(a[[n]],c[[n]]),paste("authority identity mismatch",n))
  q2_require(identical(a$contract_sha256,contract_sha),"authority does not bind exact source/input contract")
  q2_regular(a$physical_grant_path);q2_require(identical(q2_sha(a$physical_grant_path),a$physical_grant_sha256),"physical grant changed")
  g<-q2_json(a$physical_grant_path)
  q2_require(identical(g$schema_version,"integrated_quantile_qualification_physical_grant_v1")&&
    identical(g$scope,"MQ_Q2_ONE_DRAW_ORIGIN")&&identical(g$contract_sha256,contract_sha)&&
    identical(g$source_commit,c$source_commit)&&q2_time(g$expires_utc)>Sys.time()&&
    identical(g$host,strsplit(Sys.info()[["nodename"]],".",fixed=TRUE)[[1L]][1L])&&
    identical(g$boot_id,trimws(readLines("/proc/sys/kernel/random/boot_id",warn=FALSE)[1L]))&&
    isTRUE(g$physical_core_released_to_scope)&&g$max_threads==1L&&g$max_memory_bytes<=16*1024^3&&
    g$max_cpu_seconds<=600L&&g$max_wall_seconds<=900L&&g$max_output_bytes<=256*1024^2&&
    all(unlist(g[c("max_memory_bytes","max_cpu_seconds","max_wall_seconds","max_output_bytes")])>0),"physical grant scope/host/budget invalid")
  q2_require(q2_time(g$expires_utc)>Sys.time()+g$max_wall_seconds&&
    q2_time(a$expires_utc)>Sys.time()+g$max_wall_seconds,"grant/authority must cover the complete bounded run")
  cpu<-as.integer(g$logical_cpu)
  q2_require(length(cpu)==1L&&is.finite(cpu)&&cpu>=0&&
    identical(trimws(readLines(sprintf("/sys/devices/system/cpu/cpu%d/topology/core_id",cpu))),as.character(g$core_id))&&
    identical(trimws(readLines(sprintf("/sys/devices/system/cpu/cpu%d/topology/physical_package_id",cpu))),as.character(g$package_id)),"CPU topology differs from physical grant")
  q2_source(c,repo);list(authority=a,grant=g)
}
q2_limits <- function(g) {
  status<-readLines("/proc/self/status",warn=FALSE)
  allowed<-trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",status,value=TRUE)))
  q2_require(identical(allowed,as.character(g$logical_cpu)),"run under taskset on the one granted physical CPU")
  limits<-readLines("/proc/self/limits",warn=FALSE)
  for(pair in list(c("Max cpu time",g$max_cpu_seconds),c("Max address space",g$max_memory_bytes),c("Max file size",g$max_output_bytes))) {
    value<-strsplit(trimws(sub(paste0("^",pair[1L]),"",grep(paste0("^",pair[1L]),limits,value=TRUE))),"[[:space:]]+")[[1L]]
    bound<-suppressWarnings(as.numeric(value[1:2]))
    q2_require(all(is.finite(bound))&&all(bound<=as.numeric(pair[2L])),"CPU/address/file OS limit missing or too large")
  }
  # The outer OS timeout bounds the whole R process, including preparation,
  # diagnostics and serialization; an R-only timer is not a wall-time proof.
  pid<-Sys.getpid();bounded<-FALSE
  for(i in seq_len(8L)) {
    pstatus<-tryCatch(readLines(sprintf("/proc/%d/status",pid),warn=FALSE),error=function(e)character())
    ppid<-as.integer(trimws(sub("^PPid:","",grep("^PPid:",pstatus,value=TRUE))))
    if(!length(ppid)||is.na(ppid)||ppid<=1L)break
    raw<-readBin(sprintf("/proc/%d/cmdline",ppid),"raw",n=16384L);raw[raw==as.raw(0)]<-charToRaw(" ")
    command<-strsplit(rawToChar(raw),"[[:space:]]+")[[1L]]
    if(length(command)&&basename(command[1L])=="timeout") {
      args<-command[-1L];first<-which(!startsWith(args,"-"))[1L]
      duration<-if(is.na(first))"" else args[first]
      seconds<-suppressWarnings(as.numeric(sub("s$","",duration)))
      bounded<-grepl("^[0-9]+([.][0-9]+)?s?$",duration)&&is.finite(seconds)&&seconds>0&&seconds<=g$max_wall_seconds;break
    };pid<-ppid
  }
  q2_require(bounded,"whole-process OS timeout ancestor is required")
  invisible(TRUE)
}
q2_payloads <- function(d,f,draws,c) {
  q2_geometry(c);tau<-as.numeric(unlist(c$tau));p<-c$readout_slopes
  rows<-which(d$forecast_map$origin_index==c$origin_id)
  q2_require(identical(d$scenario_id,"asymmetric_laplace_tail")&&identical(d$feature_contract,"pure_recursive_v1")&&
    ncol(d$Z)==p&&length(rows)==30L&&identical(as.integer(d$forecast_map$horizon[rows]),1:30)&&
    min(d$forecast_map$full_time_index[rows])-1L==c$origin_time&&length(f$y)>=c$origin_time,"native source design/clock mismatch")
  cols<-function(block)sort(grep(paste0("^",block,"_[0-9]{4}$"),names(draws),value=TRUE))
  b<-cols("beta");a<-cols("alpha")
  q2_require(nrow(draws)==750L&&length(b)==p*7L&&length(a)==7L&&
    !anyDuplicated(names(draws))&&setequal(names(draws),c("draw_index",b,a,sprintf("sigma_%04d",1:7)))&&
    identical(as.integer(draws$draw_index),1:750)&&draws$draw_index[c$source_row]==c$source_draw_index,
    "native retained row/cardinality mismatch or unexpected nonparameter payload")
  keep<-d$row_meta$full_time_index<=c$origin_time
  safe<-d[c("scenario_id","design_class","feature_contract","response_lags","reservoir","scale_params","state_center","state_scale")]
  safe$dgp_row<-d$dgp_row[,intersect(c("simulated_length","period","dynamics_class","regime_start_fraction"),names(d$dgp_row)),drop=FALSE]
  safe$reservoir_meta<-list(win_scale_global=d$reservoir_meta$win_scale_global)
  safe$Z<-d$Z[keep,,drop=FALSE];safe$row_meta<-d$row_meta[keep,"full_time_index",drop=FALSE]
  safe$forecast_map<-d$forecast_map[rows,intersect(c("origin_index","horizon","full_time_index"),names(d$forecast_map)),drop=FALSE]
  id<-sprintf("%s/chain_%02d/draw_%06d",c$model_cell_id,c$chain_id,c$source_draw_index)
  mapping<-data.frame(draw_id=id,quantile_index=1:7,chain_id=c$chain_id,source_draw_index=c$source_draw_index,
    source_relative_path="source_posterior.csv.gz")
  posterior<-list(beta=as.matrix(draws[c$source_row,b,drop=FALSE]),alpha=as.matrix(draws[c$source_row,a,drop=FALSE]),
    draw_ids=id,chain_id=c$chain_id,source_draw_index=c$source_draw_index,draw_mapping_sha256=app_iqf_hash(mapping))
  q2_require(all(is.finite(c(posterior$beta,posterior$alpha))),"nonfinite authentic parameter draw")
  origins<-setNames(list(list(origin_time=c$origin_time,H=30L,history=as.numeric(f$y[seq_len(c$origin_time)]))),as.character(c$origin_id))
  list(design=safe,posterior=posterior,origins=origins,mapping=mapping)
}
q2_write <- function(object,path,used,cap) {
  bytes<-serialize(object,NULL,version=3L)
  q2_require(!file.exists(path)&&used+length(bytes)<=cap,"qualification output would overwrite/exceed its cumulative cap")
  writeBin(bytes,path);used+length(bytes)
}
q2_accuracy <- function(result,a) {
  split<-result$integration_diagnostic;dkw<-result$integration_dkw
  ok<-is.data.frame(split)&&is.data.frame(dkw)&&nrow(split)==nrow(result$quantiles)&&nrow(dkw)==nrow(split)&&
    all(split$split_stream_absolute_difference<=a$max_split_absolute|
      split$split_stream_relative_difference<=a$max_split_relative)&&
    all(is.finite(dkw$max_estimate_error_bound)&(dkw$max_estimate_error_bound<=a$max_quantile_abs_error|
      dkw$max_estimate_error_bound/pmax(1,abs(result$quantiles$quantile))<=a$max_quantile_rel_error))
  if(ok)"PASS_PREDECLARED_Q2_NUMERICAL_DIAGNOSTIC_ONLY" else "REVIEW_INNER_INTEGRATION_RESOLUTION"
}
q2_main <- function(argv=commandArgs(TRUE)) {
  arg<-function(n,default=NULL){j<-match(paste0("--",n),argv);if(is.na(j))default else argv[j+1L]}
  mode<-arg("mode","validate");q2_require(mode%in%c("validate","prepare","run"),"invalid mode")
  script<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L]);repo<-normalizePath(file.path(dirname(script),".."))
  source(file.path(repo,"application/R/integrated_quantile_forecast.R"))
  cp<-arg("contract");q2_require(!is.null(cp),"exact contract path required");q2_regular(cp)
  q2_require(identical(q2_sha(cp),arg("contract-sha256")),"exact contract SHA required")
  c<-q2_json(cp);metadata<-q2_metadata(c)
  if(mode=="validate"){cat("METADATA_ONLY_VALIDATED: zero RDS reads/writes, zero forecasts\n");return(invisible(metadata))}
  q2_require(identical(as.character(getRversion()),"4.6.0"),"qualification requires pinned R 4.6.0")
  gate<-q2_authorize(c,arg("contract-sha256"),arg("authorization"),arg("authorization-sha256"),mode,repo)
  q2_limits(gate$grant);setTimeLimit(elapsed=gate$grant$max_wall_seconds,transient=FALSE)
  q2_regular(c$prepared_root);q2_regular(c$output_root)
  q2_require(identical(c$prepared_root,gate$authority$prepared_root)&&identical(c$output_root,gate$authority$output_root),"output namespaces differ from authority")
  if(mode=="prepare") {
    q2_require(!file.exists(c$prepared_root),"prepared bundle must be fresh")
    objects<-q2_payloads(readRDS(c$assets$design$path),readRDS(c$assets$fixture$path),utils::read.csv(c$assets$posterior$path),c)
    dir.create(c$prepared_root,recursive=TRUE);used<-0
    for(n in c("design","posterior","origins","mapping"))used<-q2_write(objects[[n]],file.path(c$prepared_root,paste0(n,".rds")),used,gate$grant$max_output_bytes)
    spec<-list(schema_version="integrated_quantile_forecast_bundle_v1",adapter="mq_desn_native_v1",model_id=c$model_cell_id,tau=unlist(c$tau),
      identity=c[c("source_commit","source_tree","posterior_target_sha256")],payloads=list(design="design.rds",posterior="posterior.rds",origins="origins.rds"),
      supporting_evidence=list(original_posterior="source_posterior.csv.gz",draw_mapping="mapping.rds"),
      coupling=list(method="native_joint_posterior",recipe_sha256=app_iqf_hash(list(source=c$assets$posterior$sha256,row=1L,method="native_joint_posterior")),draw_mapping_sha256=objects$posterior$draw_mapping_sha256))
    used<-q2_write(spec,file.path(c$prepared_root,"spec.rds"),used,gate$grant$max_output_bytes)
    q2_require(used+c$assets$posterior$size_bytes+65536<=gate$grant$max_output_bytes&&
      file.copy(c$assets$posterior$path,file.path(c$prepared_root,"source_posterior.csv.gz"),overwrite=FALSE)&&
      identical(q2_sha(file.path(c$prepared_root,"source_posterior.csv.gz")),c$assets$posterior$sha256),"bounded source posterior copy failed")
    files<-c("design.rds","posterior.rds","origins.rds","mapping.rds","spec.rds","source_posterior.csv.gz")
    utils::write.csv(data.frame(relative_path=files,size_bytes=file.info(file.path(c$prepared_root,files))$size,
      sha256=vapply(file.path(c$prepared_root,files),q2_sha,""),role=c("retained_design","retained_posterior","observed_prefix","draw_mapping","bundle_spec","retained_posterior")),file.path(c$prepared_root,"input_manifest.csv"),row.names=FALSE)
    q2_require(sum(file.info(list.files(c$prepared_root,full.names=TRUE))$size)<=gate$grant$max_output_bytes,"prepared bundle exceeds cap")
    cat("PREPARED_Q2_ONLY: no trajectories; freeze input_manifest SHA in separate run authority\n");return(invisible(NULL))
  }
  q2_require(!file.exists(c$output_root)&&identical(q2_sha(file.path(c$prepared_root,"input_manifest.csv")),gate$authority$prepared_input_manifest_sha256),"run input hash/output namespace mismatch")
  prepared_bytes<-sum(file.info(list.files(c$prepared_root,recursive=TRUE,full.names=TRUE))$size)
  output_cap<-gate$grant$max_output_bytes-prepared_bytes-65536
  q2_require(is.finite(output_cap)&&output_cap>0,"prepared bundle leaves no aggregate qualification output allowance")
  for(n in c("00_packages.R","joint_qvp_qdesn.R","latent_path_design.R","joint_qdesn_pure_recursive_campaign.R","joint_qdesn_recursive_mean_design.R"))source(file.path(repo,"application/R",n))
  app_set_repo_root(repo);source(file.path(repo,"scripts/integrated_quantile_blocks.R"))
  bundle<-app_iqf_prepare_bundle(c$prepared_root,file.path(c$prepared_root,"input_manifest.csv"),"spec.rds",gate$authority$prepared_input_manifest_sha256)
  o<-bundle$payloads;adapter<-app_iqf_desn_adapter(o$design,o$posterior,o$origins,unlist(c$tau),"mq_grid",bundle$spec$coupling,c$rng_namespace)
  started<-proc.time();result<-app_iqf_run_task(adapter,o$posterior$draw_ids,"1",4096L,unlist(c$tau),c$model_cell_id,
    tolerance=1e-8,diagnose_integration=TRUE,mc_confidence_alpha=c$integration_accuracy$alpha_per_shard,max_kernel_bytes=gate$grant$max_memory_bytes/2)
  result$cdf_components<-NULL;result$identity<-c[c("source_commit","source_tree","source_manifest_sha256","posterior_target_sha256")]
  result$identity$input_manifest_sha256<-gate$authority$prepared_input_manifest_sha256;result$identity$task_manifest_sha256<-arg("contract-sha256")
  result$identity$rng_namespace<-c$rng_namespace;result$identity$outer_conditioning<-result$outer_conditioning
  result$integration_accuracy_contract<-c$integration_accuracy;result$integration_accuracy_contract_sha256<-app_iqf_hash(c$integration_accuracy)
  result$integration_status<-q2_accuracy(result,c$integration_accuracy)
  block<-app_iqf_pack_block(list(result));q2_require(identical(result,app_iqf_unpack_member(block,1L)),"compact block roundtrip changed original member")
  dir.create(c$output_root,recursive=TRUE);used<-q2_write(block,file.path(c$output_root,"qualification_block.rds"),0,output_cap)
  rss<-grep("^VmHWM:",readLines("/proc/self/status",warn=FALSE),value=TRUE)
  report<-list(schema_version="integrated_quantile_qualification_receipt_v1",purpose=c$purpose,contract_sha256=arg("contract-sha256"),
    status="DIAGNOSTIC_ONLY_NO_ARTICLE_PROMOTION",fits=0L,score_evaluations=0L,draws=1L,origins=1L,horizons=30L,inner_paths=4096L,
    numerical_status=result$integration_status,numerical_scope="one_parameter_draw_origin_simultaneous_horizons_only_not_full_campaign",
    compact_roundtrip_identical=TRUE,forecast_elapsed_seconds=unname((proc.time()-started)["elapsed"]),
    process_cpu_seconds=sum(proc.time()[c("user.self","sys.self")]),VmHWM=rss,grant_sha256=gate$authority$physical_grant_sha256,
    prepared_bytes=prepared_bytes,bytes_before_receipt=used,elapsed_at_receipt_seconds=unname(proc.time()["elapsed"]),
    integration_diagnostic=result$integration_diagnostic,integration_dkw=result$integration_dkw,session=capture.output(sessionInfo()))
  used<-q2_write(report,file.path(c$output_root,"qualification_receipt.rds"),used,output_cap)
  files<-c("qualification_block.rds","qualification_receipt.rds")
  app_iqf_write_output_index(data.frame(relative_path=files,size_bytes=file.info(file.path(c$output_root,files))$size,
    sha256=vapply(file.path(c$output_root,files),q2_sha,"")),file.path(c$output_root,"artifact_manifest.csv"),output_cap,used)
  cat("Q2_DIAGNOSTIC_COMPLETE: no scientific acceptance or article promotion\n")
}
if(sys.nframe()==0L)q2_main()
