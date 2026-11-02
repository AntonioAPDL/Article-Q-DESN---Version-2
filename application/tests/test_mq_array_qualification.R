#!/usr/bin/env Rscript
local({
  source("scripts/mq_array_qualification.R",local=TRUE)
  source("scripts/qualify_mq_array_methods.R",local=TRUE)
  source("scripts/prepare_mq_array_observed_prefix.R",local=TRUE)
  source("application/R/integrated_quantile_forecast.R",local=TRUE)
  n <- 0L
  check <- function(x){stopifnot(isTRUE(x));n<<-n+1L}
  reject <- function(e,pattern=NULL) {
    z <- tryCatch({force(e);NULL},error=base::identity);check(inherits(z,"error"))
    if(!is.null(pattern))check(grepl(pattern,conditionMessage(z),fixed=TRUE))
  }
  pin <- function(path)list(path=path,size_bytes=as.numeric(file.info(path)$size),sha256=unname(tools::sha256sum(path)))
  sha <- function(n=64)strrep("a",n)
  assets <- setNames(lapply(c("design","fixture","posterior","target_contract","worker_manifest","cell_target_audit"),
    function(x)list(path=paste0("/synthetic_only/",x),size_bytes=1,sha256=sha())),
    c("design","fixture","posterior","target_contract","worker_manifest","cell_target_audit"))
  unit <- list(schema_version="integrated_quantile_qualification_contract_v1",purpose="MQ_Q2_ONE_DRAW_ORIGIN",
    source_schema="mq_native_worker_v1",model_cell_id="asymmetric_laplace_tail__joint_qdesn_rhs",chain_id=1L,
    source_row=1L,source_draw_index=1L,origin_id=1L,origin_time=11000L,horizons=30L,inner_paths=4096L,
    readout_slopes=20L,tau=c(.05,.1,.25,.5,.75,.9,.95),rng_namespace="synthetic_qualification_only",
    posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
    assets=assets,integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,
      max_split_absolute=.005,max_split_relative=.005,max_quantile_abs_error=.01,max_quantile_rel_error=.01))
  spec <- list(schema_version="mq_array_source_qualification_contract_v1",
    purpose="NEW_SOURCE_MQ_ARRAY_ONE_ORIGINAL_DRAW_ORIGIN",allow_qualification=TRUE,allow_refit=FALSE,
    allow_production=FALSE,allow_scoring=FALSE,allow_article=FALSE,allow_raw_fixture_deserialization=FALSE,
    source_commit=sha(40),source_tree=sha(40),training_paths=65536L,validation_paths=262144L,batch_size=128L,
    training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),
    validation_look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3),
    inversion_tolerance=1e-8,parity_absolute_tolerance=1e-10,parity_relative_tolerance=1e-10,
    parity_path_ids=c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,65535,65536,65537,327680),
    rng_backend="r46_first_step",stop_before_validation_on_split_failure=TRUE,original_unit=unit,
    limits=list(cpu_seconds=1800L,wall_term_seconds=1799L,wall_kill_after_seconds=1L,
      address_space_bytes=16*1024^3,output_bytes=256*1024^2,logical_cpu=27L),
    origin_remote_url="git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git",published_ref="refs/heads/test-only",
    baseline_contract=list(sha256="c1490494d4307cf29ea74f3c002e765ecb790486fe4fad24c0bf04b65a9df4e6"),
    baseline_receipt=list(sha256="bffaeb83b8f341603542965cecb877a865f5b152d0b16ac4e872dc11c6b6a1cf"),
    baseline_manifest=list(sha256="3cca4efe27ede0759d643b560259336c16492c3dce5b87188927f043be9053da"))
  check(mqa_scope(spec))
  check(mqa_metadata_equal(list(a=1L,b=list(x="unchanged")),list(b=list(x="unchanged"),a=1)))
  check(!mqa_metadata_equal(list(a=list(1,2)),list(a=list(2,1))))
  check(!mqa_metadata_equal(list(a="1"),list(a=1)))
  check(!mqa_metadata_equal(list(a=1),list(a=2)))
  check(!mqa_metadata_equal(setNames(list(1,2),c("x","x")),list(x=1)))
  bad<-spec;bad$extra<-setNames(list(1,2),c("duplicate","duplicate"));reject(mqa_scope(bad),"duplicate")
  bridge_tmp<-tempfile("mq_synthetic_asset_bridge_");dir.create(bridge_tmp)
  on.exit(unlink(bridge_tmp,recursive=TRUE),add=TRUE)
  localized<-unit;recorded<-unit
  for(role in names(unit$assets)) {
    path<-file.path(bridge_tmp,role);writeLines(paste0("synthetic_",role),path)
    localized$assets[[role]]<-pin(path);recorded$assets[[role]]<-pin(path)
    recorded$assets[[role]]$path<-paste0("/recorded_original_host/",role)
  }
  bridge<-mqa_original_unit_bridge(localized,recorded)
  check(all(vapply(bridge$assets,`[[`,logical(1L),"path_relocated"))&&
    bridge$materialized_content_reverification_required&&!bridge$original_contract_rewritten)
  reordered<-recorded[rev(seq_along(recorded))]
  check(mqa_metadata_equal(bridge,mqa_original_unit_bridge(localized,reordered)))
  bad<-localized;bad$origin_time<-11001L;reject(mqa_original_unit_bridge(bad,recorded))
  bad<-localized;bad$assets$design$sha256<-strrep("b",64);reject(mqa_original_unit_bridge(bad,recorded),"size or SHA")
  bad<-localized;bad$assets$fixture$size_bytes<-bad$assets$fixture$size_bytes+1;reject(mqa_original_unit_bridge(bad,recorded),"size or SHA")
  bad<-localized;bad$assets$design<-bad$assets$fixture;reject(mqa_original_unit_bridge(bad,recorded),"size or SHA")
  bad<-localized;bad$assets<-bad$assets[-1];reject(mqa_original_unit_bridge(bad,recorded),"six")
  bad<-recorded;bad$assets$design$path<-"relative/design";reject(mqa_original_unit_bridge(localized,bad),"canonical")
  bad<-localized;bad$assets$design$path<-file.path(bridge_tmp,".","design");reject(mqa_original_unit_bridge(bad,recorded),"canonical")
  link_asset<-file.path(bridge_tmp,"linked_design");file.symlink(localized$assets$design$path,link_asset)
  bad<-localized;bad$assets$design$path<-link_asset;reject(mqa_original_unit_bridge(bad,recorded),"symlink")
  for(key in c("allow_refit","allow_production","allow_scoring","allow_article","allow_raw_fixture_deserialization")) {
    bad<-spec;bad[[key]]<-TRUE;reject(mqa_scope(bad))
  }
  for(key in c("training_paths","validation_paths","batch_size","total_alpha","inversion_tolerance",
    "parity_absolute_tolerance","parity_relative_tolerance")) {
    bad<-spec;bad[[key]]<-spec[[key]]*2;reject(mqa_scope(bad))
  }
  for(key in c("cpu_seconds","wall_term_seconds","wall_kill_after_seconds","address_space_bytes","output_bytes","logical_cpu")) {
    bad<-spec;bad$limits[[key]]<-spec$limits[[key]]+1;reject(mqa_scope(bad))
  }
  for(key in c("schema_version","purpose","rng_backend","origin_remote_url")) {
    bad<-spec;bad[[key]]<-"old_or_unknown";reject(mqa_scope(bad))
  }
  for(value in c("refs/heads/x..y","refs/heads/a//b","refs/heads/a/","HEAD")) {
    bad<-spec;bad$published_ref<-value;reject(mqa_scope(bad))
  }
  bad<-spec;bad$alpha_per_look<-c(.05,.05,.05);reject(mqa_scope(bad))
  bad<-spec;bad$parity_path_ids<-rev(bad$parity_path_ids);reject(mqa_scope(bad))
  bad<-spec;bad$stop_before_validation_on_split_failure<-FALSE;reject(mqa_scope(bad))
  bad<-spec;bad$baseline_receipt$sha256<-sha();reject(mqa_scope(bad))
  # A new checkout path is not a new native source. Historical receipt/status
  # and native bytes remain exact; the newly executed source is separate.
  b<-list(schema_version="mq_batch_acceleration_qualification_v1",
    source_commit="a099aba928e6d1fb01931a4b12466125bbb2bc64",
    source_tree="48b8baa236859f9f32969593101c75ff45bfa88c",original_unit=unit,
    original_unit_contract=list(path="/old/unit.json",size_bytes=1,sha256=sha()),
    source_manifest=list(path="/old/native.csv",size_bytes=1,sha256=sha()),
    native_rng_source=list(path="/old/RNG.c",size_bytes=1,sha256=sha()),rng_backend="r46_first_step")
  r<-b;r$schema_version<-"mq_batch_acceleration_qualification_receipt_v1"
  r$purpose_contract_sha256<-spec$baseline_contract$sha256;r$status<-"QUALIFICATION_COMPLETE_NOT_PRODUCTION"
  r$numerical_status<-"REVIEW_NUMERICAL_ACCURACY_NOT_QUALIFIED"
  r$original_legacy_numerical_status<-"REVIEW_INNER_INTEGRATION_RESOLUTION"
  r$old_failure_receipts_preserved<-TRUE;r$thresholds_loosened<-FALSE
  r$production_authorized<-FALSE;r$article_promotion_authorized<-FALSE;r$observational_future_truth_used<-FALSE
  r$parameter_refits<-0L;r$score_evaluations<-0L
  hist<-spec
  for(k in c("original_unit_contract","source_manifest","native_rng_source","rng_backend"))hist[[k]]<-b[[k]]
  hist$source_manifest$path<-"/new/native.csv"
  check(mqa_history_fields(hist,b,r))
  bad<-r;bad$numerical_status<-"PASS_NEW_SOURCE";reject(mqa_history_fields(hist,b,bad),"historical REVIEW")
  bad<-hist;bad$source_manifest$sha256<-strrep("b",64);reject(mqa_history_fields(bad,b,r),"manifest bytes changed")
  check(identical(mqa_parity_ids(spec,FALSE,FALSE),as.integer(spec$parity_path_ids[1:14])))
  check(identical(mqa_parity_ids(spec,TRUE,TRUE),c(65537L,327680L)))
  check(length(mqa_parity_ids(spec,TRUE,FALSE))==0L)
  reject(mqa_parity_ids(spec,FALSE,TRUE))
  check(mqa_timeout_argv(c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","1799s","Rscript")))
  for(argv in list(c("timeout","--signal=KILL","--kill-after=1s","1799s","Rscript"),
    c("timeout","--signal=TERM","--kill-after=1s","1800s","Rscript"),
    c("timeout","--signal=TERM","--kill-after=1s","1799s","--foreground")))reject(mqa_timeout_argv(argv))
  stat<-function(pid,pgid,sid)paste(pid,"(synthetic process)","R",1,pgid,sid,paste(rep(0,10),collapse=" "))
  check(is.list(mqa_group_guard(stat(102,100,50),stat(100,100,50),100)))
  reject(mqa_group_guard(stat(102,102,102),stat(100,100,50),100),"escaped")
  reject(mqa_group_guard(stat(102,100,51),stat(100,100,50),100),"escaped")
  reject(mqa_group_guard(stat(102,50,50),stat(100,50,50),100),"foreground")
  reject(mqa_group_guard(stat(102,100,50),stat(100,100,50),99))
  check(is.list(mqa_affinity_guard("27","27")))
  reject(mqa_affinity_guard("27","0-63"),"supervisor")
  reject(mqa_affinity_guard("0-63","27"),"supervisor")
  reject(mqa_main(c("--contract","missing","--sha256",sha())),"execute")
  reject(mqa_verify_prepared(spec,getwd()),"MISSING_AUTHENTIC_OBSERVED_PREFIX_REDUCTION")
  prep_scope <- spec;prep_scope$schema_version<-"mq_array_trusted_prefix_preparation_contract_v1"
  prep_scope$purpose<-"SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION"
  prep_scope$allow_original_archive_prefix_preparation<-TRUE;prep_scope$allow_qualification<-FALSE
  prep_scope$allow_future_response_values<-FALSE;prep_scope$allow_builder_calls<-FALSE
  prep_scope$selector<-"UNCHANGED_Q2_OBSERVED_PREFIX_AND_NATIVE_PARAMETER_ROW_ONLY"
  prep_scope$limits<-list(cpu_seconds=120,wall_term_seconds=119,wall_kill_after_seconds=1,
    address_space_bytes=2*1024^3,output_bytes=64*1024^2,logical_cpu=27)
  check(mqa_preparation_scope(prep_scope))
  for(key in c("allow_qualification","allow_future_response_values","allow_builder_calls","allow_refit","allow_scoring")) {
    bad<-prep_scope;bad[[key]]<-TRUE;reject(mqa_preparation_scope(bad))
  }
  bad<-prep_scope;bad$limits$wall_term_seconds<-120;reject(mqa_preparation_scope(bad))
  check(mqa_timeout_argv(c("timeout","--signal=TERM","--kill-after=1s","119s","Rscript"),119L))
  reject(mqa_preparation_main(character()),"execute")

  # Tiny generated native-schema inputs: the dimensions match the frozen unit
  # but no authentic observations, fit or retained draw is read.
  d <- list(scenario_id="asymmetric_laplace_tail",feature_contract="pure_recursive_v1",design_class="reservoir",
    response_lags=2L,reservoir=list(D=1L,W=list(matrix(0,20,20)),Win=list(matrix(0,20,3))),
    scale_params=list(standardize=FALSE),state_center=rep(0,20),state_scale=rep(1,20),
    reservoir_meta=list(win_scale_global=1,unused_future_information="must_not_be_retained"),
    dgp_row=data.frame(simulated_length=11030,period=12,dynamics_class="ar_fixture",regime_start_fraction=.5,
      true_parameter="not_retained"),Z=matrix(0,11030,20),
    row_meta=data.frame(full_time_index=1:11030),forecast_map=data.frame(origin_index=1L,horizon=1:30,
      full_time_index=11001:11030,true_quantile=123))
  fixture <- list(y=sin((1:11030)/20),future_truth="not_retained")
  draws <- as.data.frame(matrix(.1,750,155))
  names(draws)<-c("draw_index",sprintf("beta_%04d",1:140),sprintf("alpha_%04d",1:7),sprintf("sigma_%04d",1:7))
  draws$draw_index<-1:750
  prep <- list(source_commit=sha(40),source_tree=sha(40),purpose_contract_sha256=sha(),
    reducer_relative_path="scripts/mq_array_qualification.R",reducer_sha256=sha(),
    trusted_original_byte_verification=TRUE,read_permission_scope="SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION",
    archive_design_deserializations=1L,archive_fixture_deserializations=1L,original_posterior_csv_reads=1L,
    future_response_values_consulted=FALSE,model_calls=0L,scoring_calls=0L)
  reduced <- mqa_reduce_original_payload(d,fixture,draws,unit,prep)
  ss <- spec;ss$prepared_source <- prep
  check(mqa_validate_derivation(reduced$objects,reduced$derivation,unit,ss))
  receipt_roundtrip<-jsonlite::fromJSON(jsonlite::toJSON(reduced$derivation,auto_unbox=TRUE,digits=17),simplifyVector=FALSE)
  check(mqa_validate_derivation(reduced$objects,receipt_roundtrip,unit,ss))
  check(length(reduced$objects$origins[[1]]$history)==11000L)
  # Changing every future response/state/true-quantile value cannot alter the
  # reduced payload. Historical-byte verification remains a separate receipt.
  changed_d<-d;changed_f<-fixture
  changed_d$Z[11001:11030,]<-999;changed_d$forecast_map$true_quantile<- -999
  changed_f$y[11001:11030]<- -999;changed_f$future_truth<-.Machine$double.xmax
  again<-mqa_reduce_original_payload(changed_d,changed_f,draws,unit,prep)
  check(identical(reduced$objects,again$objects))
  check(identical(reduced$derivation$protected_field_sha256,again$derivation$protected_field_sha256))
  changed_f$y[1]<-changed_f$y[1]+1
  observed_changed<-mqa_reduce_original_payload(changed_d,changed_f,draws,unit,prep)
  check(!identical(reduced$derivation$observed_prefix_sha256,observed_changed$derivation$observed_prefix_sha256))
  for(mutate in list(function(o){o$origins[[1]]$history<-c(o$origins[[1]]$history,0);o},
    function(o){o$design$forecast_map$true_quantile<-1;o},function(o){o$design$row_meta$full_time_index[1]<-11001;o},
    function(o){o$posterior$source_draw_index<-2;o},function(o){o$mapping$future_truth<-0;o})) {
    bad<-mutate(reduced$objects);reject(mqa_validate_derivation(bad,reduced$derivation,unit,ss))
  }
  bad<-reduced$derivation;bad$original_assets$fixture$sha256<-strrep("b",64)
  reject(mqa_validate_derivation(reduced$objects,bad,unit,ss))
  bad<-reduced$objects;bad$origins[[1]]$history[1]<-bad$origins[[1]]$history[1]+.01
  reject(mqa_validate_derivation(bad,reduced$derivation,unit,ss))
  bad<-ss;bad$prepared_source$read_permission_scope<-"QUALIFICATION_MAY_READ_RAW_FIXTURE"
  reject(mqa_validate_derivation(reduced$objects,reduced$derivation,unit,bad))
  bad<-reduced$objects;bad$design$reservoir$callback<-function()fixture$y
  reject(mqa_validate_reduced_objects(bad,unit),"callbacks")
  bad<-reduced$objects;attr(bad$design$reservoir,"closure")<-new.env()
  reject(mqa_validate_reduced_objects(bad,unit),"callbacks")
  bad<-reduced$objects;bad$design$reservoir$future_y<-rep(0,30)
  reject(mqa_validate_reduced_objects(bad,unit),"unknown fields")
  bad<-reduced$objects;attr(bad$design$Z,"future_y")<-rep(0,30)
  reject(mqa_validate_reduced_objects(bad,unit),"response-bearing attributes")
  # Individual matrix CDF contributions preserve atoms, ties and infinities.
  tau<-unit$tau;q<-matrix(rep(c(-2,-2,-1,0,1,2,2),3),3,byrow=TRUE)
  y<-c(-Inf,-2,-1.5,0,2,Inf)
  actual<-mqa_cdf_rows(y,q,tau)
  reference<-t(vapply(1:3,function(i)app_iqf_mq_grid_cdf(y,q[i,],tau),numeric(length(y))))
  check(isTRUE(all.equal(actual,reference,tolerance=0)))
  reject(mqa_cdf_rows(y,q,rev(tau)))
  bad<-q;bad[1,1]<-Inf;reject(mqa_cdf_rows(y,bad,tau))

  # Source/byte-guard mutations use a tiny temporary Git repository only.
  tmp<-tempfile("mq_array_qualification_source_fixture_");dir.create(tmp)
  on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  git<-function(a){z<-system2("git",c("-C",shQuote(tmp),a),stdout=TRUE,stderr=TRUE);stopifnot(is.null(attr(z,"status")));unname(z)}
  git(c("init","--quiet"));git(c("config","user.name","synthetic-test"));git(c("config","user.email","synthetic@example.invalid"))
  paths<-mqa_required_sources("application/R/integrated_quantile_forecast.R")
  for(p in paths){dir.create(dirname(file.path(tmp,p)),recursive=TRUE,showWarnings=FALSE);writeLines("# synthetic source fixture",file.path(tmp,p))}
  writeLines("local_trackers/",file.path(tmp,".gitignore"))
  native<-data.frame(path="application/R/integrated_quantile_forecast.R",role="new_workflow",mode="100644",
    sha256=unname(tools::sha256sum(file.path(tmp,paths[grepl("^application/R/integrated_quantile_forecast",paths)]))),
    blob=git(c("hash-object","application/R/integrated_quantile_forecast.R")))
  sm<-file.path(tmp,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv")
  dir.create(dirname(sm),recursive=TRUE);write.csv(native,sm,row.names=FALSE)
  git(c("add","."));git(c("commit","--quiet","-m",shQuote("Synthetic guard fixture")))
  gs<-list(source_commit=git(c("rev-parse","HEAD")),source_tree=git(c("rev-parse","HEAD^{tree}")),
    source_manifest=pin(sm),source_files=lapply(file.path(tmp,paths),pin))
  check(is.list(mqa_source_guard(gs,tmp,FALSE)))
  bad<-gs;bad$source_commit<-sha(40);reject(mqa_source_guard(bad,tmp,FALSE),"clean exact")
  bad<-gs;bad$source_files<-bad$source_files[-1];reject(mqa_source_guard(bad,tmp,FALSE),"complete transitive")
  bad<-gs;bad$source_files[[1]]$sha256<-sha();reject(mqa_source_guard(bad,tmp,FALSE),"bytes changed")
  target<-file.path(tmp,paths[1]);writeLines("mutated source",target)
  reject(mqa_source_guard(gs,tmp,FALSE),"clean exact")
  p<-file.path(tmp,"pin_fixture");writeLines("pin",p);pp<-pin(p);check(identical(mqa_pin(pp),p))
  link<-file.path(tmp,"pin_link");file.symlink(p,link);bad<-pp;bad$path<-link;reject(mqa_pin(bad),"symlink")
  cat(sprintf("MQ_ARRAY_QUALIFICATION_GUARD_CHECKS=%d PASS; synthetic_only=TRUE authentic_reads=0 qualification_executions=0\n",n))
})
