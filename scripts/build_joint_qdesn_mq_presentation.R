#!/usr/bin/env Rscript
# Presentation-only MQ nomenclature overlay of frozen article evidence.
# No model modules, fit objects, scoring, projection, or historical builders.

mq_manifest_path <- "tables/joint_qdesn_mq_presentation_manifest.json"
mq_registry_path <- "tables/qdesn_model_display_names.csv"
mq_generator_path <- "scripts/build_joint_qdesn_mq_presentation.R"
mq_original_prefix <- "joint_qdesn_pure_desn_v2_"
mq_display_prefix <- "joint_qdesn_pure_desn_v2_mq_"
mq_table_suffixes <- c("protocol", "score_table", "secondary_score_table",
  "vb_score_table", "recursive_policy_table", "contrast_table", "crossing_table",
  "oracle_recovery_table")
mq_frozen_pins <- c(
  "tables/joint_qdesn_pure_desn_v2_article_asset_manifest.csv" =
    "cc50ea11fed8bbb3bbe9b7f1d66c2c99c570423853f0d30dd3fe6ffa42c6f473",
  "scripts/qdesn_evaluation_figure_style.R" =
    "388acabfb175f291fcf5f9112eccc66f35388ea8e0e73c6b28c7831b6bc5022c",
  "scripts/build_joint_qdesn_laplace_article_figures_v2.R" =
    "ab656a54eafcc85e51338141d92cf1b1f232f3304c38f1175503035a0c4dd2ff",
  "scripts/build_joint_qdesn_pure_desn_article_projection_v2.R" =
    "8ed87f7574d911486ddb3b24605ad9fd9a90aa5f6543860bdc27e0799dd52b9e",
  "tables/qdesn_pro_review_presentation_manifest.json" =
    "648ef97d91adceaa17cf5958dcc515520ebe31ae65ca7fc1d58de5ca960a8e9e",
  "tables/qdesn_article_presentation_manifest_v2.json" =
    "6d968c038130c62399df62b0add9be9ed817547d5068fc357c1b1e6bfb0d0277")
mq_sha <- function(p) unname(tools::sha256sum(p)[[1L]])
mq_expect <- function(value, message) {
  if (!isTRUE(value)) stop(paste("MQ_PRESENTATION_FAILED:", message), call. = FALSE)
}
mq_registry <- function(root) {
  registry <- read.csv(file.path(root, mq_registry_path), check.names = FALSE)
  fields <- c("context", "source_key", "model_family", "fit_structure",
    "likelihood_family", "display_tex", "display_text")
  mq_expect(identical(names(registry), fields) && !anyNA(registry), "Display registry schema")
  simulation <- c("joint_qdesn_rhs_vb", "joint_qdesn_rhs_mcmc",
    "qdesn_rhs_independent_vb", "qdesn_rhs_independent_mcmc",
    "joint_exqdesn_rhs_vb", "joint_exqdesn_rhs_mcmc",
    "exqdesn_rhs_independent_vb", "exqdesn_rhs_independent_mcmc")
  expected <- c(paste("simulation", simulation, sep = "|"),
    paste("glofas", c("Joint AL", "Joint exAL", "Independent AL", "Independent exAL"), sep = "|"))
  keys <- paste(registry$context, registry$source_key, sep = "|")
  mq_expect(nrow(registry) == 12L && !anyDuplicated(keys) && setequal(keys, expected),
    "Display registry has exactly the approved context/key pairs")
  joint <- startsWith(registry$source_key, "joint_") | startsWith(registry$source_key, "Joint ")
  likelihood <- ifelse(grepl("exqdesn|exAL", registry$source_key), "exAL", "AL")
  family <- ifelse(joint, "MQ-DESN", "Q-DESN")
  mq_expect(identical(registry$fit_structure, ifelse(joint, "joint", "independent")) &&
    identical(registry$model_family, family) && identical(registry$likelihood_family, likelihood) &&
    identical(registry$display_text, paste0(family, " (", likelihood, ")")) &&
    identical(registry$display_tex, paste0(sub("-", "--", family, fixed = TRUE), " (", likelihood, ")")),
    "Display registry preserves independent/coupled and AL/exAL assignments")
  registry
}
mq_frozen_sources <- function(root) {
  for (relative in names(mq_frozen_pins)) mq_expect(
    file.exists(file.path(root, relative)) &&
      identical(mq_sha(file.path(root, relative)), unname(mq_frozen_pins[[relative]])),
    paste("Frozen source fingerprint", relative))
  original <- read.csv(file.path(root, names(mq_frozen_pins)[[1L]]), check.names = FALSE)
  for (i in seq_len(nrow(original))) mq_expect(
    file.exists(file.path(root, original$relative_path[[i]])) &&
      identical(mq_sha(file.path(root, original$relative_path[[i]])), original$sha256[[i]]) &&
      file.info(file.path(root, original$relative_path[[i]]))$size == original$size_bytes[[i]],
    paste("Frozen original asset", original$relative_path[[i]]))
  source_paths <- sort(unique(c(original$relative_path, names(mq_frozen_pins))))
  stats::setNames(vapply(file.path(root, source_paths), mq_sha, character(1L)), source_paths)
}
mq_asset_mapping <- function() {
  suffixes <- c(paste0(mq_table_suffixes, ".tex"), "forecast_figure.tex", "fit_figure.tex")
  tables <- data.frame(source = paste0("tables/", mq_original_prefix, suffixes),
    file = paste0("tables/", mq_display_prefix, suffixes),
    role = c(rep("table", length(mq_table_suffixes)), "wrapper", "wrapper"))
  figures <- c("forecast_dgp_acrps.pdf", "fit_oracle_rmse.pdf")
  rbind(tables, data.frame(source = paste0("figures/joint_qdesn_simulation/", mq_original_prefix, figures),
    file = paste0("figures/joint_qdesn_simulation/", mq_display_prefix, figures), role = "figure"))
}
mq_style <- function(root, registry) {
  # The frozen source file and its independent-label dictionary never change.
  style <- new.env(parent = globalenv())
  source(file.path(root, "scripts/qdesn_evaluation_figure_style.R"), local = style)
  block <- registry[registry$context == "simulation", ]
  labels <- stats::setNames(block$display_text, block$source_key)
  style$qdesn_joint_model_labels <- labels[style$qdesn_joint_model_order]
  style
}
mq_table_text <- function(lines, registry) {
  block <- registry[registry$context == "simulation" & endsWith(registry$source_key, "_vb"), ]
  old <- c(joint_qdesn_rhs_vb = "Joint AL", qdesn_rhs_independent_vb = "Independent AL",
    joint_exqdesn_rhs_vb = "Joint exAL", exqdesn_rhs_independent_vb = "Independent exAL")
  for (i in seq_len(nrow(block))) lines <- gsub(paste0(old[[block$source_key[[i]]]], " &"),
    paste0(block$display_tex[[i]], " &"), lines, fixed = TRUE)
  lines <- gsub("Joint-minus-independent differences", "MQ--DESN minus independent Q--DESN differences", lines, fixed = TRUE)
  lines <- gsub("and joint fits supply starting values", "and MQ--DESN fits supply starting values", lines, fixed = TRUE)
  if (any(grepl("Q--DESN (AL) &", lines, fixed = TRUE))) lines <- mq_caption_names(lines)
  lines
}
mq_caption_names <- function(lines) {
  at <- startsWith(lines, "\\caption{")
  lines[at] <- sub("}$", paste0(" Q--DESN denotes independently fitted levels; ",
    "MQ--DESN denotes coupled multiquantile fits.}"), lines[at])
  lines
}
mq_wrapper_text <- function(lines) {
  for (suffix in c("forecast_dgp_acrps.pdf", "fit_oracle_rmse.pdf")) lines <- gsub(
    paste0(mq_original_prefix, suffix), paste0(mq_display_prefix, suffix), lines, fixed = TRUE)
  mq_caption_names(lines)
}
mq_normalize_pdf_date <- function(p) {
  bytes <- readBin(p, "raw", n = file.info(p)$size)
  marker <- charToRaw("/CreationDate (D:")
  candidates <- which(bytes == marker[[1L]])
  hits <- candidates[vapply(candidates, function(at) {
    end <- at + length(marker) - 1L
    end <= length(bytes) && identical(bytes[at:end], marker)
  }, logical(1L))]
  mq_expect(length(hits) == 1L, "One Cairo creation date")
  closing <- which(seq_along(bytes) > hits[[1L]] & bytes == charToRaw(")")[[1L]])[[1L]]
  replacement <- charToRaw("/CreationDate (D:20000101000000+00'00)")
  mq_expect(length(replacement) == closing - hits[[1L]] + 1L, "Fixed-length date normalization")
  bytes[hits[[1L]]:closing] <- replacement
  writeBin(bytes, p)
}
mq_render_figures <- function(root, output_root, registry) {
  style <- mq_style(root, registry)
  score <- read.csv(file.path(root, "tables/joint_qdesn_pure_desn_v2_forecast_score_summary.csv"), check.names = FALSE)
  fit <- read.csv(file.path(root, "tables/joint_qdesn_pure_desn_v2_fit_oracle_diagnostics.csv"), check.names = FALSE)
  score <- score[score$inference_method == "mcmc", ]
  fit <- fit[fit$inference_method == "mcmc", ]
  fit <- fit[match(score$model_cell_id, fit$model_cell_id), ]
  mq_expect(nrow(score) == 32L && nrow(fit) == 32L &&
    identical(score$model_cell_id, fit$model_cell_id) &&
    all(score$canonical_contract_crossing_pairs == 0) && all(fit$fit_contract_crossing_pairs == 0),
    "Frozen 32-cell figure surface")
  model_style <- stats::setNames(style$qdesn_joint_model_order,
    sub("_vb$", "_mcmc", style$qdesn_joint_model_order))
  data <- data.frame(scenario_id = score$scenario_id,
    source_model_id = unname(model_style[score$model_id]), likelihood_family = score$likelihood_family,
    mean = score$posterior_score_mean, lo = score$posterior_score_q025, hi = score$posterior_score_q975,
    crossing = sprintf("%.2f%%", 100 * score$canonical_raw_crossing_pairs / (990L * 6L)))
  mq_expect(!anyNA(data), "All original model keys are mapped")
  readable_theme <- ggplot2::theme(text = ggplot2::element_text(size = 10.4),
    strip.text = ggplot2::element_text(face = "bold", size = 10.4, lineheight = .98),
    axis.text.x = ggplot2::element_text(size = 10.4),
    axis.text.y = ggplot2::element_text(size = 10.4, colour = "#242424"),
    axis.title.x = ggplot2::element_text(size = 10.4),
    plot.margin = ggplot2::margin(7, 16, 7, 7), panel.spacing = grid::unit(1.0, "lines"))
  make_plot <- function(block, xlab, point_only = FALSE) {
    p <- style$qdesn_joint_interval_plot(block, xlab) + readable_theme
    p$layers[[3L]]$aes_params$size <- 3.7
    for (scenario in levels(p$data$scenario_id)) {
      at <- which(p$data$scenario_id == scenario)
      span <- max(p$data$hi[at]) - min(p$data$lo[at])
      if (!is.finite(span) || span <= 0) span <- max(abs(p$data$hi[at]), 1) * .1
      p$data$label_x[at] <- max(p$data$hi[at]) + .72 * span
    }
    xscale <- p$scales$get_scales("x")
    xscale$labels <- function(x) {
      digits <- if (length(x) > 1L && diff(range(x, na.rm = TRUE)) < .04) 3L else 2L
      formatC(x, format = "f", digits = digits)
    }
    if (point_only) p$layers <- p$layers[-1L]
    p
  }
  mapping <- mq_asset_mapping()
  plots <- list(make_plot(data, "Oracle aCRPS"))
  data$mean <- data$lo <- data$hi <- fit$fit_oracle_rmse
  data$crossing <- sprintf("%.2f%%", 100 * fit$fit_raw_crossing_pairs / (500L * 6L))
  plots[[2L]] <- make_plot(data, "Fitting-sample quantile-path RMSE", TRUE)
  figures <- mapping$file[mapping$role == "figure"]
  for (i in seq_along(figures)) {
    p <- file.path(output_root, figures[[i]])
    style$qdesn_save_vector_pdf(p, plots[[i]], 7.0, 8.1)
    mq_normalize_pdf_date(p)
  }
}
mq_build <- function(root, output_root) {
  mq_expect(requireNamespace("ggplot2", quietly = TRUE) && requireNamespace("jsonlite", quietly = TRUE),
    "ggplot2 and jsonlite are available")
  sources <- mq_frozen_sources(root)
  registry <- mq_registry(root)
  registry_sha <- mq_sha(file.path(root, mq_registry_path))
  mapping <- mq_asset_mapping()
  for (i in which(mapping$role != "figure")) {
    lines <- readLines(file.path(root, mapping$source[[i]]), warn = FALSE)
    lines <- if (mapping$role[[i]] == "table") mq_table_text(lines, registry) else mq_wrapper_text(lines)
    target <- file.path(output_root, mapping$file[[i]])
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    writeLines(lines, target, useBytes = TRUE)
  }
  mq_render_figures(root, output_root, registry)
  mq_expect(identical(sources, mq_frozen_sources(root)) &&
    identical(registry_sha, mq_sha(file.path(root, mq_registry_path))), "Every frozen input remains unchanged")
  receipt <- list(schema = "joint-qdesn-mq-presentation-v1",
    purpose = "Reader-only MQ nomenclature; frozen scientific values, IDs, targets and original assets unchanged",
    generator = mq_generator_path, generator_sha256 = mq_sha(file.path(root, mq_generator_path)),
    registry = mq_registry_path, registry_sha256 = registry_sha,
    sources = as.list(sources), native_ordinary_label_pt = 10.4,
    figure_width_inches = 7.0, figure_height_inches = 8.1,
    main_insertion_width = "0.94 textwidth", fitting = FALSE, rescoring = FALSE,
    quantile_projection = FALSE, model_order = c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
      "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc"),
    outputs = lapply(seq_len(nrow(mapping)), function(i) list(file = mapping$file[[i]],
      source = mapping$source[[i]], role = mapping$role[[i]],
      size_bytes = unname(file.info(file.path(output_root, mapping$file[[i]]))$size),
      sha256 = mq_sha(file.path(output_root, mapping$file[[i]])))))
  jsonlite::write_json(receipt, file.path(output_root, mq_manifest_path),
    pretty = TRUE, auto_unbox = TRUE, digits = 17)
  invisible(receipt)
}
mq_verify <- function(root) {
  # No rendering or writes: usable by the article checker and mutation tests.
  registry <- mq_registry(root)
  sources <- mq_frozen_sources(root)
  receipt <- jsonlite::fromJSON(file.path(root, mq_manifest_path), simplifyVector = FALSE)
  mapping <- mq_asset_mapping()
  mq_expect(identical(receipt$schema, "joint-qdesn-mq-presentation-v1") &&
    identical(receipt$generator, mq_generator_path) &&
    identical(receipt$generator_sha256, mq_sha(file.path(root, mq_generator_path))) &&
    identical(receipt$registry, mq_registry_path) &&
    identical(receipt$registry_sha256, mq_sha(file.path(root, mq_registry_path))) &&
    identical(receipt$sources, as.list(sources)), "MQ overlay receipt and frozen-source closure")
  mq_expect(length(receipt$outputs) == nrow(mapping) && !receipt$fitting && !receipt$rescoring &&
    !receipt$quantile_projection && receipt$native_ordinary_label_pt == 10.4,
    "MQ presentation-only scope and complete 12-output surface")
  for (i in seq_len(nrow(mapping))) {
    entry <- receipt$outputs[[i]]
    mq_expect(identical(entry$file, mapping$file[[i]]) && identical(entry$source, mapping$source[[i]]) &&
      identical(entry$role, mapping$role[[i]]) && file.exists(file.path(root, entry$file)) &&
      identical(entry$sha256, mq_sha(file.path(root, entry$file))) &&
      entry$size_bytes == file.info(file.path(root, entry$file))$size,
      paste("MQ derivative hash and mapping", mapping$file[[i]]))
    if (mapping$role[[i]] != "figure") {
      source <- readLines(file.path(root, mapping$source[[i]]), warn = FALSE)
      expected <- if (mapping$role[[i]] == "table") mq_table_text(source, registry) else mq_wrapper_text(source)
      mq_expect(identical(readLines(file.path(root, entry$file), warn = FALSE), expected),
        paste("Exact mapped text; numerical values and internal labels unchanged", entry$file))
    }
  }
  invisible(receipt)
}
if (sys.nframe() == 0L) {
  options(stringsAsFactors = FALSE, digits = 17)
  arguments <- commandArgs(trailingOnly = TRUE)
  script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
  root <- normalizePath(file.path(dirname(sub("^--file=", "", script_argument)), ".."))
  mq_expect(all(arguments %in% "--check"), "Only --check is supported")
  if ("--check" %in% arguments) {
    mq_verify(root)
    temporary <- tempfile("joint-mq-presentation-check-")
    dir.create(temporary)
    tryCatch({
      mq_build(root, temporary)
      outputs <- c(mq_asset_mapping()$file, mq_manifest_path)
      for (relative in outputs) mq_expect(identical(mq_sha(file.path(root, relative)),
        mq_sha(file.path(temporary, relative))), paste("Deterministic MQ rebuild", relative))
    }, finally = unlink(temporary, recursive = TRUE))
    cat("JOINT_MQ_PRESENTATION_CHECK=PASS outputs=12 original_sources_unchanged=TRUE no_fit_or_rescoring=TRUE\n")
  } else {
    mq_build(root, root)
    mq_verify(root)
    cat("JOINT_MQ_PRESENTATION_BUILD=PASS outputs=12 original_sources_unchanged=TRUE no_fit_or_rescoring=TRUE\n")
  }
}
