# Strict source-only policy for a new two-resolution AL diagnostic.
# Old purposes/failed outputs are not execution permission for this method.
source("scripts/qualify_ind_adapted_filter.R",local=TRUE)
source("scripts/ind_batched_al_auxiliary_filter.R",local=TRUE)
ind_hq_require <- function(ok,why) {
 if(!isTRUE(ok))stop(paste0("IND high-resolution diagnostic: ",why),call.=FALSE)
 invisible(TRUE)
}
ind_hq_scope <- function(s) {
 q<-ind_hq_require
 eq<-function(x,y)is.numeric(unlist(x))&&identical(as.numeric(unlist(x)),as.numeric(y))
 q(is.list(s)&&!anyDuplicated(names(s))&&
  identical(s$schema_version,"ind_high_resolution_AL_filter_contract_v1")&&
  identical(s$purpose,"ONE_PREDECLARED_SEED_TWO_HIGHER_RESOLUTIONS_NO_REFIT")&&
  identical(s$allow_diagnostic,TRUE)&&identical(s$allow_refit,FALSE)&&
  identical(s$allow_production,FALSE)&&identical(s$allow_scoring,FALSE)&&
  identical(s$allow_article,FALSE),"new finite diagnostic-only scope required")
 q(eq(s$particle_resolutions,c(4096,8192))&&eq(s$maximum_stream_particles,8192)&&
  eq(s$posterior_column,1)&&eq(s$observed_prefix_length,500)&&
  eq(s$checkpoint_indices,c(100,250,500))&&eq(s$probabilities,c(.05,.5,.95))&&
  eq(s$ess_fraction,.5)&&eq(s$inversion_absolute_tolerance,1e-8)&&
  eq(s$agreement_absolute_tolerance,.005)&&eq(s$agreement_relative_tolerance,.005),
  "higher resolutions and unchanged native column/checkpoints/error gates required")
 q(eq(s$seed,71521)||eq(s$seed,71522),"one of the two predeclared seeds required")
 q(identical(s$method,"ancestor_first_AL_exact_v_v1")&&
  identical(s$arithmetic_backend,"batched_AL_scalar_equivalent_v1")&&
  identical(s$rng_namespace,"ind_ancestor_first_AL_high_resolution_max8192_v1")&&
  identical(s$rng_layout,"Mersenne_Twister_max8192_time_major_proposal4_then_ancestor_then_residual_v1"),
  "fixed statistical method, supplied streams and opt-in arithmetic backend required")
 l<-s$limits;cpu<-if(eq(s$seed,71521))26 else 27
 q(is.list(l)&&eq(l$cpu_seconds,5400)&&eq(l$wall_term_seconds,5399)&&
  eq(l$wall_kill_after_seconds,1)&&eq(l$address_space_bytes,2*1024^3)&&
  eq(l$output_bytes,256*1024^2)&&eq(l$logical_cpu,cpu),
  "per-seed CPU5400/TERM5399/KILL1/2GiB/256MiB and fixed core required")
 fixed<-c(training_input="d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496",
  native_forward_receipt="440da6c4d71554952947b128c77758f86aea385c7cb3ceb203ddad5ff5737bff",
  bootstrap_receipt="b14b6ea359d6f48f37134d40e87ca2d37f8dd33d954c5c59f479352fa495e599",
  historical_guided_receipt="ce2b82b96b57de42cedd3f856f5f630e4f9387d70d9219edb47db28b64a1a2b2",
  original_fit="1e8ba3de4a6c9e9e0f6bd900be7801e8c80fe0fdff4b6ca24804bdc62e3ff17f",
  native_cpp="f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065",
  previous_attempt_terminal="d3d188cf8bb796594702c5464b2816f2092d7bddbd81bb4bcbf7282af0783e29",
  previous_attempt_manifest="91430b6e8a68ae0ecbcd4cfdcb15d1dadaf7991311ec09f7d9a16b3168218f29",
  previous_attempt_agreements="33afc10cec68c77fddd6b5998e26c3be5ff67d3ca5105f1f8e72e4a0234a2978")
 for(k in names(fixed))q(is.list(s[[k]])&&identical(s[[k]]$sha256,unname(fixed[k])),
  paste("frozen input/proof identity changed",k))
 q(eq(s$training_input$size_bytes,13728)&&eq(s$original_fit$size_bytes,611287756),
  "exact truth-free input and hash-only original fit required")
 for(k in c("source_commit","source_tree"))q(is.character(s[[k]])&&length(s[[k]])==1L&&
  !is.na(s[[k]])&&grepl("^[a-f0-9]{40}$",s[[k]]),"full source commit/tree required")
 q(identical(s$origin_remote_url,"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git")&&
  is.character(s$published_ref)&&length(s$published_ref)==1L&&!is.na(s$published_ref)&&
  grepl("^refs/heads/[A-Za-z0-9][A-Za-z0-9_./-]*$",s$published_ref)&&
  !grepl("\\.\\.|//|/$",s$published_ref),"dedicated published source ref required")
 invisible(TRUE)
}
ind_hq_previous_history <- function(s) {
 q<-ind_hq_require
 for(k in c("previous_attempt_terminal","previous_attempt_manifest","previous_attempt_agreements"))ind_aq_pin(s[[k]])
 terminal<-jsonlite::read_json(s$previous_attempt_terminal$path,simplifyVector=FALSE)
 q(identical(terminal$status,"EXECUTION_NOT_ACCEPTED")&&terminal$payload_exit_code==1&&
  identical(terminal$source_commit,"b380b279626def03c5bfc99a524e0b21b4080e76")&&
  identical(terminal$purpose_sha256,"086e940fa63950a1aab89ddc1079bcc24b17a9052a7afd7aed0e43133b364232")&&
  identical(terminal$production_authorized,FALSE),"old failed execution must remain rejected")
 base<-dirname(s$previous_attempt_manifest$path)
 q(identical(dirname(s$previous_attempt_agreements$path),base),"historical agreement/manifest namespace differs")
 m<-read.csv(s$previous_attempt_manifest$path,stringsAsFactors=FALSE)
 q(identical(names(m),c("relative_path","size_bytes","sha256"))&&nrow(m)==13L&&
  !anyDuplicated(m$relative_path)&&all(basename(m$relative_path)==m$relative_path)&&
  all(m$size_bytes>0)&&sum(m$size_bytes)==35680831&&
  setequal(list.files(base,all.files=TRUE,no..=TRUE),c(m$relative_path,"artifact_manifest.csv")),
  "frozen thirteen-artifact history required")
 for(i in seq_len(nrow(m)))ind_aq_pin(list(path=file.path(base,m$relative_path[i]),
  size_bytes=m$size_bytes[i],sha256=m$sha256[i]),max_bytes=16*1024^2)
 a<-read.csv(s$previous_attempt_agreements$path)
 q(nrow(a)==27L&&is.logical(a$agreement)&&sum(a$agreement)==20L,
  "old twenty-of-twenty-seven REVIEW evidence changed")
 list(source_commit=terminal$source_commit,purpose_sha256=terminal$purpose_sha256,
  status="HISTORICAL_EXECUTION_NOT_ACCEPTED_NUMERICAL_REVIEW_RETAINED",agreement_passes=20L,
  agreement_rows=27L,artifact_hashes_verified=nrow(m),artifact_bytes=sum(m$size_bytes),
  historical_RDS_deserializations=0L,old_failure_relabelled=FALSE)
}
ind_hq_required_sources <- function()c("scripts/qualify_ind_high_resolution_filter.R",
 "scripts/ind_high_resolution_qualification.R","scripts/ind_batched_al_auxiliary_filter.R",
 "scripts/qualify_ind_adapted_filter.R","scripts/ind_adapted_auxiliary_filter.R",
 "scripts/ind_guided_auxiliary_filter.R","scripts/ind_guided_auxiliary_primitives.R",
 "scripts/ind_conditional_auxiliary_filter.R","scripts/ind_conditional_filter_replay.R",
 "scripts/qualify_ind_guided_filter.R","scripts/runtime_identity_cache_observations.R")
ind_hq_git <- function(args) {
 z<-system2("/usr/bin/git",c("--no-optional-locks","--no-replace-objects",args),stdout=TRUE)
 ind_hq_require(is.null(attr(z,"status")),"read-only command-line Git check failed")
 unname(z)
}
ind_hq_source <- function(s,root,online=TRUE) {
 q<-ind_hq_require;git<-ind_hq_git
 q(identical(git(c("rev-parse","HEAD")),s$source_commit)&&
  identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
  !length(git(c("status","--porcelain","--untracked-files=normal"))),"clean exact source required")
 paths<-vapply(s$source_files,ind_aq_pin,character(1L))
 q(!anyDuplicated(paths)&&setequal(paths,file.path(root,ind_hq_required_sources())),
  "exact complete transitive source closure required")
 for(rel in ind_hq_required_sources())q(
  identical(git(c("hash-object","--no-filters","--",shQuote(file.path(root,rel)))),
   git(c("rev-parse",shQuote(paste0("HEAD:",rel))))),"source pin differs from its committed Git blob")
 if(online) {
  q(identical(git(c("remote","get-url","origin")),s$origin_remote_url),"origin URL differs")
  keys<-c("GIT_TERMINAL_PROMPT","GIT_SSH_COMMAND");old<-Sys.getenv(keys,unset=NA_character_)
  on.exit(for(i in seq_along(keys))if(is.na(old[i]))Sys.unsetenv(keys[i])else
   do.call(Sys.setenv,setNames(list(old[i]),keys[i])),add=TRUE)
  Sys.setenv(GIT_TERMINAL_PROMPT="0",GIT_SSH_COMMAND=paste("/usr/bin/ssh -F /dev/null -oBatchMode=yes",
   "-oControlMaster=no -oControlPath=none -oControlPersist=no -oProxyCommand=none -oProxyJump=none -oRequestTTY=no"))
  remote<-git(c("ls-remote","--exit-code","origin",s$published_ref))
  q(length(remote)==1L&&identical(strsplit(remote,"[[:space:]]+")[[1L]],
   c(s$source_commit,s$published_ref)),"published source readback differs")
 }
 list(source_files_verified=length(paths),online_source_readback=online)
}
ind_hq_runtime_inventory <- function() {
 z<-ind_aq_runtime_inventory()
 extra<-normalizePath("/usr/bin/ssh",mustWork=TRUE)
 if(!extra%in%z$path) {
  observation<-attributes(z)[c("observational_os_state","observational_os_state_role",
   "deterministic_numerical_runtime_initialization")]
  z<-rbind(z,data.frame(path=extra,size_bytes=file.info(extra)$size,sha256=unname(tools::sha256sum(extra))))
  z<-z[order(z$path),,drop=FALSE];row.names(z)<-NULL
  for(k in names(observation))attr(z,k)<-observation[[k]]
 }
 z
}
ind_hq_timeout_argv <- function(argv) {
 ind_hq_require(is.character(argv)&&length(argv)>=5L&&!anyNA(argv)&&
  basename(argv[1L])=="timeout"&&identical(argv[2:4],c("--signal=TERM","--kill-after=1s","5399s"))&&
  nzchar(argv[5L])&&!startsWith(argv[5L],"-"),"exact native TERM5399/KILL1 scope required")
 invisible(TRUE)
}
ind_hq_process_scope <- function(limits) {
 q<-ind_hq_require;cpu<-as.character(as.integer(limits$logical_cpu))
 affinity<-function(pid="self")trimws(sub("^Cpus_allowed_list:","",
  grep("^Cpus_allowed_list:",readLines(sprintf("/proc/%s/status",pid),warn=FALSE),value=TRUE)))
 q(identical(affinity(),cpu),"payload must retain its granted one-core affinity")
 lines<-readLines("/proc/self/limits",warn=FALSE)
 for(item in list(c("Max cpu time",5400),c("Max address space",2*1024^3),c("Max file size",256*1024^2))) {
  row<-grep(paste0("^",item[1L]),lines,value=TRUE)
  q(length(row)==1L,"native resource limit missing")
  value<-suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",item[1L]),"",row)),"[[:space:]]+")[[1L]][1:2]))
  q(all(is.finite(value))&&all(value==as.numeric(item[2L])),"exact finite native resource limits required")
 }
 pid<-Sys.getpid()
 for(i in 1:10) {
  stat<-ind_aq_proc_stat(readLines(sprintf("/proc/%d/stat",pid),warn=FALSE));parent<-stat$ppid
  if(parent<=1L)break
  raw<-readBin(sprintf("/proc/%d/cmdline",parent),"raw",n=16384L);ends<-which(raw==as.raw(0))
  if(length(ends)&&tail(ends,1L)==length(raw)) {
   starts<-c(1L,head(ends,-1L)+1L)
   argv<-vapply(seq_along(ends),function(j)if(starts[j]>=ends[j])"" else
    rawToChar(raw[seq.int(starts[j],ends[j]-1L)]),character(1L))
   if(length(argv)&&basename(argv[1L])=="timeout") {
    ind_hq_timeout_argv(argv)
    exe<-normalizePath(Sys.readlink(sprintf("/proc/%d/exe",parent)),mustWork=TRUE)
    q(identical(exe,normalizePath("/usr/bin/timeout",mustWork=TRUE))&&identical(affinity(parent),cpu),
     "native timeout executable and affinity differ")
    group<-ind_aq_process_group_proof(readLines("/proc/self/stat",warn=FALSE),
     readLines(sprintf("/proc/%d/stat",parent),warn=FALSE))
    return(list(executable=exe,pid=parent,argv=argv[1:5],logical_cpu=as.integer(cpu),group=group,
     aggregate_single_CPU_wall_bound_seconds=5400L))
   }
  };pid<-parent
 }
 q(FALSE,"exact process-group timeout ancestor missing")
}
ind_hq_quantile_rows <- function(q,both_seeds=TRUE) {
 r<-ind_hq_require;fields<-c("seed","particles","observed_prefix_length","probability","quantile")
 r(is.logical(both_seeds)&&length(both_seeds)==1L&&!is.na(both_seeds),"explicit one- or two-seed scope required")
 r(is.data.frame(q)&&identical(names(q),fields)&&all(vapply(q,is.numeric,logical(1L)))&&
  all(is.finite(as.matrix(q))),"finite typed diagnostic quantile rows required")
 seeds<-if(both_seeds)c(71521,71522)else unique(q$seed)
 r(length(seeds)==if(both_seeds)2L else 1L,"complete one- or two-seed surface required")
 r(all(seeds%in%c(71521,71522)),"undeclared seed rejected")
 key<-function(x)paste(x$seed,x$particles,x$observed_prefix_length,x$probability,sep=":")
 expected<-expand.grid(seed=seeds,particles=c(4096,8192),observed_prefix_length=c(100,250,500),
  probability=c(.05,.5,.95))
 r(nrow(q)==nrow(expected)&&!anyDuplicated(key(q))&&setequal(key(q),key(expected)),
  "complete fixed higher-resolution seed/checkpoint/level membership required")
 for(s in seeds)for(N in c(4096,8192))for(tt in c(100,250,500)) {
  a<-q[q$seed==s&q$particles==N&q$observed_prefix_length==tt,]
  r(all(diff(a$quantile[order(a$probability)])>=0),"diagnostic quantiles are not ordered")
 }
 invisible(TRUE)
}
ind_hq_comparisons <- function(q,both_seeds=TRUE) {
 ind_hq_quantile_rows(q,both_seeds)
 seeds<-sort(unique(q$seed));pairs<-lapply(seeds,function(s)c(s,4096,s,8192))
 if(both_seeds)pairs<-c(pairs,list(c(71521,8192,71522,8192)))
 out<-list()
 for(pair in pairs)for(tt in c(100,250,500))for(pp in c(.05,.5,.95)) {
  pick<-function(seed,N)q$quantile[q$seed==seed&q$particles==N&
   q$observed_prefix_length==tt&q$probability==pp]
  a<-pick(pair[1L],pair[2L]);b<-pick(pair[3L],pair[4L]);tol<-max(.005,.005*max(1,abs((a+b)/2)))
  out[[length(out)+1L]]<-data.frame(seed_A=pair[1L],N_A=pair[2L],seed_B=pair[3L],N_B=pair[4L],
   checkpoint=tt,probability=pp,quantile_A=a,quantile_B=b,tolerance=tol,
   absolute_difference=abs(a-b),agreement=abs(a-b)<=tol)
 }
 do.call(rbind,out)
}
ind_hq_aggregate_metadata <- function(q,receipts,terminals) {
 # The caller separately authenticates file inventories and these external
 # terminal receipts. This pure gate does not authenticate files by itself.
 r<-ind_hq_require;ind_hq_quantile_rows(q,TRUE)
 r(is.list(receipts)&&length(receipts)==2L&&is.list(terminals)&&length(terminals)==2L,
  "two complete actor and external terminal receipts required")
 seeds<-vapply(receipts,function(x)as.numeric(x$seed),numeric(1L))
 r(!anyDuplicated(seeds)&&setequal(seeds,c(71521,71522)),"both fixed seeds required")
 reference<-receipts[[1L]]
 for(i in 1:2) {
  a<-receipts[[i]];t<-terminals[[i]]
  r(identical(a$schema_version,"ind_high_resolution_filter_receipt_v1")&&
   identical(a$status,"BOUNDED_HIGH_RESOLUTION_AL_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION")&&
   identical(a$method,"ancestor_first_AL_exact_v_v1")&&
   identical(a$arithmetic_backend,"batched_AL_scalar_equivalent_v1")&&
   identical(a$rng_namespace,"ind_ancestor_first_AL_high_resolution_max8192_v1")&&
   identical(a$rng_layout,"Mersenne_Twister_max8192_time_major_proposal4_then_ancestor_then_residual_v1")&&
   a$maximum_stream_particles==8192&&a$posterior_column==1&&a$observed_prefix_length==500&&
   a$predeclared_within_seed_agreements==9&&length(a$run_receipts)==2L&&
   setequal(names(a$run_receipts),c("4096","8192")),"complete higher-resolution receipt required")
  for(k in c("source_commit","source_tree","training_input","original_fit","eta","method",
   "arithmetic_backend","rng_namespace","rng_layout"))
   r(identical(a[[k]],reference[[k]]),paste("different source/static-target identity",k))
  for(k in c("source_commit","source_tree"))r(is.character(a[[k]])&&length(a[[k]])==1L&&
   grepl("^[a-f0-9]{40}$",a[[k]]),"complete frozen source identity required")
  r(identical(a$training_input$sha256,"d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496")&&
   identical(a$original_fit$sha256,"1e8ba3de4a6c9e9e0f6bd900be7801e8c80fe0fdff4b6ca24804bdc62e3ff17f")&&
   identical(a$eta$family,"al")&&a$eta$p==.05&&is.finite(a$eta$sigma)&&a$eta$sigma>0&&a$eta$gamma==0,
   "original one-column AL target required")
  for(k in c("original_scalar_reference_unchanged","native_prefix_parity_pass","runtime_verified","caller_RNG_restored"))
   r(identical(a[[k]],TRUE),paste("actor gate not passed",k))
  for(k in c("original_fit_deserialized","filter_accuracy_certified","future_integration_accuracy_certified",
   "full_IF01_or_production_qualified","outer_parameter_weights_updated","future_truth_deserialized",
   "production_authorized","article_promotion_authorized"))
   r(identical(a[[k]],FALSE),paste("invalid scope claim",k))
  r(identical(t$status,"EXECUTION_COMPLETE_NOT_PRODUCTION")&&
   identical(t$source_commit,a$source_commit)&&identical(t$source_tree,a$source_tree)&&
   identical(t$purpose_sha256,a$purpose_contract_sha256)&&t$payload_exit_code==0&&
   is.numeric(t$payload_user_cpu_seconds)&&is.numeric(t$payload_system_cpu_seconds)&&
   all(is.finite(c(t$payload_user_cpu_seconds,t$payload_system_cpu_seconds)))&&
   t$payload_user_cpu_seconds>=0&&t$payload_system_cpu_seconds>=0&&
   t$payload_user_cpu_seconds+t$payload_system_cpu_seconds<=5400&&
   identical(t$production_authorized,FALSE)&&identical(t$article_promotion_authorized,FALSE),
   "accepted bounded external terminal receipt required")
  within<-ind_hq_comparisons(q[q$seed==a$seed,,drop=FALSE],FALSE)
  r(a$within_seed_passes==sum(within$agreement),"stored within-seed count does not reconstruct")
 }
 comparisons<-ind_hq_comparisons(q,TRUE)
 list(status=if(all(comparisons$agreement))"PASS_27_DESCRIPTIVE_AGREEMENTS_ONLY"else"REVIEW",
  comparisons=comparisons,passed=sum(comparisons$agreement),total=nrow(comparisons),
  source_commit=reference$source_commit,source_tree=reference$source_tree,
  file_and_receipt_byte_authentication_remains_a_caller_requirement=TRUE,
  filter_accuracy_certified=FALSE,future_integration_accuracy_certified=FALSE,
  full_IF01_or_production_qualified=FALSE,production_authorized=FALSE,article_promotion_authorized=FALSE)
}
