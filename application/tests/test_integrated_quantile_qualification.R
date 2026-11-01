#!/usr/bin/env Rscript
# Synthetic metadata/redaction fixtures only. No authentic posterior is read.
file_arg<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
repo<-normalizePath(file.path(dirname(file_arg),"../.."))
source(file.path(repo,"application/R/integrated_quantile_forecast.R"))
source(file.path(repo,"scripts/qualify_integrated_quantile_forecast.R"))
ncheck<-0L
check<-function(x){stopifnot(isTRUE(x));ncheck<<-ncheck+1L}
reject<-function(expr,pattern){e<-tryCatch({force(expr);NULL},error=identity)
  check(inherits(e,"error"));check(grepl(pattern,conditionMessage(e)))}
sha<-paste(rep("a",64L),collapse="")
contract<-list(schema_version="integrated_quantile_qualification_contract_v1",
  purpose="MQ_Q2_ONE_DRAW_ORIGIN",source_schema="mq_native_worker_v1",
  model_cell_id="asymmetric_laplace_tail__joint_qdesn_rhs",chain_id=1L,source_row=1L,
  source_draw_index=1L,origin_id=1L,origin_time=11000L,horizons=30L,inner_paths=4096L,
  readout_slopes=20L,tau=c(.05,.10,.25,.50,.75,.90,.95),rng_namespace="fixed_scientific_namespace",
  posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
  source_commit=paste(rep("b",40),collapse=""),source_tree=paste(rep("c",40),collapse=""),
  source_manifest_sha256=sha,integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,
    max_split_absolute=.1,max_split_relative=.1,max_quantile_abs_error=.1,max_quantile_rel_error=.1))
check(q2_geometry(contract))
bad<-contract;bad$inner_paths<-2048L;reject(q2_geometry(bad),"frozen original unit")
bad<-contract;bad$origin_time<-1000L;reject(q2_geometry(bad),"frozen original unit")
bad<-contract;bad$tau<-c(.05,.20,.35,.50,.65,.80,.95);reject(q2_geometry(bad),"frozen original unit")
bad<-contract;bad$source_schema<-"unknown_context";reject(q2_geometry(bad),"scope/schema")
bad<-contract;bad$posterior_target_sha256<-sha;reject(q2_geometry(bad),"posterior target")
bad<-contract;bad$integration_accuracy$alpha_per_shard<-1;reject(q2_geometry(bad),"accuracy/scientific RNG")

# The native ordinary design is deliberately contaminated with unused future
# fields. The preparer must select a whitelist, not merely promise not to use it.
toy<-list(scenario_id="asymmetric_laplace_tail",feature_contract="pure_recursive_v1",
  design_class="reservoir",response_lags=5L,reservoir=list(D=1L),
  reservoir_meta=list(win_scale_global=.1,hidden_future_truth=999999),
  scale_params=list(center=rep(0,5),scale=rep(1,5)),state_center=rep(0,20),state_scale=rep(1,20),
  Z=matrix(c(rep(0,3*20),rep(999999,2*20)),nrow=5L,byrow=TRUE,
    dimnames=list(NULL,paste0("reservoir_",sprintf("%04d",1:20)))),
  row_meta=data.frame(full_time_index=10998:11002,future_truth=999999),
  forecast_map=data.frame(origin_index=1L,horizon=1:30,full_time_index=11001:11030,future_truth=999999),
  dgp_row=data.frame(simulated_length=12000L,period=30L,dynamics_class="fixture",
    regime_start_fraction=.5,private_truth=999999),future_truth=999999)
fixture<-list(y=c(rep(1,11000),rep(999999,30)),true_q=rep(999999,11030))
draws<-as.data.frame(matrix(0,nrow=750L,ncol=147L))
names(draws)<-c(sprintf("beta_%04d",1:140),sprintf("alpha_%04d",1:7))
draws$draw_index<-1:750
for(k in 1:7)draws[[sprintf("sigma_%04d",k)]]<-1
draws[1,1:147]<-seq_len(147)/1000
objects<-q2_payloads(toy,fixture,draws,contract)
check(length(objects$origins[[1]]$history)==11000L&&all(objects$origins[[1]]$history==1))
check(nrow(objects$design$Z)==3L&&all(objects$design$Z==0))
check(identical(names(objects$design$row_meta),"full_time_index"))
check(!"future_truth"%in%names(objects$design)&&!"future_truth"%in%names(objects$design$forecast_map))
check(!"private_truth"%in%names(objects$design$dgp_row)&&!"hidden_future_truth"%in%names(objects$design$reservoir_meta))
check(identical(dim(objects$posterior$beta),c(1L,140L))&&identical(dim(objects$posterior$alpha),c(1L,7L)))
check(max(abs(as.numeric(objects$posterior$beta)-seq_len(140)/1000))==0)
check(all(objects$mapping$source_draw_index==1L)&&all(objects$mapping$chain_id==1L))
check(identical(objects$posterior$draw_mapping_sha256,app_iqf_hash(objects$mapping)))
bad<-toy;bad$forecast_map$full_time_index<-1001:1030
reject(q2_payloads(bad,fixture,draws,contract),"design/clock mismatch")
reject(q2_payloads(toy,fixture,draws[-1,],contract),"row/cardinality mismatch")
bad_draws<-draws;bad_draws$future_response<-999999
reject(q2_payloads(toy,fixture,bad_draws,contract),"nonparameter payload")

# Metadata validation reads only regular bytes/CSV metadata, not source RDSs.
temp<-tempfile("iqf_q2_synthetic_");dir.create(temp)
on.exit_cleanup<-function()unlink(temp,recursive=TRUE)
for(name in c("design.rds","fixture.rds","posterior_draws.csv.gz","posterior_target_contract.csv"))
  writeLines("synthetic non-RDS bytes",file.path(temp,name))
# Non-response reference fields from the frozen target contract. Reproducing
# its canonical hash is a metadata check, not a fit or a future-data fixture.
target_values<-c(contract_version="joint_qdesn_posterior_target_v1",likelihood_family="AL",fit_structure="joint",
  coefficient_hierarchy="first_quantile_anchor_adjacent_differences",ordered_intercepts="true",
  quantile_grid="0.050000000000000003;0.10000000000000001;0.25000000000000000;0.50000000000000000;0.75000000000000000;0.90000000000000002;0.94999999999999996",
  data_design_fingerprint="967e5494dc8e15b25926174d74019d8c3f93ecadd65ad2dca38144f01e577d0a",
  kappa="1.0000000000000000",tau0="0.00010000000000000000",zeta2="1.0000000000000000",slab_fixed="true",
  a_sigma="2.0000000000000000",b_sigma="1.0000000000000000",
  alpha_prior_mean="-0.31821545700745557;-0.086269816451768344;0.30130117907918980;0.73192069318722752;1.1625402072952653;1.5501112028262234;1.7820568433819099",
  alpha_prior_sd=paste(rep("1.2768748938967622",7L),collapse=";"),alpha_min_spacing="0.000000010000000000000000",
  sigma_lower_bound="0",sigma_upper_bound="Inf",gamma_prior_type="none",score_definition="dgp_integrated_finite_grid_acrps",
  projection_rule="weighted_isotonic_equal_weights",draw_coupling="matched_draw_index_with_repeated_permutation_sensitivity")
utils::write.csv(data.frame(field=names(target_values),value=unname(target_values)),
  file.path(temp,"posterior_target_contract.csv"),row.names=FALSE)
utils::write.csv(data.frame(relative_path=c("posterior_draws.csv.gz","posterior_target_contract.csv"),
  size_bytes=file.info(file.path(temp,c("posterior_draws.csv.gz","posterior_target_contract.csv")))$size,
  sha256=vapply(file.path(temp,c("posterior_draws.csv.gz","posterior_target_contract.csv")),q2_sha,"")),
  file.path(temp,"worker_manifest.csv"),row.names=FALSE)
utils::write.csv(data.frame(model_cell_id=contract$model_cell_id,verified=TRUE,n_chains=5L,
  posterior_target_sha256=contract$posterior_target_sha256),file.path(temp,"cell_target_audit.csv"),row.names=FALSE)
files<-c(design="design.rds",fixture="fixture.rds",posterior="posterior_draws.csv.gz",
  target_contract="posterior_target_contract.csv",worker_manifest="worker_manifest.csv",cell_target_audit="cell_target_audit.csv")
contract$assets<-lapply(files,function(name){path<-file.path(temp,name)
  list(path=path,size_bytes=as.numeric(file.info(path)$size),sha256=q2_sha(path))})
check(nrow(q2_metadata(contract))==6L)
bad<-contract;bad$assets$fixture$sha256<-sha;reject(q2_metadata(bad),"source size/hash mismatch")
bad<-contract;bad$assets$unknown<-bad$assets$design;reject(q2_metadata(bad),"six-source inventory")
if(.Platform$OS.type=="unix") {
  link<-file.path(temp,"linked_fixture.rds")
  if(file.symlink(file.path(temp,"fixture.rds"),link))reject(q2_regular(link),"symlink")
}
reject(q2_source(contract,repo),"committed, clean")
reject(q2_limits(list(logical_cpu=999999L)),"taskset")
auth<-c(contract[c("source_commit","source_tree","source_manifest_sha256","posterior_target_sha256")],
  list(schema_version="integrated_quantile_qualification_authorization_v1",allow_qualification=FALSE,
    allow_production=FALSE,approved_by="synthetic-test-only",allowed_operations=list("prepare","run"),
    expires_utc="2099-01-01T00:00:00Z",contract_sha256=sha))
ap<-file.path(temp,"auth.json")
jsonlite::write_json(auth,ap,auto_unbox=TRUE)
reject(q2_authorize(contract,sha,ap,q2_sha(ap),"prepare",repo),"not explicitly authorized")
auth$allow_qualification<-TRUE;auth$contract_sha256<-paste(rep("d",64),collapse="")
jsonlite::write_json(auth,ap,auto_unbox=TRUE)
reject(q2_authorize(contract,sha,ap,q2_sha(ap),"prepare",repo),"exact source/input contract")
auth$contract_sha256<-sha;auth$allow_production<-TRUE
jsonlite::write_json(auth,ap,auto_unbox=TRUE)
reject(q2_authorize(contract,sha,ap,q2_sha(ap),"prepare",repo),"not explicitly authorized")

# Qualification PASS is a numerical diagnostic only, never production status.
result<-list(quantiles=data.frame(quantile=c(0,1)),integration_diagnostic=data.frame(
  split_stream_absolute_difference=c(.01,.02),split_stream_relative_difference=c(.01,.02)),
  integration_dkw=data.frame(max_estimate_error_bound=c(.01,.02)))
check(identical(q2_accuracy(result,contract$integration_accuracy),"PASS_PREDECLARED_Q2_NUMERICAL_DIAGNOSTIC_ONLY"))
result$integration_dkw$max_estimate_error_bound[1]<-Inf
check(identical(q2_accuracy(result,contract$integration_accuracy),"REVIEW_INNER_INTEGRATION_RESOLUTION"))
path<-file.path(temp,"synthetic_payload.rds")
used<-q2_write(objects,path,0,10*1024^2)
check(identical(readRDS(path),objects)&&used==file.info(path)$size)
reject(q2_write(objects,path,0,10*1024^2),"overwrite/exceed")
reject(q2_write(objects,file.path(temp,"too_large.rds"),0,1),"overwrite/exceed")

# Default CLI validates a pinned synthetic metadata contract, requiring no token,
# no model deserialization and no launch grant. Explicit run remains blocked.
cp<-file.path(temp,"contract.json");jsonlite::write_json(contract,cp,auto_unbox=TRUE,digits=17)
cli<-system2(file.path(R.home("bin"),"Rscript"),c(shQuote(file.path(repo,"scripts/qualify_integrated_quantile_forecast.R")),
  "--contract",shQuote(cp),"--contract-sha256",q2_sha(cp)),stdout=TRUE,stderr=TRUE)
check(is.null(attr(cli,"status"))&&any(grepl("METADATA_ONLY_VALIDATED",cli)))
blocked<-suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),c(shQuote(file.path(repo,"scripts/qualify_integrated_quantile_forecast.R")),
  "--mode","run","--contract",shQuote(cp),"--contract-sha256",q2_sha(cp)),stdout=TRUE,stderr=TRUE))
check(!is.null(attr(blocked,"status")))
on.exit_cleanup()
cat(sprintf("test_integrated_quantile_qualification: PASS (%d synthetic checks; zero authentic preparation/forecast)\n",ncheck))
