#!/usr/bin/env Rscript
# Reproducible exact-runtime canaries for the authoritative GloFAS latent path.

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "build_qdesn_features.R",
  "latent_path_design.R", "simulate_latent_path.R", "latent_path_runtime_backend.R",
  "latent_path_checkpoint.R", "latent_path_vb_al.R", "latent_path_recovery.R",
  "discrepancy_design.R", "forecast_contract.R", "fit_qdesn_discrepancy.R",
  "fit_qdesn_latent_path.R"
)) source(app_path("application/R", file))

parse_benchmark_args <- function(defaults) {
  tokens <- commandArgs(trailingOnly = TRUE)
  out <- defaults
  seen <- character()
  i <- 1L
  while (i <= length(tokens)) {
    token <- tokens[[i]]
    if (!startsWith(token, "--")) {
      stop(sprintf("Unexpected positional argument '%s'.", token), call. = FALSE)
    }
    token <- sub("^--", "", token)
    if (grepl("=", token, fixed = TRUE)) {
      parts <- strsplit(token, "=", fixed = TRUE)[[1L]]
      raw_key <- parts[[1L]]
      value <- paste(parts[-1L], collapse = "=")
      i <- i + 1L
    } else {
      raw_key <- token
      next_token <- if (i < length(tokens)) tokens[[i + 1L]] else NULL
      if (!is.null(next_token) && !startsWith(next_token, "--")) {
        value <- next_token
        i <- i + 2L
      } else {
        value <- TRUE
        i <- i + 1L
      }
    }
    key <- gsub("-", "_", raw_key, fixed = TRUE)
    if (!key %in% names(defaults)) {
      stop(sprintf("Unknown benchmark option '--%s'.", raw_key), call. = FALSE)
    }
    if (key %in% seen) {
      stop(sprintf("Benchmark option '--%s' was supplied more than once.", raw_key), call. = FALSE)
    }
    out[[key]] <- value
    seen <- c(seen, key)
  }
  out
}

args <- parse_benchmark_args(list(
  mode = "kernels",
  output_dir = "local_trackers/glofas_exact_runtime_benchmark",
  run_id = "benchmark",
  design = "",
  expected_design_sha256 = "",
  expected_design_hash = "",
  config = "",
  model_grid = "",
  fit_id = "",
  fixed_iterations = "1",
  repetitions = "1",
  benchmark_draws = "8",
  compiled_future_contract = "true",
  paired_fixed_stats = "true",
  weighted_crossprod = "multiply",
  reference_result = "",
  reference_fit = "",
  checkpoint_split = "20",
  checkpoint_every = "100",
  keep_checkpoint = "false",
  keep_serialized_designs = "false",
  profile_substeps = "true",
  seed = "20260824"
))

mode <- tolower(trimws(as.character(args$mode)))
allowed_modes <- c(
  "kernels", "future", "serialization", "fixed_k", "checkpoint", "converged"
)
if (!mode %in% allowed_modes) {
  stop(sprintf("Unsupported benchmark mode '%s'.", mode), call. = FALSE)
}
output_dir <- normalizePath(args$output_dir, mustWork = FALSE)
app_ensure_dir(output_dir)
run_id <- as.character(args$run_id)
prefix <- file.path(output_dir, run_id)
seed <- as.integer(args$seed)
if (!is.finite(seed)) seed <- 20260824L

rss_mb <- function(field = "VmRSS") {
  status <- tryCatch(
    readLines(sprintf("/proc/%d/status", Sys.getpid()), warn = FALSE),
    error = function(e) character()
  )
  hit <- grep(paste0("^", field, ":"), status, value = TRUE)
  if (!length(hit)) return(NA_real_)
  suppressWarnings(as.numeric(strsplit(hit[[1L]], "[[:space:]]+")[[1L]][2L])) / 1024
}

numeric_diff <- function(reference, candidate) {
  reference <- as.numeric(reference)
  candidate <- as.numeric(candidate)
  if (length(reference) != length(candidate)) {
    return(c(max_abs = Inf, max_rel = Inf, relative_norm = Inf))
  }
  delta <- candidate - reference
  scale <- pmax(abs(reference), 1.0e-15)
  c(
    max_abs = max(abs(delta)),
    max_rel = max(abs(delta) / scale),
    relative_norm = sqrt(sum(delta^2)) / max(sqrt(sum(reference^2)), 1.0e-15)
  )
}

write_backend <- function() {
  manifest <- app_latent_runtime_backend_manifest(fail_closed = TRUE)
  manifest$runtime_backend_fingerprint <- app_latent_runtime_backend_fingerprint()
  app_write_csv(manifest, paste0(prefix, "__runtime_backend.csv"))
  manifest
}

backend_manifest <- write_backend()

if (identical(mode, "kernels")) {
  set.seed(seed)
  n <- 12495L
  p_block <- 843L
  p_full <- 1686L
  X_beta <- matrix(stats::rnorm(n * p_block), nrow = n, ncol = p_block)
  X_alpha <- matrix(stats::rnorm(n * p_block), nrow = n, ncol = p_block)
  weights <- stats::runif(n, min = 0.05, max = 2)
  rhs_values <- stats::rnorm(n)
  timing <- list()
  time_step <- function(step, expr) {
    gc_before <- sum(gc()[, "used"])
    proc_before <- proc.time()
    wall_before <- proc_before[["elapsed"]]
    value <- force(expr)
    proc_after <- proc.time()
    timing[[length(timing) + 1L]] <<- data.frame(
      step = step,
      elapsed_seconds = proc_after[["elapsed"]] - wall_before,
      user_seconds = proc_after[["user.self"]] - proc_before[["user.self"]],
      system_seconds = proc_after[["sys.self"]] - proc_before[["sys.self"]],
      gc_used_delta = sum(gc()[, "used"]) - gc_before,
      rss_mb = rss_mb(),
      hwm_mb = rss_mb("VmHWM"),
      stringsAsFactors = FALSE
    )
    value
  }
  beta_beta <- time_step("weighted_beta_beta", {
    app_latent_weighted_crossprod(X_beta, w = weights)
  })
  beta_alpha <- time_step("weighted_beta_alpha", {
    crossprod(X_beta, X_alpha * weights)
  })
  alpha_alpha <- time_step("weighted_alpha_alpha", {
    app_latent_weighted_crossprod(X_alpha, w = weights)
  })
  rhs_beta <- time_step("weighted_rhs", {
    as.numeric(crossprod(X_beta, rhs_values))
  })
  set.seed(seed + 1L)
  root_source <- matrix(stats::rnorm((p_full + 32L) * p_full), ncol = p_full)
  precision <- crossprod(root_source) + diag(0.1, p_full)
  chol_factor <- time_step("precision_cholesky", chol(precision))
  covariance <- time_step("precision_covariance_recovery", chol2inv(chol_factor))
  arrays <- list(
    beta_beta = beta_beta,
    beta_alpha = beta_alpha,
    alpha_alpha = alpha_alpha,
    rhs_beta = rhs_beta,
    chol_factor = chol_factor,
    covariance = covariance
  )
  result <- list(
    schema_version = "glofas_exact_kernel_benchmark_v1",
    run_id = run_id,
    seed = seed,
    dimensions = c(n = n, p_block = p_block, p_full = p_full),
    backend = backend_manifest,
    timing = app_bind_rows_fill(timing),
    arrays = arrays,
    state_hash = app_latent_path_contract_hash(arrays, "glofas_kernel_state_")
  )
  comparison <- data.frame()
  if (nzchar(args$reference_result)) {
    reference <- readRDS(normalizePath(args$reference_result, mustWork = TRUE))
    rows <- lapply(names(arrays), function(name) {
      metrics <- numeric_diff(reference$arrays[[name]], arrays[[name]])
      data.frame(
        object = name,
        max_abs = metrics[["max_abs"]],
        max_rel = metrics[["max_rel"]],
        relative_norm = metrics[["relative_norm"]],
        finite_mask_equal = identical(
          is.finite(reference$arrays[[name]]),
          is.finite(arrays[[name]])
        ),
        stringsAsFactors = FALSE
      )
    })
    comparison <- do.call(rbind, rows)
    result$reference_path <- normalizePath(args$reference_result, mustWork = TRUE)
    result$comparison <- comparison
  }
  saveRDS(result, paste0(prefix, "__kernel_result.rds"), compress = FALSE)
  app_write_csv(result$timing, paste0(prefix, "__kernel_timing.csv"))
  app_write_csv(comparison, paste0(prefix, "__kernel_comparison.csv"))
  cat(paste0(prefix, "__kernel_result.rds"), "\n")
  quit(status = 0)
}

if (!nzchar(args$design)) stop("A real-design benchmark requires --design.", call. = FALSE)
design_path <- normalizePath(args$design, mustWork = TRUE)
design_sha256 <- app_sha256_file(design_path)
expected_design_sha256 <- tolower(trimws(as.character(args$expected_design_sha256)))
expected_design_hash <- trimws(as.character(args$expected_design_hash))
if (nzchar(expected_design_hash) && !nzchar(expected_design_sha256)) {
  stop("--expected-design-hash requires --expected-design-sha256.", call. = FALSE)
}
if (nzchar(expected_design_sha256) &&
    !identical(tolower(design_sha256), expected_design_sha256)) {
  stop(
    sprintf(
      "Design SHA-256 mismatch: expected %s, observed %s.",
      expected_design_sha256,
      design_sha256
    ),
    call. = FALSE
  )
}
design_load_start <- proc.time()
design <- readRDS(design_path)
design_load_time <- proc.time() - design_load_start
if (is.null(design$future_context)) {
  stop("The benchmark design does not contain a rebuildable future context.", call. = FALSE)
}
if (nzchar(expected_design_hash)) {
  design_hash <- expected_design_hash
  design$warm_start_design_hash <- design_hash
} else {
  design_hash <- app_hash_latent_path_design(design)
}

prepare_design <- function(design, compiled, paired) {
  context <- design$future_context
  context$runtime_optimization <- modifyList(
    context$runtime_optimization %||% list(),
    list(compiled_future_contract = isTRUE(compiled))
  )
  design$future_context <- context
  design$future_builder <- app_make_latent_path_future_builder(context)
  feature_rows <- as.integer(design$row_info_fixed$feature_row)
  X_beta_stack <- design$X_beta_stack %||%
    design$X_beta[feature_rows, , drop = FALSE]
  design$fixed_pairing_certificate <- app_latent_pairing_certificate(
    X_beta_stack = X_beta_stack,
    source = design$source_fixed,
    beta_index = design$beta_index,
    alpha_index = design$alpha_index,
    feature_names = colnames(design$H_fixed),
    optimization_enabled = isTRUE(paired)
  )
  attr(design, "future_probe_init") <- NULL
  design
}

if (identical(mode, "future")) {
  reference_design <- prepare_design(design, compiled = FALSE, paired = FALSE)
  optimized_design <- prepare_design(design, compiled = TRUE, paired = TRUE)
  set.seed(seed)
  paths <- list(
    initial = as.numeric(design$y_future_init),
    perturbed = as.numeric(design$y_future_init) + stats::rnorm(nrow(design$future_key), sd = 0.05)
  )
  comparison_rows <- list()
  timing_rows <- list()
  optimized_probe <- NULL
  for (path_name in names(paths)) {
    y <- paths[[path_name]]
    started <- proc.time()[["elapsed"]]
    reference_probe <- reference_design$future_builder(y)
    reference_seconds <- proc.time()[["elapsed"]] - started
    started <- proc.time()[["elapsed"]]
    optimized_probe <- optimized_design$future_builder(y)
    optimized_seconds <- proc.time()[["elapsed"]] - started
    timing_rows[[length(timing_rows) + 1L]] <- data.frame(
      path = path_name,
      reference_seconds = reference_seconds,
      optimized_seconds = optimized_seconds,
      speedup = reference_seconds / optimized_seconds,
      stringsAsFactors = FALSE
    )
    objects <- c("X_beta_future", "X_alpha_future", "H_y", "H_g_key", "z_g")
    for (name in objects) {
      metrics <- numeric_diff(reference_probe[[name]], optimized_probe[[name]])
      comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
        path = path_name,
        object = name,
        max_abs = metrics[["max_abs"]],
        max_rel = metrics[["max_rel"]],
        relative_norm = metrics[["relative_norm"]],
        stringsAsFactors = FALSE
      )
    }
    for (jacobian_name in c("J_y", "J_g_key")) {
      reference_j <- do.call(rbind, reference_probe[[jacobian_name]])
      optimized_j <- do.call(rbind, optimized_probe[[jacobian_name]])
      metrics <- numeric_diff(reference_j, optimized_j)
      comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
        path = path_name,
        object = jacobian_name,
        max_abs = metrics[["max_abs"]],
        max_rel = metrics[["max_rel"]],
        relative_norm = metrics[["relative_norm"]],
        stringsAsFactors = FALSE
      )
    }
  }
  y <- paths$perturbed
  H <- length(y)
  beta <- design$beta_index
  alpha <- design$alpha_index
  causality_max <- max(vapply(seq_len(H), function(h) {
    max(abs(optimized_probe$J_y[[h]][, h:H, drop = FALSE]))
  }, numeric(1L)))
  static_alpha_max <- max(vapply(optimized_probe$J_g_key, function(J) {
    max(abs(J[alpha, , drop = FALSE]))
  }, numeric(1L)))
  finite_difference_rows <- list()
  epsilon <- 1.0e-6
  for (k in unique(c(1L, as.integer(ceiling(H / 2)), H))) {
    plus <- y
    minus <- y
    plus[[k]] <- plus[[k]] + epsilon
    minus[[k]] <- minus[[k]] - epsilon
    fd <- (optimized_design$future_builder(plus)$X_beta_future -
      optimized_design$future_builder(minus)$X_beta_future) / (2 * epsilon)
    analytic <- do.call(rbind, lapply(optimized_probe$J_y, function(J) J[beta, k]))
    metrics <- numeric_diff(fd, analytic)
    finite_difference_rows[[length(finite_difference_rows) + 1L]] <- data.frame(
      future_column = k,
      max_abs = metrics[["max_abs"]],
      max_rel = metrics[["max_rel"]],
      relative_norm = metrics[["relative_norm"]],
      stringsAsFactors = FALSE
    )
  }
  result <- list(
    schema_version = "glofas_exact_future_benchmark_v1",
    run_id = run_id,
    design_path = design_path,
    design_sha256 = design_sha256,
    design_hash = design_hash,
    backend = backend_manifest,
    comparison = app_bind_rows_fill(comparison_rows),
    timing = app_bind_rows_fill(timing_rows),
    finite_difference = app_bind_rows_fill(finite_difference_rows),
    causality_max_forbidden_derivative = causality_max,
    static_alpha_jacobian_max_abs = static_alpha_max,
    compiled_contract = optimized_probe$compiled_future_contract
  )
  saveRDS(result, paste0(prefix, "__future_result.rds"), compress = FALSE)
  app_write_csv(result$comparison, paste0(prefix, "__future_comparison.csv"))
  app_write_csv(result$timing, paste0(prefix, "__future_timing.csv"))
  app_write_csv(result$finite_difference, paste0(prefix, "__future_finite_difference.csv"))
  app_write_csv(data.frame(
    causality_max_forbidden_derivative = causality_max,
    static_alpha_jacobian_max_abs = static_alpha_max,
    compiled_contract_hash = optimized_probe$compiled_future_contract$contract_hash,
    stringsAsFactors = FALSE
  ), paste0(prefix, "__future_gates.csv"))
  cat(paste0(prefix, "__future_result.rds"), "\n")
  quit(status = 0)
}

if (identical(mode, "serialization")) {
  legacy <- prepare_design(design, compiled = TRUE, paired = TRUE)
  compact <- app_latent_path_drop_runtime_cache(legacy, compact = TRUE)
  legacy_file <- paste0(prefix, "__legacy_design.rds")
  compact_file <- paste0(prefix, "__compact_design.rds")
  started <- proc.time()[["elapsed"]]
  saveRDS(legacy, legacy_file)
  legacy_save <- proc.time()[["elapsed"]] - started
  started <- proc.time()[["elapsed"]]
  saveRDS(compact, compact_file)
  compact_save <- proc.time()[["elapsed"]] - started
  started <- proc.time()[["elapsed"]]
  legacy_loaded <- readRDS(legacy_file)
  legacy_load <- proc.time()[["elapsed"]] - started
  started <- proc.time()[["elapsed"]]
  compact_loaded <- readRDS(compact_file)
  compact_load <- proc.time()[["elapsed"]] - started
  restored <- app_latent_path_restore_legacy_view(compact_loaded)
  restored_hash <- app_hash_latent_path_design(restored)
  result <- data.frame(
    design_hash = design_hash,
    restored_design_hash = restored_hash,
    semantic_hash_equal = identical(design_hash, restored_hash),
    legacy_file_bytes = as.numeric(file.info(legacy_file)$size),
    compact_file_bytes = as.numeric(file.info(compact_file)$size),
    size_reduction_fraction = 1 - as.numeric(file.info(compact_file)$size) /
      as.numeric(file.info(legacy_file)$size),
    legacy_object_bytes = as.numeric(object.size(legacy_loaded)),
    compact_object_bytes = as.numeric(object.size(compact_loaded)),
    object_reduction_fraction = 1 - as.numeric(object.size(compact_loaded)) /
      as.numeric(object.size(legacy_loaded)),
    legacy_save_seconds = legacy_save,
    compact_save_seconds = compact_save,
    legacy_load_seconds = legacy_load,
    compact_load_seconds = compact_load,
    stringsAsFactors = FALSE
  )
  app_write_csv(result, paste0(prefix, "__serialization.csv"))
  if (!app_as_bool(args$keep_serialized_designs)) {
    unlink(c(legacy_file, compact_file), force = TRUE)
  }
  cat(paste0(prefix, "__serialization.csv"), "\n")
  quit(status = 0)
}

if (!nzchar(args$config) || !nzchar(args$model_grid)) {
  stop("A fit benchmark requires --config and --model-grid.", call. = FALSE)
}
cfg <- app_read_config(normalizePath(args$config, mustWork = TRUE))
model_grid <- utils::read.csv(normalizePath(args$model_grid, mustWork = TRUE), stringsAsFactors = FALSE)
qrows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
if (nzchar(args$fit_id)) qrows <- qrows[qrows$fit_id == args$fit_id, , drop = FALSE]
if (nrow(qrows) != 1L) stop("Fixed-K benchmark requires exactly one Q-DESN row.", call. = FALSE)
row <- qrows[1L, , drop = FALSE]
compiled <- app_as_bool(args$compiled_future_contract)
paired <- app_as_bool(args$paired_fixed_stats)
design <- prepare_design(design, compiled = compiled, paired = paired)
options(qdesn.latent.weighted_crossprod = tolower(args$weighted_crossprod))
vb_args <- app_make_qdesn_discrepancy_vb_args(
  cfg,
  prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
  seed = as.integer(row$reservoir_seed[[1L]]),
  likelihood_family = "al"
)
fixed_iterations <- as.integer(args$fixed_iterations)
repetitions <- as.integer(args$repetitions)
benchmark_draws <- as.integer(args$benchmark_draws)
profile_substeps <- app_as_bool(args$profile_substeps)
if (!is.finite(fixed_iterations) || fixed_iterations < 1L) {
  stop("fixed_iterations must be positive.", call. = FALSE)
}
if (!is.finite(repetitions) || repetitions < 1L) stop("repetitions must be positive.", call. = FALSE)
if (!is.finite(benchmark_draws) || benchmark_draws < 1L) benchmark_draws <- 8L

semantic_draw <- function(x) {
  attr(x, "substep_timing") <- NULL
  attr(x, "backend") <- NULL
  x
}

semantic_state <- function(fit) {
  list(
    summary = fit$summary,
    variational_state = fit$variational_state,
    objective = fit$vb_diagnostics$elbo_trace,
    parameter_change = fit$vb_diagnostics$parameter_change_trace,
    repairs = fit$vb_diagnostics$theta_precision_repaired,
    draws = lapply(fit$draws, semantic_draw)
  )
}

numeric_state_leaves <- function(x, prefix) {
  out <- list()
  walk <- function(value, path) {
    if (is.numeric(value) || is.integer(value) || is.logical(value)) {
      out[[path]] <<- as.numeric(value)
      return(invisible(NULL))
    }
    if (!is.list(value)) return(invisible(NULL))
    labels <- names(value)
    if (is.null(labels)) labels <- as.character(seq_along(value))
    labels[!nzchar(labels)] <- as.character(which(!nzchar(labels)))
    for (i in seq_along(value)) {
      walk(value[[i]], paste(path, labels[[i]], sep = "_"))
    }
    invisible(NULL)
  }
  walk(x, prefix)
  out
}

state_comparison <- function(reference_state, candidate_state) {
  values <- list(
    theta_mean = list(reference_state$summary$theta_mean, candidate_state$summary$theta_mean),
    theta_cov = list(reference_state$summary$theta_cov, candidate_state$summary$theta_cov),
    y_future_mean = list(reference_state$summary$y_future_mean, candidate_state$summary$y_future_mean),
    y_future_cov = list(reference_state$summary$y_future_cov, candidate_state$summary$y_future_cov),
    objective_trace = list(reference_state$objective, candidate_state$objective),
    parameter_change_trace = list(reference_state$parameter_change, candidate_state$parameter_change)
  )
  for (name in intersect(names(reference_state$draws), names(candidate_state$draws))) {
    values[[paste0("draws_", name)]] <- list(
      reference_state$draws[[name]], candidate_state$draws[[name]]
    )
  }
  for (component in c("sigma", "v", "prior")) {
    reference_leaves <- numeric_state_leaves(
      reference_state$variational_state[[component]],
      paste0("variational_", component)
    )
    candidate_leaves <- numeric_state_leaves(
      candidate_state$variational_state[[component]],
      paste0("variational_", component)
    )
    for (name in intersect(names(reference_leaves), names(candidate_leaves))) {
      values[[name]] <- list(reference_leaves[[name]], candidate_leaves[[name]])
    }
  }
  app_bind_rows_fill(lapply(names(values), function(name) {
    reference_value <- values[[name]][[1L]]
    candidate_value <- values[[name]][[2L]]
    metrics <- numeric_diff(reference_value, candidate_value)
    data.frame(
      object = name,
      max_abs = metrics[["max_abs"]],
      max_rel = metrics[["max_rel"]],
      relative_norm = metrics[["relative_norm"]],
      finite_mask_equal = identical(
        is.finite(reference_value), is.finite(candidate_value)
      ),
      exact_equal = identical(
        as.numeric(reference_value), as.numeric(candidate_value)
      ),
      stringsAsFactors = FALSE
    )
  }))
}

iteration_seconds <- function(fit) {
  timing <- fit$vb_diagnostics$iteration_timing
  iterative <- timing[
    is.finite(timing$iteration) & timing$step != "checkpoint_write",
    , drop = FALSE
  ]
  sum(iterative$elapsed_seconds)
}

if (identical(mode, "checkpoint")) {
  split_iteration <- as.integer(args$checkpoint_split)
  checkpoint_every <- as.integer(args$checkpoint_every)
  if (!is.finite(split_iteration) || split_iteration < 1L ||
      split_iteration >= fixed_iterations) {
    stop("checkpoint_split must be between 1 and fixed_iterations - 1.", call. = FALSE)
  }
  if (!is.finite(checkpoint_every) || checkpoint_every < 1L) {
    stop("checkpoint_every must be positive.", call. = FALSE)
  }
  checkpoint_path <- paste0(prefix, "__checkpoint.rds")
  app_latent_checkpoint_remove(checkpoint_path)

  base_args <- vb_args
  base_args$max_iter <- fixed_iterations
  base_args$n_draws <- benchmark_draws
  base_args$checkpoint <- list(enabled = FALSE)
  base_args$diagnostics <- modifyList(
    base_args$diagnostics %||% list(),
    list(
      fixed_iterations = TRUE,
      profile_substeps = profile_substeps,
      trace_iterations = FALSE
    )
  )

  uninterrupted_start <- proc.time()[["elapsed"]]
  uninterrupted <- app_fit_latent_path_al_vb_core(
    design = design,
    p0 = as.numeric(row$quantile_level[[1L]]),
    coefficient_prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    vb_args = base_args,
    seed = as.integer(row$reservoir_seed[[1L]])
  )
  uninterrupted_elapsed <- proc.time()[["elapsed"]] - uninterrupted_start

  interrupted_args <- base_args
  interrupted_args$checkpoint <- list(
    enabled = TRUE,
    resume = FALSE,
    path = checkpoint_path,
    every_iterations = checkpoint_every,
    every_minutes = Inf,
    keep_previous = TRUE,
    keep_on_success = TRUE,
    compress = FALSE
  )
  interrupted_args$diagnostics$stop_after_iteration <- split_iteration
  interrupted_start <- proc.time()[["elapsed"]]
  stopped <- tryCatch(
    {
      app_fit_latent_path_al_vb_core(
        design = design,
        p0 = as.numeric(row$quantile_level[[1L]]),
        coefficient_prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
        vb_args = interrupted_args,
        seed = as.integer(row$reservoir_seed[[1L]])
      )
      NULL
    },
    latent_path_checkpoint_stop = function(e) e
  )
  interrupted_elapsed <- proc.time()[["elapsed"]] - interrupted_start
  if (!inherits(stopped, "latent_path_checkpoint_stop") ||
      !identical(stopped$iteration, split_iteration)) {
    stop("Checkpoint benchmark did not stop at the requested iteration.", call. = FALSE)
  }

  resumed_args <- interrupted_args
  resumed_args$checkpoint$resume <- TRUE
  resumed_args$diagnostics$stop_after_iteration <- NULL
  resumed_start <- proc.time()[["elapsed"]]
  resumed <- app_fit_latent_path_al_vb_core(
    design = design,
    p0 = as.numeric(row$quantile_level[[1L]]),
    coefficient_prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    vb_args = resumed_args,
    seed = as.integer(row$reservoir_seed[[1L]])
  )
  resumed_elapsed <- proc.time()[["elapsed"]] - resumed_start

  uninterrupted_state <- semantic_state(uninterrupted)
  resumed_state <- semantic_state(resumed)
  comparison <- state_comparison(uninterrupted_state, resumed_state)
  uninterrupted_hash <- app_latent_path_contract_hash(
    uninterrupted_state, "glofas_checkpoint_state_"
  )
  resumed_hash <- app_latent_path_contract_hash(
    resumed_state, "glofas_checkpoint_state_"
  )
  checkpoint_seconds <- as.numeric(
    resumed$vb_diagnostics$checkpoint$write_seconds %||% NA_real_
  )
  result <- list(
    schema_version = "glofas_exact_checkpoint_benchmark_v1",
    run_id = run_id,
    design_path = design_path,
    design_sha256 = design_sha256,
    design_hash = design_hash,
    config_path = normalizePath(args$config, mustWork = TRUE),
    config_sha256 = app_sha256_file(args$config),
    model_grid_path = normalizePath(args$model_grid, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(args$model_grid),
    backend = backend_manifest,
    benchmark = data.frame(
      fixed_iterations = fixed_iterations,
      split_iteration = split_iteration,
      checkpoint_every = checkpoint_every,
      profile_substeps = profile_substeps,
      uninterrupted_elapsed_seconds = uninterrupted_elapsed,
      interrupted_elapsed_seconds = interrupted_elapsed,
      resumed_elapsed_seconds = resumed_elapsed,
      uninterrupted_iteration_seconds = iteration_seconds(uninterrupted),
      resumed_iteration_seconds = iteration_seconds(resumed),
      checkpoint_write_seconds = checkpoint_seconds,
      checkpoint_overhead_fraction = checkpoint_seconds /
        max(iteration_seconds(resumed), 1.0e-15),
      checkpoint_writes = resumed$vb_diagnostics$checkpoint$writes,
      resumed_from_iteration = resumed$vb_diagnostics$checkpoint$iteration_loaded,
      recovered_previous = resumed$vb_diagnostics$checkpoint$recovered_previous,
      uninterrupted_state_hash = uninterrupted_hash,
      resumed_state_hash = resumed_hash,
      exact_state_hash_equal = identical(uninterrupted_hash, resumed_hash),
      stringsAsFactors = FALSE
    ),
    comparison = comparison,
    uninterrupted_state = uninterrupted_state,
    resumed_state = resumed_state
  )
  saveRDS(result, paste0(prefix, "__checkpoint_result.rds"), compress = FALSE)
  app_write_csv(result$benchmark, paste0(prefix, "__checkpoint_benchmark.csv"))
  app_write_csv(comparison, paste0(prefix, "__checkpoint_comparison.csv"))
  if (!app_as_bool(args$keep_checkpoint)) {
    app_latent_checkpoint_remove(checkpoint_path)
  }
  cat(paste0(prefix, "__checkpoint_result.rds"), "\n")
  quit(status = 0)
}

if (identical(mode, "converged")) {
  if (!nzchar(args$reference_fit)) {
    stop("A converged benchmark requires --reference-fit.", call. = FALSE)
  }
  vb_args$n_draws <- benchmark_draws
  vb_args$checkpoint <- list(enabled = FALSE)
  vb_args$diagnostics <- modifyList(
    vb_args$diagnostics %||% list(),
    list(
      fixed_iterations = FALSE,
      profile_substeps = profile_substeps,
      trace_iterations = FALSE
    )
  )
  fit_start <- proc.time()[["elapsed"]]
  fit <- app_fit_latent_path_al_vb_core(
    design = design,
    p0 = as.numeric(row$quantile_level[[1L]]),
    coefficient_prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    vb_args = vb_args,
    seed = as.integer(row$reservoir_seed[[1L]])
  )
  fit_elapsed <- proc.time()[["elapsed"]] - fit_start
  reference_fit <- readRDS(normalizePath(args$reference_fit, mustWork = TRUE))
  reference_state <- semantic_state(reference_fit)
  candidate_state <- semantic_state(fit)
  comparison <- state_comparison(reference_state, candidate_state)
  benchmark <- data.frame(
    run_id = run_id,
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    elapsed_seconds = fit_elapsed,
    measured_iteration_seconds = iteration_seconds(fit),
    seconds_per_iteration = iteration_seconds(fit) /
      max(as.integer(fit$vb_diagnostics$iterations), 1L),
    reference_iterations = as.integer(reference_fit$vb_diagnostics$iterations),
    candidate_iterations = as.integer(fit$vb_diagnostics$iterations),
    iteration_delta = as.integer(fit$vb_diagnostics$iterations) -
      as.integer(reference_fit$vb_diagnostics$iterations),
    reference_converged = isTRUE(reference_fit$vb_diagnostics$converged),
    candidate_converged = isTRUE(fit$vb_diagnostics$converged),
    reference_objective = tail(reference_fit$vb_diagnostics$elbo_trace, 1L),
    candidate_objective = tail(fit$vb_diagnostics$elbo_trace, 1L),
    reference_repaired = isTRUE(reference_fit$vb_diagnostics$theta_precision_repaired),
    candidate_repaired = isTRUE(fit$vb_diagnostics$theta_precision_repaired),
    profile_substeps = profile_substeps,
    rss_mb = rss_mb(),
    hwm_mb = rss_mb("VmHWM"),
    reference_state_hash = app_latent_path_contract_hash(
      reference_state, "glofas_converged_state_"
    ),
    candidate_state_hash = app_latent_path_contract_hash(
      candidate_state, "glofas_converged_state_"
    ),
    stringsAsFactors = FALSE
  )
  result <- list(
    schema_version = "glofas_exact_converged_benchmark_v1",
    run_id = run_id,
    design_path = design_path,
    design_sha256 = design_sha256,
    design_hash = design_hash,
    config_path = normalizePath(args$config, mustWork = TRUE),
    config_sha256 = app_sha256_file(args$config),
    model_grid_path = normalizePath(args$model_grid, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(args$model_grid),
    reference_fit_path = normalizePath(args$reference_fit, mustWork = TRUE),
    reference_fit_sha256 = app_sha256_file(args$reference_fit),
    backend = backend_manifest,
    benchmark = benchmark,
    comparison = comparison,
    candidate_state = candidate_state
  )
  saveRDS(result, paste0(prefix, "__converged_result.rds"), compress = FALSE)
  app_write_csv(benchmark, paste0(prefix, "__converged_benchmark.csv"))
  app_write_csv(comparison, paste0(prefix, "__converged_comparison.csv"))
  app_write_csv(fit$vb_diagnostics$iteration_timing, paste0(prefix, "__converged_iteration_timing.csv"))
  app_write_csv(fit$vb_diagnostics$substep_timing, paste0(prefix, "__converged_substeps.csv"))
  cat(paste0(prefix, "__converged_result.rds"), "\n")
  quit(status = 0)
}

vb_args$max_iter <- fixed_iterations
vb_args$n_draws <- benchmark_draws
vb_args$checkpoint <- list(enabled = FALSE)
vb_args$diagnostics <- modifyList(
  vb_args$diagnostics %||% list(),
  list(
    fixed_iterations = TRUE,
    profile_substeps = profile_substeps,
    trace_iterations = FALSE
  )
)

rows <- list()
substeps <- list()
states <- list()
for (repetition in seq_len(repetitions)) {
  invisible(gc())
  gc_before <- sum(gc()[, "used"])
  proc_before <- proc.time()
  fit <- app_fit_latent_path_al_vb_core(
    design = design,
    p0 = as.numeric(row$quantile_level[[1L]]),
    coefficient_prior = app_map_qdesn_prior(row$coefficient_prior[[1L]]),
    vb_args = vb_args,
    seed = as.integer(row$reservoir_seed[[1L]])
  )
  proc_after <- proc.time()
  timing <- fit$vb_diagnostics$iteration_timing
  iterative <- timing[is.finite(timing$iteration) & timing$step != "checkpoint_write", , drop = FALSE]
  states[[repetition]] <- semantic_state(fit)
  rows[[repetition]] <- data.frame(
    run_id = run_id,
    repetition = repetition,
    fixed_iterations = fixed_iterations,
    engine = if (compiled || paired) "exact_optimized" else "reference",
    compiled_future_contract = compiled,
    paired_fixed_stats = paired,
    weighted_crossprod = tolower(args$weighted_crossprod),
    profile_substeps = profile_substeps,
    elapsed_seconds = proc_after[["elapsed"]] - proc_before[["elapsed"]],
    user_seconds = proc_after[["user.self"]] - proc_before[["user.self"]],
    system_seconds = proc_after[["sys.self"]] - proc_before[["sys.self"]],
    measured_iteration_seconds = sum(iterative$elapsed_seconds),
    seconds_per_iteration = sum(iterative$elapsed_seconds) / fixed_iterations,
    rss_mb = rss_mb(),
    hwm_mb = rss_mb("VmHWM"),
    gc_used_delta = sum(gc()[, "used"]) - gc_before,
    objective_value = tail(fit$vb_diagnostics$elbo_trace, 1L),
    convergence_metric = tail(fit$vb_diagnostics$parameter_change_trace, 1L),
    repaired = fit$vb_diagnostics$theta_precision_repaired,
    state_hash = app_latent_path_contract_hash(states[[repetition]], "glofas_fixed_k_state_"),
    stringsAsFactors = FALSE
  )
  substep <- fit$vb_diagnostics$substep_timing
  if (is.data.frame(substep) && nrow(substep)) {
    substep$run_id <- run_id
    substep$repetition <- repetition
    substeps[[length(substeps) + 1L]] <- substep
  }
  rm(fit)
}
result <- list(
  schema_version = "glofas_exact_fixed_k_benchmark_v1",
  run_id = run_id,
  design_path = design_path,
  design_sha256 = design_sha256,
  design_hash = design_hash,
  design_load_elapsed = unname(design_load_time[["elapsed"]]),
  config_path = normalizePath(args$config, mustWork = TRUE),
  config_sha256 = app_sha256_file(args$config),
  model_grid_path = normalizePath(args$model_grid, mustWork = TRUE),
  model_grid_sha256 = app_sha256_file(args$model_grid),
  backend = backend_manifest,
  benchmark = app_bind_rows_fill(rows),
  substeps = app_bind_rows_fill(substeps),
  states = states
)
if (nzchar(args$reference_result)) {
  reference <- readRDS(normalizePath(args$reference_result, mustWork = TRUE))
  reference_state <- reference$states[[1L]]
  candidate_state <- states[[1L]]
  result$comparison <- state_comparison(reference_state, candidate_state)
  app_write_csv(result$comparison, paste0(prefix, "__fixed_k_comparison.csv"))
}
saveRDS(result, paste0(prefix, "__fixed_k_result.rds"), compress = FALSE)
app_write_csv(result$benchmark, paste0(prefix, "__fixed_k_benchmark.csv"))
app_write_csv(result$substeps, paste0(prefix, "__fixed_k_substeps.csv"))
cat(paste0(prefix, "__fixed_k_result.rds"), "\n")
