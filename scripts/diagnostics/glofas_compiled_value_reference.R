# Optional value-only diagnostic adapter. This is not the production default and
# is outside the closed 20-evaluation nonlinear replay purpose. Authentic use
# needs a new source-pinned purpose, native allocation, and explicit call cap.
gcv_make_value_builder <- function(engine,context,max_evaluations) {
  q<-gnr_require
  q(is.numeric(max_evaluations)&&length(max_evaluations)==1L&&is.finite(max_evaluations)&&
    max_evaluations==floor(max_evaluations)&&max_evaluations>=1L&&max_evaluations<=1e7,
    "explicit finite compiled-value evaluation cap required")
  q(is.list(engine)&&is.environment(engine$env)&&is.environment(engine$audit),
    "fresh authenticated local evaluator environment required")
  # Reuse the strict numeric-context validator, including the historical cutoff,
  # weather-only timeline, supported activations, and two-block readout scope.
  context<-gnr_context(list(future_context=context),engine)
  e<-engine$env;cache<-new.env(parent=emptyenv());audit<-new.env(parent=emptyenv())
  audit$calls<-0L;audit$cache_builds<-0L;audit$cache_reuses<-0L
  audit$path_dependent_values_checked<-0L;audit$static_values_checked<-0L
  audit$context_sha256<-gnr_hash(context);audit$input_contracts<-list()
  metadata_start<-length(engine$audit$metadata)
  value<-function(y) {
    q(audit$calls<max_evaluations,"compiled-value evaluation cap reached")
    H<-nrow(context$latent_data$future_key);gnr_number(y,H)
    audit$calls<-audit$calls+1L;engine$audit$value_calls<-engine$audit$value_calls+1L
    X<-list()
    for(block in c("beta","alpha")) {
      future<-if(block=="beta")as.numeric(y)else as.numeric(context$glofas_future_center_path)-y
      history<-if(block=="beta")context$y_history_full else context$d_history_full
      panel<-if(block=="beta")context$base_panel_full else context$base_panel_disc_full
      previous<-if(exists(block,cache,inherits=FALSE))get(block,cache,inherits=FALSE)else NULL
      # The unchanged production continuation inserts this call's future values
      # into a local copy of the cached static input matrix. No derivative is
      # requested and no saved closure or newly drawn weight is used.
      cont<-e$app_qdesn_continue_latent_path(qfit=context[[paste0("qfit_",block)]],
        y_history=history,y_future=future,future_dates=context$latent_data$future_key$target_date,
        covariate_timeline=context$covariate_timeline,return_jacobian=FALSE,
        active_jacobian=FALSE,compiled_inputs=previous,compile_inputs=TRUE,
        verify_compiled_hash=FALSE)
      contract<-cont$compiled_input_contract
      q(is.list(contract)&&identical(contract$schema_version,"qdesn_compiled_future_inputs_v1")&&
        is.null(cont$J_future_core),"value-only continuation returned an unexpected contract or Jacobian")
      if(is.null(previous)) {
        # The contract was just created by pinned local code, including its hash.
        # It remains private and is never replaced by caller-supplied metadata.
        assign(block,contract,cache);audit$cache_builds<-audit$cache_builds+1L
        audit$input_contracts[[block]]<-list(production_contract_hash=contract$contract_hash,
          numeric_contract_sha256=gnr_hash(contract),columns_sha256=gnr_hash(contract$columns),
          dimensions=dim(contract$static_values),future_index_sha256=gnr_hash(contract$future_index))
      } else {
        q(identical(contract,previous),"production continuation mutated the private static input contract")
        audit$cache_reuses<-audit$cache_reuses+1L
      }
      dynamic<-contract$future_index>0L;fixed<-!dynamic
      q(identical(dim(cont$input_lag_matrix),dim(contract$static_values))&&
        all(cont$input_lag_matrix[dynamic]==future[contract$future_index[dynamic]])&&
        all(cont$input_lag_matrix[fixed]==contract$static_values[fixed]),
        "cached path-dependent or static input values were not correctly refreshed")
      audit$path_dependent_values_checked<-audit$path_dependent_values_checked+sum(dynamic)
      audit$static_values_checked<-audit$static_values_checked+sum(fixed)
      full_panel<-e$app_latent_path_combined_panel(panel,context$latent_data,future)
      assembled<-e$app_build_readout_feature_matrix(reservoir_X=cont$X_future_core,panel=full_panel,
        cfg=context[[paste0("cfg_",block)]],output_anchor_dates=context$latent_data$future_key$target_date,
        covariate_target_dates=context$latent_data$future_key$target_date,
        horizon=context$latent_data$future_key$horizon,feature_strategy=context$feature_strategy,
        horizon_scale=context$horizon_scale,feature_meta=context[[paste0("feature_meta_",block)]],fit_scale=FALSE)
      X[[block]]<-assembled$X
    }
    H_y<-cbind(X$beta,matrix(0,nrow=nrow(X$beta),ncol=ncol(X$alpha)))
    H_g_key<-cbind(X$beta,X$alpha)
    colnames(H_y)<-colnames(H_g_key)<-c(paste0("beta__",colnames(X$beta)),paste0("alpha__",colnames(X$alpha)))
    list(X_beta_future=X$beta,X_alpha_future=X$alpha,H_y=H_y,H_g_key=H_g_key)
  }
  attr(value,"gcv_diagnostics")<-function()list(
    schema_version="glofas_compiled_value_diagnostics_v1",mode="optional_newly_admitted_compiled_value_only",
    calls=audit$calls,max_evaluations=max_evaluations,cache_builds=audit$cache_builds,
    cache_reuses=audit$cache_reuses,path_dependent_values_checked=audit$path_dependent_values_checked,
    static_values_checked=audit$static_values_checked,context_sha256=audit$context_sha256,
    input_contracts=audit$input_contracts,generated_metadata_serializations=length(engine$audit$metadata)-metadata_start,
    saved_callback_calls=0L,original_file_reads=0L,random_weight_generations=0L,
    coordinate_updates=0L,future_truth_read=FALSE,production_default_changed=FALSE)
  value
}
gcv_diagnostics <- function(builder) {
  f<-attr(builder,"gcv_diagnostics",exact=TRUE)
  gnr_require(is.function(builder)&&is.function(f),"fresh compiled-value builder required")
  f()
}
gcv_performance_pilot <- function(builder,A,B,remaining_seconds,remaining_evaluations,safety_factor=2) {
  q<-gnr_require;gnr_number(A);gnr_number(B,length(A))
  q(is.numeric(remaining_seconds)&&length(remaining_seconds)==1L&&is.finite(remaining_seconds)&&remaining_seconds>0&&
    is.numeric(remaining_evaluations)&&length(remaining_evaluations)==1L&&is.finite(remaining_evaluations)&&
    remaining_evaluations==floor(remaining_evaluations)&&remaining_evaluations>=0&&
    is.numeric(safety_factor)&&length(safety_factor)==1L&&is.finite(safety_factor)&&safety_factor>=2,
    "finite separately admitted pilot time/evaluation allowance required")
  before<-gcv_diagnostics(builder)
  q(before$calls==0L&&before$max_evaluations>=3L+remaining_evaluations,
    "pilot requires a fresh builder and allowance for all three A/B/A calls plus later evaluations")
  rng<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  paths<-list(A,B,A);values<-list();latency<-numeric(3L);start<-proc.time()[["elapsed"]]
  for(i in 1:3) {
    q(proc.time()[["elapsed"]]-start<remaining_seconds,"compiled-value pilot time allowance exhausted")
    t<-proc.time()[["elapsed"]];values[[i]]<-builder(paths[[i]])
    latency[i]<-proc.time()[["elapsed"]]-t
    if(i==1L)q(safety_factor*latency[i]*(2L+remaining_evaluations)<
      remaining_seconds-(proc.time()[["elapsed"]]-start),
      "compiled-value first-call pilot projects beyond the separate admission")
  }
  diff<-gnr_compare(values[[1L]],values[[3L]],FALSE)
  rng_after<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  after<-gcv_diagnostics(builder)
  q(all(diff<=1e-10)&&identical(rng,rng_after)&&after$calls-before$calls==3L,
    "compiled-value pilot A/B/A, RNG or call-count mismatch")
  conservative<-safety_factor*max(latency)*remaining_evaluations
  list(schema_version="glofas_compiled_value_pilot_v1",status="MEASURED_PILOT_NOT_PRODUCTION_LAUNCH_APPROVAL",
    calls=3L,paths=c("A","B","A"),latency_seconds=latency,
    first_compile_seconds=latency[1L],warm_max_seconds=max(latency[-1L]),
    A_B_A_max_abs_difference=max(diff),remaining_evaluations=remaining_evaluations,
    conservative_remaining_seconds=conservative,
    remaining_budget_sufficient=conservative<remaining_seconds-(proc.time()[["elapsed"]]-start),
    RNG_unchanged=TRUE,diagnostics=after,original_file_reads=0L,saved_callback_calls=0L,
    future_truth_read=FALSE,coordinate_updates=0L,production_launch_authorized=FALSE)
}
