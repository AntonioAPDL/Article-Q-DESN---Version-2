# Independent, scalar GloFAS reporting calculations. No model or RDS access.
# A consistent packet manifest is not external provenance: callers should pass
# its separately authenticated digest to gspm_verify(). No original truth is read.
gspm_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS publication metrics: ", why), call. = FALSE)
  invisible(TRUE)
}
gspm_families <- function() c("Raw GloFAS", "Normal Ridge", "Normal RHS",
  "Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
gspm_tau <- function() c(.05, .20, .35, .50, .65, .80, .95)
gspm_dates <- function() as.Date("2022-12-25") + seq_len(28L)
gspm_hash <- function(path) unname(tools::sha256sum(path))
gspm_key <- function(data, columns) do.call(paste, c(data[columns], sep = "|"))
gspm_symlink <- function(path) {
  link <- Sys.readlink(path)
  length(link) == 1L && !is.na(link) && nzchar(link)
}

gspm_metrics <- function(rows, truth) {
  q <- gspm_require; families <- gspm_families(); p <- gspm_tau()
  required <- c("family", "target_date", "horizon", "tau", "quantile_transformed", "quantile")
  q(is.data.frame(rows) && !anyDuplicated(names(rows)) && all(required %in% names(rows)) &&
    nrow(rows) == 1372L && setequal(unique(rows$family), families), "complete seven-family grid required")
  q(all(vapply(rows[c("horizon", "tau", "quantile_transformed", "quantile")], is.numeric, logical(1L))) &&
    all(is.finite(as.matrix(rows[c("horizon", "tau", "quantile_transformed", "quantile")]))),
    "finite numeric forecast columns required")
  dates <- as.character(rows$target_date)
  q(all(rows$horizon %in% seq_len(28L)) && !anyNA(dates) &&
    identical(dates, as.character(gspm_dates()[rows$horizon])), "forecast date/horizon alignment differs")
  expected <- expand.grid(family = families, horizon = seq_len(28L), tau = p, stringsAsFactors = FALSE)
  keys <- gspm_key(rows, c("family", "horizon", "tau"))
  q(!anyDuplicated(keys) && setequal(keys, gspm_key(expected, c("family", "horizon", "tau"))),
    "missing, duplicate or changed forecast key")
  inverse <- expm1(rows$quantile_transformed)
  q(all(is.finite(inverse)) && all(abs(rows$quantile - inverse) <=
    1e-10 * pmax(1, abs(rows$quantile))), "inverse transformation differs")
  q(is.data.frame(truth) && !anyDuplicated(names(truth)) &&
    all(c("target_date", "horizon", "y_transformed") %in% names(truth)) && nrow(truth) == 28L &&
    is.numeric(truth$horizon) && is.numeric(truth$y_transformed) &&
    all(is.finite(truth$horizon)) && all(is.finite(truth$y_transformed)) &&
    !anyDuplicated(truth$horizon) && setequal(truth$horizon, seq_len(28L)) &&
    !anyNA(truth$target_date) && identical(as.character(truth$target_date),
      as.character(gspm_dates()[truth$horizon])), "complete finite dated scoring truth required")
  truth <- truth[match(seq_len(28L), truth$horizon), , drop = FALSE]
  day <- list(); cal <- list(); fam <- list(); cross <- list()
  for (fi in seq_along(families)) {
    f <- families[fi]; loss <- matrix(NA_real_, 28L, 7L)
    hit <- matrix(FALSE, 28L, 7L); violations <- matrix(0, 28L, 6L)
    d <- vector("list", 28L)
    for (h in seq_len(28L)) {
      block <- rows[rows$family == f & rows$horizon == h, , drop = FALSE]
      block <- block[match(p, block$tau), , drop = FALSE]
      z <- block$quantile_transformed; y <- truth$y_transformed[h]
      # Literal piecewise check loss, independently of the production scorer.
      for (k in seq_len(7L)) {
        loss[h, k] <- if (y < z[k]) (1 - p[k]) * (z[k] - y) else p[k] * (y - z[k])
        hit[h, k] <- y <= z[k]
      }
      for (k in seq_len(6L)) {
        if (z[k] > z[k + 1L]) violations[h, k] <- z[k] - z[k + 1L]
      }
      # Integral of twice check loss by literal trapezoids, not scorer weights.
      integrated <- 0
      for (k in seq_len(6L)) integrated <- integrated +
        (p[k + 1L] - p[k]) * (loss[h, k] + loss[h, k + 1L])
      d[[h]] <- data.frame(family = f, target_date = as.character(gspm_dates()[h]), horizon = h,
        grid_acrps_log1p = integrated, mean_check_loss = sum(loss[h, ]) / 7,
        covered90 = z[1L] <= y && y <= z[7L], inverted90 = z[1L] > z[7L],
        signed_width90_log1p = z[7L] - z[1L],
        raw_crossing_pairs = sum(violations[h, ] > 0), adjacent_comparisons = 6L,
        mean_positive_adjacent_violation_log1p = sum(violations[h, ]) / 6,
        max_positive_adjacent_violation_log1p = max(violations[h, ]), stringsAsFactors = FALSE)
    }
    d <- do.call(rbind, d); day[[fi]] <- d
    cal[[fi]] <- do.call(rbind, lapply(seq_len(7L), function(k) data.frame(family = f, tau = p[k],
      n_horizons = 28L, empirical_coverage = sum(hit[, k]) / 28,
      coverage_error = sum(hit[, k]) / 28 - p[k], mean_check_loss = sum(loss[, k]) / 28,
      stringsAsFactors = FALSE)))
    count <- sum(violations > 0); covered <- sum(d$covered90)
    cross[[fi]] <- data.frame(family = f, raw_crossing_pairs = count,
      adjacent_comparisons = 168L, raw_crossing_rate = count / 168,
      adjustment_applied = FALSE, stringsAsFactors = FALSE)
    fam[[fi]] <- data.frame(family = f, n_horizons = 28L,
      grid_acrps_log1p = sum(d$grid_acrps_log1p) / 28,
      mean_check_loss = sum(d$mean_check_loss) / 28, covered90_count = covered,
      coverage90 = covered / 28, coverage90_percent = 100 * covered / 28,
      inverted_intervals = sum(d$inverted90),
      mean_signed_width90_log1p = sum(d$signed_width90_log1p) / 28,
      min_signed_width90_log1p = min(d$signed_width90_log1p),
      max_signed_width90_log1p = max(d$signed_width90_log1p), raw_crossing_pairs = count,
      adjacent_comparisons = 168L, raw_crossing_rate = count / 168,
      raw_crossing_percent = 100 * count / 168,
      mean_positive_adjacent_violation_log1p = sum(violations) / 168,
      max_positive_adjacent_violation_log1p = max(violations), stringsAsFactors = FALSE)
  }
  result <- list(family_metrics = do.call(rbind, fam), date_metrics = do.call(rbind, day),
    calibration = do.call(rbind, cal), crossings = do.call(rbind, cross))
  for (name in names(result)) rownames(result[[name]]) <- NULL
  result
}

gspm_compare <- function(observed, expected, keys, label) {
  q <- gspm_require
  q(is.data.frame(observed) && setequal(names(observed), names(expected)) &&
    !anyDuplicated(names(observed)) && nrow(observed) == nrow(expected), paste(label, "schema differs"))
  a <- gspm_key(observed, keys); b <- gspm_key(expected, keys)
  q(!anyDuplicated(a) && setequal(a, b), paste(label, "keys differ"))
  observed <- observed[match(b, a), names(expected), drop = FALSE]
  integer_fields <- c("horizon", "n_horizons", "raw_crossing_pairs", "adjacent_comparisons", "inverted_intervals")
  for (name in names(expected)) {
    x <- observed[[name]]; y <- expected[[name]]
    if (is.logical(y)) {
      valid <- is.logical(x) && !anyNA(x) && identical(unname(x), unname(y))
    } else if (is.numeric(y)) {
      valid <- is.numeric(x) && all(is.finite(x)) &&
        if (name %in% integer_fields) all(x == y) else all(abs(x - y) <= 2e-12)
    } else valid <- identical(as.character(x), as.character(y))
    q(valid, paste(label, name, "values differ"))
  }
  invisible(TRUE)
}

gspm_regular <- function(path) {
  q <- gspm_require
  q(is.character(path) && length(path) == 1L && file.exists(path), "existing regular path required")
  if (!startsWith(path, "/")) path <- file.path(getwd(), path)
  pieces <- strsplit(path, "/", fixed = TRUE)[[1L]]; here <- "/"
  q(!any(pieces == ".."), "parent traversal rejected")
  for (piece in pieces[nzchar(pieces)]) {
    here <- file.path(here, piece); q(!gspm_symlink(here), "symlink input rejected")
  }
  normalizePath(path, mustWork = TRUE)
}

gspm_verify <- function(packet_root, output_root = NULL, expected_manifest_sha256 = NULL) {
  q <- gspm_require
  q(requireNamespace("jsonlite", quietly = TRUE), "jsonlite is required")
  # Do not silently normalize away a supplied symlink before checking it.
  q(!gspm_symlink(packet_root), "symlink packet rejected")
  root <- gspm_regular(packet_root); q(dir.exists(root), "packet directory required")
  required <- c("accepted_producers.json", "DECISION.json", "FORECAST_SEAL.json", "family_scores.csv",
    "progress.json", "quantile_paths.csv", "raw_crossings.csv", "score_contract.json", "scores_by_date.csv",
    "scoring_truth.csv", "quantile_calibration.csv", "TRUTH_DERIVATION.json", "TRUTH_PURPOSE.json")
  q(setequal(list.files(root, all.files = TRUE, no.. = TRUE), c(required, "artifact_manifest.csv")),
    "exact authenticated-v2 packet membership required")
  manifest_path <- file.path(root, "artifact_manifest.csv")
  gspm_regular(manifest_path)
  q(file.info(manifest_path)$size > 0 && file.info(manifest_path)$size <= 1024^2,
    "bounded source manifest required")
  digest <- gspm_hash(manifest_path)
  if (!is.null(expected_manifest_sha256)) q(is.character(expected_manifest_sha256) &&
    length(expected_manifest_sha256) == 1L && identical(digest, expected_manifest_sha256),
    "externally pinned source manifest differs")
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
  q(identical(names(manifest), c("relative_path", "size_bytes", "sha256")) &&
    nrow(manifest) == length(required) && !anyDuplicated(manifest$relative_path) &&
    setequal(manifest$relative_path, required) && is.numeric(manifest$size_bytes) &&
    all(is.finite(manifest$size_bytes)) && all(manifest$size_bytes == floor(manifest$size_bytes)) &&
    all(manifest$size_bytes > 0 & manifest$size_bytes <= 8 * 1024^2) &&
    sum(manifest$size_bytes) <= 16 * 1024^2 && !anyNA(manifest$sha256) &&
    all(grepl("^[0-9a-f]{64}$", manifest$sha256)), "bounded exact source manifest required")
  verify_inputs <- function() {
    q(identical(gspm_hash(manifest_path), digest), "source manifest changed during verification")
    for (i in seq_len(nrow(manifest))) {
      path <- file.path(root, manifest$relative_path[i]); q(!gspm_symlink(path), "symlink packet file rejected")
      gspm_regular(path)
      q(!isTRUE(file.info(path)$isdir) && file.info(path)$size == manifest$size_bytes[i] &&
        identical(gspm_hash(path), manifest$sha256[i]), "source packet bytes changed")
    }
    invisible(TRUE)
  }
  verify_inputs()
  json <- function(name) jsonlite::read_json(file.path(root, name), simplifyVector = FALSE)
  decision <- json("DECISION.json"); contract <- json("score_contract.json"); seal <- json("FORECAST_SEAL.json")
  q(identical(decision$schema_version, "glofas_same_family_closeout_receipt_v1") &&
    identical(decision$status, "READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION") &&
    identical(decision$mode, "score") && identical(decision$truth_interface_version, "authenticated_truth_bridge_v2") &&
    isTRUE(decision$future_truth_read) && identical(decision$model_selection_or_retuning, FALSE) &&
    decision$new_fits == 0 && decision$forecast_rows == 1372 && decision$families == 7 &&
    identical(decision$article_publication_authorized, FALSE), "complete scored-v2 decision required")
  q(identical(contract$name, "realized_finite_grid_acrps") && identical(contract$scale, "log1p") &&
    contract$factor == 2 && identical(contract$weights_renormalized, FALSE) &&
    identical(contract$truth_used_only_after_assembly, TRUE) && identical(contract$model_selection_or_retuning, FALSE) &&
    identical(contract$article_publication_authorized, FALSE) && length(contract$weights) == 7L &&
    all(abs(as.numeric(unlist(contract$weights)) - c(.075, .15, .15, .15, .15, .15, .075)) < 1e-15),
    "score definition or protected truth role differs")
  q(identical(seal$schema_version, "glofas_same_family_forecast_seal_v1") &&
    identical(seal$status, "COMPLETE_FORECAST_GRID_COMMITTED_BEFORE_TRUTH") &&
    identical(seal$future_truth_read, FALSE) && seal$forecast_rows == 1372 && seal$families == 7 &&
    seal$producers == 16 && identical(seal$article_publication_authorized, FALSE) &&
    identical(decision$forecast_seal_sha256, manifest$sha256[match("FORECAST_SEAL.json", manifest$relative_path)]),
    "forecast seal binding differs")
  names <- vapply(seal$artifacts, function(a) a$relative_path, character(1L))
  q(length(names) == 3L && !anyDuplicated(names) &&
    setequal(names, c("quantile_paths.csv", "raw_crossings.csv", "accepted_producers.json")),
    "sealed forecast membership differs")
  for (a in seal$artifacts) {
    i <- match(a$relative_path, manifest$relative_path)
    q(a$size_bytes == manifest$size_bytes[i] && identical(a$sha256, manifest$sha256[i]),
      "sealed forecast bytes differ from scored packet")
  }
  read <- function(name) read.csv(file.path(root, name), stringsAsFactors = FALSE, check.names = FALSE)
  rows <- read("quantile_paths.csv"); truth <- read("scoring_truth.csv"); result <- gspm_metrics(rows, truth)
  f <- result$family_metrics; d <- result$date_metrics
  gspm_compare(read("family_scores.csv"), f[c("family", "n_horizons", "grid_acrps_log1p", "mean_check_loss",
    "coverage90", "inverted_intervals")], "family", "aggregate score")
  gspm_compare(read("scores_by_date.csv"), d[c("family", "target_date", "horizon", "grid_acrps_log1p",
    "mean_check_loss", "covered90", "inverted90")], c("family", "horizon"), "dated score")
  gspm_compare(read("quantile_calibration.csv"), result$calibration, c("family", "tau"), "calibration")
  gspm_compare(read("raw_crossings.csv"), result$crossings, "family", "raw crossing")
  verify_inputs()
  result$rows <- rows; result$truth <- truth; result$verified <- TRUE
  result$source_packet_manifest_sha256 <- digest
  result$source_inputs <- rbind(manifest, data.frame(relative_path = "artifact_manifest.csv",
    size_bytes = as.numeric(file.info(manifest_path)$size), sha256 = digest, stringsAsFactors = FALSE))
  if (!is.null(output_root)) {
    q(is.character(output_root) && length(output_root) == 1L && !file.exists(output_root) &&
      !gspm_symlink(output_root) && dir.exists(dirname(output_root)) &&
      identical(normalizePath(dirname(output_root)), dirname(output_root)) &&
      !grepl("(^|/)\\.\\.(/|$)", output_root), "fresh canonical derived output required")
    q(system2("git", c("check-ignore", "--quiet", "--", shQuote(output_root))) == 0L,
      "derived output must be ignored")
    q(dir.create(output_root), "derived output creation failed")
    for (pair in list(c("family_metrics", "family_metrics.csv"), c("date_metrics", "date_metrics.csv"),
      c("calibration", "quantile_calibration.csv"), c("crossings", "raw_crossings.csv")))
      write.csv(result[[pair[1L]]], file.path(output_root, pair[2L]), row.names = FALSE)
    write.csv(result$source_inputs, file.path(output_root, "source_manifest.csv"), row.names = FALSE)
    jsonlite::write_json(list(schema_version = "glofas_same_family_publication_metrics_v1",
      status = "INDEPENDENT_NUMERICAL_CHECKS_PASSED_NOT_ARTICLE_AUTHORITY",
      source_packet_manifest_sha256 = digest, externally_pinned_manifest = !is.null(expected_manifest_sha256),
      families = 7L, forecast_rows = 1372L, dated_scores = 196L, calibration_rows = 49L,
      adjacent_comparisons_per_family = 168L, crossing_rule = "strict_adjacent_greater_than_no_tolerance",
      crossing_magnitude = "mean_and_max_positive_log1p_violation_mean_includes_all_168_pairs",
      width_rule = "signed_q95_minus_q05_no_sorting_or_absolute_value",
      score_rule = "twice_check_loss_trapezoids_unnormalized_probability_span_0.9",
      score_uncertainty_intervals_created = FALSE, model_RDS_reads = 0L, original_truth_RDS_reads = 0L,
      source_packet_mutated = FALSE, new_fits = 0L, publication_authorized = FALSE),
      file.path(output_root, "DERIVED_METRICS_DECISION.json"), auto_unbox = TRUE, pretty = TRUE, digits = 17)
    verify_inputs()
    files <- list.files(output_root, full.names = TRUE)
    write.csv(data.frame(relative_path = basename(files), size_bytes = as.numeric(file.info(files)$size),
      sha256 = unname(tools::sha256sum(files))), file.path(output_root, "artifact_manifest.csv"), row.names = FALSE)
  }
  invisible(result)
}
