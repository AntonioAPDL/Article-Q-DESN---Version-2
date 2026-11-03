# Genuine bounded source-regression guards; no permission is created by loading.
# The old producer/qualifier closure and generated-only APIs are not modified.
source("scripts/mq_array_qualification.R",local=TRUE)
mqns_require <- function(ok,why) {
  if(!isTRUE(ok))stop(paste0("MQ native source replay: ",why),call.=FALSE)
  invisible(TRUE)
}
mqns_scope <- function(s) {
  q<-mqns_require;mqa_unique_json_objects(s)
  q(is.list(s)&&identical(s$schema_version,"mq_native_source_replay_v1")&&
    identical(s$purpose,"NATIVE_COMPOSED_ONE_ORIGINAL_DRAW_ORIGIN")&&
    identical(s$allow_qualification,TRUE),"new genuine one-unit qualification purpose required")
  for(k in c("allow_refit","allow_scoring","allow_production","allow_article",
    "allow_raw_fixture_deserialization","allow_future_truth","C_ABI_qualified"))
    q(identical(s[[k]],FALSE),paste("forbidden scientific/global permission",k))
  q(mqa_equal(s$training_paths,65536)&&mqa_equal(s$validation_paths,262144)&&
    mqa_equal(s$batch_size,128)&&mqa_equal(s$training_path_range,c(1,65536))&&
    mqa_equal(s$validation_path_range,c(65537,327680))&&
    mqa_equal(s$validation_look_sizes,c(65536,131072,262144))&&
    mqa_equal(s$total_alpha,.05)&&mqa_equal(s$alpha_per_look,rep(.05/3,3))&&
    mqa_equal(s$inversion_tolerance,1e-8)&&mqa_equal(s$parity_absolute_tolerance,1e-10)&&
    mqa_equal(s$parity_relative_tolerance,1e-10)&&
    mqa_equal(s$parity_path_ids,c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,
      65535,65536,65537,327680))&&identical(s$rng_backend,"r46_first_step")&&
    identical(s$stop_before_validation_on_split_failure,TRUE),"unchanged counts/looks/streams/tolerances required")
  q2_geometry(s$original_unit)
  q(identical(s$original_unit$rng_namespace,
    "integrated_quantile_forecast_v1/asymmetric_laplace_tail__joint_qdesn_rhs/chain_01"),
    "original scientific namespace required")
  a<-s$original_unit$integration_accuracy
  q(mqa_equal(a$alpha_per_shard,.05)&&mqa_equal(a$max_split_absolute,.005)&&
    mqa_equal(a$max_split_relative,.005)&&mqa_equal(a$max_quantile_abs_error,.01)&&
    mqa_equal(a$max_quantile_rel_error,.01),"original numerical gates changed")
  l<-s$limits
  q(mqa_equal(l$cpu_seconds,1800)&&mqa_equal(l$wall_term_seconds,1799)&&
    mqa_equal(l$wall_kill_after_seconds,1)&&mqa_equal(l$address_space_bytes,16*1024^3)&&
    mqa_equal(l$output_bytes,256*1024^2)&&mqa_equal(l$logical_cpu,27),"fixed finite one-core numerical envelope required")
  for(k in c("source_commit","source_tree"))q(mqa_hex(s[[k]],40),"full new source identity required")
  q(identical(s$origin_remote_url,"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git")&&
    is.character(s$published_ref)&&length(s$published_ref)==1L&&!is.na(s$published_ref)&&
    grepl("^refs/heads/[A-Za-z0-9][A-Za-z0-9_./-]*$",s$published_ref)&&
    !grepl("\\.\\.|//|/$",s$published_ref),"exact new published source ref required")
  q(is.character(s$actor_nonce)&&length(s$actor_nonce)==1L&&grepl("^[A-Za-z0-9_-]{8,128}$",s$actor_nonce)&&
    is.character(s$administrative_unit_name)&&length(s$administrative_unit_name)==1L&&
    grepl("^qdesn-[A-Za-z0-9_-]+\\.service$",s$administrative_unit_name),"fresh actor identity required")
  q(is.logical(s$allow_historical_training_array_read)&&length(s$allow_historical_training_array_read)==1L&&
    !is.na(s$allow_historical_training_array_read),"explicit optional numerical-reference reader decision required")
  q(identical(s$prepared_reader_role,"truth_free_retained_observed_prefix")&&
    identical(s$historical_reader_role,if(s$allow_historical_training_array_read)
      "retained_numerical_regression_arrays_not_model_or_truth" else "NOT_GRANTED"),"explicit retained-input reader roles required")
  q(is.character(s$expires_utc)&&length(s$expires_utc)==1L&&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",s$expires_utc)&&
    !is.na(q2_time(s$expires_utc)),"explicit UTC expiry required")
  invisible(TRUE)
}
mqns_native_files <- function()c("application/R/00_packages.R","application/R/joint_qvp_qdesn.R",
  "application/R/latent_path_design.R","application/R/joint_qdesn_pure_recursive_campaign.R",
  "application/R/joint_qdesn_recursive_mean_design.R","application/R/integrated_quantile_forecast.R",
  "scripts/integrated_quantile_mq_batch.R","scripts/mq_forecast_array_methods.R",
  "scripts/mq_independent_cdf_certificate.R","scripts/mq_streaming_cdf_certificate.R")
mqns_required_sources <- function(native_paths)sort(unique(c(mqa_required_sources(native_paths),
  mqns_native_files(),"scripts/mq_native_source_qualification.R","scripts/qualify_mq_native_composed.R",
  "scripts/mq_native_qualification_backend.R","scripts/build_mq_native_replay.py",
  "application/tests/test_build_mq_native_replay.py","docs/implementation_notes/mq_native_retained_build_20261102.md",
  "scripts/mq_native_external_terminal.py","application/tests/test_mq_native_external_terminal.py",
  "docs/implementation_notes/mq_native_external_terminal_20261102.md",
  "scripts/enroll_mq_native_runtime.R","application/tests/test_mq_native_runtime_enrollment.R",
  "docs/implementation_notes/mq_native_runtime_enrollment_20261103.md",
  "application/tests/test_mq_native_qualification_backend.R",
  "docs/implementation_notes/mq_native_purpose_backend_20261103.md",
  "docs/implementation_notes/mq_native_source_qualification_20261103.md",
  "scripts/native/mq_key_hash.c","scripts/native/mq_isoreg_batch.c","scripts/native/mq_event_inverse.c",
  "application/tests/test_mq_native_source_qualification.R")))
mqns_source_guard <- function(s,root,online=TRUE) {
  q<-mqns_require;git<-function(a)mqa_git(root,a)
  q(identical(git(c("rev-parse","HEAD")),s$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=normal"))),"clean exact new source required")
  sm<-mqa_pin(s$source_manifest,1024^2)
  q(identical(sm,file.path(root,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv")),
    "immutable native manifest location required")
  native<-read.csv(sm,stringsAsFactors=FALSE)
  q(all(c("path","sha256","mode","blob")%in%names(native))&&nrow(native)>0&&!anyDuplicated(native$path),
    "complete immutable native manifest required")
  paths<-vapply(s$source_files,mqa_pin,character(1L),max_bytes=4*1024^2)
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,mqns_required_sources(native$path))),
    "exact NEW native qualification source closure required")
  for(p in paths) {
    rel<-substring(p,nchar(root)+2L)
    q(identical(digest::digest(mqa_git_blob(root,s$source_commit,rel),algo="sha256",serialize=FALSE),
      unname(tools::sha256sum(p))),"new source differs from committed blob")
  }
  for(i in seq_len(nrow(native))) {
    q(identical(unname(tools::sha256sum(file.path(root,native$path[i]))),native$sha256[i]),
      "historical native source changed")
    tracked<-git(c("ls-files","--stage","--",shQuote(native$path[i])))
    q(length(tracked)==1L&&startsWith(tracked,paste(native$mode[i],native$blob[i])),
      "immutable native mode/blob identity changed")
  }
  if(online) {
    q(identical(git(c("remote","get-url","origin")),s$origin_remote_url),"wrong publication origin")
    old<-Sys.getenv(c("GIT_TERMINAL_PROMPT","GIT_SSH_COMMAND"),unset=NA_character_)
    on.exit(for(k in names(old))if(is.na(old[[k]]))Sys.unsetenv(k)else do.call(Sys.setenv,setNames(list(old[[k]]),k)),add=TRUE)
    Sys.setenv(GIT_TERMINAL_PROMPT="0",GIT_SSH_COMMAND=paste("/usr/bin/ssh -F /dev/null -oBatchMode=yes",
      "-oControlMaster=no -oControlPath=none -oControlPersist=no -oProxyCommand=none -oProxyJump=none -oRequestTTY=no"))
    remote<-git(c("ls-remote","--exit-code","origin",s$published_ref))
    q(length(remote)==1L&&identical(strsplit(remote,"[[:space:]]+")[[1L]],c(s$source_commit,s$published_ref)),
      "new source remote readback changed")
  }
  list(source_files_verified=length(paths),native_files_verified=nrow(native),published_readback=online)
}
mqns_build_receipt <- function(s,root) {
  q<-mqns_require;p<-mqa_pin(s$retained_build_receipt,4*1024^2)
  b<-jsonlite::read_json(p,simplifyVector=FALSE);mqa_unique_json_objects(b)
  q(identical(b$schema_version,"mq_native_retained_build_receipt_v1")&&
    identical(b$status,"RETAINED_NATIVE_BUILD_COMPLETE_NOT_NUMERICAL_QUALIFICATION")&&
    identical(b$source_commit,s$source_commit)&&identical(b$source_tree,s$source_tree)&&
    identical(b$R_home,normalizePath(R.home(),mustWork=TRUE))&&
    identical(b$R_libdir,normalizePath(R.home("lib"),mustWork=TRUE)),"retained build source/native R identity changed")
  for(k in c("production_authorized","allow_refit","allow_scoring","allow_article","C_ABI_qualified",
    "source_runtime_authenticated","numeric_replay_executed"))
    q(identical(b[[k]],FALSE),"build grants forbidden numerical/publication permission")
  build_paths<-c("scripts/build_mq_native_replay.py","application/tests/test_build_mq_native_replay.py",
    "docs/implementation_notes/mq_native_retained_build_20261102.md",
    "scripts/native/mq_key_hash.c","scripts/native/mq_isoreg_batch.c","scripts/native/mq_event_inverse.c")
  build_pins<-vapply(b$source_files,`[[`,"","path")
  q(length(build_pins)==6L&&!anyDuplicated(build_pins)&&setequal(build_pins,file.path(root,build_paths))&&
    identical(b$inputs_reverified,TRUE),"exact retained build closure/reverification required")
  for(pin in b$source_files) {
    mqa_pin(pin,4*1024^2)
    matches<-Filter(function(x)identical(x$path,pin$path),s$source_files)
    q(length(matches)==1L&&mqa_metadata_equal(matches[[1L]],pin),"retained build/new numeric source pins differ")
  }
  for(role in c("toolchain_files","header_files")) {
    z<-b[[role]]
    q(is.list(z)&&length(z)>0,paste("retained build inventory missing",role))
    invisible(lapply(z,mqa_pin,max_bytes=256*1024^2))
  }
  q(is.list(b$compile_logs)&&length(b$compile_logs)==3L,"three retained compile logs required")
  invisible(lapply(b$compile_logs,mqa_pin,max_bytes=64*1024^2))
  q(is.list(b$dlls)&&setequal(names(b$dlls),c("key","isotonic","inverse")),"three exact retained DLL roles required")
  source<-c(key="scripts/native/mq_key_hash.c",isotonic="scripts/native/mq_isoreg_batch.c",inverse="scripts/native/mq_event_inverse.c")
  basename_dll<-c(key="mq_key_hash.so",isotonic="mq_isoreg_batch.so",inverse="mq_event_inverse.so")
  for(role in names(source)) {
    x<-b$dlls[[role]]
    q(is.list(x)&&setequal(names(x),c("path","size_bytes","sha256","source_path","source_sha256"))&&
      identical(x$source_path,unname(source[role]))&&identical(basename(x$path),unname(basename_dll[role]))&&
      identical(x$source_sha256,unname(tools::sha256sum(file.path(root,x$source_path)))),"DLL role/source identity differs")
    path<-mqa_pin(x[c("path","size_bytes","sha256")],8*1024^2)
    q(!startsWith(path,paste0(root,"/")),"retained binaries must be outside source checkout")
  }
  terminal<-jsonlite::read_json(mqa_pin(s$retained_build_terminal,4*1024^2),simplifyVector=FALSE)
  mqns_build_terminal_metadata(s,b,terminal)
  attr(b,"receipt_path")<-p;attr(b,"receipt_sha256")<-s$retained_build_receipt$sha256
  b
}
mqns_build_terminal_metadata <- function(s,b,t) {
  q<-mqns_require;mqa_unique_json_objects(t)
  q(identical(t$schema_version,"mq_native_external_terminal_receipt_v1")&&
    identical(t$actor,"mq-native-build")&&identical(t$phase,"final")&&
    identical(t$status,"EXECUTION_COMPLETE_NOT_PRODUCTION")&&is.list(t$failures)&&length(t$failures)==0L&&
    identical(t$production_authorized,FALSE)&&identical(t$article_promotion_authorized,FALSE)&&
    identical(t$independently_linked_successful_stop_post,TRUE)&&mqa_hex(t$stop_post_receipt_sha256)&&
    identical(t$source_commit,b$source_commit)&&identical(t$source_tree,b$source_tree)&&
    identical(t$purpose_sha256,b$purpose_sha256),"retained build lacks independently closed successful terminal proof")
  entries<-Filter(function(x)identical(x$relative_path,"BUILD_RECEIPT.json"),t$outputs)
  q(length(entries)==1L&&identical(entries[[1L]]$sha256,s$retained_build_receipt$sha256)&&
    mqa_equal(entries[[1L]]$size_bytes,s$retained_build_receipt$size_bytes),
    "retained build terminal does not bind this exact build receipt")
  invisible(TRUE)
}
mqns_lapack_warmup <- function() {
  before<-mqa_rng()
  A<-matrix(c(1,2,3,5,8,13),3L,2L)
  ch<-chol(crossprod(A)+diag(2L));decomp<-qr(A,LAPACK=TRUE)
  mqns_require(all(is.finite(ch))&&all(is.finite(decomp$qr))&&identical(before,mqa_rng()),
    "deterministic LAPACK enrollment changed RNG or failed")
  invisible(TRUE)
}
mqns_old_prepared_context <- function(s) {
  # Crucially this is the OLD authenticated producer's context, never the new
  # native source_files or an extended mqa_required_sources definition.
  names<-c("prepared_payload","prepared_derivation","prepared_manifest","prepared_source",
    "prepared_purpose","original_unit","original_unit_contract")
  old<-s[names];old$source_manifest<-s$prepared_native_manifest
  mqa_pin(old$source_manifest,1024^2)
  old
}
mqns_prepared_metadata <- function(s,root) {
  old<-mqns_old_prepared_context(s)
  r<-jsonlite::read_json(mqa_pin(old$prepared_derivation,2*1024^2),simplifyVector=FALSE)
  purpose<-jsonlite::read_json(mqa_pin(old$prepared_purpose,1024^2),simplifyVector=FALSE)
  mqa_preparation_scope(purpose);mqa_derivation_metadata(r,s$original_unit,old)
  a<-old$prepared_source
  mqns_require(identical(mqa_git(root,c("rev-parse",paste0(a$source_commit,"^{tree}"))),a$source_tree)&&
    identical(digest::digest(mqa_git_blob(root,a$source_commit,a$reducer_relative_path),algo="sha256",serialize=FALSE),a$reducer_sha256),
    "old producer/reducer Git identity changed")
  native<-read.csv(old$source_manifest$path,stringsAsFactors=FALSE)
  oldroot<-sub("/docs/reproducibility/integrated_forecast_transition_sources_20261031.csv$","",purpose$source_manifest$path)
  mqns_require(!identical(oldroot,purpose$source_manifest$path)&&
    setequal(vapply(purpose$source_files,`[[`,"","path"),file.path(oldroot,mqa_required_sources(native$path)))&&
    mqa_metadata_equal(purpose$source_manifest[c("size_bytes","sha256")],old$source_manifest[c("size_bytes","sha256")]),
    "authentic OLD producer transitive closure changed")
  for(pin in purpose$source_files) {
    rel<-substring(pin$path,nchar(oldroot)+2L);blob<-mqa_git_blob(root,a$source_commit,rel)
    mqns_require(length(blob)==pin$size_bytes&&identical(digest::digest(blob,algo="sha256",serialize=FALSE),pin$sha256),
      "old producer source differs from its frozen Git blob")
  }
  list(old_context=old,producer_source_commit=a$source_commit,old_source_files_verified=length(purpose$source_files),
    retained_payload_read=FALSE)
}
mqns_gate_metadata <- function(s,g) {
  q<-mqns_require;mqa_unique_json_objects(g)
  q(identical(g$schema_version,"mq_native_external_execution_gate_v1")&&
    identical(g$mode,"native_source_regression_qualification_v1")&&identical(g$execution_authorized,TRUE)&&
    identical(g$actor_nonce,s$actor_nonce)&&identical(g$unit_name,s$administrative_unit_name)&&
    identical(g$source_commit,s$source_commit)&&identical(g$source_tree,s$source_tree)&&
    identical(g$build_receipt_sha256,s$retained_build_receipt$sha256)&&
    identical(g$retained_build_terminal_sha256,s$retained_build_terminal$sha256)&&
    identical(g$runtime_inventory_sha256,mqa_hash(s$runtime_files))&&
    identical(g$prepared_manifest_sha256,s$prepared_manifest$sha256)&&
    identical(g$original_unit_contract_sha256,s$original_unit_contract$sha256)&&
    identical(g$allow_historical_training_array_read,s$allow_historical_training_array_read)&&
    identical(g$expires_utc,s$expires_utc)&&mqa_metadata_equal(g$limits,s$limits),"fresh external execution gate binding differs")
  for(k in c("production_authorized","refit_authorized","scoring_authorized","article_authorized","C_ABI_qualified"))
    q(identical(g[[k]],FALSE),"external gate cannot grant global scientific authority")
  g
}
mqns_external_gate <- function(s)mqns_gate_metadata(s,
  jsonlite::read_json(mqa_pin(s$external_execution_gate,1024^2),simplifyVector=FALSE))
mqns_live_gate <- function(s,purpose_sha256) {
  q<-mqns_require
  q(identical(Sys.getenv("QDESN_MQ_NATIVE_EXECUTION_GATE_SHA256"),s$external_execution_gate$sha256)&&
    identical(Sys.getenv("QDESN_MQ_NATIVE_PURPOSE_SHA256"),purpose_sha256)&&
    identical(Sys.getenv("QDESN_MQ_NATIVE_UNIT_NAME"),s$administrative_unit_name),
    "bounded supervisor did not bind this gate, final purpose and unit")
  mqns_external_gate(s)
  q(q2_time(s$expires_utc)>Sys.time()+1800,"purpose must cover complete finite execution")
  q2_limits(list(logical_cpu=27L,max_cpu_seconds=1800,max_wall_seconds=1800,
    max_memory_bytes=16*1024^3,max_output_bytes=256*1024^2))
  proof<-mqa_timeout_ancestor(1799L)
  list(process_pid=Sys.getpid(),timeout=proof,expected_gate_sha256=s$external_execution_gate$sha256,
    actual_limits_verified=TRUE,actual_timeout_process_group_verified=TRUE)
}
mqns_seal_context <- function(ctx) {
  ctx$integrity_sha256<-NULL;ctx$integrity_sha256<-mqa_hash(ctx);ctx
}
mqns_make_context <- function(s,purpose_path,purpose_sha256,live_gate) {
  ctx<-structure(list(schema_version="mq_native_purpose_context_v1",mode="native_source_regression_qualification_v1",
    canonical_source_root=normalizePath(getwd(),mustWork=TRUE),purpose_path=purpose_path,purpose_sha256=purpose_sha256,
    source_commit=s$source_commit,source_tree=s$source_tree,source_files=s$source_files,expires_utc=s$expires_utc,
    output_root=s$output_root,process_pid=live_gate$process_pid,live_gate=live_gate,
    administrative_unit_name=s$administrative_unit_name,
    external_execution_gate_pin=s$external_execution_gate,
    original_unit=s$original_unit,unit_identity=list(model_cell_id=s$original_unit$model_cell_id,
      draw_id=paste0(s$original_unit$model_cell_id,"/chain_01/draw_000001"),origin_id="1",
      rng_namespace=s$original_unit$rng_namespace,H=30L,tau=c(.05,.1,.25,.5,.75,.9,.95)),
    training_path_range=c(1,65536),validation_path_range=c(65537,327680),parity_path_ids=unlist(s$parity_path_ids),
    limits=s$limits,retained_build_receipt_sha256=s$retained_build_receipt$sha256,
    external_gate_verified=TRUE,runtime_verified=TRUE,phase="training",freeze_pin=NULL,
    production_authorized=FALSE,refit_authorized=FALSE,scoring_authorized=FALSE,article_authorized=FALSE,
    C_ABI_qualified=FALSE),class="mq_native_replay_context_v1")
  mqns_seal_context(ctx)
}
mqns_make_enrollment_context <- function(s,purpose_path,purpose_sha256,live_gate) {
  ctx<-mqns_make_context(s,purpose_path,purpose_sha256,live_gate)
  class(ctx)<-"mq_native_runtime_enrollment_context_v1"
  ctx$schema_version<-"mq_native_runtime_enrollment_context_v1"
  ctx$mode<-"load_only_runtime_enrollment_v1";ctx$runtime_verified<-FALSE
  mqns_seal_context(ctx)
}
mqns_context_live <- function(ctx) {
  q<-mqns_require
  q(identical(mqns_seal_context(ctx)$integrity_sha256,ctx$integrity_sha256)&&
    q2_time(ctx$expires_utc)>Sys.time()&&identical(ctx$external_gate_verified,TRUE)&&
    identical(ctx$process_pid,Sys.getpid())&&identical(ctx$live_gate$actual_limits_verified,TRUE)&&
    identical(ctx$live_gate$actual_timeout_process_group_verified,TRUE)&&
    identical(Sys.getenv("QDESN_MQ_NATIVE_EXECUTION_GATE_SHA256"),ctx$external_execution_gate_pin$sha256)&&
    identical(Sys.getenv("QDESN_MQ_NATIVE_PURPOSE_SHA256"),ctx$purpose_sha256)&&
    identical(Sys.getenv("QDESN_MQ_NATIVE_UNIT_NAME"),ctx$administrative_unit_name),"live purpose/supervisor/process binding changed")
  q(identical(unname(tools::sha256sum(ctx$purpose_path)),ctx$purpose_sha256),"purpose bytes changed")
  mqa_pin(ctx$external_execution_gate_pin,1024^2)
  for(k in c("production_authorized","refit_authorized","scoring_authorized","article_authorized","C_ABI_qualified"))
    q(identical(ctx[[k]],FALSE),"context grants forbidden global authority")
  invisible(TRUE)
}
mqns_enrollment_context_check <- function(ctx) {
  mqns_require(inherits(ctx,"mq_native_runtime_enrollment_context_v1")&&
    identical(ctx$schema_version,"mq_native_runtime_enrollment_context_v1")&&
    identical(ctx$mode,"load_only_runtime_enrollment_v1")&&identical(ctx$runtime_verified,FALSE),
    "distinct LOAD_ONLY context required; numeric execution forbidden")
  mqns_context_live(ctx)
}
mqns_context_check <- function(ctx) {
  q<-mqns_require
  q(inherits(ctx,"mq_native_replay_context_v1")&&identical(ctx$schema_version,"mq_native_purpose_context_v1")&&
    identical(ctx$mode,"native_source_regression_qualification_v1")&&
    identical(ctx$runtime_verified,TRUE)&&ctx$phase%in%c("training","validation"),"live immutable authentic replay context required")
  mqns_context_live(ctx)
  invisible(TRUE)
}
mqns_phase_geometry <- function(ctx,phase,inner_ids) {
  q<-mqns_require
  q(is.numeric(inner_ids)&&length(inner_ids)>0&&length(inner_ids)<=128&&all(is.finite(inner_ids))&&
    all(inner_ids==floor(inner_ids))&&!anyDuplicated(inner_ids),"bounded original path IDs required")
  valid<-if(ctx$phase=="training")c("parity_training","training")else c("parity_validation","validation")
  q(phase%in%valid,"validation cannot precede frozen training candidates")
  allowed<-switch(phase,parity_training=ctx$parity_path_ids[ctx$parity_path_ids<=65536],
    parity_validation=ctx$parity_path_ids[ctx$parity_path_ids>65536],
    training=c(1,65536),validation=c(65537,327680))
  q(if(startsWith(phase,"parity"))all(inner_ids%in%allowed)else all(inner_ids>=allowed[1]&inner_ids<=allowed[2]),
    "path IDs outside the authorized phase")
  invisible(TRUE)
}
mqns_phase_check <- function(ctx,phase,inner_ids) {
  mqns_context_check(ctx);mqns_phase_geometry(ctx,phase,inner_ids)
  if(ctx$phase=="validation")mqa_pin(ctx$freeze_pin,4*1024^2)
  invisible(TRUE)
}
mqns_context_validation <- function(ctx,freeze_pin) {
  mqns_context_check(ctx);q<-mqns_require;q(identical(ctx$phase,"training"),"one-way training freeze transition required")
  f<-jsonlite::read_json(mqa_pin(freeze_pin,4*1024^2),simplifyVector=FALSE)
  q(identical(dirname(freeze_pin$path),ctx$output_root)&&identical(basename(freeze_pin$path),"CANDIDATES_FROZEN.json"),
    "freeze must belong to this exact fresh output")
  q(identical(f$schema_version,"mq_native_training_freeze_v1")&&
    identical(f$source_commit,ctx$source_commit)&&identical(f$purpose_contract_sha256,ctx$purpose_sha256)&&
    identical(f$candidate_phase,"BEFORE_ANY_VALIDATION_PATH")&&identical(f$split_pass,TRUE)&&
    mqa_equal(f$training_path_range,c(1,65536))&&mqa_equal(f$validation_paths_generated,0)&&
    is.list(f$artifacts)&&length(f$artifacts)==3L,"authentic new-source training freeze required")
  artifacts<-vapply(f$artifacts,`[[`,"","path")
  q(!anyDuplicated(artifacts)&&setequal(artifacts,file.path(ctx$output_root,
    c("frozen_training_candidates.rds","training_split_diagnostic.rds","training_parity.rds"))),
    "exact fresh candidate/split/parity commitment required")
  for(pin in f$artifacts)mqa_pin(pin,256*1024^2)
  out<-ctx;out$phase<-"validation";out$freeze_pin<-freeze_pin;mqns_seal_context(out)
}
