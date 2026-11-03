#!/usr/bin/env Rscript
# Read-only retained-state diagnostics. No saved callback, coordinate update,
# fitting, scoring, forecast generation, or publication is an allowed action.
source("scripts/glofas_same_family_closeout.R")
source("scripts/glofas_same_family_truth_bridge.R")
source("scripts/glofas_same_family_fitted_history.R")

gfr_ids <- function() c("gft-al-p005", "gft-al-p050")
gfr_sources <- function() c("scripts/glofas_fixed_target_forensic_reader.R",
  "scripts/glofas_same_family_closeout.R", "scripts/glofas_same_family_truth_bridge.R",
  "scripts/glofas_same_family_fitted_history.R")
gfr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS retained-state reader: ", why), call. = FALSE)
  invisible(TRUE)
}
gfr_scalar_integer <- function(x) is.numeric(x) && length(x) == 1L &&
  is.finite(x) && x == floor(x)
gfr_pin_shape <- function(x, max_bytes) {
  gfr_require(is.list(x) && setequal(names(x), c("path", "size_bytes", "sha256")) &&
    length(x) == 3L && is.character(x$path) && length(x$path) == 1L &&
    !is.na(x$path) && startsWith(x$path, "/") &&
    !grepl("(^|/)\\.\\.(/|$)", x$path) && gfr_scalar_integer(x$size_bytes) &&
    x$size_bytes > 0 && x$size_bytes <= max_bytes && gsc_hash_string(x$sha256),
    "explicit bounded path/size/hash role required")
  invisible(TRUE)
}
gfr_scope <- function(s) {
  q <- gfr_require; gst_unique_objects(s)
  fields <- c("schema_version", "purpose", "nonce", "expires_utc", "source_root",
    "source_commit", "source_tree", "source_files", "expected_identity", "collection",
    "input_manifest", "design", "models", "read_budget", "limits", "output_root",
    "allow_original_reads", "allow_truth_read", "allow_callbacks", "allow_coordinate_updates",
    "allow_refit", "allow_retuning", "allow_forecasting", "allow_scoring", "allow_publication")
  forbidden <- c("allow_truth_read", "allow_callbacks", "allow_coordinate_updates", "allow_refit",
    "allow_retuning", "allow_forecasting", "allow_scoring", "allow_publication")
  q(is.list(s) && length(s) == length(fields) && setequal(names(s), fields) &&
    identical(s$schema_version, "glofas_fixed_target_forensic_contract_v1") &&
    identical(s$purpose, "TWO_AL_RETAINED_STATES_READ_ONLY_NO_TRUTH_NO_UPDATES") &&
    isTRUE(s$allow_original_reads) && all(vapply(s[forbidden], identical, logical(1L), FALSE)),
    "exact read-only purpose and explicit no-expanded-permission flags required")
  q(is.character(s$nonce) && length(s$nonce) == 1L &&
    grepl("^[a-f0-9]{32,64}$", s$nonce) &&
    all(vapply(s[c("source_commit", "source_tree")], function(x)
      is.character(x) && length(x) == 1L && grepl("^[a-f0-9]{40}$", x), logical(1L))) &&
    gst_same(s$expected_identity, gsc_identity()), "full diagnostic and frozen producer identities required")
  q(is.list(s$models) && identical(sort(names(s$models)), sort(gfr_ids())),
    "exact lower-tail and median AL pair required; additional reads need another admission")
  for (p in c(list(s$design), s$models)) gfr_pin_shape(p, 8 * 1024^3)
  for (p in s[c("collection", "input_manifest")]) gfr_pin_shape(p, 4 * 1024^2)
  q(identical(basename(s$collection$path), "accepted_producers.json") &&
    grepl("\\.csv$", s$input_manifest$path) &&
    identical(s$design$sha256,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3") &&
    identical(s$input_manifest$sha256, gsc_identity()$input_manifest_sha256) &&
    identical(basename(s$design$path), "shared_truth_free_design.rds") &&
    all(vapply(s$models, function(p) identical(basename(p$path), "fit.rds"), logical(1L))),
    "authenticated accepted collection, input manifest and exact truth-free payload roles required")
  b <- s$limits; keys <- c("cpu_seconds", "wall_seconds", "memory_bytes", "output_bytes", "logical_cpu")
  q(is.list(b) && setequal(names(b), keys) && all(vapply(b, gfr_scalar_integer, logical(1L))) &&
    b$cpu_seconds >= 60 && b$cpu_seconds <= 1800 && b$wall_seconds == b$cpu_seconds &&
    b$memory_bytes > 0 && b$memory_bytes <= 32 * 1024^3 &&
    b$output_bytes > 0 && b$output_bytes <= 64 * 1024^2 &&
    b$logical_cpu %in% 0:63 && !b$logical_cpu %in% c(16, 18, 24, 25, 31, 48, 50, 56, 57, 63),
    "finite single-core native reader allocation required")
  r <- s$read_budget
  q(is.list(r) && setequal(names(r), c("max_payload_hash_bytes", "max_deserialization_bytes",
    "max_RDS_deserializations", "max_metadata_bytes", "max_fit_output_bytes")) &&
    all(vapply(r, gfr_scalar_integer, logical(1L))) && all(unlist(r) > 0) &&
    r$max_RDS_deserializations == 3L && r$max_deserialization_bytes <= 24 * 1024^3 &&
    r$max_payload_hash_bytes <= 48 * 1024^3 && r$max_metadata_bytes <= 32 * 1024^2 &&
    r$max_fit_output_bytes <= 10 * 1024^2, "finite three-object and compact-output read budget required")
  gfr_read_cost(s)
  invisible(TRUE)
}
gfr_read_cost <- function(s) {
  bytes <- sum(vapply(c(list(s$design), s$models), function(p) p$size_bytes, numeric(1L)))
  r <- s$read_budget
  gfr_require(bytes <= r$max_deserialization_bytes && 2 * bytes <= r$max_payload_hash_bytes &&
    r$max_RDS_deserializations == 3L, "before/after hash and deserialization grant exceeded before first object")
  list(payload_hash_bytes = 2 * bytes, deserialization_bytes = bytes, RDS_deserializations = 3L)
}
gfr_source <- function(s) {
  root <- normalizePath(getwd(), mustWork = TRUE); q <- gfr_require
  git <- function(a) {
    z <- system2("/usr/bin/git", c("--no-replace-objects", "-c", "core.fsmonitor=false", a), stdout = TRUE)
    q(is.null(attr(z, "status")), "source Git check failed"); unname(z)
  }
  q(identical(root, s$source_root) && identical(git(c("rev-parse", "--show-toplevel")), root) &&
    identical(git(c("rev-parse", "HEAD")), s$source_commit) &&
    identical(git(c("rev-parse", "HEAD^{tree}")), s$source_tree) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))),
    "clean exact committed diagnostic source required")
  q(is.list(s$source_files) && length(s$source_files) == length(gfr_sources()),
    "complete diagnostic source closure required")
  paths <- vapply(s$source_files, function(p) {gfr_pin_shape(p, 1024^2); p$path}, character(1L))
  q(!anyDuplicated(paths) && setequal(paths, file.path(root, gfr_sources())),
    "exact reader and validator source closure required")
  for (pin in s$source_files) gsc_pin(pin, 1024^2)
  for (rel in gfr_sources()) q(identical(git(c("hash-object", "--no-filters", "--", shQuote(rel))),
    git(c("rev-parse", shQuote(paste0(s$source_commit, ":", rel))))), "diagnostic source differs from committed blob")
  invisible(root)
}
gfr_bind <- function(s, collection, manifest) {
  gsc_validate_collection(collection, gsc_identity()); q <- gfr_require
  q(is.data.frame(manifest) && all(c("relative_path", "role", "size_bytes", "sha256") %in% names(manifest)),
    "frozen input manifest schema required")
  at <- which(manifest$role == "truth_free_shared_design")
  q(length(at) == 1L && manifest$size_bytes[at] == s$design$size_bytes &&
    identical(manifest$sha256[at], s$design$sha256) &&
    identical(normalizePath(file.path(dirname(dirname(s$input_manifest$path)), manifest$relative_path[at]),
      mustWork = FALSE), s$design$path), "design is not bound to the frozen truth-free input role")
  for (id in gfr_ids()) {
    z <- Filter(function(x) identical(x$task_id, id), collection$producers)
    q(length(z) == 1L, "selected accepted producer absent")
    a <- Filter(function(x) identical(x$relative_path, "fit.rds"), z[[1L]]$artifacts)
    q(length(a) == 1L && gst_same(a[[1L]][c("path", "size_bytes", "sha256")], s$models[[id]]),
      "selected model does not match accepted producer artifact")
  }
  invisible(TRUE)
}
gfr_numeric <- function(x, why) {
  gfr_require(is.numeric(x) && !is.complex(x) && !is.object(x) && all(is.finite(x)), why)
  x
}
gfr_hash_numeric <- function(x) digest::digest(x, algo = "sha256", serialize = TRUE)
gfr_summary <- function(x, depth = 0L) {
  gfr_require(depth <= 10L && !is.function(x) && !is.environment(x) && !isS4(x) &&
    !is.language(x) && !typeof(x) %in% c("externalptr", "weakref", "promise"),
    "only explicit non-callback state values may be summarized")
  if (is.null(x)) return(NULL)
  if (is.numeric(x)) {
    y <- as.numeric(x); finite <- y[is.finite(y)]
    if (length(y) <= 16L && is.null(dim(x))) return(x)
    return(list(length = length(y), dim = dim(x), sha256 = gfr_hash_numeric(x),
      finite = length(finite), missing_or_nonfinite = length(y) - length(finite),
      range = if (length(finite)) range(finite) else NULL,
      mean = if (length(finite)) mean(finite) else NULL))
  }
  if (is.logical(x) || is.character(x)) {
    if (length(x) <= 256L) return(x)
    values <- unique(x)
    return(list(length = length(x), sha256 = digest::digest(x, algo = "sha256"),
      unique_count = length(values), first_unique_values = head(values, 16L)))
  }
  gfr_require(is.list(x) && (is.null(names(x)) || !anyDuplicated(names(x))), "plain named state list required")
  lapply(x, gfr_summary, depth = depth + 1L)
}
gfr_covariance <- function(V, full = FALSE) {
  V <- gfr_numeric(V, "finite numeric covariance required")
  gfr_require(is.matrix(V) && nrow(V) == ncol(V) && nrow(V) > 0L, "square covariance required")
  n <- nrow(V); diag_v <- diag(V)
  probes <- lapply(1:3, function(k) sin(seq_len(n) * (k + .25)))
  probes <- lapply(probes, function(v) v / sqrt(sum(v^2)))
  result <- list(dimension = n, sha256 = gfr_hash_numeric(V), diagonal = gfr_summary(diag_v),
    symmetry_max_abs = max(abs(V - t(V))), frobenius_norm = sqrt(sum(V^2)),
    min_diagonal = min(diag_v), max_diagonal = max(diag_v),
    operator_probe_quadratics = vapply(probes, function(v) sum(v * as.numeric(V %*% v)), numeric(1L)),
    full_spectrum_evaluated = isTRUE(full))
  if (isTRUE(full)) {
    result$eigenvalues <- eigen((V + t(V))/2, symmetric = TRUE, only.values = TRUE)$values
    result$positive_definite <- all(result$eigenvalues > 0)
  }
  result
}
gfr_state <- function(object, design, producer) {
  q <- gfr_require; gsc_validate_target(object, producer)
  q(object$task_id %in% gfr_ids() && is.list(object$fit) &&
    identical(object$fit$method, "vb") && identical(object$fit$likelihood_family, "al") &&
    identical(object$fit$prior, "rhs_ns"), "matching independent AL RHS fit required")
  history <- gfh_reference_history(design, 30L)
  q(identical(as.numeric(design$future_key$horizon), as.numeric(1:28)) &&
    identical(as.numeric(as.Date(design$future_key$target_date)), as.numeric(gsc_dates())), "frozen forecast dates differ")
  core <- object$fit; v <- core$variational_state; diag <- core$vb_diagnostics
  q(isTRUE(diag$converged) && isTRUE(diag$future_y_working_likelihood_used) &&
    identical(diag$future_gaussian_prior_used, FALSE), "matching converged same-family execution flags required")
  m <- as.numeric(gfr_numeric(v$y_future_mean, "finite future mean required"))
  V <- gfr_numeric(v$y_future_cov, "finite future covariance required")
  theta <- as.numeric(gfr_numeric(v$theta_mean, "finite coefficient mean required"))
  S <- gfr_numeric(v$theta_cov, "finite coefficient covariance required")
  q(length(m) == 28L && identical(dim(V), c(28L, 28L)) && length(theta) == length(history$columns) &&
    identical(dim(S), c(length(theta), length(theta))) &&
    identical(colnames(core$draws$theta), history$columns) &&
    isTRUE(all.equal(m, as.numeric(core$summary$y_future_mean), tolerance = 0)) &&
    isTRUE(all.equal(V, core$summary$y_future_cov, tolerance = 0)), "stored variational dimensions/order/summary disagree")
  lin <- v$future_linearization
  q(is.list(lin) && identical(lin$strategy, "first_order_delta") &&
    isTRUE(all.equal(as.numeric(lin$y_mean), m, tolerance = 0)), "retained numeric linearization at the path mean required")
  Xb <- gfr_numeric(lin$X_beta_future, "finite retained reference features required")
  Xa <- gfr_numeric(lin$X_alpha_future, "finite retained discrepancy features required")
  q(identical(dim(Xb), c(28L, length(history$beta_index))) &&
    identical(dim(Xa), c(28L, length(history$alpha_index))), "retained two-component feature dimensions differ")
  r <- as.numeric(Xb %*% theta[history$beta_index]); d <- as.numeric(Xa %*% theta[history$alpha_index])
  baseline <- design$discrepancy_baseline_future
  if (is.null(baseline)) baseline <- rep(0, 28L)
  baseline <- as.numeric(gfr_numeric(baseline, "finite known discrepancy baseline required"))
  q(length(baseline) == 28L, "known baseline is not horizon-aligned")
  jacobians <- list(reference = lin$J_beta, discrepancy = lin$J_alpha)
  causal <- do.call(rbind, lapply(names(jacobians), function(component) {
    Js <- jacobians[[component]]; rows <- if (component == "reference") length(history$beta_index) else length(history$alpha_index)
    q(is.list(Js) && length(Js) == 28L, "retained Jacobian list required")
    do.call(rbind, lapply(1:28, function(h) {
      J <- gfr_numeric(Js[[h]], "finite retained Jacobian required")
      q(identical(dim(J), c(rows, 28L)), "retained Jacobian dimension differs")
      forbidden <- max(abs(J[, h:28, drop = FALSE]))
      data.frame(component = component, horizon = h, forbidden_current_future_max_abs = forbidden,
        strict_causality_pass = forbidden <= 1e-12, stringsAsFactors = FALSE)
    }))
  }))
  tau <- gsc_task_tau(object$task_id)
  q(all(diag(V) > 0), "future covariance has a nonpositive marginal variance")
  paths <- data.frame(task_id = object$task_id, tau = tau, horizon = 1:28,
    target_date = as.character(gsc_dates()), path_mean = m, path_sd = sqrt(diag(V)),
    reported_marginal_quantile = m + qnorm(tau)*sqrt(diag(V)),
    reference_plugin_at_path_mean = r, discrepancy_plugin_at_path_mean = d,
    known_discrepancy_baseline = baseline, glofas_plugin_sum = r+d+baseline,
    readout_interpretation = "plugin_at_path_mean_not_posterior_expectation_or_marginal_median",
    stringsAsFactors = FALSE)
  covariance <- expand.grid(row_horizon = 1:28, col_horizon = 1:28)
  covariance$value <- as.numeric(V)
  prior <- v$prior
  q(is.list(prior) && prior$prior %in% c("rhs_ns", "block_rhs_ns"), "actual RHS state missing")
  state_fields <- c("theta_mean", "theta_cov", "y_future_mean", "y_future_cov", "sigma", "v", "prior", "future_linearization")
  actual_fields <- names(v)
  summary <- list(task_id = object$task_id, producer_identity = object$identity,
    source_model_target_sha256 = object$identity$posterior_target_sha256,
    complete_saved_state_fields_present = all(state_fields %in% actual_fields),
    complete_saved_state_fields = actual_fields,
    exact_resume_qualified = FALSE, coordinate_updates = 0L,
    requested_vs_executed_prior_status = "NOT_RUN_CONFIG_RDS_NOT_ADMITTED",
    actual_prior_state = gfr_summary(prior), source_scale_state = gfr_summary(v$sigma),
    local_augmentation_state = gfr_summary(v$v), convergence_diagnostics = gfr_summary(diag),
    future_covariance = gfr_covariance(V, TRUE), coefficient_covariance = gfr_covariance(S, FALSE),
    theta_mean = gfr_summary(theta),
    coefficient_column_order_sha256 = digest::digest(history$columns, algo = "sha256"),
    reference_partition_sha256 = gfr_hash_numeric(history$beta_index),
    discrepancy_partition_sha256 = gfr_hash_numeric(history$alpha_index),
    historical_last_date = as.character(tail(history$dates, 1L)),
    historical_last_reference_location = as.numeric(tail(history$H, 1L) %*% theta),
    design_identity_summaries = gfr_summary(design[intersect(c("block_config_hash_beta", "block_config_hash_alpha",
      "discrepancy_input_stream", "ensemble_member_weight_policy", "future_truth_policy",
      "readout_scale_info", "readout_scale_info_alpha"), names(design))]),
    retained_numeric_features_only = TRUE, saved_callback_calls = 0L,
    current_forecast_causality_pass = all(causal$strict_causality_pass),
    stability_status = "NOT_RUN_NO_COORDINATE_UPDATES_ADMITTED",
    future_truth_read = FALSE, new_fits = 0L, publication_authorized = FALSE)
  list(paths = paths, future_covariance = covariance, causality = causal, summary = summary)
}
gfr_json_raw <- function(x) charToRaw(paste0(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
  na = "null", digits = 17, pretty = TRUE), "\n"))
gfr_write <- function(raw, path, root, cap) {
  link <- Sys.readlink(path)
  gfr_require(is.raw(raw) && identical(dirname(path), normalizePath(root, mustWork=TRUE)) &&
    !grepl("(^|/)\\.\\.(/|$)", path) && !file.exists(path) && length(link)==1L &&
    (is.na(link)||!nzchar(link)), "fresh output required")
  total <- sum(file.info(list.files(root, full.names = TRUE))$size)
  gfr_require(length(raw) + total + 65536 <= cap, "compact output budget exceeded before write")
  con <- file(path, "wb"); tryCatch(writeBin(raw, con), finally = close(con))
  invisible(path)
}
gfr_csv_raw <- function(x) {
  con <- textConnection("lines", "w", local = TRUE)
  write.csv(x, con, row.names = FALSE); close(con)
  charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
}
gfr_main <- function(args = commandArgs(TRUE)) {
  q <- gfr_require
  if (identical(args, "--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_fixed_target_forensic_reader.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q(length(args) == 5L && identical(args[c(1L,3L,5L)], c("--contract","--sha256","--execute")),
    "explicit external purpose and execute flag required")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  q(grepl("\\.json$", purpose) && file.info(purpose)$size <= 1024^2 && gsc_hash_string(args[4L]) &&
    identical(unname(tools::sha256sum(purpose)), args[4L]), "exact bounded external purpose digest required")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE); gfr_scope(s)
  root <- normalizePath(getwd(), mustWork = TRUE)
  q(!startsWith(purpose, paste0(root,"/")), "purpose must be external to source checkout")
  gst_runtime(s); gfr_source(s)
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time() + s$limits$wall_seconds, "purpose lifetime must cover whole bounded read")
  out <- s$output_root; link <- Sys.readlink(out)
  q(is.character(out) && length(out) == 1L && startsWith(out, paste0(root,"/local_trackers/")) &&
    !file.exists(out) && (is.na(link)||!nzchar(link)) && dir.exists(dirname(out)) &&
    identical(normalizePath(dirname(out)), dirname(out)) && !grepl("(^|/)\\.\\.(/|$)", out) &&
    system2("/usr/bin/git", c("check-ignore","--quiet","--",shQuote(out))) == 0L,
    "fresh ignored output directory required")
  # Conservative code-path allowance for repeated pins/parsing, Git object/index
  # checks and /proc guards; this is not a claim to meter filesystem I/O.
  metadata_bytes <- 8 * (sum(vapply(s$source_files, function(p) p$size_bytes, numeric(1L))) +
    s$collection$size_bytes + s$input_manifest$size_bytes + file.info(purpose)$size) + 16*1024^2
  q(metadata_bytes <= s$read_budget$max_metadata_bytes, "conservative metadata read allowance exceeded")
  collection <- jsonlite::read_json(gsc_pin(s$collection, 4*1024^2), simplifyVector = FALSE)
  manifest <- read.csv(gsc_pin(s$input_manifest, 4*1024^2), stringsAsFactors = FALSE)
  gfr_bind(s, collection, manifest); cost <- gfr_read_cost(s)
  # All roles/counts are authenticated before the first deserialization.
  q(dir.create(out), "exclusive output directory creation failed")
  attempts <- list(); finished <- FALSE
  on.exit(if (!finished) {
    receipt <- list(status = "FAILED_PARTIAL_READER_EVIDENCE_RETAINED", attempted_reads = attempts,
      future_truth_read = FALSE, coordinate_updates = 0L, new_fits = 0L)
    try(gfr_write(gfr_json_raw(receipt), file.path(out,"FAILED_READ_RECEIPT.json"), out, s$limits$output_bytes), silent = TRUE)
  }, add = TRUE)
  read_one <- function(pin, role) {
    path <- gsc_pin(pin, 8*1024^3)
    attempts[[length(attempts)+1L]] <<- list(role = role, path = path, sha256 = pin$sha256,
      size_bytes = pin$size_bytes, status = "DESERIALIZATION_ATTEMPTED")
    value <- readRDS(path)
    attempts[[length(attempts)]]$status <<- "DESERIALIZED"
    value
  }
  design <- read_one(s$design, "truth_free_design")
  gfh_reference_history(design, 30L)
  for (id in gfr_ids()) {
    message("FORENSIC_READ_ROLE: ",id)
    object <- read_one(s$models[[id]], id)
    producer <- Filter(function(p) identical(p$task_id,id), collection$producers)[[1L]]
    result <- gfr_state(object, design, producer)
    payloads <- list(paths = gfr_csv_raw(result$paths), future_covariance = gfr_csv_raw(result$future_covariance),
      causality = gfr_csv_raw(result$causality), summary = gfr_json_raw(result$summary))
    q(sum(vapply(payloads,length,integer(1L))) <= s$read_budget$max_fit_output_bytes, "per-fit compact-output cap exceeded")
    for (name in names(payloads)) gfr_write(payloads[[name]], file.path(out,
      paste0(id,"_",name,if (name=="summary") ".json" else ".csv")), out, s$limits$output_bytes)
    rm(object,result,payloads); gc(FALSE); gsc_pin(s$models[[id]],8*1024^3)
    attempts[[length(attempts)]]$post_read_sha256 <- s$models[[id]]$sha256
  }
  gsc_pin(s$design,8*1024^3); attempts[[1L]]$post_read_sha256 <- s$design$sha256
  rm(design); gc(FALSE)
  gsc_pin(s$collection,4*1024^2); gsc_pin(s$input_manifest,4*1024^2); gfr_source(s)
  q(expiry > Sys.time() && length(attempts)==3L &&
    sum(proc.time()[c("user.self","sys.self","user.child","sys.child")]) <= s$limits$cpu_seconds,
    "reader lifetime/count/CPU cap exceeded")
  receipt <- list(schema_version="glofas_fixed_target_forensic_receipt_v1",
    status="TWO_AL_STATES_EXPORTED_NOT_STABILITY_OR_ACCURACY_CERTIFICATE",
    purpose_sha256=args[4L],source_commit=s$source_commit,source_tree=s$source_tree,
    producer_identity=gsc_identity(),input_bindings=c(list(design=s$design),s$models),
    accepted_collection=s$collection,input_manifest=s$input_manifest,
    read_cost=c(cost,list(metadata_bytes_upper_bound=metadata_bytes)),attempted_reads=attempts,
    RDS_deserializations=3L,saved_callback_calls=0L,coordinate_updates=0L,
    future_truth_read=FALSE,new_fits=0L,retuning=FALSE,scoring=FALSE,publication_authorized=FALSE,
    requested_vs_executed_prior_status="NOT_RUN_CONFIG_RDS_NOT_ADMITTED",
    exact_resume_status="NOT_QUALIFIED_BY_THIS_READER",
    CPU_seconds=sum(proc.time()[c("user.self","sys.self","user.child","sys.child")]),
    independent_supervisor_closure_still_required=TRUE)
  gfr_write(gfr_json_raw(receipt),file.path(out,"FORENSIC_READ_RECEIPT.json"),out,s$limits$output_bytes)
  files <- list.files(out,full.names=TRUE)
  inventory <- data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files)))
  gfr_write(gfr_csv_raw(inventory),file.path(out,"artifact_manifest.csv"),out,s$limits$output_bytes)
  finished <- TRUE
  cat("GLOFAS_TWO_AL_RETAINED_STATES_EXPORTED_NO_TRUTH_NO_UPDATES\n")
  invisible(receipt)
}

if (sys.nframe()==0L) gfr_main()
