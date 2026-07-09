#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

table_source_mode <- Sys.getenv(
  "QDESN_SIMULATION_TABLE_SOURCE_MODE",
  "fit_only_historical"
)
if (!identical(table_source_mode, "fit_only_historical")) {
  stop(
    "Unsupported QDESN_SIMULATION_TABLE_SOURCE_MODE='", table_source_mode, "'. ",
    "The shared 1.0.0 fit+forecast validation logic branch is ready, but ",
    "article-facing fit+forecast result tables are not complete. Keep using ",
    "the documented fit-only historical table source until the validation ",
    "chat confirms closeout/export.",
    call. = FALSE
  )
}

# The publication tables are reproducible from external validation outputs.
# Set these environment variables when those outputs live outside the default
# local development layout.
validation_repo <- Sys.getenv(
  "QDESN_VALIDATION_REPO",
  "/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration"
)

default_qdesn_analysis_root <- file.path(
  validation_repo,
  "reports/qdesn_mcmc_validation",
  "dynamic_exdqlm_crossstudy_p90_steepertrend_n300m50_validation",
  "qdesn-dynamic-p90-steepertrend-n400m60-rhs-tau1em5-full-20260510-204348-w30__git-20de505",
  "20260510-204449__git-20de505"
)

analysis_root <- Sys.getenv("QDESN_ANALYSIS_ROOT", default_qdesn_analysis_root)

exdqlm_validation_repo <- Sys.getenv(
  "EXDQLM_VALIDATION_REPO",
  "/data/jaguir26/local/src/exdqlm__wt__validation_rerun_after_0p4p0_integration"
)

exdqlm_run_tag <- Sys.getenv(
  "EXDQLM_RUN_TAG",
  "20260507_p90_dynamic72_qdesn_comparable_fresh_v1"
)
exdqlm_run_root <- file.path(
  exdqlm_validation_repo,
  paste0("tools/merge_reports/full288_refreshed288_", exdqlm_run_tag)
)
exdqlm_shared_interface_path <- Sys.getenv(
  "EXDQLM_SHARED_INTERFACE_PATH",
  file.path(
    exdqlm_validation_repo,
    paste0(
      "tools/merge_reports/LOCAL_refreshed288_dynamic72_shared_interface_",
      exdqlm_run_tag,
      ".csv"
    )
  )
)
exdqlm_legacy_comparison_path <- file.path(
  exdqlm_validation_repo,
  "tools/merge_reports/LOCAL_refreshed288_comparison_long_20260427_20260422_p90_full288_baseline_v1.csv"
)
exdqlm_plot_summary_dir <- file.path(exdqlm_run_root, "plot_summaries")

read_json_manifest <- function(path) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

first_nonempty <- function(...) {
  vals <- list(...)
  for (val in vals) {
    if (length(val) > 0 && !is.null(val) && !is.na(val) && nzchar(as.character(val))) {
      return(as.character(val))
    }
  }
  NA_character_
}

resolve_qdesn_fit_summary_path <- function(root) {
  env_path <- Sys.getenv("QDESN_FIT_SUMMARY_PATH", "")
  if (nzchar(env_path)) {
    return(env_path)
  }
  candidates <- c(
    file.path(root, "tables/campaign_fit_summary.csv"),
    file.path(root, "tables/authoritative_fit_summary.csv")
  )
  hits <- candidates[file.exists(candidates)]
  if (length(hits) == 0L) {
    stop(
      "Missing Q-DESN fit summary. Tried:\n",
      paste(candidates, collapse = "\n")
    )
  }
  hits[[1L]]
}

fit_summary_path <- resolve_qdesn_fit_summary_path(analysis_root)
qdesn_input_mode <- if (grepl("campaign_fit_summary[.]csv$", fit_summary_path)) {
  "campaign_fit_summary"
} else if (grepl("authoritative_fit_summary[.]csv$", fit_summary_path)) {
  "authoritative_fit_summary"
} else {
  "custom_fit_summary"
}

campaign_completed_path <- file.path(analysis_root, "manifest/campaign_completed.json")
campaign_summary_manifest_path <- file.path(analysis_root, "manifest/campaign_summary_manifest.json")
campaign_manifest <- read_json_manifest(campaign_completed_path)
campaign_summary_manifest <- read_json_manifest(campaign_summary_manifest_path)
outer_report_root <- dirname(analysis_root)
launch_manifest_path <- file.path(outer_report_root, "launch/qdesn_dynamic_exdqlm_crossstudy_launch_manifest.json")
preflight_manifest_path <- file.path(outer_report_root, "launch/qdesn_dynamic_exdqlm_crossstudy_preflight_manifest.json")
launch_manifest <- read_json_manifest(launch_manifest_path)
preflight_manifest <- read_json_manifest(preflight_manifest_path)

if (identical(qdesn_input_mode, "campaign_fit_summary") && !file.exists(campaign_completed_path)) {
  stop("Q-DESN campaign fit summary requires completed campaign manifest: ", campaign_completed_path)
}

qdesn_run_tag <- first_nonempty(
  Sys.getenv("QDESN_RUN_TAG", ""),
  launch_manifest$run_tag,
  preflight_manifest$run_tag,
  basename(outer_report_root),
  basename(analysis_root)
)
qdesn_source_git_sha <- first_nonempty(
  Sys.getenv("QDESN_SOURCE_GIT_SHA", ""),
  preflight_manifest$git_sha,
  sub(".*__git-([0-9a-f]+).*", "\\1", qdesn_run_tag)
)
qdesn_recommendation <- first_nonempty(
  campaign_manifest$recommendation,
  campaign_summary_manifest$recommendation,
  launch_manifest$recommendation
)

output_dir <- file.path(getwd(), "tables")

required_files <- c(fit_summary_path)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop("Missing required validation output(s):\n", paste(missing_files, collapse = "\n"))
}

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

fit <- read.csv(fit_summary_path, check.names = FALSE)
if (!"canonical_model" %in% names(fit) && "model" %in% names(fit)) {
  fit$canonical_model <- fit$model
}
if (!"method_model" %in% names(fit) && all(c("method", "model") %in% names(fit))) {
  fit$method_model <- paste(fit$method, fit$model, sep = "_")
}
exdqlm_uses_shared_interface <- file.exists(exdqlm_shared_interface_path)
if (exdqlm_uses_shared_interface) {
  exdqlm_shared_interface <- read.csv(exdqlm_shared_interface_path, check.names = FALSE)
  exdqlm_shared_interface_git_sha <- if ("git_sha" %in% names(exdqlm_shared_interface)) {
    paste(sort(unique(exdqlm_shared_interface$git_sha)), collapse = ",")
  } else {
    NA_character_
  }
  exdqlm_comparison <- NULL
} else {
  if (!file.exists(exdqlm_legacy_comparison_path)) {
    stop(
      "Missing fresh exDQLM shared interface and legacy comparison fallback:\n",
      exdqlm_shared_interface_path,
      "\n",
      exdqlm_legacy_comparison_path
    )
  }
  if (!dir.exists(exdqlm_plot_summary_dir)) {
    stop("Missing exDQLM and DQLM plot-summary directory: ", exdqlm_plot_summary_dir)
  }
  exdqlm_shared_interface <- NULL
  exdqlm_shared_interface_git_sha <- NA_character_
  exdqlm_comparison <- read.csv(exdqlm_legacy_comparison_path, check.names = FALSE)
}

if (nrow(fit) != 144) {
  stop("Expected 144 Q-DESN fit rows, found ", nrow(fit), ".")
}

required_columns <- c(
  "family", "tau", "fit_size", "prior", "inference", "canonical_model",
  "train_qtrue_rmse", "train_pinball_tau", "runtime_sec"
)
if (!all(required_columns %in% names(fit))) {
  stop("The authoritative fit summary is missing one or more publication-table columns.")
}

family_order <- c("normal", "laplace", "gausmix")
fit_size_order <- c(500, 5000)
tau_order <- c(0.05, 0.25, 0.50)
qdesn_model_order <- c("al_ridge", "exal_ridge", "al_rhs_ns", "exal_rhs_ns")
publication_model_order <- c(
  "dqlm", "exdqlm",
  paste0("qdesn_", qdesn_model_order)
)
inference_order <- c("vb", "mcmc")

qdesn_model_label <- c(
  al_ridge = "\\(\\AL\\)--ridge",
  exal_ridge = "\\(\\exAL\\)--ridge",
  al_rhs_ns = "\\(\\AL\\)--\\RHS{}",
  exal_rhs_ns = "\\(\\exAL\\)--\\RHS{}"
)

publication_model_label <- c(
  dqlm = "\\(\\mathrm{DQLM}\\)",
  exdqlm = "\\(\\mathrm{exDQLM}\\)",
  qdesn_al_ridge = "Q--DESN \\(\\AL\\)--ridge",
  qdesn_exal_ridge = "Q--DESN \\(\\exAL\\)--ridge",
  qdesn_al_rhs_ns = "Q--DESN \\(\\AL\\)--\\RHS{}",
  qdesn_exal_rhs_ns = "Q--DESN \\(\\exAL\\)--\\RHS{}"
)

fit$model_key <- paste(fit$canonical_model, fit$prior, sep = "_")

pinball_loss <- function(y, qhat, tau) {
  mean((tau - as.numeric(y < qhat)) * (y - qhat), na.rm = TRUE)
}

format_value <- function(x, best, digits) {
  if (length(x) == 0 || is.na(x)) {
    return("--")
  }
  value <- formatC(x, format = "f", digits = digits)
  if (!is.na(best) && abs(x - best) < 1e-10) {
    return(paste0("\\textbf{", value, "}"))
  }
  value
}

metric_value <- function(dat, metric, fit_size, tau, model_key, family, inference) {
  idx <- dat$fit_size == fit_size &
    abs(dat$tau - tau) < 1e-10 &
    dat$model_key == model_key &
    dat$family == family &
    dat$inference == inference
  vals <- dat[[metric]][idx]
  vals <- vals[!is.na(vals)]
  if (length(vals) != 1) {
    stop(
      "Expected exactly one value for ",
      paste(metric, fit_size, tau, model_key, family, inference, sep = " / "),
      ", found ", length(vals), "."
    )
  }
  vals
}

best_by_family <- function(dat, metric, fit_size, tau, family) {
  vals <- unlist(lapply(publication_model_order, function(model_key) {
    vapply(
      inference_order,
      function(inference) metric_value(dat, metric, fit_size, tau, model_key, family, inference),
      numeric(1)
    )
  }))
  min(vals, na.rm = TRUE)
}

write_metric_table <- function(dat, metric, file_name, caption, label, digits) {
  lines <- c(
    "\\begin{table}[p]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3pt}",
    "\\begin{tabular}{@{}llrrrrrr@{}}",
    "\\toprule",
    " & & \\multicolumn{2}{c}{Normal} & \\multicolumn{2}{c}{Laplace} & \\multicolumn{2}{c}{Gaussian mixture} \\\\",
    "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(l){7-8}",
    "\\(\\tau\\) & Model & VB & MCMC & VB & MCMC & VB & MCMC \\\\",
    "\\midrule"
  )

  for (fit_size in fit_size_order) {
    lines <- c(
      lines,
      sprintf("\\multicolumn{8}{@{}l}{\\emph{Effective training size \\(T=%s\\)}}\\\\", fit_size),
      "\\addlinespace[0.15em]"
    )

    for (tau in tau_order) {
      best <- setNames(
        vapply(
          family_order,
          function(family) best_by_family(dat, metric, fit_size, tau, family),
          numeric(1)
        ),
        family_order
      )

      for (i in seq_along(publication_model_order)) {
        model_key <- publication_model_order[[i]]
        tau_label <- if (i == 1) sprintf("\\(%.2f\\)", tau) else ""
        values <- unlist(lapply(family_order, function(family) {
          vapply(inference_order, function(inference) {
            x <- metric_value(dat, metric, fit_size, tau, model_key, family, inference)
            format_value(x, best[[family]], digits)
          }, character(1))
        }))
        names(values) <- c("normal_vb", "normal_mcmc", "laplace_vb", "laplace_mcmc", "gausmix_vb", "gausmix_mcmc")

        lines <- c(
          lines,
          sprintf(
            "%s & %s & %s & %s & %s & %s & %s & %s \\\\",
            tau_label,
            publication_model_label[[model_key]],
            values[["normal_vb"]],
            values[["normal_mcmc"]],
            values[["laplace_vb"]],
            values[["laplace_mcmc"]],
            values[["gausmix_vb"]],
            values[["gausmix_mcmc"]]
          )
        )
      }
      if (tau != tail(tau_order, 1)) {
        lines <- c(lines, "\\addlinespace[0.2em]")
      }
    }
    if (fit_size != tail(fit_size_order, 1)) {
      lines <- c(lines, "\\midrule")
    }
  }

  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}",
    caption,
    label,
    "\\end{table}"
  )

  writeLines(lines, file.path(output_dir, file_name), useBytes = TRUE)
}

load_exdqlm_dynamic_check_loss <- function(plot_summary_dir) {
  files <- list.files(
    plot_summary_dir,
    pattern = "^row_[0-9]{4}_plot_summary[.]csv$",
    full.names = TRUE
  )
  if (!length(files)) {
    stop("No plot-summary files found in ", plot_summary_dir)
  }

  rows <- lapply(files, function(path) {
    dat <- read.csv(path, check.names = FALSE)
    if (!nrow(dat) || !identical(as.character(dat$block[[1L]]), "dynamic")) {
      return(NULL)
    }
    required <- c("row_id", "tau", "y", "q_fit_tau")
    if (!all(required %in% names(dat))) {
      stop("Dynamic plot summary is missing required column(s): ", path)
    }
    note <- if ("artifact_note" %in% names(dat)) dat$artifact_note else NA_character_
    data.frame(
      row_id = as.integer(dat$row_id[[1L]]),
      train_pinball_tau = pinball_loss(dat$y, dat$q_fit_tau, dat$tau[[1L]]),
      plot_summary_rows = nrow(dat),
      artifact_note = paste(unique(note), collapse = "; "),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  if (is.null(out) || nrow(out) != 72L) {
    stop("Expected 72 dynamic DQLM and exDQLM plot summaries, found ", if (is.null(out)) 0L else nrow(out))
  }
  out
}

build_publication_metric_data <- function() {
  qdesn <- data.frame(
    model_key = paste0("qdesn_", fit$model_key),
    inference = fit$inference,
    family = fit$family,
    tau = fit$tau,
    fit_size = fit$fit_size,
    train_qtrue_rmse = fit$train_qtrue_rmse,
    train_pinball_tau = fit$train_pinball_tau,
    runtime_sec = fit$runtime_sec,
    source = paste0("qdesn_", qdesn_input_mode, "_", qdesn_run_tag),
    stringsAsFactors = FALSE
  )

  if (exdqlm_uses_shared_interface) {
    required_shared <- c(
      "model_variant", "inference", "family", "tau", "effective_fit_size",
      "status", "signoff_grade", "train_qtrue_rmse", "train_pinball_tau",
      "runtime_sec"
    )
    if (!all(required_shared %in% names(exdqlm_shared_interface))) {
      stop("The exDQLM shared interface is missing one or more publication-table columns.")
    }
    ex_dynamic <- exdqlm_shared_interface
    if (nrow(ex_dynamic) != 72L) {
      stop("Expected 72 dynamic DQLM and exDQLM shared-interface rows, found ", nrow(ex_dynamic))
    }
    if (!all(ex_dynamic$status == "done")) {
      stop("All fresh exDQLM shared-interface rows must have status='done'.")
    }
    if (anyNA(ex_dynamic$train_pinball_tau) || anyNA(ex_dynamic$train_qtrue_rmse)) {
      stop("Missing fresh exDQLM metric value in shared-interface table.")
    }
    exdqlm <- data.frame(
      model_key = ifelse(ex_dynamic$model_variant == "dqlm", "dqlm", "exdqlm"),
      inference = ex_dynamic$inference,
      family = ex_dynamic$family,
      tau = ex_dynamic$tau,
      fit_size = ex_dynamic$effective_fit_size,
      train_qtrue_rmse = ex_dynamic$train_qtrue_rmse,
      train_pinball_tau = ex_dynamic$train_pinball_tau,
      runtime_sec = ex_dynamic$runtime_sec,
      source = paste0("exdqlm_shared_interface_", exdqlm_run_tag),
      stringsAsFactors = FALSE
    )
  } else {
    ex_dynamic <- exdqlm_comparison[exdqlm_comparison$block == "dynamic", , drop = FALSE]
    if (nrow(ex_dynamic) != 72L) {
      stop("Expected 72 dynamic DQLM and exDQLM rows, found ", nrow(ex_dynamic))
    }
    check_loss <- load_exdqlm_dynamic_check_loss(exdqlm_plot_summary_dir)
    ex_dynamic <- merge(ex_dynamic, check_loss, by = "row_id", all.x = TRUE, sort = FALSE)
    if (anyNA(ex_dynamic$train_pinball_tau)) {
      stop("Missing computed DQLM and exDQLM check loss for at least one dynamic row.")
    }
    exdqlm <- data.frame(
      model_key = ifelse(ex_dynamic$model == "dqlm", "dqlm", "exdqlm"),
      inference = ex_dynamic$inference,
      family = ex_dynamic$family,
      tau = ex_dynamic$tau,
      fit_size = ex_dynamic$fit_size,
      train_qtrue_rmse = ex_dynamic$q_rmse,
      train_pinball_tau = ex_dynamic$train_pinball_tau,
      runtime_sec = ex_dynamic$runtime_sec,
      source = paste0("exdqlm_legacy_comparison_", exdqlm_run_tag),
      stringsAsFactors = FALSE
    )
  }

  out <- rbind(qdesn, exdqlm)
  expected_rows <- 144L + 72L
  if (nrow(out) != expected_rows) {
    stop("Expected ", expected_rows, " publication metric rows, found ", nrow(out))
  }

  combo_key <- paste(
    out$model_key, out$inference, out$family,
    format(out$tau, nsmall = 2), out$fit_size,
    sep = " / "
  )
  if (any(duplicated(combo_key))) {
    stop("Duplicate publication metric rows detected.")
  }
  expected <- expand.grid(
    model_key = publication_model_order,
    inference = inference_order,
    family = family_order,
    tau = tau_order,
    fit_size = fit_size_order,
    stringsAsFactors = FALSE
  )
  expected_key <- paste(
    expected$model_key, expected$inference, expected$family,
    format(expected$tau, nsmall = 2), expected$fit_size,
    sep = " / "
  )
  missing_key <- setdiff(expected_key, combo_key)
  if (length(missing_key)) {
    stop("Missing publication metric rows:\n", paste(head(missing_key, 12L), collapse = "\n"))
  }
  out
}

runtime_minutes <- function(model_key, inference, fit_size) {
  idx <- fit$model_key == model_key &
    fit$inference == inference &
    fit$fit_size == fit_size
  vals <- fit$runtime_sec[idx]
  vals <- vals[!is.na(vals)]
  if (length(vals) == 0) {
    return(NA_real_)
  }
  median(vals) / 60
}

format_runtime <- function(minutes) {
  if (is.na(minutes)) {
    return("--")
  }
  formatC(minutes, format = "f", digits = 1)
}

format_speedup <- function(vb_minutes, mcmc_minutes) {
  if (is.na(vb_minutes) || is.na(mcmc_minutes) || vb_minutes <= 0) {
    return("--")
  }
  paste0(formatC(mcmc_minutes / vb_minutes, format = "f", digits = 1), "\\(\\times\\)")
}

write_runtime_table <- function() {
  lines <- c(
    "\\begin{table}[t]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3pt}",
    "\\begin{tabular}{@{}lrrrrrrrr@{}}",
    "\\toprule",
    " & \\multicolumn{4}{c}{\\(T=500\\)} & \\multicolumn{4}{c}{\\(T=5000\\)} \\\\",
    "\\cmidrule(lr){2-5}\\cmidrule(l){6-9}",
    "Model & VB & MCMC & \\(\\Delta\\) & Speedup & VB & MCMC & \\(\\Delta\\) & Speedup \\\\",
    "\\midrule"
  )

  for (model_key in qdesn_model_order) {
    vb_500 <- runtime_minutes(model_key, "vb", 500)
    mcmc_500 <- runtime_minutes(model_key, "mcmc", 500)
    vb_5000 <- runtime_minutes(model_key, "vb", 5000)
    mcmc_5000 <- runtime_minutes(model_key, "mcmc", 5000)
    lines <- c(
      lines,
      sprintf(
        "%s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
        qdesn_model_label[[model_key]],
        format_runtime(vb_500),
        format_runtime(mcmc_500),
        format_runtime(mcmc_500 - vb_500),
        format_speedup(vb_500, mcmc_500),
        format_runtime(vb_5000),
        format_runtime(mcmc_5000),
        format_runtime(mcmc_5000 - vb_5000),
        format_speedup(vb_5000, mcmc_5000)
      )
    )
  }

  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}",
    "\\caption{Simulation study. Median runtime for the 144-fit validation grid, in minutes. The column \\(\\Delta\\) is MCMC minus VB runtime, and Speedup is the MCMC-to-VB runtime ratio; larger ratios indicate that VB is faster.}",
    "\\label{tab:simulation-runtime}",
    "\\end{table}"
  )

  writeLines(lines, file.path(output_dir, "qdesn_simulation_runtime.tex"), useBytes = TRUE)
}

publication_fit <- build_publication_metric_data()

write_metric_table(
  dat = publication_fit,
  metric = "train_qtrue_rmse",
  file_name = "qdesn_simulation_rmse.tex",
  caption = "\\caption{Simulation study. RMSE for the fitted conditional quantile path. Values compare VB and MCMC against the known target path on the post-washout training window. Boldface indicates the smallest RMSE among DQLM, exDQLM, and the four Q--DESN likelihood--prior specifications, across both inference methods, for the corresponding family, quantile level, and training size.}",
  label = "\\label{tab:simulation-rmse}",
  digits = 2
)

write_metric_table(
  dat = publication_fit,
  metric = "train_pinball_tau",
  file_name = "qdesn_simulation_pinball.tex",
  caption = "\\caption{Simulation study. Quantile check loss at the target quantile. Entries and boldface are defined as in Table~\\ref{tab:simulation-rmse}.}",
  label = "\\label{tab:simulation-checkloss}",
  digits = 2
)

write_runtime_table()

manifest <- c(
  paste0("generated_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("source_git_sha=", qdesn_source_git_sha),
  paste0("qdesn_run_tag=", qdesn_run_tag),
  paste0("qdesn_input_mode=", qdesn_input_mode),
  paste0("qdesn_recommendation=", qdesn_recommendation),
  paste0("analysis_root=", analysis_root),
  paste0("fit_summary_path=", fit_summary_path),
  paste0("qdesn_campaign_completed_path=", campaign_completed_path),
  paste0("qdesn_campaign_summary_manifest_path=", campaign_summary_manifest_path),
  paste0("qdesn_launch_manifest_path=", launch_manifest_path),
  paste0("qdesn_preflight_manifest_path=", preflight_manifest_path),
  paste0("exdqlm_validation_repo=", exdqlm_validation_repo),
  paste0("exdqlm_run_tag=", exdqlm_run_tag),
  paste0("exdqlm_input_mode=", if (exdqlm_uses_shared_interface) "shared_interface" else "legacy_comparison_with_plot_summaries"),
  paste0("exdqlm_shared_interface_path=", exdqlm_shared_interface_path),
  paste0("exdqlm_legacy_comparison_path=", exdqlm_legacy_comparison_path),
  paste0("exdqlm_plot_summary_dir=", exdqlm_plot_summary_dir),
  paste0("exdqlm_shared_interface_rows=", if (exdqlm_uses_shared_interface) nrow(exdqlm_shared_interface) else NA_integer_),
  paste0("exdqlm_shared_interface_git_sha=", exdqlm_shared_interface_git_sha),
  paste0("exdqlm_status_done_rows=", if (exdqlm_uses_shared_interface) sum(exdqlm_shared_interface$status == "done") else NA_integer_),
  paste0("exdqlm_signoff_pass_rows=", if (exdqlm_uses_shared_interface) sum(exdqlm_shared_interface$signoff_grade == "PASS") else NA_integer_),
  paste0("exdqlm_signoff_warn_rows=", if (exdqlm_uses_shared_interface) sum(exdqlm_shared_interface$signoff_grade == "WARN") else NA_integer_),
  paste0("exdqlm_signoff_fail_rows=", if (exdqlm_uses_shared_interface) sum(exdqlm_shared_interface$signoff_grade == "FAIL") else NA_integer_),
  paste0("fit_rows=", nrow(fit)),
  paste0("qdesn_status_success_rows=", if ("status" %in% names(fit)) sum(fit$status == "SUCCESS") else NA_integer_),
  paste0("qdesn_signoff_pass_rows=", if ("signoff_grade" %in% names(fit)) sum(fit$signoff_grade == "PASS") else NA_integer_),
  paste0("qdesn_signoff_warn_rows=", if ("signoff_grade" %in% names(fit)) sum(fit$signoff_grade == "WARN") else NA_integer_),
  paste0("qdesn_signoff_fail_rows=", if ("signoff_grade" %in% names(fit)) sum(fit$signoff_grade == "FAIL") else NA_integer_),
  paste0("publication_metric_rows=", nrow(publication_fit)),
  paste0("vb_rows=", sum(fit$inference == "vb")),
  paste0("mcmc_rows=", sum(fit$inference == "mcmc")),
  "output_files=qdesn_simulation_rmse.tex,qdesn_simulation_pinball.tex,qdesn_simulation_runtime.tex"
)
writeLines(manifest, file.path(output_dir, "qdesn_simulation_table_source_manifest.txt"), useBytes = TRUE)

message("Wrote Q-DESN simulation tables to ", output_dir)
