#!/usr/bin/env Rscript
# Narrow, config-only prior export for the experimental native GloFAS optimizer.
# This reader never opens a design or fit and never authorizes a model run.

gnpc_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS native prior contract: ", why), call. = FALSE)
  invisible(TRUE)
}

gnpc_hash_file <- function(path) unname(tools::sha256sum(path))
gnpc_hash_object <- function(x) {
  gnpc_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}
gnpc_hex <- function(x, n) is.character(x) && length(x) == 1L &&
  grepl(sprintf("^[a-f0-9]{%d}$", n), x)
gnpc_scalar <- function(x, positive = FALSE) is.numeric(x) && length(x) == 1L &&
  is.finite(x) && (!positive || x > 0)
gnpc_or <- function(x, default) if (is.null(x)) default else x

gnpc_block_prior <- function(raw, inherited = list()) {
  args <- modifyList(inherited, raw %||% list())
  pick <- function(name, default) {
    value <- gnpc_or(args[[name]], default)
    gnpc_require(gnpc_scalar(value, TRUE), paste0(name, " must be a positive scalar"))
    as.numeric(value)
  }
  fixed <- args$zeta2_fixed
  gnpc_require(is.null(fixed) || gnpc_scalar(fixed, TRUE),
    "zeta2_fixed must be NULL or a positive scalar")
  slab_s2 <- if (!is.null(args$slab_s2)) args$slab_s2 else
    if (!is.null(args$s2)) args$s2 else 1
  gnpc_require(gnpc_scalar(slab_s2, TRUE), "s2/slab_s2 initializer must be positive")
  slab_s2 <- as.numeric(slab_s2)
  list(
    tau0 = pick("tau0", 1),
    intercept_prec = pick("intercept_prec", 1e-9),
    slab = list(
      learned = is.null(fixed),
      zeta2_fixed = fixed,
      a_zeta = pick("a_zeta", 2),
      b_zeta = pick("b_zeta", 4),
      slab_s2_initial = slab_s2,
      slab_s2_role = if (is.null(fixed))
        "variational_state_initializer_not_prior_hyperparameter" else
        "ignored_by_fixed_slab_prior"
    ),
    rhs_hierarchy = list(
      coefficient_product = "N(b;0,tau2*lambda2) times N(b;0,zeta2)",
      tau2_given_xi = "IG(shape=1/2,rate=1/xi)",
      xi = "IG(shape=1/2,rate=1/tau0^2)",
      lambda2_given_nu = "IG(shape=1/2,rate=1/nu)",
      nu = "IG(shape=1/2,rate=1)",
      global_conditional_shape = "(r+1)/2 with intercept excluded",
      local_conditional_shape = 1
    )
  )
}

gnpc_extract_config <- function(config) {
  q <- gnpc_require
  q(is.list(config) && is.character(config$task_id) && length(config$task_id) == 1L &&
    nzchar(config$task_id) && is.list(config$vb_args), "task_id and vb_args are required")
  a <- config$vb_args
  protected_names <- c("beta_rhs", "alpha_rhs", "beta_ridge", "prior_sigma")
  raw <- a[protected_names]
  names(raw) <- protected_names
  beta_raw <- a$beta_rhs %||% list()
  alpha_raw <- a$alpha_rhs %||% list()
  q(is.list(beta_raw) && is.list(alpha_raw), "beta_rhs and alpha_rhs must be lists")
  prior_sigma <- a$prior_sigma %||% list()
  q(is.list(prior_sigma), "prior_sigma must be a list")
  shape <- gnpc_or(prior_sigma$a, 2)
  rate <- gnpc_or(prior_sigma$b, 1)
  q(gnpc_scalar(shape, TRUE) && gnpc_scalar(rate, TRUE),
    "source-scale prior shape and rate must be positive scalars")
  effective <- list(
    beta = gnpc_block_prior(beta_raw),
    alpha = gnpc_block_prior(alpha_raw, beta_raw),
    source_scale = list(
      Y = c(shape = as.numeric(shape), rate = as.numeric(rate)),
      G = c(shape = as.numeric(shape), rate = as.numeric(rate)),
      parameterization = "inverse_gamma_shape_rate"
    ),
    ridge = list(
      precision = as.numeric(gnpc_or((a$beta_ridge %||% list())$precision,
        gnpc_or(a$ridge_precision, 1))),
      used_by_native_AL_target = FALSE
    ),
    prior_addition = a$prior_addition,
    prior_addition_allowed = FALSE,
    coordinate_measure = "coefficients_and_log_positive_parameters",
    jacobian_count = 1L,
    warm_start_values_are_prior_defining = FALSE
  )
  q(gnpc_scalar(effective$ridge$precision, TRUE), "ridge precision must be positive")
  q(is.null(effective$prior_addition), "additional data-dependent priors are not admitted")
  list(
    schema_version = "glofas_native_prior_export_v1",
    task_id = config$task_id,
    posterior_target_sha256 = config$posterior_target_sha256 %||% NULL,
    declared_prior_sha256 = config$prior_sha256 %||% NULL,
    raw_protected_tuple = raw,
    raw_protected_tuple_sha256 = gnpc_hash_object(raw),
    effective_prior = effective,
    effective_prior_sha256 = gnpc_hash_object(effective),
    config_initializer_fields = list(
      beta_slab_s2 = beta_raw$slab_s2,
      alpha_slab_s2 = alpha_raw$slab_s2,
      role = "initialization_only_when_corresponding_zeta2_fixed_is_NULL"
    ),
    model_run_authorized = FALSE,
    native_application_qualified = FALSE,
    publication_authorized = FALSE
  )
}

gnpc_validate_purpose <- function(s) {
  q <- gnpc_require
  fields <- c("schema_version", "purpose", "nonce", "expires_utc", "source_root",
    "source_commit", "source_tree", "source_files", "config", "expected",
    "read_budget", "output_root", "allow_config_read", "allow_design_read",
    "allow_fit_read", "allow_model_run", "allow_truth_read", "allow_publication")
  q(is.list(s) && setequal(names(s), fields) && !anyDuplicated(names(s)) &&
    identical(s$schema_version, "glofas_native_prior_config_read_purpose_v1") &&
    identical(s$purpose, "ONE_MEDIAN_AL_CONFIG_PRIOR_EXPORT_NO_MODEL_RUN") &&
    gnpc_hex(s$nonce, 64L) && gnpc_hex(s$source_commit, 40L) &&
    gnpc_hex(s$source_tree, 40L), "exact config-only purpose required")
  q(isTRUE(s$allow_config_read) && all(vapply(s[c("allow_design_read", "allow_fit_read",
    "allow_model_run", "allow_truth_read", "allow_publication")], identical,
    logical(1L), FALSE)), "only one config read may be authorized")
  pin <- s$config
  q(is.list(pin) && setequal(names(pin), c("path", "size_bytes", "sha256", "role")) &&
    identical(pin$role, "transition_task_configuration") &&
    gnpc_scalar(pin$size_bytes, TRUE) && pin$size_bytes <= 1024^2 &&
    gnpc_hex(pin$sha256, 64L), "bounded role-bound config pin required")
  e <- s$expected
  q(is.list(e) && setequal(names(e), c("task_id", "posterior_target_sha256")) &&
    identical(e$task_id, "gft-al-p050") && gnpc_hex(e$posterior_target_sha256, 64L),
    "exact median task and target identities required; the hash-pinned config exports its own prior identity")
  b <- s$read_budget
  q(is.list(b) && setequal(names(b), c("max_RDS_deserializations",
    "max_deserialization_bytes", "max_hash_bytes", "max_output_bytes")) &&
    identical(as.integer(b$max_RDS_deserializations), 1L) &&
    identical(as.numeric(b$max_deserialization_bytes), as.numeric(pin$size_bytes)) &&
    identical(as.numeric(b$max_hash_bytes), 2 * as.numeric(pin$size_bytes)) &&
    gnpc_scalar(b$max_output_bytes, TRUE) && b$max_output_bytes <= 1024^2,
    "exact one-read budget required")
  q(is.list(s$source_files) && length(s$source_files) == 3L,
    "exact reader and constructor source closure required")
  invisible(TRUE)
}

gnpc_validate_source <- function(s) {
  q <- gnpc_require
  root <- normalizePath(getwd(), mustWork = TRUE)
  git <- function(args) {
    out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
      "core.fsmonitor=false", args), stdout = TRUE, stderr = TRUE)
    q(is.null(attr(out, "status")), "Git source check failed")
    unname(out)
  }
  q(identical(root, s$source_root) && identical(git(c("rev-parse", "HEAD")),
    s$source_commit) && identical(git(c("rev-parse", "HEAD^{tree}")), s$source_tree) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))),
    "reader must execute from its exact clean committed source")
  expected <- c("scripts/diagnostics/glofas_native_prior_contract.R",
    "application/R/latent_path_vb_al.R", "application/R/glofas_family_transition.R")
  paths <- vapply(s$source_files, function(pin) pin$path, character(1L))
  q(setequal(paths, file.path(root, expected)) && !anyDuplicated(paths),
    "source closure differs from reader and effective constructor sources")
  for (pin in s$source_files) {
    q(file.exists(pin$path) && isTRUE(file.info(pin$path)$size == as.numeric(pin$size_bytes)) &&
      identical(gnpc_hash_file(pin$path), pin$sha256), "source pin changed")
    rel <- substring(pin$path, nchar(root) + 2L)
    q(identical(git(c("hash-object", "--no-filters", "--", rel)),
      git(c("rev-parse", paste0(s$source_commit, ":", rel)))),
      "source file differs from committed blob")
  }
  invisible(root)
}

gnpc_main <- function(args = commandArgs(TRUE)) {
  q <- gnpc_require
  q(length(args) == 5L && identical(args[c(1L, 3L, 5L)],
    c("--purpose", "--sha256", "--execute")),
    "usage: --purpose FILE --sha256 SHA256 --execute")
  purpose <- normalizePath(args[2L], mustWork = TRUE)
  q(requireNamespace("jsonlite", quietly = TRUE), "jsonlite is required")
  q(gnpc_hex(args[4L], 64L) && identical(gnpc_hash_file(purpose), args[4L]),
    "external purpose hash mismatch")
  s <- jsonlite::read_json(purpose, simplifyVector = FALSE)
  gnpc_validate_purpose(s)
  root <- gnpc_validate_source(s)
  q(!startsWith(purpose, paste0(root, "/")), "purpose must be outside the source tree")
  expiry <- as.POSIXct(s$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  q(!is.na(expiry) && expiry > Sys.time(), "purpose is expired")
  out <- s$output_root
  q(startsWith(out, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    dir.exists(dirname(out)) && system2("/usr/bin/git",
      c("check-ignore", "--quiet", "--", out)) == 0L,
    "output must be fresh and ignored")
  pin <- s$config
  q(file.exists(pin$path) && isTRUE(file.info(pin$path)$size == as.numeric(pin$size_bytes)) &&
    identical(gnpc_hash_file(pin$path), pin$sha256), "config pin failed before read")
  q(dir.create(out), "could not create exclusive output directory")
  config <- readRDS(pin$path)
  q(identical(gnpc_hash_file(pin$path), pin$sha256), "config changed after read")
  export <- gnpc_extract_config(config)
  q(identical(export$task_id, s$expected$task_id) &&
    identical(export$posterior_target_sha256, s$expected$posterior_target_sha256) &&
    gnpc_hex(export$declared_prior_sha256, 64L),
    "config task, target, or declared prior identity differs from purpose")
  receipt <- list(
    schema_version = "glofas_native_prior_config_read_receipt_v1",
    status = "ONE_CONFIG_PRIOR_EXPORTED_NO_MODEL_RUN",
    purpose_sha256 = args[4L], source_commit = s$source_commit,
    source_tree = s$source_tree, config = pin,
    read_accounting = list(RDS_deserializations = 1L,
      deserialization_bytes = pin$size_bytes, hash_bytes = 2 * pin$size_bytes),
    future_truth_read = FALSE, design_reads = 0L, fit_reads = 0L,
    model_runs = 0L, publication_authorized = FALSE,
    export = export
  )
  bytes <- charToRaw(jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null",
    digits = 17, pretty = TRUE))
  q(length(bytes) <= s$read_budget$max_output_bytes, "receipt exceeds output budget")
  writeBin(bytes, file.path(out, "NATIVE_PRIOR_CONFIG_READ_RECEIPT.json"))
  manifest <- data.frame(relative_path = "NATIVE_PRIOR_CONFIG_READ_RECEIPT.json",
    size_bytes = file.info(file.path(out, "NATIVE_PRIOR_CONFIG_READ_RECEIPT.json"))$size,
    sha256 = gnpc_hash_file(file.path(out, "NATIVE_PRIOR_CONFIG_READ_RECEIPT.json")),
    stringsAsFactors = FALSE)
  utils::write.csv(manifest, file.path(out, "artifact_manifest.csv"), row.names = FALSE)
  cat("GLOFAS_NATIVE_PRIOR_CONFIG_READ_COMPLETE_NO_MODEL_RUN\n")
  invisible(receipt)
}

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
if (sys.nframe() == 0L) gnpc_main()
