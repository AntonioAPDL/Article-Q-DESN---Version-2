# Normal-DESN Part 1 screening helpers for the GloFAS application.
#
# Part 1 is a reservoir-only historical screen: the reservoir may consume
# lagged USGS, precipitation, and soil-moisture inputs, but the Normal readout
# is restricted to an intercept plus reservoir states. This isolates whether
# the DESN feature map itself carries useful historical signal.

app_glofas_normal_part1_default_values <- function() {
  list(
    pi_w = 0.03,
    pi_in = 1.0,
    win_scale_global = 0.18,
    win_scale_bias = 0.18,
    input_bound = "none",
    act_f = "tanh",
    act_k = "identity",
    seed = 20260512L,
    washout = 500L,
    ridge_tau2 = 1.0e4,
    intercept_var = 1.0e6,
    sigma_a = 2.0,
    sigma_b = 1.0,
    validation_n = 365L
  )
}

app_glofas_normal_part1_as_int_vec <- function(x, label) {
  if (is.null(x) || !length(x)) return(integer(0))
  if (length(x) == 1L && is.character(x)) {
    x <- gsub("[[:space:]]+", "", x)
    x <- strsplit(x, "[,;|]", perl = TRUE)[[1L]]
  }
  out <- suppressWarnings(as.integer(unlist(x, use.names = FALSE)))
  if (any(!is.finite(out))) {
    stop(sprintf("%s must contain finite integers.", label), call. = FALSE)
  }
  out
}

app_glofas_normal_part1_vector_label <- function(x) {
  x <- app_glofas_normal_part1_as_int_vec(x, "vector label")
  if (!length(x)) return("none")
  paste(x, collapse = "x")
}

app_glofas_normal_part1_identity_n_tilde <- function(n) {
  n <- app_glofas_normal_part1_as_int_vec(n, "n")
  if (length(n) <= 1L) return(integer(0))
  n[-length(n)]
}

app_glofas_normal_part1_default_dlm_families <- function() {
  c(
    "dlm_level",
    "dlm_seasonal_1",
    "dlm_seasonal_2",
    "dlm_seasonal_67",
    "dlm_transfer",
    "dlm_direct_covariate",
    "dlm_mean"
  )
}

app_glofas_normal_part1_as_bool_field <- function(x, default = FALSE) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) return(isTRUE(default))
  if (exists("app_as_bool", mode = "function", inherits = TRUE)) {
    return(isTRUE(app_as_bool(x[[1L]])))
  }
  tolower(trimws(as.character(x[[1L]]))) %in% c("true", "t", "1", "yes", "y")
}

app_glofas_normal_part1_character_field <- function(x, default = character(), label = "values") {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) return(as.character(default))
  if (length(x) == 1L && is.character(x)) {
    x <- unlist(strsplit(gsub("[[:space:]]+", "", x), "[,;|]", perl = TRUE), use.names = FALSE)
  }
  out <- as.character(unlist(x, use.names = FALSE))
  out <- unique(out[nzchar(out)])
  if (!length(out)) {
    stop(sprintf("%s must contain at least one nonempty value.", label), call. = FALSE)
  }
  out
}

app_glofas_normal_part1_row_value <- function(row, name, default = NULL) {
  if (!name %in% names(row) || !length(row[[name]])) return(default)
  value <- row[[name]][[1L]]
  if (length(value) == 0L || is.na(value)) return(default)
  if (is.character(value) && !nzchar(value)) return(default)
  value
}

app_glofas_normal_part1_parse_dlm_extension <- function(candidate_row, output_lag_max = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  enabled <- app_glofas_normal_part1_as_bool_field(app_glofas_normal_part1_row_value(
    candidate_row,
    "dlm_extension_enabled",
    FALSE
  ))
  if (!isTRUE(enabled)) return(list(enabled = FALSE))

  output_lag_max <- as.integer(output_lag_max %||% app_glofas_normal_part1_row_value(candidate_row, "output_lag_max", 1L))
  if (!is.finite(output_lag_max) || output_lag_max < 1L) {
    stop("DLM extension requires a positive output_lag_max.", call. = FALSE)
  }
  lag_min <- as.integer(app_glofas_normal_part1_row_value(candidate_row, "dlm_lag_min", 1L))
  lag_max <- as.integer(app_glofas_normal_part1_row_value(candidate_row, "dlm_lag_max", output_lag_max))
  if (!is.finite(lag_min) || lag_min < 1L) lag_min <- 1L
  if (!is.finite(lag_max) || lag_max < lag_min) lag_max <- output_lag_max
  dlm_lags_field <- app_glofas_normal_part1_row_value(candidate_row, "dlm_lags", NULL)
  dlm_lags <- if (!is.null(dlm_lags_field)) {
    app_parse_lag_spec(dlm_lags_field, allow_zero = FALSE, label = "dlm_lags")
  } else {
    seq.int(lag_min, lag_max)
  }
  if (!length(dlm_lags) || any(dlm_lags < 1L)) {
    stop("DLM extension requires strictly positive component lags.", call. = FALSE)
  }
  families <- app_glofas_normal_part1_character_field(
    app_glofas_normal_part1_row_value(
      candidate_row,
      "dlm_feature_families",
      paste(app_glofas_normal_part1_default_dlm_families(), collapse = ";")
    ),
    default = app_glofas_normal_part1_default_dlm_families(),
    label = "dlm_feature_families"
  )

  list(
    enabled = TRUE,
    timing = tolower(trimws(as.character(app_glofas_normal_part1_row_value(candidate_row, "dlm_timing", "filtered")))),
    feature_families = families,
    lags = dlm_lags,
    source = as.character(app_glofas_normal_part1_row_value(candidate_row, "dlm_source", "structural_normal_dlm")),
    covariate_mode = as.character(app_glofas_normal_part1_row_value(candidate_row, "dlm_covariate_mode", "transfer_plus_readout")),
    backend = as.character(app_glofas_normal_part1_row_value(candidate_row, "dlm_backend", "cpp")),
    components_path = as.character(app_glofas_normal_part1_row_value(candidate_row, "dlm_components_path", NA_character_)),
    allow_smoothed_predictive = app_glofas_normal_part1_as_bool_field(
      app_glofas_normal_part1_row_value(candidate_row, "dlm_allow_smoothed_predictive", FALSE)
    )
  )
}

app_glofas_normal_part1_make_cfg <- function(
  base_cfg,
  n,
  m,
  output_lag_max,
  covariate_lag_max,
  alpha,
  rho,
  seed = NULL,
  washout = NULL,
  dlm_extension = NULL
) {
  defaults <- app_glofas_normal_part1_default_values()
  n <- app_glofas_normal_part1_as_int_vec(n, "n")
  if (!length(n) || any(n < 1L)) stop("n must be a positive integer vector.", call. = FALSE)
  D <- length(n)
  m <- as.integer(m)
  output_lag_max <- as.integer(output_lag_max)
  covariate_lag_max <- as.integer(covariate_lag_max)
  washout <- as.integer(washout %||% defaults$washout)
  if (!is.finite(m) || m < 1L) stop("m must be a positive integer.", call. = FALSE)
  if (!is.finite(output_lag_max) || output_lag_max < 1L) {
    stop("output_lag_max must be a positive integer.", call. = FALSE)
  }
  if (!is.finite(covariate_lag_max) || covariate_lag_max < 0L) {
    stop("covariate_lag_max must be a nonnegative integer.", call. = FALSE)
  }
  if (!is.finite(washout) || washout < 0L) stop("washout must be nonnegative.", call. = FALSE)
  alpha <- as.numeric(alpha)
  rho <- as.numeric(rho)
  if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop("alpha must lie in (0, 1).", call. = FALSE)
  }
  if (!is.finite(rho) || rho <= 0 || rho >= 1) {
    stop("rho must lie in (0, 1).", call. = FALSE)
  }
  seed <- as.integer(seed %||% defaults$seed)
  if (!is.finite(seed)) stop("seed must be finite.", call. = FALSE)

  cfg <- base_cfg
  cfg$reservoir <- list(
    D = D,
    n = n,
    n_tilde = app_glofas_normal_part1_identity_n_tilde(n),
    m = m,
    washout = washout,
    alpha = rep(alpha, D),
    rho = rep(rho, D),
    pi_w = rep(defaults$pi_w, D),
    pi_in = rep(defaults$pi_in, D),
    win_scale_global = defaults$win_scale_global,
    win_scale_bias = defaults$win_scale_bias,
    input_bound = defaults$input_bound,
    act_f = defaults$act_f,
    act_k = defaults$act_k,
    standardize_inputs = TRUE,
    add_bias = TRUE,
    seed = seed
  )
  cfg$covariates <- cfg$covariates %||% list()
  cfg$covariates$enabled <- TRUE
  cfg$covariates$variables <- c("ppt", "soil")
  dlm_extension <- dlm_extension %||% list(enabled = FALSE)
  reservoir_input <- list(
    internal_bias = TRUE,
    output_lags = list(range = c(1L, output_lag_max)),
    covariates = list(
      ppt = list(range = c(0L, covariate_lag_max)),
      soil = list(range = c(0L, covariate_lag_max))
    ),
    standardize = TRUE
  )
  if (isTRUE(dlm_extension$enabled %||% FALSE)) {
    reservoir_input$dlm_components <- list(
      enabled = TRUE,
      timing = as.character(dlm_extension$timing %||% "filtered"),
      feature_families = as.character(dlm_extension$feature_families %||%
        app_glofas_normal_part1_default_dlm_families()),
      lags = as.integer(dlm_extension$lags %||% seq_len(output_lag_max)),
      source = as.character(dlm_extension$source %||% "structural_normal_dlm"),
      covariate_mode = as.character(dlm_extension$covariate_mode %||% "transfer_plus_readout"),
      backend = as.character(dlm_extension$backend %||% "cpp"),
      components_path = as.character(dlm_extension$components_path %||% NA_character_),
      allow_smoothed_predictive = isTRUE(dlm_extension$allow_smoothed_predictive %||% FALSE)
    )
  }

  cfg$feature_contract <- list(
    version = if (isTRUE(dlm_extension$enabled %||% FALSE)) "glofas_normal_part1_v0.2_dlm_augmented" else "glofas_normal_part1_v0.1",
    two_block_design = FALSE,
    reservoir_input = reservoir_input,
    readout = list(
      add_intercept = TRUE,
      include_reservoir_state = TRUE,
      reservoir_state_lags = list(),
      include_input_block = FALSE,
      input_block = list(
        output_lags = list(),
        covariates = list(),
        include_internal_bias = FALSE
      ),
      include_horizon_scaled = FALSE,
      standardize_output_lags = TRUE,
      standardize_non_intercept = FALSE
    ),
    forecast_alignment = list(
      output_lags_anchor = "target_date",
      covariate_lags_anchor = "target_date"
    )
  )
  cfg
}

app_glofas_normal_part1_geometry_grid <- function() {
  geometries <- list(
    D1_n300 = c(300L),
    D1_n500 = c(500L),
    D1_n800 = c(800L),
    D1_n1000 = c(1000L),
    D2_n300 = c(300L, 300L),
    D2_n500 = c(500L, 500L),
    D2_n800 = c(800L, 800L),
    D2_n1000 = c(1000L, 1000L),
    D3_n300 = c(300L, 300L, 300L),
    D3_n500 = c(500L, 500L, 500L),
    D3_n800 = c(800L, 800L, 800L),
    D3_n1000 = c(1000L, 1000L, 1000L),
    D4_n300 = c(300L, 300L, 300L, 300L),
    D4_n500 = c(500L, 500L, 500L, 500L),
    D4_n800 = c(800L, 800L, 800L, 800L),
    D4_n1000 = c(1000L, 1000L, 1000L, 1000L),
    D6_n300 = rep(300L, 6L),
    D6_n500 = rep(500L, 6L),
    D8_n300 = rep(300L, 8L),
    D8_n500 = rep(500L, 8L),
    D2_taper1000_500 = c(1000L, 500L),
    D3_taper1000_800_500 = c(1000L, 800L, 500L),
    D4_taper1000_800_500_300 = c(1000L, 800L, 500L, 300L),
    D8_taper500_400_300 = c(500L, 500L, 400L, 400L, 300L, 300L, 300L, 300L)
  )
  rows <- lapply(names(geometries), function(id) {
    n <- geometries[[id]]
    data.frame(
      geometry_id = id,
      D = length(n),
      n_vector = paste(n, collapse = ";"),
      n_tilde = paste(app_glofas_normal_part1_identity_n_tilde(n), collapse = ";"),
      n_state_features = sum(n),
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_normal_part1_lag_grid <- function() {
  data.frame(
    lag_id = c(
      "L360",
      "L720",
      "L1000a",
      "Y720_X180",
      "Y1000_X360",
      "Y360_X1000"
    ),
    m = c(360L, 720L, 1000L, 720L, 1000L, 1000L),
    output_lag_max = c(360L, 720L, 1000L, 720L, 1000L, 360L),
    covariate_lag_max = c(360L, 720L, 999L, 180L, 360L, 1000L),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part1_dynamic_grid <- function() {
  data.frame(
    dynamics_id = c(
      "a001_r095",
      "a005_r095",
      "a010_r095",
      "a020_r095",
      "a040_r095",
      "a010_r085",
      "a020_r085",
      "a010_r099",
      "a020_r099"
    ),
    alpha = c(0.01, 0.05, 0.10, 0.20, 0.40, 0.10, 0.20, 0.10, 0.20),
    rho = c(0.95, 0.95, 0.95, 0.95, 0.95, 0.85, 0.85, 0.99, 0.99),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part1_candidate_manifest <- function(
  max_candidates = Inf,
  include_expensive_frontier = TRUE
) {
  geo <- app_glofas_normal_part1_geometry_grid()
  lag <- app_glofas_normal_part1_lag_grid()
  dyn <- app_glofas_normal_part1_dynamic_grid()
  grid <- expand.grid(
    geometry_row = seq_len(nrow(geo)),
    lag_row = seq_len(nrow(lag)),
    dynamics_row = seq_len(nrow(dyn)),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  rows <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    g <- geo[grid$geometry_row[[i]], , drop = FALSE]
    l <- lag[grid$lag_row[[i]], , drop = FALSE]
    d <- dyn[grid$dynamics_row[[i]], , drop = FALSE]
    n_features <- as.integer(g$n_state_features[[1L]]) + 1L
    expensive <- n_features > 3500L || as.integer(l$output_lag_max[[1L]]) >= 1000L
    rows[[i]] <- data.frame(
      candidate_id = sprintf(
        "part1_%04d_%s__%s__%s",
        i,
        g$geometry_id[[1L]],
        l$lag_id[[1L]],
        d$dynamics_id[[1L]]
      ),
      geometry_id = g$geometry_id[[1L]],
      lag_id = l$lag_id[[1L]],
      dynamics_id = d$dynamics_id[[1L]],
      D = as.integer(g$D[[1L]]),
      n_vector = g$n_vector[[1L]],
      n_tilde = g$n_tilde[[1L]],
      n_state_features = as.integer(g$n_state_features[[1L]]),
      m = as.integer(l$m[[1L]]),
      output_lag_max = as.integer(l$output_lag_max[[1L]]),
      covariate_lag_max = as.integer(l$covariate_lag_max[[1L]]),
      washout = app_glofas_normal_part1_default_values()$washout,
      alpha = as.numeric(d$alpha[[1L]]),
      rho = as.numeric(d$rho[[1L]]),
      seed = app_glofas_normal_part1_default_values()$seed,
      ridge_tau2 = app_glofas_normal_part1_default_values()$ridge_tau2,
      intercept_var = app_glofas_normal_part1_default_values()$intercept_var,
      sigma_a = app_glofas_normal_part1_default_values()$sigma_a,
      sigma_b = app_glofas_normal_part1_default_values()$sigma_b,
      validation_n = app_glofas_normal_part1_default_values()$validation_n,
      n_readout_features = n_features,
      expensive_frontier = expensive,
      stringsAsFactors = FALSE
    )
  }
  manifest <- app_bind_rows_fill(rows)
  if (!isTRUE(include_expensive_frontier)) {
    manifest <- manifest[!app_as_bool_vec(manifest$expensive_frontier), , drop = FALSE]
  }
  priority_order <- order(
    as.integer(manifest$expensive_frontier),
    manifest$output_lag_max,
    manifest$n_readout_features,
    manifest$alpha,
    manifest$rho
  )
  manifest <- manifest[priority_order, , drop = FALSE]
  manifest$priority <- seq_len(nrow(manifest))
  if (is.finite(max_candidates) && nrow(manifest) > max_candidates) {
    manifest <- manifest[seq_len(as.integer(max_candidates)), , drop = FALSE]
  }
  rownames(manifest) <- NULL
  manifest
}

app_glofas_normal_part1_dynamics_label <- function(alpha, rho) {
  paste0(
    "a",
    sprintf("%03d", as.integer(round(100 * as.numeric(alpha)))),
    "_r",
    sprintf("%03d", as.integer(round(100 * as.numeric(rho))))
  )
}

app_glofas_normal_part1_candidate_manifest_from_axes <- function(
  geometries,
  lag_grid,
  dynamic_grid,
  candidate_prefix = "part1custom",
  include_expensive_frontier = TRUE
) {
  defaults <- app_glofas_normal_part1_default_values()
  if (!is.list(geometries) || !length(geometries) || is.null(names(geometries)) ||
      any(!nzchar(names(geometries)))) {
    stop("geometries must be a named list of positive integer vectors.", call. = FALSE)
  }
  required_lag <- c("lag_id", "m", "output_lag_max", "covariate_lag_max")
  required_dyn <- c("dynamics_id", "alpha", "rho")
  if (!all(required_lag %in% names(lag_grid))) {
    stop(sprintf("lag_grid must contain: %s", paste(required_lag, collapse = ", ")), call. = FALSE)
  }
  if (!all(required_dyn %in% names(dynamic_grid))) {
    stop(sprintf("dynamic_grid must contain: %s", paste(required_dyn, collapse = ", ")), call. = FALSE)
  }
  candidate_prefix <- gsub("[^A-Za-z0-9_.-]", "_", as.character(candidate_prefix)[[1L]])
  if (!nzchar(candidate_prefix)) candidate_prefix <- "part1custom"

  grid <- expand.grid(
    geometry_id = names(geometries),
    lag_row = seq_len(nrow(lag_grid)),
    dynamics_row = seq_len(nrow(dynamic_grid)),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  rows <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    geometry_id <- grid$geometry_id[[i]]
    n <- app_glofas_normal_part1_as_int_vec(geometries[[geometry_id]], "n")
    if (!length(n) || any(n < 1L)) {
      stop(sprintf("Invalid geometry %s.", geometry_id), call. = FALSE)
    }
    l <- lag_grid[grid$lag_row[[i]], , drop = FALSE]
    d <- dynamic_grid[grid$dynamics_row[[i]], , drop = FALSE]
    n_features <- sum(n) + 1L
    expensive <- n_features > 3500L ||
      as.integer(l$output_lag_max[[1L]]) >= 1000L ||
      max(n) >= 3000L
    rows[[i]] <- data.frame(
      candidate_id = sprintf(
        "%s_%04d_%s__%s__%s",
        candidate_prefix,
        i,
        geometry_id,
        l$lag_id[[1L]],
        d$dynamics_id[[1L]]
      ),
      geometry_id = geometry_id,
      lag_id = l$lag_id[[1L]],
      dynamics_id = d$dynamics_id[[1L]],
      D = length(n),
      n_vector = paste(n, collapse = ";"),
      n_tilde = paste(app_glofas_normal_part1_identity_n_tilde(n), collapse = ";"),
      n_state_features = sum(n),
      m = as.integer(l$m[[1L]]),
      output_lag_max = as.integer(l$output_lag_max[[1L]]),
      covariate_lag_max = as.integer(l$covariate_lag_max[[1L]]),
      washout = defaults$washout,
      alpha = as.numeric(d$alpha[[1L]]),
      rho = as.numeric(d$rho[[1L]]),
      seed = defaults$seed,
      ridge_tau2 = defaults$ridge_tau2,
      intercept_var = defaults$intercept_var,
      sigma_a = defaults$sigma_a,
      sigma_b = defaults$sigma_b,
      validation_n = defaults$validation_n,
      n_readout_features = n_features,
      expensive_frontier = expensive,
      stringsAsFactors = FALSE
    )
  }
  manifest <- app_bind_rows_fill(rows)
  if (!isTRUE(include_expensive_frontier)) {
    manifest <- manifest[!app_as_bool_vec(manifest$expensive_frontier), , drop = FALSE]
  }
  lag_priority <- match(as.character(manifest$lag_id), unique(as.character(lag_grid$lag_id)))
  dyn_priority <- match(as.character(manifest$dynamics_id), unique(as.character(dynamic_grid$dynamics_id)))
  n_target_distance <- abs(as.integer(manifest$n_state_features) - 800L)
  priority_order <- order(
    as.integer(manifest$D),
    lag_priority,
    dyn_priority,
    n_target_distance,
    as.integer(manifest$n_state_features),
    as.integer(manifest$expensive_frontier)
  )
  manifest <- manifest[priority_order, , drop = FALSE]
  manifest$priority <- seq_len(nrow(manifest))
  rownames(manifest) <- NULL
  manifest
}

app_glofas_normal_part1_wide_frontier_manifest <- function(
  include_expensive_frontier = TRUE
) {
  d1_n <- c(500L, 800L, 1000L, 1500L, 2000L, 3000L, 4000L, 5000L)
  d2_n <- c(500L, 800L, 1000L, 1500L, 2500L)
  geometries <- c(
    stats::setNames(as.list(d1_n), paste0("D1_n", d1_n)),
    stats::setNames(lapply(d2_n, function(n) c(n, n)), paste0("D2_n", d2_n))
  )
  lag_grid <- data.frame(
    lag_id = c("L360", "Y360_X180", "Y360_X540", "Y540_X360", "Y720_X360"),
    m = c(360L, 360L, 540L, 540L, 720L),
    output_lag_max = c(360L, 360L, 360L, 540L, 720L),
    covariate_lag_max = c(360L, 180L, 540L, 360L, 360L),
    stringsAsFactors = FALSE
  )
  dynamic_grid <- expand.grid(
    alpha = c(0.20, 0.30, 0.40, 0.50, 0.60),
    rho = c(0.90, 0.95, 0.99),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  dynamic_grid$dynamics_id <- mapply(
    app_glofas_normal_part1_dynamics_label,
    dynamic_grid$alpha,
    dynamic_grid$rho,
    USE.NAMES = FALSE
  )
  dynamic_grid <- dynamic_grid[, c("dynamics_id", "alpha", "rho"), drop = FALSE]
  d1_manifest <- app_glofas_normal_part1_candidate_manifest_from_axes(
    geometries = geometries[paste0("D1_n", d1_n)],
    lag_grid = lag_grid,
    dynamic_grid = dynamic_grid,
    candidate_prefix = "part1wide",
    include_expensive_frontier = include_expensive_frontier
  )
  d2_lag_grid <- lag_grid[lag_grid$lag_id %in% c("L360", "Y360_X180", "Y540_X360"), , drop = FALSE]
  d2_dynamic_grid <- dynamic_grid[
    dynamic_grid$alpha %in% c(0.20, 0.40, 0.60) &
      dynamic_grid$rho %in% c(0.95, 0.99),
    ,
    drop = FALSE
  ]
  d2_manifest <- app_glofas_normal_part1_candidate_manifest_from_axes(
    geometries = geometries[paste0("D2_n", d2_n)],
    lag_grid = d2_lag_grid,
    dynamic_grid = d2_dynamic_grid,
    candidate_prefix = "part1wide",
    include_expensive_frontier = include_expensive_frontier
  )
  manifest <- app_bind_rows_fill(list(d1_manifest, d2_manifest))
  manifest$candidate_id <- sprintf(
    "part1wide_%04d_%s__%s__%s",
    seq_len(nrow(manifest)),
    manifest$geometry_id,
    manifest$lag_id,
    manifest$dynamics_id
  )
  priority_order <- order(
    as.integer(manifest$D),
    match(as.character(manifest$lag_id), c("L360", "Y360_X180", "Y360_X540", "Y540_X360", "Y720_X360")),
    match(as.character(manifest$dynamics_id), c(
      "a040_r095", "a040_r099", "a040_r090",
      "a030_r095", "a030_r099", "a030_r090",
      "a050_r095", "a050_r099", "a050_r090",
      "a020_r095", "a020_r099", "a020_r090",
      "a060_r095", "a060_r099", "a060_r090"
    )),
    abs(as.integer(manifest$n_state_features) - 800L),
    as.integer(manifest$n_state_features)
  )
  manifest <- manifest[priority_order, , drop = FALSE]
  manifest$priority <- seq_len(nrow(manifest))
  rownames(manifest) <- NULL
  manifest
}

app_glofas_normal_part1_distribute_state_budget <- function(total, D) {
  total <- as.integer(total)
  D <- as.integer(D)
  if (!is.finite(total) || total < 1L) stop("total must be a positive integer.", call. = FALSE)
  if (!is.finite(D) || D < 1L) stop("D must be a positive integer.", call. = FALSE)
  base <- total %/% D
  remainder <- total %% D
  out <- rep(base, D)
  if (remainder > 0L) out[seq_len(remainder)] <- out[seq_len(remainder)] + 1L
  if (any(out < 1L) || sum(out) != total) {
    stop("Could not distribute the requested state budget.", call. = FALSE)
  }
  out
}

app_glofas_normal_part1_depth_budget_geometries <- function(
  depth_values = 2:10,
  total_state_budget = 5000L,
  anchor_first_layer = 3000L,
  extra_state_budget = 3000L,
  include_reference = TRUE
) {
  depth_values <- sort(unique(as.integer(depth_values)))
  if (!length(depth_values) || any(!is.finite(depth_values)) || any(depth_values < 2L)) {
    stop("depth_values must contain finite integers >= 2.", call. = FALSE)
  }
  total_state_budget <- as.integer(total_state_budget)
  anchor_first_layer <- as.integer(anchor_first_layer)
  extra_state_budget <- as.integer(extra_state_budget)
  if (!is.finite(total_state_budget) || total_state_budget < 1L) {
    stop("total_state_budget must be positive.", call. = FALSE)
  }
  if (!is.finite(anchor_first_layer) || anchor_first_layer < 1L) {
    stop("anchor_first_layer must be positive.", call. = FALSE)
  }
  if (!is.finite(extra_state_budget) || extra_state_budget < 1L) {
    stop("extra_state_budget must be positive.", call. = FALSE)
  }

  geometries <- list()
  if (isTRUE(include_reference)) {
    geometries[["D01_anchor3000_reference"]] <- anchor_first_layer
  }
  for (D in depth_values) {
    geometries[[sprintf("D%02d_budget%04d_equal", D, total_state_budget)]] <-
      app_glofas_normal_part1_distribute_state_budget(total_state_budget, D)
  }
  for (D in depth_values) {
    extra <- app_glofas_normal_part1_distribute_state_budget(extra_state_budget, D - 1L)
    geometries[[sprintf("D%02d_anchor%04d_extra%04d", D, anchor_first_layer, extra_state_budget)]] <-
      c(anchor_first_layer, extra)
  }
  geometries
}

app_glofas_normal_part1_prepare_panel <- function(cfg, manifest = NULL, schema = NULL) {
  manifest <- manifest %||% app_load_input_manifest(app_config_path(cfg, "input_manifest"), required = TRUE)
  schema <- schema %||% app_read_yaml(app_config_path(cfg, "schema"))
  panel <- app_build_application_panel(cfg, manifest, schema)
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (nrow(cutoffs) != 1L) {
    stop("Normal Part 1 screening expects exactly one enabled cutoff.", call. = FALSE)
  }
  cutoff <- cutoffs[1L, , drop = FALSE]
  panel$target_date <- as.Date(panel$target_date)
  hist <- panel[
    app_as_bool_vec(panel$is_retrospective) &
      panel$target_date >= as.Date(cutoff$train_start[[1L]]) &
      panel$target_date <= as.Date(cutoff$train_end[[1L]]) &
      is.finite(panel$y_transformed),
    ,
    drop = FALSE
  ]
  hist <- hist[order(hist$target_date), , drop = FALSE]
  if (!nrow(hist)) stop("No historical USGS rows are available for Part 1.", call. = FALSE)
  if (anyDuplicated(hist$target_date)) {
    stop("Part 1 historical panel must contain one USGS row per target date.", call. = FALSE)
  }
  list(panel = hist, cutoff = cutoff)
}

app_glofas_normal_part1_load_dlm_components <- function(
  base_cfg,
  panel_bundle,
  dlm_extension
) {
  timing <- as.character(dlm_extension$timing %||% "filtered")[[1L]]
  components_path <- as.character(dlm_extension$components_path %||% NA_character_)[[1L]]
  components_source <- "inline_fit"
  fit_score <- data.frame()
  if (!is.na(components_path) && nzchar(components_path)) {
    components_path <- app_resolve_path(components_path, must_work = TRUE)
    components <- app_read_csv(components_path)
    components_source <- "csv_components_path"
  } else {
    if (!exists("app_glofas_structural_dlm_fit_from_glofas_config", mode = "function", inherits = TRUE)) {
      stop("DLM-augmented Part 1 screening requires application/R/glofas_structural_normal_dlm.R to be sourced.", call. = FALSE)
    }
    fit <- app_glofas_structural_dlm_fit_from_glofas_config(
      base_cfg = base_cfg,
      mode = as.character(dlm_extension$covariate_mode %||% "transfer_plus_readout"),
      backend = as.character(dlm_extension$backend %||% "cpp"),
      panel_bundle = panel_bundle
    )
    components <- app_glofas_structural_dlm_components(fit, timing = timing)
    fit_score <- fit$score %||% data.frame()
  }
  if (!"timing" %in% names(components)) components$timing <- timing
  list(
    components = components,
    components_path = components_path,
    source = components_source,
    score = fit_score
  )
}

app_glofas_normal_part1_apply_dlm_extension <- function(
  base_cfg,
  panel_bundle,
  dlm_extension
) {
  if (!isTRUE(dlm_extension$enabled %||% FALSE)) {
    return(list(panel_bundle = panel_bundle, meta = list(enabled = FALSE)))
  }
  if (!exists("app_glofas_structural_dlm_augment_panel", mode = "function", inherits = TRUE)) {
    stop("DLM-augmented Part 1 screening requires application/R/glofas_structural_normal_dlm.R to be sourced.", call. = FALSE)
  }
  loaded <- app_glofas_normal_part1_load_dlm_components(
    base_cfg = base_cfg,
    panel_bundle = panel_bundle,
    dlm_extension = dlm_extension
  )
  augmented_panel <- app_glofas_structural_dlm_augment_panel(
    panel = panel_bundle$panel,
    components = loaded$components,
    timing = as.character(dlm_extension$timing %||% "filtered")
  )
  missing_features <- setdiff(as.character(dlm_extension$feature_families), names(augmented_panel))
  if (length(missing_features)) {
    stop(sprintf("DLM augmentation is missing requested features: %s.", paste(missing_features, collapse = ", ")), call. = FALSE)
  }
  meta <- list(
    enabled = TRUE,
    timing = as.character(dlm_extension$timing %||% "filtered"),
    feature_families = as.character(dlm_extension$feature_families),
    lags = as.integer(dlm_extension$lags),
    source = loaded$source,
    components_path = loaded$components_path,
    components_sha256 = if (!is.na(loaded$components_path) && nzchar(loaded$components_path)) {
      app_sha256_file(loaded$components_path)
    } else {
      NA_character_
    },
    covariate_mode = as.character(dlm_extension$covariate_mode %||% "transfer_plus_readout"),
    backend = as.character(dlm_extension$backend %||% "cpp"),
    allow_smoothed_predictive = isTRUE(dlm_extension$allow_smoothed_predictive %||% FALSE),
    score = loaded$score
  )
  list(
    panel_bundle = list(panel = augmented_panel, cutoff = panel_bundle$cutoff),
    meta = meta
  )
}

app_glofas_normal_part1_readout_matrix <- function(design) {
  X <- cbind(readout_intercept = 1, as.matrix(design$X))
  storage.mode(X) <- "double"
  feature_info <- app_feature_info_rows(
    colnames(X),
    block = c("readout_intercept", rep("reservoir_state", ncol(X) - 1L)),
    is_intercept = c(TRUE, rep(FALSE, ncol(X) - 1L))
  )
  feature_info$column_index <- seq_len(nrow(feature_info))
  feature_info <- feature_info[, c("column_index", setdiff(names(feature_info), "column_index")), drop = FALSE]
  contract <- list(readout = list(add_intercept = TRUE))
  app_validate_readout_feature_design(X, feature_info, contract = contract)
  list(X = X, feature_info = feature_info)
}

app_glofas_normal_part1_build_design <- function(base_cfg, candidate_row, panel_bundle = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  dlm_extension <- app_glofas_normal_part1_parse_dlm_extension(
    candidate_row,
    output_lag_max = candidate_row$output_lag_max[[1L]]
  )
  cfg <- app_glofas_normal_part1_make_cfg(
    base_cfg = base_cfg,
    n = candidate_row$n_vector[[1L]],
    m = candidate_row$m[[1L]],
    output_lag_max = candidate_row$output_lag_max[[1L]],
    covariate_lag_max = candidate_row$covariate_lag_max[[1L]],
    alpha = candidate_row$alpha[[1L]],
    rho = candidate_row$rho[[1L]],
    seed = candidate_row$seed[[1L]],
    washout = candidate_row$washout[[1L]],
    dlm_extension = dlm_extension
  )
  invisible(app_feature_contract(cfg))
  panel_bundle <- panel_bundle %||% app_glofas_normal_part1_prepare_panel(base_cfg)
  dlm_applied <- app_glofas_normal_part1_apply_dlm_extension(
    base_cfg = base_cfg,
    panel_bundle = panel_bundle,
    dlm_extension = dlm_extension
  )
  design_panel_bundle <- dlm_applied$panel_bundle
  design <- app_qdesn_build_article_design_full(
    panel = design_panel_bundle$panel,
    cfg = cfg,
    seed = as.integer(candidate_row$seed[[1L]]),
    drop = as.integer(candidate_row$washout[[1L]])
  )
  readout <- app_glofas_normal_part1_readout_matrix(design)
  y <- as.numeric(design$y_fit)
  dates <- as.Date(design_panel_bundle$panel$target_date[design$meta$keep_idx])
  if (nrow(readout$X) != length(y) || length(y) != length(dates)) {
    stop("Part 1 design produced incompatible X/y/date dimensions.", call. = FALSE)
  }
  list(
    cfg = cfg,
    X = readout$X,
    y = y,
    dates = dates,
    feature_info = readout$feature_info,
    design_meta = design$meta,
    reservoir = design$reservoir,
    dlm_extension = dlm_applied$meta
  )
}

app_glofas_normal_ridge_fit <- function(
  X,
  y,
  ridge_tau2 = 1.0e4,
  intercept_var = 1.0e6,
  sigma_a = 2.0,
  sigma_b = 1.0,
  jitter = 1.0e-8
) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  if (!nrow(X) || !ncol(X) || any(!is.finite(X))) stop("X must be finite.", call. = FALSE)
  if (length(y) != nrow(X) || any(!is.finite(y))) stop("y must match X and be finite.", call. = FALSE)
  ridge_tau2 <- as.numeric(ridge_tau2)
  intercept_var <- as.numeric(intercept_var)
  sigma_a <- as.numeric(sigma_a)
  sigma_b <- as.numeric(sigma_b)
  if (!is.finite(ridge_tau2) || ridge_tau2 <= 0) stop("ridge_tau2 must be positive.", call. = FALSE)
  if (!is.finite(intercept_var) || intercept_var <= 0) stop("intercept_var must be positive.", call. = FALSE)
  if (!is.finite(sigma_a) || sigma_a <= 0 || !is.finite(sigma_b) || sigma_b <= 0) {
    stop("sigma prior parameters must be positive.", call. = FALSE)
  }
  p <- ncol(X)
  prior_prec <- rep(1 / ridge_tau2, p)
  prior_prec[[1L]] <- 1 / intercept_var
  P <- crossprod(X)
  diag(P) <- diag(P) + prior_prec
  Xty <- as.numeric(crossprod(X, y))
  chol_P <- tryCatch(chol(P), error = function(e) NULL)
  if (is.null(chol_P)) {
    diag(P) <- diag(P) + jitter
    chol_P <- chol(P)
  }
  beta_mean <- as.numeric(backsolve(chol_P, forwardsolve(t(chol_P), Xty)))
  quad_post <- as.numeric(crossprod(beta_mean, P %*% beta_mean))
  sigma_a_post <- sigma_a + nrow(X) / 2
  sigma_b_post <- sigma_b + 0.5 * (as.numeric(crossprod(y)) - quad_post)
  sigma_b_post <- max(sigma_b_post, .Machine$double.eps)
  P_inv <- chol2inv(chol_P)
  beta_cov <- if (sigma_a_post > 1) sigma_b_post / (sigma_a_post - 1) * P_inv else matrix(NA_real_, p, p)
  list(
    beta_mean = beta_mean,
    beta_cov = beta_cov,
    beta_var_diag = diag(beta_cov),
    precision = P,
    precision_chol = chol_P,
    precision_inv = P_inv,
    sigma_a = sigma_a_post,
    sigma_b = sigma_b_post,
    sigma2_mean = if (sigma_a_post > 1) sigma_b_post / (sigma_a_post - 1) else NA_real_,
    ridge_tau2 = ridge_tau2,
    intercept_var = intercept_var,
    n_train = nrow(X),
    p = p
  )
}

app_glofas_normal_predict <- function(fit, X_new, chunk_size = NULL) {
  X_new <- as.matrix(X_new)
  storage.mode(X_new) <- "double"
  if (ncol(X_new) != fit$p) stop("Prediction design has wrong column count.", call. = FALSE)
  mu <- as.numeric(X_new %*% fit$beta_mean)
  sigma2 <- as.numeric(fit$sigma2_mean)
  if (!is.finite(sigma2) || sigma2 <= 0) {
    sigma2 <- fit$sigma_b / max(fit$sigma_a, .Machine$double.eps)
  }
  beta_cov <- fit$beta_cov %||% NULL
  if (!is.null(beta_cov)) {
    beta_cov <- as.matrix(beta_cov)
    if (!all(dim(beta_cov) == c(fit$p, fit$p))) {
      stop("fit$beta_cov has incompatible dimensions.", call. = FALSE)
    }
    chunk_size <- as.integer(chunk_size %||% nrow(X_new))
    if (!is.finite(chunk_size) || chunk_size < 1L) chunk_size <- nrow(X_new)
    param_var <- numeric(nrow(X_new))
    starts <- seq.int(1L, nrow(X_new), by = chunk_size)
    for (st in starts) {
      en <- min(nrow(X_new), st + chunk_size - 1L)
      Xi <- X_new[st:en, , drop = FALSE]
      solved <- Xi %*% beta_cov
      param_var[st:en] <- rowSums(solved * Xi)
    }
    sd <- sqrt(pmax(sigma2 + param_var, .Machine$double.eps))
    return(list(mean = mu, sd = sd, leverage = param_var / max(sigma2, .Machine$double.eps)))
  }
  solved <- X_new %*% fit$precision_inv
  leverage <- rowSums(solved * X_new)
  sd <- sqrt(pmax(sigma2 * (1 + leverage), .Machine$double.eps))
  list(mean = mu, sd = sd, leverage = leverage)
}

app_glofas_normal_crps <- function(y, mu, sd) {
  y <- as.numeric(y)
  mu <- as.numeric(mu)
  sd <- pmax(as.numeric(sd), .Machine$double.eps)
  z <- (y - mu) / sd
  sd * (z * (2 * stats::pnorm(z) - 1) + 2 * stats::dnorm(z) - 1 / sqrt(pi))
}

app_glofas_normal_score_predictions <- function(y, pred, prefix = "") {
  err <- as.numeric(pred$mean) - as.numeric(y)
  crps <- app_glofas_normal_crps(y, pred$mean, pred$sd)
  out <- data.frame(
    mean_crps = mean(crps),
    mae = mean(abs(err)),
    rmse = sqrt(mean(err^2)),
    mean_sd = mean(pred$sd),
    mean_abs_error = mean(abs(err)),
    stringsAsFactors = FALSE
  )
  if (nzchar(prefix)) names(out) <- paste0(prefix, names(out))
  out
}

app_glofas_normal_part1_score_candidate <- function(base_cfg, candidate_row, panel_bundle = NULL) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  started <- Sys.time()
  design <- app_glofas_normal_part1_build_design(base_cfg, candidate_row, panel_bundle = panel_bundle)
  n <- nrow(design$X)
  validation_n <- as.integer(candidate_row$validation_n[[1L]] %||% app_glofas_normal_part1_default_values()$validation_n)
  validation_n <- min(validation_n, max(30L, floor(n / 3L)))
  train_idx <- seq_len(n - validation_n)
  valid_idx <- seq.int(n - validation_n + 1L, n)
  fit <- app_glofas_normal_ridge_fit(
    X = design$X[train_idx, , drop = FALSE],
    y = design$y[train_idx],
    ridge_tau2 = as.numeric(candidate_row$ridge_tau2[[1L]]),
    intercept_var = as.numeric(candidate_row$intercept_var[[1L]]),
    sigma_a = as.numeric(candidate_row$sigma_a[[1L]]),
    sigma_b = as.numeric(candidate_row$sigma_b[[1L]])
  )
  valid_pred <- app_glofas_normal_predict(fit, design$X[valid_idx, , drop = FALSE])
  train_pred <- app_glofas_normal_predict(fit, design$X[train_idx, , drop = FALSE])
  valid_score <- app_glofas_normal_score_predictions(design$y[valid_idx], valid_pred, prefix = "valid_")
  train_score <- app_glofas_normal_score_predictions(design$y[train_idx], train_pred, prefix = "train_")
  windows <- c(50L, 200L)
  window_scores <- lapply(windows, function(w) {
    idx <- utils::tail(seq_along(valid_idx), min(w, length(valid_idx)))
    sc <- app_glofas_normal_score_predictions(
      design$y[valid_idx][idx],
      list(mean = valid_pred$mean[idx], sd = valid_pred$sd[idx]),
      prefix = paste0("valid_last", w, "_")
    )
    sc
  })
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  summary <- cbind(
    candidate_row,
    data.frame(
      status = "completed",
      n_rows_design = n,
      n_train = length(train_idx),
      n_valid = length(valid_idx),
      n_readout_features_actual = ncol(design$X),
      n_reservoir_input_features_actual = as.integer((design$design_meta %||% list())$m_input %||% NA_integer_),
      n_dlm_component_input_features = length((design$design_meta %||% list())$reservoir_dlm_component_columns %||% character(0)),
      dlm_timing_effective = as.character((design$dlm_extension %||% list())$timing %||% NA_character_),
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[valid_idx])),
      valid_end_date = as.character(max(design$dates[valid_idx])),
      runtime_seconds = elapsed,
      stringsAsFactors = FALSE
    ),
    train_score,
    valid_score,
    do.call(cbind, window_scores)
  )
  detail <- data.frame(
    candidate_id = as.character(candidate_row$candidate_id[[1L]]),
    date = design$dates[valid_idx],
    observed = design$y[valid_idx],
    pred_mean = valid_pred$mean,
    pred_sd = valid_pred$sd,
    crps = app_glofas_normal_crps(design$y[valid_idx], valid_pred$mean, valid_pred$sd),
    abs_error = abs(valid_pred$mean - design$y[valid_idx]),
    squared_error = (valid_pred$mean - design$y[valid_idx])^2,
    stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail, fit = fit, design = design)
}

app_glofas_normal_part1_failure_row <- function(candidate_row, error, started = Sys.time()) {
  cbind(
    candidate_row[1L, , drop = FALSE],
    data.frame(
      status = "failed",
      error_message = as.character(conditionMessage(error)),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
  )
}

app_glofas_normal_part1_collect_scores <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  score_files <- list.files(file.path(root, "scores"), pattern = "_summary[.]csv$", full.names = TRUE)
  detail_files <- list.files(file.path(root, "scores"), pattern = "_validation_detail[.]csv$", full.names = TRUE)
  summaries <- app_bind_rows_fill(lapply(score_files, app_read_csv))
  details <- app_bind_rows_fill(lapply(detail_files, app_read_csv))
  if (nrow(summaries)) {
    numeric_cols <- intersect(
      c("valid_mean_crps", "valid_mae", "valid_rmse", "train_mean_crps", "runtime_seconds"),
      names(summaries)
    )
    for (nm in numeric_cols) summaries[[nm]] <- suppressWarnings(as.numeric(summaries[[nm]]))
    summaries <- summaries[order(summaries$status != "completed", summaries$valid_mean_crps), , drop = FALSE]
    summaries$rank_valid_crps <- seq_len(nrow(summaries))
  }
  app_write_csv(summaries, file.path(root, "tables", "ridge_scores_latest.csv"))
  app_write_csv(details, file.path(root, "tables", "ridge_validation_detail_latest.csv"))
  summaries
}

app_glofas_normal_part1_validation_split <- function(n, validation_n) {
  n <- as.integer(n)
  validation_n <- as.integer(validation_n)
  if (!is.finite(n) || n < 4L) stop("n must be at least 4.", call. = FALSE)
  if (!is.finite(validation_n) || validation_n < 1L) {
    stop("validation_n must be positive.", call. = FALSE)
  }
  validation_n <- min(validation_n, max(30L, floor(n / 3L)))
  if (validation_n >= n) validation_n <- max(1L, n - 1L)
  list(
    train_idx = seq_len(n - validation_n),
    valid_idx = seq.int(n - validation_n + 1L, n),
    validation_n = validation_n
  )
}

app_glofas_normal_part1_design_fingerprint <- function(X, y = NULL, dates = NULL, feature_info = NULL) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  row_sum <- rowSums(X)
  payload <- list(
    dim = as.integer(dim(X)),
    colnames = colnames(X),
    col_sums = as.numeric(colSums(X)),
    col_sq_sums = as.numeric(colSums(X * X)),
    col_abs_sums = as.numeric(colSums(abs(X))),
    row_sums_head = as.numeric(utils::head(row_sum, 50L)),
    row_sums_tail = as.numeric(utils::tail(row_sum, 50L)),
    y_len = length(y %||% numeric()),
    y_sum = if (!is.null(y)) sum(as.numeric(y)) else NA_real_,
    y_sq_sum = if (!is.null(y)) sum(as.numeric(y)^2) else NA_real_,
    date_min = if (!is.null(dates)) as.character(min(as.Date(dates))) else NA_character_,
    date_max = if (!is.null(dates)) as.character(max(as.Date(dates))) else NA_character_,
    feature_names = if (!is.null(feature_info) && "column_name" %in% names(feature_info)) {
      as.character(feature_info$column_name)
    } else {
      colnames(X)
    }
  )
  tmp <- tempfile("glofas_normal_design_fingerprint_", fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(payload, tmp, version = 2L)
  app_sha256_file(tmp)
}

app_glofas_normal_part1_prefix_existing_score_columns <- function(row) {
  row <- row[1L, , drop = FALSE]
  score_cols <- grep("^(train_|valid_)", names(row), value = TRUE)
  operational_cols <- intersect(
    c(
      "status", "error_message", "runtime_seconds", "rank_valid_crps",
      "n_rows_design", "n_train", "n_valid", "n_readout_features_actual",
      "design_start_date", "design_end_date", "valid_start_date", "valid_end_date"
    ),
    names(row)
  )
  cols <- unique(c(score_cols, operational_cols))
  if (length(cols)) {
    names(row)[match(cols, names(row))] <- paste0("ridge_", cols)
  }
  row
}

app_glofas_normal_part1_empty_score <- function(prefix) {
  out <- data.frame(
    mean_crps = NA_real_,
    mae = NA_real_,
    rmse = NA_real_,
    mean_sd = NA_real_,
    mean_abs_error = NA_real_,
    stringsAsFactors = FALSE
  )
  names(out) <- paste0(prefix, names(out))
  out
}

app_glofas_normal_part1_rebuild_ridge_warm_start <- function(
  base_cfg,
  candidate_row,
  panel_bundle = NULL,
  hash_design = TRUE
) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  design <- app_glofas_normal_part1_build_design(base_cfg, candidate_row, panel_bundle = panel_bundle)
  split <- app_glofas_normal_part1_validation_split(
    nrow(design$X),
    candidate_row$validation_n[[1L]] %||% app_glofas_normal_part1_default_values()$validation_n
  )
  train_idx <- split$train_idx
  valid_idx <- split$valid_idx
  fit <- app_glofas_normal_ridge_fit(
    X = design$X[train_idx, , drop = FALSE],
    y = design$y[train_idx],
    ridge_tau2 = as.numeric(candidate_row$ridge_tau2[[1L]]),
    intercept_var = as.numeric(candidate_row$intercept_var[[1L]]),
    sigma_a = as.numeric(candidate_row$sigma_a[[1L]]),
    sigma_b = as.numeric(candidate_row$sigma_b[[1L]])
  )
  valid_pred <- app_glofas_normal_predict(fit, design$X[valid_idx, , drop = FALSE], chunk_size = 64L)
  valid_score <- app_glofas_normal_score_predictions(design$y[valid_idx], valid_pred, prefix = "ridge_valid_")
  windows <- c(50L, 200L)
  window_scores <- lapply(windows, function(w) {
    idx <- utils::tail(seq_along(valid_idx), min(w, length(valid_idx)))
    app_glofas_normal_score_predictions(
      design$y[valid_idx][idx],
      list(mean = valid_pred$mean[idx], sd = valid_pred$sd[idx]),
      prefix = paste0("ridge_valid_last", w, "_")
    )
  })
  train_hash <- if (isTRUE(hash_design)) {
    app_glofas_normal_part1_design_fingerprint(
      design$X[train_idx, , drop = FALSE],
      design$y[train_idx],
      design$dates[train_idx],
      design$feature_info
    )
  } else {
    NA_character_
  }
  full_hash <- if (isTRUE(hash_design)) {
    app_glofas_normal_part1_design_fingerprint(
      design$X,
      design$y,
      design$dates,
      design$feature_info
    )
  } else {
    NA_character_
  }
  summary <- cbind(
    candidate_row,
    data.frame(
      warm_start_status = "completed",
      n_rows_design = nrow(design$X),
      n_train = length(train_idx),
      n_valid = length(valid_idx),
      n_readout_features_actual = ncol(design$X),
      n_reservoir_input_features_actual = as.integer((design$design_meta %||% list())$m_input %||% NA_integer_),
      n_dlm_component_input_features = length((design$design_meta %||% list())$reservoir_dlm_component_columns %||% character(0)),
      dlm_timing_effective = as.character((design$dlm_extension %||% list())$timing %||% NA_character_),
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[valid_idx])),
      valid_end_date = as.character(max(design$dates[valid_idx])),
      train_design_fingerprint = train_hash,
      full_design_fingerprint = full_hash,
      stringsAsFactors = FALSE
    ),
    valid_score,
    do.call(cbind, window_scores)
  )
  warm <- list(
    type = "glofas_normal_part1_ridge_warm_start",
    version = if (isTRUE((design$dlm_extension %||% list())$enabled %||% FALSE)) "0.2" else "0.1",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    candidate_id = as.character(candidate_row$candidate_id[[1L]]),
    candidate_row = candidate_row,
    split = list(
      validation_n = split$validation_n,
      train_idx_range = range(train_idx),
      valid_idx_range = range(valid_idx)
    ),
    design = list(
      n_rows = nrow(design$X),
      n_features = ncol(design$X),
      train_design_fingerprint = train_hash,
      full_design_fingerprint = full_hash,
      colnames = colnames(design$X),
      feature_info = design$feature_info,
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[valid_idx])),
      valid_end_date = as.character(max(design$dates[valid_idx])),
      dlm_extension = design$dlm_extension %||% list(enabled = FALSE),
      reservoir_input_columns = as.character((design$design_meta %||% list())$reservoir_input_columns %||% character(0)),
      reservoir_dlm_component_columns = as.character((design$design_meta %||% list())$reservoir_dlm_component_columns %||% character(0))
    ),
    fit = list(
      beta_mean = as.numeric(fit$beta_mean),
      beta_var_diag = as.numeric(fit$beta_var_diag),
      sigma_a = as.numeric(fit$sigma_a),
      sigma_b = as.numeric(fit$sigma_b),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      ridge_tau2 = as.numeric(fit$ridge_tau2),
      intercept_var = as.numeric(fit$intercept_var),
      n_train = as.integer(fit$n_train),
      p = as.integer(fit$p)
    ),
    summary = summary
  )
  class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
  warm
}

app_glofas_normal_part1_validate_ridge_warm_start <- function(
  warm_start,
  candidate_row = NULL,
  design = NULL,
  train_idx = NULL,
  strict_hash = TRUE
) {
  if (!inherits(warm_start, "glofas_normal_part1_ridge_warm_start") ||
      !identical(as.character(warm_start$type %||% "")[[1L]], "glofas_normal_part1_ridge_warm_start")) {
    stop("Expected a GloFAS Normal Part 1 ridge warm-start object.", call. = FALSE)
  }
  if (!as.character(warm_start$version %||% "")[[1L]] %in% c("0.1", "0.2")) {
    stop("Unsupported GloFAS Normal Part 1 ridge warm-start version.", call. = FALSE)
  }
  p <- as.integer(warm_start$fit$p %||% length(warm_start$fit$beta_mean))
  if (!is.finite(p) || p < 1L) stop("Warm-start p must be positive.", call. = FALSE)
  if (length(warm_start$fit$beta_mean) != p || length(warm_start$fit$beta_var_diag) != p) {
    stop("Warm-start beta mean/variance dimensions are inconsistent.", call. = FALSE)
  }
  if (any(!is.finite(warm_start$fit$beta_mean)) || any(!is.finite(warm_start$fit$beta_var_diag))) {
    stop("Warm-start beta moments must be finite.", call. = FALSE)
  }
  if (!is.null(candidate_row)) {
    cid <- as.character(candidate_row$candidate_id[[1L]])
    if (!identical(cid, as.character(warm_start$candidate_id))) {
      stop("Warm-start candidate_id does not match the requested candidate.", call. = FALSE)
    }
  }
  if (!is.null(design)) {
    if (ncol(design$X) != p) stop("Warm-start p does not match design column count.", call. = FALSE)
    if (!identical(as.character(warm_start$design$colnames), colnames(design$X))) {
      stop("Warm-start feature names do not match rebuilt design.", call. = FALSE)
    }
    if (isTRUE(strict_hash)) {
      if (is.null(train_idx)) stop("train_idx is required for strict warm-start hash validation.", call. = FALSE)
      observed <- app_glofas_normal_part1_design_fingerprint(
        design$X[train_idx, , drop = FALSE],
        design$y[train_idx],
        design$dates[train_idx],
        design$feature_info
      )
      expected <- as.character(warm_start$design$train_design_fingerprint %||% "")
      if (nzchar(expected) && !identical(observed, expected)) {
        stop("Warm-start training design fingerprint mismatch.", call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

app_glofas_normal_part1_save_ridge_warm_start <- function(warm_start, path) {
  app_ensure_dir(dirname(path))
  saveRDS(warm_start, path, version = 2L)
  invisible(path)
}

app_glofas_normal_part1_load_ridge_warm_start <- function(path) {
  warm <- readRDS(path)
  app_glofas_normal_part1_validate_ridge_warm_start(warm, strict_hash = FALSE)
  warm
}

app_glofas_normal_spd_solve <- function(P, h = NULL, jitter = 1.0e-8, max_tries = 6L) {
  P <- as.matrix(P)
  storage.mode(P) <- "double"
  jitter <- as.numeric(jitter)
  if (!is.finite(jitter) || jitter <= 0) jitter <- 1.0e-8
  for (attempt in seq_len(max_tries)) {
    chol_P <- tryCatch(chol(P), error = function(e) NULL)
    if (!is.null(chol_P)) {
      x <- if (is.null(h)) NULL else as.numeric(backsolve(chol_P, forwardsolve(t(chol_P), h)))
      return(list(chol = chol_P, x = x, inv = chol2inv(chol_P), jitter_attempt = attempt - 1L))
    }
    diag(P) <- diag(P) + jitter * 10^(attempt - 1L)
  }
  stop("Could not compute a Cholesky factor for the Normal RHS precision matrix.", call. = FALSE)
}

app_glofas_normal_rhs_state_diagnostics <- function(state, p) {
  prec <- app_latent_rhs_prior_precision(state, p)
  data.frame(
    effective_tau = sqrt(1 / pmax(as.numeric(state$e_inv_tau2), 1.0e-12)),
    e_inv_tau2 = as.numeric(state$e_inv_tau2),
    e_inv_xi = as.numeric(state$e_inv_xi),
    e_inv_zeta2 = as.numeric(state$e_inv_zeta2),
    prior_precision_mean = mean(prec),
    prior_precision_median = stats::median(prec),
    prior_precision_max = max(prec),
    tau_update_count = as.integer(state$tau_update_count %||% 0L),
    global_relative_change = as.numeric(state$last_global_relative_change %||% 0),
    coefficient_l2 = as.numeric(state$last_coefficient_l2 %||% NA_real_),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_ig_entropy <- function(shape, rate) {
  shape <- as.numeric(shape)
  rate <- pmax(as.numeric(rate), .Machine$double.eps)
  out <- shape + log(rate) + lgamma(shape) - (shape + 1) * digamma(shape)
  out[!is.finite(out)] <- NA_real_
  out
}

app_glofas_normal_ig_log_mean <- function(shape, rate) {
  shape <- as.numeric(shape)
  rate <- pmax(as.numeric(rate), .Machine$double.eps)
  out <- log(rate) - digamma(shape)
  out[!is.finite(out)] <- NA_real_
  out
}

app_glofas_normal_rhs_partial_elbo <- function(
  stats,
  theta_mean,
  theta_cov,
  sigma_a,
  sigma_b,
  rhs_state,
  prior_prec,
  sse,
  chol_precision = NULL
) {
  p <- length(theta_mean)
  n <- as.integer(stats$n)
  idx <- as.integer(rhs_state$penalized %||% integer(0))
  sigma_a0 <- 2.0
  sigma_b0 <- 1.0
  sigma_log_mean <- app_glofas_normal_ig_log_mean(sigma_a, sigma_b)
  e_inv_sigma2 <- sigma_a / pmax(sigma_b, .Machine$double.eps)
  expected_log_likelihood <- -0.5 * n * log(2 * pi) -
    0.5 * n * sigma_log_mean -
    0.5 * e_inv_sigma2 * as.numeric(sse)
  expected_log_sigma2_prior <- sigma_a0 * log(sigma_b0) - lgamma(sigma_a0) -
    (sigma_a0 + 1) * sigma_log_mean - sigma_b0 * e_inv_sigma2
  q_sigma2_entropy <- app_glofas_normal_ig_entropy(sigma_a, sigma_b)

  logdet_cov <- NA_real_
  if (!is.null(chol_precision)) {
    diag_chol <- diag(chol_precision)
    if (all(is.finite(diag_chol)) && all(diag_chol > 0)) {
      logdet_cov <- -2 * sum(log(diag_chol))
    }
  }
  if (!is.finite(logdet_cov)) {
    logdet_cov <- as.numeric(determinant(theta_cov, logarithm = TRUE)$modulus)
  }
  q_beta_entropy <- 0.5 * (p * (1 + log(2 * pi)) + logdet_cov)
  e_theta2 <- theta_mean^2 + diag(theta_cov)
  prior_prec <- pmax(as.numeric(prior_prec), .Machine$double.eps)
  expected_log_beta_prior_kernel <- -0.5 * p * log(2 * pi) +
    0.5 * sum(log(prior_prec)) -
    0.5 * sum(prior_prec * e_theta2)

  rhs_scale_prior_kernel <- 0
  q_rhs_scale_entropy <- 0
  rhs_scale_log_precision_approx <- if (length(idx)) 0.5 * sum(log(prior_prec[idx])) else 0
  if (length(idx)) {
    lambda_shape <- rep(1, length(idx))
    lambda_rate <- 1 / pmax(as.numeric(rhs_state$e_inv_lambda2[idx]), .Machine$double.eps)
    nu_shape <- rep(1, length(idx))
    nu_rate <- 1 / pmax(as.numeric(rhs_state$e_inv_nu[idx]), .Machine$double.eps)
    tau_shape <- (length(idx) + 1) / 2
    tau_rate <- tau_shape / pmax(as.numeric(rhs_state$e_inv_tau2), .Machine$double.eps)
    xi_shape <- 1
    xi_rate <- xi_shape / pmax(as.numeric(rhs_state$e_inv_xi), .Machine$double.eps)
    zeta_shape <- as.numeric(rhs_state$a_zeta) + length(idx) / 2
    zeta_rate <- zeta_shape / pmax(as.numeric(rhs_state$e_inv_zeta2), .Machine$double.eps)

    e_log_lambda2 <- app_glofas_normal_ig_log_mean(lambda_shape, lambda_rate)
    e_log_nu <- app_glofas_normal_ig_log_mean(nu_shape, nu_rate)
    e_log_tau2 <- app_glofas_normal_ig_log_mean(tau_shape, tau_rate)
    e_log_xi <- app_glofas_normal_ig_log_mean(xi_shape, xi_rate)
    e_log_zeta2 <- app_glofas_normal_ig_log_mean(zeta_shape, zeta_rate)

    rhs_scale_prior_kernel <- rhs_scale_prior_kernel +
      sum(0.5 * (-e_log_nu) - lgamma(0.5) - 1.5 * e_log_lambda2 -
            as.numeric(rhs_state$e_inv_nu[idx]) * as.numeric(rhs_state$e_inv_lambda2[idx]))
    rhs_scale_prior_kernel <- rhs_scale_prior_kernel +
      sum(-lgamma(0.5) - 1.5 * e_log_nu - as.numeric(rhs_state$e_inv_nu[idx]))
    rhs_scale_prior_kernel <- rhs_scale_prior_kernel +
      0.5 * (-e_log_xi) - lgamma(0.5) - 1.5 * e_log_tau2 -
      as.numeric(rhs_state$e_inv_xi) * as.numeric(rhs_state$e_inv_tau2)
    rhs_scale_prior_kernel <- rhs_scale_prior_kernel +
      log(1 / rhs_state$tau0^2) - 2 * e_log_xi -
      (1 / rhs_state$tau0^2) * as.numeric(rhs_state$e_inv_xi)
    rhs_scale_prior_kernel <- rhs_scale_prior_kernel +
      as.numeric(rhs_state$a_zeta) * log(as.numeric(rhs_state$b_zeta)) -
      lgamma(as.numeric(rhs_state$a_zeta)) -
      (as.numeric(rhs_state$a_zeta) + 1) * e_log_zeta2 -
      as.numeric(rhs_state$b_zeta) * as.numeric(rhs_state$e_inv_zeta2)

    q_rhs_scale_entropy <- sum(app_glofas_normal_ig_entropy(lambda_shape, lambda_rate)) +
      sum(app_glofas_normal_ig_entropy(nu_shape, nu_rate)) +
      app_glofas_normal_ig_entropy(tau_shape, tau_rate) +
      app_glofas_normal_ig_entropy(xi_shape, xi_rate) +
      app_glofas_normal_ig_entropy(zeta_shape, zeta_rate)
  }

  normal_rhs_partial_elbo <- sum(c(
    expected_log_likelihood,
    expected_log_sigma2_prior,
    q_sigma2_entropy,
    expected_log_beta_prior_kernel,
    q_beta_entropy,
    rhs_scale_prior_kernel,
    q_rhs_scale_entropy
  ))
  data.frame(
    normal_rhs_partial_elbo = as.numeric(normal_rhs_partial_elbo),
    expected_log_likelihood = as.numeric(expected_log_likelihood),
    expected_log_sigma2_prior = as.numeric(expected_log_sigma2_prior),
    q_sigma2_entropy = as.numeric(q_sigma2_entropy),
    expected_log_beta_prior_kernel = as.numeric(expected_log_beta_prior_kernel),
    q_beta_entropy = as.numeric(q_beta_entropy),
    rhs_scale_prior_kernel = as.numeric(rhs_scale_prior_kernel),
    q_rhs_scale_entropy = as.numeric(q_rhs_scale_entropy),
    rhs_scale_log_precision_approx = as.numeric(rhs_scale_log_precision_approx),
    elbo_accounting_label = "normal_rhs_partial_mean_field_accounting_log_precision_approx",
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_rhs_fit <- function(
  X,
  y,
  ridge_warm_start,
  tau0 = 1,
  a_zeta = 2,
  b_zeta = 4,
  max_iter = 100L,
  min_iter = 30L,
  tol = 1.0e-4,
  rhs_update_every = 1L,
  freeze_tau_warmup_iters = 0L,
  min_tau_updates = 0L,
  intercept_prec = 1.0e-9,
  jitter = 1.0e-8
) {
  if (!exists("app_latent_rhs_state_init", mode = "function")) {
    stop("app_glofas_normal_rhs_fit requires application/R/latent_path_vb_al.R to be sourced.", call. = FALSE)
  }
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  if (!nrow(X) || !ncol(X) || any(!is.finite(X))) stop("X must be finite.", call. = FALSE)
  if (length(y) != nrow(X) || any(!is.finite(y))) stop("y must match X and be finite.", call. = FALSE)
  max_iter <- as.integer(max_iter)
  min_iter <- as.integer(min_iter)
  tol <- as.numeric(tol)
  tau0 <- as.numeric(tau0)
  if (!is.finite(max_iter) || max_iter < 1L) stop("max_iter must be positive.", call. = FALSE)
  if (!is.finite(min_iter) || min_iter < 1L) stop("min_iter must be positive.", call. = FALSE)
  if (!is.finite(tol) || tol < 0) stop("tol must be finite and nonnegative.", call. = FALSE)
  if (!is.finite(tau0) || tau0 <= 0) stop("tau0 must be positive.", call. = FALSE)
  p <- ncol(X)
  n <- nrow(X)
  app_glofas_normal_part1_validate_ridge_warm_start(ridge_warm_start, strict_hash = FALSE)
  if (as.integer(ridge_warm_start$fit$p) != p) {
    stop("Ridge warm-start dimension does not match X.", call. = FALSE)
  }

  stats <- list(
    n = n,
    p = p,
    XtX = crossprod(X),
    Xty = as.numeric(crossprod(X, y)),
    yty = as.numeric(crossprod(y))
  )
  m <- as.numeric(ridge_warm_start$fit$beta_mean)
  init_var <- pmax(as.numeric(ridge_warm_start$fit$beta_var_diag), 1.0e-12)
  sigma_a0 <- 2.0
  sigma_b0 <- 1.0
  sigma_a <- as.numeric(ridge_warm_start$fit$sigma_a %||% (sigma_a0 + n / 2))
  sigma_b <- as.numeric(ridge_warm_start$fit$sigma_b %||% sigma_b0)
  if (!is.finite(sigma_a) || sigma_a <= 0) sigma_a <- sigma_a0 + n / 2
  if (!is.finite(sigma_b) || sigma_b <= 0) sigma_b <- sigma_b0

  rhs_state <- app_latent_rhs_state_init(
    p = p,
    intercept_index = 1L,
    args = list(
      tau0 = tau0,
      a_zeta = a_zeta,
      b_zeta = b_zeta,
      intercept_prec = intercept_prec
    ),
    rhs_control = list(
      update_every = rhs_update_every,
      freeze_tau_warmup_iters = freeze_tau_warmup_iters,
      min_tau_updates = min_tau_updates
    )
  )
  rhs_state <- app_latent_rhs_state_update(
    rhs_state,
    theta_mean = m,
    theta_cov = diag(init_var, p),
    iter = 0L,
    update_global = FALSE
  )

  trace <- vector("list", max_iter)
  V <- diag(init_var, p)
  Pn <- NULL
  chol_P <- NULL
  converged <- FALSE
  final_delta <- NA_real_
  started <- Sys.time()
  for (iter in seq_len(max_iter)) {
    m_old <- m
    sigma2_old <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
    e_inv_sigma2 <- sigma_a / sigma_b
    prior_prec <- app_latent_rhs_prior_precision(rhs_state, p)
    if (length(prior_prec) != p || any(!is.finite(prior_prec)) || any(prior_prec <= 0)) {
      stop("RHS prior precision must be finite and positive.", call. = FALSE)
    }
    Pn <- e_inv_sigma2 * stats$XtX
    diag(Pn) <- diag(Pn) + prior_prec
    hn <- e_inv_sigma2 * stats$Xty
    sol <- app_glofas_normal_spd_solve(Pn, hn, jitter = jitter)
    m <- sol$x
    V <- sol$inv
    chol_P <- sol$chol
    Emm <- V + tcrossprod(m)
    sse <- stats$yty - 2 * as.numeric(crossprod(m, stats$Xty)) + sum(stats$XtX * Emm)
    sse <- max(as.numeric(sse), .Machine$double.eps)
    sigma_a <- sigma_a0 + n / 2
    sigma_b <- sigma_b0 + 0.5 * sse
    rhs_state <- app_latent_rhs_state_update(
      rhs_state,
      theta_mean = m,
      theta_cov = V,
      iter = iter,
      update_global = NULL
    )
    sigma2_new <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
    beta_delta <- max(abs(m - m_old))
    sigma_delta <- abs(sigma2_new - sigma2_old) / max(1, abs(sigma2_old))
    final_delta <- max(beta_delta, sigma_delta)
    diag_row <- app_glofas_normal_rhs_state_diagnostics(rhs_state, p)
    prior_prec_after <- app_latent_rhs_prior_precision(rhs_state, p)
    elbo_row <- app_glofas_normal_rhs_partial_elbo(
      stats = stats,
      theta_mean = m,
      theta_cov = V,
      sigma_a = sigma_a,
      sigma_b = sigma_b,
      rhs_state = rhs_state,
      prior_prec = prior_prec_after,
      sse = sse,
      chol_precision = chol_P
    )
    previous_elbo <- if (iter > 1L && length(trace[[iter - 1L]]) &&
                          "normal_rhs_partial_elbo" %in% names(trace[[iter - 1L]])) {
      as.numeric(trace[[iter - 1L]]$normal_rhs_partial_elbo[[1L]])
    } else {
      NA_real_
    }
    elbo_now <- as.numeric(elbo_row$normal_rhs_partial_elbo[[1L]])
    elbo_row$normal_rhs_partial_elbo_delta <- if (is.finite(previous_elbo)) {
      elbo_now - previous_elbo
    } else {
      NA_real_
    }
    elbo_row$normal_rhs_partial_elbo_relative_delta <- if (is.finite(previous_elbo)) {
      abs(elbo_now - previous_elbo) / max(1, abs(previous_elbo))
    } else {
      NA_real_
    }
    elbo_row$partial_elbo <- elbo_row$normal_rhs_partial_elbo
    trace[[iter]] <- cbind(
      data.frame(
        iter = iter,
        sigma2_mean = sigma2_new,
        beta_max_abs_delta = beta_delta,
        sigma2_relative_delta = sigma_delta,
        max_delta = final_delta,
        jitter_attempt = sol$jitter_attempt,
        elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
        stringsAsFactors = FALSE
      ),
      diag_row,
      elbo_row
    )
    if (iter >= min_iter && final_delta <= tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      break
    }
  }
  trace_df <- app_bind_rows_fill(trace)
  sigma2_mean <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
  fit <- list(
    type = "normal_rhs_vb",
    beta_mean = m,
    beta_cov = V,
    beta_var_diag = diag(V),
    precision = Pn,
    precision_chol = chol_P,
    sigma_a = sigma_a,
    sigma_b = sigma_b,
    sigma2_mean = sigma2_mean,
    rhs_state = rhs_state,
    rhs_tau0 = tau0,
    a_zeta = a_zeta,
    b_zeta = b_zeta,
    trace = trace_df,
    converged = converged,
    iterations = nrow(trace_df),
    final_delta = final_delta,
    n_train = n,
    p = p,
    uses_vb = TRUE
  )
  class(fit) <- c("glofas_normal_rhs_vb_fit", "list")
  fit
}

app_glofas_normal_rhs_coefficient_table <- function(fit, feature_info = NULL) {
  p <- as.integer(fit$p %||% length(fit$beta_mean))
  beta_mean <- as.numeric(fit$beta_mean)
  beta_sd <- sqrt(pmax(as.numeric(fit$beta_var_diag), 0))
  if (length(beta_mean) != p || length(beta_sd) != p) {
    stop("Fit beta moments are inconsistent.", call. = FALSE)
  }
  feature_info <- feature_info %||% data.frame(
    column_index = seq_len(p),
    column_name = paste0("V", seq_len(p)),
    block = "unknown",
    is_intercept = FALSE,
    stringsAsFactors = FALSE
  )
  out <- data.frame(
    column_index = seq_len(p),
    column_name = as.character(feature_info$column_name %||% paste0("V", seq_len(p))),
    block = as.character(feature_info$block %||% "unknown"),
    is_intercept = app_as_bool_vec(feature_info$is_intercept %||% rep(FALSE, p)),
    beta_mean = beta_mean,
    beta_sd = beta_sd,
    ci95_lower = beta_mean - 1.96 * beta_sd,
    ci95_upper = beta_mean + 1.96 * beta_sd,
    abs_mean = abs(beta_mean),
    z_abs = abs(beta_mean) / pmax(beta_sd, .Machine$double.eps),
    stringsAsFactors = FALSE
  )
  out$active_95 <- out$ci95_lower > 0 | out$ci95_upper < 0
  out$abs_mean_rank <- rank(-out$abs_mean, ties.method = "first")
  out <- out[order(out$abs_mean_rank), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_glofas_normal_rhs_activity_summary <- function(coef_table) {
  blocks <- unique(as.character(coef_table$block))
  app_bind_rows_fill(lapply(blocks, function(block) {
    x <- coef_table[coef_table$block == block, , drop = FALSE]
    data.frame(
      block = block,
      n_coefficients = nrow(x),
      active_95 = sum(x$active_95, na.rm = TRUE),
      active_95_fraction = mean(x$active_95, na.rm = TRUE),
      mean_abs_beta = mean(x$abs_mean, na.rm = TRUE),
      median_abs_beta = stats::median(x$abs_mean, na.rm = TRUE),
      max_abs_beta = max(x$abs_mean, na.rm = TRUE),
      median_beta_sd = stats::median(x$beta_sd, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

app_glofas_normal_part1_score_rhs_candidate <- function(
  base_cfg,
  rhs_row,
  panel_bundle = NULL,
  warm_start = NULL,
  score_train = FALSE,
  strict_hash = TRUE
) {
  rhs_row <- rhs_row[1L, , drop = FALSE]
  started <- Sys.time()
  design <- app_glofas_normal_part1_build_design(base_cfg, rhs_row, panel_bundle = panel_bundle)
  split <- app_glofas_normal_part1_validation_split(
    nrow(design$X),
    rhs_row$validation_n[[1L]] %||% app_glofas_normal_part1_default_values()$validation_n
  )
  train_idx <- split$train_idx
  valid_idx <- split$valid_idx
  if (is.null(warm_start)) {
    warm_start <- app_glofas_normal_part1_rebuild_ridge_warm_start(
      base_cfg = base_cfg,
      candidate_row = rhs_row,
      panel_bundle = panel_bundle,
      hash_design = TRUE
    )
  }
  app_glofas_normal_part1_validate_ridge_warm_start(
    warm_start,
    candidate_row = rhs_row,
    design = design,
    train_idx = train_idx,
    strict_hash = strict_hash
  )
  fit <- app_glofas_normal_rhs_fit(
    X = design$X[train_idx, , drop = FALSE],
    y = design$y[train_idx],
    ridge_warm_start = warm_start,
    tau0 = as.numeric(rhs_row$rhs_tau0[[1L]]),
    max_iter = as.integer(rhs_row$rhs_max_iter[[1L]] %||% 100L),
    min_iter = as.integer(rhs_row$rhs_min_iter[[1L]] %||% 30L),
    tol = as.numeric(rhs_row$rhs_tol[[1L]] %||% 1.0e-4),
    rhs_update_every = as.integer(rhs_row$rhs_update_every[[1L]] %||% 1L),
    freeze_tau_warmup_iters = as.integer(rhs_row$rhs_freeze_tau_warmup_iters[[1L]] %||% 0L),
    min_tau_updates = as.integer(rhs_row$rhs_min_tau_updates[[1L]] %||% 0L)
  )
  valid_pred <- app_glofas_normal_predict(fit, design$X[valid_idx, , drop = FALSE], chunk_size = 64L)
  valid_score <- app_glofas_normal_score_predictions(design$y[valid_idx], valid_pred, prefix = "valid_")
  train_score <- if (isTRUE(score_train)) {
    train_pred <- app_glofas_normal_predict(fit, design$X[train_idx, , drop = FALSE], chunk_size = 64L)
    app_glofas_normal_score_predictions(design$y[train_idx], train_pred, prefix = "train_")
  } else {
    app_glofas_normal_part1_empty_score("train_")
  }
  windows <- c(50L, 200L)
  window_scores <- lapply(windows, function(w) {
    idx <- utils::tail(seq_along(valid_idx), min(w, length(valid_idx)))
    app_glofas_normal_score_predictions(
      design$y[valid_idx][idx],
      list(mean = valid_pred$mean[idx], sd = valid_pred$sd[idx]),
      prefix = paste0("valid_last", w, "_")
    )
  })
  coef_table <- app_glofas_normal_rhs_coefficient_table(fit, design$feature_info)
  activity <- app_glofas_normal_rhs_activity_summary(coef_table)
  reservoir_activity <- activity[activity$block == "reservoir_state", , drop = FALSE]
  if (!nrow(reservoir_activity)) reservoir_activity <- activity[1L, , drop = FALSE]
  trace_tail <- if (nrow(fit$trace)) fit$trace[nrow(fit$trace), , drop = FALSE] else data.frame()
  out_row <- app_glofas_normal_part1_prefix_existing_score_columns(rhs_row)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  summary <- cbind(
    out_row,
    data.frame(
      status = "completed",
      n_rows_design = nrow(design$X),
      n_train = length(train_idx),
      n_valid = length(valid_idx),
      n_readout_features_actual = ncol(design$X),
      n_reservoir_input_features_actual = as.integer((design$design_meta %||% list())$m_input %||% NA_integer_),
      n_dlm_component_input_features = length((design$design_meta %||% list())$reservoir_dlm_component_columns %||% character(0)),
      dlm_timing_effective = as.character((design$dlm_extension %||% list())$timing %||% NA_character_),
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[valid_idx])),
      valid_end_date = as.character(max(design$dates[valid_idx])),
      runtime_seconds = elapsed,
      converged = isTRUE(fit$converged),
      iterations = as.integer(fit$iterations),
      final_delta = as.numeric(fit$final_delta),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      effective_tau = as.numeric(trace_tail$effective_tau[[1L]] %||% NA_real_),
      e_inv_tau2 = as.numeric(trace_tail$e_inv_tau2[[1L]] %||% NA_real_),
      e_inv_zeta2 = as.numeric(trace_tail$e_inv_zeta2[[1L]] %||% NA_real_),
      normal_rhs_partial_elbo = as.numeric(trace_tail$normal_rhs_partial_elbo[[1L]] %||% NA_real_),
      normal_rhs_partial_elbo_delta = as.numeric(trace_tail$normal_rhs_partial_elbo_delta[[1L]] %||% NA_real_),
      normal_rhs_partial_elbo_relative_delta = as.numeric(trace_tail$normal_rhs_partial_elbo_relative_delta[[1L]] %||% NA_real_),
      elbo_accounting_label = as.character(trace_tail$elbo_accounting_label[[1L]] %||%
        "normal_rhs_partial_mean_field_accounting_log_precision_approx"),
      reservoir_active_95 = as.integer(reservoir_activity$active_95[[1L]] %||% NA_integer_),
      reservoir_active_95_fraction = as.numeric(reservoir_activity$active_95_fraction[[1L]] %||% NA_real_),
      reservoir_mean_abs_beta = as.numeric(reservoir_activity$mean_abs_beta[[1L]] %||% NA_real_),
      reservoir_max_abs_beta = as.numeric(reservoir_activity$max_abs_beta[[1L]] %||% NA_real_),
      warm_start_path = as.character((rhs_row$warm_start_path %||% NA_character_)[[1L]]),
      stringsAsFactors = FALSE
    ),
    train_score,
    valid_score,
    do.call(cbind, window_scores)
  )
  detail <- data.frame(
    rhs_candidate_id = as.character(rhs_row$rhs_candidate_id[[1L]]),
    candidate_id = as.character(rhs_row$candidate_id[[1L]]),
    rhs_tau0 = as.numeric(rhs_row$rhs_tau0[[1L]]),
    date = design$dates[valid_idx],
    observed = design$y[valid_idx],
    pred_mean = valid_pred$mean,
    pred_sd = valid_pred$sd,
    crps = app_glofas_normal_crps(design$y[valid_idx], valid_pred$mean, valid_pred$sd),
    abs_error = abs(valid_pred$mean - design$y[valid_idx]),
    squared_error = (valid_pred$mean - design$y[valid_idx])^2,
    stringsAsFactors = FALSE
  )
  list(
    summary = summary,
    detail = detail,
    trace = fit$trace,
    coefficients = coef_table,
    activity = activity,
    fit = fit,
    design = design,
    warm_start = warm_start
  )
}

app_glofas_normal_part1_rhs_failure_row <- function(rhs_row, error, started = Sys.time()) {
  cbind(
    app_glofas_normal_part1_prefix_existing_score_columns(rhs_row),
    data.frame(
      status = "failed",
      error_message = as.character(conditionMessage(error)),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
  )
}

app_glofas_normal_part1_collect_rhs_scores <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  score_files <- list.files(file.path(root, "scores"), pattern = "_rhs_summary[.]csv$", full.names = TRUE)
  detail_files <- list.files(file.path(root, "scores"), pattern = "_rhs_validation_detail[.]csv$", full.names = TRUE)
  summaries <- app_bind_rows_fill(lapply(score_files, app_read_csv))
  details <- app_bind_rows_fill(lapply(detail_files, app_read_csv))
  if (nrow(summaries)) {
    numeric_cols <- intersect(
      c(
        "rhs_tau0", "valid_mean_crps", "valid_mae", "valid_rmse",
        "valid_last50_mean_crps", "valid_last200_mean_crps",
        "train_mean_crps", "runtime_seconds", "iterations",
        "final_delta", "sigma2_mean", "effective_tau",
        "normal_rhs_partial_elbo", "normal_rhs_partial_elbo_delta",
        "normal_rhs_partial_elbo_relative_delta"
      ),
      names(summaries)
    )
    for (nm in numeric_cols) summaries[[nm]] <- suppressWarnings(as.numeric(summaries[[nm]]))
    summaries <- summaries[order(summaries$status != "completed", summaries$valid_mean_crps), , drop = FALSE]
    summaries$rank_valid_crps <- seq_len(nrow(summaries))
  }
  app_write_csv(summaries, file.path(root, "tables", "normal_rhs_scores_latest.csv"))
  app_write_csv(details, file.path(root, "tables", "normal_rhs_validation_detail_latest.csv"))
  summaries
}
