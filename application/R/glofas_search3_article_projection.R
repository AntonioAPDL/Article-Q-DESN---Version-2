# Deterministic, read-only projection of the frozen GloFAS Search III authority.
# No fitting, forecasting, continuation, or model selection is performed here.
g3_tag <- "glofas_search3_part1234_final_20261007"
g3_tau <- c(.05, .20, .35, .50, .65, .80, .95)
g3_families <- c("Normal Ridge", "Normal RHS/VB", "Independent AL", "Independent exAL", "Joint AL", "Joint exAL", "Raw GloFAS")
g3_expected <- c(
  output_manifest = "968096fe310b61c4b05423890cad529e7c891e51691cd997ef253753c7c9de9f",
  source_pdf = "799d05536f7331d80ff534f4198e5977c08344d97d8f83167c52b8534e82ae31",
  joint_al = "0ac25ad186fa660d7958484db822c0e2c7ce60ae933928498dfd42180e439274",
  joint_exal = "0784549437365dc239e123fe0fd660d4212fa0e7a72dc1034765b5ba73e6e823",
  part123 = "8bfc582d73c39d7a0e378f37635337811416bf1a8335dba26c3d14e191e66185",
  part4 = "cef8ebb8d620d73cf64c2c4bf7723cadef498ceb4c083d053381c3269d4eac25",
  calibration = "647afb6d70dc882d9a98ba6d4e2a21df61379d4de37eb80356ffa1b2855b6355",
  selected = "c110133b0cb1c01e0e7f3dd40679e7bd4ceb17b627726adc345e45c4cc9b8296",
  convergence = "a1670d1b56c84a9228cdf05e21edb6054b7c8b1778d2ebd08ca6367f751c55aa",
  public_quantiles = "d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a",
  public_prior_scalars = "fc71014d3a39548e1c06d08fb6df116545745ae17f50abb8841a988267b6d8d5"
)
g3_pdf_expected <- c(part1 = "6adbb89c9a6be85db3343028d5a9574d728e259c2238f7a659f09b39af7d9676", part2 = "2da731c935784a59d37778cbd654a937f0e80a248fe71570d0c3fa6cfc219ec9", part3 = "12d9ec7ee4fdbcf191ec18b942af525d723f37da9337fd85c6e9ba723a3646bb", part4 = "1c6b2421ecb05b455a75d00852fc638f2325156e5aa440cb32ea1bf5d5f99de9", convergence = "9891d8917571b5ade6cf7b5069c2f56054b88e4c5024a3e551c2ce56b595b064", calibration = "7474879101d262b8e10079e0f310dcda259f2316a66fc8ef006c061527b38b2f")
g3_sha <- function(path) {
  if (!file.exists(path)) stop("Missing input: ", path, call. = FALSE)
  out <- system2("sha256sum", shQuote(path), stdout = TRUE)
  if (!is.null(attr(out, "status"))) stop("SHA256 failed.", call. = FALSE)
  sub(" .*", "", out[[1L]])
}
g3_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # write.table's numeric conversion normally rounds to 15 digits. Encode every
  # finite double at round-trip precision, keeping NA and booleans explicit.
  y <- x
  for (n in names(y)) if (is.numeric(y[[n]]) && !is.integer(y[[n]])) {
    y[[n]] <- ifelse(is.na(y[[n]]), NA_character_, sprintf("%.17g", y[[n]]))
  }
  write.table(y, path, sep = ",", quote = TRUE, row.names = FALSE, col.names = TRUE, na = "NA", eol = "\n")
}
g3_read <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
g3_path <- function(kind, suffix, ext) file.path(kind, paste0(g3_tag, "_", suffix, ".", ext))
g3_assert <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
g3_same <- function(a, b, message, tolerance = 2e-12) {
  g3_assert(identical(names(a), names(b)) && nrow(a) == nrow(b), paste0(message, " schema"))
  for (n in names(a)) {
    if (is.numeric(a[[n]]) && is.numeric(b[[n]])) {
      g3_assert(isTRUE(all.equal(a[[n]], b[[n]], tolerance = tolerance, check.attributes = FALSE)), paste0(message, ": ", n))
    } else g3_assert(identical(as.character(a[[n]]), as.character(b[[n]])), paste0(message, ": ", n))
  }
}
g3_tex_escape <- function(x) {
  x <- gsub("_", "\\_", x, fixed = TRUE)
  x <- gsub("%", "\\%", x, fixed = TRUE)
  x
}
g3_tabular <- function(headers, rows, alignment = paste(rep("r", length(headers)), collapse = "")) {
  c("% Generated deterministically from the reviewed Search III authority.",
    "\\resizebox{\\linewidth}{!}{%", paste0("\\begin{tabular}{@{}", alignment, "@{}}"),
    "\\toprule", paste0(paste(headers, collapse = " & "), " \\\\"), "\\midrule",
    apply(rows, 1L, function(row) paste0(paste(row, collapse = " & "), " \\\\")),
    "\\bottomrule", "\\end{tabular}%", "}")
}
g3_tables <- function(data) {
  p4 <- data$part4_scores
  status <- ifelse(p4$family %in% c("Joint AL", "Joint exAL"), "Strict convergence", ifelse(p4$family == "Raw GloFAS", "Issued ensemble", "Complete"))
  out <- list()
  out$part4_scores <- g3_tabular(c("Family", "Mean check loss", "Grid aCRPS", "90\\% coverage", "Reduction vs raw", "Numerical status"),
    cbind(p4$family, sprintf("%.4f", p4$mean_check_loss), sprintf("%.4f", p4$crps_grid_log1p), sprintf("%.3f", p4$coverage90), sprintf("%.2f\\%%", 100 * p4$crps_reduction_vs_raw), status), "lrrrrl")
  p <- data$part123_scores
  row <- cbind(p$part, p$family, ifelse(is.na(p$crps_grid_log1p), "---", sprintf("%.4f", p$crps_grid_log1p)), ifelse(is.na(p$coverage90), "---", sprintf("%.3f", p$coverage90)), ifelse(is.na(p$crossing_pairs), "---", p$crossing_pairs))
  out$part123_scores <- c(g3_tabular(c("Part", "Family", "Grid aCRPS", "90\\% coverage", "Crossing pairs"), row, "llrrr"), "% Part 2: post-cutoff paths are unscored; retrospective GloFAS ends at the cutoff.")
  cal <- data$calibration
  row <- do.call(rbind, lapply(p4$family, function(f) {
    z <- cal[cal$family == f, ]; z <- z[order(z$quantile_level), ]
    c(f, sprintf("%.3f", z$empirical_coverage))
  }))
  out$calibration <- g3_tabular(c("Family", sprintf("$q_{%.2f}$", g3_tau)), row, "lrrrrrrr")
  s <- data$selected_specifications
  row <- cbind(s$component, g3_tex_escape(s$candidate_id), s$D, s$n_vector, s$output_lag_max, s$covariate_lag_max, sprintf("%.2f", s$alpha), sprintf("%.2f", s$rho), s$m0, ifelse(is.na(s$rhs_zeta2_fixed), "Learned", "Fixed 16"))
  out$selected_specifications <- g3_tabular(c("Component", "Candidate", "$D$", "$n$", "$m$", "$m_x$", "$\\alpha$", "$\\rho$", "$m_0$", "Search slab"), row, "llrrrrrrrl")
  z <- data$convergence
  row <- cbind(z$family, z$outer_iteration, sprintf("%.7g", z$parameter_change), sprintf("%.7g", z$max_rhs_global_relative_change), z$terminal_consecutive_passes, "Strict convergence")
  out$convergence <- g3_tabular(c("Family", "Outer sweep", "Parameter change", "Maximum RHS change", "Full-state passes", "Status"), row, "lrrrrl")
  a <- data$authority
  out$authority <- g3_tabular(c("Authority role", "Status", "SHA256 prefix"), cbind(g3_tex_escape(a$role), a$authority_status, substr(a$sha256, 1L, 12L)), "lll")
  d <- data$decision_ledger
  out$decision_ledger <- g3_tabular(c("Decision", "Evidence scope", "Protected-window selection"), cbind(d$decision, d$evidence_scope, d$protected_window_selection), "lll")
  z <- data$prior_settings
  out$prior_settings <- g3_tabular(c("Family", "$\\tau_{0,\\mathrm{ref}}$", "$\\tau_{0,\\mathrm{dis}}$", "Slab treatment", "Intercept precision"),
    cbind(z$family, ifelse(is.na(z$reference_tau0), "---", sprintf("%.8g", z$reference_tau0)), ifelse(is.na(z$discrepancy_tau0), "---", sprintf("%.8g", z$discrepancy_tau0)), z$slab_treatment, ifelse(is.na(z$intercept_precision), "---", sprintf("%.1g", z$intercept_precision))), "lrrlr")
  z <- data$part123_prior_settings
  if (!is.null(z)) out$part123_prior_settings <- g3_tabular(c("Part", "Family", "Component", "$\\tau_0$", "Slab", "$\\tau$ posterior range"),
    cbind(z$part, z$family, z$component, ifelse(is.na(z$tau0), "---", sprintf("%.8g", z$tau0)), z$slab_treatment, ifelse(is.na(z$effective_tau_min), "Ridge: $\\tau^2=10^4$", sprintf("%.4g--%.4g", z$effective_tau_min, z$effective_tau_max))), "lllrlr")
  out
}
g3_macros <- function(data) {
  p <- data$part4_scores
  lead <- p[p$family == "Independent AL", ]; raw <- p[p$family == "Raw GloFAS", ]
  al <- p[p$family == "Joint AL", ]; ex <- p[p$family == "Joint exAL", ]
  q95 <- data$calibration$empirical_coverage[data$calibration$family == "Joint exAL" & data$calibration$quantile_level == .95]
  m <- list(CurrentRunId = paste0("\\detokenize{", g3_tag, "}"), CurrentConfigPath = g3_path("tables", "selected_specifications", "csv"),
    CurrentPromotionManifest = g3_path("tables", "decision_ledger", "csv"), CurrentSelectionManifest = g3_path("tables", "publication_manifest", "csv"),
    CurrentCandidateId = "search3\\_ref\\_001 / search3\\_dis\\_007", CurrentReferenceCandidateId = "search3\\_ref\\_001", CurrentDiscrepancyCandidateId = "search3\\_dis\\_007",
    CurrentDiscrepancyTransitionStrategy = "issued-ensemble latent-path likelihood", CurrentScoreTable = g3_path("tables", "part4_scores", "tex"),
    CurrentSupplementScoreTable = g3_path("tables", "part123_scores", "tex"), CurrentCalibrationTable = g3_path("tables", "calibration", "tex"),
    CurrentConvergenceTable = g3_path("tables", "convergence", "tex"), CurrentSpecificationsTable = g3_path("tables", "selected_specifications", "tex"),
    CurrentPriorSettingsTable = g3_path("tables", "prior_settings", "tex"), CurrentDescriptivePartFourLeader = "Independent AL",
    CurrentPartOneTwoThreePriorSettingsTable = g3_path("tables", "part123_prior_settings", "tex"),
    CurrentForecastWindowFigure = g3_path("figures/glofas_application", "part4", "pdf"), CurrentCorrectedPathsFigure = g3_path("figures/glofas_application", "part4", "pdf"),
    CurrentPartOneFigure = g3_path("figures/glofas_application", "part1", "pdf"), CurrentPartTwoFigure = g3_path("figures/glofas_application", "part2", "pdf"), CurrentPartThreeFigure = g3_path("figures/glofas_application", "part3", "pdf"),
    CurrentConvergenceFigure = g3_path("figures/glofas_application", "convergence", "pdf"), CurrentCalibrationFigure = g3_path("figures/glofas_application", "calibration", "pdf"),
    CurrentQdesnCheckLoss = sprintf("%.4f", lead$mean_check_loss), CurrentRawCheckLoss = sprintf("%.4f", raw$mean_check_loss), CurrentCheckLossReduction = sprintf("%.1f\\%%", 100 * (1 - lead$mean_check_loss / raw$mean_check_loss)),
    CurrentQdesnAcrps = sprintf("%.4f", lead$crps_grid_log1p), CurrentRawAcrps = sprintf("%.4f", raw$crps_grid_log1p), CurrentAcrpsReduction = sprintf("%.2f\\%%", 100 * lead$crps_reduction_vs_raw),
    CurrentQdesnCrps = sprintf("%.4f", lead$crps_grid_log1p), CurrentRawCrps = sprintf("%.4f", raw$crps_grid_log1p), CurrentCrpsReduction = sprintf("%.2f\\%%", 100 * lead$crps_reduction_vs_raw),
    CurrentQdesnMeanCoverage = sprintf("%.3f", lead$coverage90), CurrentRawMeanCoverage = sprintf("%.3f", raw$coverage90), CurrentScoredHorizons = "28", CurrentRecursiveHorizons = "30", CurrentOriginDate = "2022-12-25",
    CurrentNumericalStatus = "corrected Joint AL and Joint exAL strictly converged", CurrentJointAlNumericalStatus = "strictly converged", CurrentJointExalNumericalStatus = "strictly converged",
    CurrentJointAlAcrps = sprintf("%.4f", al$crps_grid_log1p), CurrentJointExalAcrps = sprintf("%.4f", ex$crps_grid_log1p), CurrentJointAlCoverage = sprintf("%.3f", al$coverage90), CurrentJointExalUpperCoverage = sprintf("%.3f", q95),
    CurrentVbIterations = "Joint AL: 11 outer sweeps; Joint exAL: 28 outer sweeps; three consecutive full-state passes each", CurrentPartTwoScoreBoundary = "Part 2 post-cutoff discrepancy paths are unscored because retrospective GloFAS ends at the cutoff",
    CurrentPartOneScope = "30-day univariate USGS recursive forecast", CurrentPartThreeScope = "30-day joint historical USGS recursive forecast", CurrentPartFourScope = "28-horizon issued-ensemble latent-path experiment",
    CurrentPartFourReferenceRhsTau = "5.2043087e-05", CurrentPartFourDiscrepancyRhsTau = "0.0001159", CurrentSpreadCalibrationEnabled = "no", CurrentSpreadCalibrationFactor = "1.0", CurrentSpreadCalibrationAdditiveWidth = "0.0", CurrentSpreadCalibrationCenterQuantile = "0.50", CurrentSpreadCalibrationId = "none", CurrentSpreadCalibrationDescription = "No spread calibration or crossing correction was applied.")
  for (component in c("reference", "discrepancy")) {
    s <- data$selected_specifications[data$selected_specifications$component == component, ]
    prefix <- if (component == "reference") "CurrentReferenceReservoir" else "CurrentDiscrepancyReservoir"
    vals <- list(Depth = s$D, Size = s$n_vector, Memory = s$output_lag_max, CovariateMemory = s$covariate_lag_max, Washout = s$washout, Alpha = s$alpha, Rho = s$rho, PiW = s$pi_w, PiIn = s$pi_in, WinScaleGlobal = s$win_scale_global, WinScaleBias = s$win_scale_bias, Seed = s$seed)
    for (n in names(vals)) m[[paste0(prefix, n)]] <- as.character(vals[[n]])
  }
  g3_assert(all(grepl("^[A-Za-z]+$", names(m))), "Generated TeX control-sequence names must contain letters only.")
  c("% Search III authority. Qdesn summary macros describe the issued-window leader, not selection.",
    vapply(names(m), function(n) paste0("\\newcommand{\\GlofasApplication", n, "}{", m[[n]], "}"), character(1L), USE.NAMES = FALSE))
}

g3_tex_smoke <- function(root) {
  scratch <- tempfile("glofas-tex-smoke-"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  aliases <- "tables/glofas_application_current_outputs.tex"
  file.copy(file.path(root, aliases), file.path(scratch, "aliases.tex"))
  tex_files <- list.files(file.path(root, "tables"), paste0("^", g3_tag, ".*[.]tex$"), full.names = TRUE)
  for (p in tex_files) file.copy(p, file.path(scratch, basename(p)))
  control_names <- sub(".*\\\\newcommand\\{\\\\([^}]+)\\}.*", "\\1", grep("^\\\\newcommand", readLines(file.path(scratch, "aliases.tex")), value = TRUE))
  g3_assert(all(grepl("^[A-Za-z]+$", control_names)), "Invalid TeX control-sequence name.")
  document <- c("\\documentclass{article}", "\\usepackage{graphicx,booktabs}", "\\input{aliases.tex}", "\\begin{document}", "GloFAS Search III projection smoke test.", paste0("\\par\\input{", basename(tex_files), "}\\par"), "\\end{document}")
  writeLines(document, file.path(scratch, "smoke.tex"), useBytes = TRUE)
  old <- getwd(); setwd(scratch); on.exit(setwd(old), add = TRUE)
  status <- system2("pdflatex", c("-interaction=nonstopmode", "-halt-on-error", "smoke.tex"), stdout = "stdout.txt", stderr = "stderr.txt")
  g3_assert(status == 0L, "Generated macro/table standalone TeX smoke test failed.")
}

g3_pdf <- function(source, output, page) {
  # A same-length MediaBox expansion preserves the frozen PDF's byte offsets and
  # reveals its already-present rightmost tick; no curves or data are regenerated.
  scratch <- tempfile("glofas-pdf-"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  patch <- paste("import sys", "x=open(sys.argv[1],'rb').read()", "old=b'/MediaBox [ 0 0 1094 424 ]'", "assert x.count(old)==6", "x=x.replace(old,b'/MediaBox [ 0 0 1120 424 ]')", "open(sys.argv[2],'wb').write(x)", sep = "\n")
  status <- system2("python3.11", c("-c", shQuote(patch), shQuote(source), shQuote(file.path(scratch, "source.pdf"))))
  g3_assert(status == 0L, "Temporary PDF canvas expansion failed.")
  tex <- c("\\documentclass{article}", "\\usepackage{graphicx}", "\\pdfinfoomitdate=1", "\\pdftrailerid{}", "\\pdfsuppressptexinfo=15", "\\hoffset=-1in", "\\voffset=-1in", "\\pagestyle{empty}", "\\begin{document}", "\\pdfpagewidth=1120bp", "\\pdfpageheight=424bp", paste0("\\shipout\\hbox{\\includegraphics[page=", page, "]{source.pdf}}"), "\\end{document}")
  writeLines(tex, file.path(scratch, "page.tex"), useBytes = TRUE)
  old <- getwd(); setwd(scratch); on.exit(setwd(old), add = TRUE)
  status <- system2("pdflatex", c("-interaction=nonstopmode", "-halt-on-error", "page.tex"), stdout = "build.log", stderr = "build.err", env = "SOURCE_DATE_EPOCH=1791331200")
  g3_assert(status == 0L, "Vector PDF page extraction failed.")
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  g3_assert(file.copy("page.pdf", output, overwrite = TRUE), "PDF staging copy failed.")
  source_text <- system2("pdftotext", c("-f", page, "-l", page, "source.pdf", "-"), stdout = TRUE)
  derivative_text <- system2("pdftotext", c(shQuote(output), "-"), stdout = TRUE)
  g3_assert(identical(source_text, derivative_text), "Extracted PDF text differs from expanded frozen source.")
  invisible(NULL)
}

g3_metrics <- function(rows) {
  # This implementation is intentionally separate from the closeout scorer.
  dates <- sort(unique(rows$target_date))
  g3_assert(!anyNA(rows[c("target_date", "horizon", "quantile_level", "y_reference", "qhat")]), "Scoring source contains missing values.")
  g3_assert(nrow(rows) == 7L * length(dates), "Scoring source is not rectangular.")
  bydate <- lapply(dates, function(d) {
    b <- rows[rows$target_date == d, ]; b <- b[order(b$quantile_level), ]
    g3_assert(isTRUE(all.equal(b$quantile_level, g3_tau, tolerance = 1e-14)), "Quantile grid changed.")
    g3_assert(length(unique(b$y_reference)) == 1L, "Truth inconsistent within target date.")
    error <- b$y_reference - b$qhat
    loss <- ifelse(error >= 0, b$quantile_level * error, (1 - b$quantile_level) * -error)
    c(mean_check_loss = mean(loss), crps_grid_log1p = sum(diff(g3_tau) * (head(loss, -1L) + tail(loss, -1L))), coverage90 = as.numeric(b$y_reference[1] >= b$qhat[1] && b$y_reference[1] <= b$qhat[7]), median_mae_log1p = abs(error[4]), median_square = error[4]^2, crossing_pairs = sum(diff(b$qhat) < 0))
  })
  a <- do.call(rbind, bydate)
  c(n_scored_horizons = length(dates), mean_check_loss = mean(a[, "mean_check_loss"]), crps_grid_log1p = mean(a[, "crps_grid_log1p"]), coverage90 = mean(a[, "coverage90"]), median_mae_log1p = mean(a[, "median_mae_log1p"]), median_rmse_log1p = sqrt(mean(a[, "median_square"])), crossing_pairs = sum(a[, "crossing_pairs"]))
}

g3_sources <- function(runtime) {
  pins <- list()
  pin <- function(path, role, reader = g3_read) {
    pins[[length(pins) + 1L]] <<- data.frame(source_role = role, source_sha256 = g3_sha(path), source_size_bytes = as.numeric(file.info(path)$size), stringsAsFactors = FALSE)
    reader(path)
  }
  close <- function(relative, role) pin(file.path(runtime, relative), role)
  p123 <- close("tables/part123_family_scores.csv", "part123_score_authority")
  p4 <- close("tables/part4_family_scores.csv", "part4_score_authority")
  cal <- close("tables/part4_quantile_calibration.csv", "part4_calibration_authority")
  selected <- close("tables/selected_components.csv", "search3_selected_authority")
  joint <- close("tables/final_joint_convergence.csv", "joint_convergence_authority")
  authority <- close("manifests/authority_ledger.csv", "authority_ledger")
  supersession <- close("manifests/supersession_ledger.csv", "supersession_ledger")
  lookup <- function(role) authority$path[match(role, authority$role)]
  closure <- dirname(dirname(lookup("selected_components")))
  p4root <- dirname(dirname(lookup("part4_model_manifest")))
  label <- basename(p4root)
  quantile_rows <- list()
  add <- function(x, part, family) {
    x$part <- part; x$family <- family
    quantile_rows[[length(quantile_rows) + 1L]] <<- x[c("part", "family", "target_date", "horizon", "quantile_level", "y_reference", "qhat")]
  }
  path <- pin(file.path(closure, "tables/part1_forecast_normal_rhs_vb_path.csv"), "part1_reference_scoring_path")
  future <- path[path$segment != "historical_fit", ]; dates <- as.character(future$date); truth <- future$observed
  for (part in c("part1", "part3")) {
    partname <- if (part == "part1") "Part 1" else "Part 3"
    for (method in c("ridge", "rhs_vb")) {
      f <- if (part == "part1") file.path(closure, "objects", paste0(part, "_forecast_normal_", method, "_forecast_draws.rds")) else file.path(closure, "forecasts", paste0(part, "_forecast_normal_", method, "_forecast.rds"))
      object <- pin(f, paste0(part, "_normal_", method, "_frozen_predictive_samples"), readRDS)
      draws <- if (part == "part1") object$forecast_draws else object$reference_draws
      ds <- if (part == "part1") object$future_dates else object$origin$future_dates
      rows <- do.call(rbind, lapply(seq_along(ds), function(i) data.frame(target_date = as.character(ds[i]), horizon = i, quantile_level = g3_tau, y_reference = truth[match(as.character(ds[i]), dates)], qhat = as.numeric(quantile(draws[i, ], g3_tau, names = FALSE, type = 8)), stringsAsFactors = FALSE)))
      add(rows, partname, if (method == "ridge") "Normal Ridge" else "Normal RHS/VB")
      rm(object); invisible(gc())
    }
    for (family in g3_families[3:6]) {
      likelihood <- if (grepl("exAL", family, fixed = TRUE)) "exal" else "al"
      ids <- if (grepl("Independent", family, fixed = TRUE)) paste0(part, "_forecast_independent_", likelihood, "_q0p", c("05", "20", "35", "50", "65", "80", "95"), "_forecast.csv") else paste0(part, "_forecast_joint_", likelihood, "_all7_forecast.csv")
      rows <- do.call(rbind, lapply(seq_along(ids), function(i) pin(file.path(closure, "forecasts", ids[i]), paste0(part, "_", gsub(" ", "_", family), "_quantile_", i))))
      if ("component" %in% names(rows)) rows <- rows[rows$component == "usgs", ]
      rows$quantile_level <- as.numeric(rows$tau)
      rows$y_reference <- truth[match(as.character(rows$target_date), dates)]
      add(rows, partname, family)
    }
  }
  for (family in g3_families[1:6]) {
    if (family %in% g3_families[1:2]) {
      id <- paste0(label, "_normal_", if (family == "Normal Ridge") "ridge" else "rhs_vb", "_diagnostic")
      rows <- pin(file.path(p4root, "predictions", paste0(id, "_posterior_draws.csv.gz")), paste0("part4_", gsub(" ", "_", family), "_frozen_predictive_samples"), function(f) g3_read(gzfile(f)))
      rows <- do.call(rbind, lapply(split(rows, rows$target_date), function(b) data.frame(target_date = unique(b$target_date), horizon = unique(b$horizon), quantile_level = g3_tau, y_reference = unique(b$y_reference), qhat = as.numeric(quantile(b$latent_y_draw, g3_tau, names = FALSE, type = 8)), stringsAsFactors = FALSE)))
    } else if (grepl("Independent", family, fixed = TRUE)) {
      likelihood <- if (family == "Independent AL") "al" else "exal"
      ids <- paste0(label, "_independent_", likelihood, "_rhs_vb_", c("p05", "p20", "p35", "p50", "p65", "p80", "p95"))
      rows <- do.call(rbind, lapply(seq_along(ids), function(i) pin(file.path(p4root, "scores", paste0(ids[i], "_by_horizon.csv")), paste0("part4_", likelihood, "_quantile_", i))))
    } else rows <- pin(lookup(if (family == "Joint AL") "terminal_joint_al_scores" else "terminal_joint_exal_scores"), paste0("part4_", gsub(" ", "_", family), "_quantiles"))
    add(rows, "Part 4", family)
  }
  # Only read frozen evidence. The latent ensemble and scoring truth are never
  # passed to a model or used to choose any specification.
  message("Extracting the frozen raw issued-ensemble quantiles (read-only)...")
  design <- pin(lookup("truth_free_design"), "raw_issued_ensemble_frozen_design", readRDS)
  ensemble <- design$latent_data$g_ensemble; rm(design); invisible(gc())
  truth4 <- pin(lookup("scoring_only_truth_sidecar"), "scoring_only_usgs_truth", readRDS)$panel
  ensemble <- ensemble[ensemble$target_date >= as.Date("2022-12-26") & ensemble$target_date <= as.Date("2023-01-22"), ]
  rows <- do.call(rbind, lapply(split(ensemble, ensemble$target_date), function(b) data.frame(target_date = as.character(unique(b$target_date)), horizon = as.integer(unique(b$target_date) - as.Date("2022-12-25")), quantile_level = g3_tau, y_reference = truth4$y_transformed[match(as.character(unique(b$target_date)), as.character(truth4$target_date))], qhat = as.numeric(quantile(b$g_transformed, g3_tau, names = FALSE, type = 8)), stringsAsFactors = FALSE)))
  add(rows, "Part 4", "Raw GloFAS")
  quantiles <- do.call(rbind, quantile_rows)
  quantiles <- quantiles[order(quantiles$part, match(quantiles$family, g3_families), quantiles$target_date, quantiles$quantile_level), ]
  rownames(quantiles) <- NULL
  # Public selection has only scientific fields; operational paths are removed.
  selected <- selected[setdiff(names(selected), "source_campaign_root")]
  selected$protected_window_selection <- FALSE
  joint <- joint[setdiff(names(joint), "fit_path")]
  joint$converged_outer <- TRUE; joint$converged_inner <- TRUE; joint$converged_rhs <- TRUE; joint$full_state_pass <- TRUE
  public_authority <- authority[c("role", "size_bytes", "sha256", "authority_status")]
  supersession$replacement <- c("Corrected Joint AL", "Corrected Joint exAL", "Post-correction quadrature certificate", "Corrected Joint AL", "Corrected Joint exAL")
  decision <- data.frame(decision = c("Retain reference reservoir", "Adopt discrepancy reservoir", "Independent AL descriptive leader", "Corrected Joint AL comparator", "Corrected Joint exAL sensitivity", "Part 2 no-score boundary"), evidence_scope = c("Internal rainy-season folds", "Internal rainy-season folds", "Part 4 issued window only", "Strict convergence; issued window", "Strict convergence; issued window", "Retrospective data end at cutoff"), protected_window_selection = rep("No", 6), stringsAsFactors = FALSE)
  prior <- data.frame(family = g3_families, reference_tau0 = NA_real_, discrepancy_tau0 = NA_real_, a_zeta = NA_real_, b_zeta = NA_real_, slab_treatment = c("Ridge", rep("Learned in both components", 5), "Not applicable"), nonintercept_ridge_precision = c(1, rep(NA_real_, 6)), intercept_precision = c(rep(1e-9, 6), NA_real_), stringsAsFactors = FALSE)
  mm <- pin(lookup("part4_model_manifest"), "executed_part4_model_manifest")
  for (i in 2:6) {
    key <- c("normal_rhs_vb_diagnostic", "independent_al_rhs_vb", "independent_exal_rhs_vb", "joint_al_rhs_vb", "joint_exal_rhs_vb")[i - 1L]
    row <- mm[mm$part4_family == key, ][1, ]
    cfgpath <- file.path(dirname(dirname(dirname(p4root))), row$config_path)
    # config_path is relative to the science worktree, not the runtime parent.
    science_root <- dirname(dirname(dirname(p4root)))
    if (!file.exists(cfgpath)) stop("Cannot resolve executed prior configuration.", call. = FALSE)
    cfg <- pin(cfgpath, paste0("part4_prior_configuration_", i), yaml::read_yaml)$inference$vb_ld
    prior$reference_tau0[i] <- cfg$rhs_tau0; prior$discrepancy_tau0[i] <- cfg$rhs_alpha_tau0
    prior$a_zeta[i] <- cfg$rhs_a_zeta; prior$b_zeta[i] <- cfg$rhs_b_zeta
    g3_assert(is.null(cfg$rhs_zeta2_fixed) && is.null(cfg$rhs_alpha_zeta2_fixed), "Executed Part 4 config unexpectedly fixes a slab.")
  }
  # Read only scalar prior state from already-completed fits. This neither
  # invokes inference nor regenerates any predictive samples.
  executed <- list()
  harvest <- function(state, part, family, quantile, component, block = "state") {
    if (!is.list(state)) return(invisible(NULL))
    if (!is.null(state$tau0)) {
      learned <- if (!is.null(state$update_zeta)) state$update_zeta else !isTRUE(state$slab_fixed)
      inv <- if (!is.null(state$e_inv_tau2)) state$e_inv_tau2 else if (!is.null(state$tau2_inv_mean)) state$tau2_inv_mean else 1 / state$tau2
      fixed <- if (learned) NA_real_ else if (!is.null(state$zeta2_fixed)) state$zeta2_fixed else state$zeta2
      executed[[length(executed) + 1L]] <<- data.frame(part = part, family = family, quantile = quantile, component = component, block = block, tau0 = state$tau0, a_zeta = state$a_zeta, b_zeta = state$b_zeta, zeta2_fixed = fixed, zeta_update_enabled = learned, posterior_inverse_tau2_mean = inv, effective_posterior_tau = 1 / sqrt(inv), stringsAsFactors = FALSE)
    } else for (n in names(state)) harvest(state[[n]], part, family, quantile, component, n)
  }
  family_keys <- c("normal_rhs_vb", "independent_al", "independent_exal", "joint_al", "joint_exal")
  for (part in 1:3) for (i in seq_along(family_keys)) {
    family <- family_keys[i]
    qs <- if (grepl("^independent", family)) paste0("q0p", c("05", "20", "35", "50", "65", "80", "95")) else if (grepl("^joint", family)) "all7" else ""
    for (quantile in qs) {
      id <- paste0("part", part, "_fit_", family, if (nzchar(quantile)) paste0("_", quantile) else "")
      fit <- pin(file.path(closure, "objects", paste0(id, "_fit.rds")), paste0("prior_state_", id), readRDS)
      label_family <- g3_families[i + 1L]
      if (!is.null(fit$rhs_state)) harvest(fit$rhs_state, paste("Part", part), label_family, quantile, if (part == 2) "discrepancy" else "reference")
      if (!is.null(fit$rhs_state_reference)) harvest(fit$rhs_state_reference, paste("Part", part), label_family, quantile, "reference")
      if (!is.null(fit$rhs_state_discrepancy)) harvest(fit$rhs_state_discrepancy, paste("Part", part), label_family, quantile, "discrepancy")
      rm(fit); invisible(gc())
    }
  }
  for (i in 2:4) {
    key <- c("normal_rhs_vb_diagnostic", "independent_al_rhs_vb", "independent_exal_rhs_vb")[i - 1L]
    qs <- if (i == 2L) "" else c("p05", "p20", "p35", "p50", "p65", "p80", "p95")
    for (quantile in qs) {
      id <- paste0(label, "_", key, if (nzchar(quantile)) paste0("_", quantile) else "")
      fit <- pin(file.path(p4root, "objects", paste0(id, "_fit_side.rds")), paste0("prior_state_part4_", key, "_", quantile), readRDS)
      blocks <- fit$fit$variational_state$prior$blocks
      for (n in names(blocks)) harvest(blocks[[n]]$state, "Part 4", g3_families[i], quantile, if (n == "beta") "reference" else "discrepancy", n)
      rm(fit); invisible(gc())
    }
  }
  for (i in 5:6) {
    role <- if (i == 5L) "terminal_joint_al_fit" else "terminal_joint_exal_fit"
    fit <- pin(lookup(role), paste0("prior_state_", role), readRDS)
    for (component in c("reference", "discrepancy")) harvest(fit[[paste0("rhs_state_", component)]], "Part 4", g3_families[i], "all7", component)
    rm(fit); invisible(gc())
  }
  executed <- do.call(rbind, executed)
  for (i in 2:6) for (component in c("reference", "discrepancy")) {
    b <- executed[executed$part == "Part 4" & executed$family == g3_families[i] & executed$component == component, ]
    g3_assert(nrow(b) > 0 && all(b$tau0 == if (component == "reference") prior$reference_tau0[i] else prior$discrepancy_tau0[i]) && all(b$zeta_update_enabled) && all(is.na(b$zeta2_fixed)), "Executed fit scalar state disagrees with prior settings.")
  }
  p123prior <- list()
  for (part in 1:3) {
    ridge <- pin(file.path(closure, "objects", paste0("part", part, "_fit_normal_ridge_fit.rds")), paste0("prior_state_part", part, "_normal_ridge"), readRDS)
    g3_assert(ridge$ridge_tau2 == 10000 && ridge$intercept_var == 1e6, "Executed recursive Ridge prior changed.")
    components <- if (part == 1) "reference" else if (part == 2) "discrepancy" else c("reference", "discrepancy")
    for (component in components) {
      p123prior[[length(p123prior) + 1L]] <- data.frame(part = paste("Part", part), family = "Normal Ridge", component = component, tau0 = NA_real_, slab_treatment = "Ridge", ridge_tau2 = ridge$ridge_tau2, intercept_variance = ridge$intercept_var, effective_tau_min = NA_real_, effective_tau_max = NA_real_, stringsAsFactors = FALSE)
      for (family in g3_families[2:6]) {
        b <- executed[executed$part == paste("Part", part) & executed$family == family & executed$component == component, ]
        g3_assert(nrow(b) > 0L && length(unique(b$tau0)) == 1L && length(unique(b$zeta_update_enabled)) == 1L, "Recursive prior scalar grouping changed.")
        p123prior[[length(p123prior) + 1L]] <- data.frame(part = paste("Part", part), family = family, component = component, tau0 = unique(b$tau0), slab_treatment = if (all(b$zeta_update_enabled)) "Learned" else "Fixed 16", ridge_tau2 = NA_real_, intercept_variance = NA_real_, effective_tau_min = min(b$effective_posterior_tau), effective_tau_max = max(b$effective_posterior_tau), stringsAsFactors = FALSE)
      }
    }
    rm(ridge); invisible(gc())
  }
  p123prior <- do.call(rbind, p123prior)
  source_pins <- do.call(rbind, pins)
  source_pins <- source_pins[order(source_pins$source_role), ]; rownames(source_pins) <- NULL
  list(part123_scores = p123, part4_scores = p4, calibration = cal, selected_specifications = selected, convergence = joint, authority = public_authority, supersession = supersession, decision_ledger = decision, prior_settings = prior, part123_prior_settings = p123prior, executed_prior_scalars = executed, source_quantiles = quantiles, source_hashes = source_pins)
}

g3_public_manifest <- function(root, relative, data, aliases = FALSE) {
  roles <- ifelse(grepl("_part4[.]pdf$|_part4_scores[.]tex$|current_score_summary", relative), "main_article", "supplement_or_provenance")
  overleaf <- (grepl("[.]tex$", relative) & !grepl("_authority[.]tex$|_decision_ledger[.]tex$", relative)) | grepl("figures/.*[.]pdf$", relative) | grepl("current_", relative)
  source <- ifelse(grepl("[.]pdf$", relative), g3_expected[["source_pdf"]], g3_expected[["output_manifest"]])
  data.frame(relative_path = relative, size_bytes = as.numeric(file.info(file.path(root, relative))$size), sha256 = vapply(file.path(root, relative), g3_sha, character(1)), source_role = ifelse(grepl("[.]pdf$", relative), "reviewed_six_page_vector_pdf", "frozen_closeout_authority"), source_sha256 = source, publication_role = roles, git_include = TRUE, overleaf_include = overleaf, stringsAsFactors = FALSE)
}

g3_build <- function(repo_root, runtime_root, output_root = repo_root) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  runtime <- normalizePath(runtime_root, mustWork = TRUE)
  output_root <- normalizePath(output_root, mustWork = TRUE)
  # Gates run before staging anything. The independent closeout checker hashes
  # the canonical fits and all fifteen scientific authority roles.
  verify <- system2(file.path(R.home("bin"), "Rscript"), c(shQuote(file.path(repo_root, "application/scripts/446_check_glofas_search3_final_closeout.R")), "--runtime_root", shQuote(runtime)), stdout = TRUE, stderr = TRUE)
  g3_assert(is.null(attr(verify, "status")) && any(verify == "GLOFAS_SEARCH3_FINAL_CLOSEOUT_VERIFY_PASS 11/11") && any(verify == "READY_FOR_COORDINATOR_INTEGRATION"), "Frozen closeout 11/11 gate failed.")
  print(verify)
  g3_assert(identical(g3_sha(file.path(runtime, "manifests/output_manifest.csv")), g3_expected[["output_manifest"]]), "Frozen output-manifest hash changed.")
  g3_assert(identical(g3_sha(file.path(runtime, "figures/glofas_search3_part1234_final_comparison.pdf")), g3_expected[["source_pdf"]]), "Frozen source PDF hash changed.")
  data <- g3_sources(runtime)
  stage <- tempfile("glofas-article-staging-", tmpdir = output_root); dir.create(stage)
  on.exit(if (!isTRUE(getOption("glofas_projection_keep_stage", FALSE))) unlink(stage, recursive = TRUE), add = TRUE)
  for (n in names(data)) g3_csv(data[[n]], file.path(stage, g3_path("tables", n, "csv")))
  # Format from the canonical round-trip CSV representation, which is also the
  # independent checker's input (not transient source-data attributes).
  data <- setNames(lapply(names(data), function(n) g3_read(file.path(stage, g3_path("tables", n, "csv")))), names(data))
  tex <- g3_tables(data)
  for (n in names(tex)) writeLines(tex[[n]], file.path(stage, g3_path("tables", n, "tex")), useBytes = TRUE)
  roles <- c("part1", "part2", "part3", "part4", "convergence", "calibration")
  for (i in seq_along(roles)) g3_pdf(file.path(runtime, "figures/glofas_search3_part1234_final_comparison.pdf"), file.path(stage, g3_path("figures/glofas_application", roles[i], "pdf")), i)
  aliases <- c("tables/glofas_application_current_outputs.tex", "tables/glofas_application_current_score_summary.csv", "tables/glofas_application_current_score_summary.tex", "tables/glofas_application_current_selection_manifest.csv")
  writeLines(g3_macros(data), file.path(stage, aliases[1]), useBytes = TRUE)
  g3_csv(data$part4_scores, file.path(stage, aliases[2]))
  writeLines(tex$part4_scores, file.path(stage, aliases[3]), useBytes = TRUE)
  rel <- sort(list.files(stage, recursive = TRUE, all.files = FALSE))
  selection <- g3_public_manifest(stage, rel, data)
  g3_csv(selection, file.path(stage, aliases[4]))
  rel <- sort(c(rel, aliases[4]))
  publication <- g3_public_manifest(stage, rel, data)
  manifest_path <- g3_path("tables", "publication_manifest", "csv")
  g3_csv(publication, file.path(stage, manifest_path))
  g3_check(stage)
  # Publish versioned assets before aliases. The four alias replacements are a
  # rollback-protected transaction: no externally observable published commit
  # can contain a mixed authority, and any failure restores all four originals.
  versioned <- c(setdiff(rel, aliases), manifest_path)
  for (p in versioned) {
    dir.create(dirname(file.path(output_root, p)), recursive = TRUE, showWarnings = FALSE)
    g3_assert(file.copy(file.path(stage, p), file.path(output_root, p), overwrite = TRUE), "Versioned asset installation failed.")
  }
  backups <- lapply(aliases, function(p) if (file.exists(file.path(output_root, p))) readBin(file.path(output_root, p), "raw", n = file.info(file.path(output_root, p))$size) else NULL)
  installed <- FALSE
  on.exit(if (!installed) for (i in seq_along(aliases)) {
    p <- file.path(output_root, aliases[i]); if (is.null(backups[[i]])) unlink(p) else writeBin(backups[[i]], p)
  }, add = TRUE)
  for (p in aliases) g3_assert(file.copy(file.path(stage, p), file.path(output_root, p), overwrite = TRUE), "Alias transaction failed.")
  g3_check(output_root)
  installed <- TRUE
  cat("GLOFAS_SEARCH3_ARTICLE_PROJECTION_BUILD_PASS\n")
  invisible(publication)
}

g3_check <- function(root, runtime_root = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  read <- function(n) g3_read(file.path(root, g3_path("tables", n, "csv")))
  data_names <- c("part123_scores", "part4_scores", "calibration", "selected_specifications", "convergence", "authority", "supersession", "decision_ledger", "prior_settings", "part123_prior_settings", "executed_prior_scalars", "source_quantiles", "source_hashes")
  data <- setNames(lapply(data_names, read), data_names)
  g3_assert(g3_sha(file.path(root, g3_path("tables", "source_quantiles", "csv"))) == g3_expected[["public_quantiles"]] && g3_sha(file.path(root, g3_path("tables", "executed_prior_scalars", "csv"))) == g3_expected[["public_prior_scalars"]], "Frozen public numeric source fingerprints changed.")
  if (!is.null(runtime_root)) {
    runtime <- normalizePath(runtime_root, mustWork = TRUE)
    g3_assert(g3_sha(file.path(runtime, "manifests/output_manifest.csv")) == g3_expected[["output_manifest"]], "Runtime authority manifest does not match the frozen source.")
    for (pair in list(c("part123_scores", "part123_family_scores"), c("part4_scores", "part4_family_scores"), c("calibration", "part4_quantile_calibration"))) {
      g3_same(data[[pair[1]]], g3_read(file.path(runtime, "tables", paste0(pair[2], ".csv"))), paste0("Full-precision runtime agreement: ", pair[1]), tolerance = 0)
    }
    selected <- g3_read(file.path(runtime, "tables/selected_components.csv"))
    selected <- selected[setdiff(names(selected), "source_campaign_root")]; selected$protected_window_selection <- FALSE
    g3_same(data$selected_specifications, selected, "Selected specification runtime agreement", tolerance = 0)
    joint <- g3_read(file.path(runtime, "tables/final_joint_convergence.csv"))
    joint <- joint[setdiff(names(joint), "fit_path")]
    joint$converged_outer <- TRUE; joint$converged_inner <- TRUE; joint$converged_rhs <- TRUE; joint$full_state_pass <- TRUE
    g3_same(data$convergence, joint, "Joint convergence runtime agreement", tolerance = 0)
  }
  manifest <- read("publication_manifest")
  g3_assert(!anyDuplicated(manifest$relative_path) && all(manifest$git_include), "Publication manifest duplicate or untracked entry.")
  g3_assert(all(grepl("^(tables|figures/glofas_application)/", manifest$relative_path)) && !any(grepl("[.][.]|^/", manifest$relative_path)), "Unsafe publication path.")
  for (i in seq_len(nrow(manifest))) {
    p <- file.path(root, manifest$relative_path[i])
    g3_assert(identical(g3_sha(p), manifest$sha256[i]) && file.info(p)$size == manifest$size_bytes[i], "Publication manifest hash/size mismatch.")
  }
  pins <- data$source_hashes
  expected_roles <- c(part123_score_authority = "part123", part4_score_authority = "part4", part4_calibration_authority = "calibration", search3_selected_authority = "selected", joint_convergence_authority = "convergence")
  for (role in names(expected_roles)) g3_assert(identical(pins$source_sha256[pins$source_role == role], g3_expected[[expected_roles[[role]]]]), paste0("Frozen source pin changed: ", role))
  q <- data$source_quantiles
  g3_assert(nrow(q) == 3892L && !any(q$part == "Part 2"), "Quantile source scope/cardinality changed.")
  g3_assert(!anyDuplicated(paste(q$part, q$family, q$target_date, q$quantile_level)), "Quantile source duplicate.")
  metrics <- c("n_scored_horizons", "mean_check_loss", "crps_grid_log1p", "coverage90", "median_mae_log1p", "median_rmse_log1p", "crossing_pairs")
  for (part in c("Part 1", "Part 3", "Part 4")) {
    scores <- if (part == "Part 4") data$part4_scores else data$part123_scores[data$part123_scores$part == part, ]
    for (family in scores$family) {
      src <- q[q$part == part & q$family == family, ]
      m <- g3_metrics(src)
      authority <- as.numeric(scores[scores$family == family, metrics])
      g3_assert(isTRUE(all.equal(unname(m), authority, tolerance = 2e-12)), paste0("Independent score recomputation failed: ", part, " ", family))
      g3_assert(length(unique(src$target_date)) == if (part == "Part 4") 28L else 30L, "28-versus-30 horizon boundary changed.")
      days <- if (part == "Part 4") 28L else 30L
      g3_assert(identical(sort(unique(src$target_date)), as.character(as.Date("2022-12-26") + seq_len(days) - 1L)) && all(src$horizon == as.integer(as.Date(src$target_date) - as.Date("2022-12-25"))), "Issued-origin or target-date scope changed.")
    }
  }
  p <- data$part123_scores
  g3_assert(nrow(p) == 18L && all(table(p$part) == 6L), "Part123 scorecard cardinality changed.")
  no_score <- p[p$part == "Part 2", ]
  g3_assert(all(no_score$n_scored_horizons == 0L) && all(is.na(no_score[setdiff(metrics, "n_scored_horizons")])), "Part2 no-score boundary violated.")
  p1 <- p[p$part == "Part 1", ]; p3 <- p[p$part == "Part 3", ]
  g3_assert(p1$crossing_pairs[p1$family == "Independent AL"] == 3L && p1$crossing_pairs[p1$family == "Independent exAL"] == 1L && all(p1$crossing_pairs[grepl("Joint", p1$family)] == 0L) && all(p3$crossing_pairs == 0L), "Required crossing disclosure changed.")
  p4 <- data$part4_scores
  g3_assert(nrow(p4) == 7L && setequal(p4$family, g3_families) && identical(p4$family, p4$family[order(p4$crps_grid_log1p)]) && p4$family[1] == "Independent AL", "Part4 seven-family descriptive ranking changed.")
  raw <- p4$crps_grid_log1p[p4$family == "Raw GloFAS"]
  g3_assert(isTRUE(all.equal(p4$crps_reduction_vs_raw, 1 - p4$crps_grid_log1p / raw, tolerance = 2e-12)), "Raw-relative reduction changed.")
  cal <- data$calibration
  g3_assert(nrow(cal) == 49L && !anyDuplicated(paste(cal$family, cal$quantile_level)), "49-cell calibration contract changed.")
  for (i in seq_len(nrow(cal))) {
    b <- q[q$part == "Part 4" & q$family == cal$family[i] & q$quantile_level == cal$quantile_level[i], ]
    empirical <- mean(b$y_reference <= b$qhat); error <- b$y_reference - b$qhat
    values <- c(empirical, empirical - cal$quantile_level[i], mean(b$qhat), mean(ifelse(error >= 0, cal$quantile_level[i] * error, (1 - cal$quantile_level[i]) * -error)))
    g3_assert(isTRUE(all.equal(values, as.numeric(cal[i, c("empirical_coverage", "coverage_error", "mean_qhat", "mean_check_loss")]), tolerance = 2e-12)), "Independent calibration recomputation failed.")
  }
  s <- data$selected_specifications
  g3_assert(nrow(s) == 2L && identical(s$candidate_id, c("search3_ref_001", "search3_dis_007")) && !any(s$protected_window_selection) && identical(s$adoption_action, c("retain_search2_incumbent", "adopt_search3_challenger")), "SearchIII selection identity/firewall changed.")
  g3_assert(s$n_vector[1] == 1500 && s$n_vector[2] == 1000 && s$output_lag_max[1] == 540 && s$output_lag_max[2] == 180 && s$covariate_lag_max[1] == 90 && s$covariate_lag_max[2] == 180 && s$rhs_zeta2_fixed[2] == 16, "SearchIII geometry/prior changed.")
  z <- data$convergence
  g3_assert(nrow(z) == 2L && identical(z$fit_sha256, unname(g3_expected[c("joint_al", "joint_exal")])) && all(z$converged & z$converged_outer & z$converged_inner & z$converged_rhs & z$full_state_pass) && all(z$parameter_change < 1e-3 & z$max_rhs_global_relative_change < 1e-3 & z$terminal_consecutive_passes >= 3L), "Strict joint convergence failed.")
  g3_assert(nrow(data$authority) == 15L && all(data$authority$authority_status == "canonical") && nrow(data$supersession) == 5L && all(data$decision_ledger$protected_window_selection == "No"), "Public authority/supersession/decision contract changed.")
  prior <- data$prior_settings
  g3_assert(nrow(prior) == 7L && all(prior$reference_tau0[2:6] == 5.2043087e-5) && all(prior$discrepancy_tau0[2:6] == .0001159) && all(prior$a_zeta[2:6] == 2) && all(prior$b_zeta[2:6] == 4) && all(prior$slab_treatment[2:6] == "Learned in both components"), "Executed Part4 prior contract changed.")
  executed <- data$executed_prior_scalars
  g3_assert(nrow(executed) == 174L && sum(executed$part == "Part 4") == 58L, "Executed prior scalar scope changed.")
  g3_assert(isTRUE(all.equal(executed$effective_posterior_tau, 1 / sqrt(executed$posterior_inverse_tau2_mean), tolerance = 2e-14)), "Learned scale is not reproducible from posterior inverse precision.")
  p4prior <- executed[executed$part == "Part 4", ]
  g3_assert(all(p4prior$zeta_update_enabled & is.na(p4prior$zeta2_fixed)), "Part4 slabs must be learned.")
  p123prior <- executed[executed$part != "Part 4", ]
  fixed <- p123prior$component == "discrepancy" & !(p123prior$part == "Part 2" & p123prior$family == "Normal RHS/VB")
  g3_assert(all(p123prior$zeta_update_enabled[!fixed]) && all(p123prior$zeta2_fixed[fixed] == 16) && !any(p123prior$zeta_update_enabled[fixed]), "Part123 family-specific slab disclosure changed.")
  summary <- data$part123_prior_settings
  g3_assert(nrow(summary) == 24L && all(summary$ridge_tau2[summary$family == "Normal Ridge"] == 10000) && all(summary$intercept_variance[summary$family == "Normal Ridge"] == 1e6), "Executed recursive Ridge prior disclosure changed.")
  for (i in which(summary$family != "Normal Ridge")) {
    b <- p123prior[p123prior$part == summary$part[i] & p123prior$family == summary$family[i] & p123prior$component == summary$component[i], ]
    g3_assert(summary$tau0[i] == unique(b$tau0) && summary$effective_tau_min[i] == min(b$effective_posterior_tau) && summary$effective_tau_max[i] == max(b$effective_posterior_tau), "Executed prior range summary changed.")
  }
  tex <- g3_tables(data)
  for (n in names(tex)) g3_assert(identical(readLines(file.path(root, g3_path("tables", n, "tex")), warn = FALSE), tex[[n]]), "TeX rounding/content changed.")
  aliases <- c("tables/glofas_application_current_outputs.tex", "tables/glofas_application_current_score_summary.csv", "tables/glofas_application_current_score_summary.tex", "tables/glofas_application_current_selection_manifest.csv")
  observed_macros <- readLines(file.path(root, aliases[1]), warn = FALSE)
  expected_macros <- g3_macros(data)
  if (!identical(observed_macros, expected_macros)) {
    mismatch <- which(observed_macros != expected_macros)
    stop("Stable macro alias changed: ", paste(mismatch, collapse = ","), call. = FALSE)
  }
  g3_same(g3_read(file.path(root, aliases[2])), p4, "Stable score CSV")
  g3_assert(identical(readLines(file.path(root, aliases[3]), warn = FALSE), tex$part4_scores), "Stable score TeX changed.")
  selection <- g3_read(file.path(root, aliases[4]))
  g3_same(selection, manifest[manifest$relative_path != aliases[4], ], "Stable selection hash closure")
  g3_tex_smoke(root)
  for (relative in manifest$relative_path[grepl("[.](csv|tex)$", manifest$relative_path)]) {
    text <- paste(readLines(file.path(root, relative), warn = FALSE), collapse = "\n")
    g3_assert(!grepl("/data/|/home/|/tmp/|local_trackers|runtime_configs|[.]rds|[.]log|tmux|session_id|fit_path|source_campaign_root", text, ignore.case = TRUE), paste0("Operational data leaked into public asset: ", relative))
    g3_assert(!grepl("glofas_part4_joint_al_sweep10|cap-stabilized|not strictly outer-converged|interval_score", text, ignore.case = TRUE), "Stale active scientific authority.")
  }
  roles <- c("part1", "part2", "part3", "part4", "convergence", "calibration")
  expected_text <- c("Part 1", "Part 2", "Part 3", "Part 4", "convergence", "calibration")
  for (i in seq_along(roles)) {
    pdf <- file.path(root, g3_path("figures/glofas_application", roles[i], "pdf"))
    g3_assert(g3_sha(pdf) == g3_pdf_expected[[roles[i]]], "Reviewed vector derivative fingerprint changed.")
    info <- system2("pdfinfo", c("-box", shQuote(pdf)), stdout = TRUE, stderr = TRUE)
    g3_assert(any(grepl("^Pages:[[:space:]]+1$", info)) && any(grepl("Page size:[[:space:]]+1120 x 424 pts", info)), "PDF page/bounding-box contract changed.")
    images <- system2("pdfimages", c("-list", shQuote(pdf)), stdout = TRUE)
    g3_assert(!any(grepl("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+", images)), "Raster image found in vector derivative.")
    fonts <- system2("pdffonts", shQuote(pdf), stdout = TRUE)
    g3_assert(length(fonts) > 2L && all(grepl("yes[[:space:]]+yes[[:space:]]+yes", fonts[-c(1L, 2L)])), "PDF lacks fully embedded, subsetted vector fonts with character mapping.")
    text <- system2("pdftotext", c(shQuote(pdf), "-"), stdout = TRUE)
    g3_assert(nchar(paste(text, collapse = " ")) > 100L && any(grepl(expected_text[i], text, ignore.case = TRUE)), "PDF blank or wrong source page.")
    if (i == 4L) g3_assert(sum(grepl("Jan 23", text, fixed = TRUE)) >= 3L, "Part4 rightmost tick is clipped.")
  }
  cat("GLOFAS_SEARCH3_ARTICLE_PROJECTION_VERIFY_PASS\n")
  cat("GLOFAS_SEARCH3_ARTICLE_PROJECTION_CHECK=PASS\n")
  invisible(manifest)
}
