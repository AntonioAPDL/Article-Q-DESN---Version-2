# Constrained p50 screening for the GloFAS two-block Q-DESN application.
#
# This module prepares and ranks median fits. It intentionally does not call a
# scheduler: launch authorization remains a separate, explicit operation.

app_glofas_median_screen_parameters <- function() {
  block_fields <- c(
    "D", "n", "n_tilde", "m", "washout", "alpha", "rho", "pi_w", "pi_in",
    "win_scale_global", "win_scale_bias", "seed", "reservoir_output_lag_max",
    "reservoir_covariate_lag_max", "direct_output_lag_max",
    "direct_covariate_lag_max", "include_input_block", "rhs_tau0"
  )
  c(
    paste0("reference.", block_fields),
    paste0("discrepancy.", block_fields)
  )
}

app_glofas_median_screen_flatten <- function(x, prefix = "") {
  if (is.null(x) || !length(x)) return(list())
  if (!is.list(x) || is.null(names(x))) {
    out <- list(x)
    names(out) <- prefix
    return(out)
  }
  out <- list()
  for (name in names(x)) {
    key <- if (nzchar(prefix)) paste(prefix, name, sep = ".") else name
    value <- x[[name]]
    if (is.list(value) && !is.null(names(value)) && !grepl("[.]", name)) {
      out <- c(out, app_glofas_median_screen_flatten(value, key))
    } else {
      out[[key]] <- value
    }
  }
  out
}

app_glofas_median_screen_normalize_yaml_keys <- function(x) {
  if (!is.list(x)) return(x)
  nms <- names(x)
  if (!is.null(nms)) {
    false_key <- which(nms == "FALSE")
    if (length(false_key)) {
      if (length(false_key) > 1L || "n" %in% nms) {
        stop("Ambiguous YAML keys: quote the DESN width key as 'n'.", call. = FALSE)
      }
      nms[[false_key]] <- "n"
      names(x) <- nms
    }
  }
  lapply(x, app_glofas_median_screen_normalize_yaml_keys)
}

app_glofas_median_screen_space <- function(x) {
  if (is.character(x) && length(x) == 1L) {
    x <- app_read_yaml(app_resolve_path(x, must_work = TRUE))
  }
  if (!is.list(x)) stop("Median screening space must be a YAML mapping or list.", call. = FALSE)
  app_glofas_median_screen_normalize_yaml_keys(x)
}

app_glofas_median_screen_validate_value <- function(name, value) {
  scalar <- unlist(value, use.names = FALSE)
  if (length(scalar) != 1L || is.na(scalar[[1L]])) {
    stop(sprintf("Screening parameter %s must be scalar within each candidate.", name), call. = FALSE)
  }
  if (grepl("include_input_block$", name)) return(invisible(app_as_bool(scalar)))
  value_num <- suppressWarnings(as.numeric(scalar))
  if (!is.finite(value_num)) stop(sprintf("Screening parameter %s must be finite.", name), call. = FALSE)
  if (grepl("[.](D|n|n_tilde|m)$", name) && value_num < 1) {
    stop(sprintf("Screening parameter %s must be positive.", name), call. = FALSE)
  }
  if (grepl("washout$|lag_max$", name) && value_num < 0) {
    stop(sprintf("Screening parameter %s must be nonnegative.", name), call. = FALSE)
  }
  if (grepl("[.]alpha$", name) && (value_num <= 0 || value_num > 1)) {
    stop(sprintf("Screening parameter %s must lie in (0, 1].", name), call. = FALSE)
  }
  if (grepl("[.](pi_w|pi_in)$", name) && (value_num < 0 || value_num > 1)) {
    stop(sprintf("Screening parameter %s must lie in [0, 1].", name), call. = FALSE)
  }
  if (grepl("rho$|win_scale|rhs_tau0$", name) && value_num <= 0) {
    stop(sprintf("Screening parameter %s must be positive.", name), call. = FALSE)
  }
  invisible(value_num)
}

app_glofas_median_screen_validate_mapping <- function(x, label) {
  flat <- app_glofas_median_screen_flatten(x)
  unknown <- setdiff(names(flat), app_glofas_median_screen_parameters())
  if (length(unknown)) {
    stop(sprintf("%s contains unsupported parameters: %s.", label, paste(unknown, collapse = ", ")), call. = FALSE)
  }
  for (name in names(flat)) {
    values <- unlist(flat[[name]], use.names = FALSE)
    if (!length(values)) stop(sprintf("%s parameter %s has no values.", label, name), call. = FALSE)
    for (value in values) app_glofas_median_screen_validate_value(name, value)
  }
  invisible(flat)
}

app_glofas_median_screen_profile_id <- function(profile, label) {
  profile_id <- as.character(profile$profile_id %||% "")
  if (length(profile_id) != 1L || !nzchar(profile_id) || grepl("[^A-Za-z0-9_.-]", profile_id)) {
    stop(sprintf("%s profile_id must be nonempty and path-safe.", label), call. = FALSE)
  }
  profile_id
}

app_glofas_median_screen_validate_linked_factorial <- function(linked) {
  if (is.null(linked) || !length(linked)) return(invisible(NULL))
  allowed <- c(
    "set_id", "require_same_desn", "architecture_profiles",
    "reservoir_memory_profiles", "direct_memory_profiles", "alpha", "rho",
    "prior_profiles"
  )
  unknown <- setdiff(names(linked), allowed)
  if (length(unknown)) {
    stop(sprintf("linked_factorial contains unsupported fields: %s.", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  set_id <- as.character(linked$set_id %||% "linked")
  if (length(set_id) != 1L || !nzchar(set_id) || grepl("[^A-Za-z0-9_.-]", set_id)) {
    stop("linked_factorial.set_id must be nonempty and path-safe.", call. = FALSE)
  }

  required_groups <- c("architecture_profiles", "reservoir_memory_profiles", "direct_memory_profiles", "prior_profiles")
  for (name in required_groups) {
    if (!is.list(linked[[name]]) || !length(linked[[name]])) {
      stop(sprintf("linked_factorial.%s must contain at least one profile.", name), call. = FALSE)
    }
    ids <- vapply(seq_along(linked[[name]]), function(i) {
      app_glofas_median_screen_profile_id(linked[[name]][[i]], sprintf("linked_factorial.%s[[%d]]", name, i))
    }, character(1L))
    if (anyDuplicated(ids)) stop(sprintf("linked_factorial.%s profile_id values must be unique.", name), call. = FALSE)
  }

  for (i in seq_along(linked$architecture_profiles)) {
    profile <- linked$architecture_profiles[[i]]
    label <- sprintf("linked_factorial.architecture_profiles[[%d]]", i)
    D <- suppressWarnings(as.integer(profile$D %||% NA_integer_))
    n <- suppressWarnings(as.integer(profile$n %||% NA_integer_))
    if (!is.finite(D) || D < 1L || !is.finite(n) || n < 1L) {
      stop(sprintf("%s requires positive scalar D and n.", label), call. = FALSE)
    }
    n_tilde <- unlist(profile$n_tilde %||% integer(), use.names = FALSE)
    if (D == 1L && length(n_tilde)) {
      stop(sprintf("%s must omit n_tilde when D=1.", label), call. = FALSE)
    }
    if (D > 1L) {
      if (length(n_tilde) != 1L || !is.finite(as.numeric(n_tilde)) || as.integer(n_tilde) != n) {
        stop(sprintf("%s requires scalar n_tilde=n to preserve width across layers.", label), call. = FALSE)
      }
    }
  }

  for (i in seq_along(linked$reservoir_memory_profiles)) {
    profile <- linked$reservoir_memory_profiles[[i]]
    label <- sprintf("linked_factorial.reservoir_memory_profiles[[%d]]", i)
    values <- c(
      m = profile$m %||% NA,
      reservoir_output_lag_max = profile$reservoir_output_lag_max %||% NA,
      reservoir_covariate_lag_max = profile$reservoir_covariate_lag_max %||% NA
    )
    if (any(!is.finite(as.numeric(values))) || as.integer(values[["m"]]) < 1L ||
        any(as.integer(values[-1L]) < 0L)) {
      stop(sprintf("%s requires finite, nonnegative memory values and positive m.", label), call. = FALSE)
    }
  }

  for (i in seq_along(linked$direct_memory_profiles)) {
    profile <- linked$direct_memory_profiles[[i]]
    label <- sprintf("linked_factorial.direct_memory_profiles[[%d]]", i)
    values <- c(
      direct_output_lag_max = profile$direct_output_lag_max %||% NA,
      direct_covariate_lag_max = profile$direct_covariate_lag_max %||% NA
    )
    if (any(!is.finite(as.numeric(values))) || any(as.integer(values) < 0L)) {
      stop(sprintf("%s requires finite nonnegative direct-memory values.", label), call. = FALSE)
    }
  }

  alpha <- unlist(linked$alpha %||% numeric(), use.names = FALSE)
  rho <- unlist(linked$rho %||% numeric(), use.names = FALSE)
  if (!length(alpha) || !length(rho)) stop("linked_factorial requires nonempty alpha and rho values.", call. = FALSE)
  for (value in alpha) app_glofas_median_screen_validate_value("reference.alpha", value)
  for (value in rho) app_glofas_median_screen_validate_value("reference.rho", value)

  for (i in seq_along(linked$prior_profiles)) {
    profile <- linked$prior_profiles[[i]]
    label <- sprintf("linked_factorial.prior_profiles[[%d]]", i)
    beta_tau <- profile$reference_tau0 %||% NA
    alpha_tau <- profile$discrepancy_tau0 %||% NA
    tryCatch(
      {
        app_glofas_median_screen_validate_value("reference.rhs_tau0", beta_tau)
        app_glofas_median_screen_validate_value("discrepancy.rhs_tau0", alpha_tau)
      },
      error = function(e) stop(sprintf("%s is invalid: %s", label, conditionMessage(e)), call. = FALSE)
    )
  }
  invisible(linked)
}

app_glofas_median_screen_linked_factorial_definitions <- function(linked, global_fixed = list()) {
  app_glofas_median_screen_validate_linked_factorial(linked)
  architectures <- linked$architecture_profiles
  reservoir_memories <- linked$reservoir_memory_profiles
  direct_memories <- linked$direct_memory_profiles
  priors <- linked$prior_profiles
  alpha <- as.numeric(unlist(linked$alpha, use.names = FALSE))
  rho <- as.numeric(unlist(linked$rho, use.names = FALSE))
  grid <- expand.grid(
    architecture = seq_along(architectures),
    reservoir_memory = seq_along(reservoir_memories),
    direct_memory = seq_along(direct_memories),
    alpha = seq_along(alpha),
    rho = seq_along(rho),
    prior = seq_along(priors),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  definitions <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    architecture <- architectures[[grid$architecture[[i]]]]
    reservoir_memory <- reservoir_memories[[grid$reservoir_memory[[i]]]]
    direct_memory <- direct_memories[[grid$direct_memory[[i]]]]
    prior <- priors[[grid$prior[[i]]]]
    values <- global_fixed
    for (block in c("reference", "discrepancy")) {
      prefix <- paste0(block, ".")
      values[[paste0(prefix, "D")]] <- as.integer(architecture$D)
      values[[paste0(prefix, "n")]] <- as.integer(architecture$n)
      if (as.integer(architecture$D) > 1L) {
        values[[paste0(prefix, "n_tilde")]] <- as.integer(architecture$n_tilde)
      }
      values[[paste0(prefix, "m")]] <- as.integer(reservoir_memory$m)
      values[[paste0(prefix, "reservoir_output_lag_max")]] <- as.integer(reservoir_memory$reservoir_output_lag_max)
      values[[paste0(prefix, "reservoir_covariate_lag_max")]] <- as.integer(reservoir_memory$reservoir_covariate_lag_max)
      values[[paste0(prefix, "direct_output_lag_max")]] <- as.integer(direct_memory$direct_output_lag_max)
      values[[paste0(prefix, "direct_covariate_lag_max")]] <- as.integer(direct_memory$direct_covariate_lag_max)
      values[[paste0(prefix, "alpha")]] <- alpha[[grid$alpha[[i]]]]
      values[[paste0(prefix, "rho")]] <- rho[[grid$rho[[i]]]]
    }
    values[["reference.rhs_tau0"]] <- as.numeric(prior$reference_tau0)
    values[["discrepancy.rhs_tau0"]] <- as.numeric(prior$discrepancy_tau0)
    metadata <- list(
      architecture_profile = app_glofas_median_screen_profile_id(architecture, "architecture"),
      reservoir_memory_profile = app_glofas_median_screen_profile_id(reservoir_memory, "reservoir memory"),
      direct_memory_profile = app_glofas_median_screen_profile_id(direct_memory, "direct memory"),
      prior_profile = app_glofas_median_screen_profile_id(prior, "prior")
    )
    definitions[[i]] <- list(
      set_id = as.character(linked$set_id %||% "linked"),
      values = values,
      metadata = metadata,
      label = paste(unlist(metadata, use.names = FALSE), collapse = "__")
    )
  }
  definitions
}

app_glofas_median_screen_validate_space <- function(space, allow_empty = FALSE) {
  space <- app_glofas_median_screen_space(space)
  screen_id <- as.character(space$screen_id %||% "")
  if (!nzchar(screen_id) || grepl("[^A-Za-z0-9_.-]", screen_id)) {
    stop("screen_id must be a nonempty path-safe identifier.", call. = FALSE)
  }
  quantile <- as.numeric((space$fixed %||% list())$quantile_level %||% 0.5)
  if (!isTRUE(all.equal(quantile, 0.5, tolerance = 1e-12))) {
    stop("The constrained median screen supports quantile_level = 0.5 only.", call. = FALSE)
  }
  max_candidates <- suppressWarnings(as.integer((space$execution %||% list())$max_candidates %||% 500L))
  if (!is.finite(max_candidates) || max_candidates < 1L) {
    stop("execution.max_candidates must be a positive integer.", call. = FALSE)
  }
  expected_candidates <- suppressWarnings(as.integer((space$execution %||% list())$expected_candidates %||% NA_integer_))
  if (!is.na(expected_candidates) && (!is.finite(expected_candidates) || expected_candidates < 1L)) {
    stop("execution.expected_candidates must be a positive integer when supplied.", call. = FALSE)
  }
  app_glofas_median_screen_validate_mapping((space$fixed %||% list())$parameters %||% list(), "fixed.parameters")
  sets <- space$candidate_sets %||% list()
  explicit <- space$explicit_candidates %||% list()
  linked <- space$linked_factorial %||% NULL
  if (!is.null(linked) && (length(sets) || length(explicit))) {
    stop("linked_factorial cannot be mixed with candidate_sets or explicit_candidates.", call. = FALSE)
  }
  app_glofas_median_screen_validate_linked_factorial(linked)
  if (!isTRUE(allow_empty) && !length(sets) && !length(explicit) && is.null(linked)) {
    stop("Screening space has no linked_factorial, candidate_sets, or explicit_candidates.", call. = FALSE)
  }
  set_ids <- character()
  for (i in seq_along(sets)) {
    set <- sets[[i]]
    set_id <- as.character(set$set_id %||% "")
    if (!nzchar(set_id) || grepl("[^A-Za-z0-9_.-]", set_id)) {
      stop(sprintf("candidate_sets[[%d]].set_id must be path-safe.", i), call. = FALSE)
    }
    set_ids <- c(set_ids, set_id)
    app_glofas_median_screen_validate_mapping(set$fixed %||% list(), sprintf("candidate set %s fixed", set_id))
    varying <- app_glofas_median_screen_validate_mapping(set$varying %||% list(), sprintf("candidate set %s varying", set_id))
    if (!length(varying)) stop(sprintf("Candidate set %s has no varying parameters.", set_id), call. = FALSE)
  }
  if (anyDuplicated(set_ids)) stop("Candidate-set IDs must be unique.", call. = FALSE)
  for (i in seq_along(explicit)) {
    app_glofas_median_screen_validate_mapping(
      explicit[[i]]$parameters %||% explicit[[i]],
      sprintf("explicit candidate %d", i)
    )
    metadata <- explicit[[i]]$metadata %||% list()
    allowed_metadata <- c(
      "source_candidate_id", "warm_start_source_fit_object",
      "warm_start_source_config", "warm_start_policy", "candidate_role",
      "require_linked_desn"
    )
    unknown_metadata <- setdiff(names(metadata), allowed_metadata)
    if (length(unknown_metadata)) {
      stop(sprintf(
        "explicit candidate %d contains unsupported metadata: %s.",
        i, paste(unknown_metadata, collapse = ", ")
      ), call. = FALSE)
    }
    warm_policy <- tolower(as.character(metadata$warm_start_policy %||% "auto"))
    if (length(warm_policy) != 1L || !warm_policy %in% c("auto", "cold")) {
      stop(sprintf(
        "explicit candidate %d warm_start_policy must be 'auto' or 'cold'.",
        i
      ), call. = FALSE)
    }
    if (identical(warm_policy, "cold") &&
        (!is.null(metadata$warm_start_source_fit_object) || !is.null(metadata$warm_start_source_config))) {
      stop(sprintf(
        "explicit candidate %d cannot supply warm-start artifacts when warm_start_policy='cold'.",
        i
      ), call. = FALSE)
    }
    if (!is.null(metadata$require_linked_desn)) {
      invisible(app_as_bool(metadata$require_linked_desn))
    }
  }
  invisible(space)
}

app_glofas_median_screen_grid <- function(varying) {
  varying <- app_glofas_median_screen_flatten(varying)
  values <- lapply(varying, function(x) unlist(x, use.names = FALSE))
  if (!length(values)) return(data.frame(.row = 1L)[, FALSE, drop = FALSE])
  do.call(
    expand.grid,
    c(values, list(KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE))
  )
}

app_glofas_median_screen_hash_values <- function(values) {
  values <- values[sort(names(values))]
  substr(app_qdesn_hash_object(values, prefix = "median_candidate_"), 1L, 10L)
}

app_glofas_median_screen_candidate_manifest <- function(space) {
  space <- app_glofas_median_screen_validate_space(space)
  global_fixed <- app_glofas_median_screen_flatten((space$fixed %||% list())$parameters %||% list())
  rows <- list()
  append_row <- function(set_id, values, label = NA_character_, metadata = list()) {
    for (name in names(values)) app_glofas_median_screen_validate_value(name, values[[name]])
    hash <- app_glofas_median_screen_hash_values(values)
    row <- as.data.frame(values, stringsAsFactors = FALSE, optional = TRUE)
    identity <- data.frame(
      candidate_id = sprintf("%s_%03d_%s", set_id, length(rows) + 1L, hash),
      candidate_set = set_id,
      candidate_label = as.character(label %||% NA_character_),
      candidate_hash = hash,
      stringsAsFactors = FALSE
    )
    if (length(metadata)) {
      identity <- cbind(identity, as.data.frame(metadata, stringsAsFactors = FALSE, optional = TRUE))
    }
    row <- cbind(identity, row)
    rows[[length(rows) + 1L]] <<- row
  }

  linked <- space$linked_factorial %||% NULL
  if (!is.null(linked)) {
    definitions <- app_glofas_median_screen_linked_factorial_definitions(linked, global_fixed)
    for (definition in definitions) {
      append_row(
        definition$set_id,
        definition$values,
        label = definition$label,
        metadata = definition$metadata
      )
    }
  }

  for (set in space$candidate_sets %||% list()) {
    set_id <- as.character(set$set_id)
    set_fixed <- app_glofas_median_screen_flatten(set$fixed %||% list())
    grid <- app_glofas_median_screen_grid(set$varying %||% list())
    for (i in seq_len(nrow(grid))) {
      values <- app_qdesn_deep_merge(global_fixed, set_fixed)
      for (name in names(grid)) values[[name]] <- grid[[name]][[i]]
      append_row(set_id, values)
    }
  }
  for (i in seq_along(space$explicit_candidates %||% list())) {
    candidate <- space$explicit_candidates[[i]]
    values <- app_qdesn_deep_merge(
      global_fixed,
      app_glofas_median_screen_flatten(candidate$parameters %||% candidate)
    )
    append_row(
      as.character(candidate$set_id %||% "explicit"),
      values,
      label = candidate$candidate_label %||% candidate$candidate_id %||% NA_character_,
      metadata = candidate$metadata %||% list()
    )
  }
  manifest <- app_bind_rows_fill(rows)
  if (!nrow(manifest)) stop("Screening expansion produced no candidates.", call. = FALSE)
  parameter_columns <- intersect(app_glofas_median_screen_parameters(), names(manifest))
  treatment_columns <- intersect("warm_start_policy", names(manifest))
  dedupe_columns <- c(parameter_columns, treatment_columns)
  dedupe_key <- apply(manifest[, dedupe_columns, drop = FALSE], 1L, function(x) paste(x, collapse = "\r"))
  manifest <- manifest[!duplicated(dedupe_key), , drop = FALSE]
  max_candidates <- as.integer((space$execution %||% list())$max_candidates %||% 500L)
  if (nrow(manifest) > max_candidates) {
    stop(sprintf(
      "Screening expansion produced %d candidates, above execution.max_candidates=%d.",
      nrow(manifest), max_candidates
    ), call. = FALSE)
  }
  expected_candidates <- suppressWarnings(as.integer((space$execution %||% list())$expected_candidates %||% NA_integer_))
  if (!is.na(expected_candidates) && nrow(manifest) != expected_candidates) {
    stop(sprintf(
      "Screening expansion produced %d unique candidates, not execution.expected_candidates=%d.",
      nrow(manifest), expected_candidates
    ), call. = FALSE)
  }
  manifest$priority <- seq_len(nrow(manifest))
  manifest$quantile_level <- 0.5
  manifest$launch_authorized <- app_as_bool(space$launch_authorized %||% FALSE)
  rownames(manifest) <- NULL
  manifest
}

app_glofas_median_screen_row_value <- function(row, name, default = NULL) {
  if (!name %in% names(row)) return(default)
  value <- row[[name]][[1L]]
  if (length(value) == 0L || is.na(value) || (is.character(value) && !nzchar(value))) default else value
}

app_glofas_median_screen_homogeneous <- function(x, D, name) {
  x <- unlist(x %||% numeric(), use.names = FALSE)
  if (!length(x)) return(x)
  if (length(x) == 1L) return(rep(x, D))
  if (length(x) == D) return(x)
  if (length(unique(x)) == 1L) return(rep(x[[1L]], D))
  stop(sprintf("Cannot resize heterogeneous %s to D=%d without an explicit candidate value.", name, D), call. = FALSE)
}

app_glofas_median_screen_apply_block <- function(cfg, row, block) {
  prefix <- paste0(block, ".")
  override <- app_qdesn_block_override(cfg, block)
  effective <- app_qdesn_block_config(cfg, block)
  reservoir <- effective$reservoir %||% list()
  D <- as.integer(app_glofas_median_screen_row_value(row, paste0(prefix, "D"), reservoir$D %||% 1L))
  reservoir$D <- D

  layer_fields <- c("n", "alpha", "rho", "pi_w", "pi_in")
  for (field in layer_fields) {
    candidate_value <- app_glofas_median_screen_row_value(row, paste0(prefix, field), NULL)
    source_value <- candidate_value %||% reservoir[[field]]
    reservoir[[field]] <- app_glofas_median_screen_homogeneous(source_value, D, paste0(block, ".", field))
  }
  n_tilde_value <- app_glofas_median_screen_row_value(row, paste0(prefix, "n_tilde"), NULL) %||% reservoir$n_tilde
  reservoir$n_tilde <- if (D == 1L) integer(0) else {
    app_glofas_median_screen_homogeneous(n_tilde_value, D - 1L, paste0(block, ".n_tilde"))
  }
  for (field in c("m", "washout", "win_scale_global", "win_scale_bias")) {
    value <- app_glofas_median_screen_row_value(row, paste0(prefix, field), NULL)
    if (!is.null(value)) reservoir[[field]] <- value
  }
  seed <- app_glofas_median_screen_row_value(row, paste0(prefix, "seed"), NULL)
  if (!is.null(seed)) override[["reservoir_seed"]] <- as.integer(seed)
  override[["reservoir"]] <- reservoir

  reservoir_input <- override[["reservoir_input"]] %||% list()
  m_changed <- !is.null(app_glofas_median_screen_row_value(row, paste0(prefix, "m"), NULL))
  output_max <- app_glofas_median_screen_row_value(row, paste0(prefix, "reservoir_output_lag_max"), NULL)
  covariate_max <- app_glofas_median_screen_row_value(row, paste0(prefix, "reservoir_covariate_lag_max"), NULL)
  if (is.null(output_max) && isTRUE(m_changed)) output_max <- as.integer(reservoir$m)
  if (is.null(covariate_max) && isTRUE(m_changed)) covariate_max <- max(0L, as.integer(reservoir$m) - 1L)
  if (!is.null(output_max)) reservoir_input$output_lags <- list(range = c(1L, as.integer(output_max)))
  if (!is.null(covariate_max)) {
    reservoir_input$covariates <- list(
      ppt = list(range = c(0L, as.integer(covariate_max))),
      soil = list(range = c(0L, as.integer(covariate_max)))
    )
  }
  if (length(reservoir_input)) override[["reservoir_input"]] <- reservoir_input

  readout <- override[["readout"]] %||% list()
  include_input <- app_glofas_median_screen_row_value(row, paste0(prefix, "include_input_block"), NULL)
  if (!is.null(include_input)) readout$include_input_block <- app_as_bool(include_input)
  direct_output_max <- app_glofas_median_screen_row_value(row, paste0(prefix, "direct_output_lag_max"), NULL)
  direct_covariate_max <- app_glofas_median_screen_row_value(row, paste0(prefix, "direct_covariate_lag_max"), NULL)
  if (!is.null(direct_output_max)) {
    readout$include_input_block <- TRUE
    readout$input_block$output_lags <- list(range = c(1L, as.integer(direct_output_max)))
  }
  if (!is.null(direct_covariate_max)) {
    readout$include_input_block <- TRUE
    readout$input_block$covariates <- list(
      ppt = list(range = c(0L, as.integer(direct_covariate_max))),
      soil = list(range = c(0L, as.integer(direct_covariate_max)))
    )
  }
  if (length(readout)) override[["readout"]] <- readout

  fc <- cfg$feature_contract %||% cfg$features %||% list()
  fc$two_block_design <- TRUE
  if (is.null(fc$version) || !nzchar(as.character(fc$version[[1L]]))) fc$version <- "0.3"
  fc$blocks <- fc$blocks %||% list()
  fc$blocks[[block]] <- override
  cfg$feature_contract <- fc
  cfg
}

app_glofas_median_screen_apply_candidate <- function(base_cfg, row) {
  if (!is.data.frame(row) || nrow(row) != 1L) stop("Candidate row must contain exactly one row.", call. = FALSE)
  cfg <- app_glofas_median_screen_apply_block(base_cfg, row, "reference")
  cfg <- app_glofas_median_screen_apply_block(cfg, row, "discrepancy")
  beta_tau <- app_glofas_median_screen_row_value(row, "reference.rhs_tau0", NULL)
  alpha_tau <- app_glofas_median_screen_row_value(row, "discrepancy.rhs_tau0", NULL)
  if (!is.null(beta_tau)) cfg$inference$vb_ld$rhs_tau0 <- as.numeric(beta_tau)
  if (!is.null(alpha_tau)) cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(alpha_tau)
  app_qdesn_validate_block_configs(cfg)
  cfg
}

app_glofas_median_screen_layout_signature <- function(cfg, block) {
  block_cfg <- app_qdesn_block_config(cfg, block)
  reservoir <- block_cfg$reservoir %||% list()
  contract <- app_feature_contract(block_cfg)
  app_qdesn_hash_object(list(
    block = block,
    D = as.integer(reservoir$D),
    n = as.integer(unlist(reservoir$n, use.names = FALSE)),
    n_tilde = as.integer(unlist(reservoir$n_tilde %||% integer(), use.names = FALSE)),
    m = as.integer(reservoir$m),
    washout = as.integer(reservoir$washout),
    seed = as.integer(app_qdesn_block_override(cfg, block)[["reservoir_seed"]] %||% reservoir$seed),
    reservoir_input = contract$reservoir_input,
    readout = contract$readout,
    forecast_alignment = contract$forecast_alignment
  ), prefix = paste0("median_layout_", block, "_"))
}

app_glofas_median_screen_design_signature <- function(cfg, block) {
  block_cfg <- app_qdesn_block_config(cfg, block)
  reservoir <- block_cfg$reservoir %||% list()
  contract <- app_feature_contract(block_cfg)
  app_qdesn_hash_object(list(
    block = block,
    D = as.integer(reservoir$D),
    n = as.integer(unlist(reservoir$n, use.names = FALSE)),
    n_tilde = as.integer(unlist(reservoir$n_tilde %||% integer(), use.names = FALSE)),
    m = as.integer(reservoir$m),
    washout = as.integer(reservoir$washout),
    alpha = as.numeric(unlist(reservoir$alpha, use.names = FALSE)),
    rho = as.numeric(unlist(reservoir$rho, use.names = FALSE)),
    pi_w = as.numeric(unlist(reservoir$pi_w, use.names = FALSE)),
    pi_in = as.numeric(unlist(reservoir$pi_in, use.names = FALSE)),
    win_scale_global = as.numeric(reservoir$win_scale_global),
    win_scale_bias = as.numeric(reservoir$win_scale_bias),
    input_bound = as.character(reservoir$input_bound %||% "none"),
    act_f = as.character(reservoir$act_f %||% "tanh"),
    act_k = as.character(reservoir$act_k %||% "identity"),
    standardize_inputs = app_as_bool(reservoir$standardize_inputs %||% TRUE),
    add_bias = app_as_bool(reservoir$add_bias %||% TRUE),
    seed = as.integer(app_qdesn_block_override(cfg, block)[["reservoir_seed"]] %||% reservoir$seed),
    reservoir_input = contract$reservoir_input,
    readout = contract$readout,
    forecast_alignment = contract$forecast_alignment
  ), prefix = paste0("median_design_", block, "_"))
}

app_glofas_median_screen_linked_desn_contract <- function(cfg) {
  block_spec <- function(block) {
    block_cfg <- app_qdesn_block_config(cfg, block)
    reservoir <- block_cfg$reservoir %||% list()
    feature_contract <- app_feature_contract(block_cfg)
    list(
      reservoir = list(
        D = as.integer(reservoir$D),
        n = as.integer(unlist(reservoir$n, use.names = FALSE)),
        n_tilde = as.integer(unlist(reservoir$n_tilde %||% integer(), use.names = FALSE)),
        m = as.integer(reservoir$m),
        washout = as.integer(reservoir$washout),
        alpha = as.numeric(unlist(reservoir$alpha, use.names = FALSE)),
        rho = as.numeric(unlist(reservoir$rho, use.names = FALSE)),
        pi_w = as.numeric(unlist(reservoir$pi_w, use.names = FALSE)),
        pi_in = as.numeric(unlist(reservoir$pi_in, use.names = FALSE)),
        win_scale_global = as.numeric(reservoir$win_scale_global),
        win_scale_bias = as.numeric(reservoir$win_scale_bias),
        input_bound = as.character(reservoir$input_bound %||% "none"),
        act_f = as.character(reservoir$act_f %||% "tanh"),
        act_k = as.character(reservoir$act_k %||% "identity"),
        standardize_inputs = app_as_bool(reservoir$standardize_inputs %||% TRUE),
        add_bias = app_as_bool(reservoir$add_bias %||% TRUE)
      ),
      reservoir_input = feature_contract$reservoir_input,
      readout = feature_contract$readout
    )
  }
  reference <- block_spec("reference")
  discrepancy <- block_spec("discrepancy")
  reference_hash <- app_qdesn_hash_object(reference, prefix = "linked_desn_")
  discrepancy_hash <- app_qdesn_hash_object(discrepancy, prefix = "linked_desn_")
  list(
    pass = identical(reference_hash, discrepancy_hash),
    reference_hash = reference_hash,
    discrepancy_hash = discrepancy_hash,
    reference_seed = app_qdesn_block_seed(data.frame(), cfg, "reference"),
    discrepancy_seed = app_qdesn_block_seed(data.frame(), cfg, "discrepancy")
  )
}

app_glofas_median_screen_warm_start_plan <- function(base_cfg, candidate_cfg, source_fit = NULL, source_contract = NULL) {
  source_ok <- !is.null(source_fit) && nzchar(as.character(source_fit[[1L]])) && file.exists(as.character(source_fit[[1L]]))
  contract_ok <- !is.null(source_contract) && length(source_contract)
  if (!source_ok || !contract_ok) {
    return(list(
      enabled = FALSE,
      compatibility_mode = "cold",
      use_theta = FALSE,
      use_future = FALSE,
      use_sigma = FALSE,
      requires_cold_confirmation = FALSE,
      reason = if (!source_ok) "source fit unavailable" else "source semantic contract unavailable"
    ))
  }
  exact <- all(vapply(c("reference", "discrepancy"), function(block) {
    identical(
      app_glofas_median_screen_design_signature(base_cfg, block),
      app_glofas_median_screen_design_signature(candidate_cfg, block)
    )
  }, logical(1L)))
  same_layout <- all(vapply(c("reference", "discrepancy"), function(block) {
    identical(
      app_glofas_median_screen_layout_signature(base_cfg, block),
      app_glofas_median_screen_layout_signature(candidate_cfg, block)
    )
  }, logical(1L)))
  if (exact) {
    return(list(
      enabled = TRUE, compatibility_mode = "exact_design", use_theta = TRUE,
      use_future = TRUE, use_sigma = TRUE, requires_cold_confirmation = FALSE,
      reason = "only prior or non-design controls differ"
    ))
  }
  if (same_layout) {
    return(list(
      enabled = TRUE, compatibility_mode = "coordinate_transfer", use_theta = TRUE,
      use_future = TRUE, use_sigma = TRUE, requires_cold_confirmation = TRUE,
      reason = "feature coordinates match but reservoir values differ"
    ))
  }
  list(
    enabled = TRUE, compatibility_mode = "state_only", use_theta = FALSE,
    use_future = TRUE, use_sigma = TRUE, requires_cold_confirmation = TRUE,
    reason = "feature coordinates differ; coefficient transfer is prohibited"
  )
}

app_glofas_median_screen_baseline_contract <- function(x) {
  contract_path <- NA_character_
  if (is.character(x) && length(x) == 1L) {
    contract_path <- app_resolve_path(x, must_work = TRUE)
    x <- app_read_yaml(contract_path)
  }
  if (!is.list(x)) stop("Median-screen baseline contract must be a YAML mapping or list.", call. = FALSE)
  x <- app_glofas_median_screen_normalize_yaml_keys(x)
  required <- c("version", "baseline_id", "candidate_id", "artifacts", "metrics", "engine")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("Median-screen baseline contract is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  attr(x, "contract_path") <- contract_path
  x
}

app_glofas_median_screen_artifact <- function(contract, name) {
  entry <- (contract$artifacts %||% list())[[name]]
  if (is.null(entry)) stop(sprintf("Baseline contract is missing artifact '%s'.", name), call. = FALSE)
  if (is.character(entry) && length(entry) == 1L) entry <- list(path = entry)
  path_value <- as.character(entry$path %||% "")
  expected_sha <- tolower(as.character(entry$sha256 %||% ""))
  if (!nzchar(path_value) || !nzchar(expected_sha)) {
    stop(sprintf("Baseline artifact '%s' requires path and sha256.", name), call. = FALSE)
  }
  path <- app_resolve_path(path_value, must_work = TRUE)
  actual_sha <- tolower(app_sha256_file(path))
  if (!identical(actual_sha, expected_sha)) {
    stop(sprintf(
      "Baseline artifact '%s' failed SHA-256 verification: expected %s, found %s.",
      name, expected_sha, actual_sha
    ), call. = FALSE)
  }
  list(name = name, path = path, expected_sha256 = expected_sha, actual_sha256 = actual_sha)
}

app_glofas_median_screen_future_key <- function(predictions) {
  required <- c("model_family", "quantile_level", "target_date", "horizon")
  missing <- setdiff(required, names(predictions))
  if (!is.data.frame(predictions) || !nrow(predictions) || length(missing)) {
    stop(sprintf("Prediction table is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  keep <- predictions$model_family == "qdesn_glofas_discrepancy" &
    abs(as.numeric(predictions$quantile_level) - 0.5) < 1e-12
  future_key <- predictions[keep, c("target_date", "horizon"), drop = FALSE]
  future_key$target_date <- as.character(as.Date(future_key$target_date))
  future_key$horizon <- as.integer(future_key$horizon)
  future_key <- unique(future_key)
  future_key <- future_key[order(future_key$horizon, future_key$target_date), , drop = FALSE]
  rownames(future_key) <- NULL
  if (!nrow(future_key) || anyDuplicated(future_key$horizon)) {
    stop("Prediction table does not define one unique p50 Q-DESN row per horizon.", call. = FALSE)
  }
  future_key
}

app_glofas_median_screen_assert_metric <- function(actual, expected, label, tolerance = 1e-12) {
  actual <- as.numeric(actual)
  expected <- as.numeric(expected)
  if (length(actual) != 1L || length(expected) != 1L || !is.finite(actual) || !is.finite(expected) ||
      !isTRUE(all.equal(actual, expected, tolerance = tolerance))) {
    stop(sprintf(
      "Baseline metric '%s' does not match its evidence (declared %.16g; observed %.16g).",
      label, expected, actual
    ), call. = FALSE)
  }
  invisible(actual)
}

app_glofas_median_screen_verify_baseline <- function(x) {
  contract <- app_glofas_median_screen_baseline_contract(x)
  required_artifacts <- c(
    "base_config", "base_model_grid", "source_fit", "observed_scores",
    "forecast_scores", "design_summary", "prediction_quantiles",
    "source_warm_contract", "authoritative_model_spec", "promotion_decision"
  )
  artifacts <- setNames(lapply(required_artifacts, function(name) {
    app_glofas_median_screen_artifact(contract, name)
  }), required_artifacts)

  candidate_id <- as.character(contract$candidate_id[[1L]])
  base_cfg <- app_read_config(artifacts$base_config$path)
  model_grid <- app_read_csv(artifacts$base_model_grid$path)
  quantile <- suppressWarnings(as.numeric(model_grid$quantile_level))
  qrow <- model_grid$model_family == "qdesn_glofas_discrepancy" & abs(quantile - 0.5) < 1e-12
  if (sum(qrow) != 1L) stop("Verified baseline model grid must contain exactly one p50 Q-DESN row.", call. = FALSE)

  model_spec <- app_read_csv(artifacts$authoritative_model_spec$path)
  model_spec <- model_spec[as.character(model_spec$candidate_id) == candidate_id, , drop = FALSE]
  if (nrow(model_spec) != 1L) stop("Authoritative model-spec registry does not contain exactly one baseline row.", call. = FALSE)
  config_sha <- tolower(artifacts$base_config$actual_sha256)
  if (!identical(tolower(as.character(model_spec$source_config_sha256[[1L]])), config_sha)) {
    stop("Authoritative model-spec registry does not identify the verified base config.", call. = FALSE)
  }

  promotion <- app_read_csv(artifacts$promotion_decision$path)
  promoted <- as.character(promotion$candidate_id) == candidate_id &
    as.character(promotion$decision) == "promote_authoritative"
  if (sum(promoted) != 1L) stop("Baseline candidate is not uniquely marked promote_authoritative.", call. = FALSE)

  warm_contract <- app_latent_path_read_warm_start_contract(artifacts$source_warm_contract$path)
  compatibility_fields <- c("design_hash", "quantile_level", "n_theta", "theta_names_hash", "n_future", "future_key_hash")
  missing_contract <- setdiff(compatibility_fields, names(warm_contract %||% list()))
  if (length(missing_contract)) {
    stop(sprintf("Source warm-start contract is missing: %s.", paste(missing_contract, collapse = ", ")), call. = FALSE)
  }

  design_summary <- app_read_csv(artifacts$design_summary$path)
  design_summary <- design_summary[abs(as.numeric(design_summary$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
  if (nrow(design_summary) != 1L) stop("Baseline design summary must contain exactly one p50 row.", call. = FALSE)
  if (!identical(as.character(design_summary$design_hash[[1L]]), as.character(warm_contract$design_hash))) {
    stop("Warm-start design hash does not match the verified design summary.", call. = FALSE)
  }
  if (!identical(as.integer(design_summary$n_augmented_features[[1L]]), as.integer(warm_contract$n_theta))) {
    stop("Warm-start coefficient dimension does not match the verified design summary.", call. = FALSE)
  }
  if (!identical(as.integer(design_summary$n_future_dates[[1L]]), as.integer(warm_contract$n_future))) {
    stop("Warm-start future dimension does not match the verified design summary.", call. = FALSE)
  }

  predictions <- app_read_csv(artifacts$prediction_quantiles$path)
  future_key <- app_glofas_median_screen_future_key(predictions)
  future_key_hash <- app_latent_path_contract_hash(future_key, "future_key_")
  if (!identical(future_key_hash, as.character(warm_contract$future_key_hash))) {
    stop("Warm-start future-key hash does not match the verified p50 prediction table.", call. = FALSE)
  }

  source <- app_latent_path_warm_start_fit(artifacts$source_fit$path)
  theta <- source$fit$variational_state$theta_mean %||% source$fit$summary$theta_mean %||% NULL
  y_future <- source$fit$variational_state$y_future_mean %||% source$fit$summary$y_future_mean %||% NULL
  if (is.null(theta) || length(theta) != as.integer(warm_contract$n_theta) || any(!is.finite(theta))) {
    stop("Verified source fit does not contain a finite coefficient state matching the warm-start contract.", call. = FALSE)
  }
  if (is.null(y_future) || length(y_future) != as.integer(warm_contract$n_future) || any(!is.finite(y_future))) {
    stop("Verified source fit does not contain a finite future-path state matching the warm-start contract.", call. = FALSE)
  }

  metrics <- contract$metrics %||% list()
  missing_metrics <- setdiff(app_glofas_median_screen_baseline_required(), names(metrics))
  if (length(missing_metrics)) {
    stop(sprintf("Baseline contract metrics are missing: %s.", paste(missing_metrics, collapse = ", ")), call. = FALSE)
  }
  observed <- app_read_csv(artifacts$observed_scores$path)
  observed <- observed[abs(as.numeric(observed$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
  metric_windows <- c(
    observed_log1p_mae_all = "all",
    observed_log1p_mae_last1000 = "last1000",
    observed_log1p_mae_last200 = "last200",
    observed_log1p_mae_last50 = "last50"
  )
  for (metric_name in names(metric_windows)) {
    hit <- observed[as.character(observed$window) == metric_windows[[metric_name]], , drop = FALSE]
    if (nrow(hit) != 1L) stop(sprintf("Observed-score evidence lacks one %s row.", metric_windows[[metric_name]]), call. = FALSE)
    app_glofas_median_screen_assert_metric(hit$log1p_mae[[1L]], metrics[[metric_name]], metric_name)
  }
  forecast <- app_read_csv(artifacts$forecast_scores$path)
  forecast <- forecast[grepl("^qdesn_", as.character(forecast$model_id)), , drop = FALSE]
  if (nrow(forecast) != 1L) stop("Forecast-score evidence lacks exactly one p50 Q-DESN row.", call. = FALSE)
  app_glofas_median_screen_assert_metric(
    forecast$check_loss_mean[[1L]], metrics$forecast_p50_check_loss_mean,
    "forecast_p50_check_loss_mean"
  )

  audit <- do.call(rbind, lapply(artifacts, function(item) {
    data.frame(
      artifact = item$name,
      path = item$path,
      sha256 = item$actual_sha256,
      verified = TRUE,
      stringsAsFactors = FALSE
    )
  }))
  rownames(audit) <- NULL
  list(
    contract = contract,
    contract_path = attr(contract, "contract_path"),
    contract_sha256 = if (!is.na(attr(contract, "contract_path"))) app_sha256_file(attr(contract, "contract_path")) else NA_character_,
    artifacts = artifacts,
    base_cfg = base_cfg,
    model_grid = model_grid,
    source_contract = warm_contract,
    metrics = metrics,
    audit = audit
  )
}

app_glofas_median_screen_baseline_required <- function() {
  c(
    "forecast_p50_check_loss_mean", "observed_log1p_mae_all",
    "observed_log1p_mae_last1000", "observed_log1p_mae_last200",
    "observed_log1p_mae_last50"
  )
}

app_glofas_median_screen_policy <- function(x = NULL) {
  defaults <- list(
    max_observed_ratio_all = 1.05,
    max_observed_ratio_last1000 = 1.05,
    max_observed_ratio_last200 = 1.10,
    max_observed_ratio_last50 = 1.15,
    last50_is_hard_gate = FALSE,
    min_forecast_improvement_fraction = 0.03
  )
  app_qdesn_deep_merge(defaults, x %||% list())
}

app_glofas_median_screen_wide_history <- function(scores) {
  required <- c("candidate_id", "window", "log1p_mae")
  missing <- setdiff(required, names(scores))
  if (!is.data.frame(scores) || !nrow(scores) || length(missing)) {
    stop(sprintf("Observed-score table is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  wanted <- c("all", "last1000", "last200", "last50")
  rows <- lapply(split(scores, scores$candidate_id), function(x) {
    values <- setNames(rep(NA_real_, length(wanted)), wanted)
    for (window in intersect(wanted, as.character(x$window))) {
      hit <- x[as.character(x$window) == window, , drop = FALSE]
      if (nrow(hit) != 1L) stop(sprintf("Candidate %s has duplicate %s scores.", x$candidate_id[[1L]], window), call. = FALSE)
      values[[window]] <- as.numeric(hit$log1p_mae[[1L]])
    }
    data.frame(
      candidate_id = x$candidate_id[[1L]],
      observed_log1p_mae_all = values[["all"]],
      observed_log1p_mae_last1000 = values[["last1000"]],
      observed_log1p_mae_last200 = values[["last200"]],
      observed_log1p_mae_last50 = values[["last50"]],
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_median_screen_rank <- function(
  observed_scores,
  forecast_scores,
  baseline,
  policy = app_glofas_median_screen_policy(),
  technical_status = NULL
) {
  missing_baseline <- setdiff(app_glofas_median_screen_baseline_required(), names(baseline %||% list()))
  if (length(missing_baseline)) {
    stop(sprintf("Median-screen baseline is missing: %s.", paste(missing_baseline, collapse = ", ")), call. = FALSE)
  }
  policy <- app_glofas_median_screen_policy(policy)
  history <- app_glofas_median_screen_wide_history(observed_scores)
  required_forecast <- c("candidate_id", "forecast_p50_check_loss_mean")
  missing_forecast <- setdiff(required_forecast, names(forecast_scores))
  if (!is.data.frame(forecast_scores) || !nrow(forecast_scores) || length(missing_forecast)) {
    stop(sprintf("Forecast-score table is empty or missing: %s.", paste(missing_forecast, collapse = ", ")), call. = FALSE)
  }
  out <- merge(history, forecast_scores[, required_forecast, drop = FALSE], by = "candidate_id", all = TRUE)
  if (!is.null(technical_status)) {
    if (!all(c("candidate_id", "technical_gate_pass") %in% names(technical_status))) {
      stop("technical_status requires candidate_id and technical_gate_pass.", call. = FALSE)
    }
    out <- merge(out, technical_status[, c("candidate_id", "technical_gate_pass"), drop = FALSE], by = "candidate_id", all.x = TRUE)
  } else {
    out$technical_gate_pass <- TRUE
  }
  out$technical_gate_pass <- app_as_bool_vec(out$technical_gate_pass)
  if (any(is.na(out$technical_gate_pass))) {
    stop("Median-screen ranking requires a finite technical gate for every candidate.", call. = FALSE)
  }
  numeric_fields <- c(required_forecast[[2L]], setdiff(app_glofas_median_screen_baseline_required(), "forecast_p50_check_loss_mean"))
  if (any(!vapply(out[numeric_fields], function(x) all(is.finite(as.numeric(x))), logical(1L)))) {
    stop("Median-screen ranking requires finite forecast and historical metrics for every candidate.", call. = FALSE)
  }
  gate <- function(field, baseline_field, ratio) {
    as.numeric(out[[field]]) <= as.numeric(baseline[[baseline_field]]) * as.numeric(ratio)
  }
  out$observed_gate_all <- gate("observed_log1p_mae_all", "observed_log1p_mae_all", policy$max_observed_ratio_all)
  out$observed_gate_last1000 <- gate("observed_log1p_mae_last1000", "observed_log1p_mae_last1000", policy$max_observed_ratio_last1000)
  out$observed_gate_last200 <- gate("observed_log1p_mae_last200", "observed_log1p_mae_last200", policy$max_observed_ratio_last200)
  out$observed_gate_last50 <- gate("observed_log1p_mae_last50", "observed_log1p_mae_last50", policy$max_observed_ratio_last50)
  out$historical_hard_gate_pass <- out$observed_gate_all & out$observed_gate_last1000 & out$observed_gate_last200 &
    (!isTRUE(policy$last50_is_hard_gate) | out$observed_gate_last50)
  out$forecast_improvement_fraction <- (
    as.numeric(baseline$forecast_p50_check_loss_mean) - as.numeric(out$forecast_p50_check_loss_mean)
  ) / as.numeric(baseline$forecast_p50_check_loss_mean)
  out$forecast_gate_pass <- out$forecast_improvement_fraction >= as.numeric(policy$min_forecast_improvement_fraction)
  out$eligible_for_full7_review <- app_as_bool_vec(out$technical_gate_pass) &
    out$historical_hard_gate_pass & out$forecast_gate_pass
  out$full7_required_for_distributional_crps <- TRUE
  out$auto_launch_full7 <- FALSE
  out$decision <- ifelse(
    out$eligible_for_full7_review,
    "eligible_after_diagnostic_and_cold_refit_review",
    ifelse(
      !out$technical_gate_pass,
      "reject_technical_gate",
      ifelse(!out$historical_hard_gate_pass, "reject_historical_fit_regression", "reject_no_forecast_gain")
    )
  )
  out <- out[order(
    !out$eligible_for_full7_review,
    as.numeric(out$forecast_p50_check_loss_mean),
    as.numeric(out$observed_log1p_mae_all),
    out$candidate_id
  ), , drop = FALSE]
  out$screen_rank <- seq_len(nrow(out))
  rownames(out) <- NULL
  out
}

app_glofas_median_screen_select_balanced_stage_b <- function(ranking, top_k = 20L) {
  required <- c(
    "candidate_id", "screen_rank", "technical_gate_pass", "historical_hard_gate_pass",
    "architecture_profile", "reservoir_memory_profile", "direct_memory_profile",
    "reference.alpha", "reference.rho"
  )
  missing <- setdiff(required, names(ranking))
  if (!is.data.frame(ranking) || !nrow(ranking) || length(missing)) {
    stop(sprintf("Stage-B selection ranking is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  top_k <- suppressWarnings(as.integer(top_k))
  if (!is.finite(top_k) || top_k < 1L) stop("top_k must be a positive integer.", call. = FALSE)
  ranking <- ranking[order(as.integer(ranking$screen_rank), ranking$candidate_id), , drop = FALSE]
  pool <- ranking[
    app_as_bool_vec(ranking$technical_gate_pass) & app_as_bool_vec(ranking$historical_hard_gate_pass),
    , drop = FALSE
  ]
  if (!nrow(pool)) stop("No Stage-A candidate passed both technical and historical hard gates.", call. = FALSE)

  chosen <- character()
  balance_fields <- c(
    "architecture_profile", "reservoir_memory_profile", "direct_memory_profile",
    "reference.alpha", "reference.rho"
  )
  for (field in balance_fields) {
    values <- unique(as.character(pool[[field]]))
    for (value in values) {
      hit <- pool[as.character(pool[[field]]) == value, , drop = FALSE]
      chosen <- unique(c(chosen, as.character(hit$candidate_id[[1L]])))
    }
  }
  if (length(chosen) > top_k) {
    chosen <- as.character(pool$candidate_id[pool$candidate_id %in% chosen])
    chosen <- chosen[seq_len(top_k)]
  }
  fill <- setdiff(as.character(pool$candidate_id), chosen)
  chosen <- c(chosen, head(fill, max(0L, top_k - length(chosen))))
  selected <- pool[match(chosen, pool$candidate_id), , drop = FALSE]
  selected$stage_b_selection_order <- seq_len(nrow(selected))
  selected$stage_b_selection_policy <- "best-per-factor-level-then-screen-rank"
  rownames(selected) <- NULL
  selected
}

app_glofas_median_screen_candidate_states <- function(manifest, output_root) {
  required <- c("candidate_id", "run_dir")
  missing <- setdiff(required, names(manifest))
  if (!is.data.frame(manifest) || !nrow(manifest) || length(missing)) {
    stop(sprintf(
      "Candidate-state census requires a nonempty manifest with: %s.",
      paste(required, collapse = ", ")
    ), call. = FALSE)
  }
  output_root <- normalizePath(output_root, mustWork = TRUE)
  rows <- lapply(seq_len(nrow(manifest)), function(i) {
    candidate_id <- as.character(manifest$candidate_id[[i]])
    run_dir <- as.character(manifest$run_dir[[i]])
    complete <- file.exists(file.path(run_dir, ".fit_recovery_complete"))
    rejected <- file.exists(file.path(run_dir, ".reservoir_preflight_rejected"))
    worker_path <- file.path(output_root, "status", paste0(candidate_id, ".csv"))
    worker <- if (file.exists(worker_path)) app_read_csv(worker_path) else data.frame()
    worker <- if (nrow(worker)) worker[nrow(worker), , drop = FALSE] else worker
    worker_status <- if (nrow(worker) && "status" %in% names(worker)) {
      as.character(worker$status[[1L]])
    } else ""
    state <- if (complete) {
      "completed"
    } else if (rejected) {
      "preflight_rejected"
    } else if (identical(worker_status, "failed")) {
      "failed"
    } else if (identical(worker_status, "running")) {
      "running_or_stale"
    } else {
      "pending_or_unknown"
    }
    data.frame(
      candidate_id = candidate_id,
      state = state,
      worker_status = worker_status,
      worker_exit_code = if (nrow(worker) && "exit_code" %in% names(worker)) {
        as.character(worker$exit_code[[1L]])
      } else "",
      run_dir = run_dir,
      stringsAsFactors = FALSE
    )
  })
  out <- app_bind_rows_fill(rows)
  out$terminal_for_strict_closeout <- out$state %in% c("completed", "preflight_rejected")
  out
}

app_glofas_median_screen_protected_candidates <- function(
  ranking,
  manifest,
  top_n = 2L,
  keep_controls = TRUE,
  explicit = character()
) {
  if (!is.data.frame(ranking) || !nrow(ranking) ||
      !all(c("candidate_id", "screen_rank") %in% names(ranking))) {
    stop("Retention protection requires a nonempty ranked candidate table.", call. = FALSE)
  }
  if (!is.data.frame(manifest) || !nrow(manifest) || !"candidate_id" %in% names(manifest)) {
    stop("Retention protection requires a nonempty candidate manifest.", call. = FALSE)
  }
  top_n <- suppressWarnings(as.integer(top_n[[1L]]))
  if (!is.finite(top_n) || top_n < 0L) stop("top_n must be a nonnegative integer.", call. = FALSE)
  ranked <- ranking[order(as.integer(ranking$screen_rank), ranking$candidate_id), , drop = FALSE]
  protected <- if (top_n) head(as.character(ranked$candidate_id), top_n) else character()
  if ("eligible_for_full7_review" %in% names(ranked)) {
    protected <- c(
      protected,
      as.character(ranked$candidate_id[app_as_bool_vec(ranked$eligible_for_full7_review)])
    )
  }
  if (isTRUE(keep_controls) && "candidate_role" %in% names(manifest)) {
    is_control <- grepl("control", as.character(manifest$candidate_role), ignore.case = TRUE)
    protected <- c(protected, as.character(manifest$candidate_id[is_control]))
  }
  explicit <- trimws(as.character(unlist(explicit, use.names = FALSE)))
  explicit <- explicit[nzchar(explicit)]
  unknown <- setdiff(explicit, as.character(manifest$candidate_id))
  if (length(unknown)) {
    stop(sprintf(
      "Explicit retention candidates are not in the manifest: %s.",
      paste(unknown, collapse = ", ")
    ), call. = FALSE)
  }
  unique(c(protected, explicit))
}

app_glofas_median_screen_moving_block_bootstrap <- function(
  differences,
  block_length = 5L,
  replicates = 10000L,
  seed = 20260823L
) {
  differences <- as.numeric(differences)
  differences <- differences[is.finite(differences)]
  n <- length(differences)
  block_length <- suppressWarnings(as.integer(block_length[[1L]]))
  replicates <- suppressWarnings(as.integer(replicates[[1L]]))
  seed <- suppressWarnings(as.integer(seed[[1L]]))
  if (n < 2L) stop("Moving-block bootstrap requires at least two finite differences.", call. = FALSE)
  if (!is.finite(block_length) || block_length < 1L || block_length > n) {
    stop("block_length must lie between one and the series length.", call. = FALSE)
  }
  if (!is.finite(replicates) || replicates < 100L) {
    stop("replicates must be at least 100.", call. = FALSE)
  }
  if (!is.finite(seed)) stop("seed must be finite.", call. = FALSE)
  starts_needed <- ceiling(n / block_length)
  old_seed_exists <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (old_seed_exists) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    if (old_seed_exists) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  draws <- numeric(replicates)
  offsets <- seq.int(0L, block_length - 1L)
  for (b in seq_len(replicates)) {
    starts <- sample.int(n, starts_needed, replace = TRUE)
    index <- as.vector(vapply(starts, function(start) {
      ((start - 1L + offsets) %% n) + 1L
    }, integer(block_length)))
    draws[[b]] <- mean(differences[index[seq_len(n)]])
  }
  ci <- unname(stats::quantile(draws, c(0.025, 0.975), names = FALSE, type = 8))
  data.frame(
    n = n,
    block_length = block_length,
    replicates = replicates,
    seed = seed,
    mean_difference = mean(differences),
    bootstrap_se = stats::sd(draws),
    ci_lower = ci[[1L]],
    ci_upper = ci[[2L]],
    probability_improvement = mean(draws < 0),
    stringsAsFactors = FALSE
  )
}

app_glofas_median_screen_merge_cleanup_reports <- function(existing, current) {
  existing <- existing %||% data.frame()
  current <- current %||% data.frame()
  rows <- list(existing, current)
  rows <- rows[vapply(rows, function(x) is.data.frame(x) && nrow(x) > 0L, logical(1L))]
  combined <- app_bind_rows_fill(rows)
  if (!nrow(combined)) return(combined)
  required <- c("candidate_id", "path", "action", "executed")
  missing <- setdiff(required, names(combined))
  if (length(missing)) {
    stop(sprintf(
      "Cleanup report is missing required columns: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  combined$executed <- app_as_bool_vec(combined$executed)
  key <- paste(combined$candidate_id, combined$path, sep = "\r")
  priority <- ifelse(combined$executed, 0L, 1L)
  ordering <- order(key, priority)
  combined <- combined[ordering, , drop = FALSE]
  key <- key[ordering]
  combined <- combined[!duplicated(key), , drop = FALSE]
  combined <- combined[order(combined$candidate_id, combined$path), , drop = FALSE]
  rownames(combined) <- NULL
  combined
}

app_glofas_median_screen_recover_cleanup_dry_run <- function(dry_run) {
  if (!is.data.frame(dry_run) || !nrow(dry_run)) return(data.frame())
  required <- c("candidate_id", "path", "action", "executed")
  missing <- setdiff(required, names(dry_run))
  if (length(missing)) {
    stop(sprintf(
      "Cleanup dry run is missing required columns: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  recovered <- dry_run
  recovered$executed <- app_as_bool_vec(recovered$executed)
  deletable <- recovered$action == "delete_candidate"
  recovered$executed[deletable] <- !file.exists(recovered$path[deletable])
  recovered
}
