# Generated forecast frames only. No scientific fit, design or original truth is read.
local({
  source("scripts/glofas_same_family_publication_metrics.R", local = TRUE)
  checks <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE)}
  reject <- function(expr, text = NULL) {
    e <- tryCatch({force(expr); NULL}, error = function(e) e)
    ok(inherits(e, "error"))
    if (!is.null(text)) ok(grepl(text, conditionMessage(e), fixed = TRUE))
  }
  rows <- expand.grid(family = gspm_families(), horizon = seq_len(28L), tau = gspm_tau(),
    stringsAsFactors = FALSE)
  rows$target_date <- as.character(gspm_dates()[rows$horizon])
  rows$quantile_transformed <- 2 + rows$tau
  rows$quantile <- expm1(rows$quantile_transformed)
  rows <- rows[c("family", "target_date", "horizon", "tau", "quantile_transformed", "quantile")]
  truth <- data.frame(target_date = as.character(gspm_dates()), horizon = seq_len(28L),
    y_transformed = rep(2.5, 28L), stringsAsFactors = FALSE)
  m <- gspm_metrics(rows, truth)
  ok(nrow(m$family_metrics) == 7L && nrow(m$date_metrics) == 196L && nrow(m$calibration) == 49L)
  ok(all(m$family_metrics$covered90_count == 28L) && all(m$family_metrics$coverage90_percent == 100))
  ok(all(m$crossings$raw_crossing_pairs == 0L) && all(m$crossings$adjacent_comparisons == 168L))
  ok(all(abs(m$family_metrics$mean_signed_width90_log1p - .9) < 1e-14))
  # Literal analytic check: p<=.5 gives p(.5-p), p>.5 gives (1-p)(p-.5).
  p <- gspm_tau(); l <- c(.0225, .06, .0525, 0, .0525, .06, .0225)
  expected <- .15 * (l[1] + 2 * sum(l[2:6]) + l[7])
  ok(all(abs(m$family_metrics$grid_acrps_log1p - expected) < 1e-14))
  ok(all(abs(m$family_metrics$mean_check_loss - sum(l) / 7) < 1e-14))
  ok(abs(expected - 2 * sum(c(.075, rep(.15, 5), .075) * l)) < 1e-15)
  ok(all(m$calibration$empirical_coverage[m$calibration$tau == .5] == 1)) # inclusive ties
  set.seed(417)
  perm <- gspm_metrics(rows[sample(nrow(rows)), ], truth[sample(nrow(truth)), ])
  ok(identical(m, perm))

  for (col in c("horizon", "tau", "quantile_transformed", "quantile")) {
    b <- rows; b[[col]][1L] <- NA_real_; reject(gspm_metrics(b, truth), "finite numeric")
  }
  b <- rows; b$family[1] <- "Joint AL"; reject(gspm_metrics(b, truth), "seven-family")
  b <- rows[-1, ]; reject(gspm_metrics(b, truth), "seven-family")
  b <- rows; b[1, ] <- b[2, ]; reject(gspm_metrics(b, truth), "forecast key")
  b <- rows; b$tau[1] <- .1; reject(gspm_metrics(b, truth), "forecast key")
  b <- rows; b$horizon[1] <- 1.5; reject(gspm_metrics(b, truth), "alignment")
  b <- rows; b$target_date[1] <- "2022-12-26 ignored"; reject(gspm_metrics(b, truth), "alignment")
  b <- rows; b$quantile[1] <- b$quantile[1] + .01; reject(gspm_metrics(b, truth), "transformation")
  b <- truth; b$horizon[1] <- 2; reject(gspm_metrics(rows, b), "scoring truth")
  b <- truth; b$y_transformed[1] <- Inf; reject(gspm_metrics(rows, b), "scoring truth")
  b <- truth; b$target_date[1] <- "2022-12-25"; reject(gspm_metrics(rows, b), "scoring truth")

  # One deliberate raw inversion; neither order nor signed width is repaired.
  crossing <- rows
  low <- which(crossing$family == "MQ AL" & crossing$horizon == 1 & crossing$tau == .05)
  high <- which(crossing$family == "MQ AL" & crossing$horizon == 1 & crossing$tau == .95)
  crossing$quantile_transformed[c(low, high)] <- crossing$quantile_transformed[c(high, low)]
  crossing$quantile <- expm1(crossing$quantile_transformed)
  z <- gspm_metrics(crossing, truth); f <- z$family_metrics[z$family_metrics$family == "MQ AL", ]
  ok(f$raw_crossing_pairs == 2 && f$inverted_intervals == 1 && f$covered90_count == 27)
  ok(abs(f$raw_crossing_rate - 2 / 168) < 1e-15 && f$min_signed_width90_log1p < 0)
  ok(abs(f$max_positive_adjacent_violation_log1p - .75) < 1e-14)
  ok(abs(f$mean_positive_adjacent_violation_log1p - 1.5 / 168) < 1e-14)
  # A representable tiny violation is counted; equality is not a crossing.
  tiny <- rows; a <- which(tiny$family == "MQ exAL" & tiny$horizon == 1 & tiny$tau == .35)
  c <- which(tiny$family == "MQ exAL" & tiny$horizon == 1 & tiny$tau == .5)
  tiny$quantile_transformed[a] <- tiny$quantile_transformed[c] + 1e-12
  tiny$quantile <- expm1(tiny$quantile_transformed)
  ok(gspm_metrics(tiny, truth)$crossings$raw_crossing_pairs[7] == 1)
  tiny$quantile_transformed[a] <- tiny$quantile_transformed[c]
  tiny$quantile <- expm1(tiny$quantile_transformed)
  ok(gspm_metrics(tiny, truth)$crossings$raw_crossing_pairs[7] == 0)

  # Synthetic complete core packet, with exact manifests and a pre-truth seal.
  dir.create("local_trackers", showWarnings = FALSE)
  parent <- tempfile("glofas_metrics_generated_", tmpdir = normalizePath("local_trackers"))
  dir.create(parent); packet <- file.path(parent, "packet"); dir.create(packet)
  json <- function(x, name) jsonlite::write_json(x, file.path(packet, name),
    auto_unbox = TRUE, pretty = TRUE, digits = 17)
  pin <- function(name) list(relative_path = name, size_bytes = as.numeric(file.info(file.path(packet, name))$size),
    sha256 = gspm_hash(file.path(packet, name)))
  seal_manifest <- function() {
    paths <- list.files(packet, full.names = TRUE); paths <- paths[basename(paths) != "artifact_manifest.csv"]
    write.csv(data.frame(relative_path = basename(paths), size_bytes = as.numeric(file.info(paths)$size),
      sha256 = unname(tools::sha256sum(paths))), file.path(packet, "artifact_manifest.csv"), row.names = FALSE)
  }
  write.csv(rows, file.path(packet, "quantile_paths.csv"), row.names = FALSE)
  write.csv(truth, file.path(packet, "scoring_truth.csv"), row.names = FALSE)
  write.csv(m$crossings, file.path(packet, "raw_crossings.csv"), row.names = FALSE)
  write.csv(m$calibration, file.path(packet, "quantile_calibration.csv"), row.names = FALSE)
  write.csv(m$family_metrics[c("family", "n_horizons", "grid_acrps_log1p", "mean_check_loss", "coverage90",
    "inverted_intervals")], file.path(packet, "family_scores.csv"), row.names = FALSE)
  write.csv(m$date_metrics[c("family", "target_date", "horizon", "grid_acrps_log1p", "mean_check_loss", "covered90",
    "inverted90")], file.path(packet, "scores_by_date.csv"), row.names = FALSE)
  json(list(schema_version = "synthetic_accepted_collection_fixture"), "accepted_producers.json")
  json(list(status = "synthetic_fixture"), "progress.json")
  json(list(status = "synthetic_fixture"), "TRUTH_DERIVATION.json")
  json(list(status = "synthetic_fixture"), "TRUTH_PURPOSE.json")
  json(list(name = "realized_finite_grid_acrps", scale = "log1p", factor = 2,
    weights = c(.075, rep(.15, 5), .075), weights_renormalized = FALSE,
    truth_used_only_after_assembly = TRUE, model_selection_or_retuning = FALSE,
    article_publication_authorized = FALSE), "score_contract.json")
  json(list(schema_version = "glofas_same_family_forecast_seal_v1",
    status = "COMPLETE_FORECAST_GRID_COMMITTED_BEFORE_TRUTH", future_truth_read = FALSE,
    forecast_rows = 1372L, families = 7L, producers = 16L, article_publication_authorized = FALSE,
    artifacts = lapply(c("quantile_paths.csv", "raw_crossings.csv", "accepted_producers.json"), pin)), "FORECAST_SEAL.json")
  json(list(schema_version = "glofas_same_family_closeout_receipt_v1",
    status = "READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION", mode = "score",
    truth_interface_version = "authenticated_truth_bridge_v2", future_truth_read = TRUE,
    model_selection_or_retuning = FALSE, new_fits = 0L, forecast_rows = 1372L, families = 7L,
    article_publication_authorized = FALSE, forecast_seal_sha256 = gspm_hash(file.path(packet, "FORECAST_SEAL.json"))),
    "DECISION.json")
  seal_manifest(); digest <- gspm_hash(file.path(packet, "artifact_manifest.csv"))
  verified <- gspm_verify(packet, expected_manifest_sha256 = digest)
  ok(isTRUE(verified$verified) && identical(verified$family_metrics, m$family_metrics))
  reject(gspm_verify(packet, expected_manifest_sha256 = strrep("0", 64)), "externally pinned")
  before <- unname(tools::sha256sum(list.files(packet, full.names = TRUE)))
  derived <- file.path(parent, "derived")
  ok(!gspm_symlink(derived) && !file.exists(derived))
  broken <- file.path(parent, "broken_derived")
  ok(file.symlink(file.path(parent, "absent_target"), broken))
  ok(gspm_symlink(broken) && !file.exists(broken))
  reject(gspm_verify(packet, broken, digest), "fresh canonical")
  packet_link <- file.path(parent, "packet_link"); ok(file.symlink(packet, packet_link))
  reject(gspm_verify(packet_link), "symlink packet")
  gspm_verify(packet, derived, digest)
  ok(file.exists(file.path(derived, "DERIVED_METRICS_DECISION.json")))
  ok(identical(before, unname(tools::sha256sum(list.files(packet, full.names = TRUE)))))
  reject(gspm_verify(packet, derived, digest), "fresh canonical")
  decision <- jsonlite::read_json(file.path(derived, "DERIVED_METRICS_DECISION.json"))
  ok(identical(decision$publication_authorized, FALSE) && identical(decision$score_uncertainty_intervals_created, FALSE))
  original <- readLines(file.path(packet, "family_scores.csv"))
  corrupt <- read.csv(file.path(packet, "family_scores.csv"), stringsAsFactors = FALSE)
  corrupt$grid_acrps_log1p[1] <- corrupt$grid_acrps_log1p[1] + .01
  write.csv(corrupt, file.path(packet, "family_scores.csv"), row.names = FALSE)
  reject(gspm_verify(packet), "source packet bytes")
  seal_manifest(); reject(gspm_verify(packet), "aggregate score")
  writeLines(original, file.path(packet, "family_scores.csv")); seal_manifest()
  for (spec in list(c("scores_by_date.csv", "grid_acrps_log1p", "dated score"),
    c("quantile_calibration.csv", "empirical_coverage", "calibration"))) {
    original_lines <- readLines(file.path(packet, spec[1L]))
    bad <- read.csv(file.path(packet, spec[1L]), stringsAsFactors = FALSE)
    bad[[spec[2L]]][1L] <- bad[[spec[2L]]][1L] + .01
    write.csv(bad, file.path(packet, spec[1L]), row.names = FALSE); seal_manifest()
    reject(gspm_verify(packet), spec[3L])
    writeLines(original_lines, file.path(packet, spec[1L])); seal_manifest()
  }
  original_contract <- readLines(file.path(packet, "score_contract.json"))
  bad_contract <- jsonlite::read_json(file.path(packet, "score_contract.json"), simplifyVector = FALSE)
  bad_contract$weights_renormalized <- TRUE; json(bad_contract, "score_contract.json"); seal_manifest()
  reject(gspm_verify(packet), "score definition")
  writeLines(original_contract, file.path(packet, "score_contract.json")); seal_manifest()
  extra <- file.path(packet, "extra.csv"); writeLines("not core", extra)
  reject(gspm_verify(packet), "membership")
  # Extra-file removal is limited to this generated fixture, never runtime data.
  unlink(extra); seal_manifest()
  core_cross <- read.csv(file.path(packet, "raw_crossings.csv"), stringsAsFactors = FALSE)
  core_cross$raw_crossing_pairs[1] <- 1
  write.csv(core_cross, file.path(packet, "raw_crossings.csv"), row.names = FALSE); seal_manifest()
  reject(gspm_verify(packet), "sealed forecast bytes")
  # Even a self-consistently rehashed false crossing table fails the independent
  # scalar calculation. This is additional to the externally pinned manifest.
  revised_seal <- jsonlite::read_json(file.path(packet, "FORECAST_SEAL.json"), simplifyVector = FALSE)
  revised_seal$artifacts <- lapply(c("quantile_paths.csv", "raw_crossings.csv", "accepted_producers.json"), pin)
  json(revised_seal, "FORECAST_SEAL.json")
  revised_decision <- jsonlite::read_json(file.path(packet, "DECISION.json"), simplifyVector = FALSE)
  revised_decision$forecast_seal_sha256 <- gspm_hash(file.path(packet, "FORECAST_SEAL.json"))
  json(revised_decision, "DECISION.json"); seal_manifest()
  reject(gspm_verify(packet), "raw crossing")
  # A missing declared producer cannot be excused by keeping a plausible score.
  bad_metrics <- m$family_metrics[c("family", "n_horizons", "grid_acrps_log1p", "mean_check_loss", "coverage90",
    "inverted_intervals")]
  reject(gspm_compare(bad_metrics[-1, ], bad_metrics, "family", "summary"), "schema")
  bad_metrics$family[1] <- bad_metrics$family[2]
  reject(gspm_compare(bad_metrics, m$family_metrics[names(bad_metrics)], "family", "summary"), "keys")
  ok(!any(grepl("gsc_(score|crossings)\\(",
    readLines("scripts/glofas_same_family_publication_metrics.R"))))
  cat("GLOFAS_PUBLICATION_METRICS_GENERATED_CHECKS=", checks,
    " PASS; scientific_model_RDS_reads=0 original_truth_RDS_reads=0 new_fits=0\n", sep = "")
})
