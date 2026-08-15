#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x) || !nzchar(as.character(x))) y else x
}

parse_args <- function(defaults) {
  args <- commandArgs(trailingOnly = TRUE)
  out <- defaults
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) {
      i <- i + 1L
      next
    }
    key <- sub("^--", "", key)
    nxt <- if (i < length(args)) args[[i + 1L]] else NULL
    if (!is.null(nxt) && !startsWith(nxt, "--")) {
      out[[key]] <- nxt
      i <- i + 2L
    } else {
      out[[key]] <- TRUE
      i <- i + 1L
    }
  }
  out
}

script_path <- {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
  } else {
    normalizePath(sys.frame(1)$ofile %||% "scripts/build_validation_tt500_current_comparison_table.R", mustWork = TRUE)
  }
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

default_exdqlm_interface <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/runs/20260515_exdqlm_dqlm_dynamic_fitforecast_v2_orchestrated_3500202605200353075941/interfaces/exdqlm_dqlm_dynamic_fitforecast_v2_shared_interface.csv"
default_qdesn_vb_summary <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-dynamic-fitforecast-v2-vb-full-20260520-035319__git-d075941/20260520-071231__git-d075941/tables/campaign_fit_summary.csv"
default_qdesn_mcmc_atomic <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/reports/qdesn_mcmc_validation/dynamic_fitforecast_v2_validation/qdesn-dynamic-fitforecast-v2-mcmc-tt500-20260520-035319__git-d075941/20260525-191523__git-d075941/provisional_progress/tt500_provisional_atomic_progress.csv"

args <- parse_args(list(
  fit_size = "500",
  source_registry_hash = "edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275",
  exdqlm_interface = default_exdqlm_interface,
  qdesn_vb_summary = default_qdesn_vb_summary,
  qdesn_mcmc_atomic = default_qdesn_mcmc_atomic,
  out_tex = file.path(repo_root, "tables/qdesn_validation_tt500_current_comparison.tex"),
  out_inference_tex = file.path(repo_root, "tables/qdesn_validation_tt500_inference_companion.tex"),
  out_csv = file.path(repo_root, "tables/qdesn_validation_tt500_current_comparison.csv"),
  out_manifest = file.path(repo_root, "tables/qdesn_validation_tt500_current_comparison_manifest.txt")
))

fit_size <- as.integer(args$fit_size)
if (is.na(fit_size) || fit_size <= 0L) {
  stop("--fit-size must be a positive integer.", call. = FALSE)
}

stop_if_missing <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf("Missing %s: %s", label, path), call. = FALSE)
  }
}

require_columns <- function(x, cols, label) {
  missing <- setdiff(cols, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
}

latex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x)
  x
}

fmt_num <- function(x) {
  if (is.na(x) || !is.finite(x)) return("--")
  formatC(as.numeric(x), format = "f", digits = 2)
}

fmt_metric <- function(x, is_best = FALSE) {
  out <- fmt_num(x)
  if (isTRUE(is_best) && !identical(out, "--")) {
    return(paste0("\\textbf{", out, "}"))
  }
  out
}

plain_family <- function(x) {
  labels <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "Gaussian mixture")
  unname(labels[as.character(x)] %||% as.character(x))
}

tex_family <- function(x) {
  labels <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "G. mix")
  unname(labels[as.character(x)] %||% as.character(x))
}

plain_inference <- function(x) {
  x <- tolower(as.character(x))
  if (identical(x, "vb")) "VB" else if (identical(x, "mcmc")) "MCMC" else x
}

qdesn_plain_model <- function(likelihood, prior) {
  like <- if (identical(as.character(likelihood), "exal")) "exAL" else "AL"
  pr <- if (identical(as.character(prior), "rhs_ns")) "RHS" else as.character(prior)
  paste0("Q-DESN ", like, "--", pr)
}

qdesn_tex_model <- function(likelihood, prior) {
  like <- if (identical(as.character(likelihood), "exal")) "\\(\\exAL\\)" else "\\(\\AL\\)"
  pr <- if (identical(as.character(prior), "rhs_ns")) "\\RHS{}" else latex_escape(prior)
  paste0("Q--DESN ", like, "--", pr)
}

baseline_plain_model <- function(model_variant) {
  if (identical(as.character(model_variant), "exdqlm")) "exDQLM" else "DQLM"
}

runtime_value <- function(...) {
  vals <- list(...)
  for (v in vals) {
    if (length(v) && !is.na(v) && is.finite(as.numeric(v))) return(as.numeric(v))
  }
  NA_real_
}

completion_gate <- function(state, gate, signoff, status) {
  state <- as.character(state %||% "")
  gate <- as.character(gate %||% "")
  signoff <- as.character(signoff %||% "")
  status <- as.character(status %||% "")
  if (!identical(tolower(state), "complete") && nzchar(state)) return(state)
  if (nzchar(signoff)) return(signoff)
  if (nzchar(gate)) return(gate)
  if (nzchar(status)) return(status)
  "complete"
}

extract_run_tag <- function(path) {
  parts <- strsplit(normalizePath(path, winslash = "/", mustWork = FALSE), "/", fixed = TRUE)[[1L]]
  hit <- grep("__git-", parts, value = TRUE)
  if (length(hit)) hit[[1L]] else NA_character_
}

extract_campaign_id <- function(path) {
  parts <- strsplit(normalizePath(path, winslash = "/", mustWork = FALSE), "/", fixed = TRUE)[[1L]]
  hit <- grep("^[0-9]{8}-[0-9]{6}__git-", parts, value = TRUE)
  if (length(hit)) hit[[1L]] else NA_character_
}

collapse_first_by_key <- function(x, keys) {
  key <- do.call(paste, c(x[keys], sep = "\r"))
  x[!duplicated(key), , drop = FALSE]
}

stop_if_missing(args$exdqlm_interface, "exDQLM/DQLM shared interface")
stop_if_missing(args$qdesn_vb_summary, "Q-DESN VB campaign summary")
stop_if_missing(args$qdesn_mcmc_atomic, "Q-DESN MCMC atomic progress table")

ex_path <- normalizePath(args$exdqlm_interface, winslash = "/", mustWork = TRUE)
qvb_path <- normalizePath(args$qdesn_vb_summary, winslash = "/", mustWork = TRUE)
qmcmc_path <- normalizePath(args$qdesn_mcmc_atomic, winslash = "/", mustWork = TRUE)

ex <- read.csv(ex_path, stringsAsFactors = FALSE, check.names = FALSE)
require_columns(
  ex,
  c(
    "family", "tau", "fit_size", "model_variant", "inference", "status", "health_gate",
    "source_registry_hash_value", "fit_qtrue_rmse", "fit_pinball_mean",
    "forecast_h100_q_rmse", "forecast_h100_pinball_mean",
    "forecast_h1000_q_rmse", "forecast_h1000_pinball_mean",
    "runtime_sec", "runtime_sec_total", "run_tag", "validation_commit", "package_version"
  ),
  "exDQLM/DQLM shared interface"
)
ex <- ex[as.integer(ex$fit_size) == fit_size, , drop = FALSE]
if (nrow(ex) == 0L) stop("No exDQLM/DQLM rows found for fit_size=", fit_size, call. = FALSE)
if (any(ex$source_registry_hash_value != args$source_registry_hash)) {
  stop("exDQLM/DQLM source registry hash does not match expected shared hash.", call. = FALSE)
}
ex <- collapse_first_by_key(ex, c("family", "tau", "fit_size", "model_variant", "inference"))
ex_rows <- data.frame(
  family = ex$family,
  family_label = vapply(ex$family, plain_family, character(1L)),
  family_tex = vapply(ex$family, tex_family, character(1L)),
  tau = as.numeric(ex$tau),
  fit_size = as.integer(ex$fit_size),
  model_family = "exdqlm_dqlm",
  model_variant = ex$model_variant,
  model = vapply(ex$model_variant, baseline_plain_model, character(1L)),
  model_tex = vapply(ex$model_variant, baseline_plain_model, character(1L)),
  inference = vapply(ex$inference, plain_inference, character(1L)),
  completion_state = "complete",
  gate = mapply(completion_gate, "complete", ex$health_gate, ex$signoff_grade, ex$status, USE.NAMES = FALSE),
  fit_rmse = as.numeric(ex$fit_qtrue_rmse),
  fit_pinball = as.numeric(ex$fit_pinball_mean),
  f100_rmse = as.numeric(ex$forecast_h100_q_rmse),
  f100_pinball = as.numeric(ex$forecast_h100_pinball_mean),
  f1000_rmse = as.numeric(ex$forecast_h1000_q_rmse),
  f1000_pinball = as.numeric(ex$forecast_h1000_pinball_mean),
  runtime_sec = mapply(runtime_value, ex$runtime_sec_total, ex$runtime_sec),
  source_table = "exdqlm_dqlm_shared_interface",
  run_tag = ex$run_tag,
  campaign_id = basename(dirname(dirname(ex_path))),
  validation_commit = ex$validation_commit,
  package_version = ex$package_version,
  source_registry_hash_value = ex$source_registry_hash_value,
  stringsAsFactors = FALSE
)

qvb <- read.csv(qvb_path, stringsAsFactors = FALSE, check.names = FALSE)
require_columns(
  qvb,
  c(
    "family", "tau", "fit_size", "prior", "likelihood_family", "inference", "status",
    "signoff_grade", "train_qtrue_rmse", "train_pinball_tau", "runtime_sec",
    "forecast_rolling_origin_path_file"
  ),
  "Q-DESN VB campaign summary"
)
qvb <- qvb[as.integer(qvb$fit_size) == fit_size, , drop = FALSE]
if (nrow(qvb) == 0L) stop("No Q-DESN VB rows found for fit_size=", fit_size, call. = FALSE)
qvb_rows <- data.frame(
  family = qvb$family,
  family_label = vapply(qvb$family, plain_family, character(1L)),
  family_tex = vapply(qvb$family, tex_family, character(1L)),
  tau = as.numeric(qvb$tau),
  fit_size = as.integer(qvb$fit_size),
  model_family = "qdesn",
  model_variant = paste0("qdesn_", qvb$likelihood_family, "_", qvb$prior),
  model = mapply(qdesn_plain_model, qvb$likelihood_family, qvb$prior, USE.NAMES = FALSE),
  model_tex = mapply(qdesn_tex_model, qvb$likelihood_family, qvb$prior, USE.NAMES = FALSE),
  inference = vapply(qvb$inference, plain_inference, character(1L)),
  completion_state = "complete",
  gate = mapply(completion_gate, "complete", "", qvb$signoff_grade, qvb$status, USE.NAMES = FALSE),
  fit_rmse = as.numeric(qvb$train_qtrue_rmse),
  fit_pinball = as.numeric(qvb$train_pinball_tau),
  f100_rmse = NA_real_,
  f100_pinball = NA_real_,
  f1000_rmse = NA_real_,
  f1000_pinball = NA_real_,
  runtime_sec = as.numeric(qvb$runtime_sec),
  source_table = "qdesn_vb_campaign_summary_with_rolling_path_sidecars",
  run_tag = extract_run_tag(qvb_path),
  campaign_id = extract_campaign_id(qvb_path),
  validation_commit = "d075941313186b15853e94c2a2cad7d0fec410d8",
  package_version = "1.0.0",
  source_registry_hash_value = args$source_registry_hash,
  stringsAsFactors = FALSE
)
qvb_rows$gate <- paste0(qvb_rows$gate, "/fit")

qmcmc <- read.csv(qmcmc_path, stringsAsFactors = FALSE, check.names = FALSE)
require_columns(
  qmcmc,
  c(
    "family", "tau", "fit_size", "prior", "likelihood_family", "completion_state",
    "status", "signoff_grade", "source_registry_hash_value", "train_qtrue_rmse",
    "train_pinball_tau", "forecast_h100_qtrue_rmse", "forecast_h100_pinball_tau",
    "forecast_h1000_qtrue_rmse", "forecast_h1000_pinball_tau", "runtime_sec",
    "run_tag", "campaign_id", "validation_commit", "package_version"
  ),
  "Q-DESN MCMC atomic progress table"
)
qmcmc <- qmcmc[as.integer(qmcmc$fit_size) == fit_size, , drop = FALSE]
if (nrow(qmcmc) == 0L) stop("No Q-DESN MCMC rows found for fit_size=", fit_size, call. = FALSE)
if (any(qmcmc$source_registry_hash_value != args$source_registry_hash)) {
  stop("Q-DESN MCMC source registry hash does not match expected shared hash.", call. = FALSE)
}
qmcmc_complete <- identical(qmcmc$completion_state, "complete")
qmcmc_rows <- data.frame(
  family = qmcmc$family,
  family_label = vapply(qmcmc$family, plain_family, character(1L)),
  family_tex = vapply(qmcmc$family, tex_family, character(1L)),
  tau = as.numeric(qmcmc$tau),
  fit_size = as.integer(qmcmc$fit_size),
  model_family = "qdesn",
  model_variant = paste0("qdesn_", qmcmc$likelihood_family, "_", qmcmc$prior),
  model = mapply(qdesn_plain_model, qmcmc$likelihood_family, qmcmc$prior, USE.NAMES = FALSE),
  model_tex = mapply(qdesn_tex_model, qmcmc$likelihood_family, qmcmc$prior, USE.NAMES = FALSE),
  inference = "MCMC",
  completion_state = qmcmc$completion_state,
  gate = mapply(completion_gate, qmcmc$completion_state, "", qmcmc$signoff_grade, qmcmc$status, USE.NAMES = FALSE),
  fit_rmse = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$train_qtrue_rmse), NA_real_),
  fit_pinball = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$train_pinball_tau), NA_real_),
  f100_rmse = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$forecast_h100_qtrue_rmse), NA_real_),
  f100_pinball = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$forecast_h100_pinball_tau), NA_real_),
  f1000_rmse = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$forecast_h1000_qtrue_rmse), NA_real_),
  f1000_pinball = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$forecast_h1000_pinball_tau), NA_real_),
  runtime_sec = ifelse(qmcmc$completion_state == "complete", as.numeric(qmcmc$runtime_sec), NA_real_),
  source_table = "qdesn_mcmc_atomic_progress",
  run_tag = qmcmc$run_tag,
  campaign_id = qmcmc$campaign_id,
  validation_commit = qmcmc$validation_commit,
  package_version = qmcmc$package_version,
  source_registry_hash_value = qmcmc$source_registry_hash_value,
  stringsAsFactors = FALSE
)

all_rows <- rbind(ex_rows, qvb_rows, qmcmc_rows)

model_order <- c(
  "DQLM",
  "exDQLM",
  "Q-DESN AL--ridge",
  "Q-DESN exAL--ridge",
  "Q-DESN AL--RHS",
  "Q-DESN exAL--RHS"
)
family_order <- c("normal", "laplace", "gausmix")
inference_order <- c("VB", "MCMC")
ord <- order(
  match(all_rows$family, family_order),
  all_rows$tau,
  match(all_rows$model, model_order),
  match(all_rows$inference, inference_order)
)
all_rows <- all_rows[ord, , drop = FALSE]

dir.create(dirname(args$out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(all_rows, args$out_csv, row.names = FALSE, na = "")

best_flags <- function(rows) {
  metric_cols <- c(
    "fit_rmse",
    "fit_pinball",
    "f100_rmse",
    "f100_pinball",
    "f1000_rmse",
    "f1000_pinball"
  )
  flags <- matrix(FALSE, nrow = nrow(rows), ncol = length(metric_cols))
  colnames(flags) <- metric_cols
  for (metric in metric_cols) {
    values <- as.numeric(rows[[metric]])
    finite <- is.finite(values)
    if (any(finite)) {
      rounded_values <- round(values, 2)
      flags[, metric] <- finite & rounded_values == min(rounded_values[finite])
    }
  }
  flags
}

row_line <- function(r, bold, include_inference = TRUE) {
  prefix <- r$model_tex
  if (isTRUE(include_inference)) {
    prefix <- paste(prefix, latex_escape(r$inference), sep = " & ")
  }
  if (!identical(as.character(r$completion_state), "complete")) {
    return(sprintf(
      "%s & \\multicolumn{6}{c}{\\emph{%s}} \\\\",
      prefix,
      latex_escape(r$completion_state)
    ))
  }
  if (!is.finite(r$f100_rmse) || !is.finite(r$f1000_rmse)) {
    return(sprintf(
      "%s & %s & %s & \\multicolumn{4}{c}{\\emph{forecast not exported}} \\\\",
      prefix,
      fmt_metric(r$fit_rmse, bold[["fit_rmse"]]),
      fmt_metric(r$fit_pinball, bold[["fit_pinball"]])
    ))
  }
  sprintf(
    "%s & %s & %s & %s & %s & %s & %s \\\\",
    prefix,
    fmt_metric(r$fit_rmse, bold[["fit_rmse"]]),
    fmt_metric(r$fit_pinball, bold[["fit_pinball"]]),
    fmt_metric(r$f100_rmse, bold[["f100_rmse"]]),
    fmt_metric(r$f100_pinball, bold[["f100_pinball"]]),
    fmt_metric(r$f1000_rmse, bold[["f1000_rmse"]]),
    fmt_metric(r$f1000_pinball, bold[["f1000_pinball"]])
  )
}

family_table <- function(rows, family_key, family_title, label) {
  rows <- rows[rows$family == family_key, , drop = FALSE]
  if (!nrow(rows)) stop("No rows found for family: ", family_key, call. = FALSE)
  out <- c(
    "\\begin{table}[H]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3pt}",
    "\\renewcommand{\\arraystretch}{1.04}",
    sprintf(
      "\\caption{Current %d-observation simulation results for %s errors. Rows are grouped by target quantile; lower RMSE and check-loss values are better.}",
      fit_size,
      family_title
    ),
    sprintf("\\label{%s}", label),
    "\\begin{tabular}{@{}llrrrrrr@{}}",
    "\\toprule",
    "Model & Inf. & \\multicolumn{2}{c}{Fit} & \\multicolumn{2}{c}{F100} & \\multicolumn{2}{c}{F1000} \\\\",
    "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}",
    " & & RMSE & CL & RMSE & CL & RMSE & CL \\\\",
    "\\midrule"
  )
  for (tau_value in sort(unique(rows$tau))) {
    if (!identical(tau_value, sort(unique(rows$tau))[[1L]])) {
      out <- c(out, "\\addlinespace[0.25em]")
    }
    out <- c(out, sprintf("\\multicolumn{8}{@{}l}{\\emph{$\\tau = %.2f$}}\\\\", tau_value))
    tau_rows <- rows[rows$tau == tau_value, , drop = FALSE]
    tau_best <- best_flags(tau_rows)
    for (i in seq_len(nrow(tau_rows))) {
      out <- c(out, row_line(tau_rows[i, , drop = FALSE], tau_best[i, ], include_inference = TRUE))
    }
  }
  c(
    out,
    "\\bottomrule",
    "\\end{tabular}",
    "\\par\\vspace{0.35em}",
    "\\begin{minipage}{0.97\\textwidth}\\footnotesize",
    "\\emph{Note.} Fit metrics use the 500-observation training window. F100 and F1000 summarize rolling-origin forecasts over held-out forecast windows of length 100 and 1000, respectively, using maximum lead \\(H_{\\max}=30\\) and origin stride 30. CL denotes check loss. Boldface marks the lowest reported value within each quantile block and metric column. Q--DESN VB rows report fit metrics only because comparable forecast metrics have not yet been exported through the shared interface; running and pending rows are placeholders.",
    "\\end{minipage}",
    "\\end{table}"
  )
}

inference_table <- function(rows, inference_value, inference_title, label) {
  rows <- rows[rows$inference == inference_value, , drop = FALSE]
  if (!nrow(rows)) stop("No rows found for inference: ", inference_value, call. = FALSE)
  out <- c(
    "\\begingroup",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3pt}",
    "\\renewcommand{\\arraystretch}{1.04}",
    "\\begin{longtable}{@{}lrrrrrr@{}}",
    sprintf(
      "\\caption{Current %d-observation simulation results for %s inference. Rows are grouped by error family and target quantile; lower RMSE and check-loss values are better.}",
      fit_size,
      inference_title
    ),
    sprintf("\\label{%s}\\\\", label),
    "\\toprule",
    "Model & \\multicolumn{2}{c}{Fit} & \\multicolumn{2}{c}{F100} & \\multicolumn{2}{c}{F1000} \\\\",
    "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}",
    " & RMSE & CL & RMSE & CL & RMSE & CL \\\\",
    "\\midrule",
    "\\endfirsthead",
    "\\multicolumn{7}{@{}l}{\\footnotesize\\emph{Table~\\thetable{} continued.}}\\\\",
    "\\toprule",
    "Model & \\multicolumn{2}{c}{Fit} & \\multicolumn{2}{c}{F100} & \\multicolumn{2}{c}{F1000} \\\\",
    "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}",
    " & RMSE & CL & RMSE & CL & RMSE & CL \\\\",
    "\\midrule",
    "\\endhead",
    "\\midrule",
    "\\multicolumn{7}{r@{}}{\\footnotesize\\emph{Continued on next page.}}\\\\",
    "\\endfoot",
    "\\bottomrule",
    "\\endlastfoot"
  )
  first_group <- TRUE
  for (family_key in family_order) {
    family_rows <- rows[rows$family == family_key, , drop = FALSE]
    if (!nrow(family_rows)) next
    for (tau_value in sort(unique(family_rows$tau))) {
      if (!isTRUE(first_group)) {
        out <- c(out, "\\addlinespace[0.25em]")
      }
      first_group <- FALSE
      tau_rows <- family_rows[family_rows$tau == tau_value, , drop = FALSE]
      tau_best <- best_flags(tau_rows)
      out <- c(
        out,
        sprintf(
          "\\multicolumn{7}{@{}l}{\\emph{%s errors, $\\tau = %.2f$}}\\\\",
          unique(tau_rows$family_label)[[1L]],
          tau_value
        )
      )
      for (i in seq_len(nrow(tau_rows))) {
        out <- c(out, row_line(tau_rows[i, , drop = FALSE], tau_best[i, ], include_inference = FALSE))
      }
    }
  }
  c(
    out,
    "\\end{longtable}",
    "\\par\\noindent\\begin{minipage}{0.97\\textwidth}\\footnotesize",
    "\\emph{Note.} Fit metrics use the 500-observation training window. F100 and F1000 summarize rolling-origin forecasts over held-out forecast windows of length 100 and 1000, respectively, using maximum lead \\(H_{\\max}=30\\) and origin stride 30. CL denotes check loss. Boldface marks the lowest reported value within each error-family, quantile, and metric column for this inference method. Rows with unavailable forecast metrics or unfinished fits are displayed as placeholders.",
    "\\end{minipage}",
    "\\par\\endgroup"
  )
}

tex <- c(
  "% Generated by scripts/build_validation_tt500_current_comparison_table.R.",
  "% Primary manuscript comparison tables; rerun after validation refresh.",
  family_table(all_rows, "normal", "Gaussian", "tab:simulation-current-normal"),
  "",
  family_table(all_rows, "laplace", "Laplace", "tab:simulation-current-laplace"),
  "",
  family_table(all_rows, "gausmix", "Gaussian mixture", "tab:simulation-current-gausmix")
)

inference_tex <- c(
  "% Generated by scripts/build_validation_tt500_current_comparison_table.R.",
  "% Companion inference-stratified views; not included in main manuscript by default.",
  "% Requires \\usepackage{longtable} if included in the manuscript.",
  inference_table(all_rows, "VB", "VB", "tab:simulation-current-vb"),
  "",
  inference_table(all_rows, "MCMC", "MCMC", "tab:simulation-current-mcmc")
)

dir.create(dirname(args$out_tex), recursive = TRUE, showWarnings = FALSE)
writeLines(tex, args$out_tex, useBytes = TRUE)
dir.create(dirname(args$out_inference_tex), recursive = TRUE, showWarnings = FALSE)
writeLines(inference_tex, args$out_inference_tex, useBytes = TRUE)

manifest <- c(
  "Current TT500 validation comparison table manifest",
  sprintf("Generated at: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "Builder: scripts/build_validation_tt500_current_comparison_table.R",
  sprintf("Fit size: %d", fit_size),
  sprintf("Expected source registry hash: %s", args$source_registry_hash),
  sprintf("exDQLM/DQLM input: %s", ex_path),
  sprintf("exDQLM/DQLM input SHA-256: %s", unname(tools::sha256sum(ex_path))),
  sprintf("Q-DESN VB input: %s", qvb_path),
  sprintf("Q-DESN VB input SHA-256: %s", unname(tools::sha256sum(qvb_path))),
  sprintf("Q-DESN MCMC input: %s", qmcmc_path),
  sprintf("Q-DESN MCMC input SHA-256: %s", unname(tools::sha256sum(qmcmc_path))),
  sprintf("Output TeX: %s", normalizePath(args$out_tex, winslash = "/", mustWork = TRUE)),
  sprintf("Output inference companion TeX: %s", normalizePath(args$out_inference_tex, winslash = "/", mustWork = TRUE)),
  sprintf("Output CSV: %s", normalizePath(args$out_csv, winslash = "/", mustWork = TRUE)),
  sprintf("Output TeX SHA-256: %s", unname(tools::sha256sum(args$out_tex))),
  sprintf("Output inference companion TeX SHA-256: %s", unname(tools::sha256sum(args$out_inference_tex))),
  sprintf("Output CSV SHA-256: %s", unname(tools::sha256sum(args$out_csv))),
  sprintf("Rows total: %d", nrow(all_rows)),
  sprintf("Rows complete: %d", sum(all_rows$completion_state == "complete")),
  sprintf("Rows running: %d", sum(all_rows$completion_state == "running")),
  sprintf("Rows pending: %d", sum(all_rows$completion_state == "pending")),
  sprintf("Rows with missing forecast metrics: %d", sum(!is.finite(all_rows$f100_rmse) | !is.finite(all_rows$f1000_rmse))),
  sprintf("Rows by source: %s", paste(names(table(all_rows$source_table)), as.integer(table(all_rows$source_table)), sep = "=", collapse = "; ")),
  "Presentation: three primary manuscript tables by error family; two inference-stratified companion longtables are generated separately to avoid duplicating the main numerical comparison.",
  "Primary table labels: tab:simulation-tt500-normal; tab:simulation-tt500-laplace; tab:simulation-tt500-gausmix",
  "Companion table labels: tab:simulation-tt500-vb; tab:simulation-tt500-mcmc",
  "Column groups: Fit RMSE/PB; F100 RMSE/PB; F1000 RMSE/PB.",
  "Table highlight rule: boldface marks the lowest reported value within each family, quantile, and metric column; ties after two-decimal rounding are all highlighted.",
  sprintf("Source registry hashes in output: %s", paste(sort(unique(all_rows$source_registry_hash_value)), collapse = ", ")),
  sprintf("Validation commits in output: %s", paste(sort(unique(all_rows$validation_commit)), collapse = ", ")),
  sprintf("Package versions in output: %s", paste(sort(unique(all_rows$package_version)), collapse = ", ")),
  sprintf("Run tags in output: %s", paste(sort(unique(all_rows$run_tag)), collapse = "; ")),
  "Policy: current article-facing comparison snapshot with explicit incomplete-row placeholders.",
  "Refresh rule: rerun this builder after validation finalizes or when adding TT100/other fit-size cases."
)
writeLines(manifest, args$out_manifest, useBytes = TRUE)

cat("Current TT500 validation comparison table built.\n")
cat(sprintf("rows: %d\n", nrow(all_rows)))
cat(sprintf("complete: %d\n", sum(all_rows$completion_state == "complete")))
cat(sprintf("running: %d\n", sum(all_rows$completion_state == "running")))
cat(sprintf("pending: %d\n", sum(all_rows$completion_state == "pending")))
cat(sprintf("tex: %s\n", normalizePath(args$out_tex, winslash = "/", mustWork = TRUE)))
cat(sprintf("inference companion tex: %s\n", normalizePath(args$out_inference_tex, winslash = "/", mustWork = TRUE)))
