#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- which(args == flag)
  if (!length(at) || at[[1L]] == length(args)) return(default)
  args[[at[[1L]] + 1L]]
}

config_path <- normalizePath(
  arg_value("--config", file.path(
    repo_root, "application", "config",
    "independent_validation_dgp_oracle_figures_v13.yaml"
  )), winslash = "/", mustWork = TRUE
)
config <- yaml::read_yaml(config_path)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
verify_hash <- function(path, expected, label) {
  if (!file.exists(path) || !identical(sha256(path), as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
  invisible(path)
}
resolve_from_repo <- function(path) {
  path <- as.character(path)[1L]
  if (!grepl("^/", path)) path <- file.path(repo_root, path)
  path
}
article_path <- function(relative, must_work = FALSE) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("An article path is not portable.", call. = FALSE)
  }
  path <- file.path(repo_root, relative)
  if (must_work) return(normalizePath(path, winslash = "/", mustWork = TRUE))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}
relative_article <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(path, prefix)) stop("An output escapes the article repository.", call. = FALSE)
  substring(path, nchar(prefix) + 1L)
}
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")

if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("scales", quietly = TRUE) ||
    !requireNamespace("png", quietly = TRUE) ||
    !requireNamespace("yaml", quietly = TRUE)) {
  stop("yaml, ggplot2, png, and scales are required.", call. = FALSE)
}

ancestor_status <- system2(
  "git", c("-C", repo_root, "merge-base", "--is-ancestor",
           as.character(config$article_minimum_commit), "HEAD")
)
if (!identical(ancestor_status, 0L)) {
  stop("The required article baseline is not an ancestor of HEAD.", call. = FALSE)
}

validation_root <- normalizePath(
  resolve_from_repo(arg_value(
    "--validation-root",
    Sys.getenv("QDESN_VALIDATION_ROOT", unset = config$validation_root)
  )), winslash = "/", mustWork = TRUE
)
validation_head <- system2(
  "git", c("-C", validation_root, "rev-parse", "HEAD"), stdout = TRUE
)
if (!identical(as.character(validation_head), as.character(config$validation_authority_commit))) {
  stop("The validation worktree is not at the frozen oracle authority.", call. = FALSE)
}
oracle_source <- normalizePath(
  file.path(validation_root, config$oracle$relative_path), winslash = "/", mustWork = TRUE
)
if (!startsWith(oracle_source, paste0(validation_root, "/"))) {
  stop("The oracle source escapes the validation worktree.", call. = FALSE)
}
verify_hash(oracle_source, config$oracle$sha256, "validation oracle asset")

interval_path <- article_path(config$inputs$interval_summary, must_work = TRUE)
verify_hash(interval_path, config$inputs$interval_summary_sha256, "v12 interval summary")
oracle_asset_path <- article_path(config$outputs$oracle_asset)
if (!isTRUE(file.copy(oracle_source, oracle_asset_path, overwrite = TRUE, copy.mode = FALSE))) {
  stop("Could not project the oracle asset into the article repository.", call. = FALSE)
}
verify_hash(oracle_asset_path, config$oracle$sha256, "projected oracle asset")

interval <- read.csv(interval_path, check.names = FALSE)
oracle <- read.csv(oracle_asset_path, check.names = FALSE)
expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference_levels <- unlist(expected$inference, use.names = FALSE)
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)
render_inference_arg <- arg_value("--inference", "all")
render_role_arg <- arg_value("--metric-role", "all")
if (!render_inference_arg %in% c("all", inference_levels) ||
    !render_role_arg %in% c("all", metric_roles)) {
  stop("Unknown --inference or --metric-role render selector.", call. = FALSE)
}
render_inference_levels <- if (render_inference_arg == "all") {
  inference_levels
} else {
  render_inference_arg
}
render_metric_roles <- if (render_role_arg == "all") metric_roles else render_role_arg

required_interval <- c(
  "inference", "model_variant", "model_label", "family", "tau",
  "fit_qtrue_rmse", "fit_cri_lower", "fit_posterior_median", "fit_cri_upper",
  "fit_n_draws", "fit_n_chains", "fit_diagnostic_grade", "fit_replay_id",
  "forecast_qtrue_mae_H1000", "forecast_mae_cri_lower",
  "forecast_mae_posterior_median", "forecast_mae_cri_upper",
  "forecast_mae_n_draws", "forecast_mae_n_chains",
  "forecast_mae_diagnostic_grade", "forecast_mae_replay_id",
  "forecast_check_loss_H1000", "forecast_check_cri_lower",
  "forecast_check_posterior_median", "forecast_check_cri_upper",
  "forecast_check_n_draws", "forecast_check_n_chains",
  "forecast_check_diagnostic_grade", "forecast_check_replay_id"
)
if (!all(required_interval %in% names(interval)) ||
    nrow(interval) != as.integer(expected$interval_rows)) {
  stop("The v12 interval summary does not satisfy the frozen contract.", call. = FALSE)
}
interval_key <- with(
  interval, paste(inference, model_variant, family, sprintf("%.2f", tau), sep = "|")
)
if (anyDuplicated(interval_key) ||
    !setequal(unique(interval$model_variant), models) ||
    !setequal(unique(interval$family), families) ||
    !setequal(unique(interval$inference), inference_levels) ||
    !setequal(unique(interval$tau), taus)) {
  stop("The v12 interval summary has an unexpected analysis surface.", call. = FALSE)
}

role_contract <- list(
  fit_rmse = c(
    mean = "fit_qtrue_rmse", lower = "fit_cri_lower",
    median = "fit_posterior_median", upper = "fit_cri_upper",
    n_draws = "fit_n_draws", n_chains = "fit_n_chains",
    grade = "fit_diagnostic_grade", replay = "fit_replay_id"
  ),
  forecast_mae = c(
    mean = "forecast_qtrue_mae_H1000", lower = "forecast_mae_cri_lower",
    median = "forecast_mae_posterior_median", upper = "forecast_mae_cri_upper",
    n_draws = "forecast_mae_n_draws", n_chains = "forecast_mae_n_chains",
    grade = "forecast_mae_diagnostic_grade", replay = "forecast_mae_replay_id"
  ),
  forecast_check = c(
    mean = "forecast_check_loss_H1000", lower = "forecast_check_cri_lower",
    median = "forecast_check_posterior_median", upper = "forecast_check_cri_upper",
    n_draws = "forecast_check_n_draws", n_chains = "forecast_check_n_chains",
    grade = "forecast_check_diagnostic_grade", replay = "forecast_check_replay_id"
  )
)
figure_blocks <- lapply(metric_roles, function(role) {
  spec <- role_contract[[role]]
  data.frame(
    inference = interval$inference,
    model_variant = interval$model_variant,
    model_label = interval$model_label,
    family = interval$family,
    tau = interval$tau,
    metric_role = role,
    posterior_mean = as.numeric(interval[[spec[["mean"]]]]),
    cri_lower = as.numeric(interval[[spec[["lower"]]]]),
    posterior_median = as.numeric(interval[[spec[["median"]]]]),
    cri_upper = as.numeric(interval[[spec[["upper"]]]]),
    n_draws = as.integer(interval[[spec[["n_draws"]]]]),
    n_chains = as.integer(interval[[spec[["n_chains"]]]]),
    diagnostic_grade = as.character(interval[[spec[["grade"]]]]),
    replay_id = as.character(interval[[spec[["replay"]]]]),
    stringsAsFactors = FALSE
  )
})
figure_data <- do.call(rbind, figure_blocks)
figure_data <- figure_data[order(
  match(figure_data$inference, inference_levels),
  match(figure_data$metric_role, metric_roles),
  match(figure_data$family, families), figure_data$tau,
  match(figure_data$model_variant, models)
), , drop = FALSE]
row.names(figure_data) <- NULL
figure_key <- with(
  figure_data,
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role, sep = "|")
)
if (nrow(figure_data) != as.integer(expected$figure_rows) || anyDuplicated(figure_key) ||
    any(!is.finite(unlist(figure_data[c(
      "posterior_mean", "cri_lower", "posterior_median", "cri_upper"
    )]))) || any(figure_data$cri_lower > figure_data$posterior_mean) ||
    any(figure_data$posterior_mean > figure_data$cri_upper)) {
  stop("The expanded interval figure data failed validation.", call. = FALSE)
}

required_oracle <- c(
  "family", "tau", "metric_role", "metric_name", "plot_reference_type",
  "plot_reference_value", "expected_reference_value", "realized_reference_value",
  "formula", "source_series_sha256", "forecast_origins", "forecast_pairs"
)
oracle_key <- with(oracle, paste(family, sprintf("%.2f", tau), metric_role, sep = "|"))
if (!all(required_oracle %in% names(oracle)) ||
    nrow(oracle) != as.integer(expected$oracle_rows) || anyDuplicated(oracle_key) ||
    !setequal(unique(oracle$family), families) ||
    !setequal(unique(oracle$tau), taus) ||
    !setequal(unique(oracle$metric_role), metric_roles) ||
    any(!is.finite(oracle$plot_reference_value)) ||
    any(oracle$plot_reference_value < 0) ||
    any(oracle$plot_reference_value[oracle$metric_role != "forecast_check"] != 0) ||
    any(oracle$plot_reference_value[oracle$metric_role == "forecast_check"] <= 0) ||
    any(oracle$forecast_origins != 34L) || any(oracle$forecast_pairs != 1000L)) {
  stop("The DGP oracle asset failed its article projection contract.", call. = FALSE)
}

join_key <- with(
  figure_data, paste(family, sprintf("%.2f", tau), metric_role, sep = "|")
)
at <- match(join_key, oracle_key)
if (anyNA(at)) stop("An interval figure cell has no DGP oracle reference.", call. = FALSE)
for (name in setdiff(required_oracle, c("family", "tau", "metric_role"))) {
  figure_data[[name]] <- oracle[[name]][at]
}
figure_data_path <- article_path(config$outputs$figure_data)
write_csv(figure_data, figure_data_path)

render_article_pdf <- function(filename, plot, width = 7.2, height = 6.6, dpi = 300L) {
  if (!isTRUE(capabilities("cairo"))) {
    stop("Cairo graphics support is required for stable article figures.", call. = FALSE)
  }
  raster_path <- tempfile(pattern = "qdesn-v13-", fileext = ".png")
  on.exit(unlink(raster_path), add = TRUE)
  grDevices::png(
    filename = raster_path, width = round(width * dpi), height = round(height * dpi),
    units = "px", res = dpi, type = "cairo", bg = "white"
  )
  print(plot)
  grDevices::dev.off()
  image <- png::readPNG(raster_path)
  grDevices::pdf(
    file = filename, width = width, height = height, bg = "white",
    useDingbats = FALSE, onefile = TRUE, compress = TRUE
  )
  grid::grid.newpage()
  grid::grid.raster(
    image, x = 0.5, y = 0.5, width = grid::unit(1, "npc"),
    height = grid::unit(1, "npc"), interpolate = FALSE
  )
  grDevices::dev.off()
  invisible(filename)
}

model_labels <- c(
  dqlm = "DQLM", exdqlm = "exDQLM",
  qdesn_al_rhs_ns = "Q-DESN AL-RHS",
  qdesn_exal_rhs_ns = "Q-DESN exAL-RHS"
)
family_labels <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "Gaussian mixture")
metric_labels <- c(
  fit_rmse = "Fit RMSE", forecast_mae = "Forecast MAE",
  forecast_check = "Forecast check loss"
)
metric_files <- c(
  fit_rmse = "fit_rmse", forecast_mae = "forecast_mae",
  forecast_check = "forecast_check_loss"
)
metric_label_ids <- c(
  fit_rmse = "fit-rmse", forecast_mae = "forecast-mae",
  forecast_check = "forecast-check-loss"
)
metric_caption_labels <- c(
  fit_rmse = "fit RMSE", forecast_mae = "forecast MAE",
  forecast_check = "forecast check loss"
)
figure_data$model_label_plot <- factor(
  unname(model_labels[figure_data$model_variant]), levels = rev(unname(model_labels[models]))
)
figure_data$panel_label_plot <- factor(
  paste(unname(family_labels[figure_data$family]),
        sprintf("p = %.2f", figure_data$tau), sep = "\n"),
  levels = unlist(lapply(unname(family_labels[families]), function(family) {
    paste(family, sprintf("p = %.2f", taus), sep = "\n")
  }), use.names = FALSE)
)

interval_plot <- function(inference, role) {
  block <- figure_data[
    figure_data$inference == inference & figure_data$metric_role == role, , drop = FALSE
  ]
  references <- unique(block[c("panel_label_plot", "plot_reference_value")])
  reference_text <- if (role == "forecast_check") {
    "Black dashed line: population expected DGP oracle check loss"
  } else {
    "Black dashed line: exact DGP oracle path error (0)"
  }
  ggplot2::ggplot(
    block, ggplot2::aes(
      x = posterior_mean, y = model_label_plot, xmin = cri_lower, xmax = cri_upper,
      colour = model_variant
    )
  ) +
    ggplot2::geom_vline(
      data = references, ggplot2::aes(xintercept = plot_reference_value),
      inherit.aes = FALSE, colour = "black", linetype = "dashed", linewidth = 0.55
    ) +
    ggplot2::geom_errorbar(orientation = "y", width = 0.18, linewidth = 0.72) +
    ggplot2::geom_point(shape = 4, size = 2.8, stroke = 1.05) +
    ggplot2::facet_wrap(~panel_label_plot, ncol = 3L, scales = "free_x") +
    ggplot2::scale_colour_manual(
      values = c(
        dqlm = "#0072B2", exdqlm = "#56B4E9",
        qdesn_al_rhs_ns = "#D55E00", qdesn_exal_rhs_ns = "#009E73"
      ),
      breaks = models, labels = unname(model_labels[models]), drop = FALSE
    ) +
    ggplot2::scale_x_continuous(
      expand = ggplot2::expansion(mult = c(0.04, 0.06)),
      breaks = scales::breaks_pretty(n = 4L),
      labels = function(x) sprintf("%.2f", x),
      guide = ggplot2::guide_axis(check.overlap = TRUE)
    ) +
    ggplot2::labs(
      title = sprintf(
        "%s: %s", if (inference == "mcmc") "MCMC" else "Variational Bayes",
        metric_labels[[role]]
      ),
      subtitle = paste0(
        if (inference == "mcmc") {
          "Posterior mean (x) and equal-tailed 95% credible interval."
        } else {
          "Variational posterior mean (x) and equal-tailed approximate 95% interval."
        },
        "\n", reference_text
      ),
      x = metric_labels[[role]], y = NULL, colour = NULL
    ) +
    ggplot2::theme_minimal(base_size = 9.5, base_family = "sans") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 11.5),
      plot.subtitle = ggplot2::element_text(size = 8.6, colour = "#333333"),
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(colour = "#E3E3E3", linewidth = 0.3),
      strip.text = ggplot2::element_text(face = "bold", size = 8.6, lineheight = 0.95),
      strip.background = ggplot2::element_rect(
        fill = "#F3F3F3", colour = "#D0D0D0", linewidth = 0.35
      ),
      axis.text.x = ggplot2::element_text(size = 7.4),
      axis.text.y = ggplot2::element_text(size = 7.8, colour = "#222222"),
      panel.spacing = grid::unit(1.15, "lines"), legend.position = "bottom",
      plot.margin = ggplot2::margin(7, 7, 5, 7)
    )
}

figure_paths <- character(0)
wrapper_paths <- character(0)
for (inference in inference_levels) {
  wrapper_lines <- character(0)
  for (role in metric_roles) {
    path <- article_path(file.path(
      config$outputs$figure_directory,
      sprintf("%s_%s_%s_intervals.pdf", config$outputs$figure_prefix,
              inference, metric_files[[role]])
    ))
    if (inference %in% render_inference_levels && role %in% render_metric_roles) {
      render_article_pdf(path, interval_plot(inference, role))
      figure_paths <- c(figure_paths, path)
    }
    interval_text <- if (inference == "mcmc") {
      "equal-tailed 95\\% posterior intervals"
    } else {
      "equal-tailed approximate 95\\% variational posterior intervals"
    }
    oracle_text <- if (role == "forecast_check") {
      paste0(
        "The black dashed line marks the population expected check loss at the true ",
        "conditional quantile. Because the intervals condition on one simulated series, ",
        "finite-sample check-loss summaries may cross this population reference."
      )
    } else {
      paste0(
        "The black dashed line marks the exact DGP oracle value of zero for this ",
        "conditional-quantile path-error criterion."
      )
    }
    caption <- paste0(
      if (inference == "mcmc") "MCMC" else "Variational Bayes",
      " posterior uncertainty for ", metric_caption_labels[[role]],
      " in the single-quantile simulation study. Horizontal segments show ", interval_text,
      "; crosses mark posterior means. Each panel uses its own horizontal scale, and lower ",
      "values are better. ", oracle_text, " Intervals condition on the simulated data, ",
      "evaluation design, and case-specific model specification."
    )
    wrapper_lines <- c(
      wrapper_lines, "\\begin{figure}[!htbp]", "\\centering",
      sprintf("\\includegraphics[width=0.98\\textwidth]{%s}", relative_article(path)),
      paste0("\\caption{", caption, "}"),
      sprintf("\\label{fig:simulation-500obs-%s-%s-intervals}",
              inference, metric_label_ids[[role]]),
      "\\end{figure}", ""
    )
  }
  wrapper <- article_path(config$outputs[[paste0(inference, "_wrapper")]])
  writeLines(head(wrapper_lines, -1L), wrapper, useBytes = TRUE)
  wrapper_paths <- c(wrapper_paths, wrapper)
}

cat(sprintf(
  paste0(
    "INDEPENDENT_DGP_ORACLE_FIGURES_V13_BUILT rows=%d oracle=%d figures=%d ",
    "inference=%s metric_role=%s\n"
  ),
  nrow(figure_data), nrow(oracle), length(figure_paths),
  render_inference_arg, render_role_arg
))
