# Pure closeout algebra. This file never fits, samples, reads truth or publishes.
gsc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS same-family closeout: ", why), call.=FALSE)
  invisible(TRUE)
}
gsc_tau <- function() c(.05,.20,.35,.50,.65,.80,.95)
gsc_families <- function() c("Raw GloFAS","Normal Ridge","Normal RHS",
  "Independent AL","Independent exAL","MQ AL","MQ exAL")
gsc_tasks <- function() c(paste0("gft-al-p",c("005","020","035","050","065","080","095")),
  paste0("gft-exal-p",c("005","020","035","050","065","080","095")),"gft-mq-al","gft-mq-exal")
gsc_dates <- function() as.Date("2022-12-25")+seq_len(28L)
gsc_hash_string <- function(x) is.character(x)&&length(x)==1L&&!is.na(x)&&grepl("^[0-9a-f]{64}$",x)
gsc_identity <- function() list(
  source_commit="fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6",
  source_tree="0d0d1eefbc930b31c404a301ace28c8e190b8453",
  source_manifest_sha256="cd6684a6933de85f23d942a538c1efd241e66821b974467afb108379c068887b",
  posterior_target_sha256="72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03",
  input_manifest_sha256="f298dac4dd45479bd847528feab6d1104a8086f2c85116c8568acc53c871ae7f",
  task_manifest_sha256="af3281e0aa916ea1ff4a793752c221e051422f2d6705c9f88da471c1e58e5397")
gsc_task_family <- function(id) {
  gsc_require(length(id)==1L&&id %in% gsc_tasks(),"unknown task")
  if(id=="gft-mq-al")"MQ AL" else if(id=="gft-mq-exal")"MQ exAL" else
    if(startsWith(id,"gft-al-"))"Independent AL" else "Independent exAL"
}
gsc_task_tau <- function(id) if(startsWith(id,"gft-mq-"))gsc_tau() else
  as.numeric(sub(".*-p","",id))/100

gsc_validate_collection <- function(x, expected) {
  q <- gsc_require
  q(is.list(x)&&identical(x$schema_version,"glofas_same_family_accepted_collection_v1")&&
    identical(x$status,"SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED")&&x$ledger_mutations==0&&
    x$fit_objects_loaded==0&&identical(x$future_truth_read,FALSE)&&
    identical(x$article_publication_authorized,FALSE),"genuine truth-free accepted collection required")
  ids <- vapply(x$producers,function(z)z$task_id,character(1L))
  q(length(ids)==16L&&!anyDuplicated(ids)&&setequal(ids,gsc_tasks()),"exact sixteen producers required")
  fields <- c("source_commit","source_tree","source_manifest_sha256","posterior_target_sha256",
    "input_manifest_sha256","task_manifest_sha256")
  q(setequal(fields,names(expected))&&all(vapply(fields,function(k)
    identical(expected[[k]],gsc_identity()[[k]]),logical(1L))),"frozen fitting-source identity required")
  for(z in x$producers) {
    q(identical(z$state,"accepted")&&isTRUE(z$numerical_gates_pass)&&
      identical(z$identity$task_id,z$task_id)&&identical(z$identity$rng_namespace,z$task_id)&&
      all(vapply(fields,function(k)identical(z$identity[[k]],expected[[k]]),logical(1L))),
      "producer source/target identity differs")
    q(gsc_hash_string(z$output_manifest_sha256)&&is.character(z$claim_nonce)&&nzchar(z$claim_nonce)&&
      identical(z$terminal$exit_code,0L)&&isTRUE(z$terminal$accounting_complete)&&
      isTRUE(z$terminal$owner_terminated)&&isTRUE(z$terminal$worker_terminated)&&
      !isTRUE(z$terminal$timed_out),"successful closed accounting required")
    names <- vapply(z$artifacts,function(a)a$relative_path,character(1L))
    q(setequal(names,c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json",
      "progress.csv","artifact_manifest.csv"))&&!anyDuplicated(names),"exact producer artifact set required")
  }
  invisible(TRUE)
}

gsc_validate_target <- function(receipt, producer) {
  q <- gsc_require; id <- producer$task_id; contract <- receipt$target_contract
  q(identical(receipt$schema_version,"glofas_family_transition_fit_v1")&&
    identical(receipt$task_id,id)&&isTRUE(receipt$converged)&&identical(receipt$status,"converged")&&
    identical(receipt$claim_nonce,producer$claim_nonce)&&
    setequal(names(receipt$identity),names(producer$identity))&&
    all(vapply(names(producer$identity),function(k)identical(receipt$identity[[k]],producer$identity[[k]]),logical(1L))),
    "retained target receipt or convergence differs")
  q(identical(contract$schema_version,"glofas_family_transition_v1")&&contract$horizons==28&&
    contract$members==51&&identical(as.numeric(unlist(contract$tau)),gsc_tau())&&
    identical(contract$reference_future_law,"one_normalized_same_family_Y_transition_per_horizon_per_level")&&
    identical(contract$product_location,"reference_readout_plus_discrepancy_readout_not_future_response_plus_discrepancy")&&
    identical(contract$ensemble_factorization,"unit_member_factors_within_each_horizon_conditioned_on_preceding_input_histories_and_parameters")&&
    contract$future_Y_factors_per_level==28&&contract$future_G_factors_per_level==1428&&
    identical(contract$MQ_path_convention,"separate_level_specific_future_paths_adjacent_coefficient_prior")&&
    identical(contract$initializer_role,"coefficient_and_path_moments_only_not_prior_or_convergence_state")&&
    identical(contract$response_summary,"level_p_marginal_quantile_of_full_ensemble_conditioned_Gaussian_VB_path_factor")&&
    identical(contract$future_truth_used_in_fit,FALSE)&&identical(contract$replacement_gaussian_path_prior,FALSE)&&
    identical(contract$extra_response_noise,FALSE)&&identical(contract$isotonic_adjustment,FALSE)&&
    identical(contract$response_transform,"log1p")&&identical(contract$inverse_transform,"expm1")&&
    identical(contract$future_truth_policy,"physically_excluded_from_fit_objects_scoring_sidecar_only")&&
    identical(contract$future_weather_policy,"frozen_realized_PRISM_ERA5_not_authenticated_issue_time_forecasts"),
    "legacy, weighted, driver-prior or changed reporting target rejected")
  blocks <- if(startsWith(id,"gft-mq-"))7 else 1
  counts <- receipt$counts
  q(counts$horizons==28&&counts$members==51&&counts$future_Y==28&&counts$future_G==1428&&
    counts$historical_Y==12455&&counts$historical_G==12455&&counts$residual_jacobian_determinant==1&&
    counts$quantile_blocks==blocks&&counts$total_future_Y==28*blocks&&counts$total_future_G==1428*blocks&&
    identical(counts$replacement_gaussian_path_prior,FALSE),"future factor counts differ")
  q(isTRUE(receipt$feature_contract$two_block_design)&&
    identical(receipt$feature_contract$discrepancy_input_stream,"discrepancy")&&
    identical(receipt$feature_contract$discrepancy_transition_strategy,"recursive_level")&&
    receipt$feature_contract$reference_coefficients==1501&&receipt$feature_contract$discrepancy_coefficients==1001,
    "reference/discrepancy feature contract differs")
  invisible(TRUE)
}

gsc_validate_grid <- function(rows, families=gsc_families(), probabilities=gsc_tau()) {
  q <- gsc_require
  required <- c("family","target_date","horizon","tau","quantile_transformed","quantile")
  q(is.data.frame(rows)&&all(required %in% names(rows))&&
    nrow(rows)==length(families)*28L*length(probabilities)&&setequal(unique(rows$family),families),
    "complete family/date/probability grid required")
  dates <- as.Date(rows$target_date)
  q(!anyNA(dates)&&is.numeric(rows$horizon)&&all(rows$horizon %in% 1:28)&&
    all(dates==gsc_dates()[rows$horizon])&&all(is.finite(rows$tau))&&
    all(is.finite(c(rows$quantile_transformed,rows$quantile)))&&
    all(abs(rows$quantile-expm1(rows$quantile_transformed))<=1e-10*pmax(1,abs(rows$quantile))),
    "dates, scale or response transformation differs")
  key <- paste(rows$family,rows$horizon,rows$tau,sep="|")
  expected <- expand.grid(family=families,horizon=1:28,tau=probabilities,stringsAsFactors=FALSE)
  q(!anyDuplicated(key)&&setequal(key,paste(expected$family,expected$horizon,expected$tau,sep="|")),
    "missing or duplicate forecast key")
  invisible(TRUE)
}

gsc_quantile_rows <- function(rows,id) {
  q <- gsc_require
  q(is.data.frame(rows)&&all(c("task_id","estimand","approximation","extra_response_noise_added",
    "quantile_functional_credible_interval","path_factor_mean","path_factor_sd") %in% names(rows))&&
    all(rows$task_id==id)&&all(rows$estimand=="marginal_future_response_quantile_under_ensemble_conditioned_VB")&&
    all(!rows$extra_response_noise_added)&&all(!rows$quantile_functional_credible_interval)&&
    all(is.finite(c(rows$path_factor_mean,rows$path_factor_sd)))&&all(rows$path_factor_sd>0),
    "quantile report functional differs")
  q(all(abs(rows$quantile_transformed-(rows$path_factor_mean+rows$path_factor_sd*qnorm(rows$tau)))<1e-10),
    "analytic response-factor quantile does not reproduce")
  rows$family <- gsc_task_family(id)
  gsc_validate_grid(rows,gsc_task_family(id),gsc_task_tau(id))
  rows[,c("family","target_date","horizon","tau","quantile_transformed","quantile")]
}

gsc_normal_rows <- function(rows,receipt,prepared_design_sha256) {
  q <- gsc_require
  d <- receipt$design_identity
  q(identical(receipt$schema_version,"glofas_normal_reporting_enrollment_receipt_v1")&&
    identical(receipt$status,"TWO_BASELINES_ENROLLED_NOT_ARTICLE_AUTHORITY")&&
    identical(receipt$source_commit,"cfa50ff3f4eebbdbf36c03c50b04bf2bed39c437")&&
    identical(receipt$source_tree,"13090d12f6de3551e8f49f1f862e4a4f621ffda7")&&
    identical(d$schema_version,"glofas_normal_design_mapping_v2")&&
    identical(d$status,"EXACT_PROTECTED_DESIGN_MATCH")&&isTRUE(d$exact_comparison)&&
    isTRUE(d$closure_context_and_all_compiled_bindings_identical)&&
    identical(d$scoring_truth_read,FALSE)&&d$new_model_fits==0&&d$builder_calls==0&&
    d$historical_Y==12455&&d$historical_G==12455&&d$future_Y==28&&d$future_G==1428&&
    identical(receipt$new_model_fits,0L)&&identical(receipt$scoring_calls,0L)&&
    identical(receipt$publication_performed,FALSE)&&identical(receipt$prepared_design$sha256,prepared_design_sha256),
    "separate authentic Normal enrollment required")
  for(model in c("normal_ridge","normal_rhs")) {
    z <- receipt$models[[model]];r <- z$new_reporting
    q(identical(z$status,"FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED")&&isTRUE(z$fit_reused)&&
      z$new_model_fits==0&&z$model_calls==0&&z$builder_calls==0&&z$expected_rows==196&&identical(z$scoring_truth_read,FALSE)&&
      identical(r$schema_version,"glofas_normal_analytic_reporting_v1")&&
      identical(as.numeric(unlist(r$tau)),gsc_tau())&&r$horizons==28&&
      identical(r$response_factor,"full_ensemble_conditioned_q_U_Normal")&&
      identical(r$transformed_quantile,"m_U_h+sqrt(V_U_hh)*qnorm(p)")&&
      identical(r$inverse_transform,"expm1")&&identical(r$isotonic_adjustment,FALSE)&&
      isTRUE(r$fit_reused)&&r$new_model_fits==0&&identical(r$scoring_truth_read,FALSE)&&
      identical(r$historical_reporting,"latent_future_path_empirical_quantiles_type8")&&
      identical(r$extra_response_noise_added,FALSE)&&identical(r$quantile_functional_credible_interval,FALSE),
      "Normal report is not analytic fit reuse")
  }
  q(is.data.frame(rows)&&nrow(rows)==392L&&all(rows$model %in% c("normal_ridge","normal_rhs"))&&
    all(rows$fit_reused)&&all(!rows$extra_response_noise_added)&&all(!rows$quantile_functional_credible_interval)&&
    all(rows$estimand=="marginal_future_response_quantile_under_ensemble_conditioned_VB"),"Normal row provenance differs")
  q(all(abs(rows$quantile_transformed-rows$path_factor_mean-rows$path_factor_sd*qnorm(rows$tau))<1e-10)&&
    all(is.finite(rows$path_factor_sd))&&all(rows$path_factor_sd>0),"Normal analytic quantiles differ")
  rows$family <- ifelse(rows$model=="normal_ridge","Normal Ridge","Normal RHS")
  gsc_validate_grid(rows,c("Normal Ridge","Normal RHS"))
  rows[,c("family","target_date","horizon","tau","quantile_transformed","quantile")]
}

gsc_raw_rows <- function(members) {
  q <- gsc_require
  q(is.data.frame(members)&&setequal(c("target_date","horizon","member","g_transformed"),names(members))&&
    nrow(members)==1428L&&is.numeric(members$g_transformed)&&all(is.finite(members$g_transformed))&&
    is.numeric(members$horizon)&&all(is.finite(members$horizon))&&
    all(members$horizon %in% 1:28)&&!anyNA(members$member)&&
    all(nzchar(trimws(as.character(members$member)))),"finite integer horizons and nonempty original member identities required")
  q(inherits(members$target_date,"Date")||is.character(members$target_date),"explicit target dates required")
  dates <- as.Date(members$target_date,format="%Y-%m-%d")
  q(!anyNA(dates)&&all(as.character(dates)==as.character(members$target_date))&&
    all(dates==gsc_dates()[members$horizon])&&
    !anyDuplicated(paste(members$horizon,members$member)),"authentic 28-by-51 member grid required")
  q(all(table(members$horizon)==51L)&&setequal(unique(members$horizon),1:28)&&
    length(unique(members$member))==51L,"missing or changed ensemble member set")
  out <- do.call(rbind,lapply(1:28,function(h) {
    b <- members[members$horizon==h,]
    v <- quantile(b$g_transformed,gsc_tau(),names=FALSE,type=8)
    data.frame(family="Raw GloFAS",target_date=as.character(gsc_dates()[h]),horizon=h,
      tau=gsc_tau(),quantile_transformed=v,quantile=expm1(v))
  }))
  gsc_validate_grid(out,"Raw GloFAS");out
}

gsc_assemble <- function(quantile_rows,normal_rows,raw_members) {
  q <- gsc_require
  q(length(quantile_rows)==16L&&!anyDuplicated(names(quantile_rows))&&
    setequal(names(quantile_rows),gsc_tasks()),"all quantile tasks required")
  out <- rbind(do.call(rbind,lapply(gsc_tasks(),function(id)gsc_quantile_rows(quantile_rows[[id]],id))),
    normal_rows,gsc_raw_rows(raw_members))
  gsc_validate_grid(out)
  out[order(match(out$family,gsc_families()),out$horizon,out$tau),]
}

gsc_crossings <- function(rows) {
  gsc_validate_grid(rows)
  do.call(rbind,lapply(gsc_families(),function(f) {
    b <- rows[rows$family==f,];count <- sum(vapply(1:28,function(h)
      sum(diff(b$quantile_transformed[b$horizon==h][order(b$tau[b$horizon==h])])<0),integer(1L)))
    data.frame(family=f,raw_crossing_pairs=count,adjacent_comparisons=168L,
      raw_crossing_rate=count/168,adjustment_applied=FALSE)
  }))
}

gsc_score <- function(rows,truth) {
  gsc_validate_grid(rows);q <- gsc_require
  q(is.data.frame(truth)&&nrow(truth)==28L&&all(c("target_date","horizon","y_transformed") %in% names(truth))&&
    !anyDuplicated(truth$horizon)&&setequal(truth$horizon,1:28)&&
    all(as.Date(truth$target_date)==gsc_dates()[truth$horizon])&&all(is.finite(truth$y_transformed)),
    "complete scoring-only USGS truth required")
  at <- match(rows$horizon,truth$horizon);e <- truth$y_transformed[at]-rows$quantile_transformed
  loss <- e*(rows$tau-(e<0));w <- c(.075,rep(.15,5),.075)
  by_date <- do.call(rbind,lapply(gsc_families(),function(f)do.call(rbind,lapply(1:28,function(h) {
    idx <- which(rows$family==f&rows$horizon==h);idx <- idx[order(rows$tau[idx])]
    quant <- rows$quantile_transformed[idx];y <- truth$y_transformed[match(h,truth$horizon)]
    data.frame(family=f,target_date=as.character(gsc_dates()[h]),horizon=h,
      grid_acrps_log1p=2*sum(w*loss[idx]),mean_check_loss=mean(loss[idx]),
      covered90=y>=quant[1L]&y<=quant[7L],inverted90=quant[1L]>quant[7L])
  }))))
  summary <- do.call(rbind,lapply(gsc_families(),function(f) {
    b <- by_date[by_date$family==f,]
    data.frame(family=f,n_horizons=28L,grid_acrps_log1p=mean(b$grid_acrps_log1p),
      mean_check_loss=mean(b$mean_check_loss),coverage90=mean(b$covered90),inverted_intervals=sum(b$inverted90))
  }))
  calibration <- do.call(rbind,lapply(gsc_families(),function(f)do.call(rbind,lapply(gsc_tau(),function(p) {
    idx <- which(rows$family==f&rows$tau==p)
    data.frame(family=f,tau=p,n_horizons=28L,empirical_coverage=mean(e[idx]<=0),
      coverage_error=mean(e[idx]<=0)-p,mean_check_loss=mean(loss[idx]))
  }))))
  list(by_date=by_date,summary=summary,calibration=calibration,crossings=gsc_crossings(rows),
    score_contract=list(name="realized_finite_grid_acrps",scale="log1p",factor=2,
      weights=w,weights_renormalized=FALSE,truth_used_only_after_assembly=TRUE,
      model_selection_or_retuning=FALSE,article_publication_authorized=FALSE))
}

gsc_pin <- function(x,max_bytes=Inf) {
  q <- gsc_require
  q(is.list(x)&&is.character(x$path)&&length(x$path)==1L&&startsWith(x$path,"/")&&
    file.exists(x$path)&&!file.info(x$path)$isdir&&is.numeric(x$size_bytes)&&
    x$size_bytes>0&&x$size_bytes<=max_bytes&&file.info(x$path)$size==x$size_bytes&&gsc_hash_string(x$sha256),
    "bounded pinned regular input required")
  parts <- strsplit(x$path,"/",fixed=TRUE)[[1L]];p <- "/"
  for(v in parts[nzchar(parts)]) {q(v!="..","path traversal");p <- file.path(p,v);q(!nzchar(Sys.readlink(p)),"symlink input")}
  q(identical(normalizePath(x$path,mustWork=TRUE),x$path)&&
    identical(unname(tools::sha256sum(x$path)),x$sha256),"input bytes changed")
  x$path
}

# Durable forecast commitment is independent of (and precedes) scoring truth.
gsc_make_forecast_seal <- function(root,input_bindings,prepared_design_sha256) {
  required <- c("quantile_paths.csv","raw_crossings.csv","accepted_producers.json")
  gsc_validate_grid(read.csv(file.path(root,required[1L]),stringsAsFactors=FALSE))
  collection <- jsonlite::read_json(file.path(root,required[3L]),simplifyVector=FALSE)
  gsc_validate_collection(collection,gsc_identity())
  gsc_require(gsc_hash_string(prepared_design_sha256)&&
    setequal(names(input_bindings),c("normal_manifest","normal_receipt","normal_quantiles",
      "raw_member_derivation","raw_members")),"complete truth-free forecast bindings required")
  list(schema_version="glofas_same_family_forecast_seal_v1",
    status="COMPLETE_FORECAST_GRID_COMMITTED_BEFORE_TRUTH",future_truth_read=FALSE,
    forecast_rows=1372L,families=7L,producers=16L,expected_identity=gsc_identity(),
    prepared_design_sha256=prepared_design_sha256,input_bindings=input_bindings,
    artifacts=lapply(required,function(name) {
      p <- file.path(root,name)
      list(relative_path=name,size_bytes=as.numeric(file.info(p)$size),sha256=unname(tools::sha256sum(p)))
    }),
    article_publication_authorized=FALSE)
}

gsc_verify_forecast_seal <- function(root,sha256) {
  path <- file.path(root,"FORECAST_SEAL.json")
  gsc_pin(list(path=path,size_bytes=as.numeric(file.info(path)$size),sha256=sha256),2*1024^2)
  s <- jsonlite::read_json(path,simplifyVector=FALSE);q <- gsc_require
  q(identical(s$schema_version,"glofas_same_family_forecast_seal_v1")&&
    identical(s$status,"COMPLETE_FORECAST_GRID_COMMITTED_BEFORE_TRUTH")&&
    identical(s$future_truth_read,FALSE)&&s$forecast_rows==1372&&s$families==7&&s$producers==16&&
    identical(s$article_publication_authorized,FALSE)&&
    setequal(names(s$expected_identity),names(gsc_identity()))&&
    all(vapply(names(gsc_identity()),function(k)identical(s$expected_identity[[k]],gsc_identity()[[k]]),logical(1L))),
    "pre-truth forecast commitment required")
  required <- c("quantile_paths.csv","raw_crossings.csv","accepted_producers.json")
  names <- vapply(s$artifacts,`[[`,character(1L),"relative_path")
  q(length(names)==3L&&!anyDuplicated(names)&&setequal(names,required),"exact pre-truth sealed membership required")
  for(a in s$artifacts)gsc_pin(list(path=file.path(root,a$relative_path),size_bytes=a$size_bytes,
    sha256=a$sha256),8*1024^2)
  invisible(s)
}
