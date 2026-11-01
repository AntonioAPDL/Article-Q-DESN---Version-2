# Additive, opt-in issued-ensemble target. Historical kernels/defaults are unchanged.
# Preparation is not launch authorization; production entry is guarded separately.

app_gft_stop <- function(...) stop(..., call. = FALSE)
app_gft_hash <- function(x) {
  digest::digest(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = 17),
    algo = "sha256", serialize = FALSE)
}
app_gft_json <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)
app_gft_values <- function(x) as.character(unlist(x, use.names = FALSE))
app_gft_no_symlink_path <- function(path) {
  raw <- as.character(path)
  if (length(raw)!=1L || !nzchar(raw) || grepl("(^|/)\\.\\.(/|$)",raw)) app_gft_stop("Unsafe file path.")
  if (!startsWith(raw,"/")) raw<-file.path(getwd(),raw)
  pieces<-strsplit(raw,"/",fixed=TRUE)[[1L]]
  current<-"/"
  for (piece in pieces[nzchar(pieces)]) {
    current<-file.path(current,piece)
    link<-Sys.readlink(current)
    if (!is.na(link) && nzchar(link)) app_gft_stop("Symlink input/output component is forbidden: ",current)
  }
  invisible(TRUE)
}

app_glofas_family_transition_contract <- function() {
  list(schema_version = "glofas_family_transition_v1", horizons = 28L,
    members = 51L, tau = c(.05, .20, .35, .50, .65, .80, .95),
    reference_future_law = "one_normalized_same_family_Y_transition_per_horizon_per_level",
    product_location = "reference_readout_plus_discrepancy_readout_not_future_response_plus_discrepancy",
    ensemble_factorization = "unit_member_factors_within_each_horizon_conditioned_on_preceding_input_histories_and_parameters",
    future_Y_factors_per_level = 28L, future_G_factors_per_level = 1428L,
    replacement_gaussian_path_prior = FALSE,
    future_truth_used_in_fit = FALSE,
    future_weather_policy = "frozen_realized_PRISM_ERA5_not_authenticated_issue_time_forecasts",
    future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
    MQ_path_convention = "separate_level_specific_future_paths_adjacent_coefficient_prior",
    response_summary = "level_p_marginal_quantile_of_full_ensemble_conditioned_Gaussian_VB_path_factor",
    uncertainty_label = "approximate_marginal_response_quantile_not_quantile_functional_credible_interval",
    response_transform = "log1p", inverse_transform = "expm1",
    extra_response_noise = FALSE, isotonic_adjustment = FALSE,
    initializer_role = "coefficient_and_path_moments_only_not_prior_or_convergence_state",
    joint_inner_workers = 1L,
    numerical_regularization = list(path_linearized_precision_diagonal = 1e-8,
      MQ_inner_ridge_floor = 1e-12,
      interpretation = "numerical_stabilizers_recorded_separately_not_an_additional_path_prior"),
    normal_reuse = "blocked_until_complete_target_input_prior_reporting_and_numerical_identity_verified",
    allow_launch = FALSE)
}

app_glofas_family_transition_tasks <- function(tau = c(.05,.20,.35,.50,.65,.80,.95)) {
  if (!identical(as.numeric(tau), c(.05,.20,.35,.50,.65,.80,.95))) {
    app_gft_stop("The frozen transition workflow requires its seven-level grid.")
  }
  id <- function(family, p) sprintf("gft-%s-p%03d", family, round(100*p))
  rows <- lapply(seq_along(tau), function(k) {
    p <- tau[k]
    parent <- if (p == .5) "" else id("al", tau[if (p < .5) k+1L else k-1L])
    data.frame(task_id = id("al", p), likelihood = "al", model_class = "independent",
      tau = p, dependencies = parent, rng_namespace = id("al", p))
  })
  rows <- c(rows, lapply(tau, function(p) data.frame(task_id = id("exal", p),
    likelihood = "exal", model_class = "independent", tau = p,
    dependencies = id("al", p), rng_namespace = id("exal", p))))
  rows <- c(rows, lapply(c("al", "exal"), function(f) data.frame(task_id = paste0("gft-mq-", f),
    likelihood = f, model_class = "multiquantile", tau = NA_real_,
    dependencies = paste(vapply(tau, function(p) id(f,p), character(1L)), collapse = "|"),
    rng_namespace = paste0("gft-mq-", f))))
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out$operation <- "glofas_family_transition_fit"
  out$expected_forecast_rows <- ifelse(out$model_class == "multiquantile", 196L, 28L)
  out
}

app_gft_manifest <- function(paths, roles = rep("input", length(paths)), root = NULL) {
  paths <- normalizePath(paths, mustWork = TRUE)
  if (length(paths) != length(roles) || anyDuplicated(paths)) app_gft_stop("Invalid input inventory.")
  if (is.null(root)) root <- dirname(paths[1L])
  root <- paste0(normalizePath(root,mustWork=TRUE),"/")
  if (any(!startsWith(paths,root))) app_gft_stop("Inputs must be inside their immutable bundle root.")
  data.frame(relative_path = substring(paths,nchar(root)+1L), size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)), role = roles,
    stringsAsFactors = FALSE)
}

app_gft_verify_manifest <- function(path, sha256, reject_truth = TRUE, root = dirname(path)) {
  app_gft_no_symlink_path(path)
  app_gft_no_symlink_path(root)
  if (!identical(app_sha256_file(path), as.character(sha256))) app_gft_stop("Manifest hash mismatch: ", path)
  x <- app_read_csv(path)
  if (!all(c("relative_path", "size_bytes", "sha256", "role") %in% names(x)) ||
      !nrow(x) || anyDuplicated(x$relative_path) ||
      any(grepl("(^/|(^|/)\\.\\.(/|$))",x$relative_path))) app_gft_stop("Incomplete or unsafe input inventory.")
  x$path <- file.path(normalizePath(root,mustWork=TRUE),x$relative_path)
  resolved <- normalizePath(x$path,mustWork=TRUE)
  if (any(!startsWith(resolved,paste0(normalizePath(root,mustWork=TRUE),"/")))) {
    app_gft_stop("An input symlink escapes its frozen bundle root.")
  }
  if (reject_truth && any(grepl("scoring|future_truth|heldout_truth", x$role, ignore.case = TRUE))) {
    app_gft_stop("Future truth/scoring sidecars cannot enter a fitting request.")
  }
  for (i in seq_len(nrow(x))) {
    p <- x$path[i]
    app_gft_no_symlink_path(p)
    if (!file.exists(p) || is.na(file.info(p)$size) ||
        as.numeric(file.info(p)$size) != as.numeric(x$size_bytes[i]) ||
        !identical(app_sha256_file(p), as.character(x$sha256[i]))) {
      app_gft_stop("Frozen input changed or disappeared: ", p)
    }
  }
  x
}

app_gft_bind_path <- function(path, manifest, role = NULL) {
  app_gft_no_symlink_path(path)
  path <- normalizePath(path, mustWork = TRUE)
  i <- match(path, normalizePath(manifest$path, mustWork = TRUE))
  if (is.na(i) || (!is.null(role) && !identical(manifest$role[i], role))) {
    app_gft_stop("Requested object is not bound by the input manifest: ", path)
  }
  path
}

app_glofas_family_transition_validate_design <- function(design, synthetic = FALSE,
    check_finite_difference = TRUE, tolerance = 1e-10) {
  app_validate_glofas_latent_path_design(design)
  if (!is.null(design$latent_data)) app_validate_glofas_latent_path_data(design$latent_data)
  if (!is.null(design$future_context$latent_data)) app_validate_glofas_latent_path_data(design$future_context$latent_data)
  H <- nrow(design$future_key)
  probe <- design$future_builder(as.numeric(design$y_future_init))
  gi <- app_latent_future_g_index(probe)
  E <- as.integer(table(gi))
  if (!isTRUE(synthetic) && (H != 28L || length(E) != H || any(E != 51L))) {
    app_gft_stop("Production transition target requires H=28 and 51 distinct members per horizon.")
  }
  if (isTRUE(synthetic) && (H > 3L || nrow(design$H_fixed) > 20L)) {
    app_gft_stop("Synthetic execution is restricted to tiny in-memory test fixtures.")
  }
  if (!identical(design$future_truth_policy,
      "physically_excluded_from_fit_objects_scoring_sidecar_only") ||
      any((design$weight_fixed %||% rep(1,length(design$z_fixed))) != 1) ||
      any((probe$weight_y %||% rep(1,H)) != 1) ||
      any((probe$weight_g %||% rep(1,length(probe$z_g))) != 1)) {
    app_gft_stop("Transition target requires truth-free inputs and unit Y/G factors.")
  }
  if (length(gi) != length(probe$z_g) || length(E) != H || any(E != E[1L]) ||
      anyDuplicated(paste(probe$row_info_g$target_date, probe$row_info_g$member))) {
    app_gft_stop("Incomplete or duplicated horizon/member likelihood rows.")
  }
  if (!identical(sort(unique(gi)), seq_len(H))) app_gft_stop("Noncontiguous member horizons.")
  if (!is.null(design$latent_data)) {
    data <- design$latent_data
    match_key <- paste(probe$row_info_g$target_date,probe$row_info_g$member)
    source_key <- paste(data$g_ensemble$target_date,data$g_ensemble$member)
    ix <- match(match_key,source_key)
    baseline <- as.numeric(probe$discrepancy_baseline_future %||% rep(0,H))
    if (anyNA(ix) || anyDuplicated(ix) || length(ix)!=nrow(data$g_ensemble) ||
        any(abs(as.numeric(probe$z_g)+baseline[gi]-as.numeric(data$g_ensemble$g_transformed[ix]))>tolerance)) {
      app_gft_stop("Issued likelihood observations differ from the complete frozen member panel.")
    }
    if (any(as.Date(data$y_history$target_date)>=min(as.Date(design$future_key$target_date)))) {
      app_gft_stop("Future gauge truth entered the historical response input.")
    }
  }
  # Y equation uses only the reference readout; G uses reference plus discrepancy.
  if (any(abs(probe$H_y[, design$alpha_index, drop=FALSE]) > tolerance) ||
      max(abs(app_latent_future_H_g_key(probe)[,design$beta_index,drop=FALSE] -
        probe$H_y[,design$beta_index,drop=FALSE])) > tolerance) {
    app_gft_stop("Future G location is not reference readout plus discrepancy.")
  }
  for (Js in list(probe$J_y, app_latent_future_J_g_key(probe))) {
    if (length(Js) != H || any(vapply(seq_len(H), function(h) {
      J <- as.matrix(Js[[h]])
      !identical(dim(J), c(ncol(design$H_fixed),H)) || any(!is.finite(J)) ||
        any(abs(J[,seq.int(h,H),drop=FALSE]) > tolerance)
    }, logical(1L)))) app_gft_stop("Future features are not strictly causal.")
  }
  # Do not trust a declared Jacobian alone: perturb current/future responses.
  if (isTRUE(check_finite_difference)) {
    for (j in seq_len(H)) {
      path <- as.numeric(design$y_future_init)
      path[j] <- path[j] + .03125
      changed <- design$future_builder(path)
      if (max(abs(changed$H_y[seq_len(j),,drop=FALSE] - probe$H_y[seq_len(j),,drop=FALSE])) > tolerance ||
          max(abs(app_latent_future_H_g_key(changed)[seq_len(j),,drop=FALSE] -
            app_latent_future_H_g_key(probe)[seq_len(j),,drop=FALSE])) > tolerance ||
          !identical(as.numeric(changed$z_g), as.numeric(probe$z_g))) {
        app_gft_stop("Actual future builder violates strict causality or changes issued observations.")
      }
    }
  }
  list(horizons = H, members = E[1L], historical_Y = sum(design$source_fixed == "Y"),
    historical_G = sum(design$source_fixed == "G"), future_Y = H,
    future_G = length(probe$z_g), residual_jacobian_determinant = 1,
    replacement_gaussian_path_prior = FALSE)
}

app_glofas_family_transition_design <- function(frozen_design, synthetic = FALSE) {
  # This copies geometry, not fits or a Normal-driver prior. Do not mutate source.
  out <- frozen_design
  if (!isTRUE(synthetic)) app_glofas_unit_member_validate_design(out)
  out$historical_unit_member_contract <- out$unit_member_contract
  out$unit_member_contract <- NULL
  out$family_transition_contract <- app_glofas_family_transition_contract()
  out$design_version <- paste0(out$design_version, "__same_family_transition_v1")
  attr(out,"future_probe_init") <- NULL
  app_glofas_family_transition_validate_design(out, synthetic)
  for (key in c("H_fixed","z_fixed","source_fixed","weight_fixed","future_key",
      "beta_index","alpha_index","intercept_index")) {
    if (!identical(out[[key]], frozen_design[[key]])) app_gft_stop("Protected geometry changed: ", key)
  }
  out
}

app_glofas_family_transition_controls <- function(vb_args, controls = NULL) {
  protected <- vb_args[c("prior_sigma","beta_rhs","alpha_rhs","beta_ridge")]
  controls <- controls %||% app_glofas_unit_member_default_controls()
  for (name in setdiff(names(controls),c("schema_version","reset_target_state"))) vb_args[[name]] <- controls[[name]]
  vb_args$future_gaussian_prior <- NULL
  vb_args$initial_state <- NULL
  vb_args$warm_start <- NULL
  vb_args$checkpoint <- list(enabled = FALSE)
  vb_args$prior_addition <- NULL
  vb_args$joint_rhs_allow_schedule_rebase <- FALSE
  vb_args$joint_inner_workers <- 1L # serial parity is the approved baseline.
  vb_args$max_iter_hard_cap <- vb_args$max_iter
  vb_args$min_iter_elbo <- as.integer(vb_args$min_iter_elbo %||% 200L)
  vb_args$min_beta_updates <- as.integer(vb_args$min_beta_updates %||% 2L)
  vb_args$freeze_beta_warmup_iters <- as.integer(vb_args$freeze_beta_warmup_iters %||% 0L)
  # Stale stop/fixed-iteration diagnostics cannot leak into the fresh target.
  vb_args$diagnostics <- list(profile_substeps = TRUE)
  if (vb_args$max_iter < vb_args$min_iter_elbo || vb_args$min_iter_elbo < 1L ||
      vb_args$freeze_beta_warmup_iters + vb_args$min_beta_updates > vb_args$max_iter ||
      vb_args$min_beta_updates < 1L) app_gft_stop("Invalid fresh-target iteration/freeze controls.")
  if (!identical(vb_args[c("prior_sigma","beta_rhs","alpha_rhs","beta_ridge")],protected)) {
    app_gft_stop("Execution controls cannot change destination prior hyperparameters.")
  }
  vb_args
}

app_gft_moment_initializer <- function(x, design) {
  init <- app_glofas_part4_initializer(x, design)
  # Old source counts/likelihood scales are not a destination prior or a resumed state.
  init$sigma_state <- NULL
  init$sigma_mean <- NULL
  init$gamma <- NULL
  init$provenance$type <- "moments_only_fresh_target_no_prior_or_iteration_transfer"
  init
}

app_glofas_family_transition_quantiles <- function(fit, tau, dates, inverse = TRUE) {
  core <- fit$fit %||% fit
  m <- as.numeric(core$summary$y_future_mean)
  V <- as.matrix(core$summary$y_future_cov)
  if (length(tau) != 1L || tau <= 0 || tau >= 1 || length(m) != length(dates) ||
      !identical(dim(V),c(length(m),length(m))) || any(!is.finite(c(m,V))) ||
      max(abs(V-t(V))) > 1e-8 || any(diag(V) <= 0) ||
      min(eigen(V,symmetric=TRUE,only.values=TRUE)$values) < -1e-8) {
    app_gft_stop("Invalid ensemble-conditioned Gaussian future-path factor.")
  }
  q <- m + sqrt(diag(V))*stats::qnorm(tau)
  if (any(!is.finite(q)) || (isTRUE(inverse) && any(!is.finite(expm1(q))))) {
    app_gft_stop("Marginal response quantile is nonfinite after transformation.")
  }
  data.frame(target_date=as.character(as.Date(dates)), horizon=seq_along(m), tau=tau,
    quantile_transformed=q, quantile=if (isTRUE(inverse)) expm1(q) else q,
    path_factor_mean=m, path_factor_sd=sqrt(diag(V)),
    estimand="marginal_future_response_quantile_under_ensemble_conditioned_VB",
    approximation="Gaussian_path_factor_with_local_Delta_and_coefficient_factorization",
    extra_response_noise_added=FALSE, quantile_functional_credible_interval=FALSE)
}

app_glofas_family_transition_crossings <- function(rows) {
  if (!all(c("horizon","tau","quantile_transformed") %in% names(rows)) ||
      anyDuplicated(paste(rows$horizon,rows$tau))) app_gft_stop("Invalid forecast grid keys.")
  by_h <- split(rows,rows$horizon)
  comparisons <- sum(vapply(by_h,function(x) nrow(x)-1L,integer(1L)))
  counts <- sum(vapply(by_h,function(x) sum(diff(x$quantile_transformed[order(x$tau)]) < 0),integer(1L)))
  data.frame(raw_crossing_pairs=counts,adjacent_comparisons=comparisons,
    crossing_rate=if (comparisons) counts/comparisons else NA_real_,
    adjustment_applied=FALSE)
}

app_glofas_family_transition_normal_reuse <- function(expected, observed) {
  keys <- c("target_sha256","history_sha256","design_sha256","prior_sha256",
    "issued_sha256","reporting_sha256","numerical_controls_sha256","source_sha256")
  complete <- all(keys %in% names(expected)) && all(keys %in% names(observed)) &&
    all(vapply(keys,function(k) is.character(expected[[k]]) && length(expected[[k]])==1L &&
      grepl("^[0-9a-f]{64}$",expected[[k]]) && identical(expected[[k]],observed[[k]]),logical(1L)))
  list(reusable=complete,status=if (complete) "identity_verified" else "blocked_missing_or_different_complete_identity",
    required_identity_fields=keys)
}

app_glofas_family_transition_fit <- function(design, job, vb_args, dependency_fits=list(),
    root_initializer=NULL, seed=1L, synthetic=FALSE, verified_execution=NULL) {
  if (!isTRUE(synthetic) && !isTRUE(verified_execution$claim_verified)) {
    app_gft_stop("Production fitting requires a verified source-bound coordinator claim.")
  }
  if (!isTRUE(synthetic) && identical(as.character(job$task_id),"gft-al-p050") &&
      is.null(root_initializer)) app_gft_stop("Median AL requires authenticated compatible Normal starting moments; cold start is not authorized.")
  counts <- app_glofas_family_transition_validate_design(design,synthetic)
  counts$quantile_blocks <- if (identical(as.character(job$model_class),"multiquantile")) 7L else 1L
  counts$total_future_Y <- counts$future_Y*counts$quantile_blocks
  counts$total_future_G <- counts$future_G*counts$quantile_blocks
  if (!is.null(vb_args$future_gaussian_prior) || !is.null(vb_args$warm_start) ||
      isTRUE((vb_args$checkpoint %||% list())$enabled) || !is.null(vb_args$prior_addition)) {
    app_gft_stop("Fresh transition fits reject driver priors, resumed states and inherited prior additions.")
  }
  started <- Sys.time()
  if (identical(as.character(job$model_class),"multiquantile")) {
    tau <- app_glofas_family_transition_contract()$tau
    if (length(dependency_fits) != length(tau)) app_gft_stop("MQ requires its complete independent family.")
    cores <- lapply(dependency_fits,function(x) x$fit %||% x)
    for (k in seq_along(cores)) {
      if (!identical(cores[[k]]$likelihood_family,as.character(job$likelihood)) ||
          !isTRUE(cores[[k]]$vb_diagnostics$future_y_working_likelihood_used) ||
          isTRUE(cores[[k]]$vb_diagnostics$future_gaussian_prior_used)) {
        app_gft_stop("MQ initializers do not share the new same-family target.")
      }
    }
    fit <- app_fit_latent_path_joint_vb_core(
      designs=lapply(tau,function(p) app_glofas_part4_design_for_quantile(design,p)),
      tau=tau,likelihood=as.character(job$likelihood),independent_fits=cores,
      vb_args=vb_args,seed=seed,initial_joint_fit=NULL)
    rows <- do.call(rbind,lapply(seq_along(tau),function(k)
      app_glofas_family_transition_quantiles(fit$fits[[k]],tau[k],design$future_key$target_date)))
    converged <- isTRUE(fit$converged)
    final_cores <- fit$fits
  } else {
    if (length(dependency_fits) > 1L) app_gft_stop("Independent task expects one or zero moment initializers.")
    tau <- as.numeric(job$tau)
    design <- app_glofas_part4_design_for_quantile(design,tau)
    init <- if (length(dependency_fits)) dependency_fits[[1L]] else root_initializer
    vb_args$initial_state <- if (is.null(init)) NULL else app_gft_moment_initializer(init,design)
    fit <- if (identical(as.character(job$likelihood),"al"))
      app_fit_latent_path_al_vb_core(design,tau,"rhs_ns",vb_args,seed) else if (
      identical(as.character(job$likelihood),"exal"))
      app_fit_latent_path_exal_vb_core(design,tau,"rhs_ns",vb_args,seed) else
      app_gft_stop("Only AL/exAL quantile refits are authorized by this workflow.")
    rows <- app_glofas_family_transition_quantiles(fit,tau,design$future_key$target_date)
    converged <- isTRUE(fit$vb_diagnostics$converged)
    final_cores <- list(fit)
  }
  for (core in final_cores) {
    if (!isTRUE(core$vb_diagnostics$future_y_working_likelihood_used) ||
        isTRUE(core$vb_diagnostics$future_gaussian_prior_used)) app_gft_stop("Kernel executed the wrong future target.")
  }
  list(schema_version="glofas_family_transition_fit_v1",task_id=as.character(job$task_id),
    fit=fit,forecast_quantiles=rows,raw_crossings=app_glofas_family_transition_crossings(rows),
    counts=counts,converged=converged,status=if (converged) "converged" else "retained_not_promotable_nonconverged",
    target_contract=app_glofas_family_transition_contract(),
    rng_policy=list(namespace=as.character(job$rng_namespace),seed=as.integer(seed),
      rule="preserved_frozen_source_seed_for_VB_diagnostics_primary_marginal_quantiles_are_analytic"),
    feature_contract=list(discrepancy_input_stream=design$discrepancy_input_stream %||% "unspecified",
      discrepancy_transition_strategy=design$discrepancy_transition_strategy %||% "recursive_level",
      two_block_design=isTRUE(design$two_block_design),
      reference_coefficients=length(design$beta_index),discrepancy_coefficients=length(design$alpha_index),
      future_discrepancy_offset="frozen_known_baseline_if_present_in_source_design"),
    elapsed_seconds=as.numeric(difftime(Sys.time(),started,units="secs")),
    numerical_qualification="path_jitter_1e-8_MQ_ridge_floor_1e-12_recorded_not_eliminated",
    monitor_qualification="kernel_historical_objective_labels_do_not_define_target_actual_future_Y_and_prior_flags_checked",
    inference_qualification="local_Gaussian_Delta_VB_not_exact_posterior_draws_or_credible_bands")
}

app_gft_verify_source_manifest <- function(path, expected_hash, root) {
  if (!identical(app_sha256_file(path),as.character(expected_hash))) app_gft_stop("Source manifest hash changed.")
  x <- app_read_csv(path)
  if (!all(c("path","role","mode","sha256","blob") %in% names(x)) ||
      !nrow(x) || anyDuplicated(x$path) || any(grepl("(^/|(^|/)\\.\\.(/|$))",x$path))) {
    app_gft_stop("Source inventory is incomplete or unsafe.")
  }
  for (i in seq_len(nrow(x))) {
    p <- file.path(root,x$path[i])
    if (!file.exists(p) || !identical(app_sha256_file(p),as.character(x$sha256[i]))) {
      app_gft_stop("Scientific source byte mismatch: ",x$path[i])
    }
  }
  x
}

app_gft_check_authorization <- function(request, authorization_path, authorization_sha256,
    source_root, now=Sys.time()) {
  if (!file.exists(authorization_path) || !identical(app_sha256_file(authorization_path),authorization_sha256)) {
    app_gft_stop("Missing or changed external launch authorization.")
  }
  auth_path <- normalizePath(authorization_path,mustWork=TRUE)
  if (startsWith(auth_path,paste0(normalizePath(source_root,mustWork=TRUE),"/"))) {
    app_gft_stop("Launch authorization must be external to the source worktree.")
  }
  auth <- app_gft_json(auth_path)
  if (!identical(auth$schema_version,"forecast_transition_authorization_v1") ||
      !isTRUE(auth$allow_launch) || !nzchar(as.character(auth$approved_by %||% ""))) {
    app_gft_stop("Production launch is disabled; explicit external approval is required.")
  }
  keys <- c("source_commit","source_tree","source_manifest_sha256","posterior_target_sha256",
    "input_manifest_sha256","task_manifest_sha256")
  for (key in keys) {
    width <- if (key %in% c("source_commit","source_tree")) 40L else 64L
    if (!identical(request[[key]],auth[[key]]) ||
        !grepl(sprintf("^[0-9a-f]{%d}$",width),as.character(request[[key]] %||% ""))) {
      app_gft_stop("Authorization identity does not match request: ",key)
    }
  }
  expiry <- as.POSIXct(as.character(auth$expires_utc %||% ""),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  if (is.na(expiry) || expiry <= now) app_gft_stop("Launch authorization expired.")
  if (!request$task_id %in% app_gft_values(auth$allowed_task_ids) ||
      !request$host %in% app_gft_values(auth$allowed_hosts) ||
      !"dispatch" %in% app_gft_values(auth$allowed_operations)) {
    app_gft_stop("Task, host or operation is outside authorization.")
  }
  for (name in c("max_threads","max_memory_mb","max_wall_seconds","max_output_bytes")) {
    value <- as.numeric(request$resource_budget[[name]] %||% NA_real_)
    if (length(value)!=1L || !is.finite(value) || value<=0) app_gft_stop("Missing finite resource budget: ",name)
  }
  if (as.numeric(request$resource_budget$max_threads) != 1L) app_gft_stop("Transition baseline uses one BLAS/inner worker thread.")
  auth
}

app_gft_verify_claim <- function(request_path, request, authorization_path,
    authorization_sha256, source_root, source_manifest_path) {
  actual_host <- strsplit(tolower(Sys.info()[["nodename"]]),".",fixed=TRUE)[[1L]][1L]
  if (!identical(actual_host,as.character(request$host)) && !identical(request$host,"hummingbird")) {
    app_gft_stop("Worker host does not match its immutable routed claim.")
  }
  if (identical(request$host,"hummingbird") &&
      (!nzchar(Sys.getenv("SLURM_JOB_ID")) || !nzchar(Sys.getenv("SLURM_JOB_NODELIST")) ||
        actual_host %in% c("muscat","jerez","hummingbird"))) {
    app_gft_stop("Hummingbird claim verification is restricted to an allocated compute node.")
  }
  ticket <- request$claim_ticket_path %||% ""
  if (!nzchar(ticket) || !file.exists(ticket) ||
      !identical(app_sha256_file(ticket),request$claim_ticket_sha256)) app_gft_stop("Missing or changed coordinator claim ticket.")
  ledger <- request$ledger_path %||% ""
  if (identical(request$host,"muscat") && !file.exists(ledger)) {
    app_gft_stop("Muscat coordinator ledger is unavailable; no remote SQLite replica is permitted.")
  }
  controller <- file.path(source_root,"application/scripts/forecast_transition_control.py")
  python <- as.character(request$controller_python %||% "/usr/bin/python3.11")
  if (!file.exists(controller) || !file.exists(python)) app_gft_stop("Qualified coordinator verifier is unavailable.")
  # A remote worker queries the qualified coordinator adapter, never a replica.
  # No remote action occurs until a later explicit external launch authorization.
  command <- if (identical(request$host,"muscat")) "verify-claim" else "verify-claim-remote"
  args <- c(shQuote(controller),command,"--ledger",shQuote(ledger),
    "--ticket",shQuote(ticket),"--ticket-sha256",request$claim_ticket_sha256,
    "--request",shQuote(request_path),"--authorization",shQuote(authorization_path),
    "--authorization-sha256",authorization_sha256,"--source-root",shQuote(source_root),
    "--source-manifest",shQuote(source_manifest_path))
  output <- system2(python,args,stdout=TRUE,stderr=TRUE)
  if (!is.null(attr(output,"status")) && attr(output,"status") != 0L) {
    app_gft_stop("Coordinator claim verification failed: ",paste(tail(output,5L),collapse=" "))
  }
  receipt <- jsonlite::fromJSON(paste(output,collapse="\n"),simplifyVector=FALSE)
  if (!isTRUE(receipt$verified) || !identical(receipt$schema_version,"forecast_transition_claim_verification_v1") ||
      !identical(receipt$task_id,request$task_id) || !identical(receipt$routing_id,request$routing_id) ||
      !identical(receipt$host,request$host)) app_gft_stop("Coordinator did not confirm this exact routed claim.")
  receipt
}

app_gft_output_namespace <- function(request, claim) {
  if (!isTRUE(claim$verified) || !identical(request$output_root,claim$output_root) ||
      !identical(request$task_id,claim$task_id) || !identical(request$routing_id,claim$routing_id) ||
      !identical(request$host,claim$host) || !is.character(claim$claim_nonce) ||
      length(claim$claim_nonce)!=1L || !grepl("^[0-9a-f]{48}$",claim$claim_nonce)) {
    app_gft_stop("OUTPUT_NAMESPACE: output directory is not bound to the exact verified ticket.")
  }
  app_gft_no_symlink_path(request$input_root)
  app_gft_no_symlink_path(request$output_root)
  input_root<-normalizePath(request$input_root,mustWork=TRUE)
  result_parent<-normalizePath(file.path(input_root,"results"),mustWork=TRUE)
  if (!startsWith(result_parent,paste0(input_root,"/"))) app_gft_stop("OUTPUT_NAMESPACE: results root escaped prepared inputs.")
  parent<-file.path(result_parent,request$task_id)
  expected<-file.path(parent,claim$claim_nonce)
  if (!identical(request$output_root,expected)) app_gft_stop("OUTPUT_NAMESPACE: ticket is outside its prepared task/nonce scope.")
  list(parent=parent,path=expected)
}

app_gft_verify_dependencies <- function(request, job) {
  ids <- if (nzchar(job$dependencies)) strsplit(job$dependencies,"|",fixed=TRUE)[[1L]] else character()
  entries <- request$prerequisites %||% list()
  if (!setequal(vapply(entries,function(x) as.character(x$task_id),character(1L)),ids) ||
      length(entries)!=length(ids)) app_gft_stop("Immutable prerequisite collection is incomplete or duplicated.")
  # The coordinator verifies accepted prerequisite identities; verify artifacts
  # again before loading a single fit. Reorder by the scientific DAG, not arrival.
  out <- lapply(ids,function(id) {
    e <- entries[[which(vapply(entries,function(x) identical(x$task_id,id),logical(1L)))]]
    if (!file.exists(e$fit_path) || !identical(app_sha256_file(e$fit_path),e$fit_sha256)) {
      app_gft_stop("Prerequisite fit hash mismatch: ",id)
    }
    x <- readRDS(e$fit_path)
    if (!identical(x$task_id,id) || !identical(x$identity$posterior_target_sha256,request$posterior_target_sha256) ||
        !identical(x$identity$input_manifest_sha256,request$input_manifest_sha256) ||
        !identical(x$identity$source_manifest_sha256,request$source_manifest_sha256) ||
        !isTRUE(x$converged)) app_gft_stop("Prerequisite is not an accepted, converged same-target result: ",id)
    x$fit
  })
  out
}

app_gft_output_usage <- function(root) {
  paths<-list.files(root,all.files=TRUE,no..=TRUE,recursive=TRUE,full.names=TRUE)
  if (!length(paths)) return(0)
  sum(as.numeric(file.info(paths)$size))
}
app_gft_output_headroom <- function(args, job) {
  # The live legacy CSV has a fixed numeric trace schema. Reserve generously
  # before entering the kernel; the dispatcher also enforces RLIMIT_FSIZE.
  iterations<-max(as.numeric(args$max_iter %||% 2000L),
    as.numeric(args$joint_outer_max_iter %||% 200L),as.numeric(args$joint_inner_max_iter %||% 60L))
  messages<-if (identical(as.character(job$model_class),"multiquantile"))
    as.numeric(args$joint_outer_max_iter %||% 200L)*7*
      as.numeric(args$joint_inner_max_iter %||% 60L) else iterations
  list(progress_bytes=65536+iterations*2048,
    runtime_log_bytes=max(16*1024^2,65536+messages*256),
    metadata_bytes=1024^2)
}
app_gft_output_precheck <- function(result, root, byte_limit, headroom) {
  reserve<-sum(unlist(headroom))
  projected<-4*as.numeric(object.size(result))+reserve+app_gft_output_usage(root)
  if (length(byte_limit)!=1L || !is.finite(byte_limit) || byte_limit<=0 || projected>byte_limit) {
    app_gft_stop("OUTPUT_BUDGET: conservative serialization/progress/log reservation exceeds the admitted cap; partial evidence retained.")
  }
  invisible(projected)
}
app_gft_bounded_write <- function(raw, path, root, byte_limit, reserve=0, replace=FALSE) {
  if (!is.raw(raw)) app_gft_stop("Bounded output writer requires explicit serialized bytes.")
  app_gft_no_symlink_path(path)
  parent<-normalizePath(dirname(path),mustWork=TRUE)
  normalized_root<-normalizePath(root,mustWork=TRUE)
  if (!identical(parent,normalized_root) && !startsWith(parent,paste0(normalized_root,"/"))) {
    app_gft_stop("Bounded output writer escaped its owned artifact root.")
  }
  exists<-file.exists(path)
  if (exists && !isTRUE(replace)) app_gft_stop("Refusing to overwrite an existing artifact.")
  old_size<-if (exists) as.numeric(file.info(path)$size) else 0
  projected<-app_gft_output_usage(root)-old_size+length(raw)+reserve
  if (!is.finite(projected) || projected>byte_limit) {
    app_gft_stop("OUTPUT_BUDGET: exact serialized bytes exceed remaining cap; previous partial evidence retained.")
  }
  tmp<-tempfile(paste0(basename(path),".partial_"),tmpdir=dirname(path))
  con<-file(tmp,"wb")
  tryCatch(writeBin(raw,con),finally=close(con))
  if (as.numeric(file.info(tmp)$size)!=length(raw)) app_gft_stop("Incomplete bounded output; partial file retained.")
  if (isTRUE(replace)) {
    if (!file.rename(tmp,path)) app_gft_stop("Could not atomically replace owned progress file; evidence retained.")
  } else {
    if (!file.link(tmp,path)) app_gft_stop("Could not create exclusive artifact; partial evidence retained.")
    unlink(tmp) # only this writer's byte-identical temporary hard link
  }
  if (app_gft_output_usage(root)+reserve>byte_limit) app_gft_stop("OUTPUT_BUDGET: exact artifact total exceeds cap; evidence retained.")
  invisible(path)
}
app_gft_csv_bytes <- function(x) {
  lines<-character()
  con<-textConnection("lines","w",local=TRUE)
  tryCatch(utils::write.csv(x,con,row.names=FALSE,na=""),finally=close(con))
  charToRaw(enc2utf8(paste0(paste(lines,collapse="\n"),"\n")))
}
app_gft_json_bytes <- function(x) charToRaw(enc2utf8(paste0(jsonlite::toJSON(x,
  auto_unbox=TRUE,pretty=TRUE,null="null",digits=17),"\n")))

app_glofas_family_transition_run_request <- function(request_path, authorization_path,
    authorization_sha256, source_root, dispatch_fields=list()) {
  if (!identical(as.character(getRversion()),"4.6.0")) app_gft_stop("Production transition worker requires pinned R 4.6.0.")
  request <- app_gft_json(request_path)
  allowed_dispatch <- c("claim_ticket_path","claim_ticket_sha256","ledger_path","controller_python")
  if (any(!names(dispatch_fields) %in% allowed_dispatch)) app_gft_stop("Unsupported operational worker override.")
  for (key in names(dispatch_fields)) request[[key]] <- dispatch_fields[[key]]
  if (!identical(request$schema_version,"glofas_family_transition_request_v1")) app_gft_stop("Unknown transition request schema.")
  if (!isTRUE(request$allow_launch) || !identical(request$workflow,"glofas_family_transition") ||
      !identical(request$authorization_sha256,authorization_sha256)) {
    app_gft_stop("NO_LAUNCH: a prepared template is not an authorized dispatch envelope.")
  }
  artifact_keys <- c("fit","forecast_quantiles","raw_crossings","target_receipt","artifact_manifest","progress")
  if (!setequal(app_gft_values(request$expected_output_keys),artifact_keys) ||
      !identical(request$expected_output_keys_sha256,app_gft_hash(sort(artifact_keys)))) {
    app_gft_stop("Controller artifact-key contract differs from the six actual outputs.")
  }
  app_gft_check_authorization(request,authorization_path,authorization_sha256,source_root)
  source_manifest <- as.character(request$source_manifest_path)
  app_gft_verify_source_manifest(source_manifest,request$source_manifest_sha256,source_root)
  source_head <- system2("git",c("-C",shQuote(source_root),"rev-parse","HEAD"),stdout=TRUE)
  source_tree <- system2("git",c("-C",shQuote(source_root),"rev-parse","HEAD^{tree}"),stdout=TRUE)
  if (!identical(source_head,request$source_commit) || !identical(source_tree,request$source_tree)) app_gft_stop("Source checkout is not the authorized immutable commit/tree.")
  input <- app_gft_verify_manifest(request$input_manifest_path,request$input_manifest_sha256,
    root=request$input_root)
  if (!identical(app_sha256_file(request$task_manifest_path),request$task_manifest_sha256)) app_gft_stop("Task manifest changed.")
  jobs <- app_read_csv(request$task_manifest_path)
  job <- jobs[jobs$task_id==request$task_id,,drop=FALSE]
  if (nrow(job)!=1L || !identical(job$rng_namespace[[1L]],request$rng_namespace)) app_gft_stop("Task/RNG identity is absent or ambiguous.")
  claim <- app_gft_verify_claim(request_path,request,authorization_path,authorization_sha256,source_root,source_manifest)
  output_namespace<-app_gft_output_namespace(request,claim)
  dependencies <- app_gft_verify_dependencies(request,job)
  # Nothing is loaded as an R object until source, target, data and claim checks pass.
  design <- readRDS(app_gft_bind_path(request$design_path,input,"truth_free_shared_design"))
  config <- readRDS(app_gft_bind_path(request$config_path,input,"transition_task_configuration"))
  if (!identical(config$task_id,request$task_id) ||
      !identical(config$posterior_target_sha256,request$posterior_target_sha256)) app_gft_stop("Configuration target identity mismatch.")
  root_initializer <- NULL
  if (!is.null(request$root_initializer_path) && nzchar(request$root_initializer_path)) {
    root_initializer <- readRDS(app_gft_bind_path(request$root_initializer_path,input,"compact_initial_moments"))
  }
  args <- app_glofas_family_transition_controls(config$vb_args,config$controls)
  # Any external feature lookup would invalidate the frozen recurrent map.
  engine_env <- environment(app_build_qdesn_design)
  saved_engine <- get("app_qdesn_engine_function",envir=engine_env,inherits=FALSE)
  on.exit(assign("app_qdesn_engine_function",saved_engine,envir=engine_env),add=TRUE)
  assign("app_qdesn_engine_function",function(...) app_gft_stop("Dynamic external feature lookup is prohibited."),envir=engine_env)
  backend <- app_latent_runtime_backend_manifest(fail_closed=TRUE)
  if (!dir.exists(output_namespace$parent) && !dir.create(output_namespace$parent,recursive=FALSE)) {
    app_gft_stop("Could not create the approved task parent directory.")
  }
  app_gft_no_symlink_path(output_namespace$parent)
  if (!identical(normalizePath(output_namespace$parent,mustWork=TRUE),output_namespace$parent)) {
    app_gft_stop("OUTPUT_NAMESPACE: task parent changed after authorization.")
  }
  output<-output_namespace$path
  if (file.exists(output) && length(list.files(output,all.files=TRUE,no..=TRUE))) app_gft_stop("Refusing to overwrite an existing task output.")
  app_ensure_dir(output)
  args$progress_path <- file.path(output,"progress.csv")
  args$progress_every <- 1L
  output_limit<-as.numeric(request$resource_budget$max_output_bytes)
  headroom<-app_gft_output_headroom(args,job)
  if (sum(unlist(headroom))>=output_limit) app_gft_stop("OUTPUT_BUDGET: progress/log headroom alone exceeds admitted cap.")
  app_write_csv(data.frame(phase="started_fresh_target",iteration=0L,
    utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")),args$progress_path)
  setTimeLimit(elapsed=as.numeric(request$resource_budget$max_wall_seconds),transient=FALSE)
  on.exit(setTimeLimit(cpu=Inf,elapsed=Inf,transient=FALSE),add=TRUE)
  result <- app_glofas_family_transition_fit(design,job,args,dependencies,root_initializer,
    seed=as.integer(config$seed),verified_execution=list(claim_verified=TRUE))
  # The old AL core has no live progress-file hook. Retain its complete final
  # trace here without pretending that an iteration-zero receipt is a heartbeat.
  progress <- if (job$model_class=="multiquantile") result$fit$trace else
    result$fit$vb_diagnostics$iteration_trace %||% data.frame(
      iteration=seq_along(result$fit$vb_diagnostics$elbo_trace),
      coordinate_monitor=result$fit$vb_diagnostics$elbo_trace,
      parameter_change=result$fit$vb_diagnostics$parameter_change_trace)
  if (as.numeric(file.info(args$progress_path)$size)>headroom$progress_bytes) {
    app_gft_stop("OUTPUT_BUDGET: legacy live progress exceeded its reserved allowance; evidence retained.")
  }
  identity_keys <- c("task_id","routing_id","rng_namespace","source_commit","source_tree",
    "source_manifest_sha256","posterior_target_sha256","input_manifest_sha256","task_manifest_sha256")
  result$identity <- request[identity_keys]
  result$authorization_sha256 <- authorization_sha256
  result$claim_ticket_sha256 <- request$claim_ticket_sha256
  result$claim_nonce <- claim$claim_nonce
  result$plan_sha256 <- request$plan_sha256
  result$prerequisite_artifacts <- request$prerequisites %||% list()
  result$root_initializer_sha256 <- if (!is.null(request$root_initializer_path) &&
    nzchar(request$root_initializer_path)) app_sha256_file(request$root_initializer_path) else NULL
  result$numerical_backend <- backend
  result$session_info <- capture.output(utils::sessionInfo())
  result$resource_budget <- request$resource_budget
  result$output_budget_headroom <- headroom
  result$memory_enforcement <- "qualified_dispatcher_OS_limit_or_Slurm_allocation_required_not_R_only"
  result$live_progress_qualification <- "kernel_dependent_AL_has_initial_and_terminal_receipts_not_live_iteration_hooks"
  result$request_sha256 <- app_sha256_file(request_path)
  expected_keys <- unlist(lapply(if (job$model_class=="multiquantile") app_glofas_family_transition_contract()$tau else job$tau,
    function(p) sprintf("%s|%02d|%.2f",job$task_id,seq_len(28L),p)))
  actual_keys <- sprintf("%s|%02d|%.2f",job$task_id,result$forecast_quantiles$horizon,result$forecast_quantiles$tau)
  if (anyDuplicated(actual_keys) || !setequal(expected_keys,actual_keys)) app_gft_stop("Worker output forecast keys are incomplete or duplicated.")
  result$scientific_output_keys <- expected_keys
  result$scientific_output_keys_sha256 <- app_gft_hash(sort(expected_keys))
  result$forecast_quantiles$task_id <- job$task_id
  app_gft_output_precheck(result,output,output_limit,headroom)
  # A raw serialization is sized exactly before a potentially large RDS write.
  # No connection can spill beyond the cap while discovering the object's size.
  fit_bytes<-serialize(result,NULL,ascii=FALSE,version=3L)
  app_gft_bounded_write(fit_bytes,file.path(output,"fit.rds"),output,output_limit,
    reserve=headroom$runtime_log_bytes+headroom$metadata_bytes+headroom$progress_bytes)
  rm(fit_bytes)
  app_gft_bounded_write(app_gft_csv_bytes(progress),args$progress_path,output,output_limit,
    reserve=headroom$runtime_log_bytes+headroom$metadata_bytes,replace=TRUE)
  app_gft_bounded_write(app_gft_csv_bytes(result$forecast_quantiles),file.path(output,"forecast_quantiles.csv"),
    output,output_limit,reserve=headroom$runtime_log_bytes+headroom$metadata_bytes)
  app_gft_bounded_write(app_gft_csv_bytes(result$raw_crossings),file.path(output,"raw_crossings.csv"),
    output,output_limit,reserve=headroom$runtime_log_bytes+headroom$metadata_bytes)
  receipt <- result[setdiff(names(result),c("fit","forecast_quantiles"))]
  app_gft_bounded_write(app_gft_json_bytes(receipt),file.path(output,"target_receipt.json"),
    output,output_limit,reserve=headroom$runtime_log_bytes+65536)
  paths <- file.path(output,c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json","progress.csv"))
  app_gft_bounded_write(app_gft_csv_bytes(app_gft_manifest(paths,rep("retained_transition_result",length(paths)),root=output)),
    file.path(output,"artifact_manifest.csv"),output,output_limit,reserve=headroom$runtime_log_bytes+65536)
  keys <- c("fit","forecast_quantiles","raw_crossings","target_receipt","progress","artifact_manifest")
  paths <- c(paths,file.path(output,"artifact_manifest.csv"))
  shards <- lapply(seq_along(paths),function(i) list(key=keys[i],relative_path=basename(paths[i]),
    bytes=as.numeric(file.info(paths[i])$size),sha256=app_sha256_file(paths[i]),
    posterior_target_sha256=request$posterior_target_sha256))
  acceptance <- c(list(schema_version="forecast_transition_output_v1",claim_nonce=claim$claim_nonce),
    request[identity_keys],list(expected_output_keys_sha256=request$expected_output_keys_sha256,
      numerical_gates_pass=isTRUE(result$converged),shards=shards))
  # Keep controller acceptance outside the exact artifact membership it authenticates.
  acceptance_bytes<-app_gft_json_bytes(acceptance)
  if (app_gft_output_usage(output)+length(acceptance_bytes)+headroom$runtime_log_bytes>output_limit) {
    app_gft_stop("OUTPUT_BUDGET: final artifact/sidecar/log total exceeds cap; evidence retained.")
  }
  sidecar<-paste0(output,".output_manifest.json")
  if (file.exists(sidecar)) app_gft_stop("Existing controller sidecar is immutable.")
  con<-file(sidecar,"wb");tryCatch(writeBin(acceptance_bytes,con),finally=close(con))
  if (app_gft_output_usage(output)+as.numeric(file.info(sidecar)$size)+headroom$runtime_log_bytes>output_limit) {
    app_gft_stop("OUTPUT_BUDGET: postwrite exact total exceeds cap; evidence retained.")
  }
  # Nonconverged evidence is retained, never silently accepted/promoted or resumed.
  if (!isTRUE(result$converged)) app_gft_stop("FIT_RETAINED_NOT_ACCEPTED: fresh-target convergence gates did not pass.")
  invisible(result)
}
