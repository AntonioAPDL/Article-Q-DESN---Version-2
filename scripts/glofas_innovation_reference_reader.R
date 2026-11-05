#!/usr/bin/env Rscript
# Separately admitted median-AL fixed-parameter innovation pilot. No historical
# purpose is reused. Two originals may be read; generated arrays are never read.
source("scripts/glofas_al_conditional_reference_reader.R")
source("scripts/diagnostics/glofas_innovation_coordinates.R")
source("scripts/diagnostics/glofas_innovation_streaming.R")
source("scripts/diagnostics/glofas_innovation_sampler.R")

gir_sources <- function() unique(c(gacr_sources(),
  "scripts/diagnostics/glofas_innovation_coordinates.R",
  "scripts/diagnostics/glofas_innovation_streaming.R",
  "scripts/diagnostics/glofas_innovation_sampler.R",
  "scripts/glofas_innovation_reference_reader.R",
  "scripts/run_glofas_innovation_reference.py", "scripts/run_glofas_reference_recovery.py"))
gir_no_link <- function(path) { link <- Sys.readlink(path); is.na(link) || !nzchar(link) }
gir_false <- function() list(reference_qualified = FALSE,
  full_posterior_accuracy_qualified = FALSE, production_launch_authorized = FALSE,
  publication_authorized = FALSE)
gir_control <- function(s) {
  ctl <- s$innovation$sampler
  if (is.list(ctl$seeds)) {
    gfr_require(length(ctl$seeds) == 4L && all(vapply(ctl$seeds,
      function(x) is.numeric(x) && length(x) == 1L, logical(1L))), "four numeric JSON seed scalars required")
    ctl$seeds <- as.numeric(unlist(ctl$seeds, use.names = FALSE))
  }
  ctl
}
gir_cost <- function(s) {
  n <- sum(vapply(s[c("design", "median_model")], function(p) p$size_bytes, numeric(1L)))
  r <- s$read_budget
  gfr_require(r$max_RDS_deserializations == 2L && r$max_generated_RDS_deserializations == 0L &&
    n <= r$max_deserialization_bytes && 2 * n <= r$max_payload_hash_bytes,
    "exact two-original and zero-generated read allowance required")
  list(original_RDS_deserializations = 2L, generated_numeric_array_deserializations = 0L,
    deserialization_bytes = n, payload_hash_bytes = 2 * n)
}
gir_scope <- function(s) {
  q <- gfr_require; gst_unique_objects(s)
  yes <- c("allow_original_reads", "allow_fresh_source_feature_evaluation",
    "allow_metadata_serialization", "allow_fixed_parameter_path_sampling", "allow_raw_draw_export")
  no <- c("allow_generated_numeric_array_read", "allow_proposal_calibration", "allow_saved_callbacks",
    "allow_parameter_updates", "allow_prior_updates", "allow_full_parameter_refit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes", "allow_publication",
    "allow_derived_context_serialization")
  keys <- c("schema_version", "purpose", "mode", "execution_mode", "nonce", "expires_utc",
    "source_root", "source_commit", "source_tree", "source_files", "expected_identity",
    "collection", "input_manifest", "design", "median_model", "prior_replay", "baseline",
    "prior_recovery", "diagnostic_dependencies", "read_budget", "limits", "output_root",
    "metadata_scratch_root", "metadata_serialization", "innovation", "draw_export", yes, no)
  q(is.list(s) && length(s) == length(keys) && setequal(names(s), keys) &&
    identical(s$schema_version, "glofas_innovation_reference_contract_v1") &&
    identical(s$purpose, "MEDIAN_AL_FIXED_PARAMETER_INNOVATION_PCN_PILOT_NO_FULL_REFIT") &&
    identical(s$mode, "computational_pilot") && identical(s$execution_mode, "fork_four") &&
    all(vapply(s[yes], isTRUE, logical(1L))) && all(vapply(s[no], identical, logical(1L), FALSE)),
    "exact new innovation pilot purpose and prohibitions required")
  q(is.character(s$nonce) && length(s$nonce) == 1L && grepl("^[a-f0-9]{32,64}$", s$nonce) &&
    all(vapply(s[c("source_commit", "source_tree")], function(x) is.character(x) && length(x) == 1L &&
      grepl("^[a-f0-9]{40}$", x), logical(1L))) && gst_same(s$expected_identity, gsc_identity()),
    "full innovation and frozen producer identities required")
  for (p in s[c("design", "median_model")]) gfr_pin_shape(p, 8 * 1024^3)
  for (p in s[c("collection", "input_manifest")]) gfr_pin_shape(p, 4 * 1024^2)
  q(s$design$size_bytes == 4014834693 && s$median_model$size_bytes == 137820489 &&
    identical(s$design$sha256, "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3") &&
    identical(s$median_model$sha256, "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881") &&
    identical(basename(s$design$path), "shared_truth_free_design.rds") &&
    identical(basename(s$median_model$path), "fit.rds") &&
    identical(s$input_manifest$sha256, gsc_identity()$input_manifest_sha256),
    "exact frozen truth-free design and median AL originals required")
  for (role in c("baseline", "prior_replay", "prior_recovery"))
    gacr_pin_list(s[[role]], c("receipt", "manifest", "summary", "terminal"))
  dep <- s$diagnostic_dependencies
  q(is.list(dep) && setequal(names(dep), c("library_root", "versions", "sources")) &&
    is.character(dep$library_root) && length(dep$library_root) == 1L && startsWith(dep$library_root, "/"),
    "isolated diagnostic dependency library required")
  for (p in dep[c("versions", "sources")]) gfr_pin_shape(p, 4 * 1024^2)
  b <- s$limits
  keys <- c("cpu_seconds", "wall_seconds", "memory_bytes", "output_bytes", "logical_cpu", "max_workers",
    "child_logical_cpus", "child_cpu_seconds", "aggregate_cpu_seconds", "aggregate_memory_bytes",
    "memory_headroom_bytes", "max_draw_memory_bytes")
  q(is.list(b) && setequal(names(b), keys) &&
    all(vapply(b[setdiff(keys, "child_logical_cpus")], gfr_scalar_integer, logical(1L))) &&
    b$cpu_seconds >= 60 && b$cpu_seconds <= b$wall_seconds && b$wall_seconds <= 3600 &&
    b$memory_bytes == 16 * 1024^3 && b$output_bytes > 0 && b$output_bytes <= 64 * 1024^2 &&
    b$logical_cpu == 26L && b$max_workers == 4L &&
    identical(as.numeric(unlist(b$child_logical_cpus)), as.numeric(26:29)) &&
    b$child_cpu_seconds == b$cpu_seconds && b$aggregate_cpu_seconds >= 5 * b$cpu_seconds &&
    b$aggregate_memory_bytes >= 5 * b$memory_bytes && b$memory_headroom_bytes >= 180 * 1024^3 &&
    b$max_draw_memory_bytes >= 5 * 1000 * 4 * 28 * 8 && b$max_draw_memory_bytes <= 128 * 1024^2,
    "explicit bounded four-child native allocation required")
  r <- s$read_budget
  keys <- c("max_payload_hash_bytes", "max_deserialization_bytes", "max_RDS_deserializations",
    "max_generated_RDS_deserializations", "max_metadata_bytes", "max_innovation_output_bytes")
  q(is.list(r) && setequal(names(r), keys) && all(vapply(r, gfr_scalar_integer, logical(1L))) &&
    all(unlist(r) >= 0) && r$max_RDS_deserializations == 2L && r$max_generated_RDS_deserializations == 0L &&
    r$max_deserialization_bytes <= 24 * 1024^3 && r$max_payload_hash_bytes <= 48 * 1024^3 &&
    r$max_metadata_bytes > 0 && r$max_metadata_bytes <= 64 * 1024^2 &&
    r$max_innovation_output_bytes > 0 && r$max_innovation_output_bytes <= 10 * 1024^2,
    "finite two-original and zero-generated read/compact output caps required")
  m <- s$metadata_serialization; d <- s$draw_export
  q(is.list(m) && setequal(names(m), c("max_files", "max_file_bytes", "max_total_bytes")) &&
    all(vapply(m, gfr_scalar_integer, logical(1L))) && all(unlist(m) > 0) &&
    m$max_files <= 64L && m$max_file_bytes <= 4 * 1024^2 && m$max_total_bytes <= 32 * 1024^2 &&
    is.list(d) && setequal(names(d), c("filename", "role", "max_bytes", "serialization_version", "numeric_array_only")) &&
    identical(d$filename, "innovation_draws.rds") &&
    identical(d$role, "generated_fixed_parameter_conditional_path_draws_not_full_posterior") &&
    gfr_scalar_integer(d$max_bytes) && d$max_bytes >= 1000 * 4 * 28 * 8 + 1024 && d$max_bytes <= 4 * 1024^2 &&
    d$serialization_version == 3L && isTRUE(d$numeric_array_only) &&
    m$max_total_bytes + r$max_innovation_output_bytes + d$max_bytes + 131072 <= b$output_bytes,
    "bounded generated metadata and single numeric draw export required")
  v <- s$innovation
  keys <- c("likelihood_family", "tau", "parameter_rule", "scale_rule", "start_rule", "value_backend",
    "max_total_forward_evaluations", "max_total_inverse_evaluations", "max_total_reference_evaluations",
    "minimum_tail_seconds", "parity_tolerance", "sampler")
  q(is.list(v) && setequal(names(v), keys) && identical(v$likelihood_family, "al") && v$tau == .5 &&
    identical(v$parameter_rule, "retained_theta_mean_fixed_coefficient_covariance_zero") &&
    identical(v$scale_rule, "reciprocal_retained_inverse_scale_means_not_scale_means") &&
    identical(v$start_rule, "retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd") &&
    identical(v$value_backend, "single_pass_retained_two_DESN_innovation") &&
    all(vapply(v[c("max_total_forward_evaluations", "max_total_inverse_evaluations",
      "max_total_reference_evaluations")], gfr_scalar_integer, logical(1L))) &&
    v$max_total_forward_evaluations >= 4 * 1501 + 5 && v$max_total_forward_evaluations <= 7000 &&
    v$max_total_inverse_evaluations >= 5 && v$max_total_inverse_evaluations <= 16 &&
    v$max_total_reference_evaluations >= 5 && v$max_total_reference_evaluations <= 32 &&
    v$minimum_tail_seconds == 120 && v$parity_tolerance == 1e-10,
    "exact median fixed-point causal backend and bounded parity scope required")
  ctl <- gir_control(s); gis_validate_control(ctl)
  q(ctl$warmup == 500L && ctl$samples == 1000L && ctl$max_evaluations == 1501L &&
    ctl$max_wall_seconds == 2400 && ctl$progress_every == 250L &&
    identical(as.numeric(unlist(ctl$seeds)), c(2026110501, 2026110502, 2026110503, 2026110504)) &&
    isTRUE(ctl$adapt_warmup) && ctl$rhat_max == 1.01 && ctl$min_ess >= 400 && ctl$max_quantile_mcse == .001 &&
    ctl$delta_initial == .15 && ctl$delta_min == .0001 && ctl$delta_max == .95 && ctl$target_accept == .234 &&
    ctl$max_wall_seconds + v$minimum_tail_seconds < b$wall_seconds,
    "fixed four-chain 500+1000 pCN efficiency pilot required")
  paths <- vapply(s$source_files, function(p) { gfr_pin_shape(p, 1024^2); p$path }, character(1L))
  q(length(paths) == 22L && !anyDuplicated(paths) &&
    setequal(paths, file.path(s$source_root, gir_sources())), "exact 22-file runtime closure required")
  gir_cost(s); invisible(TRUE)
}

gir_source <- function(s) {
  q <- gfr_require; root <- normalizePath(getwd(), mustWork = TRUE)
  git <- function(a) {
    z <- system2("/usr/bin/git", c("--no-replace-objects", "-c", "core.fsmonitor=false", a), stdout = TRUE)
    q(is.null(attr(z, "status")), "innovation source Git check failed"); unname(z)
  }
  q(identical(root, s$source_root) && identical(git(c("rev-parse", "--show-toplevel")), root) &&
    identical(git(c("rev-parse", "HEAD")), s$source_commit) &&
    identical(git(c("rev-parse", "HEAD^{tree}")), s$source_tree) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))), "exact clean committed innovation source required")
  for (p in s$source_files) gsc_pin(p, 1024^2)
  for (rel in gir_sources()) q(identical(git(c("hash-object", "--no-filters", "--", shQuote(rel))),
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel))))), "runtime source differs from committed blob")
  for (rel in gnr_production_sources()) q(identical(git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel)))),
    git(c("rev-parse", shQuote(paste0(gsc_identity()$source_commit, ":", rel))))), "production blob differs from frozen producer")
  invisible(root)
}

gir_prior_bind <- function(s, p, role) {
  q <- gfr_require; pins <- s[[role]]; r <- p$receipt; t <- p$terminal; m <- p$manifest
  q(role %in% c("baseline", "prior_recovery") && is.data.frame(m) &&
    identical(names(m), c("relative_path", "size_bytes", "sha256")) &&
    !anyDuplicated(m$relative_path) && all(basename(m$relative_path) == m$relative_path),
    "bounded closed prior manifest required")
  for (pin in pins[c("receipt", "summary")]) {
    at <- which(m$relative_path == basename(pin$path))
    q(length(at) == 1L && m$size_bytes[at] == pin$size_bytes && identical(m$sha256[at], pin$sha256) &&
      identical(dirname(pin$path), dirname(pins$manifest$path)), "prior receipt/summary not manifest-bound")
  }
  q(identical(t$purpose_sha256, r$purpose_sha256) && identical(t$source_commit, r$source_commit) &&
    identical(t$source_tree, r$source_tree) && t$native_exit_code == 0 && isTRUE(t$owner_terminated) &&
    isTRUE(t$worker_terminated) && identical(t$timed_out, FALSE) && isTRUE(t$output_manifest_verified) &&
    identical(t$output_manifest_sha256, pins$manifest$sha256) && t$original_RDS_deserializations == 2L &&
    t$saved_callback_calls == 0L && t$full_parameter_refits == 0L && identical(t$future_truth_read, FALSE) &&
    gst_same(r$producer_identity, gsc_identity()) && gst_same(r$input_bindings, s[c("design", "median_model")]) &&
    gst_same(r$accepted_collection, s$collection) && gst_same(r$input_manifest, s$input_manifest) &&
    r$original_RDS_deserializations == 2L && r$saved_callback_calls == 0L && r$full_parameter_refits == 0L &&
    identical(r$future_truth_read, FALSE) && identical(r$reference_qualified, FALSE) &&
    identical(r$full_posterior_accuracy_qualified, FALSE) && identical(r$publication_authorized, FALSE) &&
    identical(p$summary$status, r$status), "closed unqualified prior/input identity required")
  expected <- if (role == "baseline") "glofas_al_conditional_reference" else "glofas_reference_recovery"
  q(identical(r$schema_version, paste0(expected, "_receipt_v1")) &&
    identical(t$schema_version, paste0(expected, "_native_terminal_v1")), "prior role schema differs")
  if (role == "baseline") q(identical(r$status, "INCONCLUSIVE_CONDITIONAL_REFERENCE") &&
    identical(r$mode, "sample") && r$conditional_reference_chains_attempted == 4L,
    "historical baseline must remain inconclusive") else {
    q(identical(r$status, "PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION") &&
      identical(r$mode, "computational_pilot") && r$conditional_reference_chains_attempted == 8L &&
      isTRUE(t$computational_closure) && identical(t$statistical_qualification, FALSE) &&
      identical(r$production_launch_authorized, FALSE) && r$generated_numeric_array_deserializations == 1L &&
      gst_same(r$baseline, s$baseline) && gst_same(r$prior_replay, s$prior_replay),
      "historical recovery must remain a closed unqualified two-arm pilot")
  }
  q(length(r$attempted_reads) == if (role == "baseline") 2L else 3L,
    "prior complete read ledger required")
  for (a in r$attempted_reads) q(identical(a$status, "DESERIALIZED") &&
    identical(a$pre_read_sha256, a$sha256) && identical(a$post_read_sha256, a$sha256),
    "prior before/after read ledger did not close")
  invisible(TRUE)
}

gir_timing <- function(seconds, remaining) {
  q <- gfr_require
  q(is.numeric(seconds) && length(seconds) == 4L && all(is.finite(seconds)) && all(seconds > 0) &&
    is.numeric(remaining) && length(remaining) == 1L && is.finite(remaining), "four measured forward times required")
  projected <- max(seconds) * 2 * 1501
  q(projected <= 2400 && remaining > 2520, "measured forward timing exceeds bounded fork allowance")
  list(measured_forward_max_seconds = max(seconds), safety_factor = 2,
    projected_chain_seconds = projected, max_chain_evaluations = 1501L,
    sampler_wall_seconds = 2400, minimum_tail_seconds = 120, remaining_seconds_at_fork = remaining)
}
gir_progress <- function(out, chain) {
  force(out); force(chain)
  function(p) {
    q <- gfr_require
    keys <- c("schema_version", "chain_id", "completed_iterations", "retained_iterations", "callback_evaluations",
      "elapsed_seconds", "delta", "accepted_warmup", "accepted_retained", "fully_completed")
    q(is.list(p) && setequal(names(p), keys) &&
      identical(p$schema_version, "glofas_innovation_progress_v1") && p$chain_id == chain &&
      p$completed_iterations >= 0 && p$completed_iterations <= 1500 &&
      p$retained_iterations == max(0, p$completed_iterations - 500) &&
      p$callback_evaluations == p$completed_iterations + 1L && p$callback_evaluations <= 1501 &&
      p$accepted_warmup >= 0 && p$accepted_warmup <= min(500L, p$completed_iterations) &&
      p$accepted_retained >= 0 && p$accepted_retained <= p$retained_iterations &&
      is.logical(p$fully_completed) && length(p$fully_completed) == 1L &&
      identical(p$fully_completed, p$completed_iterations == 1500L) &&
      all(is.finite(unlist(p[setdiff(keys, c("schema_version", "fully_completed"))]))),
      "bounded declared-chain innovation progress required")
    raw <- gfr_json_raw(p); q(length(raw) <= 4096, "progress metadata byte cap exceeded")
    path <- file.path(out, sprintf("progress_chain_%d.json", chain)); tmp <- paste0(path, ".new")
    q(!file.exists(tmp) && gir_no_link(tmp) && gir_no_link(path), "unexpected progress temporary/link")
    con <- file(tmp, "wb"); tryCatch(writeBin(raw, con), finally = close(con))
    q(file.rename(tmp, path), "atomic progress replacement failed"); invisible(NULL)
  }
}
gir_write_draws <- function(draws, s) {
  q <- gfr_require; d <- s$draw_export
  q(typeof(draws) == "double" && !is.object(draws) && identical(dim(draws), c(1000L, 4L, 28L)) &&
    all(is.finite(draws) | is.na(draws)) && !any(is.nan(draws)) &&
    all(names(attributes(draws)) %in% c("dim", "dimnames")) && as.numeric(object.size(draws)) <= d$max_bytes,
    "bounded four-chain numeric path array required")
  path <- file.path(s$output_root, "innovation_draws.rds")
  q(!file.exists(path) && gir_no_link(path), "fresh generated path-array output required")
  used <- sum(file.info(list.files(s$output_root, full.names = TRUE))$size)
  q(used + d$max_bytes + 65536 <= s$limits$output_bytes, "combined export byte cap exceeded")
  base::saveRDS(draws, path, version = 3L, compress = FALSE)
  size <- as.numeric(file.info(path)$size); q(size <= d$max_bytes, "generated export exceeds cap")
  list(path = path, relative_path = basename(path), size_bytes = size,
    sha256 = unname(tools::sha256sum(path)), role = d$role, dimensions = dim(draws),
    finite_values = sum(is.finite(draws)), missing_values = sum(is.na(draws)),
    generated_array_only = TRUE, full_parameter_posterior_draws = FALSE)
}

gir_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_innovation_reference_reader.R --contract FILE --sha256 SHA --dry-run|--execute\n")
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L, 3L)], c("--contract", "--sha256")) &&
    args[5L] %in% c("--dry-run", "--execute"), "explicit separate innovation admission required")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  info <- file.info(purpose)
  q(grepl("\\.json$", purpose) && !isTRUE(info$isdir) && gir_no_link(purpose) &&
    info$size <= 1024^2 && info$uid == file.info("/proc/self")$uid &&
    bitwAnd(as.integer(info$mode), 63L) == 0L && gsc_hash_string(args[4L]) &&
    identical(unname(tools::sha256sum(purpose)), args[4L]), "bounded private owned external purpose digest required")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE); gir_scope(s)
  root <- normalizePath(getwd(), mustWork = TRUE)
  q(!startsWith(purpose, paste0(root, "/")), "purpose must remain external")
  if (args[5L] == "--dry-run") {
    cat("GLOFAS_INNOVATION_PURPOSE_VALID_NO_PAYLOAD_READS\n"); return(invisible(gir_cost(s)))
  }
  gst_runtime(s); gir_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds, "purpose must cover entire native lifetime")
  available <- gacr_memory_admission(s)
  out <- s$output_root; scratch <- s$metadata_scratch_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) && gir_no_link(out) &&
    dir.exists(dirname(out)) && identical(normalizePath(dirname(out)), dirname(out)) &&
    !grepl("(^|/)\\.\\.(/|$)", out) &&
    system2("/usr/bin/git", c("check-ignore", "--quiet", "--", shQuote(out))) == 0L,
    "fresh exclusive ignored innovation output required")
  q(dir.exists(scratch) && gir_no_link(scratch) && identical(normalizePath(scratch), scratch) &&
    identical(list.files(scratch, all.files = TRUE, no.. = TRUE), basename(tempdir())) &&
    !length(list.files(tempdir(), all.files = TRUE, no.. = TRUE)) && identical(Sys.getenv("TMPDIR"), scratch) &&
    startsWith(normalizePath(tempdir()), paste0(scratch, "/")), "owned native empty metadata scratch required")
  q(dir.create(out, mode = "0700"), "exclusive output creation failed")
  attempts <- list(); post_attempted <- logical(); finished <- FALSE; engine <- NULL
  worker_proofs <- list(); stage <- "PREREQUISITE_METADATA"; failure_message <- NULL
  started <- proc.time()[["elapsed"]]
  post_hash <- function() {
    errors <- character()
    for (i in seq_along(attempts)) if (!isTRUE(post_attempted[i])) {
      post_attempted[i] <<- TRUE
      if (is.null(attempts[[i]]$pre_read_sha256)) next
      tryCatch({
        gsc_pin(attempts[[i]][c("path", "size_bytes", "sha256")], 8 * 1024^3)
        attempts[[i]]$post_read_sha256 <<- attempts[[i]]$sha256
        attempts[[i]]$post_hash_status <<- "PASS"
      }, error = function(e) {
        attempts[[i]]$post_hash_status <<- "FAIL_NO_AUTOMATIC_REHASH"
        errors <<- c(errors, conditionMessage(e))
      })
    }
    q(!length(errors), paste(errors, collapse = "; ")); invisible(TRUE)
  }
  on.exit(if (!finished) {
    hash_failure <- tryCatch({ post_hash(); NULL }, error = function(e) conditionMessage(e))
    reads <- sum(vapply(attempts, function(a) a$status %in%
      c("DESERIALIZATION_ATTEMPTED", "DESERIALIZED"), logical(1L)))
    try(gfr_write(gfr_json_raw(c(list(schema_version = "glofas_innovation_reference_failure_v1",
      status = "FAILED_OR_PARTIAL_PILOT_NOT_PROMOTABLE", failure_stage = stage, error = failure_message,
      post_hash_error = hash_failure, attempted_reads = attempts, post_hash_attempted = post_attempted,
      original_RDS_deserializations_attempted = reads, generated_numeric_array_deserializations = 0L,
      worker_proofs = worker_proofs, saved_callback_calls = 0L, full_parameter_refits = 0L,
      future_truth_read = FALSE), gir_false())), file.path(out, "FAILED_INNOVATION_RECEIPT.json"),
      out, s$limits$output_bytes), silent = TRUE)
  }, add = TRUE)
  withCallingHandlers({
    meta <- c(s$source_files, s[c("collection", "input_manifest")], s$prior_replay, s$baseline,
      s$prior_recovery, s$diagnostic_dependencies[c("versions", "sources")])
    q(8 * sum(vapply(meta, function(p) p$size_bytes, numeric(1L))) + 8 * 1024^2 <=
      s$read_budget$max_metadata_bytes, "metadata allowance exceeded before original reads")
    for (p in meta) gsc_pin(p, 4 * 1024^2)
    load_prior <- function(p) list(receipt = jsonlite::read_json(p$receipt$path, simplifyVector = FALSE),
      summary = jsonlite::read_json(p$summary$path, simplifyVector = FALSE),
      manifest = read.csv(p$manifest$path, stringsAsFactors = FALSE),
      terminal = jsonlite::read_json(p$terminal$path, simplifyVector = FALSE))
    replay <- load_prior(s$prior_replay); baseline <- load_prior(s$baseline); recovery <- load_prior(s$prior_recovery)
    gacr_prior_bind(s, replay$receipt, replay$manifest, replay$summary, replay$terminal)
    gir_prior_bind(s, baseline, "baseline"); gir_prior_bind(s, recovery, "prior_recovery")
    q(identical(normalizePath(Sys.getenv("R_LIBS_USER"), mustWork = TRUE),
      normalizePath(s$diagnostic_dependencies$library_root, mustWork = TRUE)), "private diagnostic library required")
    gacr_library(s$diagnostic_dependencies$library_root,
      read.csv(s$diagnostic_dependencies$versions$path, stringsAsFactors = FALSE))
    collection <- jsonlite::read_json(s$collection$path, simplifyVector = FALSE)
    manifest <- read.csv(s$input_manifest$path, stringsAsFactors = FALSE)
    producer <- gnrr_bind(s, collection, manifest)
    read_one <- function(pin, role) {
      i <- length(attempts) + 1L; q(i <= 2L && role %in% c("design", "median_model"), "original read allowance exhausted")
      attempts[[i]] <<- c(list(role = role), pin, list(status = "PRE_READ_HASH_ATTEMPTED"))
      post_attempted[i] <<- FALSE
      path <- gsc_pin(pin, 8 * 1024^3)
      attempts[[i]]$pre_read_sha256 <<- pin$sha256
      attempts[[i]]$status <<- "DESERIALIZATION_ATTEMPTED"
      value <- base::readRDS(path)
      attempts[[i]]$status <<- "DESERIALIZED"; value
    }
    stage <- "TWO_ORIGINAL_READS"
    design <- read_one(s$design, "design"); history <- gfh_reference_history(design, 30L)
    object <- read_one(s$median_model, "median_model"); gsc_validate_target(object, producer)
    core <- object$fit; v <- core$variational_state
    q(identical(object$task_id, "gft-al-p050") && identical(core$likelihood_family, "al") &&
      identical(core$method, "vb") && identical(colnames(core$draws$theta), history$columns) &&
      isTRUE(core$vb_diagnostics$future_y_working_likelihood_used) &&
      identical(core$vb_diagnostics$future_gaussian_prior_used, FALSE), "fixed median AL source/order required")
    theta <- as.numeric(gnr_number(v$theta_mean, length(history$columns)))
    m <- as.numeric(gnr_number(v$y_future_mean, 28L)); V <- as.matrix(gnr_number(v$y_future_cov))
    q(identical(dim(V), c(28L, 28L)) && max(abs(V - t(V))) <= 1e-12 &&
      !is.null(tryCatch(chol(V), error = function(e) NULL)), "retained SPD covariance is required for starts only")
    inverse <- v$sigma$inv_mean
    q(all(c("Y", "G") %in% names(inverse)) && all(is.finite(inverse)) && all(inverse > 0), "inverse scale means required")
    scales <- c(Y = 1 / as.numeric(inverse[["Y"]]), G = 1 / as.numeric(inverse[["G"]]))
    known <- if (is.null(design$discrepancy_baseline_future)) rep(0, 28L) else as.numeric(design$discrepancy_baseline_future)
    gnr_number(known, 28L)
    child <- file.path(scratch, "contract_metadata")
    q(!file.exists(child) && dir.create(child, mode = "0700"), "fresh metadata child required")
    engine <- gnr_engine(root, child, s$metadata_serialization); context <- gnr_context(design, engine)
    identities <- gnr_identities(context); identities$input_scalers <- identities$initial_states <- NULL
    q(gacr_same_json(identities, replay$summary$actual_context_identity), "fresh numeric context differs from authentic replay")
    point <- list(parameter_id = gnr_hash(list(theta = theta, sigma_fixed = scales, known_baseline = known)),
      feature_id = identities$context_sha256, sigma_y = scales[["Y"]], sigma_g = scales[["G"]],
      coefficient_covariance_zero = TRUE, theta_mean_sha256 = gnr_hash(theta), scale_rule = s$innovation$scale_rule,
      source_scale_mean_not_used = TRUE, source_model = s$median_model, likelihood_family = "al", p = .5)
    q(gacr_same_json(point, baseline$summary$fixed_point) && gacr_same_json(point, recovery$summary$fixed_point),
      "innovation conditional point differs from closed baseline/recovery")
    stage <- "FRESH_STREAMING_PARITY_AND_TIMING"
    cap <- sum(unlist(s$innovation[c("max_total_forward_evaluations", "max_total_inverse_evaluations",
      "max_total_reference_evaluations")]))
    backend <- giv_state_factory(engine, context, theta, known, scales, cap)
    counts <- c(forward = 0L, inverse = 0L, reference = 0L)
    evaluate <- function(role, x) {
      q(counts[[role]] < s$innovation[[paste0("max_total_", role, "_evaluations")]], "per-role innovation budget exhausted")
      counts[[role]] <<- counts[[role]] + 1L
      backend[[role]](x)
    }
    ref_m <- evaluate("reference", m)
    starts <- gacr_start_paths(m, V, ref_m$reference_location)
    bases <- matrix(NA_real_, 28L, 4L); parity <- list(); forward_times <- numeric(4L)
    check_path <- function(path, label, chain = NULL) {
      inv <- evaluate("inverse", path)
      tick <- proc.time()[["elapsed"]]; fast <- evaluate("forward", inv$base)
      seconds <- proc.time()[["elapsed"]] - tick
      oracle <- if (is.null(chain)) ref_m else evaluate("reference", path)
      errors <- c(path_roundtrip = max(abs(fast$path - path)),
        base_roundtrip = max(abs(inv$base - oracle$base)),
        reference_location = max(abs(fast$reference_location - oracle$reference_location)),
        ensemble_location = max(abs(fast$ensemble_location - oracle$ensemble_location)),
        gnr_compare(fast$design, oracle$design, FALSE),
        log_reference = abs(fast$log_reference - oracle$log_reference),
        log_member = abs(fast$log_likelihood - oracle$log_likelihood),
        log_target = abs(fast$log_target - oracle$log_target),
        Jacobian_identity = abs(fast$log_path_target + fast$log_jacobian - fast$log_target))
      q(all(is.finite(errors)) && all(errors <= s$innovation$parity_tolerance), "fresh streaming/full-production parity failed")
      parity[[length(parity) + 1L]] <<- data.frame(path = label, quantity = names(errors),
        error = as.numeric(errors), tolerance = s$innovation$parity_tolerance)
      if (!is.null(chain)) { bases[, chain] <<- inv$base; forward_times[chain] <<- seconds }
      invisible(NULL)
    }
    check_path(m, "retained_m")
    for (chain in 1:4) check_path(starts[, chain], paste0("overdispersed_chain", chain), chain)
    q(engine$audit$factory_calls == 0L && engine$audit$forbidden_calls == 0L &&
      backend$diagnostics()$forward_whole_path_callbacks == 0L, "unexpected derivative or forbidden callback")
    # No RDS object, issued member, latent design, saved closure or prior is
    # exported. Raw posterior path draws are the only permitted numeric export.
    rm(design, object, core, v, history, collection, manifest, inverse, ref_m, m, V, starts); gc(FALSE)
    available_fork <- gacr_memory_admission(s)
    timing <- gir_timing(forward_times, s$limits$wall_seconds - (proc.time()[["elapsed"]] - started))
    ctl <- gir_control(s); stage <- "FOUR_CHAIN_PCN_PILOT"
    parts <- gacr_fork_dispatch(function(chain) {
      proof <- gacr_process()
      q(all(proof$native_address_space_limits <= s$limits$memory_bytes), "child address-space cap differs")
      before <- counts
      result <- gis_sample_chain(function(z) evaluate("forward", z), bases[, chain], ctl, chain,
        progress = gir_progress(out, chain))
      result$evaluation_delta <- counts - before
      result
    }, as.numeric(unlist(s$limits$child_logical_cpus)), s$limits$child_cpu_seconds)
    worker_proofs <- lapply(seq_along(parts), function(i) c(parts[[i]]$proof,
      list(logical_cpu = as.integer(25L + i), CPU_seconds = parts[[i]]$CPU_seconds)))
    q(all(vapply(parts, function(p) is.list(p$result) && !is.null(p$result$chain_id), logical(1L))),
      "every declared native chain must return its complete receipt")
    target <- list(horizon = 28L, contract = list(p = .5))
    result <- gis_combine_chains(lapply(parts, function(p) p$result), target, ctl)
    export <- gir_write_draws(result$draws, s)
    q(all(vapply(parts, function(p) isTRUE(p$result$fully_completed), logical(1L))) &&
      export$finite_values == 112000 && export$missing_values == 0L, "incomplete pilot retained but not computationally closed")
    delta <- Reduce(`+`, lapply(parts, function(p) p$result$evaluation_delta))
    totals <- counts + delta
    q(all(totals <= unlist(s$innovation[paste0("max_total_", names(totals), "_evaluations")])) &&
      sum(vapply(parts, function(p) p$result$callback_evaluations, integer(1L))) == delta[["forward"]] &&
      engine$audit$forbidden_calls == 0L, "aggregate proposal/evaluation accounting failed")
    result$draws <- NULL
    # Neither the final base coordinates nor proposal RNG state belong in the
    # compact diagnostic metadata. Retain counts/acceptance and all four chains.
    for (i in seq_along(result$chains)) result$chains[[i]]$final_base <- NULL
    status <- "PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION"
    summary <- c(list(schema_version = "glofas_innovation_reference_summary_v1", status = status,
      mode = s$mode, source_commit = s$source_commit, source_tree = s$source_tree,
      purpose_sha256 = args[4L], fixed_point = point, baseline_status = baseline$receipt$status,
      prior_recovery_status = recovery$receipt$status, diagnostic_thresholds_passed = isTRUE(result$diagnostic_thresholds_passed),
      result = result, generated_draw_export = export, worker_proofs = worker_proofs,
      timing_admission = timing, forward_evaluations = unname(totals[["forward"]]),
      inverse_evaluations = unname(totals[["inverse"]]), reference_evaluations = unname(totals[["reference"]]),
      pre_read_MemAvailable_bytes = available, pre_fork_MemAvailable_bytes = available_fork,
      streaming_parent = backend$diagnostics(),
      interpretation = "Four fixed-parameter innovation chains are an efficiency pilot; diagnostic thresholds do not confer reference or production qualification."), gir_false())
    raw <- gfr_json_raw(summary)
    q(length(raw) <= s$read_budget$max_innovation_output_bytes, "compact innovation summary allowance exceeded")
    gfr_write(raw, file.path(out, "innovation_summary.json"), out, s$limits$output_bytes)
    gfr_write(gfr_csv_raw(do.call(rbind, parity)), file.path(out, "innovation_parity.csv"), out, s$limits$output_bytes)
    stage <- "POST_READ_HASH_AND_SOURCE_CLOSURE"
    post_hash(); for (p in meta) gsc_pin(p, 4 * 1024^2); gir_source(s)
    q(identical(unname(tools::sha256sum(purpose)), args[4L]), "purpose changed during native run")
    cpu <- sum(proc.time()[c("user.self", "sys.self", "user.child", "sys.child")])
    q(cpu <= s$limits$aggregate_cpu_seconds && expiry > Sys.time() && length(attempts) == 2L,
      "aggregate native CPU/lifetime/read closure failed")
    receipt <- c(list(schema_version = "glofas_innovation_reference_receipt_v1", status = status,
      mode = s$mode, purpose_sha256 = args[4L], source_commit = s$source_commit, source_tree = s$source_tree,
      producer_identity = gsc_identity(), input_bindings = s[c("design", "median_model")],
      accepted_collection = s$collection, input_manifest = s$input_manifest,
      prior_replay = s$prior_replay, baseline = s$baseline, prior_recovery = s$prior_recovery,
      fixed_point = point, read_cost = gir_cost(s), original_RDS_deserializations = 2L,
      generated_numeric_array_deserializations = 0L, attempted_reads = attempts,
      conditional_reference_chains_attempted = 4L, full_parameter_refits = 0L,
      saved_callback_calls = 0L, future_truth_read = FALSE,
      forward_evaluations = unname(totals[["forward"]]), inverse_evaluations = unname(totals[["inverse"]]),
      reference_evaluations = unname(totals[["reference"]]), timing_admission = timing,
      metadata_serializations = engine$audit$metadata, worker_proofs = worker_proofs,
      generated_draw_export = export, aggregate_cpu_seconds = cpu,
      diagnostic_thresholds_passed = isTRUE(result$diagnostic_thresholds_passed),
      independent_supervisor_closure_still_required = TRUE), gir_false())
    gfr_write(gfr_json_raw(receipt), file.path(out, "INNOVATION_REFERENCE_RECEIPT.json"), out, s$limits$output_bytes)
    files <- list.files(out, full.names = TRUE)
    inventory <- data.frame(relative_path = basename(files), size_bytes = file.info(files)$size,
      sha256 = unname(tools::sha256sum(files)))
    gfr_write(gfr_csv_raw(inventory), file.path(out, "artifact_manifest.csv"), out, s$limits$output_bytes)
    finished <- TRUE
    cat("GLOFAS_INNOVATION_REFERENCE_PILOT_CLOSED_NO_PRODUCTION_QUALIFICATION\n")
    invisible(receipt)
  }, error = function(e) { failure_message <<- conditionMessage(e) })
}
if (sys.nframe() == 0L) gir_main()
