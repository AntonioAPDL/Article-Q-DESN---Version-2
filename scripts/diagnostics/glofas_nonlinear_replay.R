# Diagnostic evaluators of the frozen GloFAS feature map, not a fitting backend.
# Callers must authenticate inputs/source and provide a separate native budget.
gnr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS nonlinear replay: ", why), call. = FALSE)
  invisible(TRUE)
}
gnr_production_sources <- function() c("application/R/00_packages.R",
  "application/R/model_contract.R", "application/R/feature_contract.R",
  "application/R/covariate_design.R", "application/R/latent_path_design.R",
  "application/R/fit_qdesn_latent_path.R", "application/R/latent_path_vb_al.R")
gnr_plain <- function(x, depth=0L) {
  q<-gnr_require
  q(depth<=20L&&!is.function(x)&&!is.environment(x)&&!isS4(x)&&!is.language(x)&&
    !typeof(x)%in%c("externalptr","weakref","promise"),"callback or opaque value in selected numeric context")
  classes<-c("Date","data.frame","matrix","array","factor","qdesn_fit","glofas_latent_path_data")
  q(!is.object(x)||all(class(x)%in%classes),"unsupported selected-context class")
  if(is.list(x)) {
    q(is.null(names(x))||(!anyDuplicated(names(x))&&all(nzchar(names(x)))),"duplicate selected-context fields")
    for(v in x)gnr_plain(v,depth+1L)
  }
  for(v in attributes(x))gnr_plain(v,depth+1L)
  invisible(TRUE)
}
gnr_number <- function(x,n=NULL) {
  gnr_require(is.numeric(x)&&!is.complex(x)&&all(is.finite(x))&&
    (is.null(n)||length(x)==n),"finite numeric value/dimension required")
  x
}
gnr_hash <- function(x) digest::digest(x,algo="sha256",serialize=TRUE)
gnr_maxdiff <- function(a,b) {
  gnr_require(is.numeric(a)&&is.numeric(b)&&identical(dim(a),dim(b))&&length(a)==length(b)&&
    all(is.finite(a))&&all(is.finite(b)),"comparison dimensions or finite values differ")
  if(length(a))max(abs(a-b))else 0
}
gnr_engine <- function(root,scratch,budget) {
  q<-gnr_require;root<-normalizePath(root,mustWork=TRUE);scratch<-normalizePath(scratch,mustWork=TRUE)
  q(dir.exists(scratch)&&!length(list.files(scratch,all.files=TRUE,no..=TRUE))&&
    is.list(budget)&&setequal(names(budget),c("max_files","max_file_bytes","max_total_bytes"))&&
    all(vapply(budget,function(x)is.numeric(x)&&length(x)==1L&&is.finite(x)&&x==floor(x)&&x>0,logical(1L)))&&
    budget$max_files<=64L&&budget$max_file_bytes<=4*1024^2&&budget$max_total_bytes<=64*1024^2,
    "empty owned metadata scratch and finite serialization allowance required")
  e<-new.env(parent=baseenv());audit<-new.env(parent=emptyenv())
  audit$metadata<-list();audit$forbidden_calls<-0L;audit$factory_calls<-0L;audit$value_calls<-0L
  for(nm in c("head","tail","modifyList","read.csv","write.csv","capture.output"))
    assign(nm,get(nm,envir=asNamespace("utils")),e)
  e$setNames<-stats::setNames
  for(rel in gnr_production_sources())sys.source(file.path(root,rel),envir=e,keep.source=FALSE)
  denied<-function(...) {audit$forbidden_calls<-audit$forbidden_calls+1L
    stop("GloFAS nonlinear replay: forbidden inference, engine, original read, random-weight or file operation",call.=FALSE)}
  # A future continuation can only use retained numeric parameters and local source.
  entry<-c("readRDS","load","source","sys.source","eval","parse","system","system2",
    "runif","rnorm","rbinom","sample","sample.int","set.seed","app_qdesn_engine_function",
    "app_qdesn_engine_env","app_qdesn_require_engine","app_qdesn_generate_article_reservoir",
    "app_qdesn_sparse_weights","app_qdesn_make_reducer","app_qdesn_roll_article_reservoir",
    "app_qdesn_build_article_design_full","app_latent_path_feature_block","app_build_qdesn_design_full",
    "app_fit_qdesn_latent_path","app_vb_latent_path_al","app_vb_latent_path_exal",
    "app_latent_reference_feature_cache_read","app_latent_reference_feature_cache_write",
    "app_latent_reference_feature_cache_get_or_build","app_read_table","app_read_yaml","app_read_csv")
  for(nm in entry)assign(nm,denied,e)
  owned<-function(path) {
    link<-Sys.readlink(path)
    q(is.character(path)&&length(path)==1L&&identical(dirname(path),scratch)&&
      !grepl("(^|/)\\.\\.(/|$)",path)&&(is.na(link)||!nzchar(link)),"metadata escaped owned scratch")
    invisible(TRUE)
  }
  e$tempfile<-function(pattern="file",tmpdir=tempdir(),fileext="") {
    q(is.character(pattern)&&length(pattern)==1L&&
      grepl("^(qdesn_compiled_future_inputs_|latent_compiled_future_)",pattern)&&
      identical(fileext,".rds"),"unexpected generated metadata purpose")
    base::tempfile(pattern,tmpdir=scratch,fileext=fileext)
  }
  e$saveRDS<-function(object,file,ascii=FALSE,version=NULL,compress=TRUE,refhook=NULL) {
    owned(file);gnr_plain(object)
    q(is.null(refhook)&&identical(version,2L)&&!file.exists(file)&&
      length(audit$metadata)<budget$max_files&&as.numeric(object.size(object))<=budget$max_file_bytes,
      "metadata serialization pre-write cap exceeded")
    base::saveRDS(object,file,ascii=ascii,version=version,compress=compress)
    size<-as.numeric(file.info(file)$size)
    used<-sum(vapply(audit$metadata,function(x)x$size_bytes,numeric(1L)))
    q(is.finite(size)&&size<=budget$max_file_bytes&&used+size<=budget$max_total_bytes,
      "metadata serialization byte allowance exceeded")
    audit$metadata[[length(audit$metadata)+1L]]<-list(basename=basename(file),size_bytes=size,
      sha256=unname(tools::sha256sum(file)),role="generated_contract_hash_metadata_not_original_read")
    invisible(NULL)
  }
  e$app_sha256_file<-function(path) {
    owned(path)
    q(file.exists(path)&&basename(path)%in%vapply(audit$metadata,function(x)x$basename,character(1L)),
      "only admitted generated metadata can be hashed by evaluator")
    unname(tools::sha256sum(path))
  }
  e$unlink<-function(x,recursive=FALSE,force=FALSE,expand=TRUE) {
    q(!isTRUE(recursive)&&length(x)==1L,"recursive metadata removal forbidden");owned(x)
    base::unlink(x,recursive=FALSE,force=force,expand=FALSE)
  }
  list(env=e,audit=audit,scratch=scratch,budget=budget)
}
gnr_context <- function(design,engine) {
  q<-gnr_require;e<-engine$env;c<-design$future_context
  q(is.list(c)&&isTRUE(c$two_block_design)&&identical(c$discrepancy_input_stream,"discrepancy")&&
    identical(c$discrepancy_transition_strategy,"recursive_level"),"two-block recursive-level discrepancy context required")
  fields<-c("cfg","cfg_beta","cfg_alpha","latent_data","y_history_full","d_history_full",
    "base_panel_full","base_panel_disc_full","feature_meta_beta","feature_meta_alpha",
    "horizon_scale","feature_strategy","discrepancy_transition_strategy","discrepancy_input_stream",
    "runtime_optimization","covariate_timeline","two_block_design","glofas_future_center_path",
    "future_discrepancy_convention")
  out<-c[intersect(fields,names(c))]
  # Config parsing is also executable code: reject saved callables before any
  # production helper can inspect this selected value-only context.
  gnr_plain(out)
  out$cfg_beta<-if(is.null(c$cfg_beta))e$app_qdesn_block_config(c$cfg,"reference")else c$cfg_beta
  out$cfg_alpha<-if(is.null(c$cfg_alpha))e$app_qdesn_block_config(c$cfg,"discrepancy")else c$cfg_alpha
  out$feature_meta_beta<-if(is.null(c$feature_meta_beta))c$feature_meta else c$feature_meta_beta
  out$feature_meta_alpha<-if(is.null(c$feature_meta_alpha))c$feature_meta else c$feature_meta_alpha
  L<-c$latent_data;dates<-as.Date(L$future_key$target_date);origin<-as.Date(L$origin_date)
  H<-length(dates)
  q(H>=2L&&H<=28L&&length(origin)==1L&&!is.na(origin)&&identical(as.numeric(dates),
    as.numeric(origin+seq_len(H)))&&identical(as.integer(L$future_key$horizon),seq_len(H)),
    "contiguous horizon-aligned future dates required")
  ens<-L$g_ensemble
  q(is.data.frame(ens)&&nrow(ens)==H*51L&&all(as.numeric(ens$ensemble_weight)==1)&&
    all(is.finite(ens$g_transformed))&&all(as.Date(ens$origin_date)==origin)&&
    all(as.Date(ens$target_date)>origin),"all 51 finite issued members with unit weights required")
  for(nm in intersect(c("y","y_raw","y_transformed","y_reference","usgs","usgs_raw","usgs_transformed"),names(ens)))
    q(!any(is.finite(as.numeric(ens[[nm]]))),"future USGS not physically excluded from issued context")
  for(h in seq_len(H))q(sum(as.integer(ens$horizon)==h & as.Date(ens$target_date)==dates[h])==51L&&
    !anyDuplicated(as.character(ens$member[as.integer(ens$horizon)==h])),"issued member/date ordering invalid")
  q(is.null(L$y_future_oracle),"future truth sidecar is forbidden")
  out$latent_data<-L[c("origin_date","cutoff_id","future_key","g_ensemble")]
  out$latent_data$g_ensemble<-ens[,intersect(c("origin_date","target_date","horizon","member",
    "g_transformed","ensemble_weight"),names(ens)),drop=FALSE]
  gnr_number(c$glofas_future_center_path,H)
  q(max(abs(as.numeric(c$glofas_future_center_path)-vapply(seq_len(H),function(h)
    mean(ens$g_transformed[as.integer(ens$horizon)==h]),numeric(1L))))<=1e-12,
    "issued center is not the retained unit-member mean")
  for(block in c("beta","alpha")) {
    fit<-c[[paste0("qfit_",block)]]
    if(is.null(fit))fit<-c$qfit
    q(is.list(fit)&&is.list(fit$reservoir)&&is.list(fit$meta)&&is.list(fit$states$H_all),
      "retained numeric block reservoir/meta/states required")
    r<-fit$reservoir
    q(all(vapply(r[c("act_f","act_k")],function(x)is.character(x)&&length(x)==1L&&
      x%in%c("tanh","relu","identity"),logical(1L))),"supported string activation required, not saved function")
    D<-as.integer(r$D);q(length(D)==1L&&D>=1L&&length(fit$states$H_all)==D&&
      length(r$W)==D&&length(r$Win)==D,"retained layer dimensions differ")
    for(d in seq_len(D)) {
      W<-gnr_number(r$W[[d]]);Win<-gnr_number(r$Win[[d]])
      states<-gnr_number(fit$states$H_all[[d]])
      q(is.matrix(W)&&nrow(W)==ncol(W)&&is.matrix(Win)&&nrow(Win)==nrow(W)&&
        is.matrix(states)&&nrow(states)>0L&&ncol(states)==nrow(W),"retained weight/state shape mismatch")
    }
    meta<-fit$meta;spec<-meta$reservoir_input_spec
    gnr_plain(r);gnr_plain(meta[intersect(c("reservoir_input_spec","history_dates","m_input",
      "standardize_inputs","input_bound","win_scale_global","win_scale_bias","win_scale_lags",
      "lag_center","lag_scale"),names(meta))])
    q(is.list(spec)&&isTRUE(spec$uses_covariates)&&!isTRUE(spec$uses_auxiliary_lags)&&
      !isTRUE(spec$uses_dlm_components)&&length(spec$columns)==spec$m_input&&
      all(spec$output_lags>=1L)&&ncol(r$Win[[1L]])==spec$m_input+1L,
      "authentic covariate-aware, strictly lagged local continuation required")
    hist<-if(block=="beta")out$y_history_full else out$d_history_full
    gnr_number(hist)
    q(length(meta$history_dates)==length(hist)&&!anyNA(as.Date(meta$history_dates))&&
      max(as.Date(meta$history_dates))==origin&&all(as.Date(meta$history_dates)<=origin),
      "retained historical state/date initialization does not end at cutoff")
    # Only fields consumed by the authenticated continuation, not saved closures.
    mfields<-c("reservoir_input_spec","history_dates","m_input","standardize_inputs","input_bound",
      "win_scale_global","win_scale_bias","win_scale_lags","lag_center","lag_scale",
      "reservoir_input_columns","reservoir_covariates_enabled","reservoir_covariate_columns")
    out[[paste0("qfit_",block)]]<-list(reservoir=r,meta=meta[intersect(mfields,names(meta))],
      states=list(H_all=lapply(fit$states$H_all,function(M)M[nrow(M),,drop=FALSE])))
    cfg<-out[[paste0("cfg_",block)]];ct<-e$app_feature_contract(cfg)
    q(isTRUE(ct$readout$add_intercept)&&isTRUE(ct$readout$include_reservoir_state)&&
      !isTRUE(ct$readout$include_input_block)&&!length(ct$readout$reservoir_state_lags)&&
      !(isTRUE(ct$readout$include_horizon_scaled)&&identical(out$feature_strategy,"horizon_indexed_origin_state")),
      "initial replay is limited to the retained intercept/reservoir-only readout")
  }
  for(p in c("base_panel_full","base_panel_disc_full"))q(is.data.frame(out[[p]])&&
    all(as.Date(out[[p]]$target_date)<=origin)&&all(is.finite(out[[p]]$y_transformed)),
    "base panel contains nonhistorical responses")
  q(is.data.frame(out$covariate_timeline)&&all(c("date","ppt","soil")%in%names(out$covariate_timeline))&&
    !any(tolower(names(out$covariate_timeline))%in%c("y","y_raw","y_transformed","y_reference",
      "usgs","usgs_raw","usgs_transformed"))&&
    !any(grepl("usgs|truth|y_reference",names(out$covariate_timeline),ignore.case=TRUE)),
    "covariate-only retained timeline required")
  gnr_plain(out);out
}
gnr_factory <- function(engine,context,mode) {
  gnr_require(mode%in%c("uncompiled_full","compiled_full","compiled_active"),"unknown evaluator mode")
  ctx<-context;ctx$runtime_optimization<-list(compiled_future_contract=mode!="uncompiled_full",
    active_future_jacobian=mode=="compiled_active")
  f<-engine$env$app_make_latent_path_future_builder(ctx)
  function(y) {engine$audit$factory_calls<-engine$audit$factory_calls+1L;f(y)}
}
gnr_make_value_builder <- function(engine,context) {
  # Same retained-state production continuation and full readout assembler as the
  # factory, without analytical Jacobians or any compiled/readout cache. Its
  # equality to that factory must pass before its finite differences are used.
  e<-engine$env
  function(y) {
    engine$audit$value_calls<-engine$audit$value_calls+1L;gnr_number(y,nrow(context$latent_data$future_key))
    X<-list()
    for(block in c("beta","alpha")) {
      future<-if(block=="beta")as.numeric(y)else as.numeric(context$glofas_future_center_path)-y
      history<-if(block=="beta")context$y_history_full else context$d_history_full
      panel<-if(block=="beta")context$base_panel_full else context$base_panel_disc_full
      cont<-e$app_qdesn_continue_latent_path(qfit=context[[paste0("qfit_",block)]],
        y_history=history,y_future=future,future_dates=context$latent_data$future_key$target_date,
        covariate_timeline=context$covariate_timeline,return_jacobian=FALSE,
        active_jacobian=FALSE,compiled_inputs=NULL,compile_inputs=FALSE)
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
}
gnr_location_callback <- function(value_builder,theta,known_baseline=NULL) {
  gnr_number(theta);force(value_builder);force(theta);force(known_baseline)
  function(y) {
    v<-value_builder(y)
    gnr_require(length(theta)==ncol(v$H_y),"fixed coefficient/feature order dimension mismatch")
    baseline<-if(is.null(known_baseline))rep(0,nrow(v$H_y))else gnr_number(known_baseline,nrow(v$H_y))
    reference<-as.numeric(v$H_y%*%theta)
    list(reference_location=reference,ensemble_location=as.numeric(v$H_g_key%*%theta)+baseline)
  }
}
gnr_location_jacobian_callback <- function(full_builder,theta,known_baseline=NULL) {
  gnr_number(theta);force(full_builder);force(theta);force(known_baseline)
  function(y) {
    v<-full_builder(y);H<-nrow(v$H_y)
    baseline<-if(is.null(known_baseline))rep(0,H)else gnr_number(known_baseline,H)
    q<-gnr_require;q(length(theta)==ncol(v$H_y),"fixed coefficient/feature dimension mismatch")
    J<-function(name)do.call(rbind,lapply(v[[name]],function(M)as.numeric(crossprod(theta,M))))
    jr<-J("J_y");jg<-J("J_g_key")
    q(identical(dim(jr),c(H,H))&&identical(dim(jg),c(H,H))&&
      max(abs(jr[upper.tri(jr,diag=TRUE)]))<=1e-12&&
      max(abs(jg[upper.tri(jg,diag=TRUE)]))<=1e-12,"location Jacobian must be strictly causal")
    list(reference_location=as.numeric(v$H_y%*%theta),ensemble_location=as.numeric(v$H_g_key%*%theta)+baseline,
      reference_jacobian=jr,ensemble_jacobian=jg)
  }
}
gnr_compare <- function(a,b,jacobian=TRUE) {
  out<-vapply(c("X_beta_future","X_alpha_future","H_y","H_g_key"),function(nm) {
    gnr_require(identical(colnames(a[[nm]]),colnames(b[[nm]])),"feature column order differs")
    gnr_maxdiff(a[[nm]],b[[nm]])
  },numeric(1L))
  if(jacobian) {
    for(nm in c("g_future_index","z_g","weight_g"))
      out<-c(out,setNames(gnr_maxdiff(a[[nm]],b[[nm]]),nm))
    for(nm in c("row_info_y","row_info_g_key","row_info_g"))
      gnr_require(identical(a[[nm]],b[[nm]]),"issued member/date/weight rows differ across evaluator modes")
    for(nm in c("J_y","J_g_key")) {
      gnr_require(length(a[[nm]])==length(b[[nm]]),"Jacobian collection length differs")
      out<-c(out,setNames(max(vapply(seq_along(a[[nm]]),function(h)
        gnr_maxdiff(a[[nm]][[h]],b[[nm]][[h]]),numeric(1L))),nm))
    }
  }
  out
}
gnr_identities <- function(context) {
  rows<-list();state_rows<-list();blocks<-list()
  for(block in c("beta","alpha")) {
    fit<-context[[paste0("qfit_",block)]];meta<-fit$meta;r<-fit$reservoir;spec<-meta$reservoir_input_spec
    n<-spec$m_input
    expanded<-function(x,default) {if(is.null(x))x<-default;if(length(x)==1L)x<-rep(x,n);gnr_number(x,n)}
    rows[[block]]<-data.frame(block=block,input_column=spec$columns,
      lag_center=expanded(meta$lag_center,0),lag_scale=expanded(meta$lag_scale,1),
      win_scale_lags=expanded(meta$win_scale_lags,1),stringsAsFactors=FALSE)
    states<-do.call(c,lapply(fit$states$H_all,as.numeric))
    state_rows[[block]]<-data.frame(block=block,state_index=seq_along(states),last_historical_state=states)
    blocks[[block]]<-list(history_last_date=as.character(tail(as.Date(meta$history_dates),1L)),
      history_length=length(meta$history_dates),historical_values_sha256=gnr_hash(if(block=="beta")context$y_history_full else context$d_history_full),
      depth=r$D,layer_widths=vapply(r$W,nrow,integer(1L)),input_dimension=n,
      W_sha256=gnr_hash(r$W),Win_sha256=gnr_hash(r$Win),reducers_sha256=gnr_hash(r$Q),
      last_states_sha256=gnr_hash(fit$states$H_all),input_spec_sha256=gnr_hash(spec),
      feature_metadata_sha256=gnr_hash(context[[paste0("feature_meta_",block)]]),
      config_sha256=gnr_hash(context[[paste0("cfg_",block)]]),
      actual_meta=list(win_scale_global=meta$win_scale_global,win_scale_bias=meta$win_scale_bias,
        standardize_inputs=meta$standardize_inputs,input_bound=meta$input_bound,alpha=r$alpha,
        act_f=r$act_f,act_k=r$act_k),scaler_sha256=gnr_hash(rows[[block]]))
  }
  list(blocks=blocks,input_scalers=do.call(rbind,rows),initial_states=do.call(rbind,state_rows),
    context_sha256=gnr_hash(context),covariate_timeline_sha256=gnr_hash(context$covariate_timeline),
    issued_member_rows_sha256=gnr_hash(context$latent_data$g_ensemble),
    actual_runtime_optimization=context$runtime_optimization,
    discrepancy_input_stream=context$discrepancy_input_stream,
    discrepancy_transition_strategy=context$discrepancy_transition_strategy)
}
gnr_pilot_projection <- function(first_seconds,remaining_seconds,control) {
  q<-gnr_require
  q(is.numeric(first_seconds)&&length(first_seconds)==1L&&is.finite(first_seconds)&&first_seconds>=0&&
    is.numeric(remaining_seconds)&&length(remaining_seconds)==1L&&is.finite(remaining_seconds)&&
    control$max_evaluations==20L&&control$pilot_safety_factor>=2&&control$minimum_tail_seconds>=30,
    "finite conservative pilot inputs required")
  # Charge every remaining evaluation, including the eight value-only calls,
  # at the first full-factory latency. Native limits remain authoritative.
  remaining_calls<-control$max_evaluations-1L
  projected<-control$pilot_safety_factor*first_seconds*remaining_calls+control$minimum_tail_seconds
  q(projected<remaining_seconds,"pilot projects beyond admitted time; stop without additional calls")
  list(remaining_calls=remaining_calls,latency_per_call_seconds=first_seconds,
    safety_factor=control$pilot_safety_factor,projected_remaining_seconds=projected,
    admitted_remaining_seconds=remaining_seconds,
    value_call_cost_assumption="each_remaining_value_call_charged_as_full_first_factory_call")
}
gnr_replay <- function(engine,context,core,control) {
  q<-gnr_require
  keys<-c("max_evaluations","factory_evaluations","value_evaluations","direction_steps",
    "perturbation","parity_tolerance","fd_tolerance","pilot_safety_factor","minimum_tail_seconds",
    "remaining_seconds")
  q(is.list(control)&&setequal(names(control),keys)&&control$max_evaluations==20L&&
    control$factory_evaluations==12L&&control$value_evaluations==8L&&
    identical(as.numeric(control$direction_steps),c(1e-4,3e-5,1e-5))&&
    control$perturbation==.01&&control$parity_tolerance==1e-10&&control$fd_tolerance==1e-6&&
    control$pilot_safety_factor>=2&&control$minimum_tail_seconds>=30&&
    is.finite(control$remaining_seconds)&&control$remaining_seconds>control$minimum_tail_seconds,
    "exact bounded 12-factory/8-value directional pilot required")
  A<-as.numeric(gnr_number(core$variational_state$y_future_mean,nrow(context$latent_data$future_key)))
  lin<-core$variational_state$future_linearization;H<-length(A)
  q(is.list(lin)&&identical(lin$strategy,"first_order_delta")&&gnr_maxdiff(as.numeric(lin$y_mean),A)==0,
    "retained first-order linearization at the exact path mean required")
  direction<-rep(c(1,-1),length.out=H)/sqrt(H);B<-A+control$perturbation*direction
  rng<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  context_hash<-gnr_hash(context);start<-proc.time()[["elapsed"]];counts0<-engine$audit$factory_calls+engine$audit$value_calls
  comparisons<-list();add<-function(label,metrics) {
    comparisons[[length(comparisons)+1L]]<<-data.frame(comparison=label,quantity=names(metrics),
      maximum_absolute_difference=as.numeric(metrics),tolerance=control$parity_tolerance,
      pass=as.numeric(metrics)<=control$parity_tolerance,stringsAsFactors=FALSE)
  }
  deadline<-function()q(proc.time()[["elapsed"]]-start<control$remaining_seconds-control$minimum_tail_seconds&&
    engine$audit$factory_calls+engine$audit$value_calls-counts0<control$max_evaluations,
    "replay call/time cap reached; no expansion authorized")
  refs<-list();modes<-c("compiled_active","compiled_full","uncompiled_full")
  for(mode in modes) {
    f<-gnr_factory(engine,context,mode);deadline();t<-proc.time()[["elapsed"]];first<-f(A)
    if(mode==modes[1L]) {
      pilot<-proc.time()[["elapsed"]]-t
      pilot_projection<-gnr_pilot_projection(pilot,
        control$remaining_seconds-(proc.time()[["elapsed"]]-start),control)
    }
    deadline();middle<-f(B);deadline();last<-f(A)
    add(paste0(mode,"_A_B_A"),gnr_compare(first,last))
    deadline();fresh<-gnr_factory(engine,context,mode)(A)
    add(paste0(mode,"_independent_fresh_A"),gnr_compare(first,fresh))
    refs[[mode]]<-first
    if(mode==modes[1L])ref_B<-middle
  }
  ref<-refs[[1L]]
  for(mode in modes[-1L])add(paste0(mode,"_versus_active"),gnr_compare(ref,refs[[mode]]))
  retained<-c(X_beta=gnr_maxdiff(ref$X_beta_future,lin$X_beta_future),
    X_alpha=gnr_maxdiff(ref$X_alpha_future,lin$X_alpha_future),
    J_beta=max(vapply(seq_len(H),function(h)gnr_maxdiff(ref$J_y[[h]][seq_len(ncol(ref$X_beta_future)),,drop=FALSE],
      lin$J_beta[[h]]),numeric(1L))),
    J_alpha=max(vapply(seq_len(H),function(h)gnr_maxdiff(tail(ref$J_g_key[[h]],ncol(ref$X_alpha_future)),
      lin$J_alpha[[h]]),numeric(1L))))
  add("fresh_A_versus_retained_numeric_linearization",retained)
  parity<-do.call(rbind,comparisons)
  # Preserve failures in returned output. Do not qualify a value-only oracle if
  # production/retained branches disagree.
  value<-gnr_make_value_builder(engine,context)
  deadline();valueA<-value(A);deadline();valueB<-value(B)
  add("value_only_A_versus_factory",gnr_compare(ref,valueA,FALSE))
  add("value_only_B_versus_factory",gnr_compare(ref_B,valueB,FALSE))
  parity<-do.call(rbind,comparisons)
  q(all(parity$pass),"feature/Jacobian/cache parity failed before finite-difference oracle admission")
  fdrows<-list()
  for(step in control$direction_steps) {
    deadline();plus<-value(A+step*direction);deadline();minus<-value(A-step*direction)
    for(block in c("beta","alpha")) {
      J<-if(block=="beta")lapply(ref$J_y,function(M)M[seq_len(ncol(ref$X_beta_future)),,drop=FALSE])else
        lapply(ref$J_g_key,function(M)tail(M,ncol(ref$X_alpha_future)))
      field<-paste0("X_",block,"_future")
      for(h in seq_len(H)) {
        analytic<-as.numeric(J[[h]]%*%direction)
        finite<-as.numeric((plus[[field]][h,]-minus[[field]][h,])/(2*step))
        error<-max(abs(finite-analytic)/(1+pmax(abs(finite),abs(analytic))))
        fdrows[[length(fdrows)+1L]]<-data.frame(block=block,horizon=h,step=step,
          analytic_max_abs=max(abs(analytic)),finite_difference_max_abs=max(abs(finite)),
          hybrid_max_error=error,tolerance=control$fd_tolerance,pass=error<=control$fd_tolerance)
      }
    }
  }
  fd<-do.call(rbind,fdrows)
  causal<-do.call(rbind,lapply(c("J_y","J_g_key"),function(name)do.call(rbind,lapply(seq_len(H),function(h)
    data.frame(component=name,horizon=h,forbidden_current_future_max_abs=max(abs(ref[[name]][[h]][,h:H,drop=FALSE])),
      pass=max(abs(ref[[name]][[h]][,h:H,drop=FALSE]))<=1e-12)))))
  rng_after<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  q(identical(rng,rng_after)&&identical(context_hash,gnr_hash(context))&&engine$audit$forbidden_calls==0L,
    "RNG/context mutation or prohibited evaluator call detected")
  q(engine$audit$factory_calls==12L&&engine$audit$value_calls==8L,"exact admitted evaluation accounting differs")
  q(!length(list.files(engine$scratch,all.files=TRUE,no..=TRUE)),"generated metadata file not closed")
  list(status=if(all(fd$pass)&&all(causal$pass))"PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY"else
    "FAIL_FEATURE_DERIVATIVE_OR_CAUSALITY",parity=parity,directional_finite_differences=fd,causality=causal,
    feature_columns=colnames(ref$H_y),feature_columns_sha256=gnr_hash(colnames(ref$H_y)),
    issued_identity=list(index_sha256=gnr_hash(ref$g_future_index),values_sha256=gnr_hash(ref$z_g),
      weights_sha256=gnr_hash(ref$weight_g),all_weights_one=all(ref$weight_g==1),
      member_rows_sha256=gnr_hash(ref$row_info_g)),
    pilot_seconds=pilot,pilot_projection=pilot_projection,elapsed_seconds=proc.time()[["elapsed"]]-start,
    factory_evaluations=engine$audit$factory_calls,value_evaluations=engine$audit$value_calls,
    metadata_serializations=engine$audit$metadata,forbidden_calls=engine$audit$forbidden_calls,
    RNG_unchanged=identical(rng,rng_after),context_unchanged=TRUE,saved_callback_calls=0L,
    applied_updates=0L,original_file_reads=0L,future_truth_read=FALSE,
    posterior_approximation_accuracy_qualified=FALSE,production_launch_authorized=FALSE)
}
