# Descriptive calibration from retained forecast draws. This module never fits
# a model, generates forecasts, or evaluates historical production code.
ifc_assert <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
  invisible(TRUE)
}
ifc_sha <- function(path) {
  ifc_assert(length(path) == 1L && file.exists(path), "Required retained evidence is missing.")
  unname(tools::sha256sum(path)[[1L]])
}
ifc_read_csv <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
ifc_key <- function(x) paste(x$family, sprintf("%.8f", x$tau), x$model_variant, sep = "|")
ifc_grid <- function() {
  i <- seq_len(1000L)
  data.frame(origin = 9000L + ((i - 1L) %/% 30L) * 30L,
    lead = (i - 1L) %% 30L + 1L, target = 9000L + i)
}
ifc_policy <- function(path) {
  p <- jsonlite::read_json(path, simplifyVector = TRUE)
  ifc_assert(identical(p$schema, "independent_forecast_calibration_v1") &&
    identical(p$packet_manifest_sha256, "5f842dfcdd0e8314783c74d35e72a77641933c2a1e26d12a5dc557782cd96664") &&
    identical(p$protected_locator_sha256, "e2c941b4d26104e70bd178390a979ea62b8e19d9f2cfb3bfd899532ea5ea9772") &&
    identical(p$forecast_summary_sha256, "7ee08a577b47c9369c8cc8fd35677c6f884bbc1b7a886096fb2afd66838e4bcf") &&
    p$source_criterion == "forecast_check" && p$source_selection_cutoff == 300L &&
    identical(as.integer(p$evaluation_cutoffs), c(300L, 500L)) &&
    p$point_summary == "posterior_median" &&
    p$chain_pooling == "all_draws_from_three_equal_budget_chains" &&
    p$event == "response_less_than_or_equal_to_point_quantile" &&
    p$uncertainty_bands == "none_sampling_calibration_uncertainty_not_estimated" &&
    p$interpretation == "descriptive_unconditional_quantile_frequency" &&
    all(vapply(p[c("allow_refit", "allow_forecast_simulation", "allow_source_reselection",
      "allow_source_exclusion", "allow_bootstrap")], identical, logical(1), FALSE)) &&
    all(c("allow_refit", "allow_forecast_simulation", "allow_source_reselection",
      "allow_source_exclusion", "allow_bootstrap") %in% names(p)),
    "Calibration policy is outside the frozen read-only scope.")
  p
}
ifc_select_specs <- function(x) {
  required <- c("inference", "metric_role", "cutoff", "family", "tau", "model_variant",
    "replay_id", "n_draws", "n_chains")
  ifc_assert(all(required %in% names(x)), "Forecast summary schema is incomplete.")
  z <- x[x$inference == "mcmc" & x$metric_role == "forecast_check", ]
  expected <- expand.grid(family = c("normal", "laplace", "gausmix"),
    tau = c(.05, .25, .5), model_variant = c("dqlm", "exdqlm", "qdesn_al_rhs_ns", "qdesn_exal_rhs_ns"),
    stringsAsFactors = FALSE)
  a <- z[z$cutoff == 300L, ]; b <- z[z$cutoff == 500L, ]
  ifc_assert(nrow(z) == 72L && nrow(a) == 36L && nrow(b) == 36L &&
    !anyDuplicated(ifc_key(a)) && !anyDuplicated(ifc_key(b)) &&
    setequal(ifc_key(a), ifc_key(expected)) && setequal(ifc_key(b), ifc_key(expected)),
    "Exactly 36 check-loss-selected specifications at each retained window are required.")
  b <- b[match(ifc_key(a), ifc_key(b)), ]
  ifc_assert(!anyDuplicated(a$replay_id) && identical(a$replay_id, b$replay_id) &&
    all(a$n_chains == 3L & b$n_chains == 3L) && all(a$n_draws == b$n_draws) &&
    all(is.finite(a$n_draws) & a$n_draws > 0 & a$n_draws %% 3L == 0L),
    "Source selection or balanced chain budgets changed between windows.")
  a
}
ifc_validate_paths <- function(x, spec, locator) {
  required <- c("schema", "q", "grid", "y", "oracle", "p", "chain_id",
    "source_draw_index", "reconstruction_id", "coupling")
  ifc_assert(is.list(x) && all(required %in% names(x)), "Retained forecast-path schema is incomplete.")
  n <- as.integer(locator$n_draws)
  ifc_assert(identical(x$schema, "independent_joint_quantile_forecast_paths_v1") &&
    is.matrix(x$q) && is.numeric(x$q) && identical(dim(x$q), c(1000L, n)) &&
    all(is.finite(x$q)), "Retained forecast draws have invalid schema, shape, or finite values.")
  expected <- ifc_grid()
  ifc_assert(is.data.frame(x$grid) && all(names(expected) %in% names(x$grid)) &&
    nrow(x$grid) == 1000L && identical(unname(as.matrix(x$grid[names(expected)])),
      unname(as.matrix(expected))) &&
    is.numeric(x$y) && is.numeric(x$oracle) && length(x$y) == 1000L &&
    length(x$oracle) == 1000L && all(is.finite(c(x$y, x$oracle))),
    "Forecast targets, origins, leads, or truth alignment are invalid.")
  coupling <- if (grepl("^qdesn_", spec$model_variant)) "native_shared_readout_draws" else
    "historical_latent_gaussian_product_coupling"
  idx <- x$source_draw_index
  ifc_assert(length(x$p) == 1L && identical(as.numeric(x$p), as.numeric(spec$tau)) &&
    length(x$chain_id) == 1L && x$chain_id == locator$chain_id &&
    identical(x$reconstruction_id, locator$task_id) && identical(x$coupling, coupling) &&
    is.numeric(idx) && length(idx) == n && all(is.finite(idx)) &&
    all(idx > 0 & idx == floor(idx)) && !anyDuplicated(idx),
    "Forecast chain, probability level, source draw identity, or coupling metadata changed.")
  invisible(TRUE)
}
ifc_pool_point <- function(chains) {
  ifc_assert(length(chains) == 3L &&
    identical(sort(vapply(chains, function(x) as.integer(x$chain_id), integer(1))), 1:3),
    "Three distinct equal-budget chains are required.")
  ifc_assert(length(unique(vapply(chains, function(x) ncol(x$q), integer(1)))) == 1L &&
    length(unique(vapply(chains, function(x) nrow(x$q), integer(1)))) == 1L &&
    all(vapply(chains, function(x) is.matrix(x$q) && is.numeric(x$q) &&
      all(is.finite(x$q)), logical(1))) &&
    all(vapply(chains[-1L], function(x) identical(x$y, chains[[1L]]$y) &&
      identical(x$oracle, chains[[1L]]$oracle) && identical(x$grid, chains[[1L]]$grid), logical(1))),
    "Chain budgets or response/oracle/grid alignment differ.")
  # Median is taken over all retained draws, not over chain-specific medians.
  apply(do.call(cbind, lapply(chains, `[[`, "q")), 1L, stats::median)
}
ifc_frequency <- function(point, y, tau, grid, cutoff) {
  ifc_assert(cutoff %in% c(300L, 500L) && length(point) >= cutoff && length(y) >= cutoff &&
    nrow(grid) >= cutoff && all(is.finite(c(point, y))) &&
    length(tau) == 1L && is.finite(tau) && tau > 0 && tau < 1,
    "Invalid fixed-forecast calibration input.")
  idx <- seq_len(cutoff); n_hits <- sum(y[idx] <= point[idx])
  data.frame(cutoff = cutoff, n_targets = cutoff, n_origins = length(unique(grid$origin[idx])),
    n_hits = n_hits, empirical_frequency = n_hits / cutoff, nominal_frequency = tau,
    calibration_error_pp = 100 * (n_hits / cutoff - tau), point_summary = "posterior_median")
}
ifc_verify_file <- function(path, sha256, bytes = NULL) {
  ifc_assert(file.exists(path) && !dir.exists(path) && ifc_sha(path) == sha256 &&
    (is.null(bytes) || identical(as.numeric(file.info(path)$size), as.numeric(bytes))),
    paste("Retained evidence hash or size mismatch:", basename(path)))
  invisible(TRUE)
}
ifc_frozen_job_pins <- function(packet) {
  # Each edge is authenticated by its already-frozen parent manifest. Reading
  # these compact CSVs does not read or hash any fitted model objects.
  publication <- ifc_read_csv(file.path(packet, "artifact_manifest.csv"))
  source <- publication[basename(publication$path) == "source_manifest.csv", ]
  ifc_assert(nrow(source) == 1L, "Frozen publication source manifest is not unique.")
  source_path <- file.path(packet, "source_manifest.csv")
  ifc_verify_file(source_path, source$sha256, source$bytes)
  inputs <- ifc_read_csv(source_path)
  audit <- inputs[basename(inputs$path) == "artifact_manifest.csv" &
    grepl("/healthchecks/closeout_", inputs$path, fixed = TRUE), ]
  ifc_assert(nrow(audit) == 1L, "Frozen recovery closeout manifest is not unique.")
  ifc_verify_file(audit$path, audit$sha256, audit$bytes)
  inventory <- ifc_read_csv(audit$path)
  checks <- inventory[basename(inventory$path) == "full_artifact_hash_checks.csv", ]
  ifc_assert(nrow(checks) == 1L, "Frozen recovery payload audit is not unique.")
  ifc_verify_file(checks$path, checks$sha256, checks$bytes)
  pins <- ifc_read_csv(checks$path)
  ifc_assert(all(c("path", "sha256", "bytes", "observed_sha256", "pass") %in% names(pins)) &&
    !anyDuplicated(pins$path) && all(pins$pass) && all(pins$sha256 == pins$observed_sha256) &&
    all(grepl("^[0-9a-f]{64}$", pins$sha256)) && all(is.finite(pins$bytes) & pins$bytes >= 0),
    "Frozen recovery hash audit contains invalid or failed records.")
  list(records = pins, source_manifest_sha256 = source$sha256,
    recovery_artifact_manifest_sha256 = audit$sha256, frozen_payload_audit_sha256 = checks$sha256)
}
ifc_verify_pin <- function(path, pins, required = TRUE) {
  selected <- pins[pins$path == path, , drop = FALSE]
  ifc_assert(nrow(selected) <= 1L && (!required || nrow(selected) == 1L),
    paste("Immutable recovery audit does not uniquely pin:", basename(path)))
  if (nrow(selected)) ifc_verify_file(path, selected$sha256, selected$bytes)
  nrow(selected) == 1L
}
ifc_read_chain <- function(locator, spec, pins) {
  root <- locator$job_root
  status_path <- file.path(root, "task_status.json")
  status_frozen <- ifc_verify_pin(status_path, pins, required = FALSE)
  status <- jsonlite::read_json(status_path, simplifyVector = TRUE)
  ifc_assert(status$status == "COMPLETE" && status$task_id == locator$task_id &&
    identical(status$contract_sha256, locator$contract_sha256),
    "Retained task is not complete or its contract identity changed.")
  ifc_verify_file(locator$contract_path, locator$contract_sha256)
  contract <- jsonlite::read_json(locator$contract_path, simplifyVector = TRUE)
  task <- contract$task
  ifc_assert(task$task_id == locator$task_id && task$replay_id == spec$replay_id &&
    task$chain_id == locator$chain_id && task$n_draws == locator$n_draws &&
    task$model_variant == spec$model_variant && task$family == spec$family &&
    task$p == spec$tau, "Source contract does not describe the selected specification.")
  manifest_path <- file.path(root, "retention_manifest.csv")
  manifest_frozen <- ifc_verify_pin(manifest_path, pins, required = FALSE)
  ifc_verify_file(manifest_path, status$retention_manifest_sha256)
  manifest <- ifc_read_csv(manifest_path)
  ifc_assert(all(c("path", "sha256", "bytes") %in% names(manifest)),
    "Retention manifest schema is incomplete.")
  selected <- manifest[basename(manifest$path) == "protected_joint_forecast_paths.rds", ]
  payload <- file.path(root, "protected_joint_forecast_paths.rds")
  ifc_assert(nrow(selected) == 1L && normalizePath(selected$path, mustWork = TRUE) ==
    normalizePath(payload, mustWork = TRUE), "Retained forecast payload is not uniquely identified.")
  ifc_verify_file(payload, selected$sha256, selected$bytes)
  # Every selected payload has an independent immutable closeout hash. Unlike
  # live status metadata, this pin cannot be replaced along with a payload.
  ifc_verify_pin(payload, pins, required = TRUE)
  # This is the sole readRDS call: fitted objects and launchers are never loaded.
  object <- readRDS(payload)
  ifc_validate_paths(object, spec, locator)
  receipt <- data.frame(family = spec$family, tau = spec$tau, model_variant = spec$model_variant,
    replay_id = spec$replay_id, task_id = locator$task_id, chain_id = locator$chain_id,
    n_draws = locator$n_draws, payload_sha256 = selected$sha256,
    payload_bytes = selected$bytes, contract_sha256 = locator$contract_sha256,
    task_status_sha256 = ifc_sha(status_path), retention_manifest_sha256 = status$retention_manifest_sha256,
    payload_frozen_audit_verified = TRUE, task_status_individually_frozen = status_frozen,
    retention_manifest_individually_frozen = manifest_frozen,
    coupling = object$coupling)
  # At most 500 rows per chain need to remain in memory for the publication.
  object$q <- object$q[seq_len(500L), , drop = FALSE]
  list(object = object, receipt = receipt)
}
ifc_extract <- function(article_root, validation_root, output_dir) {
  ifc_assert(requireNamespace("jsonlite", quietly = TRUE), "jsonlite is required for evidence metadata.")
  article_root <- normalizePath(article_root, mustWork = TRUE)
  validation_root <- normalizePath(validation_root, mustWork = TRUE)
  policy_path <- file.path(article_root, "application/config/independent_forecast_calibration_v1.json")
  policy <- ifc_policy(policy_path)
  packet <- file.path(validation_root, "validation/fitforecast_v2/promotions/independent_forecast_300_500_v1")
  packet_manifest <- file.path(packet, "artifact_manifest.csv")
  locator_path <- file.path(packet, "protected_source_locator.csv")
  article_path <- file.path(article_root, "tables/independent_forecast_300_500_v1.csv")
  ifc_verify_file(packet_manifest, policy$packet_manifest_sha256)
  ifc_verify_file(locator_path, policy$protected_locator_sha256)
  ifc_verify_file(article_path, policy$forecast_summary_sha256)
  inventory <- ifc_read_csv(packet_manifest)
  ifc_assert(all(c("path", "sha256", "bytes") %in% names(inventory)) &&
    !anyDuplicated(basename(inventory$path)), "Frozen packet manifest schema is invalid.")
  for (i in seq_len(nrow(inventory))) ifc_verify_file(file.path(packet, basename(inventory$path[i])),
    inventory$sha256[i], inventory$bytes[i])
  frozen <- ifc_frozen_job_pins(packet)
  article <- ifc_read_csv(article_path); specs <- ifc_select_specs(article)
  locator <- ifc_read_csv(locator_path)
  fields <- c("task_id", "replay_id", "chain_id", "job_root", "contract_path", "contract_sha256", "n_draws")
  ifc_assert(all(fields %in% names(locator)), "Protected source locator schema is incomplete.")
  locator <- locator[locator$replay_id %in% specs$replay_id, ]
  ifc_assert(nrow(locator) == 108L && !anyDuplicated(locator$task_id) &&
    !anyDuplicated(paste(locator$replay_id, locator$chain_id)),
    "The 36 selected specifications require exactly 108 unique chain locators.")
  summaries <- receipts <- list(); truth <- list()
  for (i in seq_len(nrow(specs))) {
    spec <- specs[i, ]; loc <- locator[locator$replay_id == spec$replay_id, ]
    loc <- loc[order(loc$chain_id), ]
    ifc_assert(identical(as.integer(loc$chain_id), 1:3) &&
      all(loc$n_draws == spec$n_draws / 3L), "Selected chain budget is not balanced.")
    chains <- lapply(seq_len(3L), function(j) ifc_read_chain(loc[j, ], spec, frozen$records))
    objects <- lapply(chains, `[[`, "object")
    point <- ifc_pool_point(objects)
    key <- paste(spec$family, spec$tau, sep = "|")
    reference <- list(y = objects[[1L]]$y, oracle = objects[[1L]]$oracle, grid = objects[[1L]]$grid)
    if (is.null(truth[[key]])) truth[[key]] <- reference else
      ifc_assert(identical(reference, truth[[key]]), "Response or oracle alignment differs across models.")
    for (cutoff in c(300L, 500L)) {
      z <- ifc_frequency(point, reference$y, spec$tau, reference$grid, cutoff)
      z <- cbind(spec[c("family", "tau", "model_variant", "replay_id")], z)
      z$n_chains <- 3L; z$n_draws <- spec$n_draws; z$coupling <- objects[[1L]]$coupling
      z$first_target <- 9001L; z$last_target <- 9000L + cutoff
      z$last_lead <- reference$grid$lead[cutoff]
      z$source_criterion <- "forecast_check"; z$source_selection_cutoff <- 300L
      summaries[[length(summaries) + 1L]] <- z
    }
    receipts <- c(receipts, lapply(chains, `[[`, "receipt"))
    rm(chains, objects, point); gc(verbose = FALSE)
    cat(sprintf("Verified calibration specification %d/36: %s\n", i, spec$replay_id))
  }
  summary <- do.call(rbind, summaries); receipt <- do.call(rbind, receipts)
  ifc_assert(nrow(summary) == 72L && nrow(receipt) == 108L &&
    !anyDuplicated(paste(ifc_key(summary), summary$cutoff)), "Calibration output surface is incomplete.")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(output_dir, c("independent_forecast_calibration_v1.csv",
    "independent_forecast_calibration_sources_v1.csv", "independent_forecast_calibration_manifest_v1.json"))
  write.csv(summary, paths[1L], row.names = FALSE, na = "")
  write.csv(receipt, paths[2L], row.names = FALSE, na = "")
  source_paths <- c("application/config/independent_forecast_calibration_v1.json",
    "application/R/independent_forecast_calibration_v1.R", "scripts/extract_independent_forecast_calibration_v1.R",
    "tables/independent_forecast_300_500_v1.csv")
  manifest <- list(schema = "independent_forecast_calibration_v1", status = "PASS",
    packet_manifest_sha256 = policy$packet_manifest_sha256, protected_locator_sha256 = policy$protected_locator_sha256,
    source_manifest_sha256 = frozen$source_manifest_sha256,
    recovery_artifact_manifest_sha256 = frozen$recovery_artifact_manifest_sha256,
    frozen_payload_audit_sha256 = frozen$frozen_payload_audit_sha256,
    article_reference_commit = policy$article_reference_commit,
    validation_reference_commit = policy$validation_reference_commit,
    sources = as.list(setNames(vapply(file.path(article_root, source_paths), ifc_sha, character(1)), source_paths)),
    outputs = as.list(setNames(vapply(paths[1:2], ifc_sha, character(1)), basename(paths[1:2]))),
    specifications = 36L, chains = 108L, calibration_rows = 72L,
    point_summary = "posterior_median", chain_pooling = policy$chain_pooling,
    uncertainty_bands = policy$uncertainty_bands, event = policy$event,
    fits_launched = 0L, forecasts_launched = 0L, refinements_launched = 0L,
    posterior_objects_copied = 0L, per_target_forecasts_published = 0L,
    all_source_hashes_verified = TRUE, all_chain_and_model_truth_aligned = TRUE,
    immutable_payload_pins_verified = sum(receipt$payload_frozen_audit_verified),
    individually_frozen_task_statuses = sum(receipt$task_status_individually_frozen),
    individually_frozen_retention_manifests = sum(receipt$retention_manifest_individually_frozen),
    r_version = as.character(getRversion()))
  jsonlite::write_json(manifest, paths[3L], auto_unbox = TRUE, pretty = TRUE, digits = NA)
  invisible(summary)
}
