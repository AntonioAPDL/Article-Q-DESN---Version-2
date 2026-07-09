#!/usr/bin/env Rscript
# Purpose: screen a grid of D-ESN reservoir candidates for the latent-path
# application without launching VB or MCMC. Each candidate overrides only the
# reservoir controls listed in the candidate grid; all data, feature-contract,
# and model-contract settings come from the supplied application config.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/launch_control.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/reservoir_screening.R"))

app_parse_seed_arg <- function(x, fallback) {
  if (is.null(x) || !nzchar(as.character(x)[[1L]])) return(as.integer(fallback))
  x <- gsub("[[:space:]]+", "", as.character(x)[[1L]])
  if (grepl("^[0-9]+:[0-9]+$", x)) {
    parts <- as.integer(strsplit(x, ":", fixed = FALSE)[[1L]])
    return(seq.int(parts[[1L]], parts[[2L]]))
  }
  seeds <- as.integer(strsplit(x, ",", fixed = TRUE)[[1L]])
  seeds[is.finite(seeds)]
}

app_append_csv <- function(x, path) {
  if (is.null(x) || !nrow(x)) return(invisible(path))
  app_ensure_dir(dirname(path))
  write.table(
    x,
    file = path,
    append = file.exists(path),
    col.names = !file.exists(path),
    row.names = FALSE,
    sep = ",",
    na = "",
    qmethod = "double"
  )
  invisible(path)
}

app_candidate_value <- function(row, name, fallback = NULL) {
  if (!name %in% names(row)) return(fallback)
  val <- row[[name]][[1L]]
  if (is.na(val) || !nzchar(as.character(val))) fallback else val
}

app_candidate_numeric <- function(row, name, fallback = NULL) {
  val <- app_candidate_value(row, name, fallback)
  out <- suppressWarnings(as.numeric(val))
  if (!is.finite(out)) fallback else out
}

app_candidate_integer <- function(row, name, fallback = NULL) {
  val <- app_candidate_numeric(row, name, fallback)
  out <- suppressWarnings(as.integer(val))
  if (!is.finite(out)) fallback else out
}

app_candidate_integer_vector <- function(row, name, fallback = NULL) {
  if (!name %in% names(row)) return(fallback)
  val <- row[[name]][[1L]]
  if (is.na(val) || !nzchar(as.character(val))) return(fallback)
  raw <- gsub("[[:space:]]+", "", as.character(val))
  out <- suppressWarnings(as.integer(strsplit(raw, "[;|,]")[[1L]]))
  if (!length(out) || any(!is.finite(out))) fallback else out
}

app_set_lag_range <- function(lo, hi) {
  list(range = c(as.integer(lo), as.integer(hi)))
}

app_apply_candidate_memory_contract <- function(cfg, m) {
  m <- as.integer(m)
  if (!is.finite(m) || m <= 0L) return(cfg)
  cfg$feature_contract$reservoir_input$output_lags <- app_set_lag_range(1L, m)
  covariates <- names(cfg$feature_contract$reservoir_input$covariates %||% list())
  for (v in covariates) {
    cfg$feature_contract$reservoir_input$covariates[[v]] <- app_set_lag_range(0L, m)
  }
  if (!is.null((cfg$feature_contract$readout %||% list())$input_block)) {
    cfg$feature_contract$readout$input_block$output_lags <- app_set_lag_range(1L, m)
    readout_covariates <- names(cfg$feature_contract$readout$input_block$covariates %||% list())
    for (v in readout_covariates) {
      cfg$feature_contract$readout$input_block$covariates[[v]] <- app_set_lag_range(0L, m)
    }
  }
  if (!is.null((cfg$covariates %||% list())$readout)) {
    cfg$covariates$readout$lags <- app_set_lag_range(0L, m)
  }
  cfg
}

app_apply_reservoir_candidate <- function(cfg, row) {
  cfg_i <- cfg
  cfg_i$reservoir$D <- app_candidate_integer(row, "D", cfg$reservoir$D %||% 1L)
  n_vec <- app_candidate_integer_vector(row, "n_vector", NULL)
  if (is.null(n_vec)) n_vec <- app_candidate_integer_vector(row, "n", NULL)
  if (is.null(n_vec)) n_vec <- as.integer(unlist(cfg$reservoir$n %||% 300L, use.names = FALSE))
  if (length(n_vec) == 1L) n_vec <- rep(n_vec, cfg_i$reservoir$D)
  if (length(n_vec) != cfg_i$reservoir$D || any(!is.finite(n_vec)) || any(n_vec <= 0L)) {
    stop("Candidate reservoir n/n_vector does not match D.", call. = FALSE)
  }
  cfg_i$reservoir[["n"]] <- n_vec
  n_tilde_vec <- app_candidate_integer_vector(row, "n_tilde", NULL)
  if (!is.null(n_tilde_vec)) {
    cfg_i$reservoir$n_tilde <- n_tilde_vec
  } else if (cfg_i$reservoir$D <= 1L) {
    cfg_i$reservoir$n_tilde <- integer(0)
  } else {
    cfg_i$reservoir$n_tilde <- n_vec[-cfg_i$reservoir$D]
  }
  cfg_i$reservoir$m <- app_candidate_integer(row, "m", cfg$reservoir$m %||% 0L)
  cfg_i <- app_apply_candidate_memory_contract(cfg_i, cfg_i$reservoir$m)
  cfg_i$reservoir$washout <- app_candidate_integer(row, "washout", cfg$reservoir$washout %||% 0L)
  cfg_i$reservoir$alpha <- rep(app_candidate_numeric(row, "alpha", as.numeric(unlist(cfg$reservoir$alpha %||% 0.25))[[1L]]), cfg_i$reservoir$D)
  cfg_i$reservoir$rho <- rep(app_candidate_numeric(row, "rho", as.numeric(unlist(cfg$reservoir$rho %||% 0.95))[[1L]]), cfg_i$reservoir$D)
  cfg_i$reservoir$pi_w <- rep(app_candidate_numeric(row, "pi_w", as.numeric(unlist(cfg$reservoir$pi_w %||% 0.10))[[1L]]), cfg_i$reservoir$D)
  cfg_i$reservoir$pi_in <- rep(app_candidate_numeric(row, "pi_in", as.numeric(unlist(cfg$reservoir$pi_in %||% 1.00))[[1L]]), cfg_i$reservoir$D)
  cfg_i$reservoir$win_scale_global <- app_candidate_numeric(row, "win_scale_global", cfg$reservoir$win_scale_global %||% 1)
  cfg_i$reservoir$win_scale_bias <- app_candidate_numeric(row, "win_scale_bias", cfg$reservoir$win_scale_bias %||% 1)
  cfg_i$reservoir$input_bound <- as.character(app_candidate_value(row, "input_bound", cfg$reservoir$input_bound %||% "none"))
  cfg_i$reservoir$seed <- app_candidate_integer(row, "seed", app_candidate_integer(row, "launch_seed", cfg$reservoir$seed %||% 20260512L))
  cfg_i
}

args <- app_parse_args(list(
  config = "application/config/glofas_latent_path_al_vb_dec25_d1n300_focused_screen.yaml",
  candidate_grid = "application/config/reservoir_candidate_grid_latent_path_d1n300_focused_screen.csv",
  run_id = NULL,
  seeds = "20260512:20260518",
  diagnostic_target = "reservoir",
  cheap_validation = "false",
  baseline_score = "",
  max_corr_features_full = "",
  corr_block_size = "",
  spectral_radius_exact_max_n = "512",
  pruning_threshold = "",
  reject_on_cheap_validation = "false",
  start_index = "1",
  end_index = ""
))

cfg <- app_read_config(app_path(args$config))
app_validate_application_model_contract(cfg)
run_id <- args$run_id %||% app_run_id(cfg)
app_validate_run_id_for_launch(cfg, run_id)
app_validate_run_directory_for_workflow(cfg, run_id = run_id, allow_existing_run_dir = FALSE)
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_stage_start("03_screen_reservoir_candidate_grid", run_dirs)

tryCatch({
  panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
  if (!file.exists(panel_path)) {
    stop(sprintf("Missing application panel: %s. Run 01_build_panel.R first.", panel_path), call. = FALSE)
  }
  panel <- readRDS(panel_path)
  model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (!nrow(cutoffs)) stop("No enabled cutoff rows are available.", call. = FALSE)
  cutoff_row <- cutoffs[1L, , drop = FALSE]

  qrows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (!nrow(qrows)) stop("No enabled Q-DESN model rows matched the reservoir screening request.", call. = FALSE)
  template_row <- qrows[1L, , drop = FALSE]

  candidate_grid_path <- app_resolve_path(args$candidate_grid, must_work = TRUE)
  candidates <- app_read_csv(candidate_grid_path)
  required_cols <- c("spec_id", "m", "alpha", "rho", "pi_w", "pi_in", "win_scale_global", "win_scale_bias", "input_bound")
  missing_cols <- setdiff(required_cols, names(candidates))
  if (length(missing_cols)) {
    stop(sprintf("Candidate grid is missing required columns: %s.", paste(missing_cols, collapse = ", ")), call. = FALSE)
  }
  if (anyDuplicated(candidates$spec_id)) {
    stop("Candidate grid contains duplicated spec_id values.", call. = FALSE)
  }
  candidate_start <- suppressWarnings(as.integer(args$start_index))
  candidate_end <- suppressWarnings(as.integer(args$end_index))
  if (!is.finite(candidate_start) || candidate_start < 1L) candidate_start <- 1L
  if (!is.finite(candidate_end) || candidate_end > nrow(candidates)) candidate_end <- nrow(candidates)
  if (candidate_end < candidate_start) {
    stop("Candidate-grid end_index is smaller than start_index.", call. = FALSE)
  }
  candidate_indices <- seq.int(candidate_start, candidate_end)
  app_write_csv(candidates, file.path(run_dirs$tables, "reservoir_candidate_grid.csv"))

  cfg_overrides <- list()
  if (nzchar(args$max_corr_features_full)) cfg_overrides$max_corr_features_full <- as.integer(args$max_corr_features_full)
  if (nzchar(args$corr_block_size)) cfg_overrides$corr_block_size <- as.integer(args$corr_block_size)
  if (nzchar(args$spectral_radius_exact_max_n)) {
    options(app_qdesn_spectral_radius_exact_max_n = as.integer(args$spectral_radius_exact_max_n))
  }
  if (nzchar(args$pruning_threshold)) cfg_overrides$pruning_threshold <- as.numeric(args$pruning_threshold)
  cfg_overrides$reject_on_cheap_validation <- app_as_bool(args$reject_on_cheap_validation)
  if (!app_as_bool(args$cheap_validation)) {
    cfg_overrides$validation_metric <- "none"
  }
  diag_cfg <- do.call(app_reservoir_diagnostic_config, cfg_overrides)
  matrix_role <- match.arg(
    as.character(args$diagnostic_target %||% "reservoir")[[1L]],
    c("layers", "reservoir", "readout", "both")
  )
  seeds <- app_parse_seed_arg(args$seeds, fallback = cfg$reservoir$seed %||% 20260512L)
  if (!length(seeds)) stop("Reservoir screening seed list is empty.", call. = FALSE)
  baseline_score <- suppressWarnings(as.numeric(args$baseline_score))
  if (!is.finite(baseline_score)) baseline_score <- NULL

  architecture_reports <- list()
  seed_rows <- list()
  state_rows <- list()
  layer_rows <- list()
  suggestion_rows <- list()
  progress_path <- file.path(run_dirs$logs, "reservoir_candidate_grid_progress.csv")
  app_append_csv(
    data.frame(
      candidate_index = integer(),
      n_candidates = integer(),
      spec_id = character(),
      decision = character(),
      time = character(),
      stringsAsFactors = FALSE
    ),
    progress_path
  )

  for (i in candidate_indices) {
    candidate <- candidates[i, , drop = FALSE]
    spec_id <- as.character(candidate$spec_id[[1L]])
    cfg_i <- app_apply_reservoir_candidate(cfg, candidate)
    row_i <- template_row
    row_i$fit_id[[1L]] <- spec_id
    row_i$model_id[[1L]] <- spec_id
    row_i$reservoir_seed[[1L]] <- seeds[[1L]]
    row_i$notes[[1L]] <- sprintf(
      "Reservoir candidate D=%s n=%s n_tilde=%s m=%s alpha=%s rho=%s pi_w=%s pi_in=%s win_scale_global=%s win_scale_bias=%s input_bound=%s.",
      cfg_i$reservoir$D,
      paste(cfg_i$reservoir$n, collapse = ";"),
      paste(cfg_i$reservoir$n_tilde %||% integer(0), collapse = ";"),
      candidate$m[[1L]], candidate$alpha[[1L]], candidate$rho[[1L]],
      candidate$pi_w[[1L]], candidate$pi_in[[1L]],
      candidate$win_scale_global[[1L]], candidate$win_scale_bias[[1L]],
      candidate$input_bound[[1L]]
    )
    report <- app_screen_reservoir_architecture(
      cfg = cfg_i,
      panel = panel,
      model_row = row_i,
      cutoff_row = cutoff_row,
      seeds = seeds,
      config = diag_cfg,
      baseline_score = baseline_score,
      metadata = list(
        spec_id = spec_id,
        fit_id = spec_id,
        model_id = spec_id,
        matrix_role = matrix_role,
        config_path = args$config,
        candidate_grid = app_prefer_repo_relative_path(candidate_grid_path),
        run_id = run_id,
        D = cfg_i$reservoir$D,
        n = paste(cfg_i$reservoir$n, collapse = ","),
        m = cfg_i$reservoir$m,
        alpha = paste(cfg_i$reservoir$alpha, collapse = ","),
        rho = paste(cfg_i$reservoir$rho, collapse = ","),
        pi_w = paste(cfg_i$reservoir$pi_w, collapse = ","),
        pi_in = paste(cfg_i$reservoir$pi_in, collapse = ","),
        win_scale_global = cfg_i$reservoir$win_scale_global,
        win_scale_bias = cfg_i$reservoir$win_scale_bias,
        input_bound = cfg_i$reservoir$input_bound
      )
    )
    architecture_reports[[length(architecture_reports) + 1L]] <- report
    arch_i <- merge(
      candidate,
      app_architecture_summary_row(report),
      by = "spec_id",
      all.y = TRUE,
      sort = FALSE
    )
    seed_i <- app_bind_rows_fill(lapply(report$per_seed_reports, app_seed_report_row))
    state_i <- app_bind_rows_fill(lapply(report$per_seed_reports, app_state_report_rows))
    layer_i <- app_bind_rows_fill(lapply(report$per_seed_reports, app_layer_report_rows))
    suggestion_i <- app_bind_rows_fill(lapply(report$per_seed_reports, app_repair_suggestion_rows))
    seed_rows[[length(seed_rows) + 1L]] <- seed_i
    state_rows[[length(state_rows) + 1L]] <- state_i
    layer_rows[[length(layer_rows) + 1L]] <- layer_i
    suggestion_rows[[length(suggestion_rows) + 1L]] <- suggestion_i
    app_append_csv(arch_i, file.path(run_dirs$tables, "reservoir_screening_architecture_summary.csv"))
    app_append_csv(seed_i, file.path(run_dirs$tables, "reservoir_screening_seed_reports.csv"))
    app_append_csv(state_i, file.path(run_dirs$tables, "reservoir_screening_state_diagnostics.csv"))
    app_append_csv(layer_i, file.path(run_dirs$tables, "reservoir_screening_layer_stability.csv"))
    app_append_csv(suggestion_i, file.path(run_dirs$tables, "reservoir_screening_repair_suggestions.csv"))
    app_append_csv(
      data.frame(
        candidate_index = i,
        n_candidates = nrow(candidates),
        spec_id = spec_id,
        decision = report$decision,
        time = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
        stringsAsFactors = FALSE
      ),
      progress_path
    )
  }

  architecture_table <- app_bind_rows_fill(lapply(architecture_reports, app_architecture_summary_row))
  architecture_table <- merge(
    candidates,
    architecture_table,
    by = "spec_id",
    all.y = TRUE,
    sort = FALSE
  )
  app_write_csv(architecture_table, file.path(run_dirs$tables, "reservoir_screening_architecture_summary.csv"))
  app_write_csv(app_bind_rows_fill(seed_rows), file.path(run_dirs$tables, "reservoir_screening_seed_reports.csv"))
  app_write_csv(app_bind_rows_fill(state_rows), file.path(run_dirs$tables, "reservoir_screening_state_diagnostics.csv"))
  app_write_csv(app_bind_rows_fill(layer_rows), file.path(run_dirs$tables, "reservoir_screening_layer_stability.csv"))
  app_write_csv(app_bind_rows_fill(suggestion_rows), file.path(run_dirs$tables, "reservoir_screening_repair_suggestions.csv"))

  manifest <- list(
    run_id = run_id,
    config = args$config,
    candidate_grid = app_prefer_repo_relative_path(candidate_grid_path),
    seeds = seeds,
    start_index = candidate_start,
    end_index = candidate_end,
    diagnostic_target = matrix_role,
    spectral_radius_exact_max_n = args$spectral_radius_exact_max_n,
    reports = lapply(architecture_reports, app_reservoir_report_to_list)
  )
  app_write_json(manifest, file.path(run_dirs$manifest, "reservoir_candidate_grid_report.json"))

  app_stage_done("03_screen_reservoir_candidate_grid", run_dirs)
}, error = function(e) {
  app_stage_done("03_screen_reservoir_candidate_grid", run_dirs, status = "failed", message = conditionMessage(e))
  stop(e)
})
