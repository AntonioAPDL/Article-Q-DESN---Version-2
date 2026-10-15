#!/usr/bin/env Rscript
# Read-only compact-evidence checks; protected runtime is not loaded.
options(stringsAsFactors = FALSE, digits = 17)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), "..")); setwd(root)
source("application/R/independent_forecast_calibration_v1.R")
policy <- ifc_policy("application/config/independent_forecast_calibration_v1.json")
receipt <- jsonlite::read_json("tables/independent_forecast_calibration_manifest_v1.json", simplifyVector = TRUE)
stopifnot(all(c("schema", "status", "specifications", "chains", "calibration_rows",
  "point_summary", "packet_manifest_sha256", "protected_locator_sha256",
  "source_manifest_sha256", "recovery_artifact_manifest_sha256", "frozen_payload_audit_sha256",
  "article_reference_commit", "validation_reference_commit", "chain_pooling", "event",
  "immutable_payload_pins_verified", "individually_frozen_task_statuses",
  "individually_frozen_retention_manifests", "uncertainty_bands", "all_source_hashes_verified",
  "all_chain_and_model_truth_aligned", "fits_launched", "forecasts_launched",
  "refinements_launched", "posterior_objects_copied", "per_target_forecasts_published",
  "sources", "outputs") %in% names(receipt)))
stopifnot(receipt$schema == policy$schema, receipt$status == "PASS",
  receipt$specifications == 36L, receipt$chains == 108L, receipt$calibration_rows == 72L,
  receipt$point_summary == "posterior_median",
  receipt$packet_manifest_sha256 == policy$packet_manifest_sha256,
  receipt$protected_locator_sha256 == policy$protected_locator_sha256,
  receipt$source_manifest_sha256 == "baedb83f6d95d96c1b0169dd5d5a1cad60f5fed252d43d53d20d33cd05c0204c",
  receipt$recovery_artifact_manifest_sha256 == "6805bc50d8f545de101933a44c45ce52981874ed85493c4ec7186b498eb7892a",
  receipt$frozen_payload_audit_sha256 == "f05c19da9f6ce90289223556381a3332ab4bf30332e3828b8e98f782a601c3fd",
  receipt$article_reference_commit == policy$article_reference_commit,
  receipt$validation_reference_commit == policy$validation_reference_commit,
  receipt$chain_pooling == policy$chain_pooling, receipt$event == policy$event,
  receipt$immutable_payload_pins_verified == 108L,
  receipt$individually_frozen_task_statuses == 24L,
  receipt$individually_frozen_retention_manifests == 24L,
  receipt$uncertainty_bands == policy$uncertainty_bands,
  receipt$all_source_hashes_verified, receipt$all_chain_and_model_truth_aligned,
  receipt$fits_launched == 0L, receipt$forecasts_launched == 0L,
  receipt$refinements_launched == 0L, receipt$posterior_objects_copied == 0L,
  receipt$per_target_forecasts_published == 0L,
  setequal(names(receipt$sources), c("application/config/independent_forecast_calibration_v1.json",
    "application/R/independent_forecast_calibration_v1.R",
    "scripts/extract_independent_forecast_calibration_v1.R",
    "tables/independent_forecast_300_500_v1.csv")))
for (path in names(receipt$sources)) ifc_verify_file(path, receipt$sources[[path]])
stopifnot(setequal(names(receipt$outputs), c("independent_forecast_calibration_v1.csv",
  "independent_forecast_calibration_sources_v1.csv")))
for (path in names(receipt$outputs)) ifc_verify_file(file.path("tables", path), receipt$outputs[[path]])
original <- ifc_read_csv("tables/independent_forecast_300_500_v1.csv")
specs <- ifc_select_specs(original)
x <- ifc_read_csv("tables/independent_forecast_calibration_v1.csv")
sources <- ifc_read_csv("tables/independent_forecast_calibration_sources_v1.csv")
stopifnot(all(c("family", "tau", "model_variant", "replay_id", "task_id", "chain_id",
  "n_draws", "payload_sha256", "payload_bytes", "contract_sha256", "task_status_sha256",
  "retention_manifest_sha256", "payload_frozen_audit_verified",
  "task_status_individually_frozen", "retention_manifest_individually_frozen",
  "coupling") %in% names(sources)),
  all(c("family", "tau", "model_variant", "replay_id", "cutoff", "n_targets", "n_origins",
  "n_hits", "empirical_frequency", "nominal_frequency", "calibration_error_pp",
  "point_summary", "n_chains", "n_draws", "coupling", "first_target", "last_target",
  "last_lead", "source_criterion", "source_selection_cutoff") %in% names(x)))
stopifnot(nrow(x) == 72L, nrow(sources) == 108L, !anyDuplicated(paste(ifc_key(x), x$cutoff)),
  !anyDuplicated(sources$task_id), all(x$cutoff %in% c(300L, 500L)),
  all(is.finite(as.matrix(x[c("tau", "n_targets", "n_origins", "n_hits", "empirical_frequency",
    "nominal_frequency", "calibration_error_pp", "n_chains", "n_draws")]))),
  all(x$n_targets == x$cutoff), all(x$n_origins == ceiling(x$cutoff / 30)),
  all(x$n_hits == floor(x$n_hits) & x$n_hits >= 0 & x$n_hits <= x$n_targets),
  all(abs(x$empirical_frequency - x$n_hits / x$n_targets) < 1e-12),
  all(x$nominal_frequency == x$tau),
  all(abs(x$calibration_error_pp - 100 * (x$empirical_frequency - x$tau)) < 1e-10),
  all(x$point_summary == "posterior_median"), all(x$n_chains == 3L),
  all(x$source_criterion == "forecast_check"), all(x$source_selection_cutoff == 300L),
  all(x$first_target == 9001L), all(x$last_target == 9000L + x$cutoff),
  all(x$last_lead == ifelse(x$cutoff == 300L, 30L, 20L)))
expected_coupling <- function(model) ifelse(grepl("^qdesn_", model),
  "native_shared_readout_draws", "historical_latent_gaussian_product_coupling")
stopifnot(all(x$coupling == expected_coupling(x$model_variant)),
  all(sources$coupling == expected_coupling(sources$model_variant)),
  all(sources$payload_frozen_audit_verified),
  sum(sources$task_status_individually_frozen) == 24L,
  sum(sources$retention_manifest_individually_frozen) == 24L)
for (n in c(300L, 500L)) {
  block <- x[x$cutoff == n, ]
  stopifnot(setequal(ifc_key(block), ifc_key(specs)))
  block <- block[match(ifc_key(specs), ifc_key(block)), ]
  stopifnot(identical(block$replay_id, specs$replay_id),
    identical(as.numeric(block$n_draws), as.numeric(specs$n_draws)))
}
a <- x[x$cutoff == 300L, ]; b <- x[x$cutoff == 500L, ]
b <- b[match(ifc_key(a), ifc_key(b)), ]
stopifnot(all(b$n_hits >= a$n_hits & b$n_hits - a$n_hits <= 200L))
for (i in seq_len(nrow(specs))) {
  s <- sources[sources$replay_id == specs$replay_id[i], ]
  stopifnot(nrow(s) == 3L, identical(sort(as.integer(s$chain_id)), 1:3),
    all(s$n_draws == specs$n_draws[i] / 3L),
    all(s$family == specs$family[i]), all(s$tau == specs$tau[i]),
    all(s$model_variant == specs$model_variant[i]))
}
for (name in grep("sha256$", names(sources), value = TRUE))
  stopifnot(all(grepl("^[a-f0-9]{64}$", sources[[name]])))
stopifnot(!grepl("/data/|/home/|local_trackers/|[.]rds", paste(
  readLines("tables/independent_forecast_calibration_manifest_v1.json"),
  readLines("tables/independent_forecast_calibration_sources_v1.csv"), collapse = "\n")))
cat("INDEPENDENT_CALIBRATION_COMPACT_CHECK=PASS specifications=36 chains=108 rows=72 no_inference=TRUE\n")
