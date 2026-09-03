# Phase181 diagnostic atlas: source audit, path extraction, rendering, and QA.

app_joint_qdesn_atlas_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

app_joint_qdesn_atlas_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_atlas_sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  out <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (!length(out) || (length(status) && status != 0L)) {
    stop(sprintf("Could not hash '%s'.", path), call. = FALSE)
  }
  strsplit(out[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

app_joint_qdesn_atlas_read_config <- function(path) {
  x <- app_joint_qdesn_atlas_read_csv(path)
  required <- c("key", "value", "value_type", "description")
  if (!identical(names(x), required) || anyDuplicated(x$key)) {
    stop("Malformed Phase181 atlas configuration.", call. = FALSE)
  }
  parse <- function(value, type) {
    switch(type,
      character = as.character(value),
      integer = as.integer(value),
      numeric = as.numeric(value),
      logical = tolower(value) == "true",
      numeric_vector = as.numeric(strsplit(value, ",", fixed = TRUE)[[1L]]),
      stop(sprintf("Unknown atlas configuration type '%s'.", type), call. = FALSE)
    )
  }
  values <- lapply(seq_len(nrow(x)), function(i) parse(x$value[[i]], x$value_type[[i]]))
  names(values) <- x$key
  values$config_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  values$config_sha256 <- app_joint_qdesn_atlas_sha256(path)
  values
}

app_joint_qdesn_atlas_model_dictionary <- function() {
  data.frame(
    source_model_id = c(
      "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
      "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
    ),
    model_order = 1:4,
    model_label = c(
      "Joint QDESN (AL-RHS)", "Independent QDESN (AL-RHS)",
      "Joint exQDESN (exAL-RHS)", "Independent exQDESN (exAL-RHS)"
    ),
    short_label = c("Joint AL", "Independent AL", "Joint exAL", "Independent exAL"),
    colour = c("#0072B2", "#56B4E9", "#D55E00", "#E69F00"),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_scenario_dictionary <- function() {
  data.frame(
    scenario_id = c(
      "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
      "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
      "regime_shift", "student_t_location_scale"
    ),
    scenario_order = 1:8,
    scenario_label = c(
      "Asymmetric Laplace tail", "Gaussian-mixture bridge", "Laplace bridge",
      "Nonlinear reservoir-friendly", "Normal bridge", "Persistent heavy tail",
      "Regime shift", "Student-t location-scale"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_attach_labels <- function(x) {
  models <- app_joint_qdesn_atlas_model_dictionary()
  scenarios <- app_joint_qdesn_atlas_scenario_dictionary()
  if ("source_model_id" %in% names(x)) {
    x <- merge(x, models, by = "source_model_id", all.x = TRUE, sort = FALSE)
  }
  scenario_key <- if ("scenario_id" %in% names(x)) "scenario_id" else
    if ("base_scenario_id" %in% names(x)) "base_scenario_id" else NULL
  if (!is.null(scenario_key)) {
    names(scenarios)[names(scenarios) == "scenario_id"] <- scenario_key
    x <- merge(x, scenarios, by = scenario_key, all.x = TRUE, sort = FALSE)
  }
  x
}

app_joint_qdesn_atlas_page_plan <- function() {
  global <- data.frame(
    page_number = 1:8,
    page_id = sprintf("global_%02d", 1:8),
    page_type = c(
      "protocol", "score_intervals", "regret_intervals", "contrasts",
      "expected_realized", "oracle_recovery", "coherence", "mcmc_diagnostics"
    ),
    scenario_id = NA_character_,
    title = c(
      "Protocol, estimand, and frozen provenance",
      "Posterior DGP-integrated score intervals",
      "Posterior expected-regret intervals",
      "Joint-minus-independent score contrasts",
      "DGP-integrated and realized finite-grid scores",
      "Oracle quantile-path recovery",
      "Raw crossings and monotone adjustment",
      "Score-functional and scalar-parameter diagnostics"
    ), stringsAsFactors = FALSE
  )
  scenarios <- app_joint_qdesn_atlas_scenario_dictionary()
  types <- c("tau_decomposition", "origin_lead", "forecast_paths", "fit_coherence")
  titles <- c(
    "Finite-grid score decomposition by quantile level",
    "Forecast expected regret by origin and lead",
    "Forecast quantile-path recovery",
    "Fit-window recovery and coherence"
  )
  pages <- lapply(seq_len(nrow(scenarios)), function(i) {
    data.frame(
      page_number = 8L + (i - 1L) * 4L + seq_along(types),
      page_id = sprintf("scenario_%02d_%s", i, types),
      page_type = types,
      scenario_id = scenarios$scenario_id[[i]],
      title = paste(scenarios$scenario_label[[i]], titles, sep = ": "),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, c(list(global), pages))
  out$png_path <- file.path("pages", sprintf("page_%02d_%s.png", out$page_number, out$page_id))
  out$pdf_path <- file.path("pages", sprintf("page_%02d_%s.pdf", out$page_number, out$page_id))
  out
}

app_joint_qdesn_atlas_verify_manifest <- function(dir, expected_sha256 = NULL) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  manifest <- app_joint_qdesn_atlas_read_csv(manifest_path)
  path_col <- intersect(c("path", "relative_path", "file"), names(manifest))
  hash_col <- intersect(c("sha256", "sha_256"), names(manifest))
  if (length(path_col) != 1L || length(hash_col) != 1L) {
    stop(sprintf("Manifest schema is unsupported in '%s'.", dir), call. = FALSE)
  }
  paths <- file.path(dir, manifest[[path_col]])
  actual <- vapply(paths, app_joint_qdesn_atlas_sha256, character(1L))
  status <- file.exists(paths) & actual == manifest[[hash_col]]
  if (!is.null(expected_sha256) &&
      app_joint_qdesn_atlas_sha256(manifest_path) != expected_sha256) {
    status[] <- FALSE
  }
  data.frame(
    manifest_path = normalizePath(manifest_path, winslash = "/", mustWork = TRUE),
    relative_path = manifest[[path_col]], expected_sha256 = manifest[[hash_col]],
    actual_sha256 = actual, status = ifelse(status, "pass", "fail"),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_source_paths <- function(config, source_root) {
  source_root <- normalizePath(source_root, winslash = "/", mustWork = TRUE)
  list(
    source_root = source_root,
    packet = file.path(source_root, config$packet_relative_path),
    fixtures = file.path(source_root, config$fixture_relative_path)
  )
}

app_joint_qdesn_atlas_validate_sources <- function(config, source_root) {
  paths <- app_joint_qdesn_atlas_source_paths(config, source_root)
  packet_manifest <- app_joint_qdesn_atlas_verify_manifest(
    paths$packet, config$packet_manifest_sha256
  )
  fixture_manifest <- app_joint_qdesn_atlas_verify_manifest(
    paths$fixtures, config$fixture_manifest_sha256
  )
  registry_path <- file.path(paths$packet, "final_selected_source_registry.csv")
  registry <- app_joint_qdesn_atlas_read_csv(registry_path)
  summary <- app_joint_qdesn_atlas_read_csv(file.path(
    paths$packet, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  contrasts <- app_joint_qdesn_atlas_read_csv(file.path(
    paths$packet, "joint_independent_score_contrast_summary.csv"
  ))
  score_draws <- app_joint_qdesn_atlas_read_csv(gzfile(file.path(
    paths$packet, "posterior_dgp_integrated_acrps_draws.csv.gz"
  )))
  registry_cells <- table(registry$case_id)
  draw_cells <- table(score_draws$case_id)
  worker_dirs <- unique(registry$worker_output_dir)
  worker_hash <- setNames(registry$worker_manifest_sha256, registry$worker_output_dir)
  worker_audit <- do.call(rbind, lapply(worker_dirs, function(dir) {
    manifest <- file.path(dir, "artifact_manifest.csv")
    actual <- app_joint_qdesn_atlas_sha256(manifest)
    data.frame(
      worker_output_dir = dir, manifest_exists = file.exists(manifest),
      expected_sha256 = worker_hash[[dir]], actual_sha256 = actual,
      status = if (file.exists(manifest) && identical(actual, worker_hash[[dir]]))
        "pass" else "fail", stringsAsFactors = FALSE
    )
  }))
  gates <- data.frame(
    gate = c(
      "packet_manifest_entries", "fixture_manifest_entries", "selected_registry_hash",
      "selected_registry_rows", "selected_cells", "chains_per_cell",
      "score_summary_cells", "score_draw_cells", "score_draws_per_cell",
      "contrast_rows", "worker_manifest_hashes", "contract_crossings"
    ),
    observed = c(
      sum(packet_manifest$status == "pass"), sum(fixture_manifest$status == "pass"),
      app_joint_qdesn_atlas_sha256(registry_path), nrow(registry),
      length(registry_cells), paste(sort(unique(registry_cells)), collapse = ","),
      nrow(summary), length(draw_cells), paste(sort(unique(draw_cells)), collapse = ","),
      nrow(contrasts), sum(worker_audit$status == "pass"),
      sum(summary$contract_crossing_pairs)
    ),
    expected = c(
      nrow(packet_manifest), nrow(fixture_manifest), config$selected_registry_sha256,
      config$expected_cells * config$expected_chains_per_cell, config$expected_cells,
      config$expected_chains_per_cell, config$expected_cells, config$expected_cells,
      config$expected_score_draws_per_cell, 2L * config$expected_scenarios,
      length(worker_dirs), 0L
    ), stringsAsFactors = FALSE
  )
  gates$status <- ifelse(as.character(gates$observed) == as.character(gates$expected),
                         "pass", "fail")
  if (any(packet_manifest$status != "pass") || any(fixture_manifest$status != "pass") ||
      any(worker_audit$status != "pass") || any(gates$status != "pass") ||
      length(unique(registry$scenario_id)) != config$expected_scenarios ||
      length(unique(registry$source_model_id)) != config$expected_models) {
    stop("Phase181 atlas source audit failed closed.", call. = FALSE)
  }
  list(paths = paths, registry = registry, score_summary = summary,
       contrasts = contrasts, score_draws = score_draws, gates = gates,
       packet_manifest = packet_manifest, fixture_manifest = fixture_manifest,
       worker_audit = worker_audit)
}

app_joint_qdesn_atlas_row_quantiles <- function(x) {
  if (requireNamespace("matrixStats", quietly = TRUE)) {
    out <- matrixStats::rowQuantiles(x, probs = c(0.025, 0.5, 0.975),
                                     type = 8, drop = FALSE)
  } else {
    out <- t(apply(x, 1L, stats::quantile,
                   probs = c(0.025, 0.5, 0.975), names = FALSE, type = 8))
  }
  colnames(out) <- c("q025", "median", "q975")
  out
}

app_joint_qdesn_atlas_load_fits <- function(jobs, fixture) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  lapply(seq_len(nrow(jobs)), function(i) {
    job <- jobs[i, , drop = FALSE]
    if (identical(job$source_kind[[1L]], "phase172_reuse")) {
      return(app_joint_exqdesn_phase157_read_fit(
        app_joint_exqdesn_phase172_checkpoint_dir(job$worker_output_dir[[1L]]),
        fixture$tau, job$chain_seed[[1L]], job$chain_id[[1L]]
      ))
    }
    app_joint_qdesn_phase180_read_fit(
      job$worker_output_dir[[1L]], fixture$tau,
      job$chain_seed[[1L]], job$chain_id[[1L]]
    )
  })
}

app_joint_qdesn_atlas_path_bands <- function(
  fits, Z, tau, fit_structure, pairing_seed, draws_per_chain, target_tau
) {
  target_index <- match(target_tau, tau)
  if (anyNA(target_index)) stop("Requested path tau is outside the fitted grid.", call. = FALSE)
  n_time <- nrow(Z); K <- length(tau); p <- ncol(Z)
  X <- cbind(intercept = 1, Z)
  total <- length(fits) * draws_per_chain
  storage <- lapply(target_index, function(k) matrix(NA_real_, n_time, total))
  cursor <- 0L
  for (ii in seq_along(fits)) {
    fit <- fits[[ii]]
    selected <- app_joint_qdesn_postscore_even_indices(
      nrow(fit$beta_draws), draws_per_chain
    )
    index_by_tau <- app_joint_qdesn_postscore_per_tau_indices(
      selected, K, fit_structure, pairing_seed, ii
    )
    chunks <- split(seq_along(selected), ceiling(seq_along(selected) / 50L))
    for (position in chunks) {
      B <- length(position)
      raw <- matrix(NA_real_, n_time * B, K)
      for (kk in seq_len(K)) {
        source_index <- index_by_tau[[kk]][position]
        beta_index <- ((kk - 1L) * p + 1L):(kk * p)
        theta <- cbind(
          fit$alpha_draws[source_index, kk],
          fit$beta_draws[source_index, beta_index, drop = FALSE]
        )
        raw[, kk] <- as.vector(X %*% t(theta))
      }
      contracted <- app_joint_qdesn_postscore_contract_rows(raw, tau)$q_contract
      columns <- cursor + position
      for (jj in seq_along(target_index)) {
        storage[[jj]][, columns] <- matrix(
          contracted[, target_index[[jj]]], nrow = n_time, ncol = B
        )
      }
    }
    cursor <- cursor + draws_per_chain
  }
  do.call(rbind, lapply(seq_along(target_index), function(jj) {
    values <- storage[[jj]]
    qs <- app_joint_qdesn_atlas_row_quantiles(values)
    data.frame(
      row_index = seq_len(n_time), quantile_index = target_index[[jj]],
      tau = tau[target_index[[jj]]], posterior_mean = rowMeans(values),
      posterior_median = qs[, "median"], posterior_q025 = qs[, "q025"],
      posterior_q975 = qs[, "q975"], stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_atlas_crossing_events <- function(
  raw, contract, tau, row_meta, case_id, window
) {
  blocks <- lapply(seq_len(length(tau) - 1L), function(k) {
    magnitude <- raw[, k] - raw[, k + 1L]
    index <- which(magnitude > 1e-12)
    if (!length(index)) return(NULL)
    meta <- row_meta[index, , drop = FALSE]
    data.frame(
      case_id = case_id, window = window, row_index = index,
      lower_tau = tau[[k]], upper_tau = tau[[k + 1L]],
      raw_lower_qhat = raw[index, k], raw_upper_qhat = raw[index, k + 1L],
      crossing_magnitude = magnitude[index],
      contract_lower_qhat = contract[index, k],
      contract_upper_qhat = contract[index, k + 1L],
      full_time_index = meta$full_time_index,
      origin_index = if ("origin_index" %in% names(meta)) meta$origin_index else NA_integer_,
      horizon = if ("horizon" %in% names(meta)) meta$horizon else NA_integer_,
      stringsAsFactors = FALSE
    )
  })
  blocks <- Filter(Negate(is.null), blocks)
  if (!length(blocks)) return(data.frame(
    case_id = character(), window = character(), row_index = integer(),
    lower_tau = numeric(), upper_tau = numeric(), raw_lower_qhat = numeric(),
    raw_upper_qhat = numeric(), crossing_magnitude = numeric(),
    contract_lower_qhat = numeric(), contract_upper_qhat = numeric(),
    full_time_index = integer(), origin_index = integer(), horizon = integer()
  ))
  do.call(rbind, blocks)
}

app_joint_qdesn_atlas_score_map <- function(
  qhat, truth, y, mu, sigma, sc, tau, weights, row_meta, case_id
) {
  n <- nrow(qhat); K <- length(tau)
  expected <- realized <- oracle <- matrix(NA_real_, n, K)
  for (k in seq_len(K)) {
    expected[, k] <- app_joint_qdesn_postscore_expected_check(
      qhat[, k], tau[[k]], mu, sigma, sc
    )
    oracle[, k] <- app_joint_qdesn_postscore_expected_check(
      truth[, k], tau[[k]], mu, sigma, sc
    )
    realized[, k] <- app_joint_qdesn_postscore_check_loss(y, qhat[, k], tau[[k]])
  }
  data.frame(
    case_id = case_id, row_index = seq_len(n),
    full_time_index = row_meta$full_time_index,
    origin_index = row_meta$origin_index, horizon = row_meta$horizon,
    expected_score = as.numeric(2 * expected %*% weights),
    oracle_expected_score = as.numeric(2 * oracle %*% weights),
    expected_regret = as.numeric(2 * (expected - oracle) %*% weights),
    realized_score = as.numeric(2 * realized %*% weights),
    oracle_mae = rowMeans(abs(qhat - truth)),
    oracle_rmse = sqrt(rowMeans((qhat - truth)^2)), stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_tau_decomposition <- function(
  qhat, truth, y, mu, sigma, sc, tau, weights, case_id
) {
  do.call(rbind, lapply(seq_along(tau), function(k) {
    expected <- app_joint_qdesn_postscore_expected_check(
      qhat[, k], tau[[k]], mu, sigma, sc
    )
    oracle <- app_joint_qdesn_postscore_expected_check(
      truth[, k], tau[[k]], mu, sigma, sc
    )
    realized <- app_joint_qdesn_postscore_check_loss(y, qhat[, k], tau[[k]])
    data.frame(
      case_id = case_id, quantile_index = k, tau = tau[[k]], weight = weights[[k]],
      expected_check_loss = mean(expected), oracle_expected_check_loss = mean(oracle),
      expected_regret = mean(expected - oracle), realized_check_loss = mean(realized),
      weighted_expected_contribution = 2 * weights[[k]] * mean(expected),
      weighted_oracle_contribution = 2 * weights[[k]] * mean(oracle),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_atlas_extract_scenario <- function(
  scenario_id, registry, fixture_dir, config, scenario_dir
) {
  dir.create(scenario_dir, recursive = TRUE, showWarnings = FALSE)
  loaded <- app_joint_qdesn_phase180_load_fixture(scenario_id, fixture_dir)
  fixture <- loaded$fixture
  context <- app_joint_qdesn_postscore_forecast_context(loaded, fixture)
  model_ids <- app_joint_qdesn_atlas_model_dictionary()$source_model_id
  fit_paths <- forecast_paths <- score_maps <- tau_rows <- crossings <- adjustments <- list()
  for (model_id in model_ids) {
    jobs <- registry[
      registry$scenario_id == scenario_id & registry$source_model_id == model_id,
      , drop = FALSE
    ]
    if (nrow(jobs) != config$expected_chains_per_cell) {
      stop(sprintf("Scenario '%s' model '%s' is not source complete.",
                   scenario_id, model_id), call. = FALSE)
    }
    fits <- app_joint_qdesn_atlas_load_fits(jobs, fixture)
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
      fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
    )
    raw_fit <- app_joint_qdesn_predict_fit(pooled, fixture$Z, fixture$tau)
    raw_forecast <- app_joint_qdesn_predict_fit(
      pooled, context$forecast$Z, fixture$tau
    )
    contract_fit <- app_joint_qdesn_apply_monotone_contract(raw_fit, fixture$tau)
    contract_forecast <- app_joint_qdesn_apply_monotone_contract(
      raw_forecast, fixture$tau
    )
    fit_band <- app_joint_qdesn_atlas_path_bands(
      fits, fixture$Z, fixture$tau, jobs$fit_structure[[1L]],
      config$primary_pairing_seed, config$path_draws_per_chain,
      config$path_display_tau
    )
    forecast_band <- app_joint_qdesn_atlas_path_bands(
      fits, context$forecast$Z, fixture$tau, jobs$fit_structure[[1L]],
      config$primary_pairing_seed, config$path_draws_per_chain,
      config$path_display_tau
    )
    fit_band$canonical_action <- contract_fit$qhat_contract[cbind(
      fit_band$row_index, fit_band$quantile_index
    )]
    fit_band$true_quantile <- fixture$true_q[cbind(
      fit_band$row_index, fit_band$quantile_index
    )]
    fit_band$y <- fixture$y[fit_band$row_index]
    fit_band$full_time_index <- fixture$row_meta$full_time_index[fit_band$row_index]
    forecast_band$canonical_action <- contract_forecast$qhat_contract[cbind(
      forecast_band$row_index, forecast_band$quantile_index
    )]
    forecast_band$true_quantile <- context$forecast$true_q[cbind(
      forecast_band$row_index, forecast_band$quantile_index
    )]
    forecast_band$y <- context$forecast$y[forecast_band$row_index]
    forecast_band$full_time_index <- context$forecast$row_meta$full_time_index[
      forecast_band$row_index
    ]
    forecast_band$origin_index <- context$forecast$row_meta$origin_index[
      forecast_band$row_index
    ]
    forecast_band$horizon <- context$forecast$row_meta$horizon[forecast_band$row_index]
    for (xname in c("fit_band", "forecast_band")) {
      x <- get(xname)
      x$case_id <- jobs$case_id[[1L]]; x$scenario_id <- scenario_id
      x$source_model_id <- model_id; x$fit_structure <- jobs$fit_structure[[1L]]
      x$likelihood_family <- jobs$likelihood_family[[1L]]
      if (xname == "fit_band") fit_band <- x else forecast_band <- x
    }
    fit_paths[[model_id]] <- fit_band
    forecast_paths[[model_id]] <- forecast_band
    score_maps[[model_id]] <- transform(
      app_joint_qdesn_atlas_score_map(
        contract_forecast$qhat_contract, context$forecast$true_q,
        context$forecast$y, context$mu, context$sigma, context$sc,
        fixture$tau, config$trapezoidal_weights, context$forecast$row_meta,
        jobs$case_id[[1L]]
      ), scenario_id = scenario_id, source_model_id = model_id
    )
    tau_rows[[model_id]] <- transform(
      app_joint_qdesn_atlas_tau_decomposition(
        contract_forecast$qhat_contract, context$forecast$true_q,
        context$forecast$y, context$mu, context$sigma, context$sc,
        fixture$tau, config$trapezoidal_weights, jobs$case_id[[1L]]
      ), scenario_id = scenario_id, source_model_id = model_id
    )
    add_event_meta <- function(events) {
      if (!nrow(events)) {
        events$scenario_id <- character()
        events$source_model_id <- character()
        return(events)
      }
      events$scenario_id <- scenario_id
      events$source_model_id <- model_id
      events
    }
    crossings[[paste0(model_id, "_fit")]] <- add_event_meta(
      app_joint_qdesn_atlas_crossing_events(
        raw_fit, contract_fit$qhat_contract, fixture$tau, fixture$row_meta,
        jobs$case_id[[1L]], "fit"
      )
    )
    crossings[[paste0(model_id, "_forecast")]] <- add_event_meta(
      app_joint_qdesn_atlas_crossing_events(
        raw_forecast, contract_forecast$qhat_contract, fixture$tau,
        context$forecast$row_meta, jobs$case_id[[1L]], "forecast"
      )
    )
    adjustment_rows <- function(raw, contracted, row_meta, window) data.frame(
      case_id = jobs$case_id[[1L]], scenario_id = scenario_id,
      source_model_id = model_id, window = window, row_index = seq_len(nrow(raw)),
      full_time_index = row_meta$full_time_index,
      origin_index = if ("origin_index" %in% names(row_meta)) row_meta$origin_index else NA_integer_,
      horizon = if ("horizon" %in% names(row_meta)) row_meta$horizon else NA_integer_,
      mean_abs_adjustment = rowMeans(abs(contracted - raw)),
      max_abs_adjustment = apply(abs(contracted - raw), 1L, max),
      stringsAsFactors = FALSE
    )
    adjustments[[paste0(model_id, "_fit")]] <- adjustment_rows(
      raw_fit, contract_fit$qhat_contract, fixture$row_meta, "fit"
    )
    adjustments[[paste0(model_id, "_forecast")]] <- adjustment_rows(
      raw_forecast, contract_forecast$qhat_contract,
      context$forecast$row_meta, "forecast"
    )
    rm(fits, pooled, fit_band, forecast_band)
    invisible(gc(FALSE))
  }
  bind <- function(x) if (length(x)) do.call(rbind, x) else data.frame()
  files <- c(
    fit_path_bands = app_joint_qdesn_atlas_write_csv(bind(fit_paths), file.path(scenario_dir, "fit_path_bands.csv")),
    forecast_path_bands = app_joint_qdesn_atlas_write_csv(bind(forecast_paths), file.path(scenario_dir, "forecast_path_bands.csv")),
    forecast_origin_lead = app_joint_qdesn_atlas_write_csv(bind(score_maps), file.path(scenario_dir, "forecast_origin_lead.csv")),
    tau_decomposition = app_joint_qdesn_atlas_write_csv(bind(tau_rows), file.path(scenario_dir, "tau_decomposition.csv")),
    crossing_events = app_joint_qdesn_atlas_write_csv(bind(crossings), file.path(scenario_dir, "crossing_events.csv")),
    monotone_adjustment = app_joint_qdesn_atlas_write_csv(bind(adjustments), file.path(scenario_dir, "monotone_adjustment.csv"))
  )
  data.frame(
    scenario_id = scenario_id, artifact_id = names(files), path = unname(files),
    bytes = file.info(files)$size,
    sha256 = vapply(files, app_joint_qdesn_atlas_sha256, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_prepare <- function(
  config_path, source_root, output_dir, cores = 2L, force = FALSE
) {
  config <- app_joint_qdesn_atlas_read_config(config_path)
  audit <- app_joint_qdesn_atlas_validate_sources(config, source_root)
  if (dir.exists(output_dir)) {
    prepared <- file.exists(file.path(output_dir, "preparation_manifest.csv"))
    if (prepared && !force) {
      return(list(output_dir = normalizePath(output_dir), reused = TRUE))
    }
    quarantine <- paste0(
      output_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(output_dir, quarantine)) {
      stop("Could not quarantine prior atlas output.", call. = FALSE)
    }
  }
  dir.create(file.path(output_dir, "tables", "scenarios"), recursive = TRUE)
  dir.create(file.path(output_dir, "pages"), recursive = TRUE)
  dir.create(file.path(output_dir, "previews"), recursive = TRUE)
  dir.create(file.path(output_dir, "qa"), recursive = TRUE)

  packet <- audit$paths$packet
  table_map <- c(
    score_summary = "posterior_dgp_integrated_acrps_summary.csv",
    score_contrasts = "joint_independent_score_contrast_summary.csv",
    oracle_recovery = "oracle_recovery_diagnostics.csv",
    coherence = "raw_contract_crossing_summary.csv",
    parameter_diagnostics = "parameter_block_diagnostics.csv",
    score_diagnostics = "score_functional_mcmc_diagnostics.csv",
    expected_realized = "realized_expected_score_comparison.csv",
    chain_allocation = "chain_allocation_sensitivity.csv",
    chain_leave_one_out = "chain_leave_one_out_audit.csv",
    promotion_decisions = "mean_metric_promotion_decisions.csv"
  )
  case_meta <- unique(audit$score_summary[, c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "fit_structure", "variant_id"
  ), drop = FALSE])
  global_paths <- character()
  for (id in names(table_map)) {
    x <- app_joint_qdesn_atlas_read_csv(file.path(packet, table_map[[id]]))
    if ("case_id" %in% names(x) && !"source_model_id" %in% names(x)) {
      x <- merge(x, case_meta, by = "case_id", all.x = TRUE, sort = FALSE)
    }
    x <- app_joint_qdesn_atlas_attach_labels(x)
    if (all(c("scenario_order", "model_order") %in% names(x))) {
      x <- x[order(x$scenario_order, x$model_order), , drop = FALSE]
    }
    global_paths[[id]] <- app_joint_qdesn_atlas_write_csv(
      x, file.path(output_dir, "tables", paste0(id, ".csv"))
    )
  }
  contrasts <- app_joint_qdesn_atlas_read_csv(global_paths[["score_contrasts"]])
  scenarios <- app_joint_qdesn_atlas_scenario_dictionary()
  if (!"scenario_label" %in% names(contrasts)) contrasts <- merge(
      contrasts, scenarios, by.x = "base_scenario_id", by.y = "scenario_id",
      all.x = TRUE, sort = FALSE
    )
  contrasts$contrast_label <- ifelse(
    contrasts$variant_id == "AL", "Joint AL - Independent AL",
    "Joint exAL - Independent exAL"
  )
  contrasts <- contrasts[order(contrasts$scenario_order, contrasts$variant_id), ]
  global_paths[["score_contrasts"]] <- app_joint_qdesn_atlas_write_csv(
    contrasts, file.path(output_dir, "tables", "score_contrasts.csv")
  )

  page_plan <- app_joint_qdesn_atlas_page_plan()
  if (nrow(page_plan) != config$expected_pages) {
    stop("Atlas page-plan cardinality differs from the frozen contract.", call. = FALSE)
  }
  page_plan_path <- app_joint_qdesn_atlas_write_csv(
    page_plan, file.path(output_dir, "page_manifest.csv")
  )
  config_snapshot <- app_joint_qdesn_atlas_read_csv(config$config_path)
  config_snapshot_path <- app_joint_qdesn_atlas_write_csv(
    config_snapshot, file.path(output_dir, "config_snapshot.csv")
  )
  source_gate_path <- app_joint_qdesn_atlas_write_csv(
    audit$gates, file.path(output_dir, "source_gate_audit.csv")
  )
  source_worker_path <- app_joint_qdesn_atlas_write_csv(
    audit$worker_audit, file.path(output_dir, "source_worker_manifest_audit.csv")
  )
  source_manifest_path <- app_joint_qdesn_atlas_write_csv(
    rbind(
      transform(audit$packet_manifest, source = "phase181_packet"),
      transform(audit$fixture_manifest, source = "article_fixture")
    ), file.path(output_dir, "source_manifest_verification.csv")
  )

  scenario_ids <- app_joint_qdesn_atlas_scenario_dictionary()$scenario_id
  extract_one <- function(id) {
    try(app_joint_qdesn_atlas_extract_scenario(
      id, audit$registry, audit$paths$fixtures, config,
      file.path(output_dir, "tables", "scenarios", id)
    ), silent = TRUE)
  }
  cores <- max(1L, min(as.integer(cores), length(scenario_ids)))
  extracted <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(scenario_ids, extract_one, mc.cores = cores,
                       mc.preschedule = FALSE)
  } else lapply(scenario_ids, extract_one)
  failed <- vapply(extracted, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Atlas scenario extraction failed: %s",
      paste(vapply(extracted[failed], as.character, character(1L)), collapse = " | ")
    ), call. = FALSE)
  }
  extract_manifest <- do.call(rbind, extracted)
  extract_manifest_path <- app_joint_qdesn_atlas_write_csv(
    extract_manifest, file.path(output_dir, "scenario_extract_manifest.csv")
  )

  git_one <- function(args) {
    value <- system2("git", args, stdout = TRUE, stderr = TRUE)
    if (!length(value)) NA_character_ else paste(value, collapse = "\n")
  }
  status_text <- git_one(c("status", "--short"))
  status_file <- tempfile("joint_atlas_git_status_")
  writeLines(status_text, status_file, useBytes = TRUE)
  status_sha256 <- app_joint_qdesn_atlas_sha256(status_file)
  unlink(status_file)
  provenance <- data.frame(
    key = c(
      "contract_version", "scientific_source_commit", "packet_manifest_sha256",
      "superseded_packet_manifest_sha256", "selected_registry_sha256",
      "fixture_manifest_sha256", "source_root", "output_root", "git_branch",
      "git_head", "git_status_sha256", "r_version", "rng_kind",
      "posterior_interval_definition", "forecast_protocol"
    ),
    value = c(
      config$contract_version, config$scientific_source_commit,
      config$packet_manifest_sha256, config$superseded_packet_manifest_sha256,
      config$selected_registry_sha256, config$fixture_manifest_sha256,
      audit$paths$source_root, normalizePath(output_dir),
      git_one(c("branch", "--show-current")), git_one(c("rev-parse", "HEAD")),
      status_sha256,
      R.version.string, paste(RNGkind(), collapse = ","),
      sprintf(
        "Equal-tailed %.0f%% intervals from %d selected posterior draws per cell",
        100 * config$credible_interval, config$expected_score_draws_per_cell
      ),
      paste(
        "Sequential conditional evaluation: coefficients remain fixed;",
        "realized lagged responses become available between forecast origins."
      )
    ), stringsAsFactors = FALSE
  )
  provenance_path <- app_joint_qdesn_atlas_write_csv(
    provenance, file.path(output_dir, "provenance.csv")
  )
  readme_path <- file.path(output_dir, "README.md")
  writeLines(c(
    "# Joint QDESN Phase181 diagnostic atlas", "",
    "This ignored review packet compares the four final Phase181 MCMC models",
    "across all eight frozen synthetic mechanisms. It is diagnostic evidence,",
    "not a new model-selection stage and not an article asset.", "",
    "The first eight pages summarize the DGP-integrated finite-grid score,",
    "expected regret, joint-minus-independent contrasts, oracle recovery,",
    "crossings, monotone adjustment, and MCMC diagnostics. Four subsequent",
    "pages per mechanism show score decomposition, origin-by-lead behavior,",
    "forecast paths, and fit-window coherence.", "",
    sprintf("Posterior intervals use %d selected draws per cell.",
            config$expected_score_draws_per_cell),
    "Path bands are genuine equal-tailed posterior intervals after applying",
    "the same row-wise monotone forecast contract used by Phase181.",
    "Origins and leads represent sequential conditional evaluation, not an",
    "open-loop recursive forecast fan.", "",
    "All 16 joint-minus-independent 95% score contrasts include zero;",
    "comparative conclusions in this packet are therefore descriptive."
  ), readme_path, useBytes = TRUE)

  prep_paths <- c(
    page_manifest = page_plan_path, config_snapshot = config_snapshot_path,
    source_gate_audit = source_gate_path,
    source_worker_manifest_audit = source_worker_path,
    source_manifest_verification = source_manifest_path,
    scenario_extract_manifest = extract_manifest_path,
    provenance = provenance_path, README = normalizePath(readme_path), global_paths
  )
  prep_manifest <- data.frame(
    artifact_id = names(prep_paths),
    path = vapply(prep_paths, function(path) {
      substring(normalizePath(path), nchar(normalizePath(output_dir)) + 2L)
    }, character(1L)),
    bytes = file.info(prep_paths)$size,
    sha256 = vapply(prep_paths, app_joint_qdesn_atlas_sha256, character(1L)),
    stringsAsFactors = FALSE
  )
  prep_manifest_path <- app_joint_qdesn_atlas_write_csv(
    prep_manifest, file.path(output_dir, "preparation_manifest.csv")
  )
  list(
    output_dir = normalizePath(output_dir), preparation_manifest = prep_manifest_path,
    source_gates = audit$gates, scenario_extract_manifest = extract_manifest,
    reused = FALSE
  )
}

app_joint_qdesn_atlas_model_colours <- function() {
  setNames(app_joint_qdesn_atlas_model_dictionary()$colour,
           app_joint_qdesn_atlas_model_dictionary()$source_model_id)
}

app_joint_qdesn_atlas_tau_colours <- function() {
  c(`0.05` = "#0072B2", `0.50` = "#222222", `0.95` = "#D55E00")
}

app_joint_qdesn_atlas_plot_header <- function(title, subtitle = NULL) {
  graphics::mtext(title, side = 3, outer = TRUE, line = 1.6,
                  adj = 0, cex = 1.45, font = 2, col = "#17212B")
  if (!is.null(subtitle)) graphics::mtext(
    subtitle, side = 3, outer = TRUE, line = 0.15,
    adj = 0, cex = 0.78, col = "#4C5967"
  )
}

app_joint_qdesn_atlas_plot_footer <- function(page_number) {
  graphics::mtext(
    sprintf("JOINT Phase181 diagnostic atlas | page %d | descriptive review evidence", page_number),
    side = 1, outer = TRUE, line = 0.35, adj = 1, cex = 0.62, col = "#65717D"
  )
}

app_joint_qdesn_atlas_interval_panel <- function(
  x, mean_col, low_col, high_col, labels, colours, xlab, zero = FALSE,
  main = NULL
) {
  n <- nrow(x); y <- rev(seq_len(n))
  xr <- range(c(x[[low_col]], x[[high_col]], if (zero) 0), finite = TRUE)
  pad <- diff(xr) * 0.08
  graphics::plot(NA, xlim = xr + c(-pad, pad), ylim = c(0.5, n + 0.5),
                 yaxt = "n", ylab = "", xlab = xlab, bty = "n", main = main)
  graphics::abline(h = seq(0.5, n + 0.5, 1), col = "#EEF1F3", lwd = 0.6)
  if (zero) graphics::abline(v = 0, lty = 2, col = "#C43C39", lwd = 1.2)
  graphics::segments(x[[low_col]], y, x[[high_col]], y, col = colours, lwd = 2)
  graphics::points(x[[mean_col]], y, pch = 21, bg = colours, col = "white", cex = 1.1)
  graphics::axis(2, at = y, labels = labels, las = 2, cex.axis = 0.62, tick = FALSE)
  graphics::grid(nx = NA, ny = NULL, col = "#E1E6EA", lty = 1)
}

app_joint_qdesn_atlas_read_table <- function(output_dir, name) {
  app_joint_qdesn_atlas_read_csv(file.path(output_dir, "tables", paste0(name, ".csv")))
}

app_joint_qdesn_atlas_render_protocol <- function(output_dir, page) {
  provenance <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "provenance.csv"))
  gates <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "source_gate_audit.csv"))
  graphics::par(mar = c(0, 0, 0, 0), oma = c(2, 1, 4, 1))
  graphics::plot.new(); graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
  graphics::rect(0.035, 0.56, 0.49, 0.94, col = "#F3F7F9", border = "#CDD7DE")
  graphics::rect(0.515, 0.56, 0.965, 0.94, col = "#FFF7EC", border = "#E4CDA9")
  graphics::rect(0.035, 0.08, 0.965, 0.52, col = "white", border = "#CDD7DE")
  graphics::text(0.06, 0.90, "Scientific question", adj = 0, font = 2, cex = 1.05)
  graphics::text(0.06, 0.84, paste(
    "How do joint and independent quantile readouts compare under AL and exAL",
    "when the issued action is the seven-level monotone quantile grid?", sep = "\n"
  ), adj = c(0, 1), cex = 0.82)
  graphics::text(0.06, 0.71, "Primary estimand", adj = 0, font = 2, cex = 1.05)
  graphics::text(0.06, 0.66, paste(
    "DGP-integrated finite-grid quantile score: twice the trapezoidally weighted",
    "expected check loss over tau = 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95.",
    sep = "\n"
  ), adj = c(0, 1), cex = 0.79)
  graphics::text(0.54, 0.90, "Interpretation boundary", adj = 0, font = 2, cex = 1.05)
  graphics::text(0.54, 0.84, paste(
    "The score evaluates posterior quantile-grid actions. It does not treat the",
    "composite AL/exAL working likelihood as a scalar predictive density.", sep = "\n"
  ), adj = c(0, 1), cex = 0.82)
  graphics::text(0.54, 0.71, "Forecast protocol", adj = 0, font = 2, cex = 1.05)
  graphics::text(0.54, 0.66, paste(
    "Thirty-three sequential origins, leads 1-30, and 990 scored rows per cell.",
    "Readout coefficients remain fixed while realized lags become available.", sep = "\n"
  ), adj = c(0, 1), cex = 0.79)
  key <- setNames(provenance$value, provenance$key)
  lines <- c(
    sprintf("Frozen scientific commit: %s", substr(key[["scientific_source_commit"]], 1, 16)),
    sprintf("Corrected packet manifest: %s", substr(key[["packet_manifest_sha256"]], 1, 16)),
    sprintf("Selected registry: %s", substr(key[["selected_registry_sha256"]], 1, 16)),
    sprintf("Fixture manifest: %s", substr(key[["fixture_manifest_sha256"]], 1, 16)),
    sprintf("Source gates: %d/%d pass", sum(gates$status == "pass"), nrow(gates)),
    "Final packet: 8 scenarios x 4 models x 8 chains; 8,000 score draws per cell.",
    "All 16 joint-minus-independent 95% score contrasts include zero.",
    "Comparisons are descriptive; no new model selection is performed here."
  )
  graphics::text(0.06, 0.48, "Frozen evidence and audit status", adj = 0,
                 font = 2, cex = 1.05)
  for (i in seq_along(lines)) graphics::text(
    0.075, 0.43 - (i - 1) * 0.043, paste0("- ", lines[[i]]), adj = 0, cex = 0.78
  )
  app_joint_qdesn_atlas_plot_header(page$title,
    "A single hash-pinned review packet derived from the final Phase181 source registry.")
}

app_joint_qdesn_atlas_render_score_intervals <- function(output_dir, page, regret = FALSE) {
  x <- app_joint_qdesn_atlas_read_table(output_dir, "score_summary")
  x <- x[order(x$variant_id, x$scenario_order, x$model_order), ]
  graphics::par(mfrow = c(1, 2), mar = c(4, 10, 3, 1), oma = c(2, 1, 4, 1))
  for (variant in c("AL", "exAL")) {
    z <- x[x$variant_id == variant, ]
    if (regret) {
      z$low <- z$posterior_score_q025 - z$expected_oracle_acrps
      z$mid <- z$posterior_regret_mean
      z$high <- z$posterior_score_q975 - z$expected_oracle_acrps
      xlab <- "Expected regret (lower is better)"
    } else {
      z$low <- z$posterior_score_q025; z$mid <- z$posterior_score_mean
      z$high <- z$posterior_score_q975
      xlab <- "DGP-integrated finite-grid score (lower is better)"
    }
    labels <- paste(z$scenario_label, ifelse(z$fit_structure == "joint", "J", "I"), sep = " | ")
    app_joint_qdesn_atlas_interval_panel(
      z, "mid", "low", "high", labels, z$colour, xlab,
      zero = regret, main = if (variant == "AL") "AL-RHS" else "exAL-RHS"
    )
    if (!regret) {
      oracle <- z$expected_oracle_acrps; y <- rev(seq_len(nrow(z)))
      graphics::points(oracle, y, pch = 3, col = "#333333", cex = 0.7)
    }
  }
  app_joint_qdesn_atlas_plot_header(page$title,
    if (regret) "Equal-tailed 95% posterior intervals; zero is the DGP oracle minimum."
    else "Mean and equal-tailed 95% posterior interval; crosses mark the DGP oracle score.")
}

app_joint_qdesn_atlas_render_contrasts <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_read_table(output_dir, "score_contrasts")
  x <- x[order(x$scenario_order, x$variant_id), ]
  colours <- ifelse(x$variant_id == "AL", "#0072B2", "#D55E00")
  labels <- paste(x$scenario_label, x$variant_id, sep = " | ")
  graphics::par(mar = c(4, 12, 2, 1), oma = c(2, 1, 4, 1))
  app_joint_qdesn_atlas_interval_panel(
    x, "score_delta_mean", "score_delta_q025", "score_delta_q975",
    labels, colours, "Joint score - independent score", zero = TRUE
  )
  app_joint_qdesn_atlas_plot_header(page$title,
    "Negative values favor the joint readout. Every equal-tailed 95% interval includes zero.")
}

app_joint_qdesn_atlas_render_expected_realized <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_read_table(output_dir, "score_summary")
  xr <- range(c(x$canonical_action_dgp_integrated_acrps,
                x$canonical_action_realized_acrps), finite = TRUE)
  graphics::par(mar = c(4.5, 5, 2, 1), oma = c(2, 1, 4, 1))
  graphics::plot(x$canonical_action_dgp_integrated_acrps,
                 x$canonical_action_realized_acrps,
                 pch = ifelse(x$fit_structure == "joint", 21, 24), bg = x$colour,
                 col = "white", cex = 1.35, xlim = xr, ylim = xr,
                 xlab = "DGP-integrated score", ylab = "Realized seven-level score", bty = "n")
  graphics::abline(0, 1, lty = 2, col = "#555555")
  graphics::grid(col = "#E1E6EA")
  models <- app_joint_qdesn_atlas_model_dictionary()
  graphics::legend("topleft", legend = models$short_label, pch = c(21, 24, 21, 24),
                   pt.bg = models$colour, col = "white", bty = "n", cex = 0.8)
  app_joint_qdesn_atlas_plot_header(page$title,
    "The DGP-integrated score is the primary estimand; the realized score remains a compatibility diagnostic.")
}

app_joint_qdesn_atlas_heatmap <- function(matrix_value, row_labels, col_labels, main,
                                         palette, zlim = NULL, format = "%.3f") {
  if (is.null(zlim)) zlim <- range(matrix_value, finite = TRUE)
  graphics::image(seq_len(ncol(matrix_value)), seq_len(nrow(matrix_value)),
                  t(matrix_value[nrow(matrix_value):1, , drop = FALSE]),
                  col = palette, zlim = zlim, axes = FALSE, xlab = "", ylab = "", main = main)
  graphics::axis(1, at = seq_along(col_labels), labels = col_labels, las = 2, cex.axis = 0.72)
  graphics::axis(2, at = seq_along(row_labels), labels = rev(row_labels), las = 2, cex.axis = 0.64)
  for (i in seq_len(nrow(matrix_value))) for (j in seq_len(ncol(matrix_value))) {
    graphics::text(j, nrow(matrix_value) - i + 1,
                   sprintf(format, matrix_value[i, j]), cex = 0.58)
  }
  graphics::box(col = "#AAB4BD")
}

app_joint_qdesn_atlas_render_oracle <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_read_table(output_dir, "oracle_recovery")
  scenarios <- app_joint_qdesn_atlas_scenario_dictionary()
  models <- app_joint_qdesn_atlas_model_dictionary()
  graphics::par(mfrow = c(2, 2), mar = c(7, 7, 3, 1), oma = c(2, 1, 4, 1))
  for (window in c("fit", "forecast")) for (metric in c("mae", "rmse")) {
    value <- paste0("oracle_quantile_", metric)
    mat <- matrix(NA_real_, nrow(scenarios), nrow(models))
    for (i in seq_len(nrow(scenarios))) for (j in seq_len(nrow(models))) {
      z <- x[x$scenario_id == scenarios$scenario_id[[i]] &
             x$source_model_id == models$source_model_id[[j]] & x$window == window, ]
      mat[i, j] <- z[[value]][[1L]]
    }
    app_joint_qdesn_atlas_heatmap(
      mat, scenarios$scenario_label, models$short_label,
      sprintf("%s-window oracle %s", tools::toTitleCase(window), toupper(metric)),
      grDevices::colorRampPalette(c("#F7FBFF", "#6BAED6", "#08306B"))(60)
    )
  }
  app_joint_qdesn_atlas_plot_header(page$title,
    "MAE and RMSE compare reported quantile paths with known conditional quantiles; they are diagnostics, not forecast scores.")
}

app_joint_qdesn_atlas_render_coherence <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_read_table(output_dir, "coherence")
  models <- app_joint_qdesn_atlas_model_dictionary()
  aggregate_one <- function(value, fun) {
    sapply(models$source_model_id, function(id) fun(x[x$source_model_id == id, value]))
  }
  graphics::par(mfrow = c(1, 2), mar = c(7, 5, 3, 1), oma = c(2, 1, 4, 1))
  counts <- sapply(c("fit", "forecast"), function(w) sapply(
    models$source_model_id, function(id) sum(x$raw_crossing_pairs[
      x$source_model_id == id & x$window == w
    ])))
  graphics::barplot(t(counts), beside = TRUE, col = c("#9ECAE1", "#3182BD"),
                    names.arg = models$short_label, las = 2, ylab = "Raw adjacent-pair crossings",
                    main = "Canonical action crossings", border = NA)
  graphics::legend("topright", legend = c("Fit", "Forecast"),
                   fill = c("#9ECAE1", "#3182BD"), bty = "n", cex = 0.8)
  z <- x[x$window == "forecast", ]
  graphics::plot(z$model_order + stats::runif(nrow(z), -0.08, 0.08),
                 z$max_abs_monotone_adjustment, pch = 21, bg = z$colour, col = "white",
                 xaxt = "n", xlab = "", ylab = "Maximum absolute adjustment",
                 main = "Forecast monotone adjustment", bty = "n")
  graphics::axis(1, at = 1:4, labels = models$short_label, las = 2, cex.axis = 0.75)
  graphics::grid(nx = NA, col = "#E1E6EA")
  app_joint_qdesn_atlas_plot_header(page$title,
    "Raw crossings remain visible; the reported contract grid has zero crossings in all 32 cells.")
}

app_joint_qdesn_atlas_render_diagnostics <- function(output_dir, page) {
  score <- app_joint_qdesn_atlas_read_table(output_dir, "score_summary")
  param <- app_joint_qdesn_atlas_read_table(output_dir, "parameter_diagnostics")
  models <- app_joint_qdesn_atlas_model_dictionary()
  worst <- do.call(rbind, lapply(split(param, param$case_id), function(z) data.frame(
    case_id = z$case_id[[1L]], source_model_id = z$source_model_id[[1L]],
    max_rank_rhat = max(z$rank_rhat, na.rm = TRUE),
    min_bulk_ess = min(z$bulk_ess, na.rm = TRUE), stringsAsFactors = FALSE
  )))
  worst <- app_joint_qdesn_atlas_attach_labels(worst)
  graphics::par(mfrow = c(2, 2), mar = c(5, 5, 3, 1), oma = c(2, 1, 4, 1))
  panels <- list(
    list(score$score_rank_rhat, 1.05, "Score rank-Rhat", "Rank-Rhat"),
    list(score$score_bulk_ess, 400, "Score bulk ESS", "Bulk ESS"),
    list(worst$max_rank_rhat, 1.05, "Worst scalar-block rank-Rhat", "Rank-Rhat"),
    list(worst$min_bulk_ess, 400, "Minimum scalar-block bulk ESS", "Bulk ESS")
  )
  frames <- list(score, score, worst, worst)
  for (i in seq_along(panels)) {
    z <- frames[[i]]; value <- panels[[i]][[1L]]
    graphics::plot(z$model_order + stats::runif(nrow(z), -0.10, 0.10), value,
                   pch = 21, bg = z$colour, col = "white", xaxt = "n", xlab = "",
                   ylab = panels[[i]][[4L]], main = panels[[i]][[3L]], bty = "n")
    graphics::axis(1, at = 1:4, labels = models$short_label, las = 2, cex.axis = 0.68)
    graphics::abline(h = panels[[i]][[2L]], lty = 2, col = "#C43C39")
    graphics::grid(nx = NA, col = "#E1E6EA")
  }
  app_joint_qdesn_atlas_plot_header(page$title,
    "Mixing thresholds are review diagnostics. Quantile-grid functional stability governs interpretation.")
}

app_joint_qdesn_atlas_scenario_table <- function(output_dir, scenario_id, file) {
  app_joint_qdesn_atlas_read_csv(file.path(
    output_dir, "tables", "scenarios", scenario_id, file
  ))
}

app_joint_qdesn_atlas_render_tau <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_scenario_table(
    output_dir, page$scenario_id, "tau_decomposition.csv"
  )
  x <- app_joint_qdesn_atlas_attach_labels(x)
  models <- app_joint_qdesn_atlas_model_dictionary()
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 5, 3, 1), oma = c(2, 1, 4, 1))
  for (metric in c("weighted_expected_contribution", "expected_regret")) {
    yr <- range(x[[metric]], finite = TRUE)
    graphics::plot(range(x$tau), yr, type = "n", bty = "n", xlab = "Quantile level",
                   ylab = if (metric == "expected_regret") "Expected check-loss regret"
                   else "Weighted score contribution",
                   main = if (metric == "expected_regret") "Oracle-relative contribution"
                   else "Finite-grid score contribution")
    if (metric == "expected_regret") graphics::abline(h = 0, lty = 2, col = "#555555")
    for (i in seq_len(nrow(models))) {
      z <- x[x$source_model_id == models$source_model_id[[i]], ]
      z <- z[order(z$tau), ]
      graphics::lines(z$tau, z[[metric]], type = "o", pch = if (i %% 2) 16 else 17,
                      col = models$colour[[i]], lwd = 1.8, cex = 0.75)
    }
    graphics::grid(col = "#E1E6EA")
  }
  graphics::legend("top", inset = c(0, -0.04), xpd = NA, horiz = TRUE,
                   legend = models$short_label, col = models$colour,
                   pch = c(16, 17, 16, 17), lwd = 1.8, bty = "n", cex = 0.72)
  app_joint_qdesn_atlas_plot_header(page$title,
    "Canonical monotone action; the seven contributions sum to the DGP-integrated finite-grid score.")
}

app_joint_qdesn_atlas_origin_lead_panel <- function(z, model, zlim) {
  mat <- matrix(NA_real_, 33, 30)
  mat[cbind(z$origin_index, z$horizon)] <- z$expected_regret
  palette <- grDevices::colorRampPalette(c("#F7FBFF", "#6BAED6", "#08306B"))(80)
  graphics::image(1:30, 1:33, t(mat), col = palette, zlim = zlim,
                  xlab = "Lead", ylab = "Origin", main = model, useRaster = TRUE)
  graphics::box(col = "#AAB4BD")
}

app_joint_qdesn_atlas_render_origin_lead <- function(output_dir, page) {
  x <- app_joint_qdesn_atlas_scenario_table(
    output_dir, page$scenario_id, "forecast_origin_lead.csv"
  )
  models <- app_joint_qdesn_atlas_model_dictionary()
  upper <- stats::quantile(x$expected_regret, 0.99, names = FALSE, na.rm = TRUE)
  zlim <- c(0, max(upper, .Machine$double.eps))
  graphics::par(mfrow = c(2, 2), mar = c(4, 4, 3, 1), oma = c(2, 1, 4, 1))
  for (i in seq_len(nrow(models))) {
    z <- x[x$source_model_id == models$source_model_id[[i]], ]
    app_joint_qdesn_atlas_origin_lead_panel(z, models$short_label[[i]], zlim)
  }
  app_joint_qdesn_atlas_plot_header(page$title,
    "DGP-expected finite-grid regret; a common 99th-percentile colour cap makes the four panels comparable.")
}

app_joint_qdesn_atlas_path_panel <- function(z, model_label, forecast = TRUE,
                                             crossing_times = numeric()) {
  tau_colours <- app_joint_qdesn_atlas_tau_colours()
  xr <- range(z$full_time_index)
  yr <- range(c(z$posterior_q025, z$posterior_q975, z$true_quantile), finite = TRUE)
  graphics::plot(NA, xlim = xr, ylim = yr, xlab = if (forecast) "Held-out time" else "Fit-window time",
                 ylab = "Response / quantile", main = model_label, bty = "n")
  for (tau_value in sort(unique(z$tau), decreasing = TRUE)) {
    q <- z[abs(z$tau - tau_value) < 1e-10, ]
    q <- q[order(q$full_time_index), ]
    colour <- tau_colours[[sprintf("%.2f", tau_value)]]
    graphics::polygon(c(q$full_time_index, rev(q$full_time_index)),
                      c(q$posterior_q025, rev(q$posterior_q975)),
                      col = grDevices::adjustcolor(colour, alpha.f = 0.11), border = NA)
    graphics::lines(q$full_time_index, q$canonical_action, col = colour, lwd = 1.1)
    graphics::lines(q$full_time_index, q$true_quantile, col = colour, lwd = 0.75, lty = 3)
  }
  if (length(crossing_times)) graphics::rug(crossing_times, side = 3,
                                            col = "#C43C39", ticksize = 0.035)
  graphics::grid(col = "#E8ECEF")
}

app_joint_qdesn_atlas_render_paths <- function(output_dir, page, forecast = TRUE) {
  file <- if (forecast) "forecast_path_bands.csv" else "fit_path_bands.csv"
  x <- app_joint_qdesn_atlas_scenario_table(output_dir, page$scenario_id, file)
  events <- app_joint_qdesn_atlas_scenario_table(
    output_dir, page$scenario_id, "crossing_events.csv"
  )
  models <- app_joint_qdesn_atlas_model_dictionary()
  window <- if (forecast) "forecast" else "fit"
  graphics::par(mfrow = c(2, 2), mar = c(4, 4.5, 3, 1), oma = c(2, 1, 4, 1))
  for (i in seq_len(nrow(models))) {
    z <- x[x$source_model_id == models$source_model_id[[i]], ]
    crossing_times <- events$full_time_index[
      events$source_model_id == models$source_model_id[[i]] & events$window == window
    ]
    app_joint_qdesn_atlas_path_panel(
      z, models$short_label[[i]], forecast = forecast,
      crossing_times = unique(crossing_times)
    )
  }
  subtitle <- if (forecast) paste(
    "Solid: canonical contract action; dotted: oracle path; shaded: equal-tailed 95% posterior interval.",
    "Origins are sequential conditional evaluations, not open-loop fans."
  ) else paste(
    "Solid: canonical contract action; dotted: oracle path; shaded: equal-tailed 95% posterior interval.",
    "Red top-axis ticks mark raw crossing times before the monotone contract."
  )
  app_joint_qdesn_atlas_plot_header(page$title, subtitle)
}

app_joint_qdesn_atlas_render_page <- function(output_dir, page_number) {
  plan <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "page_manifest.csv"))
  page <- plan[plan$page_number == as.integer(page_number), , drop = FALSE]
  if (nrow(page) != 1L) stop("Unknown atlas page number.", call. = FALSE)
  config <- app_joint_qdesn_atlas_read_config(file.path(output_dir, "config_snapshot.csv"))
  png_path <- file.path(output_dir, page$png_path[[1L]])
  pdf_path <- file.path(output_dir, page$pdf_path[[1L]])
  dir.create(dirname(png_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::png(
    png_path, width = config$render_width_inches,
    height = config$render_height_inches, units = "in", res = config$render_dpi,
    type = "cairo", bg = "white"
  )
  set.seed(181000L + page$page_number[[1L]])
  type <- page$page_type[[1L]]
  if (type == "protocol") app_joint_qdesn_atlas_render_protocol(output_dir, page)
  else if (type == "score_intervals") app_joint_qdesn_atlas_render_score_intervals(output_dir, page)
  else if (type == "regret_intervals") app_joint_qdesn_atlas_render_score_intervals(output_dir, page, TRUE)
  else if (type == "contrasts") app_joint_qdesn_atlas_render_contrasts(output_dir, page)
  else if (type == "expected_realized") app_joint_qdesn_atlas_render_expected_realized(output_dir, page)
  else if (type == "oracle_recovery") app_joint_qdesn_atlas_render_oracle(output_dir, page)
  else if (type == "coherence") app_joint_qdesn_atlas_render_coherence(output_dir, page)
  else if (type == "mcmc_diagnostics") app_joint_qdesn_atlas_render_diagnostics(output_dir, page)
  else if (type == "tau_decomposition") app_joint_qdesn_atlas_render_tau(output_dir, page)
  else if (type == "origin_lead") app_joint_qdesn_atlas_render_origin_lead(output_dir, page)
  else if (type == "forecast_paths") app_joint_qdesn_atlas_render_paths(output_dir, page, TRUE)
  else if (type == "fit_coherence") app_joint_qdesn_atlas_render_paths(output_dir, page, FALSE)
  else stop(sprintf("Unsupported atlas page type '%s'.", type), call. = FALSE)
  app_joint_qdesn_atlas_plot_footer(page$page_number[[1L]])
  grDevices::dev.off()
  image <- png::readPNG(png_path)
  grDevices::cairo_pdf(
    pdf_path, width = config$render_width_inches,
    height = config$render_height_inches, onefile = FALSE
  )
  graphics::par(mar = rep(0, 4)); graphics::plot.new()
  graphics::rasterImage(image, 0, 0, 1, 1, interpolate = FALSE)
  grDevices::dev.off()
  data.frame(
    page_number = page$page_number, page_id = page$page_id,
    png_path = normalizePath(png_path), png_sha256 = app_joint_qdesn_atlas_sha256(png_path),
    pdf_path = normalizePath(pdf_path), pdf_sha256 = app_joint_qdesn_atlas_sha256(pdf_path),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_atlas_run <- function(command, args) {
  output <- system2(command, args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (length(status) && status != 0L) {
    stop(sprintf("Command failed: %s %s\n%s", command, paste(args, collapse = " "),
                 paste(output, collapse = "\n")), call. = FALSE)
  }
  output
}

app_joint_qdesn_atlas_pdf_pages <- function(path) {
  info <- app_joint_qdesn_atlas_run("pdfinfo", path)
  line <- grep("^Pages:", info, value = TRUE)
  if (length(line) != 1L) return(NA_integer_)
  as.integer(sub("^Pages:[[:space:]]+", "", line))
}

app_joint_qdesn_atlas_pdf_image_audit <- function(path) {
  lines <- app_joint_qdesn_atlas_run("pdfimages", c("-list", path))
  rows <- grep("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", lines,
               value = TRUE)
  if (!length(rows)) return(data.frame())
  values <- strsplit(trimws(rows), "[[:space:]]+")
  do.call(rbind, lapply(values, function(x) data.frame(
    page = as.integer(x[[1L]]), image_number = as.integer(x[[2L]]),
    width = as.integer(x[[4L]]), height = as.integer(x[[5L]]),
    x_ppi = as.numeric(x[[13L]]), y_ppi = as.numeric(x[[14L]]),
    stringsAsFactors = FALSE
  )))
}

app_joint_qdesn_atlas_png_audit <- function(path, expected_width, expected_height) {
  x <- png::readPNG(path)
  dimensions <- dim(x)
  if (length(dimensions) == 2L) {
    rgb <- x
    ink <- 1 - rgb
  } else {
    channels <- seq_len(min(3L, dimensions[[3L]]))
    rgb <- x[, , channels, drop = FALSE]
    if (length(channels) == 1L) {
      ink <- 1 - rgb[, , 1L]
    } else {
      channel_mean <- Reduce(`+`, lapply(channels, function(k) rgb[, , k])) /
        length(channels)
      ink <- 1 - channel_mean
      rm(channel_mean)
    }
  }
  border <- 20L
  edge <- c(
    ink[seq_len(border), , drop = FALSE],
    ink[(nrow(ink) - border + 1L):nrow(ink), , drop = FALSE],
    ink[, seq_len(border), drop = FALSE],
    ink[, (ncol(ink) - border + 1L):ncol(ink), drop = FALSE]
  )
  out <- data.frame(
    path = normalizePath(path), width = dimensions[[2L]], height = dimensions[[1L]],
    dimensions_pass = dimensions[[2L]] == expected_width &&
      dimensions[[1L]] == expected_height,
    ink_fraction = mean(ink > 0.02), edge_ink_fraction = mean(edge > 0.02),
    nonblank_pass = mean(ink > 0.02) > 0.003,
    margin_pass = mean(edge > 0.02) < 0.02,
    stringsAsFactors = FALSE
  )
  rm(x, rgb, ink, edge)
  invisible(gc(FALSE))
  out
}

app_joint_qdesn_atlas_render_pdf_pngs <- function(pdf, prefix, dpi = 96L) {
  dir.create(dirname(prefix), recursive = TRUE, showWarnings = FALSE)
  app_joint_qdesn_atlas_run(
    "pdftocairo", c("-png", "-r", as.character(as.integer(dpi)), pdf, prefix)
  )
  sort(list.files(dirname(prefix), pattern = paste0("^", basename(prefix), "-[0-9]+\\.png$"),
                  full.names = TRUE))
}

app_joint_qdesn_atlas_contact_sheet <- function(preview_paths, output_path) {
  grDevices::png(output_path, width = 2400, height = 3400, res = 200,
                 type = "cairo", bg = "#E8EDF1")
  grid::grid.newpage()
  rows <- 10L; columns <- 4L
  for (i in seq_along(preview_paths)) {
    row <- (i - 1L) %/% columns + 1L
    column <- (i - 1L) %% columns + 1L
    image <- png::readPNG(preview_paths[[i]])
    grid::grid.rect(
      x = (column - 0.5) / columns, y = 1 - (row - 0.5) / rows,
      width = 0.238, height = 0.094, gp = grid::gpar(fill = "white", col = "#AAB4BD")
    )
    grid::grid.raster(
      image, x = (column - 0.5) / columns, y = 1 - (row - 0.5) / rows,
      width = 0.232, height = 0.087, interpolate = TRUE
    )
    grid::grid.text(
      sprintf("%02d", i), x = (column - 0.5) / columns - 0.112,
      y = 1 - (row - 0.5) / rows + 0.039,
      gp = grid::gpar(fontsize = 7, fontface = "bold", col = "#17212B")
    )
    rm(image); invisible(gc(FALSE))
  }
  grDevices::dev.off()
  normalizePath(output_path)
}

app_joint_qdesn_atlas_write_manifest <- function(output_dir) {
  files <- list.files(output_dir, recursive = TRUE, full.names = TRUE,
                      all.files = FALSE)
  files <- files[file.info(files)$isdir %in% FALSE]
  files <- files[basename(files) != "artifact_manifest.csv"]
  relative <- substring(normalizePath(files), nchar(normalizePath(output_dir)) + 2L)
  manifest <- data.frame(
    artifact_id = gsub("[^A-Za-z0-9]+", "_", relative),
    path = relative, bytes = file.info(files)$size,
    sha256 = vapply(files, app_joint_qdesn_atlas_sha256, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest <- manifest[order(manifest$path), ]
  app_joint_qdesn_atlas_write_csv(
    manifest, file.path(output_dir, "artifact_manifest.csv")
  )
}

app_joint_qdesn_atlas_finalize <- function(output_dir, force = FALSE) {
  plan <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "page_manifest.csv"))
  config <- app_joint_qdesn_atlas_read_config(file.path(output_dir, "config_snapshot.csv"))
  png_paths <- file.path(output_dir, plan$png_path)
  pdf_paths <- file.path(output_dir, plan$pdf_path)
  if (nrow(plan) != config$expected_pages || any(!file.exists(png_paths)) ||
      any(!file.exists(pdf_paths))) {
    stop("Atlas finalization requires every source PNG and PDF page.", call. = FALSE)
  }
  combined <- file.path(output_dir, "joint_qdesn_phase181_diagnostic_atlas_FINAL_20260831.pdf")
  if (file.exists(combined) && !force) {
    stop("Combined atlas already exists; use --force to replace it.", call. = FALSE)
  }
  tmp_pdf <- tempfile("joint_qdesn_atlas_", tmpdir = output_dir, fileext = ".pdf")
  status <- system2("pdfunite", c(pdf_paths, tmp_pdf), stdout = TRUE, stderr = TRUE)
  exit <- attr(status, "status")
  if (length(exit) && exit != 0L) {
    app_joint_qdesn_atlas_run("gs", c(
      "-dBATCH", "-dNOPAUSE", "-q", "-sDEVICE=pdfwrite",
      paste0("-sOutputFile=", tmp_pdf), pdf_paths
    ))
  }
  if (!file.exists(tmp_pdf)) stop("PDF assembly produced no output.", call. = FALSE)
  if (file.exists(combined)) unlink(combined)
  if (!file.rename(tmp_pdf, combined)) stop("Could not publish combined atlas.", call. = FALSE)

  expected_width <- as.integer(config$render_width_inches * config$render_dpi)
  expected_height <- as.integer(config$render_height_inches * config$render_dpi)
  png_audit <- do.call(rbind, lapply(png_paths, function(path) {
    out <- app_joint_qdesn_atlas_png_audit(
      path, expected_width = expected_width, expected_height = expected_height
    )
    invisible(gc(FALSE))
    out
  }))
  image_audit <- app_joint_qdesn_atlas_pdf_image_audit(combined)
  qa_dir <- file.path(output_dir, "qa", paste0("render_", Sys.getpid()))
  dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
  render_a <- app_joint_qdesn_atlas_render_pdf_pngs(
    combined, file.path(qa_dir, "combined_a"), 96L
  )
  render_b <- app_joint_qdesn_atlas_render_pdf_pngs(
    combined, file.path(qa_dir, "combined_b"), 96L
  )
  source_render <- unlist(lapply(seq_along(pdf_paths), function(i) {
    app_joint_qdesn_atlas_render_pdf_pngs(
      pdf_paths[[i]], file.path(qa_dir, sprintf("source_%02d", i)), 96L
    )
  }), use.names = FALSE)
  stable <- length(render_a) == length(render_b) && all(
    vapply(render_a, app_joint_qdesn_atlas_sha256, character(1L)) ==
      vapply(render_b, app_joint_qdesn_atlas_sha256, character(1L))
  )
  equivalent <- length(render_a) == length(source_render) && all(
    vapply(render_a, app_joint_qdesn_atlas_sha256, character(1L)) ==
      vapply(source_render, app_joint_qdesn_atlas_sha256, character(1L))
  )
  preview_paths <- file.path(
    output_dir, "previews", sprintf("page_%02d.png", seq_along(render_a))
  )
  copied <- file.copy(render_a, preview_paths, overwrite = TRUE)
  if (!all(copied)) stop("Could not preserve atlas page previews.", call. = FALSE)
  contact <- app_joint_qdesn_atlas_contact_sheet(
    preview_paths, file.path(output_dir, "previews", "contact_sheet.png")
  )
  unlink(qa_dir, recursive = TRUE, force = TRUE)

  embedded_ppi <- if (nrow(image_audit)) {
    sort(unique(c(image_audit$x_ppi, image_audit$y_ppi)))
  } else {
    numeric()
  }
  embedded_ppi_min <- if (length(embedded_ppi)) min(embedded_ppi) else NA_real_
  embedded_ppi_floor <- as.integer(0.95 * config$render_dpi)
  qa <- data.frame(
    gate = c(
      "combined_page_count", "source_page_count", "one_image_per_page",
      "embedded_image_ppi_min", "source_png_dimensions", "nonblank_pages",
      "clear_page_margins", "repeat_render_stability",
      "source_to_combined_equivalence", "contact_sheet"
    ),
    observed = c(
      app_joint_qdesn_atlas_pdf_pages(combined), length(pdf_paths), nrow(image_audit),
      embedded_ppi_min,
      sum(png_audit$dimensions_pass), sum(png_audit$nonblank_pass),
      sum(png_audit$margin_pass), as.character(stable), as.character(equivalent),
      as.character(file.exists(contact))
    ),
    expected = c(
      config$expected_pages, config$expected_pages, config$expected_pages,
      paste0(">=", embedded_ppi_floor), config$expected_pages, config$expected_pages,
      config$expected_pages, TRUE, TRUE, TRUE
    ), stringsAsFactors = FALSE
  )
  qa$observed <- as.character(qa$observed)
  qa$expected <- as.character(qa$expected)
  qa$status <- c(
    if (app_joint_qdesn_atlas_pdf_pages(combined) == config$expected_pages) "pass" else "fail",
    if (length(pdf_paths) == config$expected_pages) "pass" else "fail",
    if (nrow(image_audit) == config$expected_pages) "pass" else "fail",
    if (is.finite(embedded_ppi_min) && embedded_ppi_min >= embedded_ppi_floor) "pass" else "fail",
    if (sum(png_audit$dimensions_pass) == config$expected_pages) "pass" else "fail",
    if (sum(png_audit$nonblank_pass) == config$expected_pages) "pass" else "fail",
    if (sum(png_audit$margin_pass) == config$expected_pages) "pass" else "fail",
    if (isTRUE(stable)) "pass" else "fail",
    if (isTRUE(equivalent)) "pass" else "fail",
    if (file.exists(contact)) "pass" else "fail"
  )
  app_joint_qdesn_atlas_write_csv(
    png_audit, file.path(output_dir, "qa", "page_ink_and_margin_audit.csv")
  )
  app_joint_qdesn_atlas_write_csv(
    image_audit, file.path(output_dir, "qa", "embedded_image_audit.csv")
  )
  qa_path <- app_joint_qdesn_atlas_write_csv(
    qa, file.path(output_dir, "visual_qa.csv")
  )
  if (any(qa$status != "pass")) {
    stop("Atlas visual/PDF QA failed closed.", call. = FALSE)
  }
  manifest <- app_joint_qdesn_atlas_write_manifest(output_dir)
  list(
    output_dir = normalizePath(output_dir), combined_pdf = normalizePath(combined),
    combined_pdf_sha256 = app_joint_qdesn_atlas_sha256(combined),
    visual_qa = qa_path, artifact_manifest = manifest
  )
}

app_joint_qdesn_atlas_check <- function(output_dir) {
  config <- app_joint_qdesn_atlas_read_config(file.path(output_dir, "config_snapshot.csv"))
  manifest <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "artifact_manifest.csv"))
  paths <- file.path(output_dir, manifest$path)
  manifest_pass <- file.exists(paths) &
    vapply(paths, app_joint_qdesn_atlas_sha256, character(1L)) == manifest$sha256
  source_gates <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "source_gate_audit.csv"))
  visual <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "visual_qa.csv"))
  score <- app_joint_qdesn_atlas_read_table(output_dir, "score_summary")
  contrast <- app_joint_qdesn_atlas_read_table(output_dir, "score_contrasts")
  coherence <- app_joint_qdesn_atlas_read_table(output_dir, "coherence")
  plan <- app_joint_qdesn_atlas_read_csv(file.path(output_dir, "page_manifest.csv"))
  scenario_ids <- app_joint_qdesn_atlas_scenario_dictionary()$scenario_id
  path_gate <- do.call(rbind, lapply(scenario_ids, function(id) {
    fit <- app_joint_qdesn_atlas_scenario_table(output_dir, id, "fit_path_bands.csv")
    forecast <- app_joint_qdesn_atlas_scenario_table(output_dir, id, "forecast_path_bands.csv")
    finite <- all(is.finite(as.matrix(rbind(
      fit[, c("posterior_mean", "posterior_median", "posterior_q025", "posterior_q975",
              "canonical_action", "true_quantile")],
      forecast[, c("posterior_mean", "posterior_median", "posterior_q025", "posterior_q975",
                   "canonical_action", "true_quantile")]
    ))))
    ordered <- all(fit$posterior_q025 <= fit$posterior_median &
                   fit$posterior_median <= fit$posterior_q975) &&
      all(forecast$posterior_q025 <= forecast$posterior_median &
          forecast$posterior_median <= forecast$posterior_q975)
    data.frame(
      scenario_id = id, fit_rows = nrow(fit), forecast_rows = nrow(forecast),
      finite = finite, intervals_ordered = ordered,
      status = if (nrow(fit) == 4L * 3L * 500L &&
        nrow(forecast) == 4L * 3L * 990L && finite && ordered) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
  combined <- file.path(output_dir, "joint_qdesn_phase181_diagnostic_atlas_FINAL_20260831.pdf")
  gates <- data.frame(
    gate = c(
      "artifact_manifest", "source_gates", "visual_qa", "page_plan",
      "score_cells", "contrast_rows", "contract_crossings", "path_tables",
      "combined_pdf_pages"
    ),
    observed = c(
      sum(manifest_pass), sum(source_gates$status == "pass"),
      sum(visual$status == "pass"), nrow(plan), nrow(score), nrow(contrast),
      sum(coherence$contract_crossing_pairs), sum(path_gate$status == "pass"),
      app_joint_qdesn_atlas_pdf_pages(combined)
    ),
    expected = c(
      nrow(manifest), nrow(source_gates), nrow(visual), config$expected_pages,
      config$expected_cells, 2L * config$expected_scenarios, 0L,
      config$expected_scenarios, config$expected_pages
    ), stringsAsFactors = FALSE
  )
  gates$status <- ifelse(as.character(gates$observed) == as.character(gates$expected),
                         "pass", "fail")
  check_path <- app_joint_qdesn_atlas_write_csv(
    gates, file.path(output_dir, "final_check.csv")
  )
  path_path <- app_joint_qdesn_atlas_write_csv(
    path_gate, file.path(output_dir, "qa", "path_interval_audit.csv")
  )
  if (any(gates$status != "pass")) stop("Final atlas check failed.", call. = FALSE)
  # The check itself changes the packet, so refresh its manifest once.
  manifest_path <- app_joint_qdesn_atlas_write_manifest(output_dir)
  list(
    status = "pass", gates = gates, check_path = check_path,
    path_interval_audit = path_path, artifact_manifest = manifest_path,
    combined_pdf = normalizePath(combined),
    combined_pdf_sha256 = app_joint_qdesn_atlas_sha256(combined)
  )
}
