#!/usr/bin/env Rscript

script_file <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/validation_interface_contract.R"))

args <- app_parse_args(list(
  config = app_default_tt500_final_validation_config(),
  out_csv = app_path("tables/qdesn_validation_tt500_final_summary.csv"),
  out_wrapper = app_path("tables/qdesn_validation_tt500_final_tables.tex"),
  out_combined = app_path("tables/qdesn_validation_tt500_final_combined.tex"),
  out_protocol = app_path("tables/qdesn_validation_tt500_final_protocol.tex"),
  out_normal = app_path("tables/qdesn_validation_tt500_final_normal.tex"),
  out_laplace = app_path("tables/qdesn_validation_tt500_final_laplace.tex"),
  out_gausmix = app_path("tables/qdesn_validation_tt500_final_gausmix.tex"),
  out_manifest = app_path("tables/qdesn_validation_tt500_final_manifest.txt")
))

latex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x)
  x
}

format_float <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x)) return("--")
  ax <- abs(x)
  if (ax >= 1.0e4) {
    exponent <- floor(log10(ax))
    mantissa <- x / (10^exponent)
    return(sprintf("$%.2f\\times10^{%d}$", mantissa, exponent))
  }
  if (ax >= 100) return(sprintf("%.1f", x))
  if (ax >= 10) return(sprintf("%.2f", x))
  if (ax >= 1) return(sprintf("%.3f", x))
  sprintf("%.4f", x)
}

bold_if_best <- function(value, best) {
  out <- format_float(value)
  if (!is.finite(as.numeric(value)) || !is.finite(as.numeric(best))) return(out)
  if (abs(as.numeric(value) - as.numeric(best)) <= 1.0e-10) {
    return(sprintf("\\textbf{%s}", out))
  }
  out
}

extract_qdesn_likelihood <- function(spec_id) {
  hit <- sub("^.*__(al|exal)__[[:xdigit:]]+$", "\\1", as.character(spec_id), perl = TRUE)
  ifelse(hit %in% c("al", "exal"), hit, NA_character_)
}

qdesn_variant_label <- function(variant) {
  ifelse(as.character(variant) == "rhs_ns", "RHS", as.character(variant))
}

add_model_labels <- function(x) {
  x$qdesn_likelihood <- ifelse(
    as.character(x$model_family) == "qdesn",
    extract_qdesn_likelihood(x$spec_id),
    NA_character_
  )
  x$model_key <- ifelse(
    as.character(x$model_family) == "exdqlm_dqlm",
    as.character(x$model_variant),
    paste("qdesn", x$qdesn_likelihood, as.character(x$model_variant), sep = "_")
  )
  x$model_label <- ifelse(
    x$model_key == "dqlm", "DQLM",
    ifelse(
      x$model_key == "exdqlm", "exDQLM",
      paste(
        ifelse(x$qdesn_likelihood == "al", "QDESN", "exQDESN"),
        qdesn_variant_label(x$model_variant)
      )
    )
  )
  if (any(as.character(x$model_family) == "qdesn" & is.na(x$qdesn_likelihood))) {
    stop("Could not parse QDESN/exQDESN likelihood from spec_id.", call. = FALSE)
  }
  x
}

first_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x)) x[[1L]] else NA_real_
}

weighted_mean <- function(x, w) {
  x <- as.numeric(x)
  w <- as.numeric(w)
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}

collapse_group <- function(block) {
  data.frame(
    model_family = block$model_family[[1L]],
    model_variant = block$model_variant[[1L]],
    qdesn_likelihood = block$qdesn_likelihood[[1L]],
    model_key = block$model_key[[1L]],
    model_label = block$model_label[[1L]],
    inference = block$inference[[1L]],
    inference_label = ifelse(block$inference[[1L]] == "vb", "VB--LD", "MCMC"),
    family = block$family[[1L]],
    tau = as.numeric(block$tau[[1L]]),
    fit_size = as.integer(block$fit_size[[1L]]),
    n_leads = length(unique(as.integer(block$forecast_lead))),
    n_origins_scored_total = sum(as.numeric(block$n_origins_scored), na.rm = TRUE),
    fit_qtrue_rmse = first_finite(block$fit_qtrue_rmse),
    fit_pinball_mean = first_finite(block$fit_pinball_mean),
    forecast_qtrue_mae_lead_weighted = weighted_mean(block$forecast_qtrue_mae, block$n_origins_scored),
    forecast_qtrue_rmse_lead_weighted = weighted_mean(block$forecast_qtrue_rmse, block$n_origins_scored),
    forecast_pinball_mean_lead_weighted = weighted_mean(block$forecast_pinball_mean, block$n_origins_scored),
    runtime_hours = first_finite(block$runtime_sec_total) / 3600,
    source_registry_hash_value = block$source_registry_hash_value[[1L]],
    validation_branch = block$validation_branch[[1L]],
    validation_commit = paste(sort(unique(block$validation_commit)), collapse = ";"),
    article_interface_ids = paste(sort(unique(block$article_interface_id)), collapse = ";"),
    article_interface_sha256 = paste(sort(unique(block$article_interface_sha256)), collapse = ";"),
    stringsAsFactors = FALSE
  )
}

as_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x[1L]))
  tolower(as.character(x)[1L]) %in% c("true", "t", "1", "yes")
}

as_bool_vec <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "t", "1", "yes")
}

verify_file_hash <- function(path, expected, label) {
  if (is.null(path) || !nzchar(as.character(path)[1L])) {
    stop(sprintf("%s path is missing.", label), call. = FALSE)
  }
  path <- normalizePath(as.character(path)[1L], winslash = "/", mustWork = TRUE)
  observed <- app_sha256_file(path)
  if (!identical(observed, as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
  path
}

cell_key <- function(family, tau, model_key, inference) {
  paste(as.character(family), sprintf("%.12g", as.numeric(tau)), as.character(model_key), as.character(inference), sep = "\r")
}

bind_rows_fill <- function(rows) {
  if (!length(rows)) return(data.frame())
  all_names <- unique(unlist(lapply(rows, names), use.names = FALSE))
  filled <- lapply(rows, function(x) {
    missing <- setdiff(all_names, names(x))
    for (nm in missing) x[[nm]] <- NA
    x[, all_names, drop = FALSE]
  })
  do.call(rbind, filled)
}

has_value <- function(x) {
  if (is.null(x) || !length(x)) return(FALSE)
  val <- x[[1L]]
  !is.na(val) && nzchar(as.character(val))
}

apply_summary_overrides <- function(summary_rows, config) {
  overrides <- config$summary_overrides
  if (is.null(overrides) || !length(overrides)) {
    attr(summary_rows, "applied_summary_overrides") <- data.frame()
    return(summary_rows)
  }

  applied <- list()
  for (override_id in names(overrides)) {
    spec <- overrides[[override_id]]
    if (!as_bool(spec$enabled %||% FALSE)) next
    override_type <- as.character(spec$override_type %||% "single_profile_dominance")

    if (identical(override_type, "exdqlm_dqlm_vb_current_best")) {
      required <- c(
        "interface_role", "validation_commit_at_export", "validation_audit_commit",
        "run_tag", "selected_candidate_id", "expected_cells",
        "expected_leads", "expected_origins_scored_total",
        "current_best_csv_path", "current_best_csv_sha256",
        "current_best_audit_path", "current_best_audit_sha256",
        "raw_interface_path", "raw_interface_sha256",
        "expected_model_variants", "expected_families", "expected_tau_values"
      )
      missing <- setdiff(required, names(spec))
      if (length(missing)) {
        stop(
          sprintf("Summary override '%s' is missing required field(s): %s", override_id, paste(missing, collapse = ", ")),
          call. = FALSE
        )
      }
      app_fail_on_disallowed_validation_text(spec, sprintf("summary override '%s'", override_id))

      current_best_path <- verify_file_hash(
        spec$current_best_csv_path,
        spec$current_best_csv_sha256,
        sprintf("summary override '%s' current-best CSV", override_id)
      )
      audit_path <- verify_file_hash(
        spec$current_best_audit_path,
        spec$current_best_audit_sha256,
        sprintf("summary override '%s' current-best audit", override_id)
      )
      raw_interface_path <- verify_file_hash(
        spec$raw_interface_path,
        spec$raw_interface_sha256,
        sprintf("summary override '%s' raw shared interface", override_id)
      )

      current_best <- app_read_csv(current_best_path)
      raw_interface <- app_read_csv(raw_interface_path)
      app_fail_on_disallowed_validation_text(current_best, sprintf("summary override '%s' current-best CSV", override_id))
      app_fail_on_disallowed_validation_text(raw_interface, sprintf("summary override '%s' raw shared interface", override_id))
      app_fail_on_disallowed_validation_text(
        readLines(audit_path, warn = FALSE),
        sprintf("summary override '%s' current-best audit", override_id)
      )

      current_required <- c(
        "model_variant", "family", "tau", "row_id", "candidate_id",
        "fit_qtrue_rmse", "fit_check", "forecast_qtrue_mae",
        "forecast_qtrue_rmse", "forecast_check", "n_leads",
        "n_origins_scored_total", "runtime_sec_total",
        "source_registry_hash_value", "validation_branch", "validation_commit",
        "run_tag", "package_version", "forecast_protocol",
        "state_update_method", "max_lead_configured", "origin_stride"
      )
      missing_current <- setdiff(current_required, names(current_best))
      if (length(missing_current)) {
        stop(
          sprintf("Summary override '%s' current-best CSV is missing column(s): %s", override_id, paste(missing_current, collapse = ", ")),
          call. = FALSE
        )
      }
      raw_required <- c(
        "candidate_id", "model_family", "model_variant", "inference",
        "fit_size", "status", "health_gate", "forecast_lead",
        "n_origins_scored", "family", "tau", "source_registry_hash_value",
        "validation_branch", "validation_commit", "run_tag",
        "package_version", "forecast_protocol", "max_lead_configured",
        "origin_stride"
      )
      missing_raw <- setdiff(raw_required, names(raw_interface))
      if (length(missing_raw)) {
        stop(
          sprintf("Summary override '%s' raw interface is missing column(s): %s", override_id, paste(missing_raw, collapse = ", ")),
          call. = FALSE
        )
      }

      expected_model_variants <- sort(as.character(unlist(spec$expected_model_variants, use.names = FALSE)))
      expected_families <- sort(as.character(unlist(spec$expected_families, use.names = FALSE)))
      expected_taus <- sort(as.numeric(unlist(spec$expected_tau_values, use.names = FALSE)))
      if (nrow(current_best) != as.integer(spec$expected_cells) ||
          !identical(sort(unique(as.character(current_best$model_variant))), expected_model_variants) ||
          !identical(sort(unique(as.character(current_best$family))), expected_families) ||
          !identical(sort(unique(as.numeric(current_best$tau))), expected_taus) ||
          any(as.character(current_best$candidate_id) != as.character(spec$selected_candidate_id)) ||
          any(as.integer(current_best$n_leads) != as.integer(spec$expected_leads)) ||
          any(as.integer(current_best$n_origins_scored_total) != as.integer(spec$expected_origins_scored_total)) ||
          any(as.character(current_best$source_registry_hash_value) != as.character(config$source_registry_hash_value)) ||
          any(as.character(current_best$validation_branch) != as.character(config$validation_branch)) ||
          any(as.character(current_best$validation_commit) != as.character(spec$validation_commit_at_export)) ||
          any(as.character(current_best$run_tag) != as.character(spec$run_tag)) ||
          any(as.character(current_best$package_version) != as.character(config$package_version)) ||
          any(as.character(current_best$forecast_protocol) != as.character(config$forecast_protocol)) ||
          any(as.integer(current_best$max_lead_configured) != as.integer(config$max_lead_configured)) ||
          any(as.integer(current_best$origin_stride) != as.integer(config$origin_stride))) {
        stop(sprintf("Summary override '%s' current-best CSV violates the active exDQLM/DQLM VB contract.", override_id), call. = FALSE)
      }
      metric_cols <- c("fit_qtrue_rmse", "fit_check", "forecast_qtrue_mae", "forecast_qtrue_rmse", "forecast_check", "runtime_sec_total")
      if (any(!is.finite(as.numeric(unlist(current_best[metric_cols], use.names = FALSE))))) {
        stop(sprintf("Summary override '%s' current-best CSV contains non-finite displayed metrics.", override_id), call. = FALSE)
      }

      raw_selected <- raw_interface[
        as.character(raw_interface$candidate_id) == as.character(spec$selected_candidate_id) &
          as.character(raw_interface$model_family) == "exdqlm_dqlm" &
          as.character(raw_interface$inference) == "vb" &
          as.integer(raw_interface$fit_size) == as.integer(config$fit_size) &
          as.character(raw_interface$status) == "done" &
          as.character(raw_interface$health_gate) == "PASS",
        ,
        drop = FALSE
      ]
      if (nrow(raw_selected) != as.integer(spec$expected_cells) * as.integer(spec$expected_leads) ||
          any(as.character(raw_selected$source_registry_hash_value) != as.character(config$source_registry_hash_value)) ||
          any(as.character(raw_selected$validation_branch) != as.character(config$validation_branch)) ||
          any(as.character(raw_selected$validation_commit) != as.character(spec$validation_commit_at_export)) ||
          any(as.character(raw_selected$run_tag) != as.character(spec$run_tag)) ||
          any(as.character(raw_selected$package_version) != as.character(config$package_version)) ||
          any(as.character(raw_selected$forecast_protocol) != as.character(config$forecast_protocol)) ||
          any(as.integer(raw_selected$max_lead_configured) != as.integer(config$max_lead_configured)) ||
          any(as.integer(raw_selected$origin_stride) != as.integer(config$origin_stride))) {
        stop(sprintf("Summary override '%s' raw shared interface does not support the current-best CSV.", override_id), call. = FALSE)
      }
      raw_key <- paste(raw_selected$model_variant, raw_selected$family, raw_selected$tau, sep = "\r")
      for (kk in unique(raw_key)) {
        leads <- sort(unique(as.integer(raw_selected$forecast_lead[raw_key == kk])))
        if (!identical(leads, seq_len(as.integer(spec$expected_leads)))) {
          stop(sprintf("Summary override '%s' raw interface is missing a complete lead grid.", override_id), call. = FALSE)
        }
      }

      seen <- character()
      for (ii in seq_len(nrow(current_best))) {
        repl <- current_best[ii, , drop = FALSE]
        model_key <- as.character(repl$model_variant[[1L]])
        key <- cell_key(repl$family[[1L]], repl$tau[[1L]], model_key, "vb")
        if (key %in% seen) {
          stop(sprintf("Summary override '%s' contains duplicate current-best replacement keys.", override_id), call. = FALSE)
        }
        seen <- c(seen, key)

        row_idx <- which(
          summary_rows$model_family == "exdqlm_dqlm" &
            summary_rows$family == as.character(repl$family[[1L]]) &
            abs(as.numeric(summary_rows$tau) - as.numeric(repl$tau[[1L]])) < 1.0e-12 &
            summary_rows$model_key == model_key &
            summary_rows$inference == "vb"
        )
        if (length(row_idx) != 1L) {
          stop(sprintf("Summary override '%s' replacement did not identify exactly one exDQLM/DQLM VB article row.", override_id), call. = FALSE)
        }

        original <- summary_rows[row_idx, , drop = FALSE]
        summary_rows$fit_qtrue_rmse[[row_idx]] <- as.numeric(repl$fit_qtrue_rmse[[1L]])
        summary_rows$fit_pinball_mean[[row_idx]] <- as.numeric(repl$fit_check[[1L]])
        summary_rows$forecast_qtrue_mae_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_qtrue_mae[[1L]])
        summary_rows$forecast_qtrue_rmse_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_qtrue_rmse[[1L]])
        summary_rows$forecast_pinball_mean_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_check[[1L]])
        summary_rows$runtime_hours[[row_idx]] <- as.numeric(repl$runtime_sec_total[[1L]]) / 3600
        summary_rows$n_leads[[row_idx]] <- as.integer(repl$n_leads[[1L]])
        summary_rows$n_origins_scored_total[[row_idx]] <- as.integer(repl$n_origins_scored_total[[1L]])
        summary_rows$validation_commit[[row_idx]] <- as.character(spec$validation_commit_at_export)
        summary_rows$article_interface_ids[[row_idx]] <- override_id
        summary_rows$article_interface_sha256[[row_idx]] <- paste(
          c(spec$current_best_csv_sha256, spec$current_best_audit_sha256, spec$raw_interface_sha256),
          collapse = ";"
        )

        applied[[length(applied) + 1L]] <- data.frame(
          override_id = override_id,
          family = as.character(repl$family[[1L]]),
          tau = as.numeric(repl$tau[[1L]]),
          model_key = model_key,
          inference = "vb",
          profile = as.character(repl$candidate_id[[1L]]),
          original_forecast_mae = as.numeric(original$forecast_qtrue_mae_lead_weighted[[1L]]),
          replacement_forecast_mae = as.numeric(repl$forecast_qtrue_mae[[1L]]),
          original_forecast_pinball = as.numeric(original$forecast_pinball_mean_lead_weighted[[1L]]),
          replacement_forecast_pinball = as.numeric(repl$forecast_check[[1L]]),
          replacement_fit_rmse = as.numeric(repl$fit_qtrue_rmse[[1L]]),
          replacement_fit_pinball = as.numeric(repl$fit_check[[1L]]),
          replacement_runtime_sec = as.numeric(repl$runtime_sec_total[[1L]]),
          report_root = dirname(current_best_path),
          evidence_source = override_type,
          current_best_csv_path = current_best_path,
          current_best_csv_sha256 = as.character(spec$current_best_csv_sha256),
          current_best_audit_path = audit_path,
          current_best_audit_sha256 = as.character(spec$current_best_audit_sha256),
          raw_interface_path = raw_interface_path,
          raw_interface_sha256 = as.character(spec$raw_interface_sha256),
          source_run_tag = as.character(spec$run_tag),
          diagnostic_qualification = "current_best_vb_summary",
          replacement_signoff_grade = "PASS",
          replacement_signoff_reason = "done/PASS current-best c13 VB evidence",
          stringsAsFactors = FALSE
        )
      }
      next
    }

    if (identical(override_type, "exdqlm_dqlm_mcmc_current_best")) {
      required <- c(
        "interface_role", "validation_commit_at_export", "validation_run_commit",
        "run_tag", "promotion_id", "promotion_status",
        "diagnostic_qualification", "selected_candidate_id",
        "expected_cells", "expected_leads", "expected_origins_scored_total",
        "promotion_summary_path", "promotion_summary_sha256",
        "promotion_manifest_path", "promotion_manifest_sha256",
        "promotion_sources_path", "promotion_sources_sha256",
        "expected_model_variants", "expected_families", "expected_tau_values"
      )
      missing <- setdiff(required, names(spec))
      if (length(missing)) {
        stop(
          sprintf("Summary override '%s' is missing required field(s): %s", override_id, paste(missing, collapse = ", ")),
          call. = FALSE
        )
      }
      app_fail_on_disallowed_validation_text(spec, sprintf("summary override '%s'", override_id))

      promotion_summary_path <- verify_file_hash(
        spec$promotion_summary_path,
        spec$promotion_summary_sha256,
        sprintf("summary override '%s' promotion summary", override_id)
      )
      promotion_manifest_path <- verify_file_hash(
        spec$promotion_manifest_path,
        spec$promotion_manifest_sha256,
        sprintf("summary override '%s' promotion manifest", override_id)
      )
      promotion_sources_path <- verify_file_hash(
        spec$promotion_sources_path,
        spec$promotion_sources_sha256,
        sprintf("summary override '%s' promotion source ledger", override_id)
      )
      promotion <- app_read_csv(promotion_summary_path)
      sources <- app_read_csv(promotion_sources_path)
      app_fail_on_disallowed_validation_text(promotion, sprintf("summary override '%s' promotion summary", override_id))
      app_fail_on_disallowed_validation_text(sources, sprintf("summary override '%s' promotion source ledger", override_id))
      app_fail_on_disallowed_validation_text(
        readLines(promotion_manifest_path, warn = FALSE),
        sprintf("summary override '%s' promotion manifest", override_id)
      )

      manifest <- jsonlite::fromJSON(promotion_manifest_path, simplifyVector = FALSE)
      expected_lead_rows <- as.integer(spec$expected_cells) * as.integer(spec$expected_leads)
      if (!identical(as.character(manifest$promotion_id), as.character(spec$promotion_id)) ||
          !identical(as.character(manifest$promotion_status), as.character(spec$promotion_status)) ||
          !identical(as.character(manifest$validation_branch), as.character(config$validation_branch)) ||
          !identical(as.character(manifest$validation_commit_at_materialization), as.character(spec$validation_commit_at_export)) ||
          !identical(as.character(manifest$run_tag), as.character(spec$run_tag)) ||
          !identical(as.character(manifest$candidate_id), as.character(spec$selected_candidate_id)) ||
          !identical(as.integer(manifest$expected_cells), as.integer(spec$expected_cells)) ||
          !identical(as.integer(manifest$observed_cells), as.integer(spec$expected_cells)) ||
          !identical(as.integer(manifest$expected_lead_rows), expected_lead_rows) ||
          !identical(as.integer(manifest$observed_lead_rows), expected_lead_rows) ||
          !identical(as.character(manifest$source_registry_hash_value), as.character(config$source_registry_hash_value)) ||
          !identical(as.character(manifest$summary_sha256), as.character(spec$promotion_summary_sha256)) ||
          !identical(as.character(manifest$sources_sha256), as.character(spec$promotion_sources_sha256))) {
        stop(sprintf("Summary override '%s' promotion manifest violates the configured identity or hash contract.", override_id), call. = FALSE)
      }

      source_required <- c("source_id", "path", "sha256")
      missing_sources <- setdiff(source_required, names(sources))
      if (length(missing_sources)) {
        stop(
          sprintf("Summary override '%s' promotion source ledger is missing column(s): %s", override_id, paste(missing_sources, collapse = ", ")),
          call. = FALSE
        )
      }
      expected_source_ids <- c("row_manifest", "shared_interface", "source_registry", "runtime_metadata")
      if (!identical(sort(as.character(sources$source_id)), sort(expected_source_ids)) ||
          any(grepl("/home/jaguir26/local/src", as.character(sources$path), fixed = TRUE))) {
        stop(sprintf("Summary override '%s' promotion source ledger violates the path/source-id contract.", override_id), call. = FALSE)
      }

      promotion_required <- c(
        "promotion_id", "promotion_status", "diagnostic_qualification",
        "model_family", "model_variant", "model_key", "inference",
        "method", "family", "tau", "fit_size", "effective_fit_size",
        "candidate_id", "calibration_id", "status", "health_gate",
        "signoff_grade", "comparison_eligible", "fit_qtrue_rmse",
        "fit_check_loss", "forecast_qtrue_mae_lead_weighted",
        "forecast_qtrue_rmse_lead_weighted",
        "forecast_check_loss_lead_weighted", "runtime_sec_total",
        "runtime_hours", "n_leads", "n_origins_scored_total",
        "max_lead_configured", "origin_stride", "forecast_protocol",
        "state_update_method", "train_start_source_index",
        "train_end_source_index", "forecast_origin_source_index",
        "forecast_block_start_source_index",
        "forecast_block_end_source_index", "source_registry_hash_name",
        "source_registry_hash_value", "validation_branch",
        "validation_commit_at_materialization", "validation_run_commit",
        "package_version", "run_tag"
      )
      missing_promotion <- setdiff(promotion_required, names(promotion))
      if (length(missing_promotion)) {
        stop(
          sprintf("Summary override '%s' promotion summary is missing column(s): %s", override_id, paste(missing_promotion, collapse = ", ")),
          call. = FALSE
        )
      }
      expected_model_variants <- sort(as.character(unlist(spec$expected_model_variants, use.names = FALSE)))
      expected_families <- sort(as.character(unlist(spec$expected_families, use.names = FALSE)))
      expected_taus <- sort(as.numeric(unlist(spec$expected_tau_values, use.names = FALSE)))
      expected_source_registry_hash_names <- as.character(unlist(
        spec$expected_source_registry_hash_names %||% config$source_registry_hash_name,
        use.names = FALSE
      ))
      if (nrow(promotion) != as.integer(spec$expected_cells) ||
          !identical(sort(unique(as.character(promotion$model_variant))), expected_model_variants) ||
          !identical(sort(unique(as.character(promotion$family))), expected_families) ||
          !identical(sort(unique(as.numeric(promotion$tau))), expected_taus) ||
          any(as.character(promotion$promotion_id) != as.character(spec$promotion_id)) ||
          any(as.character(promotion$promotion_status) != as.character(spec$promotion_status)) ||
          any(as.character(promotion$diagnostic_qualification) != as.character(spec$diagnostic_qualification)) ||
          any(as.character(promotion$model_family) != "exdqlm_dqlm") ||
          any(as.character(promotion$inference) != "mcmc") ||
          any(as.character(promotion$method) != "mcmc") ||
          any(as.integer(promotion$fit_size) != as.integer(config$fit_size)) ||
          any(as.integer(promotion$effective_fit_size) != as.integer(config$fit_size)) ||
          any(as.character(promotion$candidate_id) != as.character(spec$selected_candidate_id)) ||
          any(as.character(promotion$status) != "done") ||
          any(as.character(promotion$health_gate) != "PASS") ||
          any(!as_bool_vec(promotion$comparison_eligible)) ||
          any(as.integer(promotion$n_leads) != as.integer(spec$expected_leads)) ||
          any(as.integer(promotion$n_origins_scored_total) != as.integer(spec$expected_origins_scored_total)) ||
          any(as.integer(promotion$max_lead_configured) != as.integer(config$max_lead_configured)) ||
          any(as.integer(promotion$origin_stride) != as.integer(config$origin_stride)) ||
          any(as.character(promotion$forecast_protocol) != as.character(config$forecast_protocol)) ||
          any(as.integer(promotion$train_start_source_index) != as.integer(config$train_start_source_index)) ||
          any(as.integer(promotion$train_end_source_index) != as.integer(config$train_end_source_index)) ||
          any(as.integer(promotion$forecast_origin_source_index) != as.integer(config$forecast_origin_source_index)) ||
          any(as.integer(promotion$forecast_block_start_source_index) != as.integer(config$forecast_block_start_source_index)) ||
          any(as.integer(promotion$forecast_block_end_source_index) != as.integer(config$forecast_block_end_source_index)) ||
          any(!(as.character(promotion$source_registry_hash_name) %in% expected_source_registry_hash_names)) ||
          any(as.character(promotion$source_registry_hash_value) != as.character(config$source_registry_hash_value)) ||
          any(as.character(promotion$validation_branch) != as.character(config$validation_branch)) ||
          any(as.character(promotion$validation_commit_at_materialization) != as.character(spec$validation_commit_at_export)) ||
          any(as.character(promotion$validation_run_commit) != as.character(spec$validation_run_commit)) ||
          any(as.character(promotion$package_version) != as.character(config$package_version)) ||
          any(as.character(promotion$run_tag) != as.character(spec$run_tag))) {
        stop(sprintf("Summary override '%s' promotion summary violates the active exDQLM/DQLM MCMC contract.", override_id), call. = FALSE)
      }
      invalid_run_tags <- as.character(unlist(spec$invalid_run_tags %||% character(), use.names = FALSE))
      if (length(invalid_run_tags) &&
          any(as.character(promotion$run_tag) %in% invalid_run_tags)) {
        stop(sprintf("Summary override '%s' points at an invalid or superseded run tag.", override_id), call. = FALSE)
      }
      metric_cols <- c(
        "fit_qtrue_rmse", "fit_check_loss",
        "forecast_qtrue_mae_lead_weighted",
        "forecast_qtrue_rmse_lead_weighted",
        "forecast_check_loss_lead_weighted", "runtime_sec_total",
        "runtime_hours"
      )
      if (any(!is.finite(as.numeric(unlist(promotion[metric_cols], use.names = FALSE))))) {
        stop(sprintf("Summary override '%s' promotion summary contains non-finite displayed metrics.", override_id), call. = FALSE)
      }

      seen <- character()
      for (ii in seq_len(nrow(promotion))) {
        repl <- promotion[ii, , drop = FALSE]
        article_model_key <- as.character(repl$model_variant[[1L]])
        key <- cell_key(repl$family[[1L]], repl$tau[[1L]], article_model_key, repl$inference[[1L]])
        if (key %in% seen) {
          stop(sprintf("Summary override '%s' contains duplicate promotion keys.", override_id), call. = FALSE)
        }
        seen <- c(seen, key)

        row_idx <- which(
          summary_rows$model_family == "exdqlm_dqlm" &
            summary_rows$family == as.character(repl$family[[1L]]) &
            abs(as.numeric(summary_rows$tau) - as.numeric(repl$tau[[1L]])) < 1.0e-12 &
            summary_rows$model_key == article_model_key &
            summary_rows$inference == "mcmc"
        )
        if (length(row_idx) != 1L) {
          stop(sprintf("Summary override '%s' replacement did not identify exactly one exDQLM/DQLM MCMC article row.", override_id), call. = FALSE)
        }

        original <- summary_rows[row_idx, , drop = FALSE]
        summary_rows$fit_qtrue_rmse[[row_idx]] <- as.numeric(repl$fit_qtrue_rmse[[1L]])
        summary_rows$fit_pinball_mean[[row_idx]] <- as.numeric(repl$fit_check_loss[[1L]])
        summary_rows$forecast_qtrue_mae_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_qtrue_mae_lead_weighted[[1L]])
        summary_rows$forecast_qtrue_rmse_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_qtrue_rmse_lead_weighted[[1L]])
        summary_rows$forecast_pinball_mean_lead_weighted[[row_idx]] <- as.numeric(repl$forecast_check_loss_lead_weighted[[1L]])
        summary_rows$runtime_hours[[row_idx]] <- as.numeric(repl$runtime_hours[[1L]])
        summary_rows$n_leads[[row_idx]] <- as.integer(repl$n_leads[[1L]])
        summary_rows$n_origins_scored_total[[row_idx]] <- as.integer(repl$n_origins_scored_total[[1L]])
        summary_rows$validation_commit[[row_idx]] <- as.character(spec$validation_commit_at_export)
        summary_rows$article_interface_ids[[row_idx]] <- override_id
        summary_rows$article_interface_sha256[[row_idx]] <- paste(
          c(spec$promotion_summary_sha256, spec$promotion_manifest_sha256, spec$promotion_sources_sha256),
          collapse = ";"
        )

        applied[[length(applied) + 1L]] <- data.frame(
          override_id = override_id,
          family = as.character(repl$family[[1L]]),
          tau = as.numeric(repl$tau[[1L]]),
          model_key = article_model_key,
          inference = "mcmc",
          profile = as.character(repl$candidate_id[[1L]]),
          original_forecast_mae = as.numeric(original$forecast_qtrue_mae_lead_weighted[[1L]]),
          replacement_forecast_mae = as.numeric(repl$forecast_qtrue_mae_lead_weighted[[1L]]),
          original_forecast_pinball = as.numeric(original$forecast_pinball_mean_lead_weighted[[1L]]),
          replacement_forecast_pinball = as.numeric(repl$forecast_check_loss_lead_weighted[[1L]]),
          replacement_fit_rmse = as.numeric(repl$fit_qtrue_rmse[[1L]]),
          replacement_fit_pinball = as.numeric(repl$fit_check_loss[[1L]]),
          replacement_runtime_sec = as.numeric(repl$runtime_sec_total[[1L]]),
          report_root = dirname(promotion_summary_path),
          evidence_source = override_type,
          promotion_summary_path = promotion_summary_path,
          promotion_summary_sha256 = as.character(spec$promotion_summary_sha256),
          promotion_manifest_path = promotion_manifest_path,
          promotion_manifest_sha256 = as.character(spec$promotion_manifest_sha256),
          promotion_sources_path = promotion_sources_path,
          promotion_sources_sha256 = as.character(spec$promotion_sources_sha256),
          source_selection = as.character(repl$calibration_id[[1L]]),
          source_run_tag = as.character(repl$run_tag[[1L]]),
          diagnostic_qualification = as.character(repl$diagnostic_qualification[[1L]]),
          replacement_signoff_grade = as.character(repl$health_gate[[1L]]),
          replacement_signoff_reason = "done/PASS promoted c13 MCMC evidence",
          stringsAsFactors = FALSE
        )
      }
      next
    }

    if (identical(override_type, "candidate_ledger")) {
      required <- c(
        "interface_role", "validation_commit_at_export", "run_tag",
        "candidate_ledger_path", "candidate_ledger_sha256",
        "candidate_ledger_manifest_path", "candidate_ledger_manifest_sha256",
        "stage_sources", "replacements"
      )
      missing <- setdiff(required, names(spec))
      if (length(missing)) {
        stop(
          sprintf("Summary override '%s' is missing required field(s): %s", override_id, paste(missing, collapse = ", ")),
          call. = FALSE
        )
      }
      app_fail_on_disallowed_validation_text(spec, sprintf("summary override '%s'", override_id))

      ledger_path <- verify_file_hash(
        spec$candidate_ledger_path,
        spec$candidate_ledger_sha256,
        sprintf("summary override '%s' candidate ledger", override_id)
      )
      ledger_manifest_path <- verify_file_hash(
        spec$candidate_ledger_manifest_path,
        spec$candidate_ledger_manifest_sha256,
        sprintf("summary override '%s' candidate ledger manifest", override_id)
      )
      ledger <- app_read_csv(ledger_path)
      app_fail_on_disallowed_validation_text(ledger, sprintf("summary override '%s' candidate ledger", override_id))
      app_fail_on_disallowed_validation_text(
        readLines(ledger_manifest_path, warn = FALSE),
        sprintf("summary override '%s' candidate ledger manifest", override_id)
      )

      ledger_required <- c(
        "family", "tau", "stage", "screening_profile_base",
        "beats_all_primary_baselines", "worst_metric_ratio",
        "forecast_mae_ratio_vs_best_vb_baseline",
        "forecast_pinball_ratio_vs_best_vb_baseline",
        "fit_rmse_ratio_vs_best_vb_baseline",
        "fit_pinball_ratio_vs_best_vb_baseline",
        "stage_strict_ready", "stage_n_fail",
        "stage_forbidden_binary_count_total", "stage_report_root",
        "stage_cell_summary_path", "stage_cell_summary_sha256",
        "stage_strict_audit_path", "stage_strict_audit_sha256"
      )
      missing_ledger <- setdiff(ledger_required, names(ledger))
      if (length(missing_ledger)) {
        stop(
          sprintf("Summary override '%s' candidate ledger is missing column(s): %s", override_id, paste(missing_ledger, collapse = ", ")),
          call. = FALSE
        )
      }
      ratio_cols <- c(
        "forecast_mae_ratio_vs_best_vb_baseline",
        "forecast_pinball_ratio_vs_best_vb_baseline",
        "fit_rmse_ratio_vs_best_vb_baseline",
        "fit_pinball_ratio_vs_best_vb_baseline"
      )
      if (!all(as_bool_vec(ledger$beats_all_primary_baselines)) ||
          !all(as_bool_vec(ledger$stage_strict_ready)) ||
          any(as.integer(ledger$stage_n_fail) != 0L) ||
          any(as.integer(ledger$stage_forbidden_binary_count_total) != 0L) ||
          any(!is.finite(as.numeric(unlist(ledger[ratio_cols], use.names = FALSE)))) ||
          any(as.numeric(unlist(ledger[ratio_cols], use.names = FALSE)) >= 1)) {
        stop(sprintf("Summary override '%s' candidate ledger does not clear the dominance/storage gates.", override_id), call. = FALSE)
      }
      accepted_signoff_grades <- as.character(unlist(spec$accepted_signoff_grades %||% "PASS", use.names = FALSE))

      stage_cache <- new.env(parent = emptyenv())
      load_stage_source <- function(stage) {
        stage <- as.character(stage)[[1L]]
        if (exists(stage, envir = stage_cache, inherits = FALSE)) {
          return(get(stage, envir = stage_cache, inherits = FALSE))
        }
        stage_spec <- spec$stage_sources[[stage]]
        if (is.null(stage_spec)) {
          stop(sprintf("Summary override '%s' has no stage source for '%s'.", override_id, stage), call. = FALSE)
        }
        source_required <- c(
          "report_root",
          "fit_forecast_summary_path", "fit_forecast_summary_sha256",
          "dominance_cell_summary_path", "dominance_cell_summary_sha256",
          "dominance_profile_ranking_path", "dominance_profile_ranking_sha256",
          "audit_summary_path", "audit_summary_sha256"
        )
        missing_source <- setdiff(source_required, names(stage_spec))
        if (length(missing_source)) {
          stop(
            sprintf("Summary override '%s' stage source '%s' is missing field(s): %s", override_id, stage, paste(missing_source, collapse = ", ")),
            call. = FALSE
          )
        }
        fit_path <- verify_file_hash(
          stage_spec$fit_forecast_summary_path,
          stage_spec$fit_forecast_summary_sha256,
          sprintf("summary override '%s' stage '%s' fit/forecast summary", override_id, stage)
        )
        cell_path <- verify_file_hash(
          stage_spec$dominance_cell_summary_path,
          stage_spec$dominance_cell_summary_sha256,
          sprintf("summary override '%s' stage '%s' dominance cell summary", override_id, stage)
        )
        rank_path <- verify_file_hash(
          stage_spec$dominance_profile_ranking_path,
          stage_spec$dominance_profile_ranking_sha256,
          sprintf("summary override '%s' stage '%s' dominance profile ranking", override_id, stage)
        )
        audit_path <- verify_file_hash(
          stage_spec$audit_summary_path,
          stage_spec$audit_summary_sha256,
          sprintf("summary override '%s' stage '%s' audit summary", override_id, stage)
        )
        fit <- app_read_csv(fit_path)
        cell <- app_read_csv(cell_path)
        rank <- app_read_csv(rank_path)
        audit <- app_read_csv(audit_path)
        app_fail_on_disallowed_validation_text(fit, sprintf("summary override '%s' stage '%s' fit/forecast summary", override_id, stage))
        app_fail_on_disallowed_validation_text(cell, sprintf("summary override '%s' stage '%s' dominance cell summary", override_id, stage))
        app_fail_on_disallowed_validation_text(rank, sprintf("summary override '%s' stage '%s' dominance ranking", override_id, stage))
        app_fail_on_disallowed_validation_text(audit, sprintf("summary override '%s' stage '%s' audit summary", override_id, stage))
        if (nrow(audit) != 1L || !isTRUE(as_bool(audit$strict_ready[[1L]])) ||
            as.integer(audit$n_success[[1L]]) != as.integer(audit$expected_roots[[1L]]) ||
            as.integer(audit$n_fail[[1L]]) != 0L ||
            as.integer(audit$forbidden_binary_count_total[[1L]]) != 0L) {
          stop(sprintf("Summary override '%s' stage '%s' audit is not strict-ready and storage-light.", override_id, stage), call. = FALSE)
        }
        out <- list(
          report_root = as.character(stage_spec$report_root),
          fit = fit,
          cell = cell,
          rank = rank,
          audit = audit,
          fit_path = fit_path,
          fit_sha256 = as.character(stage_spec$fit_forecast_summary_sha256),
          cell_path = cell_path,
          cell_sha256 = as.character(stage_spec$dominance_cell_summary_sha256),
          audit_path = audit_path,
          audit_sha256 = as.character(stage_spec$audit_summary_sha256)
        )
        assign(stage, out, envir = stage_cache)
        out
      }

      replacements <- spec$replacements
      if (!is.list(replacements) || !length(replacements)) {
        stop(sprintf("Summary override '%s' declares no replacements.", override_id), call. = FALSE)
      }
      seen <- character()
      for (ii in seq_along(replacements)) {
        repl <- replacements[[ii]]
        repl_required <- c("family", "tau", "model_key", "inference", "profile")
        missing_repl <- setdiff(repl_required, names(repl))
        if (length(missing_repl)) {
          stop(
            sprintf("Summary override '%s' replacement %d is missing field(s): %s", override_id, ii, paste(missing_repl, collapse = ", ")),
            call. = FALSE
          )
        }
        key <- cell_key(repl$family, repl$tau, repl$model_key, repl$inference)
        if (key %in% seen) {
          stop(sprintf("Summary override '%s' contains duplicate replacement keys.", override_id), call. = FALSE)
        }
        seen <- c(seen, key)

        row_idx <- which(
          summary_rows$family == as.character(repl$family) &
            abs(as.numeric(summary_rows$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            summary_rows$model_key == as.character(repl$model_key) &
            summary_rows$inference == as.character(repl$inference)
        )
        if (length(row_idx) != 1L) {
          stop(sprintf("Summary override '%s' replacement did not identify exactly one article row.", override_id), call. = FALSE)
        }

        ledger_row <- ledger[
          as.character(ledger$family) == as.character(repl$family) &
            abs(as.numeric(ledger$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            as.character(ledger$screening_profile_base) == as.character(repl$profile),
          , drop = FALSE
        ]
        if (nrow(ledger_row) != 1L) {
          stop(sprintf("Summary override '%s' replacement did not identify exactly one candidate-ledger row.", override_id), call. = FALSE)
        }
        if (!is.null(repl$stage) &&
            !identical(as.character(ledger_row$stage[[1L]]), as.character(repl$stage))) {
          stop(sprintf("Summary override '%s' replacement stage does not match the candidate ledger.", override_id), call. = FALSE)
        }
        stage_source <- load_stage_source(ledger_row$stage[[1L]])
        if (!identical(normalizePath(ledger_row$stage_cell_summary_path[[1L]], winslash = "/", mustWork = TRUE), stage_source$cell_path) ||
            !identical(as.character(ledger_row$stage_cell_summary_sha256[[1L]]), stage_source$cell_sha256) ||
            !identical(normalizePath(ledger_row$stage_strict_audit_path[[1L]], winslash = "/", mustWork = TRUE), stage_source$audit_path) ||
            !identical(as.character(ledger_row$stage_strict_audit_sha256[[1L]]), stage_source$audit_sha256)) {
          stop(sprintf("Summary override '%s' candidate ledger does not match the pinned stage source.", override_id), call. = FALSE)
        }

        cell <- stage_source$cell
        fit <- stage_source$fit
        cell_row <- cell[
          as.character(cell$family) == as.character(repl$family) &
            abs(as.numeric(cell$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            as.character(cell$screening_profile_base) == as.character(repl$profile),
          , drop = FALSE
        ]
        fit_row <- fit[
          as.character(fit$family) == as.character(repl$family) &
            abs(as.numeric(fit$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            as.character(fit$screening_profile_base) == as.character(repl$profile),
          , drop = FALSE
        ]
        if (nrow(cell_row) != 1L || nrow(fit_row) != 1L) {
          stop(sprintf("Summary override '%s' replacement source row is not unique.", override_id), call. = FALSE)
        }
        if (!isTRUE(as_bool(cell_row$beats_all_primary_baselines[[1L]]))) {
          stop(sprintf("Summary override '%s' replacement source does not beat all primary baselines.", override_id), call. = FALSE)
        }
        if (as.character(fit_row$status[[1L]]) != "SUCCESS" ||
            !(as.character(fit_row$signoff_grade[[1L]]) %in% accepted_signoff_grades) ||
            !isTRUE(as_bool(fit_row$finite_ok[[1L]])) ||
            !isTRUE(as_bool(fit_row$domain_ok[[1L]])) ||
            !isTRUE(as_bool(fit_row$comparison_eligible[[1L]])) ||
            as.character(fit_row$inference[[1L]]) != "vb" ||
            as.character(fit_row$likelihood_family[[1L]]) != "exal" ||
            as.character(fit_row$prior[[1L]]) != "rhs_ns" ||
            as.integer(fit_row$fit_size[[1L]]) != as.integer(config$fit_size) ||
            as.integer(fit_row$forecast_max_lead_configured[[1L]]) != as.integer(config$max_lead_configured) ||
            as.integer(fit_row$forecast_origin_stride[[1L]]) != as.integer(config$origin_stride)) {
          stop(sprintf("Summary override '%s' replacement source violates the active TT500 VB exAL RHS contract.", override_id), call. = FALSE)
        }

        original <- summary_rows[row_idx, , drop = FALSE]
        summary_rows$fit_qtrue_rmse[[row_idx]] <- as.numeric(cell_row$qdesn_fit_rmse_mean[[1L]])
        summary_rows$fit_pinball_mean[[row_idx]] <- as.numeric(cell_row$qdesn_fit_pinball_mean[[1L]])
        summary_rows$forecast_qtrue_mae_lead_weighted[[row_idx]] <- as.numeric(cell_row$qdesn_forecast_mae_mean[[1L]])
        summary_rows$forecast_qtrue_rmse_lead_weighted[[row_idx]] <- as.numeric(fit_row$forecast_all_qtrue_rmse[[1L]])
        summary_rows$forecast_pinball_mean_lead_weighted[[row_idx]] <- as.numeric(cell_row$qdesn_forecast_pinball_mean[[1L]])
        summary_rows$runtime_hours[[row_idx]] <- as.numeric(cell_row$qdesn_runtime_sec_mean[[1L]]) / 3600
        summary_rows$n_leads[[row_idx]] <- as.integer(fit_row$forecast_lead_metrics_rows[[1L]])
        summary_rows$n_origins_scored_total[[row_idx]] <- as.integer(fit_row$forecast_all_origin_scores[[1L]])
        summary_rows$validation_commit[[row_idx]] <- as.character(spec$validation_commit_at_export)
        summary_rows$article_interface_ids[[row_idx]] <- override_id
        summary_rows$article_interface_sha256[[row_idx]] <- paste(
          c(
            spec$candidate_ledger_sha256,
            stage_source$fit_sha256,
            stage_source$cell_sha256,
            stage_source$audit_sha256
          ),
          collapse = ";"
        )

        applied[[length(applied) + 1L]] <- data.frame(
          override_id = override_id,
          family = as.character(repl$family),
          tau = as.numeric(repl$tau),
          model_key = as.character(repl$model_key),
          inference = as.character(repl$inference),
          profile = as.character(repl$profile),
          original_forecast_mae = as.numeric(original$forecast_qtrue_mae_lead_weighted[[1L]]),
          replacement_forecast_mae = as.numeric(cell_row$qdesn_forecast_mae_mean[[1L]]),
          original_forecast_pinball = as.numeric(original$forecast_pinball_mean_lead_weighted[[1L]]),
          replacement_forecast_pinball = as.numeric(cell_row$qdesn_forecast_pinball_mean[[1L]]),
          replacement_fit_rmse = as.numeric(cell_row$qdesn_fit_rmse_mean[[1L]]),
          replacement_fit_pinball = as.numeric(cell_row$qdesn_fit_pinball_mean[[1L]]),
          replacement_runtime_sec = as.numeric(cell_row$qdesn_runtime_sec_mean[[1L]]),
          report_root = stage_source$report_root,
          evidence_source = "candidate_ledger",
          candidate_ledger_path = ledger_path,
          candidate_ledger_sha256 = as.character(spec$candidate_ledger_sha256),
          stage = as.character(ledger_row$stage[[1L]]),
          replacement_signoff_grade = as.character(fit_row$signoff_grade[[1L]]),
          replacement_signoff_reason = as.character(fit_row$signoff_reason[[1L]]),
          stringsAsFactors = FALSE
        )
      }
      next
    }

    if (identical(override_type, "mcmc_authoritative_handoff") ||
        identical(override_type, "promotion_handoff")) {
      required <- c(
        "interface_role", "validation_commit_at_export", "run_tag",
        "promotion_id", "diagnostic_qualification",
        "promotion_summary_path", "promotion_summary_sha256",
        "promotion_manifest_path", "promotion_manifest_sha256",
        "accepted_signoff_grades", "replacements"
      )
      missing <- setdiff(required, names(spec))
      if (length(missing)) {
        stop(
          sprintf("Summary override '%s' is missing required field(s): %s", override_id, paste(missing, collapse = ", ")),
          call. = FALSE
        )
      }
      app_fail_on_disallowed_validation_text(spec, sprintf("summary override '%s'", override_id))

      promotion_summary_path <- verify_file_hash(
        spec$promotion_summary_path,
        spec$promotion_summary_sha256,
        sprintf("summary override '%s' MCMC promotion summary", override_id)
      )
      promotion_manifest_path <- verify_file_hash(
        spec$promotion_manifest_path,
        spec$promotion_manifest_sha256,
        sprintf("summary override '%s' MCMC promotion manifest", override_id)
      )
      promotion <- app_read_csv(promotion_summary_path)
      app_fail_on_disallowed_validation_text(promotion, sprintf("summary override '%s' MCMC promotion summary", override_id))
      app_fail_on_disallowed_validation_text(
        readLines(promotion_manifest_path, warn = FALSE),
        sprintf("summary override '%s' MCMC promotion manifest", override_id)
      )
      manifest <- jsonlite::fromJSON(promotion_manifest_path, simplifyVector = FALSE)
      if (!identical(as.character(manifest$promotion_id), as.character(spec$promotion_id)) ||
          !identical(as.character(manifest$diagnostic_qualification), as.character(spec$diagnostic_qualification))) {
        stop(sprintf("Summary override '%s' promotion manifest does not match the configured promotion identity.", override_id), call. = FALSE)
      }
      if (!identical(as.character(manifest$artifacts$summary_csv$sha256), as.character(spec$promotion_summary_sha256))) {
        stop(sprintf("Summary override '%s' promotion manifest does not pin the configured summary hash.", override_id), call. = FALSE)
      }
      expected_promotion_rows <- as.integer(spec$expected_promotion_rows %||% 9L)
      expected_model_variants <- as.character(unlist(spec$expected_model_variants %||% spec$expected_model_variant %||% "rhs_ns", use.names = FALSE))
      expected_model_keys <- as.character(unlist(spec$expected_model_keys %||% spec$expected_model_key %||% "qdesn_exal_rhs_ns", use.names = FALSE))
      expected_qdesn_likelihoods <- as.character(unlist(spec$expected_qdesn_likelihoods %||% spec$expected_qdesn_likelihood %||% "exal", use.names = FALSE))
      expected_likelihood_families <- as.character(unlist(spec$expected_likelihood_families %||% spec$expected_likelihood_family %||% expected_qdesn_likelihoods, use.names = FALSE))
      expected_priors <- as.character(unlist(spec$expected_priors %||% spec$expected_prior %||% expected_model_variants, use.names = FALSE))
      expected_methods <- as.character(unlist(spec$expected_methods %||% "mcmc", use.names = FALSE))
      expected_inferences <- as.character(unlist(spec$expected_inferences %||% "mcmc", use.names = FALSE))
      expected_row_diagnostic_qualifications <- as.character(unlist(
        spec$expected_row_diagnostic_qualifications %||% spec$diagnostic_qualification,
        use.names = FALSE
      ))
      require_comparison_eligible <- as_bool(spec$require_comparison_eligible %||% TRUE)

      promotion_required <- c(
        "promotion_id", "promotion_status", "diagnostic_qualification",
        "source_selection", "source_run_tag", "source_report_root", "root_id",
        "spec_id", "model_family", "model_variant", "model_key",
        "qdesn_likelihood", "inference", "method", "likelihood_family",
        "prior", "family", "tau", "fit_size", "effective_fit_size",
        "screening_profile_id", "status", "signoff_grade", "signoff_reason",
        "comparison_eligible", "fit_qtrue_rmse", "fit_pinball_mean",
        "forecast_qtrue_mae_lead_weighted", "forecast_qtrue_rmse_lead_weighted",
        "forecast_pinball_mean_lead_weighted", "runtime_hours", "n_leads",
        "n_origins_scored_total", "forecast_max_lead_configured",
        "forecast_origin_stride", "forecast_protocol",
        "train_start_source_index", "train_end_source_index",
        "forecast_origin_source_index", "forecast_block_start_source_index",
        "forecast_block_end_source_index", "validation_branch",
        "package_version", "source_registry_hash_value"
      )
      missing_promotion <- setdiff(promotion_required, names(promotion))
      if (length(missing_promotion)) {
        stop(
          sprintf("Summary override '%s' MCMC promotion summary is missing column(s): %s", override_id, paste(missing_promotion, collapse = ", ")),
          call. = FALSE
        )
      }
      if (nrow(promotion) != expected_promotion_rows ||
          any(as.character(promotion$promotion_id) != as.character(spec$promotion_id)) ||
          any(!(as.character(promotion$diagnostic_qualification) %in% expected_row_diagnostic_qualifications)) ||
          any(as.character(promotion$status) != "SUCCESS") ||
          any(!(as.character(promotion$method) %in% expected_methods)) ||
          any(!(as.character(promotion$inference) %in% expected_inferences)) ||
          any(as.character(promotion$model_family) != "qdesn") ||
          any(!(as.character(promotion$model_variant) %in% expected_model_variants)) ||
          any(!(as.character(promotion$model_key) %in% expected_model_keys)) ||
          any(!(as.character(promotion$qdesn_likelihood) %in% expected_qdesn_likelihoods)) ||
          any(!(as.character(promotion$likelihood_family) %in% expected_likelihood_families)) ||
          any(!(as.character(promotion$prior) %in% expected_priors)) ||
          any(as.integer(promotion$fit_size) != as.integer(config$fit_size)) ||
          any(as.integer(promotion$effective_fit_size) != as.integer(config$fit_size)) ||
          any(as.integer(promotion$n_leads) != as.integer(config$max_lead_configured)) ||
          any(as.integer(promotion$n_origins_scored_total) !=
              as.integer(config$forecast_block_end_source_index) - as.integer(config$forecast_block_start_source_index) + 1L) ||
          any(as.integer(promotion$forecast_max_lead_configured) != as.integer(config$max_lead_configured)) ||
          any(as.integer(promotion$forecast_origin_stride) != as.integer(config$origin_stride)) ||
          any(as.character(promotion$forecast_protocol) != as.character(config$forecast_protocol)) ||
          any(as.integer(promotion$train_start_source_index) != as.integer(config$train_start_source_index)) ||
          any(as.integer(promotion$train_end_source_index) != as.integer(config$train_end_source_index)) ||
          any(as.integer(promotion$forecast_origin_source_index) != as.integer(config$forecast_origin_source_index)) ||
          any(as.integer(promotion$forecast_block_start_source_index) != as.integer(config$forecast_block_start_source_index)) ||
          any(as.integer(promotion$forecast_block_end_source_index) != as.integer(config$forecast_block_end_source_index)) ||
          any(as.character(promotion$validation_branch) != as.character(config$validation_branch)) ||
          any(as.character(promotion$package_version) != as.character(config$package_version)) ||
          any(as.character(promotion$source_registry_hash_value) != as.character(config$source_registry_hash_value)) ||
          (require_comparison_eligible && any(!as_bool_vec(promotion$comparison_eligible)))) {
        stop(sprintf("Summary override '%s' promotion summary violates the active TT500 promotion contract.", override_id), call. = FALSE)
      }
      accepted_signoff_grades <- as.character(unlist(spec$accepted_signoff_grades, use.names = FALSE))
      if (any(!(as.character(promotion$signoff_grade) %in% accepted_signoff_grades))) {
        stop(sprintf("Summary override '%s' MCMC promotion contains a non-accepted diagnostic signoff.", override_id), call. = FALSE)
      }
      metric_cols <- c(
        "fit_qtrue_rmse", "fit_pinball_mean",
        "forecast_qtrue_mae_lead_weighted", "forecast_qtrue_rmse_lead_weighted",
        "forecast_pinball_mean_lead_weighted", "runtime_hours"
      )
      if (any(!is.finite(as.numeric(unlist(promotion[metric_cols], use.names = FALSE))))) {
        stop(sprintf("Summary override '%s' MCMC promotion contains non-finite displayed metrics.", override_id), call. = FALSE)
      }

      replacements <- spec$replacements
      if (!is.list(replacements) || !length(replacements)) {
        stop(sprintf("Summary override '%s' declares no replacements.", override_id), call. = FALSE)
      }
      seen <- character()
      for (ii in seq_along(replacements)) {
        repl <- replacements[[ii]]
        repl_required <- c("family", "tau", "model_key", "inference")
        missing_repl <- setdiff(repl_required, names(repl))
        if (length(missing_repl)) {
          stop(
            sprintf("Summary override '%s' replacement %d is missing field(s): %s", override_id, ii, paste(missing_repl, collapse = ", ")),
            call. = FALSE
          )
        }
        key <- cell_key(repl$family, repl$tau, repl$model_key, repl$inference)
        if (key %in% seen) {
          stop(sprintf("Summary override '%s' contains duplicate replacement keys.", override_id), call. = FALSE)
        }
        seen <- c(seen, key)

        row_idx <- which(
          summary_rows$family == as.character(repl$family) &
            abs(as.numeric(summary_rows$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            summary_rows$model_key == as.character(repl$model_key) &
            summary_rows$inference == as.character(repl$inference)
        )
        promo_row <- promotion[
          as.character(promotion$family) == as.character(repl$family) &
            abs(as.numeric(promotion$tau) - as.numeric(repl$tau)) < 1.0e-12 &
            as.character(promotion$model_key) == as.character(repl$model_key) &
            as.character(promotion$inference) == as.character(repl$inference),
          , drop = FALSE
        ]
        if (length(row_idx) != 1L || nrow(promo_row) != 1L) {
          stop(sprintf("Summary override '%s' replacement did not identify exactly one article row and one promotion row.", override_id), call. = FALSE)
        }

        original <- summary_rows[row_idx, , drop = FALSE]
        summary_rows$fit_qtrue_rmse[[row_idx]] <- as.numeric(promo_row$fit_qtrue_rmse[[1L]])
        summary_rows$fit_pinball_mean[[row_idx]] <- as.numeric(promo_row$fit_pinball_mean[[1L]])
        summary_rows$forecast_qtrue_mae_lead_weighted[[row_idx]] <- as.numeric(promo_row$forecast_qtrue_mae_lead_weighted[[1L]])
        summary_rows$forecast_qtrue_rmse_lead_weighted[[row_idx]] <- as.numeric(promo_row$forecast_qtrue_rmse_lead_weighted[[1L]])
        summary_rows$forecast_pinball_mean_lead_weighted[[row_idx]] <- as.numeric(promo_row$forecast_pinball_mean_lead_weighted[[1L]])
        summary_rows$runtime_hours[[row_idx]] <- as.numeric(promo_row$runtime_hours[[1L]])
        summary_rows$n_leads[[row_idx]] <- as.integer(promo_row$n_leads[[1L]])
        summary_rows$n_origins_scored_total[[row_idx]] <- as.integer(promo_row$n_origins_scored_total[[1L]])
        summary_rows$validation_commit[[row_idx]] <- as.character(spec$validation_commit_at_export)
        summary_rows$article_interface_ids[[row_idx]] <- override_id
        summary_rows$article_interface_sha256[[row_idx]] <- paste(
          c(spec$promotion_summary_sha256, spec$promotion_manifest_sha256),
          collapse = ";"
        )

        applied[[length(applied) + 1L]] <- data.frame(
          override_id = override_id,
          family = as.character(repl$family),
          tau = as.numeric(repl$tau),
          model_key = as.character(repl$model_key),
          inference = as.character(repl$inference),
          profile = as.character(promo_row$screening_profile_id[[1L]]),
          original_forecast_mae = as.numeric(original$forecast_qtrue_mae_lead_weighted[[1L]]),
          replacement_forecast_mae = as.numeric(promo_row$forecast_qtrue_mae_lead_weighted[[1L]]),
          original_forecast_pinball = as.numeric(original$forecast_pinball_mean_lead_weighted[[1L]]),
          replacement_forecast_pinball = as.numeric(promo_row$forecast_pinball_mean_lead_weighted[[1L]]),
          replacement_fit_rmse = as.numeric(promo_row$fit_qtrue_rmse[[1L]]),
          replacement_fit_pinball = as.numeric(promo_row$fit_pinball_mean[[1L]]),
          replacement_runtime_sec = as.numeric(promo_row$runtime_hours[[1L]]) * 3600,
          report_root = as.character(promo_row$source_report_root[[1L]]),
          evidence_source = override_type,
          promotion_summary_path = promotion_summary_path,
          promotion_summary_sha256 = as.character(spec$promotion_summary_sha256),
          promotion_manifest_path = promotion_manifest_path,
          promotion_manifest_sha256 = as.character(spec$promotion_manifest_sha256),
          source_selection = as.character(promo_row$source_selection[[1L]]),
          source_run_tag = as.character(promo_row$source_run_tag[[1L]]),
          diagnostic_qualification = as.character(promo_row$diagnostic_qualification[[1L]]),
          replacement_signoff_grade = as.character(promo_row$signoff_grade[[1L]]),
          replacement_signoff_reason = as.character(promo_row$signoff_reason[[1L]]),
          stringsAsFactors = FALSE
        )
      }
      next
    }

    if (!identical(override_type, "single_profile_dominance")) {
      stop(sprintf("Summary override '%s' has unknown override_type '%s'.", override_id, override_type), call. = FALSE)
    }

    required <- c(
      "interface_role", "validation_commit_at_export", "run_tag",
      "report_root", "results_root", "primary_profile",
      "fit_forecast_summary_path", "fit_forecast_summary_sha256",
      "dominance_cell_summary_path", "dominance_cell_summary_sha256",
      "dominance_profile_ranking_path", "dominance_profile_ranking_sha256",
      "audit_summary_path", "audit_summary_sha256", "replacements"
    )
    missing <- setdiff(required, names(spec))
    if (length(missing)) {
      stop(
        sprintf("Summary override '%s' is missing required field(s): %s", override_id, paste(missing, collapse = ", ")),
        call. = FALSE
      )
    }
    app_fail_on_disallowed_validation_text(spec, sprintf("summary override '%s'", override_id))

    fit_path <- verify_file_hash(
      spec$fit_forecast_summary_path,
      spec$fit_forecast_summary_sha256,
      sprintf("summary override '%s' fit/forecast summary", override_id)
    )
    cell_path <- verify_file_hash(
      spec$dominance_cell_summary_path,
      spec$dominance_cell_summary_sha256,
      sprintf("summary override '%s' dominance cell summary", override_id)
    )
    rank_path <- verify_file_hash(
      spec$dominance_profile_ranking_path,
      spec$dominance_profile_ranking_sha256,
      sprintf("summary override '%s' dominance profile ranking", override_id)
    )
    audit_path <- verify_file_hash(
      spec$audit_summary_path,
      spec$audit_summary_sha256,
      sprintf("summary override '%s' audit summary", override_id)
    )

    fit <- app_read_csv(fit_path)
    cell <- app_read_csv(cell_path)
    rank <- app_read_csv(rank_path)
    audit <- app_read_csv(audit_path)
    app_fail_on_disallowed_validation_text(fit, sprintf("summary override '%s' fit/forecast summary", override_id))
    app_fail_on_disallowed_validation_text(cell, sprintf("summary override '%s' dominance cell summary", override_id))
    app_fail_on_disallowed_validation_text(rank, sprintf("summary override '%s' dominance ranking", override_id))
    app_fail_on_disallowed_validation_text(audit, sprintf("summary override '%s' audit summary", override_id))

    if (nrow(audit) != 1L || !isTRUE(as_bool(audit$strict_ready[[1L]])) ||
        as.integer(audit$n_success[[1L]]) != as.integer(audit$expected_roots[[1L]]) ||
        as.integer(audit$n_fail[[1L]]) != 0L ||
        as.integer(audit$forbidden_binary_count_total[[1L]]) != 0L) {
      stop(sprintf("Summary override '%s' audit is not strict-ready and storage-light.", override_id), call. = FALSE)
    }
    if (!all(c("screening_profile_base", "dominance_pass") %in% names(rank))) {
      stop(sprintf("Summary override '%s' dominance ranking is missing required columns.", override_id), call. = FALSE)
    }
    primary_rank <- rank[as.character(rank$screening_profile_base) == as.character(spec$primary_profile), , drop = FALSE]
    if (nrow(primary_rank) != 1L || !isTRUE(as_bool(primary_rank$dominance_pass[[1L]]))) {
      stop(sprintf("Summary override '%s' primary profile does not pass dominance.", override_id), call. = FALSE)
    }

    replacements <- spec$replacements
    if (!is.list(replacements) || !length(replacements)) {
      stop(sprintf("Summary override '%s' declares no replacements.", override_id), call. = FALSE)
    }
    seen <- character()
    for (ii in seq_along(replacements)) {
      repl <- replacements[[ii]]
      repl_required <- c("family", "tau", "model_key", "inference", "profile")
      missing_repl <- setdiff(repl_required, names(repl))
      if (length(missing_repl)) {
        stop(
          sprintf("Summary override '%s' replacement %d is missing field(s): %s", override_id, ii, paste(missing_repl, collapse = ", ")),
          call. = FALSE
        )
      }
      key <- cell_key(repl$family, repl$tau, repl$model_key, repl$inference)
      if (key %in% seen) {
        stop(sprintf("Summary override '%s' contains duplicate replacement keys.", override_id), call. = FALSE)
      }
      seen <- c(seen, key)

      row_idx <- which(
        summary_rows$family == as.character(repl$family) &
          abs(as.numeric(summary_rows$tau) - as.numeric(repl$tau)) < 1.0e-12 &
          summary_rows$model_key == as.character(repl$model_key) &
          summary_rows$inference == as.character(repl$inference)
      )
      if (length(row_idx) != 1L) {
        stop(sprintf("Summary override '%s' replacement did not identify exactly one article row.", override_id), call. = FALSE)
      }

      cell_row <- cell[
        as.character(cell$family) == as.character(repl$family) &
          abs(as.numeric(cell$tau) - as.numeric(repl$tau)) < 1.0e-12 &
          as.character(cell$screening_profile_base) == as.character(repl$profile),
        , drop = FALSE
      ]
      fit_row <- fit[
        as.character(fit$family) == as.character(repl$family) &
          abs(as.numeric(fit$tau) - as.numeric(repl$tau)) < 1.0e-12 &
          as.character(fit$screening_profile_base) == as.character(repl$profile),
        , drop = FALSE
      ]
      if (nrow(cell_row) != 1L || nrow(fit_row) != 1L) {
        stop(sprintf("Summary override '%s' replacement source row is not unique.", override_id), call. = FALSE)
      }
      if (!isTRUE(as_bool(cell_row$beats_all_primary_baselines[[1L]]))) {
        stop(sprintf("Summary override '%s' replacement source does not beat all primary baselines.", override_id), call. = FALSE)
      }
      if (as.character(fit_row$status[[1L]]) != "SUCCESS" ||
          as.character(fit_row$signoff_grade[[1L]]) != "PASS" ||
          as.character(fit_row$inference[[1L]]) != "vb" ||
          as.character(fit_row$likelihood_family[[1L]]) != "exal" ||
          as.character(fit_row$prior[[1L]]) != "rhs_ns" ||
          as.integer(fit_row$fit_size[[1L]]) != as.integer(config$fit_size) ||
          as.integer(fit_row$forecast_max_lead_configured[[1L]]) != as.integer(config$max_lead_configured) ||
          as.integer(fit_row$forecast_origin_stride[[1L]]) != as.integer(config$origin_stride)) {
        stop(sprintf("Summary override '%s' replacement source violates the active TT500 VB exAL RHS contract.", override_id), call. = FALSE)
      }

      original <- summary_rows[row_idx, , drop = FALSE]
      summary_rows$fit_qtrue_rmse[[row_idx]] <- as.numeric(cell_row$qdesn_fit_rmse_mean[[1L]])
      summary_rows$fit_pinball_mean[[row_idx]] <- as.numeric(cell_row$qdesn_fit_pinball_mean[[1L]])
      summary_rows$forecast_qtrue_mae_lead_weighted[[row_idx]] <- as.numeric(cell_row$qdesn_forecast_mae_mean[[1L]])
      summary_rows$forecast_qtrue_rmse_lead_weighted[[row_idx]] <- as.numeric(fit_row$forecast_all_qtrue_rmse[[1L]])
      summary_rows$forecast_pinball_mean_lead_weighted[[row_idx]] <- as.numeric(cell_row$qdesn_forecast_pinball_mean[[1L]])
      summary_rows$runtime_hours[[row_idx]] <- as.numeric(cell_row$qdesn_runtime_sec_mean[[1L]]) / 3600
      summary_rows$n_leads[[row_idx]] <- as.integer(fit_row$forecast_lead_metrics_rows[[1L]])
      summary_rows$n_origins_scored_total[[row_idx]] <- as.integer(fit_row$forecast_all_origin_scores[[1L]])
      summary_rows$validation_commit[[row_idx]] <- as.character(spec$validation_commit_at_export)
      summary_rows$article_interface_ids[[row_idx]] <- override_id
      summary_rows$article_interface_sha256[[row_idx]] <- paste(
        c(spec$fit_forecast_summary_sha256, spec$dominance_cell_summary_sha256, spec$dominance_profile_ranking_sha256),
        collapse = ";"
      )

      applied[[length(applied) + 1L]] <- data.frame(
        override_id = override_id,
        family = as.character(repl$family),
        tau = as.numeric(repl$tau),
        model_key = as.character(repl$model_key),
        inference = as.character(repl$inference),
        profile = as.character(repl$profile),
        original_forecast_mae = as.numeric(original$forecast_qtrue_mae_lead_weighted[[1L]]),
        replacement_forecast_mae = as.numeric(cell_row$qdesn_forecast_mae_mean[[1L]]),
        original_forecast_pinball = as.numeric(original$forecast_pinball_mean_lead_weighted[[1L]]),
        replacement_forecast_pinball = as.numeric(cell_row$qdesn_forecast_pinball_mean[[1L]]),
        replacement_fit_rmse = as.numeric(cell_row$qdesn_fit_rmse_mean[[1L]]),
        replacement_fit_pinball = as.numeric(cell_row$qdesn_fit_pinball_mean[[1L]]),
        replacement_runtime_sec = as.numeric(cell_row$qdesn_runtime_sec_mean[[1L]]),
        report_root = as.character(spec$report_root),
        stringsAsFactors = FALSE
      )
    }
  }

  attr(summary_rows, "applied_summary_overrides") <- if (length(applied)) {
    bind_rows_fill(applied)
  } else {
    data.frame()
  }
  summary_rows
}

model_order <- c(
  "dqlm", "exdqlm",
  "qdesn_al_ridge", "qdesn_exal_ridge",
  "qdesn_al_rhs_ns", "qdesn_exal_rhs_ns"
)
family_order <- c("normal", "laplace", "gausmix")
family_label <- c(
  normal = "Gaussian",
  laplace = "Laplace",
  gausmix = "Gaussian mixture"
)
inference_order <- c("vb", "mcmc")
tau_order <- c(0.05, 0.25, 0.50)
metrics <- c(
  fit_qtrue_rmse = "Fit RMSE",
  forecast_qtrue_mae_lead_weighted = "Forecast MAE",
  forecast_pinball_mean_lead_weighted = "Check loss"
)
metric_labels <- unname(metrics)

result <- app_validate_tt500_final_validation(args$config)
config <- result$config
rows <- add_model_labels(result$tt500)

split_key <- interaction(
  rows$model_key, rows$inference, rows$family, rows$tau, rows$fit_size,
  drop = TRUE,
  lex.order = TRUE
)
summary_rows <- do.call(rbind, lapply(split(rows, split_key), collapse_group))
summary_rows$model_order <- match(summary_rows$model_key, model_order)
summary_rows$family_order <- match(summary_rows$family, family_order)
summary_rows$inference_order <- match(summary_rows$inference, inference_order)
summary_rows <- summary_rows[order(
  summary_rows$family_order,
  summary_rows$inference_order,
  summary_rows$model_order,
  summary_rows$tau
), , drop = FALSE]
rownames(summary_rows) <- NULL
summary_rows <- apply_summary_overrides(summary_rows, config)
applied_summary_overrides <- attr(summary_rows, "applied_summary_overrides")

expected_summary_rows <- length(model_order) * length(family_order) * length(inference_order) * length(tau_order)
if (nrow(summary_rows) != expected_summary_rows) {
  stop(
    sprintf("Expected %d TT500 final summary rows; found %d.", expected_summary_rows, nrow(summary_rows)),
    call. = FALSE
  )
}
if (any(is.na(summary_rows$model_order))) {
  stop("Final TT500 summary contains an unexpected model key.", call. = FALSE)
}

app_write_csv(summary_rows, args$out_csv)

best_lookup <- list()
for (fam in family_order) {
  for (inf in inference_order) {
    for (tau in tau_order) {
      block <- summary_rows[
        summary_rows$family == fam &
          summary_rows$inference == inf &
          abs(summary_rows$tau - tau) < 1.0e-12,
        , drop = FALSE
      ]
      for (metric in names(metrics)) {
        key <- paste(fam, inf, tau, metric, sep = "\r")
        vals <- as.numeric(block[[metric]])
        best_lookup[[key]] <- if (length(vals) && any(is.finite(vals))) min(vals, na.rm = TRUE) else NA_real_
      }
    }
  }
}

table_cell <- function(fam, inf, model_key, tau, metric) {
  row <- summary_rows[
    summary_rows$family == fam &
      summary_rows$inference == inf &
      summary_rows$model_key == model_key &
      abs(summary_rows$tau - tau) < 1.0e-12,
    , drop = FALSE
  ]
  if (nrow(row) != 1L) return("--")
  best <- best_lookup[[paste(fam, inf, tau, metric, sep = "\r")]]
  bold_if_best(row[[metric]][[1L]], best)
}

short_hash <- function(x, n = 12L) {
  x <- as.character(x)
  ifelse(nchar(x) > n, paste0(substr(x, 1L, n), "..."), x)
}

write_protocol_table <- function(out_path) {
  protocol_rows <- data.frame(
    Item = c(
      "Fit size",
      "Training window",
      "Forecast block",
      "Forecast origins",
      "Rolling-origin grid",
      "Error families",
      "Quantile levels",
      "Inference methods",
      "Displayed criteria"
    ),
    Value = c(
      sprintf("%d observations", as.integer(config$fit_size)),
      sprintf("%d--%d", as.integer(config$train_start_source_index), as.integer(config$train_end_source_index)),
      sprintf("%d--%d", as.integer(config$forecast_block_start_source_index), as.integer(config$forecast_block_end_source_index)),
      sprintf("every %d indices from %d through %d",
              as.integer(config$origin_stride),
              as.integer(config$forecast_origin_source_index),
              as.integer(config$forecast_block_end_source_index) - 10L),
      sprintf("leads 1--%d, stride %d, no refit",
              as.integer(config$max_lead_configured), as.integer(config$origin_stride)),
      "Gaussian, Laplace, Gaussian mixture",
      "p = 0.05, 0.25, 0.50",
      "VB--LD and MCMC",
      "Fit RMSE, forecast MAE, check loss"
    ),
    stringsAsFactors = FALSE
  )
  row_lines <- sprintf(
    "%s & %s \\\\",
    latex_escape(protocol_rows$Item),
    latex_escape(protocol_rows$Value)
  )
  lines <- c(
    "% Generated by application/scripts/31_build_shared_validation_tt500_final_tables.R.",
    sprintf("%% Source config: %s", app_prefer_repo_relative_path(args$config)),
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\small",
    "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.34\\textwidth}>{\\raggedright\\arraybackslash}p{0.56\\textwidth}@{}}",
    "\\toprule",
    "Protocol item & Recorded value \\\\",
    "\\midrule",
    row_lines,
    "\\bottomrule",
    "\\end{tabular}",
    paste0(
      "\\caption{Simulation fit-and-forecast protocol used by the ",
      "manuscript comparison tables. All reported models use the same ",
      "training window, held-out block, rolling-origin grid, and scoring ",
      "criteria.}"
    ),
    "\\label{tab:simulation-tt500-final-protocol}",
    "\\end{table}"
  )
  app_ensure_dir(dirname(out_path))
  writeLines(lines, out_path, useBytes = TRUE)
}

write_family_table <- function(fam, out_path) {
  label <- family_label[[fam]]
  col_count <- 1L + length(tau_order) * length(metrics)
  lines <- c(
    "% Generated by application/scripts/31_build_shared_validation_tt500_final_tables.R.",
    sprintf("%% Source config: %s", app_prefer_repo_relative_path(args$config)),
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3.4pt}",
    "\\resizebox{\\textwidth}{!}{%",
    sprintf("\\begin{tabular}{@{}l%s@{}}", paste(rep("r", col_count - 1L), collapse = "")),
    "\\toprule",
    paste0(
      "Model",
      paste(
        sprintf(" & \\multicolumn{%d}{c}{$p=%s$}", length(metrics), format(tau_order, nsmall = 2)),
        collapse = ""
      ),
      " \\\\"
    ),
    paste0(
      paste(
        sprintf("\\cmidrule(lr){%d-%d}", 2 + (seq_along(tau_order) - 1L) * length(metrics),
                1 + seq_along(tau_order) * length(metrics)),
        collapse = " "
      )
    ),
    paste0(
      " & ",
      paste(rep(paste(metric_labels, collapse = " & "), length(tau_order)), collapse = " & "),
      " \\\\"
    ),
    "\\midrule"
  )
  for (inf in inference_order) {
    inf_label <- ifelse(inf == "vb", "VB--LD", "MCMC")
    if (!identical(inf, head(inference_order, 1L))) {
      lines <- c(lines, "\\midrule")
    }
    lines <- c(lines, sprintf("\\multicolumn{%d}{@{}l}{\\textit{%s}} \\\\", col_count, inf_label))
    for (mk in model_order) {
      row_label <- summary_rows$model_label[summary_rows$model_key == mk][[1L]]
      cells <- character()
      for (tau in tau_order) {
        for (metric in names(metrics)) {
          cells <- c(cells, table_cell(fam, inf, mk, tau, metric))
        }
      }
      lines <- c(lines, sprintf("%s & %s \\\\", latex_escape(row_label), paste(cells, collapse = " & ")))
    }
    if (!identical(inf, tail(inference_order, 1L))) {
      lines <- c(lines, "\\addlinespace[2pt]")
    }
  }
  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}%",
    "}",
    sprintf(
      paste0(
        "\\caption{Final TT500 fit-and-forecast comparison for the %s simulation family. ",
        "Rows compare DQLM, exDQLM, and QDESN/exQDESN variants; panels separate ",
        "VB--LD and MCMC. Forecast entries average scored rolling-origin ",
        "lead-target pairs over leads 1--%d with origin stride %d. Lower ",
        "values are better for all displayed metrics, and boldface marks the ",
        "lowest value within each inference panel and quantile level.}"
      ),
      label,
      as.integer(config$max_lead_configured),
      as.integer(config$origin_stride)
    ),
    sprintf("\\label{tab:simulation-tt500-final-%s}", fam),
    "\\end{table}"
  )
  app_ensure_dir(dirname(out_path))
  writeLines(lines, out_path, useBytes = TRUE)
}

combined_header_lines <- function() {
  combined_metric_labels <- c(
    "\\shortstack{Fit\\\\RMSE}",
    "\\shortstack{Forecast\\\\MAE}",
    "\\shortstack{Check\\\\loss}"
  )
  c(
    paste0(
      "Model",
      paste(
        sprintf(" & \\multicolumn{%d}{c}{$p=%s$}", length(metrics), format(tau_order, nsmall = 2)),
        collapse = ""
      ),
      " \\\\"
    ),
    paste0(
      paste(
        sprintf(
          "\\cmidrule(lr){%d-%d}",
          2 + (seq_along(tau_order) - 1L) * length(metrics),
          1 + seq_along(tau_order) * length(metrics)
        ),
        collapse = " "
      )
    ),
    paste0(
      " & ",
      paste(rep(paste(combined_metric_labels, collapse = " & "), length(tau_order)), collapse = " & "),
      " \\\\"
    )
  )
}

combined_model_label <- function(model_key) {
  labels <- c(
    dqlm = "DQLM",
    exdqlm = "exDQLM",
    qdesn_al_ridge = "QDESN ridge",
    qdesn_exal_ridge = "exQDESN ridge",
    qdesn_al_rhs_ns = "QDESN RHS",
    qdesn_exal_rhs_ns = "exQDESN RHS"
  )
  out <- labels[[as.character(model_key)]]
  if (is.null(out)) latex_escape(as.character(model_key)) else out
}

write_combined_table <- function(out_path) {
  col_count <- 1L + length(tau_order) * length(metrics)
  family_panel_label <- c(
    normal = "Gaussian innovations",
    laplace = "Laplace innovations",
    gausmix = "Gaussian-mixture innovations"
  )
  note <- sprintf(
    paste0(
      "\\par\\smallskip\\noindent{\\footnotesize\\raggedright ",
      "\\textit{Notes:} Common protocol: the training window ",
      "contains source indices %d--%d, the held-out forecast block contains ",
      "source indices %d--%d, forecast origins are spaced every %d indices ",
      "from %d through %d, and forecasts score leads 1--%d without refitting. ",
      "Fit RMSE compares the fitted quantile path with the oracle quantile ",
      "on the training window; forecast MAE compares rolling-origin quantile ",
      "forecasts with the oracle quantile; check loss scores the held-out ",
      "observations at the target quantile level.\\par}"
    ),
    as.integer(config$train_start_source_index),
    as.integer(config$train_end_source_index),
    as.integer(config$forecast_block_start_source_index),
    as.integer(config$forecast_block_end_source_index),
    as.integer(config$origin_stride),
    as.integer(config$forecast_origin_source_index),
    as.integer(config$forecast_block_end_source_index) - 10L,
    as.integer(config$max_lead_configured)
  )
  provenance_note <- paste0(
    "\\par\\smallskip\\noindent{\\footnotesize\\raggedright ",
    "\\textit{Provenance:} exDQLM/DQLM VB rows use the July 2026 ",
    "current-best c13 validation summary. exDQLM/DQLM MCMC rows are retained ",
    "from the earlier matched-protocol interface and should not be read as a ",
    "new MCMC calibration. QDESN/exQDESN rows use the pinned repair and promotion ",
    "handoffs recorded in the generated manifest.\\par}"
  )
  header <- combined_header_lines()
  lines <- c(
    "\\begingroup",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{2.0pt}",
    "\\renewcommand{\\arraystretch}{1.06}",
    sprintf("\\begin{longtable}{@{}l%s@{}}", paste(rep("r", col_count - 1L), collapse = "")),
    paste0(
      "\\caption{Consolidated simulation fit-and-forecast comparison using ",
      "500 training observations. Rows are grouped by innovation distribution and ",
      "inference method; columns report fit RMSE, forecast MAE, and check loss ",
      "at each target quantile level. Lower values are better, and ",
      "boldface marks the best value within each family, inference method, ",
      "quantile level, and criterion.}"
    ),
    "\\label{tab:simulation-fitforecast-results}\\\\",
    "\\toprule",
    header,
    "\\midrule",
    "\\endfirsthead",
    paste0(
      "\\caption[]{Consolidated simulation fit-and-forecast comparison ",
      "(continued).}\\\\"
    ),
    "\\toprule",
    header,
    "\\midrule",
    "\\endhead",
    "\\endfoot",
    "\\bottomrule",
    "\\endlastfoot"
  )

  for (fam in family_order) {
    if (!identical(fam, family_order[[1L]])) {
      lines <- c(
        lines,
        if (identical(fam, "laplace")) "\\pagebreak[4]" else "\\addlinespace[4pt]"
      )
    }
    lines <- c(
      lines,
      sprintf("\\multicolumn{%d}{@{}l}{\\textbf{%s}} \\\\", col_count, latex_escape(family_panel_label[[fam]])),
      "\\addlinespace[1pt]"
    )
    for (inf in inference_order) {
      inf_label <- ifelse(inf == "vb", "VB", "MCMC")
      lines <- c(lines, sprintf("\\multicolumn{%d}{@{}l}{\\textit{%s}} \\\\", col_count, inf_label))
      for (mk in model_order) {
        row_label <- combined_model_label(mk)
        cells <- character()
        for (tau in tau_order) {
          for (metric in names(metrics)) {
            cells <- c(cells, table_cell(fam, inf, mk, tau, metric))
          }
        }
        lines <- c(lines, sprintf("%s & %s \\\\", row_label, paste(cells, collapse = " & ")))
      }
      if (!identical(inf, tail(inference_order, 1L))) {
        lines <- c(lines, "\\addlinespace[2pt]")
      }
    }
  }

  lines <- c(
    lines,
    "\\end{longtable}",
    note,
    provenance_note,
    "\\endgroup"
  )
  app_ensure_dir(dirname(out_path))
  writeLines(lines, out_path, useBytes = TRUE)
}

write_combined_table(args$out_combined)
write_protocol_table(args$out_protocol)
write_family_table("normal", args$out_normal)
write_family_table("laplace", args$out_laplace)
write_family_table("gausmix", args$out_gausmix)

wrapper_lines <- c(
  "% Generated by application/scripts/31_build_shared_validation_tt500_final_tables.R.",
  "\\input{tables/qdesn_validation_tt500_final_protocol.tex}",
  "\\input{tables/qdesn_validation_tt500_final_normal.tex}",
  "\\input{tables/qdesn_validation_tt500_final_laplace.tex}",
  "\\input{tables/qdesn_validation_tt500_final_gausmix.tex}"
)
app_ensure_dir(dirname(args$out_wrapper))
writeLines(wrapper_lines, args$out_wrapper, useBytes = TRUE)

repo_root_norm <- normalizePath(app_repo_root(), winslash = "/", mustWork = TRUE)
repo_path_label <- function(path) {
  abs_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root_norm, "/")
  if (identical(abs_path, repo_root_norm)) {
    "."
  } else if (startsWith(abs_path, prefix)) {
    substring(abs_path, nchar(prefix) + 1L)
  } else {
    abs_path
  }
}

manifest_lines <- c(
  "Shared validation 500-observation final article table manifest",
  "Generation mode: deterministic from pinned interface hashes; article provenance is the Git commit containing this manifest.",
  sprintf("Builder: application/scripts/31_build_shared_validation_tt500_final_tables.R"),
  sprintf("Config: %s", repo_path_label(args$config)),
  sprintf("Output CSV: %s", repo_path_label(args$out_csv)),
  sprintf("Output wrapper: %s", repo_path_label(args$out_wrapper)),
  sprintf("Output combined table: %s", repo_path_label(args$out_combined)),
  sprintf("Output protocol table: %s", repo_path_label(args$out_protocol)),
  sprintf("Output normal table: %s", repo_path_label(args$out_normal)),
  sprintf("Output laplace table: %s", repo_path_label(args$out_laplace)),
  sprintf("Output gausmix table: %s", repo_path_label(args$out_gausmix)),
  sprintf("Summary CSV SHA-256: %s", app_sha256_file(args$out_csv)),
  sprintf("Wrapper SHA-256: %s", app_sha256_file(args$out_wrapper)),
  sprintf("Combined TeX SHA-256: %s", app_sha256_file(args$out_combined)),
  sprintf("Protocol TeX SHA-256: %s", app_sha256_file(args$out_protocol)),
  sprintf("Normal TeX SHA-256: %s", app_sha256_file(args$out_normal)),
  sprintf("Laplace TeX SHA-256: %s", app_sha256_file(args$out_laplace)),
  sprintf("Gausmix TeX SHA-256: %s", app_sha256_file(args$out_gausmix)),
  sprintf("Validation worktree: %s", config$validation_worktree),
  sprintf("Validation branch: %s", config$validation_branch),
  sprintf("Validation HEAD at article sync: %s", config$validation_head_commit_at_article_sync),
  sprintf("Package version: %s", config$package_version),
  sprintf("Source registry root: %s", config$source_registry_root),
  sprintf("Source registry hash name: %s", config$source_registry_hash_name),
  sprintf("Source registry hash value: %s", config$source_registry_hash_value),
  sprintf("Fit size: %d", as.integer(config$fit_size)),
  sprintf("Train window: %d:%d", as.integer(config$train_start_source_index), as.integer(config$train_end_source_index)),
  sprintf("Forecast block: %d:%d", as.integer(config$forecast_block_start_source_index), as.integer(config$forecast_block_end_source_index)),
  sprintf("Rolling-origin max lead: %d", as.integer(config$max_lead_configured)),
  sprintf("Rolling-origin stride: %d", as.integer(config$origin_stride)),
  sprintf("Summary rows: %d", nrow(summary_rows)),
  sprintf("Lead-level 500-observation rows consumed: %d", nrow(rows)),
  sprintf("Summary override rows applied: %d", nrow(applied_summary_overrides)),
  "Interfaces:"
)
for (interface_id in app_tt500_final_interface_names(config)) {
  spec <- config$interfaces[[interface_id]]
  manifest_lines <- c(
    manifest_lines,
    sprintf("- %s role: %s", interface_id, spec$interface_role),
    sprintf("  path: %s", spec$path),
    sprintf("  sha256: %s", spec$sha256),
    sprintf("  validation_commit_at_export: %s", spec$validation_commit_at_export),
    sprintf("  expected_rows_total: %d", as.integer(spec$expected_rows_total)),
    sprintf("  expected_rows_tt500: %d", as.integer(spec$expected_rows_tt500))
  )
}
manifest_lines <- c(
  manifest_lines,
  "Summary overrides:"
)
if (nrow(applied_summary_overrides)) {
  for (ii in seq_len(nrow(applied_summary_overrides))) {
    row <- applied_summary_overrides[ii, , drop = FALSE]
    manifest_lines <- c(
      manifest_lines,
      sprintf(
        "- %s %s tau %.2f %s/%s profile %s",
        row$override_id,
        row$family,
        row$tau,
        row$model_key,
        row$inference,
        row$profile
      ),
      sprintf("  report_root: %s", row$report_root),
      if ("stage" %in% names(row) && has_value(row$stage)) {
        sprintf("  stage: %s", row$stage)
      },
      if ("evidence_source" %in% names(row) && has_value(row$evidence_source)) {
        sprintf("  evidence_source: %s", row$evidence_source)
      },
      if ("candidate_ledger_path" %in% names(row) && has_value(row$candidate_ledger_path)) {
        sprintf("  candidate_ledger_path: %s", row$candidate_ledger_path)
      },
      if ("candidate_ledger_sha256" %in% names(row) && has_value(row$candidate_ledger_sha256)) {
        sprintf("  candidate_ledger_sha256: %s", row$candidate_ledger_sha256)
      },
      if ("current_best_csv_path" %in% names(row) && has_value(row$current_best_csv_path)) {
        sprintf("  current_best_csv_path: %s", row$current_best_csv_path)
      },
      if ("current_best_csv_sha256" %in% names(row) && has_value(row$current_best_csv_sha256)) {
        sprintf("  current_best_csv_sha256: %s", row$current_best_csv_sha256)
      },
      if ("current_best_audit_path" %in% names(row) && has_value(row$current_best_audit_path)) {
        sprintf("  current_best_audit_path: %s", row$current_best_audit_path)
      },
      if ("current_best_audit_sha256" %in% names(row) && has_value(row$current_best_audit_sha256)) {
        sprintf("  current_best_audit_sha256: %s", row$current_best_audit_sha256)
      },
      if ("raw_interface_path" %in% names(row) && has_value(row$raw_interface_path)) {
        sprintf("  raw_interface_path: %s", row$raw_interface_path)
      },
      if ("raw_interface_sha256" %in% names(row) && has_value(row$raw_interface_sha256)) {
        sprintf("  raw_interface_sha256: %s", row$raw_interface_sha256)
      },
      if ("promotion_summary_path" %in% names(row) && has_value(row$promotion_summary_path)) {
        sprintf("  promotion_summary_path: %s", row$promotion_summary_path)
      },
      if ("promotion_summary_sha256" %in% names(row) && has_value(row$promotion_summary_sha256)) {
        sprintf("  promotion_summary_sha256: %s", row$promotion_summary_sha256)
      },
      if ("promotion_manifest_path" %in% names(row) && has_value(row$promotion_manifest_path)) {
        sprintf("  promotion_manifest_path: %s", row$promotion_manifest_path)
      },
      if ("promotion_manifest_sha256" %in% names(row) && has_value(row$promotion_manifest_sha256)) {
        sprintf("  promotion_manifest_sha256: %s", row$promotion_manifest_sha256)
      },
      if ("promotion_sources_path" %in% names(row) && has_value(row$promotion_sources_path)) {
        sprintf("  promotion_sources_path: %s", row$promotion_sources_path)
      },
      if ("promotion_sources_sha256" %in% names(row) && has_value(row$promotion_sources_sha256)) {
        sprintf("  promotion_sources_sha256: %s", row$promotion_sources_sha256)
      },
      if ("source_selection" %in% names(row) && has_value(row$source_selection)) {
        sprintf("  source_selection: %s", row$source_selection)
      },
      if ("source_run_tag" %in% names(row) && has_value(row$source_run_tag)) {
        sprintf("  source_run_tag: %s", row$source_run_tag)
      },
      if ("diagnostic_qualification" %in% names(row) && has_value(row$diagnostic_qualification)) {
        sprintf("  diagnostic_qualification: %s", row$diagnostic_qualification)
      },
      if ("replacement_signoff_grade" %in% names(row) && has_value(row$replacement_signoff_grade)) {
        sprintf("  replacement_signoff_grade: %s", row$replacement_signoff_grade)
      },
      if ("replacement_signoff_reason" %in% names(row) && has_value(row$replacement_signoff_reason)) {
        sprintf("  replacement_signoff_reason: %s", row$replacement_signoff_reason)
      },
      sprintf("  original_forecast_mae: %.12g", row$original_forecast_mae),
      sprintf("  replacement_forecast_mae: %.12g", row$replacement_forecast_mae),
      sprintf("  original_forecast_pinball: %.12g", row$original_forecast_pinball),
      sprintf("  replacement_forecast_pinball: %.12g", row$replacement_forecast_pinball),
      sprintf("  replacement_fit_rmse: %.12g", row$replacement_fit_rmse),
      sprintf("  replacement_fit_pinball: %.12g", row$replacement_fit_pinball),
      sprintf("  replacement_runtime_sec: %.12g", row$replacement_runtime_sec)
    )
  }
} else {
  manifest_lines <- c(manifest_lines, "- none")
}
manifest_lines <- c(
  manifest_lines,
  "Article policy: final 500-observation comparison only; no 5000-observation MCMC claims are made here."
)
writeLines(manifest_lines, args$out_manifest, useBytes = TRUE)

cat("500-observation final manuscript tables: PASS\n")
cat(sprintf("summary_rows: %d\n", nrow(summary_rows)))
cat(sprintf("lead_rows_consumed: %d\n", nrow(rows)))
cat(sprintf("csv: %s\n", normalizePath(args$out_csv, winslash = "/", mustWork = TRUE)))
cat(sprintf("wrapper: %s\n", normalizePath(args$out_wrapper, winslash = "/", mustWork = TRUE)))
cat(sprintf("combined: %s\n", normalizePath(args$out_combined, winslash = "/", mustWork = TRUE)))
cat(sprintf("protocol: %s\n", normalizePath(args$out_protocol, winslash = "/", mustWork = TRUE)))
cat(sprintf("manifest: %s\n", normalizePath(args$out_manifest, winslash = "/", mustWork = TRUE)))
