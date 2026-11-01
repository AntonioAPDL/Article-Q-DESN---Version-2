#!/usr/bin/env Rscript
# One native conditional-forward parity check; no fit or forecast is run.
ind_cfr_qualify <- function(args = commandArgs(TRUE)) {
  if (identical(args, "--help")) {
    cat("Usage: Rscript scripts/qualify_ind_conditional_filter.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  stopifnot(length(args) == 5L, args[[1L]] == "--contract", args[[3L]] == "--sha256", args[[5L]] == "--execute")
  source("scripts/ind_conditional_filter_replay.R")
  require <- ind_cfr_require
  pin <- function(x) {
    require(is.list(x) && is.character(x$path) && length(x$path) == 1L && startsWith(x$path, "/") &&
      !grepl("(^|/)\\.\\.(/|$)", x$path) && file.exists(x$path) &&
      !isTRUE(file.info(x$path)$isdir) && identical(unname(Sys.readlink(x$path)), "") &&
      identical(as.numeric(file.info(x$path)$size), as.numeric(x$size_bytes)) &&
      is.character(x$sha256) && length(x$sha256) == 1L && grepl("^[a-f0-9]{64}$", x$sha256) &&
      identical(unname(tools::sha256sum(x$path)), x$sha256), "exact input/source binding")
    x$path
  }
  contract_path <- normalizePath(args[[2L]], mustWork = TRUE)
  require(file.info(contract_path)$size <= 1024^2 &&
    identical(unname(tools::sha256sum(contract_path)), args[[4L]]), "bounded external purpose contract")
  spec <- jsonlite::read_json(contract_path, simplifyVector = FALSE)
  require(identical(spec$schema_version, "ind_native_forward_qualification_v1") &&
    isTRUE(spec$allow_qualification) && identical(spec$allow_refit, FALSE) &&
    identical(spec$allow_forecast, FALSE) && identical(spec$allow_production, FALSE) &&
    identical(spec$posterior_column, 1L) && spec$observed_prefix_length == 500L,
    "one predeclared training-column qualification only")
  root <- normalizePath(getwd(), mustWork = TRUE)
  require(!startsWith(contract_path, paste0(root, "/")), "purpose contract must be outside source")
  git <- function(a) {
    z <- system2("git", c("--no-replace-objects", a), stdout = TRUE)
    require(is.null(attr(z, "status")), "Git identity check failed"); unname(z)
  }
  require(identical(git(c("rev-parse", "HEAD")), spec$source_commit) &&
    length(git(c("status", "--porcelain", "--untracked-files=normal"))) == 0L,
    "clean frozen qualification source")
  expiry <- as.POSIXct(spec$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  require(!is.na(expiry) && expiry > Sys.time() + 120 && as.character(getRversion()) == "4.6.0",
    "pinned R and complete bounded purpose lifetime")
  require(unname(Sys.info()[["nodename"]]) %in% c("muscat", "muscat.be.ucsc.edu") &&
    identical(Sys.getenv("LD_PRELOAD"), "") &&
    all(Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")) == "1"),
    "local one-thread bundled numerical environment")
  status <- readLines("/proc/self/status", warn = FALSE)
  affinity <- trimws(sub("^Cpus_allowed_list:", "", grep("^Cpus_allowed_list:", status, value = TRUE)))
  require(identical(affinity, "26"), "separate administrative CPU26, not active fitting cores")
  limits <- readLines("/proc/self/limits", warn = FALSE)
  finite_limit <- function(prefix, ceiling) {
    x <- grep(paste0("^", prefix), limits, value = TRUE)
    if (length(x) != 1L) return(FALSE)
    z <- as.numeric(strsplit(trimws(sub(paste0("^", prefix), "", x)), "[[:space:]]+")[[1L]][1:2])
    all(is.finite(z) & z > 0 & z <= ceiling)
  }
  require(finite_limit("Max cpu time", 120) && finite_limit("Max address space", 16*1024^3) &&
    finite_limit("Max file size", 32*1024^2), "finite qualification process limits")
  for (x in spec$source_files) pin(x)
  require(spec$native_cpp$sha256 == ind_cfr_policy()$source_sha256, "authentic C++ policy source")
  pin(spec$native_cpp); pin(spec$native_exports); pin(spec$native_dll)
  require(!"exdqlm" %in% loadedNamespaces(), "do not substitute the installed package namespace")
  path <- pin(spec$protected_fit)
  protected <- readRDS(path)
  pin(spec$protected_fit)
  fit <- protected$fit
  require(is.list(fit) && isTRUE(fit$dqlm.ind) && identical(protected$source_commit, spec$fit_source_commit),
    "original AL fit/source identity")
  n <- spec$observed_prefix_length; model <- fit$model
  sigma <- as.numeric(fit$samp.sigma)
  v <- as.matrix(fit$samp.vts)
  require(length(fit$y) == n && nrow(v) == n && ncol(v) == length(sigma) &&
    spec$posterior_column <= length(sigma), "native paired posterior-column geometry")
  j <- spec$posterior_column
  obs <- ind_cfr_augmentation("al", fit$p0, sigma[j], as.numeric(v[,j]))
  input <- list(y = as.numeric(fit$y), FF = as.matrix(model$FF), GG = model$GG,
    m0 = as.numeric(model$m0), C0 = as.matrix(model$C0), ex_f = obs$ex_f, ex_q = obs$ex_q,
    df_mat = ind_cfr_discount_matrix(fit$df, fit$dim.df, length(model$m0)), observed_prefix_length = n)
  rm(protected, fit, v, model); gc(FALSE)
  # Only the physically training-only input above reaches the numerical kernels.
  replay <- do.call(ind_cfr_cpp_forward, input)
  require(requireNamespace("Rcpp", quietly = TRUE), "pinned Rcpp runtime unavailable")
  set.seed(74219L); seed_before <- .Random.seed
  dll <- dyn.load(spec$native_dll$path)
  on.exit(dyn.unload(spec$native_dll$path), add = TRUE)
  entry <- getDLLRegisteredRoutines(dll)[[".Call"]][["_exdqlm_mcmc_ffbs_smooth_cpp"]]
  require(!is.null(entry) && entry$numParameters == 8L, "exact registered deterministic forward/smoother entry")
  native <- .Call(entry, input$GG, input$m0, input$C0, input$FF, input$y,
    input$ex_f, input$ex_q, input$df_mat)
  require(identical(.Random.seed, seed_before), "deterministic parity calculation changed RNG state")
  native_sfe_dim <- dim(native$standard.forecast.errors)
  if (identical(native_sfe_dim, c(n,1L))) native$standard.forecast.errors <- as.numeric(native$standard.forecast.errors)
  result <- ind_cfr_compare_native(replay, native, spec$absolute_tolerance, spec$relative_tolerance)
  require(identical(result$status, "NATIVE_FORWARD_PARITY_PASS"), "native full-time parity failed")
  for (x in spec$source_files) pin(x)
  pin(spec$protected_fit); pin(spec$native_dll)
  output <- spec$output_root
  require(startsWith(output, paste0(root, "/local_trackers/")) && !file.exists(output) &&
    !grepl("(^|/)\\.\\.(/|$)", output), "new ignored output namespace")
  require(dir.create(output, recursive = TRUE), "fresh output creation failed")
  saveRDS(input, file.path(output, "training_only_input.rds"))
  saveRDS(replay, file.path(output, "conditional_forward_replay.rds"))
  receipt <- list(schema_version = "ind_native_forward_qualification_receipt_v1", status = result$status,
    source_commit = spec$source_commit, purpose_contract_sha256 = args[[4L]],
    original_fit = spec$protected_fit, original_fit_source = spec$fit_source_commit,
    native_dll = spec$native_dll, native_cpp = spec$native_cpp,
    reference_source_version = spec$reference_source_version,
    original_native_posterior_column = j, native_posterior_columns_present = length(sigma),
    historical_metric_row_mapping_inferred = FALSE, observed_training_rows = n,
    original_native_sfe_dim = native_sfe_dim, forward_comparison = result,
    numerical_environment = list(R = as.character(getRversion()), Rcpp = as.character(utils::packageVersion("Rcpp")),
      BLAS = unname(extSoftVersion()[["BLAS"]]), LD_PRELOAD = Sys.getenv("LD_PRELOAD"),
      logical_cpus = affinity),
    conditioning = replay$conditioning, training_augmentation_integrated = FALSE,
    parameters_only_filter_qualified = FALSE, forecasts_generated = 0L, new_model_fits = 0L,
    random_draws_generated = 0L, production_authorized = FALSE,
    approximation_scope = "training_only_conditional_forward_operator_not_full_historical_posterior_target")
  jsonlite::write_json(receipt, file.path(output, "qualification.json"), pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null")
  files <- list.files(output, full.names = TRUE)
  manifest <- data.frame(relative_path = basename(files), size_bytes = unname(file.info(files)$size),
    sha256 = unname(tools::sha256sum(files)))
  require(sum(manifest$size_bytes) < 32*1024^2, "finite qualification output budget")
  write.csv(manifest, file.path(output, "artifact_manifest.csv"), row.names = FALSE)
  cat("IND_NATIVE_FORWARD_PARITY_PASS training_rows=500 new_fits=0 forecasts=0 production=FALSE\n")
  invisible(receipt)
}
if (sys.nframe() == 0L) ind_cfr_qualify()
