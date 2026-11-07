#!/usr/bin/env Rscript
# Purpose-bound p05/p95 fixed-parameter global-path diagnostic. Each run reads
# one truth-free design and one accepted AL fit. No fit, truth, score, retuning,
# promotion, or publication operation exists in this entry point.
source("scripts/glofas_global_path_native_reader.R")

ggtr_sources <- function() unique(c(ggrr_sources(),
  "scripts/glofas_global_path_tail_reader.R",
  "scripts/launch_glofas_global_path_tail.sh",
  "scripts/diagnostics/glofas_global_path_tail_controls.json"))

ggtr_task <- function(task_id) {
  values <- c(`gft-al-p005` = .05, `gft-al-p095` = .95)
  gfr_require(is.character(task_id) && length(task_id) == 1L &&
    task_id %in% names(values), "only the two admitted AL tails are allowed")
  unname(values[[task_id]])
}

ggtr_identity <- function(task_id) {
  identities <- list(
    `gft-al-p005` = list(probability = .05, fit_size_bytes = 138934249,
      fit_sha256 =
        "74c56d0ac8a3aae28202438a6d732e333658185de4ba598a8e6f78c061b5eccf",
      config_size_bytes = 3798,
      config_sha256 =
        "81ec20c1b010996297f1ecde3b5323f7ccae9d54c5b767c793f4433b60fb6509"),
    `gft-al-p095` = list(probability = .95, fit_size_bytes = 139362323,
      fit_sha256 =
        "f36af23fe23aeadbc690eb927b8546c7f0240f66a0e3fdae776ca83a34f35d6b",
      config_size_bytes = 3798,
      config_sha256 =
        "6b30294a257ccb1afdda7b1fdba22dfa0d678b248c35306e86c13173f7e693c2"))
  ggtr_task(task_id)
  identities[[task_id]]
}

ggtr_controls <- function(x, task_id, operation) {
  q <- gfr_require
  q(is.list(x) && x$schema_version %in% c(
      "glofas_global_path_tail_controls_v1",
      "glofas_global_path_tail_controls_v2") &&
    identical(x$posterior_target_sha256,
      "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03") &&
    identical(x$declared_prior_sha256,
      "d7549e8287c6bf37ee1dafbdc70b0fcc5921307484e9c9658a8140a1926ed65b") &&
    identical(x$truth_access, "forbidden") && x$model_fits == 0L &&
    x$parameter_updates == 0L && identical(x$publication_authorized, FALSE),
    "exact truth-free tail controls required")
  q(setequal(names(x$tasks), c("gft-al-p005", "gft-al-p095")),
    "exact two-tail task registry required")
  task <- x$tasks[[task_id]]
  expected <- ggtr_identity(task_id)
  q(is.list(task) && gst_same(task[names(expected)], expected) &&
    identical(as.numeric(task$probability), ggtr_task(task_id)) &&
    gsc_hash_string(task$fit_sha256) && task$fit_size_bytes > 0 &&
    task$config_size_bytes == 3798L && gsc_hash_string(task$config_sha256),
    "tail task identity changed")
  m <- x$measurement
  q(is.list(m) && identical(unlist(m$path_rules), c("retained_mean",
      "retained_mean_minus_quarter_sd", "retained_mean_plus_quarter_sd")) &&
    m$sd_multiplier == .25 && m$maximum_target_evaluations == 12L &&
    m$maximum_wall_seconds == 7200L,
    "fixed tail measurement controls required")
  if (identical(operation, "execute")) {
    q(identical(x$schema_version, "glofas_global_path_tail_controls_v2") &&
      isTRUE(x$execution$authorized) && is.list(task$authentic_measurement) &&
      all(vapply(task$authentic_measurement[c("receipt_sha256", "summary_sha256",
        "target_measurement_sha256")], gsc_hash_string, logical(1L))) &&
      grepl("^[a-f0-9]{40}$", task$authentic_measurement$source_commit) &&
      task$authentic_measurement$target_evaluations == 12L &&
      task$authentic_measurement$maximum_target_seconds > 0 &&
      is.list(task$execution) && isTRUE(task$execution$authorized),
      "tail execution requires a source-bound measurement and frozen budget")
    e <- task$execution
    q(identical(as.numeric(e$probabilities),
        c(.05, .2, .35, .5, .65, .8, .95)) &&
      e$proposal_covariance_inflation == 1 &&
      e$importance$particles == 2048L &&
      e$importance$max_evaluations == 2048L &&
      e$tempering$particles == 256L &&
      e$tempering$max_evaluations == 2304L &&
      e$tempering$max_tempering_steps == 8L &&
      (4 * (e$importance$max_evaluations + e$tempering$max_evaluations) *
        task$authentic_measurement$maximum_target_seconds) < 12000,
      "tail execution exceeds its measured four-hour evaluation envelope")
    ggpr_validate_common(function(x) 0, numeric(28L), diag(28L),
      c(e$importance, seed = 1L))
    ggpr_validate_common(function(x) 0, numeric(28L), diag(28L),
      c(e$tempering, seed = 1L), tempered = TRUE)
  } else q(identical(x$schema_version,
      "glofas_global_path_tail_controls_v1") &&
    identical(x$execution$authorized, FALSE),
    "measurement source must not authorize execution")
  invisible(task)
}

ggtr_cost <- function(s) {
  bytes <- as.numeric(s$design$size_bytes) + as.numeric(s$model$size_bytes)
  r <- s$read_budget
  gfr_require(r$max_RDS_deserializations == 2L &&
    r$max_generated_RDS_deserializations == 0L &&
    r$max_deserialization_bytes == bytes &&
    r$max_payload_hash_bytes == 2 * bytes,
    "exact two-original tail read allowance required")
  list(original_RDS_deserializations = 2L,
    generated_RDS_deserializations = 0L,
    deserialization_bytes = bytes, payload_hash_bytes = 2 * bytes)
}

ggtr_scope <- function(s) {
  q <- gfr_require
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_fixed_parameter_diagnostic",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_authority_replacement")
  fields <- c("schema_version", "purpose", "operation", "task_id",
    "probability", "nonce", "expires_utc", "source_root", "source_commit",
    "source_tree", "source_files", "expected_identity", "collection",
    "input_manifest", "design", "model", "prior_receipt", "acceptance_budget",
    "controls", "measurement_receipt", "read_budget", "limits", "output_root",
    "metadata_scratch_root", "metadata_serialization", yes, no)
  q(is.list(s) && setequal(names(s), fields) && !anyDuplicated(names(s)) &&
    identical(s$schema_version, "glofas_global_path_tail_purpose_v1") &&
    identical(s$purpose,
      "TAIL_AL_FIXED_PARAMETER_GLOBAL_PATH_NO_FIT_NO_TRUTH") &&
    s$operation %in% c("measure", "execute") &&
    identical(as.numeric(s$probability), ggtr_task(s$task_id)) &&
    all(vapply(s[yes], isTRUE, logical(1L))) &&
    all(vapply(s[no], identical, logical(1L), FALSE)),
    "exact tail diagnostic-only purpose required")
  q(is.character(s$nonce) && grepl("^[a-f0-9]{32,64}$", s$nonce) &&
    gst_same(s$expected_identity, gsc_identity()),
    "tail source and producer identities required")
  for (pin in s[c("design", "model")]) gfr_pin_shape(pin, 8 * 1024^3)
  for (pin in s[c("collection", "input_manifest", "prior_receipt",
    "acceptance_budget", "controls")]) gfr_pin_shape(pin, 4 * 1024^2)
  if (identical(s$operation, "measure")) q(is.null(s$measurement_receipt),
    "measurement cannot consume a measurement receipt") else
    gfr_pin_shape(s$measurement_receipt, 4 * 1024^2)
  paths <- vapply(s$source_files, function(pin) {
    gfr_pin_shape(pin, 2 * 1024^2); pin$path
  }, character(1L))
  q(length(paths) == length(ggtr_sources()) && !anyDuplicated(paths) &&
    setequal(paths, file.path(s$source_root, ggtr_sources())),
    "complete tail transitive source closure required")
  limits <- s$limits
  q(is.list(limits) && setequal(names(limits), c("cpu_seconds", "wall_seconds",
      "memory_bytes", "output_bytes", "logical_cpu")) &&
    all(vapply(limits, gfr_scalar_integer, logical(1L))) &&
    limits$cpu_seconds > 0 && limits$cpu_seconds <= 28800L &&
    limits$wall_seconds > 0 && limits$wall_seconds <= 28800L &&
    limits$memory_bytes == 32 * 1024^3 && limits$output_bytes == 64 * 1024^2 &&
    limits$logical_cpu %in% 0:63, "bounded one-core tail allocation required")
  r <- s$read_budget
  q(is.list(r) && setequal(names(r), c("max_payload_hash_bytes",
      "max_deserialization_bytes", "max_RDS_deserializations",
      "max_generated_RDS_deserializations", "max_metadata_bytes",
      "max_diagnostic_output_bytes")) && r$max_metadata_bytes == 64 * 1024^2 &&
    r$max_diagnostic_output_bytes == 48 * 1024^2,
    "exact bounded tail read/output budget required")
  m <- s$metadata_serialization
  q(is.list(m) && setequal(names(m), c("max_files", "max_file_bytes",
      "max_total_bytes")) && m$max_files == 64L &&
    m$max_file_bytes == 4 * 1024^2 && m$max_total_bytes == 32 * 1024^2,
    "bounded tail metadata serialization required")
  ggtr_cost(s)
  invisible(TRUE)
}

ggtr_source <- function(s) {
  q <- gfr_require
  root <- normalizePath(getwd(), mustWork = TRUE)
  git <- function(args) {
    out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
      "core.fsmonitor=false", args), stdout = TRUE)
    q(is.null(attr(out, "status")), "tail source Git check failed")
    unname(out)
  }
  q(identical(root, s$source_root) && identical(git(c("rev-parse", "HEAD")),
      s$source_commit) && identical(git(c("rev-parse", "HEAD^{tree}")),
      s$source_tree) && !length(git(c("status", "--porcelain",
      "--untracked-files=all"))), "exact clean tail source required")
  for (pin in s$source_files) gsc_pin(pin, 2 * 1024^2)
  for (rel in ggtr_sources()) q(identical(
    git(c("hash-object", "--no-filters", "--", rel)),
    git(c("rev-parse", paste0(s$source_commit, ":", rel)))),
    "tail source differs from committed blob")
  invisible(root)
}

ggtr_bind <- function(s, collection, manifest, prior, budget, controls) {
  q <- gfr_require
  gsc_validate_collection(collection, gsc_identity())
  q(is.data.frame(manifest) && !anyDuplicated(manifest$relative_path),
    "frozen input manifest required")
  at <- which(manifest$role == "truth_free_shared_design")
  q(length(at) == 1L && manifest$size_bytes[at] == s$design$size_bytes &&
    identical(manifest$sha256[at], s$design$sha256),
    "tail design differs from truth-free manifest")
  producer <- Filter(function(x) identical(x$task_id, s$task_id),
    collection$producers)
  q(length(producer) == 1L, "one accepted tail producer required")
  artifact <- Filter(function(x) identical(x$relative_path, "fit.rds"),
    producer[[1L]]$artifacts)
  q(length(artifact) == 1L && gst_same(artifact[[1L]][c("path", "size_bytes",
      "sha256")], s$model), "tail fit is not its accepted artifact")
  task <- ggtr_controls(controls, s$task_id, s$operation)
  q(gst_same(s$model, list(path = artifact[[1L]]$path,
      size_bytes = task$fit_size_bytes, sha256 = task$fit_sha256)),
    "tail control and accepted fit differ")
  q(is.list(prior) && prior$status == "ONE_CONFIG_PRIOR_EXPORTED_NO_MODEL_RUN" &&
    prior$future_truth_read == FALSE && prior$model_runs == 0L &&
    identical(prior$export$task_id, s$task_id) &&
    identical(as.numeric(prior$export$probability), s$probability) &&
    identical(prior$export$posterior_target_sha256,
      controls$posterior_target_sha256) &&
    identical(prior$export$declared_prior_sha256,
      controls$declared_prior_sha256) &&
    prior$export$model_run_authorized == FALSE,
    "task-matched config-only prior export required")
  gnse_validate_budget(budget)
  list(producer = producer[[1L]], prior_export = prior$export, task = task)
}

ggtr_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_global_path_tail_reader.R --contract FILE --sha256 SHA --dry-run|--execute\n")
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L, 3L)],
    c("--contract", "--sha256")) && args[5L] %in% c("--dry-run", "--execute"),
    "explicit external tail purpose required")
  purpose_path <- normalizePath(args[2L], mustWork = TRUE)
  info <- file.info(purpose_path)
  q(info$size <= 1024^2 && info$uid == file.info("/proc/self")$uid &&
    bitwAnd(as.integer(info$mode), 63L) == 0L &&
    identical(unname(tools::sha256sum(purpose_path)), args[4L]),
    "private owned tail purpose digest required")
  s <- jsonlite::read_json(purpose_path, simplifyVector = FALSE)
  ggtr_scope(s)
  controls <- jsonlite::read_json(s$controls$path, simplifyVector = FALSE)
  ggtr_controls(controls, s$task_id, s$operation)
  if (args[5L] == "--dry-run") {
    cat("GLOFAS_GLOBAL_PATH_TAIL_PURPOSE_VALID_NO_PAYLOAD_READS\n")
    return(invisible(ggtr_cost(s)))
  }
  gst_runtime(s); root <- ggtr_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds,
    "tail purpose expiry must cover the admitted process")
  out <- s$output_root; scratch <- s$metadata_scratch_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    dir.exists(dirname(out)) && system2("/usr/bin/git", c("check-ignore",
      "--quiet", "--", out)) == 0L, "fresh ignored tail output required")
  q(dir.exists(scratch) && identical(list.files(scratch, all.files = TRUE,
      no.. = TRUE), basename(tempdir())) && !length(list.files(tempdir(),
      all.files = TRUE, no.. = TRUE)) && identical(Sys.getenv("TMPDIR"), scratch),
    "empty owned tail scratch required")
  metadata <- c(s$source_files, s[c("collection", "input_manifest",
    "prior_receipt", "acceptance_budget", "controls")])
  if (!is.null(s$measurement_receipt)) metadata <- c(metadata,
    list(s$measurement_receipt))
  for (pin in metadata) gsc_pin(pin, 4 * 1024^2)
  collection <- jsonlite::read_json(s$collection$path, simplifyVector = FALSE)
  manifest <- read.csv(s$input_manifest$path, stringsAsFactors = FALSE)
  prior <- jsonlite::read_json(s$prior_receipt$path, simplifyVector = FALSE)
  budget <- jsonlite::read_json(s$acceptance_budget$path, simplifyVector = FALSE)
  bound <- ggtr_bind(s, collection, manifest, prior, budget, controls)
  if (identical(s$operation, "execute")) {
    measured <- jsonlite::read_json(s$measurement_receipt$path, simplifyVector = FALSE)
    authentic <- bound$task$authentic_measurement
    q(identical(unname(tools::sha256sum(s$measurement_receipt$path)),
        authentic$receipt_sha256) && measured$task_id == s$task_id &&
      measured$status == "MEASUREMENT_COMPLETE_EXECUTION_NOT_AUTHORIZED" &&
      measured$future_truth_read == FALSE && measured$model_fits == 0L,
      "tail measurement receipt differs from frozen execution control")
  }
  q(dir.create(out, mode = "0700"), "exclusive tail output creation failed")
  attempts <- list(); post_attempted <- logical(); finished <- FALSE
  started <- proc.time()[["elapsed"]]
  post_hash <- function() {
    closed <- gnser_post_hash_attempts(attempts, post_attempted)
    attempts <<- closed$attempts; post_attempted <<- closed$post_attempted
  }
  on.exit(if (!finished) try({
    post_hash()
    gfr_write(gfr_json_raw(list(schema_version =
      "glofas_global_path_tail_failure_v1", status = "FAILED_PARTIAL_NO_FIT_NO_TRUTH",
      task_id = s$task_id, attempted_reads = attempts, future_truth_read = FALSE,
      model_fits = 0L, publication_authorized = FALSE)),
      file.path(out, "FAILED_TAIL_RECEIPT.json"), out, s$limits$output_bytes)
  }, silent = TRUE), add = TRUE)
  read_one <- function(pin, role) {
    opened <- gnser_append_attempt(attempts, post_attempted, pin, role)
    attempts <<- opened$attempts; post_attempted <<- opened$post_attempted
    value <- readRDS(gsc_pin(pin, 8 * 1024^3))
    attempts[[opened$index]]$status <<- "DESERIALIZED"; value
  }
  design <- read_one(s$design, "truth_free_shared_design")
  object <- read_one(s$model, paste0("accepted_", s$task_id, "_fit"))
  gsc_validate_target(object, bound$producer)
  q(identical(object$task_id, s$task_id) && nrow(design$future_key) == 28L &&
    is.null(design$future_context$latent_data$y_future_oracle),
    "exact truth-free accepted tail payload required")
  child <- file.path(scratch, "tail_global_path_contract_metadata")
  q(dir.create(child), "exclusive tail metadata child required")
  engine <- gnr_engine(root, child, s$metadata_serialization)
  built <- ggrr_build(engine, design, object, bound$prior_export, budget,
    s$task_id, s$probability)
  measurement <- ggrr_measure(built, controls)
  result <- NULL
  if (identical(s$operation, "execute"))
    result <- ggrr_execute(built, bound$task$execution,
      if (s$task_id == "gft-al-p005") 2026110705L else 2026110795L)
  gfr_write(gfr_csv_raw(measurement), file.path(out, "target_measurement.csv"),
    out, s$limits$output_bytes)
  if (!is.null(result)) {
    reports <- do.call(rbind, Map(function(x, name) transform(x, contract = name),
      result$reporting, names(result$reporting)))
    gfr_write(gfr_csv_raw(reports), file.path(out, "reporting.csv"), out,
      s$limits$output_bytes)
    outputs <- ggrr_reference_outputs(result)
    q(sum(vapply(outputs, length, integer(1L))) <=
      s$read_budget$max_diagnostic_output_bytes,
      "tail evidence exceeds compact-output cap")
    for (name in names(outputs)) gfr_write(outputs[[name]], file.path(out, name),
      out, s$limits$output_bytes)
  }
  summary <- list(schema_version = "glofas_global_path_tail_summary_v1",
    operation = s$operation, task_id = s$task_id, probability = s$probability,
    status = if (s$operation == "measure")
      "MEASUREMENT_COMPLETE_EXECUTION_NOT_AUTHORIZED" else
      "TAIL_GLOBAL_PATH_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION",
    target_evaluations = nrow(measurement), maximum_target_seconds =
      max(measurement$elapsed_seconds), future_truth_read = FALSE,
    model_fits = 0L, parameter_updates = 0L, scoring = FALSE,
    production_authorized = FALSE, publication_authorized = FALSE)
  gfr_write(gfr_json_raw(summary), file.path(out, "global_path_summary.json"),
    out, s$limits$output_bytes)
  rm(design, object, collection, manifest, prior); gc(FALSE)
  post_hash(); for (pin in metadata) gsc_pin(pin, 4 * 1024^2); ggtr_source(s)
  receipt <- list(schema_version = "glofas_global_path_tail_receipt_v1",
    status = summary$status, task_id = s$task_id, probability = s$probability,
    operation = s$operation, purpose_sha256 = args[4L],
    source_commit = s$source_commit, source_tree = s$source_tree,
    input_bindings = s[c("design", "model")], attempted_reads = attempts,
    original_RDS_deserializations = 2L, generated_RDS_deserializations = 0L,
    future_truth_read = FALSE, model_fits = 0L, parameter_updates = 0L,
    scoring = FALSE, production_authorized = FALSE, publication_authorized = FALSE,
    CPU_seconds = sum(proc.time()[c("user.self", "sys.self", "user.child", "sys.child")]),
    elapsed_seconds = proc.time()[["elapsed"]] - started)
  gfr_write(gfr_json_raw(receipt), file.path(out, "GLOBAL_PATH_TAIL_RECEIPT.json"),
    out, s$limits$output_bytes)
  files <- list.files(out, full.names = TRUE)
  inventory <- data.frame(relative_path = basename(files),
    size_bytes = file.info(files)$size, sha256 = unname(tools::sha256sum(files)),
    stringsAsFactors = FALSE)
  gfr_write(gfr_csv_raw(inventory), file.path(out, "artifact_manifest.csv"),
    out, s$limits$output_bytes)
  finished <- TRUE
  cat("GLOFAS_GLOBAL_PATH_TAIL_COMPLETE task=", s$task_id,
    " operation=", s$operation, " status=", summary$status, "\n", sep = "")
  invisible(receipt)
}

if (sys.nframe() == 0L) ggtr_main()
