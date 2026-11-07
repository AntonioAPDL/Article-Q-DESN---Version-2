#!/usr/bin/env Rscript
# Purpose-bound authentic fixed-parameter global-path diagnostic. This reader
# authenticates exactly the frozen truth-free design and median-AL fit. It
# cannot fit, score against future USGS, promote results, or publish.
source("scripts/glofas_native_stage_e_reader.R")
source("scripts/diagnostics/glofas_global_path_reference.R")
source("scripts/diagnostics/glofas_forecast_factorial_diagnostic.R")
source("scripts/diagnostics/glofas_native_factorial_adapter.R")

ggrr_sources <- function() unique(c(gnser_sources(),
  "scripts/glofas_global_path_native_reader.R",
  "scripts/launch_glofas_global_path_native.sh",
  "scripts/diagnostics/glofas_global_path_reference.R",
  "scripts/diagnostics/glofas_forecast_factorial_diagnostic.R",
  "scripts/diagnostics/glofas_native_factorial_adapter.R",
  "scripts/diagnostics/glofas_global_path_native_controls.json"))

ggrr_controls <- function(x) {
  q <- gfr_require
  q(is.list(x) && identical(x$schema_version,
      "glofas_global_path_native_controls_v2") &&
    identical(x$task_id, "gft-al-p050") &&
    identical(x$posterior_target_sha256,
      "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03") &&
    identical(x$truth_access, "forbidden") && x$model_fits == 0L &&
    x$parameter_updates == 0L && identical(x$publication_authorized, FALSE),
    "exact truth-free median global-path controls required")
  m <- x$measurement
  q(is.list(m) && identical(unlist(m$path_rules), c("retained_mean",
      "retained_mean_minus_quarter_sd", "retained_mean_plus_quarter_sd")) &&
    m$sd_multiplier == .25 && m$maximum_target_evaluations == 12L &&
    m$maximum_wall_seconds == 7200L,
    "fixed three-path measurement controls required")
  a <- x$authentic_measurement
  q(is.list(a) && grepl("^[a-f0-9]{40}$", a$source_commit) &&
    all(vapply(a[c("receipt_sha256", "summary_sha256",
      "target_measurement_sha256")], gsc_hash_string, logical(1L))) &&
    a$target_evaluations == 12L && a$maximum_target_seconds == .608,
    "exact source-bound authentic measurement is required")
  e <- x$execution
  q(is.list(e) && is.logical(e$authorized) && length(e$authorized) == 1L &&
    is.character(e$reason) && length(e$reason) == 1L && nzchar(e$reason) &&
    identical(e$authorized, TRUE) && identical(as.numeric(e$probabilities),
      c(.05, .2, .35, .5, .65, .8, .95)) &&
    e$proposal_covariance_inflation == 1 && is.list(e$importance) &&
    is.list(e$tempering), "explicit frozen execution admission required")
  ggpr_validate_common(function(x) 0, numeric(28L), diag(28L),
    c(e$importance, seed = 1L))
  ggpr_validate_common(function(x) 0, numeric(28L), diag(28L),
    c(e$tempering, seed = 1L), tempered = TRUE)
  q(e$importance$particles == 2048L && e$importance$max_evaluations == 2048L &&
    e$tempering$particles == 256L && e$tempering$max_evaluations == 2304L &&
    e$tempering$max_tempering_steps == 8L &&
    (4 * (e$importance$max_evaluations + e$tempering$max_evaluations) *
      a$maximum_target_seconds) < 12000,
    "execution evaluation budget exceeds the measured four-hour envelope")
  invisible(TRUE)
}

ggrr_cost <- function(s) {
  bytes <- sum(vapply(s[c("design", "median_model")],
    function(x) as.numeric(x$size_bytes), numeric(1L)))
  r <- s$read_budget
  gfr_require(r$max_RDS_deserializations == 2L &&
    r$max_generated_RDS_deserializations == 0L &&
    bytes == 4152655182 && r$max_deserialization_bytes == bytes &&
    r$max_payload_hash_bytes == 2 * bytes,
    "exact two-original before/after-hash read allowance required")
  list(original_RDS_deserializations = 2L,
    generated_RDS_deserializations = 0L,
    deserialization_bytes = bytes, payload_hash_bytes = 2 * bytes)
}

ggrr_scope <- function(s) {
  q <- gfr_require
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_fixed_parameter_diagnostic",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_authority_replacement")
  fields <- c("schema_version", "purpose", "operation", "nonce", "expires_utc",
    "source_root", "source_commit", "source_tree", "source_files",
    "expected_identity", "collection", "input_manifest", "design",
    "median_model", "prior_receipt", "acceptance_budget", "controls",
    "measurement_receipt",
    "read_budget", "limits", "output_root", "metadata_scratch_root",
    "metadata_serialization", "execution_controls", yes, no)
  q(is.list(s) && length(s) == length(fields) && setequal(names(s), fields) &&
    identical(s$schema_version, "glofas_global_path_native_purpose_v1") &&
    identical(s$purpose,
      "MEDIAN_AL_FIXED_PARAMETER_GLOBAL_PATH_NO_FIT_NO_TRUTH") &&
    s$operation %in% c("measure", "execute") &&
    all(vapply(s[yes], isTRUE, logical(1L))) &&
    all(vapply(s[no], identical, logical(1L), FALSE)),
    "exact fixed-parameter diagnostic-only purpose required")
  q(is.character(s$nonce) && length(s$nonce) == 1L &&
    grepl("^[a-f0-9]{32,64}$", s$nonce) &&
    all(vapply(s[c("source_commit", "source_tree")], function(x)
      is.character(x) && length(x) == 1L && grepl("^[a-f0-9]{40}$", x),
      logical(1L))) && gst_same(s$expected_identity, gsc_identity()),
    "full source and accepted-producer identities required")
  for (pin in s[c("design", "median_model")]) gfr_pin_shape(pin, 8 * 1024^3)
  for (pin in s[c("collection", "input_manifest", "prior_receipt",
    "acceptance_budget", "controls", "measurement_receipt")])
    gfr_pin_shape(pin, 4 * 1024^2)
  q(s$design$size_bytes == 4014834693 && identical(s$design$sha256,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3") &&
    s$median_model$size_bytes == 137820489 && identical(s$median_model$sha256,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881") &&
    identical(s$input_manifest$sha256, gsc_identity()$input_manifest_sha256) &&
    identical(basename(s$controls$path),
      "glofas_global_path_native_controls.json") &&
    identical(basename(s$measurement_receipt$path),
      "GLOBAL_PATH_RECEIPT.json") &&
    identical(s$measurement_receipt$sha256,
      "66f472e44e89c72adeac3358c0f1540e43b6cfcee122080dafef4a1fc7261e3b"),
    "exact frozen native inputs and controls required")
  paths <- vapply(s$source_files, function(pin) {
    gfr_pin_shape(pin, 2 * 1024^2); pin$path
  }, character(1L))
  q(length(paths) == length(ggrr_sources()) && !anyDuplicated(paths) &&
    setequal(paths, file.path(s$source_root, ggrr_sources())),
    "complete global-path transitive source closure required")
  q(gst_same(s$controls, s$source_files[[match(s$controls$path, paths)]]) &&
    gst_same(s$acceptance_budget,
      s$source_files[[match(s$acceptance_budget$path, paths)]]),
    "tracked controls and Stage E budget must be source-pinned")
  limits <- s$limits
  q(is.list(limits) && setequal(names(limits), c("cpu_seconds", "wall_seconds",
      "memory_bytes", "output_bytes", "logical_cpu")) &&
    all(vapply(limits, gfr_scalar_integer, logical(1L))) &&
    limits$cpu_seconds > 0 && limits$cpu_seconds <= 28800L &&
    limits$wall_seconds > 0 && limits$wall_seconds <= 28800L &&
    limits$memory_bytes == 32 * 1024^3 && limits$output_bytes == 64 * 1024^2 &&
    limits$logical_cpu %in% 0:63,
    "bounded one-core global-path allocation required")
  r <- s$read_budget
  q(is.list(r) && setequal(names(r), c("max_payload_hash_bytes",
      "max_deserialization_bytes", "max_RDS_deserializations",
      "max_generated_RDS_deserializations", "max_metadata_bytes",
      "max_diagnostic_output_bytes")) &&
    all(vapply(r, gfr_scalar_integer, logical(1L))) && all(unlist(r) >= 0) &&
    r$max_metadata_bytes == 64 * 1024^2 &&
    r$max_diagnostic_output_bytes == 48 * 1024^2,
    "finite exact read and compact-output caps required")
  ggrr_cost(s)
  m <- s$metadata_serialization
  q(is.list(m) && setequal(names(m), c("max_files", "max_file_bytes",
      "max_total_bytes")) && all(vapply(m, gfr_scalar_integer, logical(1L))) &&
    m$max_files == 64L && m$max_file_bytes == 4 * 1024^2 &&
    m$max_total_bytes == 32 * 1024^2,
    "bounded generated metadata serialization required")
  ec <- s$execution_controls
  q(is.list(ec) && all(c("importance", "tempering", "probabilities",
      "proposal_covariance_inflation") %in% names(ec)),
    "explicit execution controls required even for measurement")
  invisible(TRUE)
}

ggrr_source <- function(s) {
  q <- gfr_require
  root <- normalizePath(getwd(), mustWork = TRUE)
  git <- function(args) {
    out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
      "core.fsmonitor=false", args), stdout = TRUE)
    q(is.null(attr(out, "status")), "global-path source Git check failed")
    unname(out)
  }
  q(identical(root, s$source_root) &&
    identical(git(c("rev-parse", "--show-toplevel")), root) &&
    identical(git(c("rev-parse", "HEAD")), s$source_commit) &&
    identical(git(c("rev-parse", "HEAD^{tree}")), s$source_tree) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))),
    "global-path diagnostic requires exact clean immutable source")
  for (pin in s$source_files) gsc_pin(pin, 2 * 1024^2)
  for (rel in ggrr_sources()) q(identical(
    git(c("hash-object", "--no-filters", "--", shQuote(rel))),
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel))))),
    "global-path source differs from committed blob")
  invisible(root)
}

ggrr_build <- function(engine, design, object, prior_export, budget,
    task_id = "gft-al-p050", probability = gnse_task_probability(task_id)) {
  core <- object$fit
  spec <- if (identical(task_id, "gft-al-p050"))
    gnse_spec(design, prior_export, budget) else
    gnse_spec_task(design, prior_export, budget, task_id, probability)
  initializer <- gnse_initializer(core, spec, design, budget)
  context <- gnr_context(design, engine)
  known <- if (is.null(design$discrepancy_baseline_future)) rep(0, 28L) else
    as.numeric(design$discrepancy_baseline_future)
  binding <- gnse_binding(engine, context, spec, known, budget)
  decoded <- gcat_decode(initializer$mean, spec)
  parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  mean <- as.numeric(core$variational_state$y_future_mean)
  covariance <- as.matrix(core$variational_state$y_future_cov)
  adapter <- gnfa_build(binding, parameters, mean, covariance)
  list(core = core, spec = spec, initializer = initializer, binding = binding,
    parameters = parameters, mean = mean, covariance = covariance, adapter = adapter)
}

ggrr_measure <- function(built, controls) {
  sd <- sqrt(diag(built$covariance))
  multiplier <- controls$measurement$sd_multiplier
  paths <- list(retained_mean = built$mean,
    retained_mean_minus_quarter_sd = built$mean - multiplier * sd,
    retained_mean_plus_quarter_sd = built$mean + multiplier * sd)
  rows <- list(); at <- 0L
  for (path_name in names(paths)) for (contract_name in names(built$adapter$contracts)) {
    started <- proc.time()[["elapsed"]]
    parts <- gffd_log_target(paths[[path_name]], built$adapter$callback,
      built$adapter$contracts[[contract_name]], TRUE)
    at <- at + 1L
    rows[[at]] <- data.frame(path = path_name, contract = contract_name,
      path_law = built$adapter$contracts[[contract_name]]$path_law,
      member_policy = built$adapter$contracts[[contract_name]]$member_policy,
      path_log_density = parts$path, member_log_density = parts$members,
      total_log_density = parts$total,
      elapsed_seconds = proc.time()[["elapsed"]] - started,
      stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  gfr_require(nrow(out) == controls$measurement$maximum_target_evaluations &&
    all(is.finite(unlist(out[c("path_log_density", "member_log_density",
      "total_log_density", "elapsed_seconds")]))) &&
    max(out$elapsed_seconds) <= controls$measurement$maximum_wall_seconds,
    "complete finite bounded target measurement required")
  out
}

ggrr_execute <- function(built, execution, seed_base) {
  q <- gfr_require
  q(isTRUE(execution$authorized), "tracked controls do not authorize execution")
  probabilities <- as.numeric(execution$probabilities)
  inflation <- as.numeric(execution$proposal_covariance_inflation)
  covariance <- inflation * built$covariance
  diag(covariance) <- diag(covariance) + 1e-10
  references <- reporting <- list()
  for (i in seq_along(built$adapter$contracts)) {
    name <- names(built$adapter$contracts)[i]
    contract <- built$adapter$contracts[[i]]
    target <- function(path) gffd_log_target(path, built$adapter$callback, contract)
    importance <- execution$importance
    importance$seed <- as.integer(seed_base + i)
    reference <- ggpr_importance(target, built$mean, covariance, probabilities,
      importance, retain_paths = TRUE)
    tempered <- NULL
    if (!isTRUE(reference$diagnostic_thresholds_passed)) {
      tempering <- execution$tempering
      tempering$seed <- as.integer(seed_base + 100L + i)
      tempered <- ggpr_tempered(target, built$mean, covariance, probabilities,
        tempering, retain_paths = TRUE)
    }
    combined <- list(schema_version = "glofas_forecast_factorial_reference_v1",
      contract = contract, importance = reference, tempered = tempered,
      future_truth_read = FALSE, full_parameter_refits = 0L,
      production_qualified = FALSE)
    references[[name]] <- combined
    reporting[[name]] <- gffd_reporting(combined, built$adapter$callback,
      list(mean = built$mean, covariance = built$covariance))
  }
  list(references = references, reporting = reporting)
}

ggrr_reference_outputs <- function(result) {
  q <- gfr_require
  q(is.list(result) && is.list(result$references) && length(result$references),
    "complete global-path reference result required")
  outputs <- list()
  summary_rows <- list()
  row_at <- 0L
  for (contract_name in names(result$references)) {
    reference <- result$references[[contract_name]]
    for (method_name in c("importance", "tempered")) {
      draw <- reference[[method_name]]
      if (is.null(draw)) next
      q(is.matrix(draw$paths) && nrow(draw$paths) == length(draw$weights) &&
        ncol(draw$paths) == reference$contract$horizon &&
        length(draw$log_target) == nrow(draw$paths) &&
        length(draw$log_proposal) == nrow(draw$paths),
        "retained paths and reference weights are incomplete")
      evidence <- data.frame(contract = contract_name, method = method_name,
        particle = seq_len(nrow(draw$paths)), weight = draw$weights,
        log_target = draw$log_target, log_proposal = draw$log_proposal,
        stringsAsFactors = FALSE)
      names(draw$paths) <- NULL
      path_frame <- as.data.frame(draw$paths, stringsAsFactors = FALSE)
      names(path_frame) <- sprintf("h%02d", seq_len(ncol(path_frame)))
      evidence <- cbind(evidence, path_frame)
      outputs[[paste0("paths_", contract_name, "__", method_name, ".csv")]] <-
        gfr_csv_raw(evidence)
      row_at <- row_at + 1L
      summary_rows[[row_at]] <- data.frame(contract = contract_name,
        method = method_name, status = draw$status,
        diagnostic_thresholds_passed = isTRUE(draw$diagnostic_thresholds_passed),
        complete = if (is.null(draw$complete)) TRUE else isTRUE(draw$complete),
        particles = nrow(draw$paths), evaluations = draw$evaluations,
        effective_sample_size = draw$effective_sample_size,
        maximum_weight = draw$maximum_weight,
        normalized_entropy = draw$normalized_entropy,
        elapsed_seconds = draw$elapsed_seconds, stringsAsFactors = FALSE)
      if (!is.null(draw$diagnostics) && nrow(draw$diagnostics)) {
        stages <- transform(draw$diagnostics, contract = contract_name,
          method = method_name)
        outputs[[paste0("stages_", contract_name, "__", method_name, ".csv")]] <-
          gfr_csv_raw(stages)
      }
    }
  }
  q(length(summary_rows) > 0L, "at least one reference output is required")
  outputs[["reference_summary.csv"]] <- gfr_csv_raw(do.call(rbind, summary_rows))
  outputs
}

ggrr_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_global_path_native_reader.R --contract FILE --sha256 SHA --dry-run|--execute\n")
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L, 3L)], c("--contract", "--sha256")) &&
    args[5L] %in% c("--dry-run", "--execute"), "explicit external purpose required")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  info <- file.info(purpose)
  q(grepl("\\.json$", purpose) && !isTRUE(info$isdir) && info$size <= 1024^2 &&
    info$uid == file.info("/proc/self")$uid && bitwAnd(as.integer(info$mode), 63L) == 0L &&
    gsc_hash_string(args[4L]) && identical(unname(tools::sha256sum(purpose)), args[4L]),
    "private owned external purpose digest required")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE)
  ggrr_scope(s)
  controls <- jsonlite::read_json(gsc_pin(s$controls, 4 * 1024^2),
    simplifyVector = FALSE)
  ggrr_controls(controls)
  q(identical(s$measurement_receipt$sha256,
      controls$authentic_measurement$receipt_sha256) &&
    gst_same(s$execution_controls, controls$execution),
    "purpose must use the measured and tracked execution controls exactly")
  if (identical(s$operation, "execute")) q(isTRUE(controls$execution$authorized),
    "tracked control freezes execution until measurement review")
  if (args[5L] == "--dry-run") {
    cat("GLOFAS_GLOBAL_PATH_NATIVE_PURPOSE_VALID_NO_PAYLOAD_READS operation=",
      s$operation, "\n", sep = "")
    return(invisible(TRUE))
  }
  gst_runtime(s); root <- ggrr_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds,
    "purpose expiry must cover the admitted process")
  out <- s$output_root; scratch <- s$metadata_scratch_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    dir.exists(dirname(out)) && system2("/usr/bin/git", c("check-ignore", "--quiet",
      "--", shQuote(out))) == 0L, "fresh ignored output required")
  q(dir.exists(scratch) && identical(normalizePath(scratch), scratch) &&
    identical(list.files(scratch, all.files = TRUE, no.. = TRUE), basename(tempdir())) &&
    !length(list.files(tempdir(), all.files = TRUE, no.. = TRUE)) &&
    identical(Sys.getenv("TMPDIR"), scratch), "empty owned metadata scratch required")
  metadata <- c(s$source_files, s[c("collection", "input_manifest", "prior_receipt",
    "acceptance_budget", "controls", "measurement_receipt")])
  for (pin in metadata) gsc_pin(pin, 4 * 1024^2)
  collection <- jsonlite::read_json(s$collection$path, simplifyVector = FALSE)
  manifest <- read.csv(s$input_manifest$path, stringsAsFactors = FALSE)
  prior <- jsonlite::read_json(s$prior_receipt$path, simplifyVector = FALSE)
  budget <- jsonlite::read_json(s$acceptance_budget$path, simplifyVector = FALSE)
  measured <- jsonlite::read_json(s$measurement_receipt$path, simplifyVector = FALSE)
  q(identical(measured$schema_version, "glofas_global_path_native_receipt_v1") &&
    identical(measured$status, "MEASUREMENT_COMPLETE_EXECUTION_NOT_AUTHORIZED") &&
    identical(measured$source_commit, controls$authentic_measurement$source_commit) &&
    measured$future_truth_read == FALSE && measured$model_fits == 0L &&
    measured$parameter_updates == 0L && measured$scoring == FALSE,
    "authentic truth-free measurement receipt is invalid")
  bound <- gnser_bind_metadata(s, collection, manifest, prior, budget)
  q(dir.create(out, mode = "0700"), "exclusive output creation failed")
  attempts <- list(); post_attempted <- logical(); finished <- FALSE
  started <- proc.time()[["elapsed"]]; engine <- NULL
  post_hash <- function() {
    closed <- gnser_post_hash_attempts(attempts, post_attempted)
    attempts <<- closed$attempts; post_attempted <<- closed$post_attempted
  }
  on.exit(if (!finished) try({
    post_hash()
    gfr_write(gfr_json_raw(list(schema_version =
      "glofas_global_path_native_failure_v1", status = "FAILED_PARTIAL_NO_FIT_NO_TRUTH",
      attempted_reads = attempts, future_truth_read = FALSE, model_fits = 0L,
      production_authorized = FALSE, publication_authorized = FALSE)),
      file.path(out, "FAILED_GLOBAL_PATH_RECEIPT.json"), out, s$limits$output_bytes)
  }, silent = TRUE), add = TRUE)
  read_one <- function(pin, role) {
    path <- gsc_pin(pin, 8 * 1024^3)
    attempt_pin <- pin
    attempt_pin$path <- path
    opened <- gnser_append_attempt(attempts, post_attempted, attempt_pin, role)
    attempts <<- opened$attempts; post_attempted <<- opened$post_attempted
    value <- readRDS(path); attempts[[opened$index]]$status <<- "DESERIALIZED"; value
  }
  design <- read_one(s$design, "truth_free_shared_design")
  object <- read_one(s$median_model, "accepted_median_AL_fit")
  gsc_validate_target(object, bound$producer)
  q(identical(object$task_id, "gft-al-p050") && nrow(design$future_key) == 28L &&
    is.null(design$future_context$latent_data$y_future_oracle),
    "exact truth-free median AL H28 payload required")
  child <- file.path(scratch, "global_path_contract_metadata")
  q(!file.exists(child) && dir.create(child), "exclusive metadata child required")
  engine <- gnr_engine(root, child, s$metadata_serialization)
  built <- ggrr_build(engine, design, object, bound$prior_export, budget)
  measurement <- ggrr_measure(built, controls)
  result <- NULL
  if (identical(s$operation, "execute"))
    result <- ggrr_execute(built, s$execution_controls, 2026110600L)
  gfr_write(gfr_csv_raw(measurement), file.path(out, "target_measurement.csv"),
    out, s$limits$output_bytes)
  if (!is.null(result)) {
    reports <- do.call(rbind, Map(function(x, name) transform(x, contract = name),
      result$reporting, names(result$reporting)))
    gfr_write(gfr_csv_raw(reports), file.path(out, "reporting.csv"), out,
      s$limits$output_bytes)
    reference_outputs <- ggrr_reference_outputs(result)
    q(sum(vapply(reference_outputs, length, integer(1L))) <=
      s$read_budget$max_diagnostic_output_bytes,
      "raw global-path evidence exceeds its compact-output cap")
    for (name in names(reference_outputs)) gfr_write(reference_outputs[[name]],
      file.path(out, name), out, s$limits$output_bytes)
  }
  summary <- list(schema_version = "glofas_global_path_native_summary_v1",
    operation = s$operation, status = if (s$operation == "measure")
      "MEASUREMENT_COMPLETE_EXECUTION_NOT_AUTHORIZED" else
      "GLOBAL_PATH_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION",
    adapter_sha256 = built$adapter$adapter_sha256,
    binding_static_sha256 = built$binding$static_sha256,
    parameter_id = built$adapter$parameter_id, feature_id = built$adapter$feature_id,
    target_evaluations = nrow(measurement), maximum_target_seconds =
      max(measurement$elapsed_seconds), future_truth_read = FALSE,
    model_fits = 0L, parameter_updates = 0L, scoring = FALSE,
    authority_replacement = FALSE, production_authorized = FALSE,
    publication_authorized = FALSE)
  gfr_write(gfr_json_raw(summary), file.path(out, "global_path_summary.json"),
    out, s$limits$output_bytes)
  rm(design, object, collection, manifest, prior, measured); gc(FALSE)
  post_hash(); for (pin in metadata) gsc_pin(pin, 4 * 1024^2); ggrr_source(s)
  receipt <- list(schema_version = "glofas_global_path_native_receipt_v1",
    status = summary$status, purpose_sha256 = args[4L], operation = s$operation,
    source_commit = s$source_commit, source_tree = s$source_tree,
    producer_identity = gsc_identity(), input_bindings = s[c("design", "median_model")],
    attempted_reads = attempts, original_RDS_deserializations = 2L,
    generated_RDS_deserializations = 0L, metadata_serializations = engine$audit$metadata,
    source_feature_value_calls = engine$audit$value_calls,
    future_truth_read = FALSE, model_fits = 0L, parameter_updates = 0L,
    scoring = FALSE, production_authorized = FALSE, publication_authorized = FALSE,
    CPU_seconds = sum(proc.time()[c("user.self", "sys.self", "user.child", "sys.child")]),
    elapsed_seconds = proc.time()[["elapsed"]] - started)
  gfr_write(gfr_json_raw(receipt), file.path(out, "GLOBAL_PATH_RECEIPT.json"),
    out, s$limits$output_bytes)
  files <- list.files(out, full.names = TRUE)
  inventory <- data.frame(relative_path = basename(files), size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)), stringsAsFactors = FALSE)
  gfr_write(gfr_csv_raw(inventory), file.path(out, "artifact_manifest.csv"),
    out, s$limits$output_bytes)
  finished <- TRUE
  cat("GLOFAS_GLOBAL_PATH_NATIVE_COMPLETE operation=", s$operation,
    " status=", summary$status, "\n", sep = "")
  invisible(receipt)
}

if (sys.nframe() == 0L) ggrr_main()
