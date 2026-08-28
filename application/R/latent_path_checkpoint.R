# Exact checkpoint and resume helpers for the latent-path VB engine.

app_latent_checkpoint_config <- function(vb_args = list()) {
  raw <- vb_args$checkpoint %||% list(enabled = FALSE)
  if (is.logical(raw) && length(raw) == 1L) raw <- list(enabled = raw)
  if (!is.list(raw)) raw <- list(enabled = app_as_bool(raw))
  every_iterations <- suppressWarnings(as.integer(raw$every_iterations %||% 100L))
  every_minutes <- suppressWarnings(as.numeric(raw$every_minutes %||% 30))
  if (!is.finite(every_iterations) || every_iterations < 1L) every_iterations <- 100L
  if (!is.finite(every_minutes) || every_minutes <= 0) every_minutes <- Inf
  list(
    enabled = app_as_bool(raw$enabled %||% FALSE),
    resume = app_as_bool(raw$resume %||% FALSE),
    path = as.character(raw$path %||% "")[[1L]],
    every_iterations = every_iterations,
    every_seconds = every_minutes * 60,
    keep_previous = app_as_bool(raw$keep_previous %||% TRUE),
    keep_on_success = app_as_bool(raw$keep_on_success %||% TRUE),
    compress = app_as_bool(raw$compress %||% FALSE),
    schema_version = "latent_path_vb_checkpoint_v1"
  )
}

app_latent_checkpoint_semantic_vb_args <- function(vb_args = list()) {
  fields <- c(
    "max_iter", "min_iter_elbo", "tol", "tol_par", "n_samp_xi", "n_draws",
    "seed", "beta_prior_type", "beta_rhs", "alpha_rhs", "prior_contract", "prior_sigma", "rhs",
    "future_moment_strategy", "future_update_strategy", "future_objective_strategy",
    "chunking", "draw_backend", "likelihood_family"
  )
  out <- vb_args[intersect(fields, names(vb_args))]
  out$diagnostics <- list(
    fixed_iterations = app_as_bool((vb_args$diagnostics %||% list())$fixed_iterations %||% FALSE)
  )
  out
}

app_latent_checkpoint_engine_hash <- function() {
  function_names <- c(
    "app_latent_row_moments",
    "app_latent_update_theta",
    "app_latent_update_future_gaussian_delta",
    "app_latent_update_v",
    "app_latent_update_sigma",
    "app_qdesn_alpha_rhs_group_layout",
    "app_qdesn_latent_vb_prior_contract",
    "app_latent_grouped_rhs_prior_precision",
    "app_latent_grouped_rhs_state_init",
    "app_latent_grouped_rhs_state_update",
    "app_latent_rhs_state_init_dispatch",
    "app_latent_rhs_state_update_dispatch",
    "app_latent_prior_state_update",
    "app_latent_approx_objective",
    "app_fit_latent_path_al_vb_core"
  )
  bodies <- lapply(function_names, function(name) {
    if (!exists(name, mode = "function", inherits = TRUE)) return(NULL)
    body(get(name, mode = "function", inherits = TRUE))
  })
  names(bodies) <- function_names
  app_latent_path_contract_hash(bodies, prefix = "latent_checkpoint_engine_")
}

app_latent_checkpoint_contract <- function(
  design,
  p0,
  coefficient_prior,
  vb_args,
  seed,
  backend_fail_closed = TRUE
) {
  design_hash <- design$warm_start_design_hash %||% NULL
  if (is.null(design_hash) && exists("app_hash_latent_path_design", mode = "function")) {
    design_hash <- app_hash_latent_path_design(design)
  }
  theta_names <- colnames(design$H_fixed)
  if (is.null(theta_names)) theta_names <- paste0("theta_", seq_len(ncol(design$H_fixed)))
  runtime_contract <- if (exists("app_latent_runtime_backend_contract", mode = "function")) {
    app_latent_runtime_backend_contract(fail_closed = backend_fail_closed)
  } else {
    list(backend = "unrecorded")
  }
  contract <- list(
    schema_version = "latent_path_vb_checkpoint_contract_v1",
    design_hash = as.character(design_hash %||% NA_character_),
    design_version = as.character(design$design_version %||% NA_character_),
    p0 = as.numeric(p0),
    coefficient_prior = as.character(coefficient_prior),
    seed = as.integer(seed),
    n_theta = ncol(design$H_fixed),
    theta_names_hash = app_latent_path_contract_hash(theta_names, "checkpoint_theta_names_"),
    n_future = nrow(design$future_key),
    future_key_hash = app_latent_path_contract_hash(design$future_key, "checkpoint_future_key_"),
    semantic_vb_args = app_latent_checkpoint_semantic_vb_args(vb_args),
    engine_hash = app_latent_checkpoint_engine_hash(),
    runtime_backend = runtime_contract
  )
  contract$contract_hash <- app_latent_path_contract_hash(contract, "latent_checkpoint_contract_")
  contract
}

app_latent_checkpoint_validate_payload <- function(payload, expected_contract = NULL) {
  required <- c(
    "schema_version", "contract", "iteration_completed", "state", "traces",
    "rng_state", "written_at"
  )
  missing <- setdiff(required, names(payload %||% list()))
  if (length(missing)) {
    stop(sprintf("Checkpoint payload is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (!identical(payload$schema_version, "latent_path_vb_checkpoint_v1")) {
    stop(sprintf("Unsupported checkpoint schema '%s'.", payload$schema_version), call. = FALSE)
  }
  state_required <- c(
    "theta_mean", "theta_cov", "y_mean", "y_cov", "sigma_state", "v_state",
    "prior_state"
  )
  missing_state <- setdiff(state_required, names(payload$state %||% list()))
  if (length(missing_state)) {
    stop(sprintf("Checkpoint state is missing: %s.", paste(missing_state, collapse = ", ")), call. = FALSE)
  }
  iter <- suppressWarnings(as.integer(payload$iteration_completed))
  if (!is.finite(iter) || iter < 0L) stop("Checkpoint iteration is invalid.", call. = FALSE)
  trace_required <- c(
    "objective", "par_change", "repaired_theta", "rhs_gate_trace", "rhs_trace",
    "iteration_timing", "substep_timing"
  )
  missing_trace <- setdiff(trace_required, names(payload$traces %||% list()))
  if (length(missing_trace)) {
    stop(sprintf("Checkpoint traces are missing: %s.", paste(missing_trace, collapse = ", ")), call. = FALSE)
  }
  scalar_traces <- c("objective", "par_change", "repaired_theta", "rhs_gate_trace")
  bad_trace <- scalar_traces[vapply(
    scalar_traces,
    function(name) length(payload$traces[[name]]) != iter,
    logical(1L)
  )]
  if (length(bad_trace)) {
    stop(sprintf("Checkpoint trace lengths are invalid: %s.", paste(bad_trace, collapse = ", ")), call. = FALSE)
  }
  if (!is.null(expected_contract)) {
    expected_hash <- as.character(expected_contract$contract_hash %||% "")
    observed_hash <- as.character(payload$contract$contract_hash %||% "")
    if (!nzchar(expected_hash) || !identical(expected_hash, observed_hash)) {
      stop(
        sprintf(
          "Checkpoint contract mismatch: expected %s, observed %s.",
          expected_hash,
          observed_hash
        ),
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

app_latent_checkpoint_hash_path <- function(path) paste0(path, ".sha256")

app_latent_checkpoint_fsync <- function(path) {
  sync_bin <- Sys.which("sync")
  if (!nzchar(sync_bin)) {
    stop("Exact checkpointing requires the system 'sync' command.", call. = FALSE)
  }
  status <- suppressWarnings(system2(
    sync_bin,
    c("-f", normalizePath(path, mustWork = TRUE)),
    stdout = FALSE,
    stderr = FALSE
  ))
  if (!identical(as.integer(status), 0L)) {
    stop(sprintf("Could not fsync checkpoint path: %s.", path), call. = FALSE)
  }
  invisible(path)
}

app_latent_checkpoint_payload <- function(
  contract,
  iteration_completed,
  state,
  traces,
  rng_state,
  metadata = list()
) {
  payload <- list(
    schema_version = "latent_path_vb_checkpoint_v1",
    contract = contract,
    iteration_completed = as.integer(iteration_completed),
    next_iteration = as.integer(iteration_completed) + 1L,
    state = state,
    traces = traces,
    rng_state = rng_state,
    metadata = metadata,
    written_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  app_latent_checkpoint_validate_payload(payload, expected_contract = contract)
  payload
}

app_latent_checkpoint_stop <- function(iteration, path) {
  condition <- structure(
    list(
      message = sprintf(
        "Controlled latent-path VB stop after iteration %d; exact checkpoint: %s.",
        as.integer(iteration),
        normalizePath(path, mustWork = FALSE)
      ),
      call = NULL,
      iteration = as.integer(iteration),
      checkpoint_path = normalizePath(path, mustWork = FALSE)
    ),
    class = c("latent_path_checkpoint_stop", "error", "condition")
  )
  stop(condition)
}

app_latent_checkpoint_write <- function(payload, path, compress = FALSE, keep_previous = TRUE) {
  if (is.null(path) || !nzchar(as.character(path[[1L]]))) {
    stop("Checkpoint path cannot be empty.", call. = FALSE)
  }
  path <- normalizePath(as.character(path[[1L]]), mustWork = FALSE)
  app_ensure_dir(dirname(path))
  app_latent_checkpoint_validate_payload(payload)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  tmp_hash <- app_latent_checkpoint_hash_path(tmp)
  on.exit(unlink(c(tmp, tmp_hash), force = TRUE), add = TRUE)
  saveRDS(payload, tmp, compress = isTRUE(compress), version = 3L)
  app_latent_checkpoint_fsync(tmp)
  roundtrip <- readRDS(tmp)
  app_latent_checkpoint_validate_payload(roundtrip)
  digest <- app_sha256_file(tmp)
  writeLines(digest, tmp_hash, useBytes = TRUE)
  app_latent_checkpoint_fsync(tmp_hash)

  previous <- paste0(path, ".previous")
  previous_hash <- app_latent_checkpoint_hash_path(previous)
  if (file.exists(path) && isTRUE(keep_previous)) {
    if (file.exists(previous)) unlink(previous, force = TRUE)
    if (file.exists(previous_hash)) unlink(previous_hash, force = TRUE)
    if (!file.rename(path, previous)) stop("Could not rotate prior checkpoint.", call. = FALSE)
    current_hash <- app_latent_checkpoint_hash_path(path)
    if (file.exists(current_hash) && !file.rename(current_hash, previous_hash)) {
      stop("Could not rotate prior checkpoint hash.", call. = FALSE)
    }
  } else if (file.exists(path)) {
    unlink(c(path, app_latent_checkpoint_hash_path(path)), force = TRUE)
  }
  if (!file.rename(tmp, path)) stop("Could not atomically install checkpoint.", call. = FALSE)
  if (!file.rename(tmp_hash, app_latent_checkpoint_hash_path(path))) {
    stop("Could not atomically install checkpoint hash.", call. = FALSE)
  }
  app_latent_checkpoint_fsync(path)
  invisible(path)
}

app_latent_checkpoint_read_one <- function(path, expected_contract = NULL) {
  if (!file.exists(path)) stop(sprintf("Checkpoint does not exist: %s.", path), call. = FALSE)
  hash_path <- app_latent_checkpoint_hash_path(path)
  if (!file.exists(hash_path)) stop(sprintf("Checkpoint hash is missing: %s.", hash_path), call. = FALSE)
  expected_hash <- trimws(readLines(hash_path, n = 1L, warn = FALSE))
  observed_hash <- app_sha256_file(path)
  if (!identical(tolower(expected_hash), tolower(observed_hash))) {
    stop(sprintf("Checkpoint file hash mismatch: %s.", path), call. = FALSE)
  }
  payload <- readRDS(path)
  app_latent_checkpoint_validate_payload(payload, expected_contract = expected_contract)
  payload
}

app_latent_checkpoint_read <- function(path, expected_contract = NULL, allow_previous = TRUE) {
  path <- normalizePath(as.character(path[[1L]]), mustWork = FALSE)
  primary_error <- NULL
  primary <- tryCatch(
    app_latent_checkpoint_read_one(path, expected_contract = expected_contract),
    error = function(e) {
      primary_error <<- conditionMessage(e)
      NULL
    }
  )
  if (!is.null(primary)) {
    attr(primary, "checkpoint_path") <- path
    attr(primary, "checkpoint_recovered_previous") <- FALSE
    return(primary)
  }
  previous <- paste0(path, ".previous")
  if (isTRUE(allow_previous) && file.exists(previous)) {
    recovered <- app_latent_checkpoint_read_one(previous, expected_contract = expected_contract)
    attr(recovered, "checkpoint_path") <- previous
    attr(recovered, "checkpoint_recovered_previous") <- TRUE
    attr(recovered, "primary_error") <- primary_error
    return(recovered)
  }
  stop(primary_error %||% sprintf("No valid checkpoint is available at %s.", path), call. = FALSE)
}

app_latent_checkpoint_remove <- function(path) {
  paths <- c(
    path,
    app_latent_checkpoint_hash_path(path),
    paste0(path, ".previous"),
    app_latent_checkpoint_hash_path(paste0(path, ".previous"))
  )
  existing <- paths[file.exists(paths)]
  if (length(existing) && !all(unlink(existing, force = TRUE) == 0L)) {
    stop("One or more checkpoint files could not be removed.", call. = FALSE)
  }
  invisible(existing)
}
