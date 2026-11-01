#!/usr/bin/env Rscript
# Scoring is deliberately separated from forecast construction. Oracle/future
# outcomes are read only here, after the immutable forecast tasks are accepted.
app_iqf_score_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("IQF_SCORE:", message), call. = FALSE)
}
app_iqf_score_key_hash <- function(keys) digest::digest(jsonlite::toJSON(
  as.list(sort(as.character(keys), method = "radix")), auto_unbox = TRUE, pretty = FALSE),
  algo = "sha256", serialize = FALSE)
app_iqf_score_accuracy <- function(shard) {
  require <- app_iqf_score_require
  contract <- shard$integration_accuracy_contract
  dkw <- shard$integration_dkw; split <- shard$integration_diagnostic
  require(is.list(contract) && identical(contract$method, "dkw_response_cdf") &&
    identical(app_iqf_hash(contract), shard$integration_accuracy_contract_sha256),
    "numerical-accuracy contract is absent or changed")
  require(is.data.frame(dkw) && is.data.frame(split) && nrow(dkw) == nrow(shard$quantiles) &&
    nrow(split) == nrow(dkw) && all(c("lower","upper","max_estimate_error_bound",
      "empirical_cdf_epsilon","alpha_per_draw_origin") %in% names(dkw)), "numerical receipt is incomplete")
  for (receipt in list(dkw, split)) require(
    all(c("horizon", "probability") %in% names(receipt)) &&
      identical(as.numeric(receipt$horizon), as.numeric(shard$quantiles$horizon)) &&
      identical(as.numeric(receipt$probability), as.numeric(shard$quantiles$probability)),
    "numerical receipts must match each ordered horizon/probability key")
  require(length(shard$integration_resolution) == 1L &&
    is.finite(shard$integration_resolution) && shard$integration_resolution >= 2 &&
    shard$integration_resolution == as.integer(shard$integration_resolution),
    "integration resolution must be an explicit positive integer")
  require(all(vapply(contract[c("alpha_per_shard", "max_split_absolute", "max_split_relative",
      "max_quantile_abs_error", "max_quantile_rel_error")], function(z)
        is.numeric(z) && length(z) == 1L && is.finite(z) && z > 0, logical(1L))) &&
    contract$alpha_per_shard < 1, "numerical-accuracy limits are not explicit and finite")
  expected <- sqrt(log(2 * length(unique(shard$quantiles$horizon)) / contract$alpha_per_shard) /
    (2 * shard$integration_resolution))
  require(is.finite(expected) && all(abs(dkw$empirical_cdf_epsilon - expected) < 1e-12) &&
    all(dkw$alpha_per_draw_origin == contract$alpha_per_shard) &&
    all(is.finite(dkw$lower)) && all(is.finite(dkw$upper)) && all(dkw$lower <= dkw$upper),
    "DKW reference bounds are unresolved or inconsistent")
  error <- pmax(abs(shard$quantiles$quantile - dkw$lower), abs(dkw$upper - shard$quantiles$quantile))
  require(all(abs(error - dkw$max_estimate_error_bound) < 1e-10) &&
    all(error <= contract$max_quantile_abs_error |
      error / pmax(1, abs(shard$quantiles$quantile)) <= contract$max_quantile_rel_error) &&
    all(split$split_stream_absolute_difference <= contract$max_split_absolute |
      split$split_stream_relative_difference <= contract$max_split_relative),
    "predeclared integration precision was not achieved")
  invisible(TRUE)
}
app_iqf_score_write <- function(value, path, format, budget, used) {
  # Serialize before creating a file: an artifact cannot consume an unbounded
  # amount of disk and only then fail its cumulative byte check.
  if (format == "csv") {
    lines <- character()
    connection <- textConnection("lines", "w", local = TRUE)
    tryCatch(utils::write.csv(value, connection, row.names = FALSE),
      finally = close(connection))
    bytes <- charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  } else {
    app_iqf_score_require(format == "json", "unknown output serialization")
    bytes <- charToRaw(paste0(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE), "\n"))
  }
  app_iqf_score_require(length(budget) == 1L && is.finite(budget) && budget > 0 &&
    is.finite(used) && used >= 0 && used + length(bytes) <= budget,
    "serialized scoring output exceeds the admitted cumulative byte budget")
  app_iqf_score_require(!file.exists(path), "scoring output cannot overwrite an existing artifact")
  writeBin(bytes, path)
  used + length(bytes)
}
app_iqf_score_oracle <- function(oracle, mode) {
  require <- app_iqf_score_require
  require(mode %in% c("oracle_acrps", "realized_check_loss"), "unknown score functional")
  map <- oracle$forecast_map
  require(is.data.frame(map) && all(c("origin_id", "horizon") %in% names(map)),
    "oracle/evaluation rows need explicit origin-horizon keys")
  keys <- paste(map$origin_id, map$horizon, sep = "|")
  require(nrow(map) > 0L && !anyDuplicated(keys) &&
    length(oracle$observed_y) == nrow(map) && all(is.finite(oracle$observed_y)),
    "scoring response coverage is incomplete or nonfinite")
  if (mode == "oracle_acrps") {
    y <- as.matrix(oracle$sorted_response); prefix <- as.matrix(oracle$prefix_response)
    require(ncol(y) == nrow(map) && nrow(y) > 0L && identical(dim(y), dim(prefix)) &&
      all(is.finite(c(y, prefix))) && all(vapply(seq_len(ncol(y)), function(i)
        all(diff(y[, i]) >= 0) && max(abs(cumsum(y[, i]) - prefix[, i])) < 1e-8, logical(1L))),
      "authenticated DGP sorted/prefix bank is incomplete or inconsistent")
    require(is.data.frame(oracle$diagnostics) && nrow(oracle$diagnostics) > 0L &&
      all(oracle$diagnostics$status == "pass"),
      "frozen oracle numerical checks did not pass")
  }
  invisible(keys)
}
app_iqf_score_native_oracle <- function(native) {
  app_iqf_score_require(all(c("origin_index", "horizon") %in% names(native$forecast_map)),
    "native oracle map cannot be reconstructed from aggregate scores")
  out <- native
  out$forecast_map$origin_id <- as.character(native$forecast_map$origin_index)
  out
}
app_iqf_score_expected_check <- function(q, p, sorted_y, prefix) {
  n <- length(sorted_y); below <- findInterval(q, sorted_y)
  lower <- if (below > 0L) prefix[below] else 0
  ((1 - p) * (below * q - lower) + p *
    ((prefix[n] - lower) - (n - below) * q)) / n
}
app_iqf_score_shard <- function(shard, oracle, probabilities, weights,
                                mode = "oracle_acrps") {
  require <- app_iqf_score_require
  require(identical(shard$schema_version, "integrated_quantile_forecast_shard_v1") &&
    identical(shard$integration_status, "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE"),
    "forecast functional or predeclared numerical accuracy gate did not pass")
  app_iqf_score_accuracy(shard)
  x <- shard$quantiles; p <- as.numeric(probabilities); weights <- as.numeric(weights)
  require(length(p) > 0L && all(diff(p) > 0) && min(p) > 0 && max(p) < 1 &&
    length(weights) == length(p) && all(is.finite(weights)) && all(weights > 0), "score grid is invalid")
  expected_weights <- if (length(p) == 1L) 1 else c(diff(p)[1L] / 2,
    if (length(p) > 2L) (p[3:length(p)] - p[1:(length(p)-2L)]) / 2 else numeric(),
    tail(diff(p), 1L) / 2)
  require(max(abs(weights - expected_weights)) < 1e-12,
    "weights must be the unchanged unnormalized trapezoidal weights (one for a single level)")
  require(all(c("model_id", "draw_id", "origin_id", "horizon", "probability", "quantile", "functional") %in% names(x)) &&
    all(is.finite(x$quantile)) && all(x$functional == "parameter_conditional_integrated_quantile"),
    "quantile draws must have the integrated, not mean-feature or single-path, definition")
  conditioning <- shard$outer_conditioning
  require(is.character(conditioning) && length(conditioning) == 1L &&
    conditioning %in% c("parameters_and_observed_origin_reservoir_state",
      "parameters_only_integrate_filtered_origin_state", "parameters_and_joint_retained_origin_state") &&
    identical(shard$identity$outer_conditioning, conditioning) &&
    "outer_conditioning" %in% names(x) && all(x$outer_conditioning == conditioning),
    "outer conditioning must be explicit and identical in the shard, rows and identity")
  require(length(unique(x$model_id)) == 1L && length(unique(x$draw_id)) == 1L &&
    length(unique(x$origin_id)) == 1L &&
    !anyDuplicated(paste(x$horizon, x$probability, sep = "|")), "forecast shard key membership is ambiguous")
  evaluation_keys <- app_iqf_score_oracle(oracle, mode)
  require(all(c("source_manifest_sha256", "posterior_target_sha256") %in% names(shard$identity)),
    "score provenance is incomplete")
  out <- lapply(sort(unique(x$horizon)), function(h) {
    rows <- x[x$horizon == h, ]; rows <- rows[order(rows$probability), ]
    require(identical(as.numeric(rows$probability), p), "missing or changed probability-level coverage")
    at <- match(paste(rows$origin_id[1L], h, sep = "|"), evaluation_keys)
    require(!is.na(at), "forecast/evaluation origin-horizon mismatch")
    observed <- oracle$observed_y[at]
    loss <- (observed - rows$quantile) * (p - (observed < rows$quantile))
    factor <- if (length(p) == 1L) 1 else 2
    primary <- if (mode == "oracle_acrps") vapply(seq_along(p), function(k)
      app_iqf_score_expected_check(rows$quantile[k], p[k], oracle$sorted_response[, at],
        oracle$prefix_response[, at]), numeric(1L)) else loss
    data.frame(model_id = rows$model_id[1L], draw_id = rows$draw_id[1L],
      origin_id = rows$origin_id[1L], horizon = h,
      source_manifest_sha256 = shard$identity$source_manifest_sha256,
      posterior_target_sha256 = shard$identity$posterior_target_sha256,
      outer_conditioning = conditioning,
      integration_accuracy_contract_sha256 = shard$integration_accuracy_contract_sha256,
      score_sum = sum(factor * weights * primary), score_count = 1L,
      secondary_realized_score = sum(factor * weights * loss),
      score_label = if (mode == "oracle_acrps") {
        if (length(p) == 1L) "DGP_expected_check_loss" else "DGP_integrated_finite_grid_acrps"
      } else if (length(p) == 1L) "realized_quantile_check_loss" else "realized_finite_grid_acrps",
      quantile_definition = "parameter_conditional_integrated_quantile", stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

app_iqf_quantile_recovery <- function(shard, reference) {
  required <- c("origin_id","horizon","probability","reference_quantile","reference_kind")
  app_iqf_score_require(all(required %in% names(reference)) &&
    all(is.finite(reference$reference_quantile)) &&
    all(reference$reference_kind %in% c("realized_DGP_quantile_path", "origin_marginal_DGP_quantile")),
    "oracle quantile recovery reference must be explicit")
  key <- function(x) paste(x$origin_id, x$horizon, x$probability, sep="|")
  app_iqf_score_require(!anyDuplicated(key(reference)), "duplicate oracle recovery keys")
  x <- shard$quantiles; at <- match(key(x), key(reference))
  app_iqf_score_require(!anyNA(at), "oracle recovery coverage is incomplete")
  error <- x$quantile - reference$reference_quantile[at]
  data.frame(x[c("model_id","draw_id","origin_id","horizon","probability")],
    absolute_error=abs(error),squared_error=error^2,
    reference_kind=reference$reference_kind[at],
    interpretation="oracle_quantile_path_recovery_not_response_forecast_accuracy")
}

app_iqf_score_manifest <- function(root, path, expected) {
  app_iqf_score_require(identical(app_iqf_hash(path, TRUE), expected), "scoring input manifest changed")
  x <- utils::read.csv(path, stringsAsFactors = FALSE)
  app_iqf_score_require(identical(names(x), c("relative_path", "size_bytes", "sha256", "role")) &&
    nrow(x) > 0L && !anyDuplicated(x$relative_path) && all(grepl("^[a-f0-9]{64}$", x$sha256)),
    "scoring inventory schema is incomplete")
  for (i in seq_len(nrow(x))) {
    p <- app_iqf_safe_path(root, x$relative_path[i])
    app_iqf_score_require(file.info(p)$size == x$size_bytes[i] &&
      identical(app_iqf_hash(p, TRUE), x$sha256[i]), "scoring input byte identity failed")
  }
  x
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(TRUE)
  arg <- function(name, default = NULL) {
    i <- match(paste0("--", name), argv)
    if (is.na(i)) default else { app_iqf_score_require(i < length(argv), "missing argument value"); argv[i+1L] }
  }
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
  repo <- normalizePath(file.path(dirname(file_arg), ".."))
  source(file.path(repo, "application/R/integrated_quantile_forecast.R"))
  mode <- arg("mode", "preflight")
  app_iqf_score_require(mode %in% c("preflight", "score", "aggregate"), "unsupported scoring mode")
  request_file <- arg("request")
  if (is.null(request_file)) {
    app_iqf_score_require(mode == "preflight", "scoring requires an authorized immutable request")
    cat("NO_LAUNCH: scoring preparation only; zero forecasts, scores or jobs generated.\n")
    quit(save = "no", status = 0L)
  }
  request <- jsonlite::read_json(request_file, simplifyVector = FALSE)
  app_iqf_score_require(identical(request$schema_version, "integrated_quantile_score_request_v1") &&
    identical(request$workflow, "integrated_quantile_score"), "unknown scoring request")
  if (mode != "preflight") {
    app_iqf_score_require(identical(request$mode, mode), "scoring request mode changed")
    auth <- arg("authorization"); auth_sha <- arg("authorization-sha256")
    ticket <- arg("claim-ticket"); ticket_sha <- arg("claim-ticket-sha256")
    ledger <- arg("ledger"); python <- arg("python", "/usr/bin/python3.11")
    source_manifest <- arg("source-manifest", file.path(repo,
      "docs/reproducibility/integrated_forecast_transition_sources_20261031.csv"))
    app_iqf_score_require(all(vapply(list(auth, auth_sha, ticket, ticket_sha, ledger),
      function(z) is.character(z) && length(z) == 1L && nzchar(z), logical(1L))), "scoring requires a central claim and external authorization")
    command <- c(file.path(repo, "application/scripts/forecast_transition_control.py"),
      if (request$host == "muscat") "verify-claim" else "verify-claim-remote",
      "--ledger", ledger, "--ticket", ticket, "--ticket-sha256", ticket_sha,
      "--request", request_file, "--authorization", auth, "--authorization-sha256", auth_sha,
      "--source-root", repo, "--source-manifest", source_manifest)
    verified <- system2(python, vapply(command, shQuote, ""), stdout = TRUE)
    app_iqf_score_require(is.null(attr(verified, "status")), "scoring claim/source verification failed")
    claim <- jsonlite::fromJSON(paste(verified, collapse = "\n"), simplifyVector = FALSE)
    app_iqf_score_require(isTRUE(claim$verified), "scoring claim was not verified")
  }
  manifest <- app_iqf_score_manifest(request$input_root, request$input_manifest_path, request$input_manifest_sha256)
  bind <- function(relative, role) {
    j <- match(relative, manifest$relative_path)
    app_iqf_score_require(!is.na(j) && identical(manifest$role[j], role), "scoring role is not manifest-bound")
    app_iqf_safe_path(request$input_root, relative)
  }
  spec <- jsonlite::read_json(bind(request$scoring_spec_path, "scoring_spec"), simplifyVector = FALSE)
  app_iqf_score_require(identical(spec$schema_version, "integrated_quantile_scoring_v1"), "scoring specification is unknown")
  if (mode == "preflight") {
    cat("SCORING_PREFLIGHT_PASS: authenticated sidecars; zero scores generated.\n")
    quit(save = "no", status = 0L)
  }
  setTimeLimit(elapsed = as.numeric(claim$resource_budget$wall_seconds), transient = FALSE)
  output <- normalizePath(request$output_root, mustWork = FALSE)
  app_iqf_score_require(identical(output, claim$output_root),
    "scoring output must equal the ticket-bound qualified output directory")
  app_iqf_score_require(!file.exists(output), "scoring output must be a fresh task-owned directory")
  dir.create(output, recursive = TRUE)
  written <- 0
  bounded_write <- function(value, name, format = "csv") {
    written <<- app_iqf_score_write(value, file.path(output, name), format,
      claim$resource_budget$output_bytes, written)
  }
  if (mode == "score") {
    oracle <- readRDS(bind(spec$oracle_path, "scoring_oracle"))
    if (!"origin_id" %in% names(oracle$forecast_map)) oracle <- app_iqf_score_native_oracle(oracle)
    blocks <- lapply(unlist(spec$forecast_shards), function(path) {
      shard <- readRDS(bind(path, "accepted_forecast_shard"))
      app_iqf_score_require(identical(shard$identity$posterior_target_sha256, request$posterior_target_sha256),
        "forecast/scoring posterior target mismatch")
      app_iqf_score_require(identical(shard$integration_accuracy_contract_sha256,
        spec$integration_accuracy_contract_sha256), "scoring used a different integration accuracy contract")
      app_iqf_score_shard(shard, oracle, unlist(spec$probabilities), unlist(spec$weights), spec$score_mode)
    })
    scores <- do.call(rbind, blocks)
    app_iqf_score_require(!anyDuplicated(do.call(paste, c(scores[c("model_id","draw_id","origin_id","horizon")], sep="|"))),
      "duplicate forecast shards in scoring task")
    files <- c(score_blocks = "score_blocks.csv")
    bounded_write(scores, files)
    if (!is.null(spec$recovery_path)) {
      reference <- readRDS(bind(spec$recovery_path,"oracle_quantile_recovery"))
      recovery <- do.call(rbind,lapply(unlist(spec$forecast_shards),function(path)
        app_iqf_quantile_recovery(readRDS(bind(path,"accepted_forecast_shard")),reference)))
      bounded_write(recovery, "oracle_recovery.csv")
      files <- c(files,oracle_recovery="oracle_recovery.csv")
    }
  } else {
    blocks <- lapply(unlist(spec$score_blocks), function(path) utils::read.csv(bind(path, "accepted_score_block"), stringsAsFactors = FALSE))
    keys <- utils::read.csv(bind(spec$expected_keys_path, "expected_score_keys"), stringsAsFactors = FALSE)
    registry <- utils::read.csv(bind(spec$model_target_registry_path, "model_target_registry"), stringsAsFactors = FALSE)
    all_blocks <- do.call(rbind, blocks)
    app_iqf_score_require(all(c("model_id","posterior_target_sha256", "outer_conditioning") %in% names(registry)) &&
      !anyDuplicated(registry$model_id) && setequal(registry$model_id, all_blocks$model_id), "complete model-target registry required")
    for (m in registry$model_id) app_iqf_score_require(
      all(all_blocks$posterior_target_sha256[all_blocks$model_id == m] == registry$posterior_target_sha256[registry$model_id == m]) &&
      all(all_blocks$outer_conditioning[all_blocks$model_id == m] == registry$outer_conditioning[registry$model_id == m]),
      "mixed posterior targets or outer-state conditioning in final aggregation")
    key_fields <- c("model_id","draw_id","origin_id","horizon")
    app_iqf_score_require(identical(names(keys), key_fields), "expected-key manifest schema is exact")
    result <- app_iqf_aggregate_scores(blocks, do.call(paste, c(keys, sep="|")))
    files <- c(draw_scores="draw_scores.csv", score_summary="score_summary.csv")
    bounded_write(result$draw_scores, files[1L])
    bounded_write(result$summary, files[2L])
    if (!is.null(spec$pairing_path)) {
      pairing <- utils::read.csv(bind(spec$pairing_path,"contrast_pairing"), stringsAsFactors=FALSE)
      contrasts <- app_iqf_contrasts(result$draw_scores,pairing)
      bounded_write(contrasts, "contrasts.csv")
      files <- c(files,contrasts="contrasts.csv")
    }
  }
  receipt <- list(schema_version="integrated_quantile_scoring_receipt_v1",mode=mode,
    task_id=request$task_id, numerical_gates_pass=TRUE, new_model_fits=0L,
    intervals="posterior_summaries_after_complete_drawwise_sum_count_aggregation",
    raw_coherence="not_inferred_from_ordered_predictive_CDF_quantiles")
  bounded_write(receipt, "score_receipt.json", "json")
  files <- c(files,score_receipt="score_receipt.json")
  keys <- names(files)
  app_iqf_score_require(setequal(keys,unlist(request$expected_output_keys)) &&
    identical(app_iqf_score_key_hash(keys),request$expected_output_keys_sha256),"scoring output-key contract changed")
  records <- lapply(seq_along(files),function(i) list(key=keys[i],relative_path=unname(files[i]),
    bytes=as.numeric(file.info(file.path(output,files[i]))$size),sha256=app_iqf_hash(file.path(output,files[i]),TRUE),
    posterior_target_sha256=request$posterior_target_sha256))
  app_iqf_score_require(sum(vapply(records,`[[`,numeric(1L),"bytes")) <= claim$resource_budget$output_bytes,
    "scoring output exceeds admitted byte budget")
  identity <- c("task_id","routing_id","rng_namespace","source_commit","source_tree","source_manifest_sha256",
    "posterior_target_sha256","input_manifest_sha256","task_manifest_sha256")
  acceptance <- c(list(schema_version="forecast_transition_output_v1",claim_nonce=claim$claim_nonce),request[identity],
    list(expected_output_keys_sha256=request$expected_output_keys_sha256,numerical_gates_pass=TRUE,shards=records))
  jsonlite::write_json(acceptance,paste0(output,".output_manifest.json"),auto_unbox=TRUE,pretty=TRUE)
  cat("CLAIMED_SCORING_TASK_COMPLETE: no refits; article promotion remains separately gated.\n")
}
