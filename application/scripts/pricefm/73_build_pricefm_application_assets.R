#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(jsonlite)
  library(digest)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

args <- commandArgs(trailingOnly = TRUE)
cmd_args <- commandArgs(trailingOnly = FALSE)
script_arg <- sub("^--file=", "", cmd_args[grep("^--file=", cmd_args)][1] %||% "")
if (nzchar(script_arg)) {
  repo_root <- normalizePath(file.path(dirname(script_arg), "../../.."), mustWork = FALSE)
} else {
  repo_root <- normalizePath(getwd(), mustWork = TRUE)
}
if (!file.exists(file.path(repo_root, "main.tex"))) {
  repo_root <- normalizePath(getwd(), mustWork = TRUE)
}

arg_value <- function(name, default = NULL) {
  key <- paste0("--", name)
  hit <- which(args == key)
  if (!length(hit)) {
    return(default)
  }
  if (hit == length(args)) {
    stop("Missing value after ", key, call. = FALSE)
  }
  args[[hit + 1]]
}

auto_source_root <- function() {
  candidates <- c(
    repo_root,
    "/data/jaguir26/local/src/Article-Q-DESN"
  )
  rel <- file.path(
    "application/data_local/pricefm/authoritative",
    "pricefm_stage_m_current_decision_surface_20260624",
    "current_decision_surface_table.csv"
  )
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, rel))) {
      return(normalizePath(candidate, mustWork = TRUE))
    }
  }
  stop("Could not find authoritative PriceFM decision-surface CSV. Use --source-root.", call. = FALSE)
}

source_root <- normalizePath(arg_value("source-root", auto_source_root()), mustWork = TRUE)
table_dir <- file.path(repo_root, arg_value("table-dir", "tables"))
figure_dir <- file.path(repo_root, arg_value("figure-dir", "figures/pricefm_application"))
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

paper_quantiles <- c("0.10", "0.25", "0.45", "0.50", "0.55", "0.75", "0.90")
paper_quantile_text <- paste(paper_quantiles, collapse = ", ")

decision_csv <- arg_value(
  "decision-csv",
  file.path(
    source_root,
    "application/data_local/pricefm/authoritative",
    "pricefm_stage_m_current_decision_surface_20260624",
    "current_decision_surface_table.csv"
  )
)
split_registry <- arg_value(
  "split-registry",
  file.path(source_root, "application/data_local/pricefm/processed/splits/split_registry.csv")
)
comparability_dir <- arg_value(
  "comparability-dir",
  file.path(
    source_root,
    "application/data_local/pricefm/authoritative",
    "pricefm_stage_m_comparability_audit_20260624"
  )
)

read_required_csv <- function(path, label) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    stop(label, " missing or empty: ", path, call. = FALSE)
  }
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

rel_path <- function(path) {
  path <- normalizePath(path, mustWork = FALSE)
  root <- normalizePath(repo_root, mustWork = TRUE)
  sub(paste0("^", gsub("([\\^\\$\\.\\|\\(\\)\\[\\]\\*\\+\\?\\{\\}\\\\])", "\\\\\\1", root), "/?"), "", path)
}

latex_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  replacements <- c(
    "\\" = "\\textbackslash{}",
    "&" = "\\&",
    "%" = "\\%",
    "$" = "\\$",
    "#" = "\\#",
    "_" = "\\_",
    "{" = "\\{",
    "}" = "\\}",
    "~" = "\\textasciitilde{}",
    "^" = "\\textasciicircum{}"
  )
  for (pat in names(replacements)) {
    x <- gsub(pat, replacements[[pat]], x, fixed = TRUE)
  }
  x
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "--", formatC(as.numeric(x), digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "--", paste0(formatC(100 * as.numeric(x), digits = digits, format = "f"), "\\%"))
}

png_cairo <- function(filename, width, height, units, res, ...) {
  grDevices::png(filename, width = width, height = height, units = units, res = res, type = "cairo", ...)
}

method_label <- function(x) {
  labels <- c(
    qdesn_exal = "Q--DESN exAL",
    qdesn_al = "Q--DESN AL",
    qdesn_exal_rhs_ns_exact_chunked = "Q--DESN exAL RHS\\(_{\\mathrm{NS}}\\)",
    qdesn_al_rhs_ns_exact_chunked = "Q--DESN AL RHS\\(_{\\mathrm{NS}}\\)"
  )
  out <- labels[as.character(x)]
  out[is.na(out)] <- latex_escape(x[is.na(out)])
  unname(out)
}

info_label <- function(x) {
  labels <- c(
    pricefm_graph_inputs = "Neighboring-region inputs",
    target_only = "Own-region inputs"
  )
  out <- labels[as.character(x)]
  out[is.na(out)] <- latex_escape(x[is.na(out)])
  unname(out)
}

write_text <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

write_tabular <- function(path, headers, rows, align) {
  lines <- c(
    paste0("\\begin{tabular}{", align, "}"),
    "\\toprule",
    paste(headers, collapse = " & "),
    "\\\\",
    "\\midrule"
  )
  if (length(rows)) {
    for (row in rows) {
      lines <- c(lines, paste(row, collapse = " & "), "\\\\")
    }
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  write_text(path, lines)
}

sha256_file <- function(path) {
  digest(file = path, algo = "sha256")
}

decisions <- read_required_csv(decision_csv, "Decision surface")
splits <- read_required_csv(split_registry, "Split registry")

required_decision_cols <- c(
  "region", "fold", "best_local_method", "model_family", "information_set",
  "local_AQL", "pricefm_AQL", "delta_abs", "local_wins", "decision_label"
)
missing_decision_cols <- setdiff(required_decision_cols, names(decisions))
if (length(missing_decision_cols)) {
  stop("Decision surface missing columns: ", paste(missing_decision_cols, collapse = ", "), call. = FALSE)
}

required_split_cols <- c("fold", "split", "start", "end", "n_rows")
missing_split_cols <- setdiff(required_split_cols, names(splits))
if (length(missing_split_cols)) {
  stop("Split registry missing columns: ", paste(missing_split_cols, collapse = ", "), call. = FALSE)
}

numeric_cols <- c("local_AQL", "pricefm_AQL", "delta_abs")
for (col in numeric_cols) {
  decisions[[col]] <- as.numeric(decisions[[col]])
}
if (any(!is.finite(as.matrix(decisions[numeric_cols])))) {
  stop("Decision surface contains non-finite AQL metrics.", call. = FALSE)
}
max_delta_error <- max(abs(decisions$delta_abs - (decisions$local_AQL - decisions$pricefm_AQL)))
if (max_delta_error > 1e-8) {
  stop("delta_abs does not equal local_AQL - pricefm_AQL. Max error: ", max_delta_error, call. = FALSE)
}
key <- paste(decisions$region, decisions$fold, sep = "::")
if (anyDuplicated(key)) {
  stop("Decision surface has duplicate region/fold keys.", call. = FALSE)
}
allowed_info <- c("pricefm_graph_inputs", "target_only")
bad_info <- setdiff(unique(decisions$information_set), allowed_info)
if (length(bad_info)) {
  stop("Unsupported information_set labels: ", paste(bad_info, collapse = ", "), call. = FALSE)
}

decisions$local_wins_bool <- decisions$local_wins %in% c(TRUE, "TRUE", "True", "true", "1", 1)

overall <- data.frame(
  group = "Overall",
  n_region_folds = nrow(decisions),
  n_local_wins = sum(decisions$local_wins_bool),
  win_rate = mean(decisions$local_wins_bool),
  mean_local_AQL = mean(decisions$local_AQL),
  mean_pricefm_AQL = mean(decisions$pricefm_AQL),
  mean_delta_abs = mean(decisions$delta_abs),
  stringsAsFactors = FALSE
)
fold_summary <- aggregate(
  cbind(local_AQL, pricefm_AQL, delta_abs) ~ fold,
  decisions,
  mean
)
fold_counts <- aggregate(local_wins_bool ~ fold, decisions, function(x) c(rows = length(x), wins = sum(x), win_rate = mean(x)))
fold_summary$n_region_folds <- fold_counts$local_wins_bool[, "rows"]
fold_summary$n_local_wins <- fold_counts$local_wins_bool[, "wins"]
fold_summary$win_rate <- fold_counts$local_wins_bool[, "win_rate"]
fold_summary <- fold_summary[, c("fold", "n_region_folds", "n_local_wins", "win_rate", "local_AQL", "pricefm_AQL", "delta_abs")]
names(fold_summary) <- c("fold", "n_region_folds", "n_local_wins", "win_rate", "mean_local_AQL", "mean_pricefm_AQL", "mean_delta_abs")

info_summary <- aggregate(
  cbind(local_AQL, pricefm_AQL, delta_abs) ~ information_set,
  decisions,
  mean
)
info_counts <- aggregate(local_wins_bool ~ information_set, decisions, function(x) c(rows = length(x), wins = sum(x), win_rate = mean(x)))
info_summary$n_region_folds <- info_counts$local_wins_bool[, "rows"]
info_summary$n_local_wins <- info_counts$local_wins_bool[, "wins"]
info_summary$win_rate <- info_counts$local_wins_bool[, "win_rate"]
info_summary <- info_summary[, c("information_set", "n_region_folds", "n_local_wins", "win_rate", "local_AQL", "pricefm_AQL", "delta_abs")]
names(info_summary) <- c("information_set", "n_region_folds", "n_local_wins", "win_rate", "mean_local_AQL", "mean_pricefm_AQL", "mean_delta_abs")
info_summary <- info_summary[match(c("target_only", "pricefm_graph_inputs"), info_summary$information_set), ]

region_summary <- aggregate(
  cbind(local_AQL, pricefm_AQL, delta_abs) ~ region,
  decisions,
  mean
)
region_counts <- aggregate(local_wins_bool ~ region, decisions, function(x) c(rows = length(x), wins = sum(x)))
region_summary$n_region_folds <- region_counts$local_wins_bool[, "rows"]
region_summary$n_local_wins <- region_counts$local_wins_bool[, "wins"]
region_summary <- region_summary[order(region_summary$delta_abs), c("region", "n_region_folds", "n_local_wins", "local_AQL", "pricefm_AQL", "delta_abs")]
names(region_summary) <- c("region", "n_region_folds", "n_local_wins", "mean_local_AQL", "mean_pricefm_AQL", "mean_delta_abs")

split_rows <- splits[splits$split %in% c("train", "val", "test"), ]
split_rows <- split_rows[order(split_rows$fold, match(split_rows$split, c("train", "val", "test"))), ]
split_text <- paste(
  paste0(
    "Fold ", split_rows$fold, " ", split_rows$split, ": ",
    split_rows$start, " to ", split_rows$end,
    " (", trimws(format(split_rows$n_rows, big.mark = ",")), " rows)"
  ),
  collapse = "; "
)

regions_text <- paste(sort(unique(decisions$region)), collapse = ", ")
model_text <- paste(sort(unique(method_label(decisions$best_local_method))), collapse = "; ")

protocol_rows <- list(
  c("Data source", "PriceFM European day-ahead electricity benchmark; fold-aligned cached PriceFM predictions are used for the comparison."),
  c("Frequency and response", "15-minute day-ahead electricity prices evaluated on the original EUR/MWh scale."),
  c("Covariates", "Day-ahead load, solar, and wind forecasts, plus lagged price/covariate information through the Q--DESN reservoir design."),
  c("Rolling folds", latex_escape(split_text)),
  c("Selected panel", paste0(nrow(decisions), " region/folds from ", length(unique(decisions$region)), " regions: ", latex_escape(regions_text), ".")),
  c("Q--DESN selection", "One validation-selected Q--DESN is used per region/fold. The candidate set includes AL/exAL RHS\\(_{\\mathrm{NS}}\\) readouts and may include topology-neighbor covariates from the released PriceFM graph."),
  c("Selected Q--DESN readouts", model_text),
  c("Quantile grid", paper_quantile_text),
  c("Primary metric", "Original-unit average quantile loss (AQL); lower is better. Delta AQL is Q--DESN AQL minus PriceFM AQL.")
)

protocol_table <- file.path(table_dir, "pricefm_application_protocol_summary.tex")
fold_table <- file.path(table_dir, "pricefm_application_fold_summary.tex")
region_table <- file.path(table_dir, "pricefm_application_region_summary.tex")
aliases_file <- file.path(table_dir, "pricefm_application_current_outputs.tex")
manifest_file <- file.path(table_dir, "pricefm_application_asset_manifest.json")
qa_report <- file.path(table_dir, "pricefm_application_qa_report.md")
heatmap_file <- file.path(figure_dir, "pricefm_application_delta_heatmap.png")
ranking_file <- file.path(figure_dir, "pricefm_application_region_delta_ranking.png")

write_tabular(
  protocol_table,
  c("Item", "Value"),
  lapply(protocol_rows, function(x) c(latex_escape(x[[1]]), x[[2]])),
  ">{\\raggedright\\arraybackslash}p{0.22\\textwidth}>{\\raggedright\\arraybackslash}p{0.66\\textwidth}"
)

fold_rows <- lapply(seq_len(nrow(fold_summary)), function(i) {
  row <- fold_summary[i, ]
  c(
    as.character(row$fold),
    as.character(row$n_region_folds),
    as.character(row$n_local_wins),
    fmt_pct(row$win_rate),
    fmt_num(row$mean_local_AQL),
    fmt_num(row$mean_pricefm_AQL),
    fmt_num(row$mean_delta_abs)
  )
})
fold_rows <- c(
  list(c("Overall", as.character(overall$n_region_folds), as.character(overall$n_local_wins), fmt_pct(overall$win_rate), fmt_num(overall$mean_local_AQL), fmt_num(overall$mean_pricefm_AQL), fmt_num(overall$mean_delta_abs))),
  fold_rows
)
write_tabular(
  fold_table,
  c("Fold", "Rows", "Q--DESN wins", "Win rate", "Q--DESN AQL", "PriceFM AQL", "$\\Delta$ AQL"),
  fold_rows,
  "lrrrrrr"
)

region_rows <- lapply(seq_len(nrow(region_summary)), function(i) {
  row <- region_summary[i, ]
  c(
    latex_escape(row$region),
    as.character(row$n_region_folds),
    as.character(row$n_local_wins),
    fmt_num(row$mean_local_AQL),
    fmt_num(row$mean_pricefm_AQL),
    fmt_num(row$mean_delta_abs)
  )
})
write_tabular(
  region_table,
  c("Region", "Rows", "Q--DESN wins", "Q--DESN AQL", "PriceFM AQL", "$\\Delta$ AQL"),
  region_rows,
  "lrrrrr"
)

decision_for_plot <- decisions
region_order <- region_summary$region
decision_for_plot$region <- factor(decision_for_plot$region, levels = rev(region_order))
decision_for_plot$fold <- factor(decision_for_plot$fold, levels = sort(unique(decision_for_plot$fold)))

p_heat <- ggplot(decision_for_plot, aes(x = fold, y = region, fill = delta_abs)) +
  geom_tile(color = "white", linewidth = 0.4) +
  geom_text(aes(label = sprintf("%.2f", delta_abs)), size = 3.1) +
  scale_fill_gradient2(
    low = "#2166ac", mid = "white", high = "#b2182b",
    midpoint = 0, name = expression(Delta~AQL)
  ) +
  labs(x = "Fold", y = "Region", subtitle = "Negative values favor Q-DESN") +
  theme_minimal(base_size = 12) +
  theme(panel.grid = element_blank(), legend.position = "right")
ggsave(heatmap_file, p_heat, width = 8.2, height = 6.4, dpi = 220, device = png_cairo)

region_plot <- region_summary
region_plot$region <- factor(region_plot$region, levels = region_summary$region)
p_rank <- ggplot(region_plot, aes(x = mean_delta_abs, y = region, fill = mean_delta_abs < 0)) +
  geom_col(width = 0.72) +
  geom_vline(xintercept = 0, linewidth = 0.4) +
  scale_fill_manual(values = c("TRUE" = "#2166ac", "FALSE" = "#b2182b"), guide = "none") +
  labs(x = expression("Mean Q-DESN-minus-PriceFM AQL"), y = "Region", subtitle = "Selected-panel averages; negative values favor Q-DESN") +
  theme_minimal(base_size = 12) +
  theme(panel.grid.major.y = element_blank())
ggsave(ranking_file, p_rank, width = 7.2, height = 5.6, dpi = 220, device = png_cairo)

macros <- c(
  PricefmApplicationRegionFolds = as.character(nrow(decisions)),
  PricefmApplicationRegions = as.character(length(unique(decisions$region))),
  PricefmApplicationFolds = as.character(length(unique(decisions$fold))),
  PricefmApplicationQdesnWins = as.character(sum(decisions$local_wins_bool)),
  PricefmApplicationPricefmWins = as.character(nrow(decisions) - sum(decisions$local_wins_bool)),
  PricefmApplicationWinRate = fmt_pct(mean(decisions$local_wins_bool)),
  PricefmApplicationTopologyInputSelections = as.character(sum(decisions$information_set == "pricefm_graph_inputs")),
  PricefmApplicationOwnRegionInputSelections = as.character(sum(decisions$information_set == "target_only")),
  PricefmApplicationMeanQdesnAql = fmt_num(mean(decisions$local_AQL)),
  PricefmApplicationMeanPricefmAql = fmt_num(mean(decisions$pricefm_AQL)),
  PricefmApplicationMeanDeltaAql = fmt_num(mean(decisions$delta_abs)),
  PricefmApplicationPaperQuantiles = paper_quantile_text,
  PricefmApplicationProtocolTable = rel_path(protocol_table),
  PricefmApplicationFoldSummaryTable = rel_path(fold_table),
  PricefmApplicationRegionSummaryTable = rel_path(region_table),
  PricefmApplicationDeltaHeatmapFigure = rel_path(heatmap_file),
  PricefmApplicationRegionDeltaRankingFigure = rel_path(ranking_file)
)
alias_lines <- c(
  "% Generated by application/scripts/pricefm/73_build_pricefm_application_assets.R",
  "% Paper-facing aliases for the PriceFM application section.",
  vapply(names(macros), function(name) paste0("\\newcommand{\\", name, "}{", macros[[name]], "}"), character(1))
)
write_text(aliases_file, alias_lines)

tracked_outputs <- c(
  aliases_file, protocol_table, fold_table, region_table,
  heatmap_file, ranking_file
)
source_files <- c(decision_csv, split_registry)
if (dir.exists(comparability_dir)) {
  comparability_files <- list.files(comparability_dir, recursive = TRUE, full.names = TRUE)
  source_files <- c(source_files, comparability_files[file.info(comparability_files)$isdir == FALSE])
}
manifest <- list(
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  script = "application/scripts/pricefm/73_build_pricefm_application_assets.R",
  source_root = source_root,
  selected_panel = list(
    n_region_folds = nrow(decisions),
    n_regions = length(unique(decisions$region)),
    n_folds = length(unique(decisions$fold)),
    n_target_only_rows = sum(decisions$information_set == "target_only"),
    n_graph_neighbor_rows = sum(decisions$information_set == "pricefm_graph_inputs"),
    n_qdesn_wins = sum(decisions$local_wins_bool),
    mean_qdesn_aql = mean(decisions$local_AQL),
    mean_pricefm_aql = mean(decisions$pricefm_AQL),
    mean_delta_aql = mean(decisions$delta_abs),
    paper_quantiles = paper_quantiles
  ),
  checks = list(
    max_delta_identity_error = max_delta_error,
    unique_region_fold_keys = length(unique(key)) == nrow(decisions),
    finite_metrics = TRUE,
    selected_panel_not_full_pricefm_scope = nrow(decisions) != 38 * 3
  ),
  source_files = lapply(source_files[file.exists(source_files)], function(path) {
    list(path = path, sha256 = sha256_file(path), bytes = unname(file.info(path)$size))
  }),
  output_files = lapply(c(tracked_outputs, manifest_file), function(path) {
    list(path = rel_path(path), sha256 = if (file.exists(path)) sha256_file(path) else NA_character_, bytes = if (file.exists(path)) unname(file.info(path)$size) else NA_integer_)
  })
)
write_json(manifest, manifest_file, pretty = TRUE, auto_unbox = TRUE)
manifest$output_files <- lapply(c(tracked_outputs, manifest_file), function(path) {
  list(path = rel_path(path), sha256 = sha256_file(path), bytes = unname(file.info(path)$size))
})
write_json(manifest, manifest_file, pretty = TRUE, auto_unbox = TRUE)

qa_lines <- c(
  "# PriceFM Application Asset QA",
  "",
  "This report is generated by `application/scripts/pricefm/73_build_pricefm_application_assets.R`.",
  "",
  "## Coverage",
  "",
  paste0("- Region/fold rows: `", nrow(decisions), "`"),
  paste0("- Regions: `", length(unique(decisions$region)), "`"),
  paste0("- Folds: `", paste(sort(unique(decisions$fold)), collapse = ", "), "`"),
  paste0("- Own-region input rows: `", sum(decisions$information_set == "target_only"), "`"),
  paste0("- Neighboring-region input rows: `", sum(decisions$information_set == "pricefm_graph_inputs"), "`"),
  "",
  "This remains a selected-panel comparison, not the full 38-region PriceFM benchmark.",
  "",
  "## Metric Identity Checks",
  "",
  paste0("- Max absolute delta identity error: `", format(max_delta_error, scientific = TRUE), "`"),
  "- All AQL metrics are finite.",
  "- Region/fold keys are unique.",
  "",
  "## Main Empirical Signal",
  "",
  paste0("- Overall mean Q--DESN-minus-PriceFM AQL: `", fmt_num(mean(decisions$delta_abs)), "`"),
  paste0("- Q--DESN wins: `", sum(decisions$local_wins_bool), "` of `", nrow(decisions), "`"),
  paste0("- Selected Q--DESN specifications using topology-neighbor inputs: `", sum(decisions$information_set == "pricefm_graph_inputs"), "`"),
  paste0("- Selected Q--DESN specifications using own-region inputs only: `", sum(decisions$information_set == "target_only"), "`")
)
write_text(qa_report, qa_lines)

cat(toJSON(list(
  aliases = rel_path(aliases_file),
  manifest = rel_path(manifest_file),
  qa_report = rel_path(qa_report),
  n_region_folds = nrow(decisions),
  n_regions = length(unique(decisions$region)),
  mean_delta_aql = mean(decisions$delta_abs)
), pretty = TRUE, auto_unbox = TRUE))
cat("\n")
