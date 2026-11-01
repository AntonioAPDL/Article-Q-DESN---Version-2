# Reporting-only enrollment of authentic, retained Gaussian GloFAS fits.
# This module never calls a feature builder, fitter, forecast sampler or scorer.
# It does not alter the stricter historical identical-reporting reuse helper.

app_gnr_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("Normal reuse enrollment: ", message), call. = FALSE)
  invisible(TRUE)
}

app_gnr_hash <- function(x) digest::digest(x, algo = "sha256", serialize = TRUE)

app_gnr_file_binding <- function(binding) {
  app_gnr_require(is.list(binding) && all(c("path", "size_bytes", "sha256") %in% names(binding)),
    "file requires path, size and SHA-256")
  app_gnr_require(is.character(binding$path) && length(binding$path) == 1L &&
    startsWith(binding$path, "/") && !grepl("(^|/)\\.\\.(/|$)", binding$path), "absolute regular input path")
  parts <- strsplit(binding$path, "/", fixed = TRUE)[[1L]]
  current <- "/"
  for (part in parts[nzchar(parts)]) {
    current <- file.path(current, part)
    link <- Sys.readlink(current)
    app_gnr_require(is.na(link) || !nzchar(link), "symlink input component")
  }
  info <- file.info(binding$path)
  app_gnr_require(nrow(info) == 1L && !is.na(info$size) && !isTRUE(info$isdir) &&
    is.numeric(binding$size_bytes) && length(binding$size_bytes) == 1L &&
    is.finite(binding$size_bytes) && binding$size_bytes > 0 &&
    identical(as.numeric(info$size), as.numeric(binding$size_bytes)), "input size mismatch")
  app_gnr_require(is.character(binding$sha256) && length(binding$sha256) == 1L &&
    grepl("^[0-9a-f]{64}$", binding$sha256) &&
    identical(unname(tools::sha256sum(binding$path)[[1L]]), binding$sha256), "input SHA-256 mismatch")
  list(path = normalizePath(binding$path, mustWork = TRUE),
    size_bytes = as.numeric(binding$size_bytes), sha256 = binding$sha256)
}

app_gnr_read_pinned_rds <- function(binding) {
  before <- app_gnr_file_binding(binding)
  object <- readRDS(before$path)
  after <- app_gnr_file_binding(binding)
  app_gnr_require(identical(before, after), "input changed while reading")
  structure(list(object = object, binding = before), class = "gnr_verified_rds")
}

# Compare closures by code and all local bindings, not pointer identity. No
# binding is evaluated through the function, and unknown environment geometry
# is rejected rather than silently discarded as a cache.
app_gnr_equal_value <- function(a, b, path = "design", depth = 0L) {
  app_gnr_require(depth < 60L, paste0("recursive or excessively deep input at ", path))
  if (is.function(a) || is.function(b)) {
    app_gnr_require(is.function(a) && is.function(b) &&
      identical(formals(a), formals(b)) && identical(body(a), body(b)), paste0("function code differs at ", path))
    ea <- environment(a); eb <- environment(b)
    app_gnr_require(!is.null(ea) && !is.null(eb), paste0("unsupported primitive at ", path))
    app_gnr_require(identical(sort(ls(ea, all.names = TRUE)), c("compiled", "context")) &&
      identical(sort(ls(eb, all.names = TRUE)), c("compiled", "context")),
      paste0("unexpected future-builder bindings at ", path))
    app_gnr_require(identical(parent.env(ea), globalenv()) &&
      identical(parent.env(eb), globalenv()), paste0("unexpected future-builder parent at ", path))
    app_gnr_equal_value(get("context", ea, inherits = FALSE), get("context", eb, inherits = FALSE),
      paste0(path, "$context"), depth + 1L)
    app_gnr_equal_value(get("compiled", ea, inherits = FALSE), get("compiled", eb, inherits = FALSE),
      paste0(path, "$compiled"), depth + 1L)
  } else if (is.environment(a) || is.environment(b)) {
    app_gnr_require(is.environment(a) && is.environment(b) &&
      identical(parent.env(a), emptyenv()) && identical(parent.env(b), emptyenv()),
      paste0("unexpected environment at ", path))
    keys <- sort(ls(a, all.names = TRUE))
    app_gnr_require(identical(keys, sort(ls(b, all.names = TRUE))), paste0("environment fields differ at ", path))
    for (key in keys) {
      app_gnr_require(!bindingIsActive(key, a) && !bindingIsActive(key, b), paste0("active binding at ", path))
      app_gnr_equal_value(get(key, a, inherits = FALSE), get(key, b, inherits = FALSE),
        paste0(path, "$", key), depth + 1L)
    }
  } else if (is.list(a) || is.list(b)) {
    app_gnr_require(is.list(a) && is.list(b) && identical(attributes(a), attributes(b)) &&
      length(a) == length(b), paste0("list structure differs at ", path))
    for (i in seq_along(a)) app_gnr_equal_value(a[[i]], b[[i]], paste0(path, "[[", i, "]]"), depth + 1L)
  } else app_gnr_require(identical(a, b), paste0("protected value differs at ", path))
  invisible(TRUE)
}

app_gnr_compare_designs <- function(original, prepared, expected_transition_contract) {
  app_gnr_require(is.list(original) && is.list(prepared) &&
    is.list(original$unit_member_contract) &&
    identical(original$unit_member_contract$schema_version, "glofas_unit_member_part4_v1"),
    "authentic unit-member source design required")
  app_gnr_require(is.list(expected_transition_contract) &&
    identical(expected_transition_contract$schema_version, "glofas_family_transition_v1") &&
    identical(prepared$family_transition_contract, expected_transition_contract), "prepared transition contract differs")
  app_gnr_require(is.null(prepared$unit_member_contract) &&
    identical(prepared$historical_unit_member_contract, original$unit_member_contract) &&
    identical(prepared$design_version, paste0(original$design_version, "__same_family_transition_v1")) &&
    is.null(attr(prepared, "future_probe_init")), "unapproved metadata mapping")
  app_gnr_require(is.null(original$historical_unit_member_contract) && is.null(original$family_transition_contract),
    "source already contains a transition mapping")
  metadata <- c("unit_member_contract", "historical_unit_member_contract", "family_transition_contract", "design_version")
  old <- original[setdiff(names(original), metadata)]
  new <- prepared[setdiff(names(prepared), metadata)]
  app_gnr_require(identical(names(old), names(new)), "protected design fields differ")
  old_attr <- attributes(original); new_attr <- attributes(prepared)
  old_attr$names <- new_attr$names <- NULL
  old_attr$future_probe_init <- new_attr$future_probe_init <- NULL
  app_gnr_require(identical(old_attr, new_attr), "unapproved design attributes differ")
  app_gnr_equal_value(old, new)
  # These small values are used by the subsequent fit audit without calling
  # the feature map. Whole-object file hashes are retained by the caller.
  app_gnr_require(identical(original$future_truth_policy,
    "physically_excluded_from_fit_objects_scoring_sidecar_only") &&
    all(original$weight_fixed == 1) &&
    all(c("Y", "G") %in% as.character(original$source_fixed)), "truth or weighting boundary differs")
  future <- original$future_key
  app_gnr_require(is.data.frame(future) && nrow(future) == 28L &&
    identical(as.integer(future$horizon), seq_len(28L)) &&
    !anyNA(as.Date(future$target_date)) && !anyDuplicated(as.Date(future$target_date)), "expected 28 unique future dates")
  list(schema_version = "glofas_normal_design_mapping_v2", status = "EXACT_PROTECTED_DESIGN_MATCH",
    exact_comparison = TRUE, mapping = c("unit_member_contract -> historical_unit_member_contract",
      "family_transition_contract added", "design_version suffix __same_family_transition_v1",
      "future_probe_init attribute removed"),
    protected_fields = names(old),
    # Do not serialize the multi-GB arrays again merely to add redundant
    # component digests. The pinned whole-file hashes and the complete exact
    # comparison above carry data identity; these small descriptors are for
    # readable inventory only and are never used as equality evidence.
    data_identity_evidence = "pinned_whole_file_SHA256_and_exact_all_protected_value_comparison",
    protected_component_structures = lapply(setdiff(names(old), "future_builder"), function(k) {
      x <- old[[k]]
      list(field = k, type = typeof(x), class = class(x), length = length(x), dimensions = dim(x))
    }),
    closure_code_sha256 = app_gnr_hash(list(formals(original$future_builder), body(original$future_builder))),
    closure_context_and_all_compiled_bindings_identical = TRUE,
    original_design_version = original$design_version, prepared_design_version = prepared$design_version,
    future_key = future, coefficient_columns = colnames(original$H_fixed),
    beta_index = original$beta_index, alpha_index = original$alpha_index,
    intercept_index = original$intercept_index,
    historical_Y = sum(as.character(original$source_fixed) == "Y"),
    historical_G = sum(as.character(original$source_fixed) == "G"),
    future_Y = 28L, future_G = 1428L,
    scoring_truth_read = FALSE, builder_calls = 0L, new_model_fits = 0L)
}

app_gnr_reporting_contract <- function() {
  list(schema_version = "glofas_normal_analytic_reporting_v1", tau = c(.05, .20, .35, .50, .65, .80, .95),
    horizons = 28L, response_factor = "full_ensemble_conditioned_q_U_Normal",
    transformed_quantile = "m_U_h+sqrt(V_U_hh)*qnorm(p)", inverse_transform = "expm1",
    extra_response_noise_added = FALSE, quantile_functional_credible_interval = FALSE,
    isotonic_adjustment = FALSE, historical_reporting = "latent_future_path_empirical_quantiles_type8",
    fit_reused = TRUE, new_model_fits = 0L, scoring_truth_read = FALSE)
}

app_gnr_response_quantiles <- function(core, dates, model) {
  contract <- app_gnr_reporting_contract()
  m <- as.numeric(core$summary$y_future_mean); V <- as.matrix(core$summary$y_future_cov)
  dates <- as.Date(dates)
  app_gnr_require(length(m) == 28L && identical(dim(V), c(28L, 28L)) &&
    length(dates) == 28L && !anyNA(dates) && !anyDuplicated(dates) &&
    all(is.finite(c(m, V))) && identical(V, t(V)) &&
    !inherits(try(chol(V), silent = TRUE), "try-error"), "invalid full Gaussian response factor")
  out <- do.call(rbind, lapply(contract$tau, function(p) {
    q <- m + sqrt(diag(V)) * qnorm(p)
    data.frame(model = model, target_date = as.character(dates), horizon = seq_len(28L), tau = p,
      quantile_transformed = q, quantile = expm1(q), path_factor_mean = m,
      path_factor_sd = sqrt(diag(V)),
      estimand = "marginal_future_response_quantile_under_ensemble_conditioned_VB",
      approximation = "Gaussian_path_factor_with_local_Delta_and_coefficient_factorization",
      extra_response_noise_added = FALSE, quantile_functional_credible_interval = FALSE,
      fit_reused = TRUE, stringsAsFactors = FALSE)
  }))
  app_gnr_require(nrow(out) == 196L && !anyDuplicated(paste(out$target_date, out$tau)) &&
    all(is.finite(c(out$quantile_transformed, out$quantile))), "invalid 28-by-seven reporting grid")
  out
}

app_gnr_enroll_fit <- function(verified_fit, design_identity, original_design_binding,
    config, model_grid, target_receipt, runtime_receipt, expected) {
  app_gnr_require(inherits(verified_fit, "gnr_verified_rds") &&
    identical(design_identity$status, "EXACT_PROTECTED_DESIGN_MATCH") &&
    isTRUE(design_identity$exact_comparison), "verified fit and exact design mapping required")
  object <- verified_fit$object; core <- object$fit
  app_gnr_require(expected$model %in% c("normal_ridge", "normal_rhs") &&
    is.character(expected$source_commit) && grepl("^[0-9a-f]{40}$", expected$source_commit) &&
    is.character(expected$state_contract_hash) && grepl("^[0-9a-f]{64}$", expected$state_contract_hash),
    "explicit original fit/source identity required")
  prior <- if (expected$model == "normal_ridge") "ridge" else "rhs_ns"
  app_gnr_require(identical(object$status, "completed") && identical(core$method, "vb") &&
    identical(core$likelihood_family, "normal") && identical(core$prior, prior) &&
    identical(object$coefficient_prior, prior) && identical(object$state_contract_hash, expected$state_contract_hash) &&
    identical(object$shared_design_reference$state_contract_hash, expected$state_contract_hash) &&
    identical(object$shared_design_reference$sha256, original_design_binding$sha256), "retained fit identity differs")
  grid <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  app_gnr_require(nrow(grid) == 7L && identical(sort(as.numeric(grid$quantile_level)), app_gnr_reporting_contract()$tau) &&
    all(grid$likelihood_family == "normal") &&
    all(grid$coefficient_prior %in% if (prior == "ridge") "ridge" else c("rhs", "rhs_ns")) &&
    all(grid$model_id == object$model_id) && !anyDuplicated(grid$fit_id) &&
    identical(as.character(grid$fit_id), paste0(object$model_id, "_p", sprintf("%02d", round(100 * grid$quantile_level)))) &&
    all(as.integer(grid$reservoir_seed) == as.integer(config$reservoir$seed)) &&
    identical(as.character(grid$fit_id[1L]), object$fit_id),
    "original model grid differs")
  shared_columns <- setdiff(names(grid), c("fit_id", "quantile_level"))
  app_gnr_require(all(vapply(shared_columns, function(k) all(vapply(seq_len(nrow(grid)),
    function(i) identical(grid[[k]][i], grid[[k]][1L]), logical(1L))), logical(1L))),
    "probability levels do not share the original Gaussian specification")
  args <- app_make_qdesn_discrepancy_vb_args(config, prior = prior,
    seed = as.integer(grid$reservoir_seed[1L]), likelihood_family = "normal")
  args <- app_glofas_unit_member_vb_controls(args, config)
  diag <- core$vb_diagnostics; state <- core$variational_state
  if (identical(diag$initialization$type, "cold")) args$freeze_beta_warmup_iters <- 0L
  app_gnr_require(is.null(args$future_gaussian_prior) && is.null(args$prior_addition) &&
    is.null(state$prior$prior_addition) && length(state$prior$prior_linear) == length(state$theta_mean) &&
    all(state$prior$prior_linear == 0), "additional prior is not authorized")
  p <- length(design_identity$coefficient_columns)
  expected_prior <- app_latent_prior_state_init(p, prior, design_identity$intercept_index, args,
    design_identity$beta_index, design_identity$alpha_index)
  app_gnr_require(identical(state$prior$prior, expected_prior$prior) &&
    identical(state$prior$intercept_index, expected_prior$intercept_index), "coefficient prior structure differs")
  app_gnr_require(all(is.finite(state$prior$prior_precision)) &&
    identical(state$prior$prior_precision[design_identity$intercept_index],
      expected_prior$prior_precision[design_identity$intercept_index]), "intercept prior differs")
  if (prior == "ridge") {
    app_gnr_require(identical(state$prior$prior_precision, expected_prior$prior_precision), "ridge prior differs")
  } else for (block in c("beta", "alpha")) {
    a <- state$prior$blocks[[block]]; b <- expected_prior$blocks[[block]]
    app_gnr_require(identical(a$global_index, b$global_index), "RHS block coordinates differ")
    keys <- c("prior", "penalized", "intercept_index", "intercept_prec", "tau0", "a_zeta", "b_zeta",
      "zeta2_fixed", "update_zeta", "rhs_control")
    app_gnr_require(identical(a$state[keys], b$state[keys]), "RHS hyperparameters differ")
    s <- a$state
    app_gnr_require(isTRUE(s$has_post_warmup_tau_update) &&
      s$tau_update_count >= s$rhs_control$min_tau_updates &&
      s$first_tau_update_iter > s$rhs_control$freeze_tau_warmup_iters &&
      s$last_tau_update_iter <= diag$iterations, "RHS release gate not satisfied")
  }
  trace <- diag$iteration_trace
  app_gnr_require(isTRUE(diag$converged) && isTRUE(tail(trace$convergence_eligible, 1L)) &&
    nrow(trace) == diag$iterations && diag$iterations >= args$min_iter_elbo && diag$iterations <= args$max_iter &&
    identical(as.integer(diag$freeze_beta_warmup_iters), as.integer(args$freeze_beta_warmup_iters)) &&
    diag$beta_update_count >= args$min_beta_updates &&
    diag$beta_update_count == diag$iterations - diag$freeze_beta_warmup_iters &&
    is.finite(tail(trace$parameter_change, 1L)) && tail(trace$parameter_change, 1L) < args$tol &&
    identical(diag$ensemble_weight_contract, "each_included_member_weight_one") &&
    identical(diag$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only") &&
    isTRUE(diag$normal_exact_optimization) && identical(diag$objective_type, "normal_mean_field_expected_log_joint"),
    "original convergence or numerical controls fail")
  target_fields <- c("schema_version", "policy", "horizons", "members", "job_id", "family",
    "shared_design_sha256", "state_contract_hash", "future_path_prior_hash", "future_truth_used_in_fit",
    "included_historical_Y", "included_historical_G", "included_future_Y", "included_issued_G",
    "quantile_blocks", "included_issued_G_across_blocks")
  app_gnr_require(all(target_fields %in% names(target_receipt)) &&
    identical(target_receipt$schema_version, "glofas_unit_member_part4_v1") &&
    identical(target_receipt$policy, "unit_member_likelihood_v1") &&
    target_receipt$horizons == 28L && target_receipt$members == 51L &&
    identical(target_receipt$family,
    if (prior == "ridge") "normal_ridge_diagnostic" else "normal_rhs_vb_diagnostic") &&
    identical(target_receipt$shared_design_sha256, original_design_binding$sha256) &&
    identical(target_receipt$state_contract_hash, expected$state_contract_hash) &&
    is.null(target_receipt$future_path_prior_hash) && identical(target_receipt$future_truth_used_in_fit, FALSE) &&
    target_receipt$included_historical_Y == design_identity$historical_Y &&
    target_receipt$included_historical_G == design_identity$historical_G &&
    target_receipt$included_future_Y == 28L && target_receipt$included_issued_G == 1428L &&
    target_receipt$quantile_blocks == 1L && target_receipt$included_issued_G_across_blocks == 1428L,
    "original executed Normal target differs")
  expected_shape <- args$prior_sigma$a + .5 * c(design_identity$historical_Y + 28L,
    design_identity$historical_G + 1428L)
  app_gnr_require(identical(unname(as.numeric(state$sigma$shape)), expected_shape) &&
    all(is.finite(c(state$sigma$rate, state$sigma$mean))) && all(state$sigma$rate > args$prior_sigma$b),
    "Normal variance target/counts differ")
  app_gnr_require(is.data.frame(runtime_receipt) && nrow(runtime_receipt) == 1L &&
    identical(as.character(runtime_receipt$job_id), target_receipt$job_id) &&
    identical(as.character(runtime_receipt$source_head), expected$source_commit) &&
    isTRUE(as.logical(runtime_receipt$backend_verified)) &&
    identical(as.logical(runtime_receipt$engine_source_dirty), FALSE) &&
    identical(as.character(runtime_receipt$backend), "bundled_rblas") &&
    identical(as.character(runtime_receipt$ld_preload), "") &&
    all(as.character(unlist(runtime_receipt[c("omp_num_threads", "openblas_num_threads", "mkl_num_threads")])) == "1"),
    "original numerical runtime identity differs")
  app_gnr_require(length(core$summary$theta_mean) == p &&
    identical(dim(core$summary$theta_cov), c(p, p)) &&
    all(vapply(core$summary, function(x) is.numeric(x) && all(is.finite(x)), logical(1L))) &&
    identical(core$summary$y_future_mean, state$y_future_mean) &&
    identical(core$summary$y_future_cov, state$y_future_cov), "retained summary/state moments differ")
  rows <- app_gnr_response_quantiles(core, design_identity$future_key$target_date, expected$model)
  reporting <- app_gnr_reporting_contract()
  target <- list(family = "normal", reference_future_law = "one_normalized_Normal_Y_factor_per_horizon",
    product_location = "reference_readout_plus_discrepancy_readout", ensemble_weight = 1L,
    historical_Y = design_identity$historical_Y, historical_G = design_identity$historical_G,
    future_Y = 28L, future_G = 1428L, prior_specification = expected_prior,
    prior_sigma = args$prior_sigma)
  list(receipt = list(schema_version = "glofas_normal_reuse_enrollment_v1",
    status = "FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED", model = expected$model,
    fit_reused = TRUE, new_model_fits = 0L, model_calls = 0L, builder_calls = 0L,
    scoring_truth_read = FALSE, original_fit = verified_fit$binding,
    original_source_commit = expected$source_commit, original_state_contract_hash = expected$state_contract_hash,
    original_backend = as.character(runtime_receipt$backend), original_runtime = runtime_receipt,
    original_design = original_design_binding, design_mapping_sha256 = app_gnr_hash(design_identity),
    fit_target_sha256 = app_gnr_hash(target), original_target_receipt_sha256 = app_gnr_hash(target_receipt),
    original_configuration_sha256 = app_gnr_hash(config), effective_controls = args,
    effective_controls_sha256 = app_gnr_hash(args), original_prior_state_sha256 = app_gnr_hash(state$prior),
    original_diagnostics_sha256 = app_gnr_hash(diag), original_moment_sha256 = lapply(core$summary, app_gnr_hash),
    old_reporting = reporting$historical_reporting, new_reporting = reporting,
    new_reporting_sha256 = app_gnr_hash(reporting), reporting_rows_sha256 = app_gnr_hash(rows),
    expected_rows = 196L, raw_crossings = 0L, article_publication_authorized = FALSE), rows = rows)
}
