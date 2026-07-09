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

app_qdesn_block_seed <- function(model_row, cfg, block = c("reference", "discrepancy")) {
  block <- match.arg(block)
  base_seed <- app_model_row_reservoir_seed(model_row, cfg)
  if (!is.finite(base_seed)) base_seed <- app_config_reservoir_seed(cfg)
  if (!is.finite(base_seed)) base_seed <- 20260511L
  if (identical(block, "reference")) return(as.integer(base_seed))
  as.integer(base_seed + app_qdesn_discrepancy_seed_offset(cfg))
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
    reference_seed <- app_qdesn_block_seed(row, cfg, "reference")
    discrepancy_seed <- app_qdesn_block_seed(row, cfg, "discrepancy")
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
