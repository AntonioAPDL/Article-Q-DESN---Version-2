#!/usr/bin/env Rscript
# Purpose-bound Stage E native operations/precision qualification. Exactly two
# authenticated original RDS objects are read. No optimizer, refit, truth read,
# scoring, publication, or Stage F launch is available from this entry point.
source("scripts/glofas_nonlinear_replay_reader.R")
source("scripts/diagnostics/glofas_innovation_coordinates.R")
source("scripts/diagnostics/glofas_collapsed_particle_vi.R")
source("scripts/diagnostics/glofas_guided_collapsed_particle.R")
source("scripts/diagnostics/glofas_collapsed_al_target.R")
source("scripts/diagnostics/glofas_two_desn_particle_backend.R")
source("scripts/diagnostics/glofas_native_parameter_optimizer.R")
source("scripts/diagnostics/glofas_particle_marginal_quantiles.R")
source("scripts/diagnostics/glofas_native_stage_e.R")

gnser_sources <- function() unique(c(gnrr_sources(),
  "scripts/glofas_native_stage_e_reader.R",
  "scripts/diagnostics/glofas_innovation_coordinates.R",
  "scripts/diagnostics/glofas_collapsed_particle_vi.R",
  "scripts/diagnostics/glofas_guided_collapsed_particle.R",
  "scripts/diagnostics/glofas_collapsed_al_target.R",
  "scripts/diagnostics/glofas_two_desn_particle_backend.R",
  "scripts/diagnostics/glofas_native_parameter_optimizer.R",
  "scripts/diagnostics/glofas_particle_marginal_quantiles.R",
  "scripts/diagnostics/glofas_native_stage_e.R",
  "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json"))

gnser_cost <- function(s) {
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

gnser_append_attempt <- function(attempts, post_attempted, pin, role) {
  q <- gfr_require
  at <- length(attempts) + 1L
  q(at <= 2L && length(post_attempted) == length(attempts),
    "consistent two-original Stage E read ledger required")
  attempts[[at]] <- list(role = role, path = pin$path,
    size_bytes = pin$size_bytes, sha256 = pin$sha256,
    pre_read_sha256 = pin$sha256, status = "DESERIALIZATION_ATTEMPTED")
  post_attempted[[at]] <- FALSE
  list(attempts = attempts, post_attempted = post_attempted, index = at)
}

gnser_post_hash_attempts <- function(attempts, post_attempted) {
  q <- gfr_require
  q(length(attempts) <= 2L && length(post_attempted) == length(attempts),
    "consistent Stage E post-read ledger required")
  for (i in seq_along(attempts)) if (!isTRUE(post_attempted[[i]])) {
    post_attempted[[i]] <- TRUE
    if (is.null(attempts[[i]]$pre_read_sha256)) next
    gsc_pin(attempts[[i]][c("path", "size_bytes", "sha256")], 8 * 1024^3)
    attempts[[i]]$post_read_sha256 <- attempts[[i]]$sha256
    attempts[[i]]$post_hash_status <- "PASS"
  }
  list(attempts = attempts, post_attempted = post_attempted)
}

gnser_scope <- function(s) {
  q <- gfr_require; gst_unique_objects(s)
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_target_qualification",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_stage_f_launch",
    "allow_derived_context_serialization")
  fields <- c("schema_version", "purpose", "nonce", "expires_utc",
    "source_root", "source_commit", "source_tree", "source_files",
    "expected_identity", "collection", "input_manifest", "design",
    "median_model", "prior_receipt", "acceptance_budget", "read_budget",
    "limits", "output_root", "metadata_scratch_root",
    "metadata_serialization", yes, no)
  q(is.list(s) && length(s) == length(fields) && setequal(names(s), fields) &&
    identical(s$schema_version, "glofas_native_stage_e_purpose_v1") &&
    identical(s$purpose,
      "MEDIAN_AL_NATIVE_OPERATIONS_PRECISION_COST_NO_FIT_NO_TRUTH") &&
    all(vapply(s[yes], isTRUE, logical(1L))) &&
    all(vapply(s[no], identical, logical(1L), FALSE)),
    "exact Stage E qualification-only purpose required")
  q(is.character(s$nonce) && length(s$nonce) == 1L &&
    grepl("^[a-f0-9]{32,64}$", s$nonce) &&
    all(vapply(s[c("source_commit", "source_tree")], function(x)
      is.character(x) && length(x) == 1L && grepl("^[a-f0-9]{40}$", x),
      logical(1L))) && gst_same(s$expected_identity, gsc_identity()),
    "full source and accepted-producer identities required")
  for (pin in s[c("design", "median_model")]) gfr_pin_shape(pin, 8 * 1024^3)
  for (pin in s[c("collection", "input_manifest", "prior_receipt",
    "acceptance_budget")]) gfr_pin_shape(pin, 4 * 1024^2)
  q(s$design$size_bytes == 4014834693 &&
    identical(s$design$sha256,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3") &&
    s$median_model$size_bytes == 137820489 &&
    identical(s$median_model$sha256,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881") &&
    identical(s$input_manifest$sha256, gsc_identity()$input_manifest_sha256) &&
    identical(basename(s$collection$path), "accepted_producers.json") &&
    identical(basename(s$design$path), "shared_truth_free_design.rds") &&
    identical(basename(s$median_model$path), "fit.rds") &&
    identical(basename(s$prior_receipt$path),
      "NATIVE_PRIOR_CONFIG_READ_RECEIPT.json") &&
    identical(basename(s$acceptance_budget$path),
      "glofas_native_stage_e_acceptance_budget.json"),
    "exact native Stage E input roles required")
  limits <- s$limits
  keys <- c("cpu_seconds", "wall_seconds", "memory_bytes", "output_bytes",
    "logical_cpu")
  q(is.list(limits) && setequal(names(limits), keys) &&
    all(vapply(limits, gfr_scalar_integer, logical(1L))) &&
    limits$cpu_seconds == 28800L && limits$wall_seconds == 28800L &&
    limits$memory_bytes == 32 * 1024^3 &&
    limits$output_bytes == 64 * 1024^2 && limits$logical_cpu %in% 0:63,
    "exact one-core eight-hour 32-GiB Stage E allocation required")
  r <- s$read_budget
  keys <- c("max_payload_hash_bytes", "max_deserialization_bytes",
    "max_RDS_deserializations", "max_generated_RDS_deserializations",
    "max_metadata_bytes", "max_qualification_output_bytes")
  q(is.list(r) && setequal(names(r), keys) &&
    all(vapply(r, gfr_scalar_integer, logical(1L))) && all(unlist(r) >= 0) &&
    r$max_metadata_bytes == 64 * 1024^2 &&
    r$max_qualification_output_bytes == 24 * 1024^2,
    "finite exact Stage E read and compact-output caps required")
  m <- s$metadata_serialization
  q(is.list(m) && setequal(names(m),
      c("max_files", "max_file_bytes", "max_total_bytes")) &&
    all(vapply(m, gfr_scalar_integer, logical(1L))) && all(unlist(m) > 0) &&
    m$max_files == 64L && m$max_file_bytes == 4 * 1024^2 &&
    m$max_total_bytes == 32 * 1024^2 &&
    m$max_total_bytes + r$max_qualification_output_bytes + 65536 <=
      limits$output_bytes,
    "bounded generated metadata and Stage E output required")
  paths <- vapply(s$source_files, function(pin) {
    gfr_pin_shape(pin, 2 * 1024^2); pin$path
  }, character(1L))
  q(length(paths) == length(gnser_sources()) && !anyDuplicated(paths) &&
    setequal(paths, file.path(s$source_root, gnser_sources())),
    "complete Stage E transitive source closure required")
  q(gst_same(s$acceptance_budget,
    s$source_files[[match(s$acceptance_budget$path, paths)]]),
    "acceptance budget must be the frozen tracked source pin")
  gnser_cost(s); invisible(TRUE)
}

gnser_source <- function(s) {
  q <- gfr_require; root <- normalizePath(getwd(), mustWork = TRUE)
  git <- function(args) {
    out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
      "core.fsmonitor=false", args), stdout = TRUE)
    q(is.null(attr(out, "status")), "Stage E source Git check failed")
    unname(out)
  }
  q(identical(root, s$source_root) &&
    identical(git(c("rev-parse", "--show-toplevel")), root) &&
    identical(git(c("rev-parse", "HEAD")), s$source_commit) &&
    identical(git(c("rev-parse", "HEAD^{tree}")), s$source_tree) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))),
    "Stage E requires exact clean immutable source")
  for (pin in s$source_files) gsc_pin(pin, 2 * 1024^2)
  for (rel in gnser_sources()) q(identical(
    git(c("hash-object", "--no-filters", "--", shQuote(rel))),
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel))))),
    "Stage E source differs from committed blob")
  for (rel in gnr_production_sources()) q(identical(
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel)))),
    git(c("rev-parse", shQuote(paste0(gsc_identity()$source_commit, ":", rel))))),
    "production continuation blob differs from accepted producer")
  invisible(root)
}

gnser_bind_metadata <- function(s, collection, manifest, prior, budget) {
  q <- gfr_require
  producer <- gnrr_bind(s, collection, manifest)
  q(is.list(prior) && identical(prior$schema_version,
      "glofas_native_prior_config_read_receipt_v1") &&
    identical(prior$status, "ONE_CONFIG_PRIOR_EXPORTED_NO_MODEL_RUN") &&
    prior$read_accounting$RDS_deserializations == 1L &&
    prior$future_truth_read == FALSE && prior$design_reads == 0L &&
    prior$fit_reads == 0L && prior$model_runs == 0L &&
    prior$publication_authorized == FALSE &&
    identical(prior$export$schema_version, "glofas_native_prior_export_v1") &&
    identical(prior$export$task_id, "gft-al-p050") &&
    identical(prior$export$posterior_target_sha256,
      budget$posterior_target_sha256) &&
    identical(prior$export$declared_prior_sha256,
      budget$declared_prior_sha256) &&
    identical(prior$export$effective_prior_sha256,
      budget$effective_prior_sha256) &&
    prior$export$model_run_authorized == FALSE &&
    prior$export$native_application_qualified == FALSE &&
    prior$export$publication_authorized == FALSE,
    "closed Stage A prior export identity required")
  gnse_validate_budget(budget)
  list(producer = producer, prior_export = prior$export)
}

gnser_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_native_stage_e_reader.R --contract FILE --sha256 SHA --dry-run|--execute\n")
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L, 3L)],
    c("--contract", "--sha256")) && args[5L] %in% c("--dry-run", "--execute"),
    "explicit external Stage E purpose required")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  info <- file.info(purpose)
  q(grepl("\\.json$", purpose) && !isTRUE(info$isdir) &&
    info$size <= 1024^2 && info$uid == file.info("/proc/self")$uid &&
    bitwAnd(as.integer(info$mode), 63L) == 0L && gsc_hash_string(args[4L]) &&
    identical(unname(tools::sha256sum(purpose)), args[4L]),
    "private owned external Stage E purpose digest required")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE); gnser_scope(s)
  root <- normalizePath(getwd(), mustWork = TRUE)
  q(!startsWith(purpose, paste0(root, "/")),
    "Stage E purpose must remain external to source")
  if (args[5L] == "--dry-run") {
    cat("GLOFAS_NATIVE_STAGE_E_PURPOSE_VALID_NO_PAYLOAD_READS\n")
    return(invisible(gnser_cost(s)))
  }
  gst_runtime(s); gnser_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds,
    "purpose expiry must cover the complete Stage E process")
  out <- s$output_root; scratch <- s$metadata_scratch_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    dir.exists(dirname(out)) && identical(normalizePath(dirname(out)), dirname(out)) &&
    !grepl("(^|/)\\.\\.(/|$)", out) &&
    system2("/usr/bin/git", c("check-ignore", "--quiet", "--", shQuote(out))) == 0L,
    "fresh exclusive ignored Stage E output required")
  q(dir.exists(scratch) && identical(normalizePath(scratch), scratch) &&
    identical(list.files(scratch, all.files = TRUE, no.. = TRUE), basename(tempdir())) &&
    !length(list.files(tempdir(), all.files = TRUE, no.. = TRUE)) &&
    identical(Sys.getenv("TMPDIR"), scratch) &&
    startsWith(normalizePath(tempdir()), paste0(scratch, "/")),
    "empty owned Stage E metadata scratch required")
  metadata <- c(s$source_files, s[c("collection", "input_manifest",
    "prior_receipt")])
  q(8 * sum(vapply(metadata, function(x) x$size_bytes, numeric(1L))) +
      8 * 1024^2 <= s$read_budget$max_metadata_bytes,
    "conservative metadata-read allowance exceeded")
  collection <- jsonlite::read_json(gsc_pin(s$collection, 4 * 1024^2),
    simplifyVector = FALSE)
  manifest <- read.csv(gsc_pin(s$input_manifest, 4 * 1024^2),
    stringsAsFactors = FALSE)
  prior <- jsonlite::read_json(gsc_pin(s$prior_receipt, 4 * 1024^2),
    simplifyVector = FALSE)
  budget <- jsonlite::read_json(gsc_pin(s$acceptance_budget, 4 * 1024^2),
    simplifyVector = FALSE)
  bound <- gnser_bind_metadata(s, collection, manifest, prior, budget)
  cost <- gnser_cost(s)
  q(dir.create(out, mode = "0700"), "exclusive Stage E output creation failed")
  attempts <- list(); post_attempted <- logical(); finished <- FALSE
  started <- proc.time()[["elapsed"]]; engine <- NULL; result <- NULL
  post_hash <- function() {
    closed <- gnser_post_hash_attempts(attempts, post_attempted)
    attempts <<- closed$attempts
    post_attempted <<- closed$post_attempted
    invisible(TRUE)
  }
  on.exit(if (!finished) try({
    post_hash()
    failure <- list(schema_version = "glofas_native_stage_e_failure_v1",
      status = "FAILED_PARTIAL_STAGE_E_RETAINED_NO_FIT", attempted_reads = attempts,
      decision = if (is.null(result)) "INCONCLUSIVE" else result$summary$decision,
      future_truth_read = FALSE, model_fits = 0L, optimizer_iterations = 0L,
      stage_f_authorized = FALSE, production_authorized = FALSE,
      publication_authorized = FALSE)
    gfr_write(gfr_json_raw(failure), file.path(out, "FAILED_STAGE_E_RECEIPT.json"),
      out, s$limits$output_bytes)
  }, silent = TRUE), add = TRUE)
  read_one <- function(pin, role) {
    path <- gsc_pin(pin, 8 * 1024^3)
    attempt_pin <- pin
    attempt_pin$path <- path
    opened <- gnser_append_attempt(attempts, post_attempted,
      attempt_pin, role)
    attempts <<- opened$attempts
    post_attempted <<- opened$post_attempted
    at <- opened$index
    value <- readRDS(path)
    attempts[[at]]$status <<- "DESERIALIZED"
    value
  }
  design <- read_one(s$design, "truth_free_shared_design")
  object <- read_one(s$median_model, "accepted_median_AL_fit")
  gsc_validate_target(object, bound$producer)
  q(identical(object$task_id, "gft-al-p050") &&
    nrow(design$future_key) == 28L &&
    identical(as.numeric(as.Date(design$future_key$target_date)),
      as.numeric(gsc_dates())) && is.null(design$future_context$latent_data$y_future_oracle),
    "exact truth-free median AL H28 payload required")
  scratch_child <- file.path(scratch, "stage_e_contract_metadata")
  q(!file.exists(scratch_child) && dir.create(scratch_child),
    "exclusive Stage E generated metadata scratch failed")
  engine <- gnr_engine(root, scratch_child, s$metadata_serialization)
  source_sha <- vapply(s$source_files, function(x) x$sha256, character(1L))
  names(source_sha) <- vapply(s$source_files, function(x)
    substring(x$path, nchar(root) + 2L), character(1L))
  available_wall <- s$limits$wall_seconds - (proc.time()[["elapsed"]] - started)
  q(available_wall > 600, "insufficient admitted time remains after authenticated reads")
  result <- gnse_run(engine, design, object, bound$prior_export, budget,
    wall_seconds = available_wall, source_sha256 = source_sha)
  tables <- c("parity", "derivatives", "derivative_summary", "h2",
    "h2_summary", "h2_pieces", "rhs_invariance", "extension",
    "particle_grid", "particle_horizon", "particle_quantiles",
    "precision_summary", "precision_drift", "reporting_precision",
    "reporting_stability", "adjacent_pair_decisions", "gradient_assessment")
  outputs <- setNames(lapply(tables, function(name) gfr_csv_raw(result[[name]])),
    paste0(tables, ".csv"))
  outputs[["stage_e_summary.json"]] <- gfr_json_raw(result$summary)
  outputs[["native_target_contract.json"]] <- gfr_json_raw(result$native_contract)
  outputs[["native_binding.json"]] <- gfr_json_raw(result$binding)
  q(sum(vapply(outputs, length, integer(1L))) <=
    s$read_budget$max_qualification_output_bytes,
    "compact Stage E evidence exceeds its output cap")
  for (name in names(outputs)) gfr_write(outputs[[name]], file.path(out, name),
    out, s$limits$output_bytes)
  rm(design, object, collection, manifest, prior, outputs); gc(FALSE)
  post_hash()
  for (pin in metadata) gsc_pin(pin, 4 * 1024^2)
  gnser_source(s)
  cpu <- sum(proc.time()[c("user.self", "sys.self", "user.child", "sys.child")])
  q(length(attempts) == 2L && all(vapply(attempts,
      function(x) identical(x$status, "DESERIALIZED") &&
        identical(x$post_hash_status, "PASS"), logical(1L))) &&
    expiry > Sys.time() && cpu <= s$limits$cpu_seconds &&
    result$summary$decision %in% unlist(budget$decision_states),
    "Stage E final lifetime, source, read, or decision gate failed")
  receipt <- list(schema_version = "glofas_native_stage_e_receipt_v1",
    status = "STAGE_E_COMPLETE_NO_FIT_NO_TRUTH",
    decision = result$summary$decision, purpose_sha256 = args[4L],
    source_commit = s$source_commit, source_tree = s$source_tree,
    producer_identity = gsc_identity(), input_bindings = s[c("design", "median_model")],
    accepted_collection = s$collection, input_manifest = s$input_manifest,
    prior_receipt = s$prior_receipt, acceptance_budget = s$acceptance_budget,
    read_cost = cost, attempted_reads = attempts,
    original_RDS_deserializations = 2L, generated_RDS_deserializations = 0L,
    metadata_serializations = engine$audit$metadata,
    source_feature_factory_calls = engine$audit$factory_calls,
    source_feature_value_calls = engine$audit$value_calls,
    saved_callback_calls = 0L, model_fits = 0L, optimizer_iterations = 0L,
    future_truth_read = FALSE, scoring = FALSE, retuning = FALSE,
    stage_f_authorized = FALSE, native_fit_authorized = FALSE,
    production_authorized = FALSE, publication_authorized = FALSE,
    CPU_seconds = cpu, elapsed_seconds = proc.time()[["elapsed"]] - started,
    peak_rss_bytes = gnse_peak_rss(), independent_supervisor_closure_required = TRUE)
  gfr_write(gfr_json_raw(receipt), file.path(out, "NATIVE_STAGE_E_RECEIPT.json"),
    out, s$limits$output_bytes)
  files <- list.files(out, full.names = TRUE)
  inventory <- data.frame(relative_path = basename(files),
    size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)), stringsAsFactors = FALSE)
  gfr_write(gfr_csv_raw(inventory), file.path(out, "artifact_manifest.csv"),
    out, s$limits$output_bytes)
  finished <- TRUE
  cat("GLOFAS_NATIVE_STAGE_E_COMPLETE_NO_FIT_NO_TRUTH decision=",
    result$summary$decision, "\n", sep = "")
  invisible(receipt)
}

if (sys.nframe() == 0L) gnser_main()
