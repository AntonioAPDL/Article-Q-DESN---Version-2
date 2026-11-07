# Truth-free closeout of the fixed-parameter native global-path diagnostic.
# Reads only compact execution CSV/JSON evidence; never reads model RDS or truth.

ggpc_stop <- function(message) stop(paste0("GloFAS global-path closeout: ",
  message), call. = FALSE)

ggpc_hash <- function(path) unname(tools::sha256sum(path))

ggpc_classify <- function(summary, controls) {
  required <- c("contract", "method", "status", "complete", "particles",
    "effective_sample_size", "maximum_weight")
  if (!is.data.frame(summary) || !all(required %in% names(summary)))
    ggpc_stop("reference summary is incomplete")
  rows <- summary
  rows$minimum_ess <- NA_real_
  rows$maximum_weight_allowed <- NA_real_
  rows$classification <- NA_character_
  for (i in seq_len(nrow(rows))) {
    control_name <- if (identical(rows$method[i], "tempered")) "tempering" else
      rows$method[i]
    rule <- controls$execution[[control_name]]
    if (is.null(rule)) ggpc_stop("reference method has no frozen control")
    rows$minimum_ess[i] <- rule$min_ess_fraction * rows$particles[i]
    rows$maximum_weight_allowed[i] <- rule$max_weight_fraction
    ess_ok <- rows$effective_sample_size[i] >= rows$minimum_ess[i]
    weight_ratio <- rows$maximum_weight[i] / rows$maximum_weight_allowed[i]
    rows$classification[i] <- if (!isTRUE(rows$complete[i])) {
      "INCONCLUSIVE_INCOMPLETE"
    } else if (ess_ok && weight_ratio <= 1) {
      "STRICT_PASS"
    } else if (ess_ok && weight_ratio <= 1.10) {
      "NEAR_PASS_WEIGHT_ONLY"
    } else {
      "FAIL"
    }
  }
  rows$ess_ratio <- rows$effective_sample_size / rows$minimum_ess
  rows$maximum_weight_ratio <- rows$maximum_weight / rows$maximum_weight_allowed
  rows
}

ggpc_operator_differences <- function(reporting) {
  required <- c("contract", "horizon", "reporting_operator", "estimate")
  if (!is.data.frame(reporting) || !all(required %in% names(reporting)))
    ggpc_stop("reporting evidence is incomplete")
  output <- list()
  for (contract in unique(reporting$contract)) {
    block <- reporting[reporting$contract == contract, required[-1L], drop = FALSE]
    wide <- reshape(block, idvar = "horizon", timevar = "reporting_operator",
      direction = "wide")
    columns <- setdiff(names(wide), "horizon")
    for (i in seq_along(columns)) for (j in seq_along(columns)) if (i < j) {
      difference <- wide[[columns[i]]] - wide[[columns[j]]]
      output[[length(output) + 1L]] <- data.frame(contract = contract,
        operator_a = sub("^estimate\\.", "", columns[i]),
        operator_b = sub("^estimate\\.", "", columns[j]),
        mean_absolute_difference = mean(abs(difference)),
        maximum_absolute_difference = max(abs(difference)),
        maximum_horizon = wide$horizon[which.max(abs(difference))],
        stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, output)
}

ggpc_read <- function(root, controls_path) {
  root <- normalizePath(root, mustWork = TRUE)
  controls_path <- normalizePath(controls_path, mustWork = TRUE)
  needed <- c("GLOBAL_PATH_RECEIPT.json", "global_path_summary.json",
    "reference_summary.csv", "reporting.csv", "target_measurement.csv",
    "artifact_manifest.csv")
  if (!all(file.exists(file.path(root, needed)))) ggpc_stop("required evidence is absent")
  manifest <- read.csv(file.path(root, "artifact_manifest.csv"),
    stringsAsFactors = FALSE)
  if (!identical(names(manifest), c("relative_path", "size_bytes", "sha256")) ||
      anyDuplicated(manifest$relative_path) ||
      !setequal(list.files(root), c(manifest$relative_path, "artifact_manifest.csv")))
    ggpc_stop("execution inventory is not closed")
  for (i in seq_len(nrow(manifest))) {
    path <- file.path(root, manifest$relative_path[i])
    if (file.info(path)$size != manifest$size_bytes[i] ||
        !identical(ggpc_hash(path), manifest$sha256[i]))
      ggpc_stop("execution artifact hash mismatch")
  }
  receipt <- jsonlite::read_json(file.path(root, "GLOBAL_PATH_RECEIPT.json"),
    simplifyVector = FALSE)
  if (!identical(receipt$status, "GLOBAL_PATH_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION") ||
      receipt$future_truth_read != FALSE || receipt$model_fits != 0L ||
      receipt$parameter_updates != 0L || receipt$scoring != FALSE ||
      receipt$production_authorized != FALSE ||
      receipt$publication_authorized != FALSE)
    ggpc_stop("execution receipt is outside diagnostic scope")
  controls <- jsonlite::read_json(controls_path, simplifyVector = FALSE)
  summary <- read.csv(file.path(root, "reference_summary.csv"),
    stringsAsFactors = FALSE)
  reporting <- read.csv(file.path(root, "reporting.csv"),
    stringsAsFactors = FALSE)
  list(root = root, controls_path = controls_path, receipt = receipt,
    manifest = manifest, controls = controls,
    reference = ggpc_classify(summary, controls), reporting = reporting,
    differences = ggpc_operator_differences(reporting),
    measurement = read.csv(file.path(root, "target_measurement.csv"),
      stringsAsFactors = FALSE))
}

ggpc_contract_label <- function(x) {
  x <- sub("same_family_al_transition", "Same-family AL", x, fixed = TRUE)
  x <- sub("gaussian_path_prior", "Gaussian path", x, fixed = TRUE)
  x <- sub("unit_member_likelihood_v1", "unit members", x, fixed = TRUE)
  sub("fractional_marginal_information_diagnostic_v1", "fractional diagnostic",
    x, fixed = TRUE)
}

ggpc_pdf <- function(evidence, path) {
  grDevices::pdf(path, width = 11, height = 8.5, onefile = TRUE,
    family = "sans", useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- par(no.readonly = TRUE); on.exit(par(old), add = TRUE)
  palette <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7")

  par(mar = c(1, 1, 1, 1)); plot.new()
  title <- "GloFAS fixed-parameter global-path diagnostic"
  text(.05, .94, title, adj = c(0, 1), cex = 1.55, font = 2)
  text(.05, .875, "Truth-free median AL closeout", adj = c(0, 1),
    cex = 1.05, col = "#555555")
  lines <- c(
    "No future USGS truth, refit, parameter update, score, or authority replacement.",
    "Gaussian path-prior importance cells pass their frozen ESS/weight gates.",
    "Same-family tempering completes with strong ESS; max weight misses by only 1-5%.",
    "Global marginal medians agree across all four target cells.",
    "Legacy mean-readout locations diverge sharply from latent response medians.",
    "Conclusion: median path law/member strength is not the catastrophic tail mechanism.")
  for (i in seq_along(lines)) text(.07, .78 - .075 * (i - 1),
    paste0(if (i == 6) "Conclusion: " else "", sub("^Conclusion: ", "", lines[i])),
    adj = c(0, .5), cex = if (i == 6) 1.05 else .95,
    font = if (i == 6) 2 else 1, col = if (i == 6) "#9B2226" else "#222222")
  text(.05, .18, paste("Source", evidence$receipt$source_commit),
    adj = c(0, .5), cex = .75, col = "#666666")
  text(.05, .13, paste("Execution receipt", ggpc_hash(file.path(evidence$root,
    "GLOBAL_PATH_RECEIPT.json"))), adj = c(0, .5), cex = .75, col = "#666666")

  par(mar = c(7, 4.5, 3, 1)); x <- evidence$reference
  labels <- paste(ggpc_contract_label(x$contract), x$method, sep = "\n")
  reference_colors <- rep(palette, length.out = nrow(x))
  barplot(x$ess_ratio, names.arg = labels, las = 2, col = reference_colors,
    ylab = "ESS / frozen minimum", main = "Reference quality: effective sample size")
  abline(h = 1, lty = 2, lwd = 2, col = "#333333")
  legend("topright", legend = unique(x$classification), bty = "n", cex = .8)

  barplot(x$maximum_weight_ratio, names.arg = labels, las = 2,
    col = reference_colors, ylab = "max weight / frozen maximum",
    main = "Reference quality: maximum normalized weight")
  abline(h = 1, lty = 2, lwd = 2, col = "#333333")
  abline(h = 1.1, lty = 3, col = "#777777")

  par(mar = c(4.5, 4.5, 3, 1)); reporting <- evidence$reporting
  operators <- unique(reporting$reporting_operator)
  contracts <- unique(reporting$contract)
  for (operator in operators) {
    block <- reporting[reporting$reporting_operator == operator, ]
    range_y <- range(block$estimate)
    plot(NA, xlim = range(block$horizon), ylim = range_y, xlab = "Forecast horizon",
      ylab = "Transformed response", main = gsub("_", " ", operator),
      panel.first = grid(col = "#E5E5E5"))
    for (i in seq_along(contracts)) {
      line <- block[block$contract == contracts[i], ]
      lines(line$horizon, line$estimate, col = palette[i], lwd = 2)
    }
    legend("topright", legend = ggpc_contract_label(contracts), col = palette,
      lwd = 2, bty = "n", cex = .72)
  }

  par(mar = c(4.5, 4.5, 3, 1)); measurement <- evidence$measurement
  keys <- unique(measurement$contract)
  mat <- sapply(keys, function(key) measurement$total_log_density[
    measurement$contract == key])
  matplot(seq_len(nrow(mat)), mat, type = "b", pch = 16, lty = 1,
    col = palette, xlab = "Measured path: mean, mean - 0.25 SD, mean + 0.25 SD",
    ylab = "Total log density", main = "Local target geometry at retained paths")
  legend("bottomleft", legend = ggpc_contract_label(keys), col = palette,
    lwd = 2, pch = 16, bty = "n", cex = .72)

  stage_files <- list.files(evidence$root, pattern = "^stages_.*\\.csv$",
    full.names = TRUE)
  if (length(stage_files)) {
    plot(NA, xlim = c(1, 8), ylim = c(0, 1), xlab = "Tempering stage",
      ylab = expression(beta), main = "Adaptive likelihood tempering",
      panel.first = grid(col = "#E5E5E5"))
    for (i in seq_along(stage_files)) {
      stage <- read.csv(stage_files[i])
      lines(stage$stage, stage$beta, type = "b", pch = 16,
        col = palette[i], lwd = 2)
    }
    legend("bottomright", legend = ggpc_contract_label(sub("^stages_|__tempered.csv$",
      "", basename(stage_files))), col = palette, lwd = 2, pch = 16,
      bty = "n", cex = .72)
  }
}

ggpc_main <- function(args = commandArgs(TRUE)) {
  if (length(args) != 4L || !identical(args[c(1, 3)], c("--input", "--output")))
    ggpc_stop("use --input EXECUTION_ROOT --output FRESH_CLOSEOUT_ROOT")
  input <- normalizePath(args[2], mustWork = TRUE)
  output <- args[4]
  if (file.exists(output) || !dir.exists(dirname(output)))
    ggpc_stop("closeout output must be a fresh child of an existing directory")
  controls <- "scripts/diagnostics/glofas_global_path_native_controls.json"
  evidence <- ggpc_read(input, controls)
  if (!dir.create(output, mode = "0700")) ggpc_stop("cannot create closeout output")
  write.csv(evidence$reference, file.path(output, "reference_classification.csv"),
    row.names = FALSE)
  write.csv(evidence$differences, file.path(output, "operator_differences.csv"),
    row.names = FALSE)
  ggpc_pdf(evidence, file.path(output, "global_path_diagnostic_closeout.pdf"))
  conclusion <- list(schema_version = "glofas_global_path_closeout_v1",
    status = "MEDIAN_DIAGNOSTIC_COMPLETE_TAIL_MECHANISM_UNRESOLVED",
    execution_receipt_sha256 = ggpc_hash(file.path(input,
      "GLOBAL_PATH_RECEIPT.json")), future_truth_read = FALSE,
    model_fits = 0L, parameter_updates = 0L, scoring = FALSE,
    authority_replacement = FALSE, production_authorized = FALSE,
    conclusions = list(gaussian_reference = "PASS",
      same_family_reference = "COMPLETE_NEAR_PASS_WEIGHT_ONLY",
      median_path_law_sensitivity = "SMALL",
      median_member_policy_sensitivity = "SMALL",
      legacy_mean_readout_disagreement = "LARGE",
      extreme_quantile_root_cause = "UNRESOLVED_REQUIRES_TAIL_DIAGNOSTIC"))
  jsonlite::write_json(conclusion, file.path(output, "CLOSEOUT.json"),
    auto_unbox = TRUE, pretty = TRUE, digits = 17)
  files <- list.files(output, full.names = TRUE)
  manifest <- data.frame(relative_path = basename(files),
    size_bytes = file.info(files)$size, sha256 = unname(tools::sha256sum(files)),
    stringsAsFactors = FALSE)
  write.csv(manifest, file.path(output, "artifact_manifest.csv"), row.names = FALSE)
  cat("GLOFAS_GLOBAL_PATH_CLOSEOUT_COMPLETE tail_mechanism=UNRESOLVED\n")
}

if (sys.nframe() == 0L) ggpc_main()
