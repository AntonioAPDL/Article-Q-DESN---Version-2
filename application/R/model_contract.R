# Application-model contracts for the GloFAS Q-DESN workflow.

app_application_model_contracts <- function() {
  c("origin_state_bridge", "latent_path_ensemble_likelihood")
}

app_application_model_contract <- function(cfg, model_row = NULL) {
  contract <- cfg$application_model$contract %||% NULL
  if (!is.null(model_row) && "application_model_contract" %in% names(model_row)) {
    row_contract <- as.character(model_row$application_model_contract[[1L]])
    if (nzchar(row_contract)) contract <- row_contract
  }
  if (is.null(contract)) {
    contract <- "origin_state_bridge"
  }
  contract <- tolower(as.character(contract[[1L]]))
  aliases <- c(
    origin_state = "origin_state_bridge",
    origin_state_calibration = "origin_state_bridge",
    bridge = "origin_state_bridge",
    latent_path = "latent_path_ensemble_likelihood",
    ensemble_likelihood = "latent_path_ensemble_likelihood",
    joint_ensemble_likelihood = "latent_path_ensemble_likelihood"
  )
  if (contract %in% names(aliases)) contract <- aliases[[contract]]
  if (!contract %in% app_application_model_contracts()) {
    stop(sprintf(
      "Unsupported application model contract '%s'. Supported contracts are: %s.",
      contract,
      paste(app_application_model_contracts(), collapse = ", ")
    ), call. = FALSE)
  }
  contract
}

app_is_latent_path_contract <- function(cfg, model_row = NULL) {
  identical(app_application_model_contract(cfg, model_row), "latent_path_ensemble_likelihood")
}

app_application_model_contract_row <- function(cfg, model_row = NULL) {
  contract <- app_application_model_contract(cfg, model_row)
  likelihood_family <- app_model_row_likelihood_family(model_row %||% data.frame(), cfg)
  has_gamma <- identical(tolower(likelihood_family), "exal")
  data.frame(
    application_model_contract = contract,
    likelihood_family = likelihood_family,
    future_reference_path = if (identical(contract, "latent_path_ensemble_likelihood")) "latent_missing_path" else "not_in_model",
    issued_glofas_role = if (identical(contract, "latent_path_ensemble_likelihood")) "likelihood_rows" else "prediction_or_bridge_input",
    glofas_scale_scope = if (identical(contract, "latent_path_ensemble_likelihood")) "retrospective_and_issued_glofas" else "fitted_glofas_rows",
    glofas_asymmetry_scope = if (has_gamma && identical(contract, "latent_path_ensemble_likelihood")) "retrospective_and_issued_glofas" else if (has_gamma) "fitted_glofas_rows" else NA_character_,
    stringsAsFactors = FALSE
  )
}

app_validate_application_model_contract <- function(cfg, model_row = NULL) {
  contract <- app_application_model_contract(cfg, model_row)
  pred <- cfg$prediction %||% list()
  if (identical(contract, "latent_path_ensemble_likelihood")) {
    qsrc <- as.character(pred$q_g_source %||% "posterior_model_quantile")[[1L]]
    if (!identical(qsrc, "posterior_model_quantile")) {
      stop(
        paste(
          "latent_path_ensemble_likelihood requires prediction.q_g_source =",
          "'posterior_model_quantile', because issued GloFAS ensemble members",
          "enter the likelihood rather than only an empirical post-fit quantile."
        ),
        call. = FALSE
      )
    }
    unit <- as.character(pred$prediction_unit %||% "posterior_draw")[[1L]]
    if (!identical(unit, "posterior_draw")) {
      stop("latent_path_ensemble_likelihood requires prediction.prediction_unit = 'posterior_draw'.", call. = FALSE)
    }
  }
  invisible(contract)
}

app_qdesn_model_rows <- function(model_grid, enabled_only = TRUE) {
  rows <- model_grid[
    model_grid$model_family %in% c("qdesn_reference_only", "qdesn_glofas_discrepancy"),
    ,
    drop = FALSE
  ]
  if (enabled_only && nrow(rows) && "enabled" %in% names(rows)) {
    rows <- rows[app_as_bool_vec(rows$enabled), , drop = FALSE]
  }
  rows
}

app_config_reservoir_seed <- function(cfg) {
  seed <- suppressWarnings(as.integer((cfg$reservoir %||% list())$seed %||% NA_integer_))
  if (length(seed) == 0L || !is.finite(seed[[1L]])) return(NA_integer_)
  as.integer(seed[[1L]])
}

app_model_row_reservoir_seed <- function(model_row, cfg) {
  row_seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", NA_integer_)))
  cfg_seed <- app_config_reservoir_seed(cfg)
  if (length(row_seed) && is.finite(row_seed[[1L]])) return(as.integer(row_seed[[1L]]))
  cfg_seed
}

app_qdesn_two_block_design <- function(cfg) {
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  version <- as.character(fc$version %||% "0.1")[[1L]]
  identical(version, "0.3") || isTRUE(fc$two_block_design %||% FALSE)
}

app_qdesn_discrepancy_seed_offset <- function(cfg) {
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  blocks <- fc$blocks %||% list()
  disc <- blocks$discrepancy %||% list()
  offset <- suppressWarnings(as.integer(disc$reservoir_seed_offset %||% fc$discrepancy_reservoir_seed_offset %||% 1009L))
  if (!is.finite(offset)) offset <- 1009L
  as.integer(offset)
}

app_qdesn_deep_merge <- function(base, override) {
  if (is.null(override) || !length(override)) return(base)
  if (is.null(base) || !is.list(base) || !is.list(override)) return(override)
  utils::modifyList(base, override, keep.null = TRUE)
}

app_qdesn_block_override <- function(cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  fc <- cfg$feature_contract %||% cfg$features %||% list()
  override <- (fc$blocks %||% list())[[block]] %||% list()
  if (!is.list(override)) {
    stop(sprintf("feature_contract.blocks.%s must be a mapping.", block), call. = FALSE)
  }
  override
}

app_qdesn_block_config <- function(cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  override <- app_qdesn_block_override(cfg, block)
  out <- cfg
  out$reservoir <- app_qdesn_deep_merge(
    cfg$reservoir %||% list(),
    override[["reservoir"]] %||% list()
  )

  fc_name <- if (!is.null(cfg$feature_contract)) "feature_contract" else if (!is.null(cfg$features)) "features" else "feature_contract"
  fc <- cfg[[fc_name]] %||% list()
  fc$reservoir_input <- app_qdesn_deep_merge(
    fc$reservoir_input %||% list(),
    override[["reservoir_input"]] %||% list()
  )
  fc$readout <- app_qdesn_deep_merge(
    fc$readout %||% list(),
    override[["readout"]] %||% list()
  )
  out[[fc_name]] <- fc
  out$.__qdesn_block__ <- block
  out
}

app_qdesn_validate_reservoir_spec <- function(reservoir, label = "reservoir") {
  if (!is.list(reservoir)) stop(sprintf("%s must be a mapping.", label), call. = FALSE)
  D <- suppressWarnings(as.integer(reservoir$D %||% 1L))
  if (length(D) != 1L || !is.finite(D) || D < 1L) {
    stop(sprintf("%s.D must be one positive integer.", label), call. = FALSE)
  }
  check_length <- function(name, allowed) {
    value <- unlist(reservoir[[name]] %||% numeric(), use.names = FALSE)
    if (length(value) && !(length(value) %in% allowed)) {
      stop(sprintf(
        "%s.%s must have length %s for D=%d; observed length %d.",
        label,
        name,
        paste(allowed, collapse = " or "),
        D,
        length(value)
      ), call. = FALSE)
    }
    invisible(value)
  }
  n <- check_length("n", c(1L, D))
  n_tilde_allowed <- if (D == 1L) c(0L, 1L) else c(1L, D - 1L)
  n_tilde <- check_length("n_tilde", n_tilde_allowed)
  for (name in c("alpha", "rho", "pi_w", "pi_in")) check_length(name, c(1L, D))
  if (length(n) && any(!is.finite(as.numeric(n)) | as.numeric(n) < 1)) {
    stop(sprintf("%s.n must contain positive finite values.", label), call. = FALSE)
  }
  if (length(n_tilde) && any(!is.finite(as.numeric(n_tilde)) | as.numeric(n_tilde) < 1)) {
    stop(sprintf("%s.n_tilde must contain positive finite values.", label), call. = FALSE)
  }
  alpha <- as.numeric(unlist(reservoir$alpha %||% numeric(), use.names = FALSE))
  if (length(alpha) && any(!is.finite(alpha) | alpha <= 0 | alpha > 1)) {
    stop(sprintf("%s.alpha must lie in (0, 1].", label), call. = FALSE)
  }
  rho <- as.numeric(unlist(reservoir$rho %||% numeric(), use.names = FALSE))
  if (length(rho) && any(!is.finite(rho) | rho < 0)) {
    stop(sprintf("%s.rho must be nonnegative and finite.", label), call. = FALSE)
  }
  for (name in c("pi_w", "pi_in")) {
    value <- as.numeric(unlist(reservoir[[name]] %||% numeric(), use.names = FALSE))
    if (length(value) && any(!is.finite(value) | value < 0 | value > 1)) {
      stop(sprintf("%s.%s must lie in [0, 1].", label, name), call. = FALSE)
    }
  }
  invisible(TRUE)
}

app_qdesn_validate_block_configs <- function(cfg) {
  for (block in c("reference", "discrepancy")) {
    block_cfg <- app_qdesn_block_config(cfg, block)
    app_qdesn_validate_reservoir_spec(block_cfg$reservoir, sprintf("%s reservoir", block))
  }
  invisible(TRUE)
}

app_qdesn_hash_object <- function(x, prefix = "qdesn_contract_") {
  path <- tempfile(prefix, fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path, version = 2L)
  app_sha256_file(path)
}

app_qdesn_normalize_rhs_alpha_grouping <- function(vb_cfg = list()) {
  raw <- vb_cfg$rhs_alpha_grouping %||% list(enabled = FALSE)
  if (is.logical(raw) && length(raw) == 1L) raw <- list(enabled = raw)
  if (!is.list(raw)) {
    stop("inference.vb_ld.rhs_alpha_grouping must be a mapping or one logical value.", call. = FALSE)
  }
  unknown <- setdiff(names(raw), c("enabled", "mode", "tau0"))
  if (length(unknown)) {
    stop(sprintf(
      "rhs_alpha_grouping contains unsupported fields: %s.",
      paste(unknown, collapse = ", ")
    ), call. = FALSE)
  }
  enabled <- app_as_bool(raw$enabled %||% FALSE)
  mode <- tolower(as.character(raw$mode %||% "direct_reservoir")[[1L]])
  if (!mode %in% c("direct_reservoir")) {
    stop(sprintf("Unsupported RHS alpha grouping mode '%s'.", mode), call. = FALSE)
  }
  if (!enabled) {
    return(list(
      schema_version = "qdesn_rhs_alpha_grouping_v1",
      enabled = FALSE,
      mode = "legacy_single",
      tau0 = numeric()
    ))
  }
  tau0 <- raw$tau0 %||% list()
  if (!is.list(tau0) || is.null(names(tau0))) {
    stop("Enabled RHS alpha grouping requires named tau0 values.", call. = FALSE)
  }
  required <- c("direct", "reservoir")
  missing <- setdiff(required, names(tau0))
  extra <- setdiff(names(tau0), required)
  if (length(missing) || length(extra)) {
    stop(sprintf(
      "Grouped alpha tau0 must contain exactly direct and reservoir (missing: %s; extra: %s).",
      paste(missing, collapse = ", "), paste(extra, collapse = ", ")
    ), call. = FALSE)
  }
  values <- stats::setNames(
    vapply(required, function(name) as.numeric(tau0[[name]])[[1L]], numeric(1L)),
    required
  )
  if (any(!is.finite(values) | values <= 0)) {
    stop("Every grouped alpha tau0 value must be finite and positive.", call. = FALSE)
  }
  list(
    schema_version = "qdesn_rhs_alpha_grouping_v1",
    enabled = TRUE,
    mode = mode,
    tau0 = values
  )
}

app_qdesn_alpha_rhs_group_layout <- function(feature_info, intercept_index, grouping) {
  grouping <- grouping %||% list(enabled = FALSE)
  if (!isTRUE(grouping$enabled)) return(NULL)
  if (!is.data.frame(feature_info) || !nrow(feature_info)) {
    stop("Grouped alpha RHS requires nonempty semantic feature metadata.", call. = FALSE)
  }
  required <- c("column_index", "column_name", "block", "variable", "is_intercept")
  missing <- setdiff(required, names(feature_info))
  if (length(missing)) {
    stop(sprintf(
      "Grouped alpha feature metadata is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  p <- nrow(feature_info)
  column_index <- as.integer(feature_info$column_index)
  if (!identical(column_index, seq_len(p)) || anyDuplicated(feature_info$column_name)) {
    stop("Grouped alpha feature metadata must be ordered, contiguous, and uniquely named.", call. = FALSE)
  }
  semantic_intercept <- which(
    app_as_bool_vec(feature_info$is_intercept) |
      as.character(feature_info$block) == "readout_intercept"
  )
  intercept_index <- sort(unique(as.integer(intercept_index %||% integer())))
  if (!identical(intercept_index, as.integer(semantic_intercept))) {
    stop("Grouped alpha intercept indices disagree with semantic feature metadata.", call. = FALSE)
  }
  block <- as.character(feature_info$block)
  direct_blocks <- c("direct_output_lag", "direct_covariate_lag", "horizon")
  reservoir_blocks <- c("reservoir_state", "reservoir_state_lag")
  groups <- list(
    direct = which(block %in% direct_blocks & !(seq_len(p) %in% intercept_index)),
    reservoir = which(block %in% reservoir_blocks & !(seq_len(p) %in% intercept_index))
  )
  if (any(vapply(groups, length, integer(1L)) == 0L)) {
    empty <- names(groups)[vapply(groups, length, integer(1L)) == 0L]
    stop(sprintf("Grouped alpha layout has empty groups: %s.", paste(empty, collapse = ", ")), call. = FALSE)
  }
  penalized <- setdiff(seq_len(p), intercept_index)
  assigned <- unlist(groups, use.names = FALSE)
  if (anyDuplicated(assigned) || !identical(sort(assigned), penalized)) {
    unknown <- setdiff(penalized, assigned)
    stop(sprintf(
      "Grouped alpha layout is not an exact partition; unassigned blocks: %s.",
      paste(unique(block[unknown]), collapse = ", ")
    ), call. = FALSE)
  }
  group_name <- rep("intercept", p)
  for (name in names(groups)) group_name[groups[[name]]] <- name
  metadata <- data.frame(
    column_index = column_index,
    column_name = as.character(feature_info$column_name),
    block = block,
    variable = as.character(feature_info$variable),
    is_intercept = seq_len(p) %in% intercept_index,
    rhs_global_group = group_name,
    stringsAsFactors = FALSE
  )
  hash_input <- list(
    schema_version = "qdesn_rhs_alpha_group_layout_v1",
    mode = grouping$mode,
    p = p,
    intercept_index = intercept_index,
    groups = groups,
    metadata = metadata
  )
  list(
    schema_version = "qdesn_rhs_alpha_group_layout_v1",
    enabled = TRUE,
    mode = grouping$mode,
    p = p,
    penalized = penalized,
    intercept_index = intercept_index,
    groups = groups,
    tau0 = grouping$tau0,
    metadata = metadata,
    layout_hash = app_qdesn_hash_object(hash_input, prefix = "qdesn_rhs_alpha_layout_")
  )
}

app_qdesn_latent_vb_prior_contract <- function(vb_args, alpha_layout = NULL) {
  beta <- vb_args$beta_rhs %||% list()
  alpha <- vb_args$alpha_rhs %||% list()
  grouping <- alpha$global_grouping %||% list(enabled = FALSE, mode = "legacy_single")
  declared <- list(
    schema_version = "qdesn_latent_vb_prior_declared_v1",
    beta = list(
      tau0 = as.numeric(beta$tau0), slab_s2 = as.numeric(beta$s2),
      a_zeta = as.numeric(beta$a_zeta), b_zeta = as.numeric(beta$b_zeta),
      intercept_prec = as.numeric(beta$intercept_prec)
    ),
    alpha = list(
      tau0 = as.numeric(alpha$tau0), slab_s2 = as.numeric(alpha$s2),
      a_zeta = as.numeric(alpha$a_zeta), b_zeta = as.numeric(alpha$b_zeta),
      intercept_prec = as.numeric(alpha$intercept_prec), grouping = grouping
    )
  )
  effective_alpha <- if (isTRUE(grouping$enabled)) {
    list(
      prior = "grouped_rhs_ns",
      global_tau0 = grouping$tau0,
      local_lambda_hierarchy = TRUE,
      shared_dynamic_zeta = list(a_zeta = as.numeric(alpha$a_zeta), b_zeta = as.numeric(alpha$b_zeta)),
      intercept_prec = as.numeric(alpha$intercept_prec),
      group_layout_hash = alpha_layout$layout_hash %||% NA_character_
    )
  } else {
    list(
      prior = "rhs_ns",
      global_tau0 = as.numeric(alpha$tau0),
      local_lambda_hierarchy = TRUE,
      shared_dynamic_zeta = list(a_zeta = as.numeric(alpha$a_zeta), b_zeta = as.numeric(alpha$b_zeta)),
      intercept_prec = as.numeric(alpha$intercept_prec)
    )
  }
  effective <- list(
    schema_version = "qdesn_latent_vb_prior_effective_v1",
    beta = list(
      prior = "rhs_ns", global_tau0 = as.numeric(beta$tau0),
      local_lambda_hierarchy = TRUE,
      dynamic_zeta = list(a_zeta = as.numeric(beta$a_zeta), b_zeta = as.numeric(beta$b_zeta)),
      intercept_prec = as.numeric(beta$intercept_prec)
    ),
    alpha = effective_alpha
  )
  ledger <- data.frame(
    field = c(
      "beta.tau0", "beta.slab_s2", "beta.a_zeta", "beta.b_zeta",
      "alpha.tau0", "alpha.slab_s2", "alpha.a_zeta", "alpha.b_zeta",
      "alpha.grouping"
    ),
    operative = c(TRUE, FALSE, TRUE, TRUE, !isTRUE(grouping$enabled), FALSE, TRUE, TRUE, isTRUE(grouping$enabled)),
    reason = c(
      "beta global RHS scale", "accepted legacy metadata; not consumed by latent-path VB",
      "beta dynamic regularization", "beta dynamic regularization",
      if (isTRUE(grouping$enabled)) "replaced by grouped alpha tau0 values" else "alpha global RHS scale",
      "accepted legacy metadata; not consumed by latent-path VB",
      "shared alpha dynamic regularization", "shared alpha dynamic regularization",
      if (isTRUE(grouping$enabled)) "direct/reservoir global RHS scales" else "legacy single alpha scale"
    ),
    stringsAsFactors = FALSE
  )
  list(
    schema_version = "qdesn_latent_vb_prior_contract_v1",
    declared = declared,
    effective = effective,
    declared_hash = app_qdesn_hash_object(declared, prefix = "qdesn_prior_declared_"),
    effective_hash = app_qdesn_hash_object(effective, prefix = "qdesn_prior_effective_"),
    field_ledger = ledger
  )
}

app_qdesn_block_config_hash <- function(cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  block_cfg <- app_qdesn_block_config(cfg, block)
  contract <- app_feature_contract(block_cfg)
  app_qdesn_hash_object(list(
    block = block,
    reservoir = block_cfg$reservoir,
    reservoir_input = contract$reservoir_input,
    readout = contract$readout,
    forecast_alignment = contract$forecast_alignment
  ))
}

app_qdesn_common_washout <- function(cfg, drop = NULL) {
  if (!is.null(drop)) {
    drop <- suppressWarnings(as.integer(drop[[1L]]))
    if (!is.finite(drop) || drop < 0L) stop("drop must be a nonnegative integer.", call. = FALSE)
    return(drop)
  }
  values <- vapply(c("reference", "discrepancy"), function(block) {
    block_cfg <- app_qdesn_block_config(cfg, block)
    suppressWarnings(as.integer((block_cfg$reservoir %||% list())$washout %||% 0L))
  }, integer(1L))
  if (any(!is.finite(values) | values < 0L)) {
    stop("Reference and discrepancy washout values must be nonnegative integers.", call. = FALSE)
  }
  max(values)
}

app_qdesn_block_seed_resolution <- function(model_row, cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  override <- app_qdesn_block_override(cfg, block)
  wrapper_seed <- suppressWarnings(as.integer(override[["reservoir_seed"]] %||% NA_integer_))
  nested_seed <- suppressWarnings(as.integer(
    (override[["reservoir"]] %||% list())[["seed"]] %||% NA_integer_
  ))
  wrapper_seed <- if (length(wrapper_seed) && is.finite(wrapper_seed[[1L]])) {
    as.integer(wrapper_seed[[1L]])
  } else {
    NA_integer_
  }
  nested_seed <- if (length(nested_seed) && is.finite(nested_seed[[1L]])) {
    as.integer(nested_seed[[1L]])
  } else {
    NA_integer_
  }
  base_seed <- app_model_row_reservoir_seed(model_row, cfg)
  if (!is.finite(base_seed)) base_seed <- app_config_reservoir_seed(cfg)
  if (!is.finite(base_seed)) base_seed <- 20260511L
  fallback_seed <- if (identical(block, "reference")) {
    as.integer(base_seed)
  } else {
    as.integer(base_seed + app_qdesn_discrepancy_seed_offset(cfg))
  }
  effective_seed <- if (is.finite(wrapper_seed)) {
    wrapper_seed
  } else if (is.finite(nested_seed)) {
    nested_seed
  } else {
    fallback_seed
  }
  source <- if (is.finite(wrapper_seed)) {
    sprintf("feature_contract.blocks.%s.reservoir_seed", block)
  } else if (is.finite(nested_seed)) {
    sprintf("feature_contract.blocks.%s.reservoir.seed", block)
  } else if (identical(block, "reference")) {
    "model_grid_or_config_reservoir_seed"
  } else {
    "model_grid_or_config_reservoir_seed_plus_discrepancy_offset"
  }
  data.frame(
    block = block,
    wrapper_seed = wrapper_seed,
    nested_seed = nested_seed,
    fallback_seed = fallback_seed,
    effective_seed = as.integer(effective_seed),
    seed_source = source,
    explicit_seed_conflict = is.finite(wrapper_seed) && is.finite(nested_seed) &&
      !identical(wrapper_seed, nested_seed),
    precedence_rule = "wrapper_reservoir_seed_then_nested_reservoir_seed_then_fallback",
    stringsAsFactors = FALSE
  )
}

app_qdesn_block_seed <- function(model_row, cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  app_qdesn_block_seed_resolution(model_row, cfg, block)$effective_seed[[1L]]
}

app_qdesn_seed_contract_report <- function(cfg, model_grid, require_match = NULL) {
  qrows <- app_qdesn_model_rows(model_grid, enabled_only = TRUE)
  cfg_seed <- app_config_reservoir_seed(cfg)
  seed_cfg <- ((cfg$execution %||% list())$seed_contract %||% list())
  if (is.null(require_match)) {
    require_match <- isTRUE(seed_cfg$require_config_model_grid_match %||% TRUE)
  }
  require_match <- isTRUE(require_match)
  if (!nrow(qrows)) {
    return(data.frame(
      fit_id = character(),
      model_id = character(),
      model_family = character(),
      quantile_level = numeric(),
      cfg_reservoir_seed = integer(),
      model_grid_reservoir_seed = integer(),
      effective_reservoir_seed = integer(),
      seed_source = character(),
      reference_reservoir_seed = integer(),
      discrepancy_reservoir_seed = integer(),
      discrepancy_reservoir_seed_offset = integer(),
      reference_seed_source = character(),
      discrepancy_seed_source = character(),
      reference_explicit_seed_conflict = logical(),
      discrepancy_explicit_seed_conflict = logical(),
      block_seed_precedence_rule = character(),
      config_model_seed_match = logical(),
      require_config_model_seed_match = logical(),
      two_block_design = logical(),
      status = character(),
      message = character(),
      stringsAsFactors = FALSE
    ))
  }

  rows <- lapply(seq_len(nrow(qrows)), function(i) {
    row <- qrows[i, , drop = FALSE]
    raw_row_seed <- suppressWarnings(as.integer(app_model_row_value(row, "reservoir_seed", NA_integer_)))
    has_row_seed <- length(raw_row_seed) && is.finite(raw_row_seed[[1L]])
    row_seed <- if (has_row_seed) as.integer(raw_row_seed[[1L]]) else NA_integer_
    effective_seed <- app_model_row_reservoir_seed(row, cfg)
    reference_resolution <- app_qdesn_block_seed_resolution(row, cfg, "reference")
    discrepancy_resolution <- app_qdesn_block_seed_resolution(row, cfg, "discrepancy")
    reference_seed <- reference_resolution$effective_seed[[1L]]
    discrepancy_seed <- discrepancy_resolution$effective_seed[[1L]]
    offset <- discrepancy_seed - reference_seed
    match <- !has_row_seed || !is.finite(cfg_seed) || identical(as.integer(row_seed), as.integer(cfg_seed))
    ok <- !require_match || isTRUE(match)
    data.frame(
      fit_id = as.character(row$fit_id[[1L]]),
      model_id = as.character(row$model_id[[1L]]),
      model_family = as.character(row$model_family[[1L]]),
      quantile_level = suppressWarnings(as.numeric(row$quantile_level[[1L]])),
      cfg_reservoir_seed = cfg_seed,
      model_grid_reservoir_seed = row_seed,
      effective_reservoir_seed = effective_seed,
      seed_source = if (has_row_seed) "model_grid.reservoir_seed" else "config.reservoir.seed",
      reference_reservoir_seed = reference_seed,
      discrepancy_reservoir_seed = discrepancy_seed,
      discrepancy_reservoir_seed_offset = offset,
      reference_seed_source = reference_resolution$seed_source[[1L]],
      discrepancy_seed_source = discrepancy_resolution$seed_source[[1L]],
      reference_explicit_seed_conflict = reference_resolution$explicit_seed_conflict[[1L]],
      discrepancy_explicit_seed_conflict = discrepancy_resolution$explicit_seed_conflict[[1L]],
      block_seed_precedence_rule = reference_resolution$precedence_rule[[1L]],
      config_model_seed_match = isTRUE(match),
      require_config_model_seed_match = require_match,
      two_block_design = app_qdesn_two_block_design(cfg),
      status = if (ok) "ok" else "failed",
      message = if (ok) {
        sprintf("effective_seed=%s; reference_seed=%s; discrepancy_seed=%s", effective_seed, reference_seed, discrepancy_seed)
      } else {
        sprintf(
          "Config reservoir seed (%s) disagrees with model-grid reservoir_seed (%s) for fit_id=%s.",
          cfg_seed,
          row_seed,
          as.character(row$fit_id[[1L]])
        )
      },
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_validate_qdesn_seed_contract <- function(cfg, model_grid, require_match = NULL) {
  report <- app_qdesn_seed_contract_report(cfg, model_grid, require_match = require_match)
  failed <- report[report$status != "ok", , drop = FALSE]
  if (nrow(failed)) {
    stop(paste(failed$message, collapse = "; "), call. = FALSE)
  }
  invisible(report)
}

app_validate_qdesn_block_seed_resolution <- function(
  cfg,
  model_row,
  conflict_action = c("record", "error")
) {
  conflict_action <- match.arg(conflict_action)
  report <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(block) {
    app_qdesn_block_seed_resolution(model_row, cfg, block)
  }))
  conflicts <- report[report$explicit_seed_conflict, , drop = FALSE]
  if (identical(conflict_action, "error") && nrow(conflicts)) {
    stop(
      sprintf(
        "Conflicting explicit Q-DESN block seeds: %s. The documented wrapper field has precedence.",
        paste(conflicts$block, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(report)
}
