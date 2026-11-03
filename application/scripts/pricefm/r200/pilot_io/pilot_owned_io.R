# New pilot-only I/O definitions. Source/parse does not read a target or run R525.
# A separately priced native build, R ABI and real compute qualification are REQUIRED.
r200_closed <- function(x, keys) {
  stopifnot(is.list(x), !anyDuplicated(names(x)), length(x) == length(keys),
            setequal(names(x), keys))
  invisible(TRUE)
}
r200_json <- function(path) {
  x <- jsonlite::read_json(path, simplifyVector = FALSE)
  walk <- function(v) {
    if (is.list(v)) {
      if (!is.null(names(v))) stopifnot(!anyDuplicated(names(v)))
      invisible(lapply(v, walk))
    } else if (is.numeric(v)) stopifnot(all(is.finite(v)))
  }
  walk(x); x
}
r200_physical <- function(path) {
  stopifnot(is.character(path), length(path) == 1L,
    grepl("^/[A-Za-z0-9_./-]+$", path), !grepl("(^|/)\\.\\.(/|$)", path),
    identical(normalizePath(path, mustWork = TRUE), path))
  cursor <- path
  repeat {
    stopifnot(identical(Sys.readlink(cursor), ""))
    if (identical(cursor, "/")) break
    cursor <- dirname(cursor)
  }
  path
}
r200_pin_file <- function(pin) {
  r200_closed(pin, c("path", "sha256"))
  stopifnot(grepl("^[0-9a-f]{64}$", pin$sha256))
  path <- r200_physical(pin$path)
  stopifnot(identical(digest::digest(path, file = TRUE, algo = "sha256"), pin$sha256))
  path
}
r200_proc <- function(pid) {
  text <- readLines(sprintf("/proc/%d/stat", pid), warn = FALSE)
  bits <- strsplit(sub("^.*\\) ", "", text), " +")[[1L]]
  list(pid = as.integer(pid), parent = as.integer(bits[[2L]]),
       start_ticks = as.numeric(bits[[20L]]))
}
r200_uid <- function() {
  line <- readLines("/proc/self/status", warn = FALSE)
  as.numeric(strsplit(trimws(sub("^Uid:", "", line[startsWith(line, "Uid:")])), "[ \t]+")[[1L]][[1L]])
}
r200_begin_after_real_ack <- function(owner_spec_pin, io_request_pin,
                                       authority_pin, source_review_pin) {
  # All arguments here are pinned source/metadata. They are not payload grants.
  owner <- r200_json(r200_pin_file(owner_spec_pin))
  request <- r200_json(r200_pin_file(io_request_pin))
  authority <- r200_json(r200_pin_file(authority_pin))
  review <- r200_json(r200_pin_file(source_review_pin))
  stopifnot(identical(owner$io_request, io_request_pin),
    identical(request$schema, "r200_pilot_owned_io_request_v1"),
    identical(request$role, "NO3_AL300_PILOT"),
    identical(request$purpose, owner$purpose), identical(request$nonce, owner$nonce),
    identical(request$role, owner$role), identical(authority$spec, owner_spec_pin),
    identical(authority$source_review, source_review_pin),
    identical(request$controller_source, review$controller_source),
    identical(as.character(getRversion()), request$runtime_build$R_version),
    request$runtime_build$connection_api_version == 1L,
    identical(Sys.getenv("SLURM_JOB_ID"), owner$job_id),
    identical(Sys.getenv("SLURMD_NODENAME"), owner$node),
    grepl("^node-[0-9]+$", owner$node), identical(Sys.getenv("SLURM_CPUS_PER_TASK"), "1"))
  # Inert DLL preload and exact source parsing occur before the native barrier.
  io_dll <- dyn.load(r200_pin_file(request$io_library))
  boundary_dll <- dyn.load(r200_pin_file(request$native_boundary))
  for (p in owner$source_pins) {
    source_path <- r200_pin_file(p)
    if (grepl("\\.R$", source_path)) invisible(parse(file = source_path, keep.source = FALSE))
  }
  for (p in request$science_source_pins) r200_pin_file(p)
  # Runtime definitions/namespace load are source-only bootstrap operations.
  source(r200_pin_file(request$scientific_context$fixedpoint_helper))
  source(r200_pin_file(request$scientific_context$project_consumer))
  ns <- r129_namespace(request$scientific_context$library)
  stopifnot(identical(digest::digest(body(get(".run_static_dqlm_cavi", ns)),
    algo = "sha256"), request$scientific_context$expected_stock_body_sha256))
  frame <- list(status = "R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT",
    purpose = owner$purpose, nonce = owner$nonce, role = owner$role,
    job_id = owner$job_id, node = owner$node, source_pins = owner$source_pins,
    optimizer_invocations = 0L, scientific_target_data_read = FALSE)
  cat(jsonlite::toJSON(frame, auto_unbox = TRUE, digits = 17), "\n")
  flush(stdout())
  # This is the real pinned native kernel/parent handshake, not a callback,
  # supplied TRUE, environment marker, or a JSON assertion of an ACK.
  stopifnot(isTRUE(.Call(getNativeSymbolInfo("r157_scientific_boundary",
                                           boundary_dll)$address, NULL)))
  now <- as.numeric(Sys.time())
  gate <- r200_json(r200_physical(owner$acknowledgement_path))
  r200_closed(gate, c("schema", "status", "spec", "authority", "source_review",
    "purpose", "nonce", "role", "job_id", "node", "uid", "owner", "child",
    "source_pins", "frame", "created_epoch", "kernel_ACK_requires_real_boundary_call"))
  me <- r200_proc(Sys.getpid()); parent <- r200_proc(me$parent)
  boot <- readLines("/proc/sys/kernel/random/boot_id", warn = FALSE)
  stopifnot(identical(gate$schema, "r200_parent_parse_gate_v1"),
    identical(gate$status, "OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK"),
    identical(gate$spec, owner_spec_pin), identical(gate$authority, authority_pin),
    identical(gate$source_review, source_review_pin),
    identical(gate$frame, frame), identical(gate$source_pins, owner$source_pins),
    identical(gate$purpose, owner$purpose), identical(gate$nonce, owner$nonce),
    identical(gate$role, owner$role), identical(gate$job_id, owner$job_id),
    identical(gate$node, owner$node), gate$uid == r200_uid(),
    gate$child$pid == me$pid, gate$child$start_ticks == me$start_ticks,
    gate$owner$pid == parent$pid, gate$owner$start_ticks == parent$start_ticks,
    identical(gate$owner$boot_id, boot),
    isTRUE(gate$kernel_ACK_requires_real_boundary_call),
    gate$created_epoch <= now, now - gate$created_epoch <= 120,
    owner$runtime_owner$parent_pid == parent$pid,
    owner$runtime_owner$parent_birth_ticks == parent$start_ticks,
    owner$runtime_owner$uid == gate$uid,
    now < owner$runtime_owner$expires_epoch)
  call <- function(name, ...) .Call(getNativeSymbolInfo(name, io_dll)$address, ...)
  proof_inputs <- list()
  for (key in names(request$accepted_bridge)) {
    logical <- request$accepted_bridge[[key]]
    rows <- Filter(function(x) identical(x$logical, logical), request$proof_aliases)
    stopifnot(length(rows) == 1L, rows[[1L]]$uid == gate$uid,
      identical(rows[[1L]]$physical$sha256, logical$sha256))
    proof_inputs[[paste0("proof_", key)]] <- list(
      physical = rows[[1L]]$physical$path, bytes = rows[[1L]]$bytes)
  }
  config <- c(owner$runtime_owner,
    list(output_root = request$output_root, slots = request$storage$slots,
         headroom_bytes = request$storage$headroom_bytes,
         max_snapshot_bytes = request$storage$max_snapshot_bytes,
         inputs = c(request$inputs, proof_inputs)))
  native <- call("r200_io_activate", config)
  cap <- new.env(parent = emptyenv())
  cap$native <- native; cap$call <- call; cap$request <- request
  cap$owner_spec <- owner_spec_pin; cap$authority <- authority_pin
  cap$source_review <- source_review_pin; cap$parent_gate <- gate
  cap$completed <- 0L; cap$optimizer_invocations <- 0L; cap$namespace <- ns
  cap$inputs_verified <- FALSE; cap$sealed <- list(); cap$sealed_proofs <- list()
  class(cap) <- "r200_owned_io_capability"
  lockBinding("native", cap); lockBinding("call", cap); lockBinding("request", cap)
  cap
}
r200_guard_capability <- function(cap) {
  stopifnot(is.environment(cap), inherits(cap, "r200_owned_io_capability"),
            typeof(cap$native) == "externalptr")
  invisible(cap$call("r200_io_validate_live", cap$native))
}
r200_verify_all_input_bytes <- function(cap) {
  r200_guard_capability(cap)
  stopifnot(!cap$inputs_verified)
  # The native helper checks the physical inode/UID/length and creates sealed
  # memfds. Hash the immutable copies BEFORE any RDS or numeric interpretation.
  sealed <- list()
  for (name in c("X", "y", "factor_state")) {
    expected <- cap$request$inputs[[name]]
    path <- cap$call("r200_io_snapshot", cap$native, name)
    stopifnot(file.info(path)$size == expected$bytes,
      identical(digest::digest(path, file = TRUE, algo = "sha256"), expected$sha256))
    sealed[[name]] <- path
  }
  proofs <- list()
  for (key in names(cap$request$accepted_bridge)) {
    logical <- cap$request$accepted_bridge[[key]]
    alias <- Filter(function(x) identical(x$logical, logical), cap$request$proof_aliases)[[1L]]
    path <- cap$call("r200_io_snapshot", cap$native, paste0("proof_", key))
    stopifnot(file.info(path)$size == alias$bytes,
      identical(digest::digest(path, file = TRUE, algo = "sha256"), logical$sha256))
    proofs[[key]] <- path
  }
  cap$sealed <- sealed; cap$sealed_proofs <- proofs; cap$inputs_verified <- TRUE
  invisible(sealed)
}
r200_read_design <- function(cap) {
  r200_guard_capability(cap); stopifnot(cap$inputs_verified)
  read_one <- function(path, count) {
    con <- file(path, "rb"); on.exit(close(con))
    x <- readBin(con, double(), n = count, size = 8L, endian = "little")
    stopifnot(length(x) == count, all(is.finite(x))); x
  }
  list(X = matrix(read_one(cap$sealed$X, 48576L * 417L),
                  nrow = 48576L, byrow = TRUE),
       y = read_one(cap$sealed$y, 48576L))
}
r200_write_with_reservation <- function(cap, name, writer) {
  # 'writer' controls serialization only. It cannot create a capability,
  # authenticate ACK/owner, choose a path, enlarge a cap or replace a file.
  r200_guard_capability(cap)
  con <- cap$call("r200_io_connection", cap$native, name)
  done <- FALSE; connection_closed <- FALSE
  on.exit({
    if (!connection_closed) tryCatch(close(con), error = function(e) NULL)
    if (!done) cap$call("r200_io_fail", cap$native)
  })
  writer(con)
  close(con); connection_closed <- TRUE
  bytes <- cap$call("r200_io_commit", cap$native, name)
  done <- TRUE
  path <- file.path(cap$request$output_root, name)
  list(path = path, sha256 = digest::digest(path, file = TRUE, algo = "sha256"),
       bytes = bytes)
}
r200_save_rds <- function(cap, name, object) {
  r200_write_with_reservation(cap, name,
    function(con) saveRDS(object, con, ascii = FALSE, version = 3L, compress = FALSE))
}
r200_write_json <- function(cap, name, object) {
  text <- paste0(jsonlite::toJSON(object, auto_unbox = TRUE, pretty = TRUE,
                                digits = 17, null = "null", na = "null"), "\n")
  r200_write_with_reservation(cap, name,
    function(con) writeBin(charToRaw(enc2utf8(text)), con))
}
r200_import_verified_factors <- function(cap, ns, prior, X, y, ctx) {
  r200_guard_capability(cap); stopifnot(cap$inputs_verified)
  request <- cap$request
  bridge <- r200_json(cap$sealed_proofs$bridge_validation)
  stopifnot(identical(bridge$source, request$scientific_source),
    identical(bridge$target_name, request$case$target),
    bridge$optimizer_updates == 0L, isTRUE(bridge$full_state_factors_verified),
    isTRUE(bridge$explicit_factor_elbo_verified), isTRUE(bridge$source_recipe_reproduced),
    identical(bridge$factor_state, request$accepted_bridge$factor_state),
    identical(ctx$source, request$scientific_source),
    identical(ctx$target_name, request$case$target),
    identical(ctx$posterior_target_sha256, request$posterior_target_sha256),
    identical(ctx$original_manifest_sha256, request$original_manifest_sha256),
    identical(ctx$original_failed, request$expected_state_provenance$original_failed_bindings),
    identical(ctx$data_references, request$expected_state_provenance$data_references))
  # readRDS uses the exact sealed bytes whose hash was already verified.
  factors <- readRDS(cap$sealed$factor_state)
  stopifnot(identical(factors$kind, "conditional_reconstruction_new_initialization"),
    identical(factors$origin, "sealed_real_target_project_consumer"),
    identical(factors$target_key, request$posterior_target_sha256),
    identical(factors$source_provenance, request$expected_state_provenance),
    identical(factors$source_provenance$source, request$scientific_source),
    identical(factors$source_provenance$data_references,
              request$expected_state_provenance$data_references),
    identical(factors$source_provenance$original_failed_bindings,
              request$expected_state_provenance$original_failed_bindings),
    identical(factors$prior_controls, prior$controls))
  checked <- r525_validate_state(factors, X, y, ctx$tau, prior,
    rep(0, ctx$p), diag(1e6, ctx$p), 1, 1, ns, ctx)
  stopifnot(identical(checked, factors))
  objective <- r525_explicit_factor_elbo(ns, prior, factors, X, y, ctx$tau, ctx)
  r200_write_json(cap, "proof/COMPUTE_IMPORT_PROVENANCE.json", list(
    schema = "r200_actual_owned_import_verification_v1",
    status = "VERIFIED_SEALED_BYTES_FULL_PROVENANCE_AND_UNCHANGED_FACTOR_OBJECTIVE",
    owner_spec = cap$owner_spec, authority = cap$authority,
    source_review = cap$source_review, parent_gate = cap$parent_gate,
    scientific_source = request$scientific_source,
    controller_source = request$controller_source,
    accepted_bridge = request$accepted_bridge, proof_aliases = request$proof_aliases,
    inputs = request$inputs, factors_unchanged = TRUE,
    initialization_only = TRUE, optimizer_resume = FALSE,
    objective = objective, does_not_grant_production_acceptance = TRUE))
  list(factors = factors, objective = objective)
}
r200_checkpoint <- function(cap, frame, ctx) {
  r200_guard_capability(cap)
  iter <- get("iter", frame)
  stopifnot(iter == cap$completed + 1L, iter >= 1L, iter <= 300L)
  state <- r525_factor_state(frame, ctx, "project_new_attempt_full_factors")
  optimizer <- list(completed_sweep = iter,
    stable_count = get("stable_count", frame), step = get("step", frame),
    stock_controls = get("controls", frame),
    raw_formal_stop_pending = isTRUE(get("step", frame)$stop_now),
    formal_flag_before_unchanged_stock_stop_check = get("converged", frame),
    elbo_trace = get("elbo_trace", frame), seq_sigma = get("seq.sigma", frame),
    delta_beta = get("delta_beta", frame), delta_sigma = get("delta_sigma", frame),
    delta_elbo = get("delta_elbo", frame),
    RNG_kind = RNGkind(), RNG_before_post_sampling = get(".Random.seed", .GlobalEnv),
    resume_supported_by_this_adapter = FALSE)
  base <- sprintf("checkpoints/sweep_%04d/", iter)
  saved <- r200_save_rds(cap, paste0(base, "full_state.rds"),
    list(factors = state, optimizer = optimizer,
         data_references = ctx$data_references, source = ctx$source))
  entry <- list(completed_sweep = iter,
    state_pin = saved[c("path", "sha256")], bytes = saved$bytes,
    contains_all_factors_and_schedules = TRUE)
  r200_write_json(cap, paste0(base, "completed_evidence.json"), entry)
  ctx$checkpoint_entries[[length(ctx$checkpoint_entries) + 1L]] <- entry
  cap$completed <- iter
  invisible(NULL)
}
r200_make_bounded_engine <- function(cap, ns, ctx, output) {
  r200_guard_capability(cap); stopifnot(cap$inputs_verified,
    identical(output, cap$request$output_root))
  engine <- r525_make_engine(ns, ctx, output)
  before <- digest::digest(body(engine), algo = "sha256")
  child <- environment(engine)
  stopifnot(exists("r525_checkpoint_bound", child, inherits = FALSE))
  child$r525_checkpoint_bound <- function(frame) r200_checkpoint(cap, frame, ctx)
  lockBinding("r525_checkpoint_bound", child)
  stopifnot(identical(digest::digest(body(engine), algo = "sha256"), before))
  attr(engine, "r200_recorded_checkpoint_glue") <- "bounded_native_reservation_no_math_body_change"
  engine
}

r200_execute_exact_pilot <- function(cap) {
  r200_guard_capability(cap)
  stopifnot(cap$optimizer_invocations == 0L)
  request <- cap$request
  original <- r200_json(r200_pin_file(request$scientific_context$original_manifest))
  targets <- Filter(function(x) identical(x$name, request$case$target), original$targets)
  stopifnot(length(targets) == 1L)
  target <- targets[[1L]]; c <- target$contract
  stopifnot(target$n == 48576L, target$p == 417L, target$seed == 819509105L,
    target$tau == .75, target$tau0 == .0022915214919211734,
    c$max_iter == 300L, c$seed == 819509105L, c$tol == 1e-5,
    c$n_samp == 20L, c$max_rhs_iter == 20000L,
    identical(target$bindings, request$expected_state_provenance$original_failed_bindings),
    identical(target$posterior_target_sha256, request$posterior_target_sha256))
  r200_verify_all_input_bytes(cap)
  data <- r200_read_design(cap); X <- data$X; y <- data$y
  ns <- cap$namespace
  ctx <- list2env(list(target_name = target$name, n = target$n, p = target$p,
    origin = "sealed_real_target_project_consumer", tau = target$tau, tau0 = target$tau0,
    source = request$scientific_source,
    original_manifest_sha256 = request$original_manifest_sha256,
    posterior_target_sha256 = target$posterior_target_sha256,
    units = "original_design_and_response", prior = original$scope$prior,
    original_failed = target$bindings, checkpoint_entries = list(),
    disk_bytes = sum(vapply(request$storage$slots, function(x) x$max_bytes, numeric(1L))),
    data_references = request$expected_state_provenance$data_references), parent = emptyenv())
  r525_closed_data_limits(ctx, X, y)
  prior <- r129_prior(ns, ctx$p, ctx$tau0)
  imported <- r200_import_verified_factors(cap, ns, prior, X, y, ctx)
  factors <- imported$factors
  engine <- r200_make_bounded_engine(cap, ns, ctx, request$output_root)
  set.seed(c$seed)
  # Spend before entry: any optimizer error stops this attempt permanently.
  cap$optimizer_invocations <- 1L
  fit <- tryCatch(engine(y, X, ctx$tau, max_iter = 300L, tol = c$tol,
    b0 = rep(0, ctx$p), V0 = diag(1e6, ctx$p), beta_prior_obj = prior,
    a_sigma = 1, b_sigma = 1, init = list(full_state = factors),
    n.samp = c$n_samp, verbose = FALSE), error = function(e) {
      cap$call("r200_io_fail", cap$native); stop(e)
    })
  trace <- as.data.frame(fit$diagnostics$vb_trace)
  sigma <- as.numeric(fit$qsig$E_sigma); m <- as.numeric(fit$qbeta$m); V <- as.matrix(fit$qbeta$V)
  finite <- length(m) == ctx$p && all(is.finite(m)) && all(is.finite(V)) &&
    all(diag(V) > 0) && is.finite(sigma) && sigma > 0 && nrow(trace) > 0
  stopifnot(finite, fit$iter >= 1L, fit$iter <= 300L,
    cap$completed == fit$iter, length(ctx$checkpoint_entries) == fit$iter)
  # The unchanged seven-measure certificate executes even when formal is TRUE.
  cert <- r129_certificate(ns, X, y, m, V, sigma, ctx$tau, ctx$tau0,
    unlist(c$certificate_limits), max_rhs_iter = c$max_rhs_iter)
  stopifnot(length(cert$measures) == 7L)
  accepted <- finite && (isTRUE(fit$converged) || isTRUE(cert$certified))
  write64 <- function(name, value) r200_write_with_reservation(cap, name,
    function(con) writeBin(as.double(value), con, size = 8L, endian = "little"))
  write64("beta_mean.bin", m); write64("beta_cov.bin", t(V))
  r200_write_with_reservation(cap, "vb_trace.csv",
    function(con) utils::write.csv(trace, con, row.names = FALSE))
  r200_save_rds(cap, "final_state.rds", list(qbeta = fit$qbeta, qv = fit$qv, qsig = fit$qsig,
    beta_prior = fit$beta_prior, diagnostics = fit$diagnostics, misc = fit$misc,
    data_references = ctx$data_references, source = ctx$source,
    RNG_after_stock_sampling = get(".Random.seed", .GlobalEnv),
    posterior_draws_retained = FALSE, stock_sampling_executed = TRUE,
    exact_optimizer_resume_supported = FALSE))
  r200_save_rds(cap, "independent_certificate_full_state.rds", cert)
  index <- r200_write_json(cap, "checkpoint_index.json", list(
    schema = "r154_fullstate_checkpoint_index_v1",
    target_name = ctx$target_name, posterior_target_sha256 = ctx$posterior_target_sha256,
    n = ctx$n, p = ctx$p, tau = ctx$tau, tau0 = ctx$tau0,
    source = ctx$source, data_references = ctx$data_references,
    checkpoints = ctx$checkpoint_entries))
  stripped <- cert
  stripped[c("reconstructed_rhs_state", "latent_state", "beta_covariance", "prior_center")] <- NULL
  stripped$limits <- as.list(stripped$limits); stripped$measures <- as.list(stripped$measures)
  r200_write_json(cap, "terminal_core.json", list(
    schema = "r154_project_consumer_candidate_v1",
    record_kind = "pilot_candidate_no_automatic_release",
    origin = "sealed_real_target_project_consumer", target_name = ctx$target_name,
    posterior_target_sha256 = ctx$posterior_target_sha256,
    n = ctx$n, p = ctx$p, tau = ctx$tau, tau0 = ctx$tau0,
    original_manifest_sha256 = ctx$original_manifest_sha256,
    source = ctx$source, units = ctx$units, prior = ctx$prior,
    initializer = list(kind = "conditional_reconstruction_new_initialization",
      bridge = request$accepted_bridge$bridge_validation, exact_optimizer_resume = FALSE,
      prior_center_from_initializer = FALSE),
    max_iter = 300L, new_attempt_index = 1L, maximum_new_attempts = 1L,
    prior_attempt_iterations = 300L, completed_sweeps = fit$iter,
    cumulative_update_history = list(previous_failed_attempt_sweeps = 300L,
      this_separate_attempt_completed_sweeps = fit$iter, single_fit_cap = 300L,
      old_attempt_resumed = FALSE),
    finite_core = finite, formal_converged = isTRUE(fit$converged),
    raw_stock_convergence = fit$diagnostics$convergence,
    independent_certificate = stripped, all_seven_certificate_computed = TRUE,
    computationally_certified = accepted, checkpoint_index = index[c("path", "sha256")],
    original_failed = target$bindings, owner_spec = cap$owner_spec, authority = cap$authority,
    sigma = sigma, seed = c$seed, test_opened = FALSE, prior_center_from_initializer = FALSE,
    acceptance_logic = "finite AND (formal OR independent)",
    old_completed_artifacts_modified = FALSE,
    production_parent_or_original_failed_state_modified = FALSE,
    automatic_dependant_release = FALSE, scope_expansion_to_other_five = FALSE))
  inventory <- cap$call("r200_io_inventory", cap$native)
  expected_completed <- unlist(lapply(seq_len(fit$iter), function(k)
    paste0(sprintf("checkpoints/sweep_%04d/", k),
           c("full_state.rds", "completed_evidence.json"))), use.names = FALSE)
  expected_outputs <- c("final_state.rds", "independent_certificate_full_state.rds",
    "terminal_core.json", "beta_mean.bin", "beta_cov.bin", "vb_trace.csv",
    "checkpoint_index.json", "proof/COMPUTE_IMPORT_PROVENANCE.json")
  committed <- vapply(inventory, function(x) isTRUE(x$committed), logical(1L))
  names <- vapply(inventory, function(x) x$name, character(1L))
  stopifnot(setequal(names[committed], c(expected_completed, expected_outputs)))
  # Unused preallocated slots remain paid reservations; do not delete them.
  # The separately owned return verifier must account for both sets.
  invisible(list(candidate_only = TRUE, completed_sweeps = fit$iter,
    retained_slot_inventory = inventory, production_admission = FALSE))
}
