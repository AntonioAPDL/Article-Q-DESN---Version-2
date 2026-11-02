# Pure native extraction and replay comparisons. No I/O, fitter or RNG calls.
ind_qnc_require <- function(ok,why) {
  if(!isTRUE(ok))stop(paste0("IND QDESN catalog: ",why),call.=FALSE)
  invisible(TRUE)
}
ind_qnc_hash <- function(x) {
  ind_qnc_require(requireNamespace("digest",quietly=TRUE),"digest required")
  digest::digest(x,algo="sha256",serialize=TRUE,serializeVersion=2L)
}
ind_qnc_requests <- function(contracts) {
  q <- ind_qnc_require
  q(is.list(contracts)&&length(contracts)==78L,"exactly78 QDESN chain contracts required")
  rows <- lapply(contracts,function(c) {
    t <- c$task;cfg <- c$config
    q(is.list(c)&&identical(c$engine,"qdesn")&&is.list(t)&&is.list(cfg)&&
      identical(t$refit_authorized,FALSE)&&t$chain_id %in% 1:3&&
      t$family %in% c("normal","laplace","gausmix")&&t$p %in% c(.05,.25,.5)&&
      t$model_variant %in% c("qdesn_al_rhs_ns","qdesn_exal_rhs_ns")&&
      is.character(t$task_id)&&length(t$task_id)==1L&&nzchar(t$task_id)&&
      is.character(t$replay_id)&&length(t$replay_id)==1L&&nzchar(t$replay_id)&&
      identical(c$package_version,"1.0.0")&&
      is.logical(c$refit_authorized)&&length(c$refit_authorized)==1L&&!is.na(c$refit_authorized)&&
      is.numeric(t$n_draws)&&length(t$n_draws)==1L&&t$n_draws %in% c(1000,4000)&&
      c$source_commit %in% c("c72e19f345da88fc1a8175ed30bdde328eab88be",
        "d6bc4c5e47a922ea0255f3ad8d73e58f374827a0")&&
      identical(cfg$inference$method,"mcmc")&&cfg$inference$mcmc$n_mcmc==20000&&
      cfg$inference$mcmc$n_burn==5000&&cfg$inference$mcmc$thin==1,
      "frozen QDESN source, likelihood, chain and native retention required")
    expected <- if(t$model_variant=="qdesn_al_rhs_ns")"al" else "exal"
    q(identical(cfg$inference$likelihood_family,expected)&&
      is.character(t$key)&&length(t$key)==1L&&
      tail(strsplit(t$key,"|",fixed=TRUE)[[1L]],1L) %in% c("forecast_mae","forecast_check"),
      "explicit criterion role and matching likelihood required")
    data.frame(task_id=t$task_id,replay_id=t$replay_id,chain_id=as.integer(t$chain_id),
      source_commit=c$source_commit,package_version=c$package_version,family=t$family,p=t$p,
      model_variant=t$model_variant,criterion_role=tail(strsplit(t$key,"|",fixed=TRUE)[[1L]],1L),
      native_columns_requested=20000L,original_iteration_start=5001L,original_iteration_end=25000L,
      historical_metric_draws=t$n_draws,root_refit_authorized_historical=isTRUE(c$refit_authorized),
      current_refit_authorized=FALSE,stringsAsFactors=FALSE)
  })
  out <- do.call(rbind,rows)
  q(!anyDuplicated(out$task_id)&&length(unique(out$replay_id))==26L,"78 distinct tasks in26 specification groups required")
  for(g in unique(out$replay_id)) {
    r <- out[out$replay_id==g,,drop=FALSE]
    q(nrow(r)==3L&&setequal(r$chain_id,1:3)&&
      nrow(unique(r[c("source_commit","family","p","model_variant","criterion_role")]))==1L,
      "each specification group must preserve its three matching chains")
  }
  d6 <- out$source_commit=="d6bc4c5e47a922ea0255f3ad8d73e58f374827a0"
  q(sum(d6)==3L&&all(out$family[d6]=="normal")&&all(out$p[d6]==.05)&&
    all(out$model_variant[d6]=="qdesn_al_rhs_ns")&&all(out$historical_metric_draws[d6]==1000)&&
    all(out$historical_metric_draws[!d6]==4000)&&
    sum(out$criterion_role=="forecast_mae")==54L&&sum(out$criterion_role=="forecast_check")==24L,
    "frozen source/role cardinalities changed")
  attr(out,"native_rows_requested_not_payload_verified") <- 1560000L
  attr(out,"production_authorized") <- FALSE
  out
}

ind_qnc_extract <- function(payload,case,contract,expected_columns=20000L) {
  q <- ind_qnc_require
  q(is.numeric(expected_columns)&&length(expected_columns)==1L&&is.finite(expected_columns)&&
    expected_columns==20000L,"the frozen20000 native rows are required")
  q(is.list(payload)&&is.list(payload$fits_fc)&&length(payload$fits_fc)==1L&&
    is.list(payload$fits_fc[[1L]]$fit_train)&&is.list(case)&&is.list(contract),
    "exact one-level forecast_objects$fits_fc native container required; no fallback selector")
  entry <- payload$fits_fc[[1L]];fit <- entry$fit_train$fit;cfg <- contract$config
  q(identical(contract$engine,"qdesn")&&identical(contract$task$task_id,case$task_id)&&
    identical(contract$task$replay_id,case$replay_id)&&contract$task$chain_id==case$chain_id&&
    identical(contract$task$model_variant,case$model_variant)&&identical(contract$task$family,case$family)&&
    contract$task$p==case$p&&
    identical(contract$task$refit_authorized,FALSE)&&identical(contract$source_commit,case$source_commit)&&
    identical(contract$package_version,"1.0.0")&&case$chain_id %in% 1:3&&
    case$source_commit %in% c("c72e19f345da88fc1a8175ed30bdde328eab88be",
      "d6bc4c5e47a922ea0255f3ad8d73e58f374827a0")&&
    case$model_variant %in% c("qdesn_al_rhs_ns","qdesn_exal_rhs_ns")&&
    expected_columns==20000L&&cfg$inference$mcmc$n_mcmc==expected_columns&&
    cfg$inference$mcmc$n_burn==5000&&cfg$inference$mcmc$thin==1,
    "case/source/native retention mismatch; historical fitter flags cannot grant a refit")
  q(is.list(fit)&&inherits(fit,"exal_mcmc")&&identical(fit$method,"mcmc")&&
    fit$control$n_mcmc==expected_columns&&fit$control$n_burn==5000&&fit$control$thin==1&&
    fit$p0==case$p,"native static MCMC object and original iteration budget required")
  likelihood <- if(case$model_variant=="qdesn_al_rhs_ns")"al"else"exal"
  q(identical(fit$likelihood_family,likelihood)&&identical(cfg$inference$likelihood_family,likelihood),
    "native likelihood mismatch")
  q(is.list(fit$beta_prior)&&identical(fit$beta_prior$type,"rhs_ns")&&
    identical(cfg$inference$mcmc$priors$beta$type,"rhs_ns"),
    "saved and requested prior family must match; no prior correction is implied")
  beta <- as.matrix(fit$samp.beta);sigma <- as.numeric(fit$samp.sigma);gamma <- as.numeric(fit$samp.gamma)
  q(is.numeric(beta)&&nrow(beta)==expected_columns&&ncol(beta)>=1L&&all(is.finite(beta))&&
    length(sigma)==expected_columns&&all(is.finite(sigma))&&all(sigma>0)&&
    length(gamma)==expected_columns&&all(is.finite(gamma)),"complete paired native beta/sigma/gamma rows required")
  if(likelihood=="al")q(all(gamma==0),"AL cannot inherit estimated exAL shape") else {
    logg <- log(2)+stats::pnorm(-abs(gamma),log.p=TRUE)+.5*gamma^2
    r <- (case$p-as.numeric(gamma<0))/exp(logg)+as.numeric(gamma<0)
    q(all(is.finite(r))&&all(r>0&r<1),"native exAL support violated")
  }
  q(is.matrix(fit$X)&&is.numeric(fit$X)&&ncol(fit$X)==ncol(beta)&&nrow(fit$X)>=1L&&
    all(is.finite(fit$X))&&(is.null(colnames(beta))||is.null(colnames(fit$X))||
      identical(colnames(fit$X),colnames(beta))),
    "native coefficient order and retained training matrix must agree without relabeling")
  keep <- entry$fit_train$meta$keep_idx
  q(is.numeric(keep)&&length(keep)==nrow(fit$X)&&all(is.finite(keep))&&all(keep>=1&keep==as.integer(keep))&&
    !anyDuplicated(keep)&&!is.unsorted(keep),"original native fitting-row map required; no invented indices")
  meta <- entry$fit_train$meta$fit_meta
  structure(list(schema_version="ind_qdesn_native_parameter_block_v1",
    identity=list(task_id=case$task_id,replay_id=case$replay_id,chain_id=case$chain_id,p=case$p,
      likelihood=likelihood,source_commit=case$source_commit,package_version="1.0.0",
      native_rows=expected_columns,chains_per_model=3L,original_burn=5000L,thin=1L,
      parameter_row_identity="original_native_MCMC_row_not_historical_metric_draw",
      prior_type=fit$beta_prior$type,prior_hypers=fit$beta_prior$hypers,
      prior_object_sha256=ind_qnc_hash(fit$beta_prior),request_sha256=ind_qnc_hash(contract)),
    native_column=seq_len(expected_columns),original_iteration=5000L+seq_len(expected_columns),
    beta=beta,sigma=sigma,gamma=gamma,within_model_weight=rep(1/(3*expected_columns),expected_columns),
    training_X_sha256=ind_qnc_hash(fit$X),native_readout_positions=seq_len(ncol(beta)),
    native_readout_names=colnames(beta),native_design_column_names=colnames(fit$X),
    column_mapping="original_native_matrix_position_preserved_no_missing_names_imputed",
    native_keep_idx=as.integer(keep),fit_meta=meta,
    feature_context_status=if(is.list(meta)&&length(meta))"REPLAY_FIXTURE_STILL_REQUIRED"else"BLOCKED_MISSING_NATIVE_FEATURE_METADATA",
    legacy_metric_draw_mapping_inferred=FALSE,parameters_reestimated=FALSE,
    source_identity_authenticated=FALSE,posterior_target_exactness_certified=FALSE,
    feature_replay_authenticated=FALSE,production_authorized=FALSE),
    class=c("ind_qdesn_native_parameter_block","list"))
}

ind_qnc_feature_replay <- function(reference,replay,absolute_tolerance=1e-10,relative_tolerance=1e-10) {
  q <- ind_qnc_require
  fields <- c("schema_version","source_commit","fit_sha256","X_fit","y_fit","keep_idx","fit_meta","origin_states")
  valid <- function(x)is.list(x)&&setequal(names(x),fields)&&
    identical(x$schema_version,"ind_qdesn_feature_values_v1")&&is.matrix(x$X_fit)&&is.numeric(x$X_fit)&&
    all(is.finite(x$X_fit))&&is.numeric(x$y_fit)&&length(x$y_fit)==nrow(x$X_fit)&&all(is.finite(x$y_fit))&&
    is.numeric(x$keep_idx)&&length(x$keep_idx)==nrow(x$X_fit)&&all(is.finite(x$keep_idx))&&
    all(x$keep_idx>=1&x$keep_idx==as.integer(x$keep_idx))&&!anyDuplicated(x$keep_idx)&&!is.unsorted(x$keep_idx)&&
    is.list(x$fit_meta)&&length(x$fit_meta)>0L&&is.list(x$origin_states)&&length(x$origin_states)>0L&&
    !is.null(names(x$origin_states))&&!anyDuplicated(names(x$origin_states))&&all(nzchar(names(x$origin_states)))
  q(valid(reference)&&valid(replay),"BLOCKED_MISSING_AUTHENTIC_FEATURE_FIXTURE_OR_REPLAY")
  q(is.numeric(absolute_tolerance)&&length(absolute_tolerance)==1L&&is.finite(absolute_tolerance)&&
    absolute_tolerance>0&&absolute_tolerance<=1e-10&&is.numeric(relative_tolerance)&&
    length(relative_tolerance)==1L&&is.finite(relative_tolerance)&&relative_tolerance>0&&relative_tolerance<=1e-10,
    "declared native feature parity tolerances cannot exceed1e-10")
  q(identical(reference$source_commit,replay$source_commit)&&identical(reference$fit_sha256,replay$fit_sha256)&&
    is.character(reference$source_commit)&&length(reference$source_commit)==1L&&
    grepl("^[a-f0-9]{40}$",reference$source_commit)&&is.character(reference$fit_sha256)&&
    length(reference$fit_sha256)==1L&&grepl("^[a-f0-9]{64}$",reference$fit_sha256)&&
    identical(reference$fit_meta,replay$fit_meta)&&identical(reference$keep_idx,replay$keep_idx),
    "native source, fixed metadata or row map changed")
  maximum <- 0;values <- 0L
  compare <- function(a,b) {
    q(is.numeric(a)&&is.numeric(b)&&identical(attributes(a),attributes(b))&&length(a)==length(b)&&
      all(is.finite(a))&&all(is.finite(b)),"native feature/state shape/order mismatch")
    d <- abs(as.numeric(a)-as.numeric(b))
    q(all(d<=absolute_tolerance+relative_tolerance*pmax(abs(as.numeric(a)),abs(as.numeric(b)))),
      "native feature/state values differ")
    if(length(d))maximum <<- max(maximum,d)
    values <<- values+length(d)
  }
  compare(reference$X_fit,replay$X_fit);compare(reference$y_fit,replay$y_fit)
  q(identical(names(reference$origin_states),names(replay$origin_states)),"original origin order changed")
  for(key in names(reference$origin_states)) {
    a <- reference$origin_states[[key]];b <- replay$origin_states[[key]]
    q(is.list(a)&&is.list(b)&&setequal(names(a),c("prefix_source_end","layers"))&&
      identical(names(a),names(b))&&is.numeric(a$prefix_source_end)&&length(a$prefix_source_end)==1L&&
      is.finite(a$prefix_source_end)&&a$prefix_source_end>=max(reference$keep_idx)&&
      a$prefix_source_end==as.integer(a$prefix_source_end)&&
      identical(a$prefix_source_end,b$prefix_source_end)&&is.list(a$layers)&&length(a$layers)>0L&&
      identical(names(a$layers),names(b$layers))&&length(a$layers)==length(b$layers),
      "explicit retained observed-prefix origin/layer fixture required")
    for(j in seq_along(a$layers))compare(a$layers[[j]],b$layers[[j]])
  }
  list(schema_version="ind_qdesn_feature_value_comparison_v1",
    status="FEATURE_VALUES_MATCH_REFERENCE_PROVENANCE_NOT_AUTHENTICATED",
    values_compared=values,maximum_absolute_difference=maximum,
    reference_sha256=ind_qnc_hash(reference),replay_sha256=ind_qnc_hash(replay),
    source_identity_authenticated=FALSE,feature_reference_provenance_authenticated=FALSE,
    source_reservoir_reconstructed_here=FALSE,random_draws_generated=0L,
    new_model_fits=0L,production_authorized=FALSE)
}
