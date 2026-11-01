#!/usr/bin/env Rscript
# No discovery of science caches and no launch by default. Actual reconstruction
# is admitted only by an external, source-bound authorization AND a live central
# claim. This program never fits a model or rewrites a retained source artifact.

iqf_args <- commandArgs(trailingOnly = TRUE)
iqf_arg <- function(name, default = NULL) {
  at <- match(paste0("--", name), iqf_args)
  if (is.na(at)) return(default)
  if (at == length(iqf_args)) stop(paste("Missing argument:", name), call. = FALSE)
  iqf_args[at + 1L]
}
iqf_script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
iqf_repo <- normalizePath(file.path(dirname(iqf_script), "../.."), mustWork = TRUE)
source(file.path(iqf_repo, "application/R/integrated_quantile_forecast.R"))
source(file.path(iqf_repo, "scripts/integrated_quantile_blocks.R"))
iqf_mode <- iqf_arg("mode", "preflight")
app_iqf_require(iqf_mode %in% c("preflight", "run"), "Mode must be preflight or run.")
iqf_request_path <- iqf_arg("request")
if (is.null(iqf_request_path)) {
  app_iqf_require(iqf_mode == "preflight", "Production mode requires a frozen request.")
  cat("NO_LAUNCH: integrated forecast implementation is preparation-only by default.\n")
  quit(save = "no", status = 0L)
}
app_iqf_require(requireNamespace("jsonlite", quietly = TRUE), "jsonlite is required.")
iqf_request <- jsonlite::fromJSON(iqf_request_path, simplifyVector = FALSE)
app_iqf_require(identical(iqf_request$schema_version, "integrated_quantile_forecast_request_v1"),
  "Unrecognized worker request schema.")
iqf_required <- c("task_id", "routing_id", "rng_namespace", "host", "source_commit", "source_tree",
  "source_manifest_sha256", "posterior_target_sha256", "input_manifest_sha256",
  "task_manifest_sha256", "expected_output_keys_sha256", "bundle_root", "bundle_manifest_path", "bundle_spec_path")
app_iqf_require(all(iqf_required %in% names(iqf_request)) &&
  all(vapply(iqf_request[iqf_required], function(x) is.character(x) && length(x) == 1L && nzchar(x), logical(1L))),
  "Immutable worker identity is incomplete.")

if (iqf_mode == "run") {
  # Do not deserialize source objects, create outputs, or run forecast paths
  # until the authoritative central ledger has authenticated the full envelope.
  iqf_auth_path <- iqf_arg("authorization")
  iqf_ticket <- iqf_arg("claim-ticket")
  iqf_auth_sha <- iqf_arg("authorization-sha256", iqf_request$authorization_sha256)
  iqf_ticket_sha <- iqf_arg("claim-ticket-sha256")
  iqf_ledger <- iqf_arg("ledger")
  iqf_python <- iqf_arg("python", "/usr/bin/python3.11")
  iqf_source_manifest <- iqf_arg("source-manifest", file.path(iqf_repo,
    "docs/reproducibility/integrated_forecast_transition_sources_20261031.csv"))
  app_iqf_require(all(vapply(list(iqf_auth_path, iqf_ticket, iqf_auth_sha, iqf_ticket_sha, iqf_ledger),
    function(x) is.character(x) && length(x) == 1L && nzchar(x), logical(1L))),
    "Production requires external authorization, its digest, and a central ledger-backed claim ticket.")
  app_iqf_require(identical(app_iqf_hash(iqf_auth_path, TRUE), iqf_auth_sha), "External authorization changed.")
  iqf_auth <- jsonlite::fromJSON(iqf_auth_path, simplifyVector = FALSE)
  app_iqf_require(identical(iqf_auth$schema_version, "forecast_transition_authorization_v1") &&
    isTRUE(iqf_auth$allow_launch), "NO_LAUNCH: external source-bound allow_launch=true is required.")
  app_iqf_require(!startsWith(normalizePath(iqf_auth_path), paste0(iqf_repo, "/")),
    "Launch authorization must be external, not a repository payload.")
  identity <- c("source_commit", "source_tree", "source_manifest_sha256", "posterior_target_sha256",
    "input_manifest_sha256", "task_manifest_sha256")
  app_iqf_require(all(vapply(identity, function(nm) identical(iqf_auth[[nm]], iqf_request[[nm]]), logical(1L))),
    "Authorization is not bound to the exact source, posterior and inputs.")
  app_iqf_require(identical(app_iqf_hash(iqf_source_manifest, TRUE), iqf_request$source_manifest_sha256),
    "Local source-manifest digest differs from authorization.")
  control <- file.path(iqf_repo, "application/scripts/forecast_transition_control.py")
  app_iqf_require(file.exists(control), "Central launch controller is unavailable.")
  command <- c(control, if (iqf_request$host == "muscat") "verify-claim" else "verify-claim-remote",
    "--ledger", iqf_ledger, "--ticket", iqf_ticket,
    "--ticket-sha256", iqf_ticket_sha, "--request", iqf_request_path,
    "--authorization", iqf_auth_path, "--authorization-sha256", iqf_auth_sha,
    "--source-root", iqf_repo, "--source-manifest", iqf_source_manifest)
  actual_host <- strsplit(tolower(Sys.info()[["nodename"]]), ".", fixed = TRUE)[[1L]][1L]
  app_iqf_require(identical(actual_host, iqf_request$host) ||
    (iqf_request$host == "hummingbird" && nzchar(Sys.getenv("SLURM_JOB_ID")) &&
      nzchar(Sys.getenv("SLURM_JOB_NODELIST")) && !actual_host %in% c("muscat", "jerez", "hummingbird")),
    "Actual worker host/compute allocation differs from the routed claim.")
  iqf_verification <- suppressWarnings(system2(iqf_python,
    vapply(command, shQuote, character(1L)), stdout = TRUE, stderr = TRUE))
  app_iqf_require(is.null(attr(iqf_verification, "status")) || attr(iqf_verification, "status") == 0L,
    "Central claim/source/qualification verification failed; no work was run.")
  iqf_claim <- jsonlite::fromJSON(paste(iqf_verification, collapse = "\n"), simplifyVector = FALSE)
  app_iqf_require(identical(iqf_claim$schema_version, "forecast_transition_claim_verification_v1") &&
    isTRUE(iqf_claim$verified) && identical(iqf_claim$task_id, iqf_request$task_id) &&
    identical(iqf_claim$routing_id, iqf_request$routing_id) && identical(iqf_claim$host, iqf_request$host),
    "Central verifier did not confirm this exact routed task.")
}

iqf_bundle <- app_iqf_prepare_bundle(iqf_request$bundle_root, iqf_request$bundle_manifest_path,
  iqf_request$bundle_spec_path, iqf_request$input_manifest_sha256)
for (nm in c("posterior_target_sha256", "source_commit", "source_tree"))
  app_iqf_require(identical(iqf_bundle$spec$identity[[nm]], iqf_request[[nm]]),
    paste("Bundle/request identity differs:", nm))
if (iqf_mode == "preflight") {
  cat("PREFLIGHT_PASS: authenticated retained evidence; zero trajectories generated, zero outputs written.\n")
  quit(save = "no", status = 0L)
}

# Native helpers are loaded only after production admission. Sourcing is not a
# model fit and the bootstrap's default cache paths are never used by this CLI.
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
source(file.path(iqf_repo, "application/scripts/_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
iqf_p <- iqf_bundle$payloads; iqf_s <- iqf_bundle$spec
iqf_native_environment <- if (iqf_s$adapter == "single_qdesn_fit_native_v1" &&
    !is.null(iqf_s$native_kernel_paths)) app_iqf_load_native_kernels(
      iqf_request$bundle_root, iqf_bundle$manifest, unlist(iqf_s$native_kernel_paths),
      iqf_s$native_version) else NULL
iqf_adapter <- switch(iqf_s$adapter,
  mq_desn_native_v1 = app_iqf_desn_adapter(iqf_p$design, iqf_p$posterior, iqf_p$origins,
    unlist(iqf_s$tau), "mq_grid", iqf_s$coupling, iqf_request$rng_namespace),
  single_qdesn_fit_native_v1 = app_iqf_single_desn_adapter(iqf_p$object, iqf_p$posterior,
    iqf_p$origins, iqf_s$family, unlist(iqf_s$tau), iqf_request$rng_namespace,
    iqf_s$native_version, iqf_s$native_function_sha256, iqf_native_environment),
  state_space_conditional_v1 = app_iqf_state_space_adapter(iqf_p$model, iqf_p$posterior,
    iqf_p$origins, iqf_request$rng_namespace))
iqf_draws <- unlist(iqf_request$draw_ids, use.names = FALSE)
iqf_origins <- unlist(iqf_request$origin_ids, use.names = FALSE)
app_iqf_require(length(iqf_draws) > 0L && !anyDuplicated(iqf_draws) &&
  length(iqf_origins) > 0L && !anyDuplicated(iqf_origins), "Empty/duplicate worker task keys.")
iqf_budget <- iqf_claim$resource_budget
iqf_requested_budget <- iqf_request$resource_budget
app_iqf_require(is.list(iqf_budget) && all(c("memory_bytes", "output_bytes", "cpus", "wall_seconds") %in% names(iqf_budget)) &&
  all(vapply(iqf_budget[c("memory_bytes", "output_bytes", "cpus", "wall_seconds")],
    function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0, logical(1L))) &&
  iqf_requested_budget$max_memory_mb * 1024^2 == iqf_budget$memory_bytes &&
  iqf_requested_budget$max_output_bytes == iqf_budget$output_bytes &&
  iqf_requested_budget$max_threads == iqf_budget$cpus &&
  iqf_requested_budget$max_wall_seconds == iqf_budget$wall_seconds && iqf_budget$cpus == 1L,
  "Worker resource bounds differ from the verified central reservation; use one inner/BLAS thread.")
setTimeLimit(elapsed = iqf_budget$wall_seconds, transient = FALSE)
iqf_mc <- iqf_request$integration_accuracy
app_iqf_require(is.list(iqf_mc) && all(vapply(iqf_mc[c("max_split_absolute", "max_split_relative")],
  function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0, logical(1L))) &&
  all(c("max_split_absolute", "max_split_relative") %in% names(iqf_mc)),
  "Worker needs predeclared numerical-integration accuracy gates.")
app_iqf_require(iqf_mc$method %in% c("dkw_response_cdf", "split_stream_diagnostic"),
  "An explicit integration-accuracy method is required.")
if (iqf_mc$method == "dkw_response_cdf") app_iqf_require(
  all(c("alpha_per_shard", "max_quantile_abs_error", "max_quantile_rel_error") %in% names(iqf_mc)) &&
  all(vapply(iqf_mc[c("alpha_per_shard", "max_quantile_abs_error", "max_quantile_rel_error")],
    function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0, logical(1L))) &&
  iqf_mc$alpha_per_shard < 1, "DKW confidence/accuracy contract is incomplete.")
iqf_retain_cdf <- isTRUE(iqf_request$retain_cdf_components)
iqf_expected_keys <- unlist(lapply(iqf_draws, function(draw) paste0("draw:", draw, "|origin:", iqf_origins)),
  use.names = FALSE)
app_iqf_require(!anyDuplicated(iqf_expected_keys) &&
  setequal(iqf_expected_keys, unlist(iqf_request$expected_output_keys, use.names = FALSE)),
  "Frozen expected outer-draw/origin keys differ from the worker geometry.")
iqf_estimate <- sum(vapply(iqf_origins, function(o) as.double(iqf_adapter$origins[[o]]$H), numeric(1L))) *
  length(iqf_draws) * as.integer(iqf_request$inner_paths) *
  (2048 + 8 * length(iqf_request$probabilities))
if (iqf_retain_cdf) app_iqf_require(iqf_estimate <= iqf_budget$output_bytes,
  "Requested retained CDF components exceed the admitted total output budget.")
app_iqf_verify_output_root(iqf_request$output_root, iqf_claim$output_root)
dir.create(iqf_request$output_root, recursive = TRUE, showWarnings = FALSE)
app_iqf_require(dir.exists(iqf_request$output_root), "Could not create admitted output directory.")
iqf_outputs <- list(); iqf_n <- 0L; iqf_written_bytes <- 0
iqf_block_limit <- iqf_request$members_per_file
if (is.null(iqf_block_limit)) iqf_block_limit <- if (iqf_retain_cdf) 1L else 1000L
app_iqf_require(is.numeric(iqf_block_limit) && length(iqf_block_limit) == 1L &&
  is.finite(iqf_block_limit) && iqf_block_limit == as.integer(iqf_block_limit) &&
  iqf_block_limit >= 1L && iqf_block_limit <= 1000L && (!iqf_retain_cdf || iqf_block_limit == 1L),
  "Storage blocks require 1–1000 complete members; retained inner CDFs require one member per file.")
iqf_buffer <- list(); iqf_buffer_bytes <- 0; iqf_block_count <- 0L
iqf_flush_block <- function() {
  if (!length(iqf_buffer)) return(invisible(NULL))
  block <- app_iqf_pack_block(iqf_buffer)
  bytes <- serialize(block, NULL, version = 3L)
  app_iqf_require(iqf_written_bytes + length(bytes) + 65536 <= iqf_budget$output_bytes,
    "Next storage block exceeds the admitted cumulative output budget; partial evidence is retained.")
  iqf_block_count <<- iqf_block_count + 1L
  name <- sprintf("block_%06d_%s.rds", iqf_block_count, app_iqf_hash(block$member_keys))
  destination <- file.path(iqf_request$output_root, name)
  app_iqf_require(!file.exists(destination), "Refusing to overwrite a forecast storage block.")
  writeBin(bytes, destination)
  hash <- app_iqf_hash(destination, TRUE)
  for (member in seq_along(iqf_buffer)) {
    result <- iqf_buffer[[member]]
    iqf_n <<- iqf_n + 1L
    iqf_outputs[[iqf_n]] <<- data.frame(relative_path = name, member_index = member,
      storage_schema = block$schema_version, size_bytes = length(bytes), sha256 = hash,
      draw_id = result$draw_id, origin_id = result$origin_id,
      integration_status = result$integration_status,
      artifact_key = app_iqf_member_key(result), stringsAsFactors = FALSE)
  }
  iqf_written_bytes <<- iqf_written_bytes + length(bytes)
  iqf_buffer <<- list(); iqf_buffer_bytes <<- 0
  invisible(gc(FALSE))
}
iqf_identity_names <- c("task_id", "source_commit", "source_tree", "source_manifest_sha256",
  "posterior_target_sha256", "input_manifest_sha256", "task_manifest_sha256", "rng_namespace")
for (iqf_draw in iqf_draws) for (iqf_origin in iqf_origins) {
  iqf_result <- app_iqf_run_task(iqf_adapter, iqf_draw, iqf_origin,
    as.integer(iqf_request$inner_paths), as.numeric(unlist(iqf_request$probabilities)),
    iqf_s$model_id, as.numeric(iqf_request$quantile_tolerance),
    diagnose_integration = TRUE, max_kernel_bytes = iqf_budget$memory_bytes / 2,
    mc_confidence_alpha = if (iqf_mc$method == "dkw_response_cdf") iqf_mc$alpha_per_shard else NULL)
  iqf_split_pass <- all(iqf_result$integration_diagnostic$split_stream_absolute_difference <= iqf_mc$max_split_absolute |
    iqf_result$integration_diagnostic$split_stream_relative_difference <= iqf_mc$max_split_relative)
  iqf_result$integration_status <- "REVIEW_SPLIT_STREAM_DIAGNOSTIC_ONLY_NOT_A_CONFIDENCE_BOUND"
  if (iqf_mc$method == "dkw_response_cdf") {
    bound <- iqf_result$integration_dkw$max_estimate_error_bound
    estimate <- abs(iqf_result$quantiles$quantile)
    dkw_pass <- all(is.finite(bound) & (bound <= iqf_mc$max_quantile_abs_error |
      bound / pmax(1, estimate) <= iqf_mc$max_quantile_rel_error))
    iqf_result$integration_status <- if (iqf_split_pass && dkw_pass)
      "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE" else "REVIEW_INNER_INTEGRATION_RESOLUTION"
  }
  iqf_result$integration_accuracy_contract <- iqf_mc
  iqf_result$integration_accuracy_contract_sha256 <- app_iqf_hash(iqf_mc)
  # Store numerical discrepancy honestly; a failed accuracy check is retained
  # and blocks later acceptance/promotion. It is never a seed-screening trigger.
  if (!iqf_retain_cdf) iqf_result$cdf_components <- NULL
  iqf_result$posterior_predictive_status <- if (iqf_retain_cdf)
    "CDF_COMPONENTS_RETAINED_POOLED_QUANTILE_NOT_YET_COMPUTED" else
    "NOT_MATERIALIZED_SEPARATE_BOUNDED_CDF_WORKFLOW_REQUIRED"
  iqf_result$identity <- iqf_request[iqf_identity_names]
  iqf_result$identity$outer_conditioning <- iqf_adapter$outer_conditioning
  iqf_result$task_id <- iqf_request$task_id
  iqf_result$routing_id <- iqf_request$routing_id
  if (length(iqf_buffer) && !app_iqf_same_geometry(iqf_buffer[[1L]], iqf_result)) iqf_flush_block()
  iqf_buffer_bytes <- iqf_buffer_bytes + as.numeric(object.size(iqf_result))
  app_iqf_require(iqf_buffer_bytes <= iqf_budget$memory_bytes / 4,
    "Output block buffer exceeds its admitted memory allowance; lower members_per_file prospectively.")
  iqf_buffer[[length(iqf_buffer) + 1L]] <- iqf_result
  rm(iqf_result)
  if (length(iqf_buffer) >= iqf_block_limit) iqf_flush_block()
}
iqf_flush_block()
iqf_output_table <- do.call(rbind, iqf_outputs)
iqf_csv <- file.path(iqf_request$output_root, "output_manifest.csv")
app_iqf_write_output_index(iqf_output_table, iqf_csv, iqf_budget$output_bytes, iqf_written_bytes)
app_iqf_require(sum(iqf_output_table$size_bytes[!duplicated(iqf_output_table$relative_path)]) +
    file.info(iqf_csv)$size <= iqf_budget$output_bytes,
  "Final artifact inventory exceeds the admitted output budget; evidence is retained but not accepted.")
iqf_acceptance <- app_iqf_block_envelope(iqf_request, iqf_claim, iqf_output_table, iqf_request$output_root)
# The controller sidecar is outside the exact artifact set; no hash self-cycle.
jsonlite::write_json(iqf_acceptance, paste0(iqf_request$output_root, ".output_manifest.json"),
  auto_unbox = TRUE, pretty = TRUE, digits = 17L, null = "null")
app_iqf_require(iqf_acceptance$numerical_gates_pass,
  "RESULT_RETAINED_NOT_ACCEPTED: integration accuracy needs review under the frozen contract.")
cat("ADMITTED_TASK_COMPLETE: source-bound per-draw/origin shards written; promotion is a separate gate.\n")
