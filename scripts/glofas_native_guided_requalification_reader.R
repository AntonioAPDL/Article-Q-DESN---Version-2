#!/usr/bin/env Rscript
# Purpose-bound guided native requalification. Exactly two authenticated
# original RDS objects are read. No fit, optimizer, truth, scoring, article,
# publication, or Stage F operation is available from this entry point.
source("scripts/glofas_native_stage_e_reader.R")
source("scripts/diagnostics/glofas_al_affine_guided_proposal.R")
source("scripts/diagnostics/glofas_native_guided_requalification.R")

gngrr_sources <- function() unique(c(gnser_sources(),
  "scripts/glofas_native_guided_requalification_reader.R",
  "scripts/diagnostics/glofas_al_affine_guided_proposal.R",
  "scripts/diagnostics/glofas_native_guided_requalification.R",
  "scripts/diagnostics/glofas_native_guided_requalification_budget.json"))

gngrr_stage_e_view <- function(s) {
  fields <- c("schema_version", "purpose", "nonce", "expires_utc",
    "source_root", "source_commit", "source_tree", "source_files",
    "expected_identity", "collection", "input_manifest", "design",
    "median_model", "prior_receipt", "acceptance_budget", "read_budget",
    "limits", "output_root", "metadata_scratch_root",
    "metadata_serialization", "allow_original_reads",
    "allow_prior_metadata_read", "allow_fresh_source_feature_replay",
    "allow_target_qualification", "allow_metadata_serialization",
    "allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_stage_f_launch",
    "allow_derived_context_serialization")
  out <- s[fields]
  out$schema_version <- "glofas_native_stage_e_purpose_v1"
  out$purpose <- "MEDIAN_AL_NATIVE_OPERATIONS_PRECISION_COST_NO_FIT_NO_TRUTH"
  paths <- vapply(s$source_files, function(x) x$path, character(1L))
  keep <- file.path(s$source_root, gnser_sources())
  at <- match(keep, paths)
  gfr_require(!anyNA(at), "guided source closure omits the Stage E base")
  out$source_files <- s$source_files[at]
  out
}

gngrr_scope <- function(s) {
  q <- gfr_require
  fields <- c(names(gngrr_stage_e_view(s)), "guide_budget")
  q(is.list(s) && length(s) == length(fields) && setequal(names(s), fields) &&
    identical(s$schema_version,
      "glofas_native_guided_requalification_purpose_v1") &&
    identical(s$purpose,
      "MEDIAN_AL_GUIDED_NATIVE_REQUALIFICATION_NO_FIT_NO_TRUTH"),
    "exact guided requalification purpose required")
  base <- gngrr_stage_e_view(s)
  gnser_scope(base)
  gfr_pin_shape(s$guide_budget, 4 * 1024^2)
  q(identical(basename(s$guide_budget$path),
      "glofas_native_guided_requalification_budget.json"),
    "exact guided requalification budget role required")
  paths <- vapply(s$source_files, function(pin) {
    gfr_pin_shape(pin, 2 * 1024^2); pin$path
  }, character(1L))
  q(length(paths) == length(gngrr_sources()) && !anyDuplicated(paths) &&
    setequal(paths, file.path(s$source_root, gngrr_sources())),
    "complete guided requalification source closure required")
  q(gst_same(s$guide_budget,
    s$source_files[[match(s$guide_budget$path, paths)]]),
    "guide budget must be the frozen tracked source pin")
  invisible(TRUE)
}

gngrr_source <- function(s) {
  root <- gnser_source(gngrr_stage_e_view(s))
  git <- function(args) {
    out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
      "core.fsmonitor=false", args), stdout = TRUE)
    gfr_require(is.null(attr(out, "status")),
      "guided source Git check failed")
    unname(out)
  }
  for (pin in s$source_files) gsc_pin(pin, 2 * 1024^2)
  for (rel in gngrr_sources()) gfr_require(identical(
    git(c("hash-object", "--no-filters", "--", shQuote(rel))),
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel))))),
    "guided source differs from committed blob")
  root
}

gngrr_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat(paste0("Usage: Rscript --vanilla ",
      "scripts/glofas_native_guided_requalification_reader.R ",
      "--contract FILE --sha256 SHA --dry-run|--execute\n"))
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L, 3L)],
    c("--contract", "--sha256")) && args[5L] %in% c("--dry-run", "--execute"),
    "explicit external guided requalification purpose required")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  info <- file.info(purpose)
  q(grepl("\\.json$", purpose) && !isTRUE(info$isdir) &&
    info$size <= 1024^2 && info$uid == file.info("/proc/self")$uid &&
    bitwAnd(as.integer(info$mode), 63L) == 0L && gsc_hash_string(args[4L]) &&
    identical(unname(tools::sha256sum(purpose)), args[4L]),
    "private owned external guided purpose digest required")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE)
  gngrr_scope(s)
  root <- normalizePath(getwd(), mustWork = TRUE)
  q(!startsWith(purpose, paste0(root, "/")),
    "guided purpose must remain external to source")
  if (args[5L] == "--dry-run") {
    cat("GLOFAS_NATIVE_GUIDED_REQUALIFICATION_PURPOSE_VALID_NO_PAYLOAD_READS\n")
    return(invisible(gnser_cost(gngrr_stage_e_view(s))))
  }
  gst_runtime(s); gngrr_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds,
    "purpose expiry must cover the complete guided process")
  out <- s$output_root; scratch <- s$metadata_scratch_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    dir.exists(dirname(out)) && identical(normalizePath(dirname(out)), dirname(out)) &&
    !grepl("(^|/)\\.\\.(/|$)", out) &&
    system2("/usr/bin/git", c("check-ignore", "--quiet", "--", shQuote(out))) == 0L,
    "fresh exclusive ignored guided output required")
  q(dir.exists(scratch) && identical(normalizePath(scratch), scratch) &&
    identical(list.files(scratch, all.files = TRUE, no.. = TRUE), basename(tempdir())) &&
    !length(list.files(tempdir(), all.files = TRUE, no.. = TRUE)) &&
    identical(Sys.getenv("TMPDIR"), scratch) &&
    startsWith(normalizePath(tempdir()), paste0(scratch, "/")),
    "empty owned guided metadata scratch required")
  metadata <- c(s$source_files, s[c("collection", "input_manifest",
    "prior_receipt")])
  q(8 * sum(vapply(metadata, function(x) x$size_bytes, numeric(1L))) +
      8 * 1024^2 <= s$read_budget$max_metadata_bytes,
    "conservative guided metadata-read allowance exceeded")
  collection <- jsonlite::read_json(gsc_pin(s$collection, 4 * 1024^2),
    simplifyVector = FALSE)
  manifest <- read.csv(gsc_pin(s$input_manifest, 4 * 1024^2),
    stringsAsFactors = FALSE)
  prior <- jsonlite::read_json(gsc_pin(s$prior_receipt, 4 * 1024^2),
    simplifyVector = FALSE)
  budget <- jsonlite::read_json(gsc_pin(s$acceptance_budget, 4 * 1024^2),
    simplifyVector = FALSE)
  guide_budget <- jsonlite::read_json(gsc_pin(s$guide_budget, 4 * 1024^2),
    simplifyVector = FALSE)
  bound <- gnser_bind_metadata(gngrr_stage_e_view(s), collection, manifest,
    prior, budget)
  gngr_validate_budget(guide_budget, budget)
  cost <- gnser_cost(gngrr_stage_e_view(s))
  q(dir.create(out, mode = "0700"), "exclusive guided output creation failed")
  attempts <- list(); post_attempted <- logical(); finished <- FALSE
  started <- proc.time()[["elapsed"]]; engine <- NULL; result <- NULL
  post_hash <- function() {
    closed <- gnser_post_hash_attempts(attempts, post_attempted)
    attempts <<- closed$attempts; post_attempted <<- closed$post_attempted
    invisible(TRUE)
  }
  on.exit(if (!finished) try({
    post_hash()
    failure <- list(
      schema_version = "glofas_native_guided_requalification_failure_v1",
      status = "FAILED_PARTIAL_GUIDED_REQUALIFICATION_RETAINED_NO_FIT",
      attempted_reads = attempts,
      decision = if (is.null(result)) "INCONCLUSIVE" else result$summary$decision,
      future_truth_read = FALSE, model_fits = 0L, optimizer_iterations = 0L,
      stage_f_authorized = FALSE, production_authorized = FALSE,
      publication_authorized = FALSE)
    gfr_write(gfr_json_raw(failure),
      file.path(out, "FAILED_GUIDED_REQUALIFICATION_RECEIPT.json"),
      out, s$limits$output_bytes)
  }, silent = TRUE), add = TRUE)
  read_one <- function(pin, role) {
    path <- gsc_pin(pin, 8 * 1024^3)
    attempt_pin <- pin; attempt_pin$path <- path
    opened <- gnser_append_attempt(attempts, post_attempted, attempt_pin, role)
    attempts <<- opened$attempts; post_attempted <<- opened$post_attempted
    value <- readRDS(path)
    attempts[[opened$index]]$status <<- "DESERIALIZED"
    value
  }
  design <- read_one(s$design, "truth_free_shared_design")
  object <- read_one(s$median_model, "accepted_median_AL_fit")
  gsc_validate_target(object, bound$producer)
  q(identical(object$task_id, "gft-al-p050") && nrow(design$future_key) == 28L &&
    identical(as.numeric(as.Date(design$future_key$target_date)),
      as.numeric(gsc_dates())) &&
    is.null(design$future_context$latent_data$y_future_oracle),
    "exact truth-free median AL H28 payload required")
  scratch_child <- file.path(scratch, "guided_requalification_contract_metadata")
  q(!file.exists(scratch_child) && dir.create(scratch_child),
    "exclusive guided generated metadata scratch failed")
  engine <- gnr_engine(root, scratch_child, s$metadata_serialization)
  source_sha <- vapply(s$source_files, function(x) x$sha256, character(1L))
  names(source_sha) <- vapply(s$source_files, function(x)
    substring(x$path, nchar(root) + 2L), character(1L))
  available_wall <- s$limits$wall_seconds - (proc.time()[["elapsed"]] - started)
  q(available_wall > 600, "insufficient admitted time after authenticated reads")
  result <- gngr_run(engine, design, object, bound$prior_export, budget,
    guide_budget, wall_seconds = available_wall, source_sha256 = source_sha)
  tables <- c("parity", "derivatives", "derivative_summary", "h2",
    "h2_summary", "h2_pieces", "rhs_invariance", "extension",
    "initial_precision_comparison", "particle_grid", "particle_horizon",
    "particle_quantiles", "precision_summary", "precision_drift",
    "reporting_precision", "reporting_stability", "adjacent_pair_decisions",
    "gradient_assessment")
  outputs <- setNames(lapply(tables, function(name) gfr_csv_raw(result[[name]])),
    paste0(tables, ".csv"))
  outputs[["guided_requalification_summary.json"]] <- gfr_json_raw(result$summary)
  outputs[["native_target_contract.json"]] <- gfr_json_raw(result$native_contract)
  outputs[["native_binding.json"]] <- gfr_json_raw(result$binding)
  q(sum(vapply(outputs, length, integer(1L))) <=
    s$read_budget$max_qualification_output_bytes,
    "compact guided evidence exceeds its output cap")
  for (name in names(outputs)) gfr_write(outputs[[name]], file.path(out, name),
    out, s$limits$output_bytes)
  rm(design, object, collection, manifest, prior, outputs); gc(FALSE)
  post_hash()
  for (pin in metadata) gsc_pin(pin, 4 * 1024^2)
  gngrr_source(s)
  cpu <- sum(proc.time()[c("user.self", "sys.self", "user.child", "sys.child")])
  q(length(attempts) == 2L && all(vapply(attempts,
      function(x) identical(x$status, "DESERIALIZED") &&
        identical(x$post_hash_status, "PASS"), logical(1L))) &&
    expiry > Sys.time() && cpu <= s$limits$cpu_seconds &&
    result$summary$decision %in% unlist(budget$decision_states),
    "guided final lifetime, source, read, or decision gate failed")
  receipt <- list(
    schema_version = "glofas_native_guided_requalification_receipt_v1",
    status = "GUIDED_REQUALIFICATION_COMPLETE_NO_FIT_NO_TRUTH",
    decision = result$summary$decision, purpose_sha256 = args[4L],
    source_commit = s$source_commit, source_tree = s$source_tree,
    producer_identity = gsc_identity(), input_bindings = s[c("design", "median_model")],
    accepted_collection = s$collection, input_manifest = s$input_manifest,
    prior_receipt = s$prior_receipt, acceptance_budget = s$acceptance_budget,
    guide_budget = s$guide_budget, read_cost = cost, attempted_reads = attempts,
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
  gfr_write(gfr_json_raw(receipt),
    file.path(out, "NATIVE_GUIDED_REQUALIFICATION_RECEIPT.json"),
    out, s$limits$output_bytes)
  files <- list.files(out, full.names = TRUE)
  inventory <- data.frame(relative_path = basename(files),
    size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)), stringsAsFactors = FALSE)
  gfr_write(gfr_csv_raw(inventory), file.path(out, "artifact_manifest.csv"),
    out, s$limits$output_bytes)
  finished <- TRUE
  cat("GLOFAS_NATIVE_GUIDED_REQUALIFICATION_COMPLETE_NO_FIT_NO_TRUTH decision=",
    result$summary$decision, "\n", sep = "")
  invisible(receipt)
}

if (sys.nframe() == 0L) gngrr_main()
