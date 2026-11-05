# Generated contract/metadata fixtures only. No original or generated RDS read.
source("scripts/glofas_innovation_reference_reader.R")

# This template deliberately declares unopened fixture paths and fake identities.
# It is not a launchable purpose. Native purposes replace every source/metadata
# pin from authenticated receipts and bind a clean commit under the controller.
gir_generated_contract <- function(root = getwd()) {
  pin <- function(path, bytes = 1, sha = strrep("a", 64L))
    list(path = path, size_bytes = bytes, sha256 = sha)
  metadata <- function(role) setNames(lapply(c("receipt", "manifest", "summary", "terminal"),
    function(x) pin(paste0("/generated/", role, "/", x, if (x == "manifest") ".csv" else ".json"))),
    c("receipt", "manifest", "summary", "terminal"))
  yes <- c("allow_original_reads", "allow_fresh_source_feature_evaluation", "allow_metadata_serialization",
    "allow_fixed_parameter_path_sampling", "allow_raw_draw_export")
  no <- c("allow_generated_numeric_array_read", "allow_proposal_calibration", "allow_saved_callbacks",
    "allow_parameter_updates", "allow_prior_updates", "allow_full_parameter_refit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes", "allow_publication", "allow_derived_context_serialization")
  s <- list(schema_version = "glofas_innovation_reference_contract_v1",
    purpose = "MEDIAN_AL_FIXED_PARAMETER_INNOVATION_PCN_PILOT_NO_FULL_REFIT",
    mode = "computational_pilot", execution_mode = "fork_four", nonce = strrep("b", 32L),
    expires_utc = "2099-01-01T00:00:00Z", source_root = root,
    source_commit = strrep("c", 40L), source_tree = strrep("d", 40L),
    source_files = lapply(gir_sources(), function(p) pin(file.path(root, p))),
    expected_identity = gsc_identity(), collection = pin("/generated/accepted_producers.json"),
    input_manifest = pin("/generated/input_manifest.csv", sha = gsc_identity()$input_manifest_sha256),
    design = pin("/generated/shared_truth_free_design.rds", 4014834693,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model = pin("/generated/fit.rds", 137820489,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    prior_replay = metadata("replay"), baseline = metadata("baseline"), prior_recovery = metadata("recovery"),
    diagnostic_dependencies = list(library_root = "/generated/private_library",
      versions = pin("/generated/versions.csv"), sources = pin("/generated/sources.csv")),
    read_budget = list(max_payload_hash_bytes = 48 * 1024^3, max_deserialization_bytes = 24 * 1024^3,
      max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
      max_metadata_bytes = 64 * 1024^2, max_innovation_output_bytes = 10 * 1024^2),
    limits = list(cpu_seconds = 3600L, wall_seconds = 3600L, memory_bytes = 16 * 1024^3,
      output_bytes = 64 * 1024^2, logical_cpu = 26L, max_workers = 4L,
      child_logical_cpus = as.list(26:29), child_cpu_seconds = 3600L,
      aggregate_cpu_seconds = 18000L, aggregate_memory_bytes = 80 * 1024^3,
      memory_headroom_bytes = 180 * 1024^3, max_draw_memory_bytes = 128 * 1024^2),
    output_root = file.path(root, "local_trackers/generated_not_admitted"),
    metadata_scratch_root = "/generated/scratch",
    metadata_serialization = list(max_files = 64L, max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2),
    innovation = list(likelihood_family = "al", tau = .5,
      parameter_rule = "retained_theta_mean_fixed_coefficient_covariance_zero",
      scale_rule = "reciprocal_retained_inverse_scale_means_not_scale_means",
      start_rule = "retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd",
      value_backend = "single_pass_retained_two_DESN_innovation",
      max_total_forward_evaluations = 7000L, max_total_inverse_evaluations = 16L,
      max_total_reference_evaluations = 32L, minimum_tail_seconds = 120L, parity_tolerance = 1e-10,
      sampler = list(warmup = 500L, samples = 1000L, max_evaluations = 1501L,
        max_wall_seconds = 2400L, delta_initial = .15, delta_min = .0001, delta_max = .95,
        target_accept = .234, adapt_warmup = TRUE,
        seeds = as.list(c(2026110501, 2026110502, 2026110503, 2026110504)), progress_every = 250L,
        rhat_max = 1.01, min_ess = 400L, max_quantile_mcse = .001)),
    draw_export = list(filename = "innovation_draws.rds",
      role = "generated_fixed_parameter_conditional_path_draws_not_full_posterior",
      max_bytes = 4 * 1024^2, serialization_version = 3L, numeric_array_only = TRUE))
  for (k in yes) s[[k]] <- TRUE
  for (k in no) s[[k]] <- FALSE
  s
}

local({
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE) }
  reject <- function(expr, pattern = NULL) {
    error <- tryCatch({ force(expr); NULL }, error = function(e) e)
    ok(inherits(error, "error"))
    if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  s <- gir_generated_contract()
  gir_scope(s); ok(length(gir_sources()) == 22L)
  ok(length(gacr_sources()) == 16L && length(setdiff(gir_sources(), gacr_sources())) == 6L)
  ok(!"scripts/glofas_reference_recovery_reader.R" %in% gir_sources())
  cost <- gir_cost(s)
  ok(cost$original_RDS_deserializations == 2L && cost$generated_numeric_array_deserializations == 0L &&
    cost$deserialization_bytes == 4152655182 && cost$payload_hash_bytes == 8305310364)
  ok(is.numeric(gir_control(s)$seeds) && length(gir_control(s)$seeds) == 4L)
  decoded <- jsonlite::fromJSON(jsonlite::toJSON(s, auto_unbox = TRUE, digits = 17), simplifyVector = FALSE)
  gir_scope(decoded); ok(TRUE)
  for (key in names(s)[startsWith(names(s), "allow_")]) {
    bad <- s; bad[[key]] <- !bad[[key]]; reject(gir_scope(bad), "purpose and prohibitions")
  }
  for (key in c("schema_version", "purpose", "execution_mode", "mode")) {
    bad <- s; bad[[key]] <- "wrong"; reject(gir_scope(bad), "purpose and prohibitions")
  }
  bad <- s; bad$calibration_draws <- s$design; reject(gir_scope(bad), "purpose and prohibitions")
  bad <- s; bad$read_budget$max_generated_RDS_deserializations <- 1L; reject(gir_scope(bad), "zero-generated")
  bad <- s; bad$read_budget$max_deserialization_bytes <- 1L; reject(gir_scope(bad), "read allowance")
  bad <- s; bad$design$size_bytes <- 4014834692; reject(gir_scope(bad), "exact frozen")
  bad <- s; bad$median_model$sha256 <- strrep("a", 64L); reject(gir_scope(bad), "exact frozen")
  bad <- s; bad$source_files <- bad$source_files[-1L]; reject(gir_scope(bad), "22-file")
  bad <- s; bad$source_files[[1L]] <- bad$source_files[[2L]]; reject(gir_scope(bad), "22-file")
  bad <- s; bad$limits$child_logical_cpus <- as.list(20:23); reject(gir_scope(bad), "four-child")
  bad <- s; bad$limits$max_workers <- 8L; reject(gir_scope(bad), "four-child")
  bad <- s; bad$limits$memory_headroom_bytes <- 179 * 1024^3; reject(gir_scope(bad), "four-child")
  bad <- s; bad$innovation$tau <- .05; reject(gir_scope(bad), "median fixed-point")
  bad <- s; bad$innovation$likelihood_family <- "exal"; reject(gir_scope(bad), "median fixed-point")
  bad <- s; bad$innovation$max_total_forward_evaluations <- 6004L; reject(gir_scope(bad), "bounded parity")
  bad <- s; bad$innovation$max_total_inverse_evaluations <- 17L; reject(gir_scope(bad), "bounded parity")
  bad <- s; bad$innovation$sampler$warmup <- 1000L; reject(gir_scope(bad))
  bad <- s; bad$innovation$sampler$seeds[[4L]] <- bad$innovation$sampler$seeds[[1L]]; reject(gir_scope(bad))
  bad <- s; bad$innovation$sampler$adapt_warmup <- FALSE; reject(gir_scope(bad), "efficiency pilot")
  bad <- s; bad$innovation$sampler$max_quantile_mcse <- .005; reject(gir_scope(bad), "efficiency pilot")
  bad <- s; bad$draw_export$filename <- "old_draws.rds"; reject(gir_scope(bad), "single numeric")
  bad <- s; bad$metadata_serialization$max_total_bytes <- 64 * 1024^2; reject(gir_scope(bad), "bounded generated")
  t <- gir_timing(c(.1, .2, .3, .4), 3000)
  ok(t$projected_chain_seconds == .4 * 2 * 1501 && t$safety_factor == 2L)
  reject(gir_timing(rep(.8, 4L), 3000), "timing exceeds")
  reject(gir_timing(rep(.1, 4L), 2520), "timing exceeds")
  reject(gir_timing(rep(.1, 3L), 3000), "four measured")
  reject(gir_timing(c(.1, .1, NA_real_, .1), 3000), "four measured")
  ok(all(vapply(gir_false(), identical, logical(1L), FALSE)))
  scratch <- tempfile("gir_generated_"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  progress <- gir_progress(scratch, 1L)
  p <- list(schema_version = "glofas_innovation_progress_v1", chain_id = 1L,
    completed_iterations = 250L, retained_iterations = 0L, callback_evaluations = 251L,
    elapsed_seconds = 1, delta = .15, accepted_warmup = 50L, accepted_retained = 0L,
    fully_completed = FALSE)
  progress(p); ok(file.exists(file.path(scratch, "progress_chain_1.json")))
  p$completed_iterations <- 1500L; p$retained_iterations <- 1000L
  p$callback_evaluations <- 1501L; p$fully_completed <- TRUE
  progress(p)
  readback <- jsonlite::read_json(file.path(scratch, "progress_chain_1.json"), simplifyVector = FALSE)
  ok(readback$fully_completed && readback$retained_iterations == 1000L)
  badp <- p; badp$chain_id <- 2L; reject(progress(badp), "declared-chain")
  badp <- p; badp$fully_completed <- FALSE; reject(progress(badp), "declared-chain")
  badp <- p; badp$retained_iterations <- 999L; reject(progress(badp), "declared-chain")
  badp <- p; badp$callback_evaluations <- 1499L; reject(progress(badp), "declared-chain")
  s$output_root <- scratch
  draws <- array(0, c(1000L, 4L, 28L)); exported <- gir_write_draws(draws, s)
  ok(exported$finite_values == 112000L && exported$missing_values == 0L &&
    exported$generated_array_only && !exported$full_parameter_posterior_draws)
  reject(gir_write_draws(draws, s), "fresh generated")
  reject(gir_write_draws(matrix(0, 4L, 28L), s), "numeric path array")
  # Dry run validates only the private JSON declaration; no source/payload path
  # below /generated is required to exist or is opened by this test.
  purpose <- tempfile("gir_contract_", fileext = ".json")
  on.exit(unlink(purpose), add = TRUE)
  jsonlite::write_json(s, purpose, auto_unbox = TRUE, digits = 17); Sys.chmod(purpose, "0600")
  gir_main(c("--contract", purpose, "--sha256", unname(tools::sha256sum(purpose)), "--dry-run")); ok(TRUE)
  reject(gir_main(c("--execute")), "explicit separate")
  Sys.chmod(purpose, "0644")
  reject(gir_main(c("--contract", purpose, "--sha256", unname(tools::sha256sum(purpose)), "--dry-run")), "private owned")
  cat(sprintf("PASS: GloFAS innovation reader (%d generated contract checks; zero RDS reads)\n", checks))
})
