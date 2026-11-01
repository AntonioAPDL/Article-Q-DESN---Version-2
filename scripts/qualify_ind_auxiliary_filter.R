#!/usr/bin/env Rscript
# Bounded training-only filter probe, not an accuracy or production certificate.
ind_caf_qualify <- function(args = commandArgs(TRUE)) {
  if (identical(args, "--help")) {
    cat("Usage: Rscript scripts/qualify_ind_auxiliary_filter.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  stopifnot(length(args) == 5L, args[[1L]] == "--contract", args[[3L]] == "--sha256", args[[5L]] == "--execute")
  source("scripts/ind_conditional_filter_replay.R")
  source("scripts/ind_conditional_auxiliary_filter.R")
  require <- ind_cfr_require
  pin <- function(x) {
    require(is.list(x) && is.character(x$path) && length(x$path) == 1L &&
      startsWith(x$path, "/") && !grepl("(^|/)\\.\\.(/|$)", x$path) &&
      file.exists(x$path) && !isTRUE(file.info(x$path)$isdir) &&
      identical(unname(Sys.readlink(x$path)), "") &&
      identical(as.numeric(file.info(x$path)$size), as.numeric(x$size_bytes)) &&
      is.character(x$sha256) && length(x$sha256) == 1L &&
      grepl("^[a-f0-9]{64}$", x$sha256) &&
      identical(unname(tools::sha256sum(x$path)), x$sha256), "exact input/source binding")
    x$path
  }
  contract_path <- normalizePath(args[[2L]], mustWork = TRUE)
  require(file.info(contract_path)$size <= 1024^2 &&
    identical(unname(tools::sha256sum(contract_path)), args[[4L]]),
    "bounded external purpose contract")
  spec <- jsonlite::read_json(contract_path, simplifyVector = FALSE)
  ints <- function(x) as.integer(unlist(x, use.names = FALSE))
  exact_integers <- function(x, expected) {
    values <- unlist(x, use.names = FALSE)
    is.numeric(values) && length(values) == length(expected) &&
      all(is.finite(values)) && all(values == expected)
  }
  require(identical(spec$schema_version, "ind_auxiliary_filter_qualification_v1") &&
    isTRUE(spec$allow_qualification) && identical(spec$allow_refit, FALSE) &&
    identical(spec$allow_forecast, FALSE) && identical(spec$allow_production, FALSE) &&
    identical(spec$posterior_column, 1L) && spec$observed_prefix_length == 500L &&
    exact_integers(spec$particle_resolutions, c(32L,64L,128L)) &&
    exact_integers(spec$seeds, c(71421L,71422L)) &&
    exact_integers(spec$checkpoint_indices, c(100L,250L,500L)) &&
    identical(spec$ess_fraction, .5), "fixed prospective AL training-only probe")
  require(is.list(spec$limits) && spec$limits$cpu_seconds == 300 &&
    spec$limits$wall_term_seconds == 299 && spec$limits$wall_kill_after_seconds == 1 &&
    spec$limits$address_space_bytes == 16*1024^3 &&
    spec$limits$output_bytes == 8*1024^2,
    "unchanged externally enforced finite qualification limits")
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
  require(!is.na(expiry) && expiry > Sys.time() + 300 &&
    as.character(getRversion()) == "4.6.0", "pinned R and complete bounded purpose lifetime")
  require(unname(Sys.info()[["nodename"]]) %in% c("muscat", "muscat.be.ucsc.edu") &&
    identical(Sys.getenv("LD_PRELOAD"), "") &&
    all(Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")) == "1"),
    "local one-thread bundled numerical environment")
  blas <- unname(extSoftVersion()[["BLAS"]])
  require(is.character(blas) && length(blas) == 1L &&
    identical(normalizePath(blas, mustWork = TRUE),
      normalizePath(file.path(R.home("lib"), "libRblas.so"), mustWork = TRUE)),
    "R's bundled BLAS required, not a replacement library")
  status <- readLines("/proc/self/status", warn = FALSE)
  affinity <- trimws(sub("^Cpus_allowed_list:", "", grep("^Cpus_allowed_list:", status, value = TRUE)))
  require(identical(affinity, "26"), "separate administrative CPU26, not fitting cores")
  limits <- readLines("/proc/self/limits", warn = FALSE)
  finite_limit <- function(prefix, ceiling) {
    x <- grep(paste0("^", prefix), limits, value = TRUE)
    if (length(x) != 1L) return(FALSE)
    z <- suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^", prefix), "", x)), "[[:space:]]+")[[1L]][1:2]))
    all(is.finite(z) & z > 0 & z <= ceiling)
  }
  require(finite_limit("Max cpu time", 300) && finite_limit("Max address space", 16*1024^3) &&
    finite_limit("Max file size", 8*1024^2), "finite qualification process limits")
  require(is.list(spec$source_files) && length(spec$source_files) >= 3L,
    "complete executable-source pins required")
  source_paths <- vapply(spec$source_files, pin, character(1L))
  require(all(startsWith(source_paths, paste0(root, "/"))) &&
    all(file.path(root, c("scripts/qualify_ind_auxiliary_filter.R",
      "scripts/ind_conditional_filter_replay.R", "scripts/ind_conditional_auxiliary_filter.R")) %in% source_paths) &&
    !anyDuplicated(source_paths), "qualification entry and both kernel sources must be pinned")
  require(spec$native_cpp$sha256 == ind_cfr_policy()$source_sha256, "authentic C++ policy source")
  pin(spec$native_cpp)
  require(!"exdqlm" %in% loadedNamespaces(), "no installed exdqlm namespace substitution")
  output <- spec$output_root
  require(is.character(output) && length(output) == 1L &&
    startsWith(output, paste0(root, "/local_trackers/")) && !file.exists(output) &&
    !grepl("(^|/)\\.\\.(/|$)", output), "fresh ignored output namespace required")
  parent <- dirname(output)
  require(dir.exists(parent) && identical(normalizePath(parent, mustWork = TRUE), parent),
    "precreated real output parent required")
  ignored <- system2("git", c("check-ignore", "--quiet", "--", shQuote(output)))
  require(identical(ignored, 0L), "qualification artifacts must be ignored by Git")
  require(dir.create(output), "fresh output creation failed")
  write_json <- function(value, name) {
    target <- file.path(output, name); temporary <- paste0(target, ".tmp")
    jsonlite::write_json(value, temporary, pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null")
    require(file.rename(temporary, target), "atomic qualification receipt write")
  }
  progress <- function(phase, ...) write_json(list(
    schema_version = "ind_auxiliary_qualification_progress_v1", phase = phase,
    timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    source_commit = spec$source_commit, purpose_contract_sha256 = args[[4L]],
    production_authorized = FALSE, details = list(...)), "progress.json")
  manifest <- function() {
    files <- list.files(output, full.names = TRUE)
    files <- files[basename(files) != "artifact_manifest.csv"]
    m <- data.frame(relative_path = basename(files), size_bytes = unname(file.info(files)$size),
      sha256 = unname(tools::sha256sum(files)))
    require(sum(m$size_bytes) < 8*1024^2 - 65536,
      "finite qualification output budget including manifest reserve")
    write.csv(m, file.path(output, "artifact_manifest.csv"), row.names = FALSE)
    require(sum(file.info(list.files(output, full.names=TRUE))$size) <= 8*1024^2,
      "complete qualification artifact budget")
    invisible(m)
  }
  # Restore the caller's exact RNG state/kinds, including absence of a seed.
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  old_kind <- RNGkind()
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  progress("PROBE_ADMITTED_PROTECTED_FIT_LOADING")
  tryCatch({
    path <- pin(spec$protected_fit)
    protected <- readRDS(path)
    pin(spec$protected_fit)
    fit <- protected$fit
    require(is.list(fit) && isTRUE(fit$dqlm.ind) &&
      identical(protected$source_commit, spec$fit_source_commit), "original AL fit/source identity")
    n <- spec$observed_prefix_length; model <- fit$model
    sigma <- as.numeric(fit$samp.sigma)
    require(is.numeric(fit$samp.sigma) && length(sigma) >= 1L &&
      all(is.finite(sigma)) && all(sigma > 0) && is.matrix(fit$samp.vts) &&
      nrow(fit$samp.vts) == n && ncol(fit$samp.vts) == length(sigma) &&
      spec$posterior_column <= length(sigma), "native paired-column geometry and scale support")
    j <- spec$posterior_column
    require(all(is.finite(fit$samp.vts[,j])) && all(fit$samp.vts[,j] > 0),
      "selected original paired augmentation support")
    require(is.numeric(fit$y) && length(fit$y) == n && all(is.finite(fit$y)) &&
      is.numeric(fit$p0) && length(fit$p0) == 1L && is.finite(fit$p0) &&
      fit$p0 > 0 && fit$p0 < 1 && is.list(model), "native training-only response and AL level")
    p <- length(model$m0)
    require(is.matrix(model$FF) && identical(dim(model$FF), c(p,n)) &&
      is.numeric(model$FF) && all(is.finite(model$FF)) &&
      is.numeric(model$GG) && all(is.finite(model$GG)) &&
      (identical(dim(model$GG),c(p,p)) || identical(dim(model$GG),c(p,p,n))) &&
      is.numeric(model$m0) && p >= 1L && all(is.finite(model$m0)),
      "original training-only feature and evolution geometry")
    native_columns <- length(sigma)
    require(is.numeric(fit$samp.theta) &&
      identical(dim(fit$samp.theta), c(p,n,native_columns)),
      "original paired native state-column geometry")
    input <- list(y = as.numeric(fit$y), FF = as.matrix(model$FF), GG = model$GG,
      m0 = as.numeric(model$m0), C0 = as.matrix(model$C0),
      df_mat = ind_cfr_discount_matrix(fit$df, fit$dim.df, p),
      observed_prefix_length = n, p0 = fit$p0, sigma = sigma[j])
    ind_caf_psd(input$C0, p, 1e-10, "original initial covariance")
    sigma_text <- sprintf("%.17g", sigma)
    require(identical(as.numeric(sigma_text), sigma), "lossless native scalar catalog formatting")
    catalog <- data.frame(native_column = seq_along(sigma), sigma = sigma_text,
      catalog_role = "columns_present_not_campaign_draw_selection")
    write.csv(catalog, file.path(output, "native_scale_columns_present.csv"), row.names = FALSE)
    rm(protected, fit, model, sigma, sigma_text, catalog); gc(FALSE)
    # Only these explicitly training-only fields reach the kernels. Protected
    # config/data/task future values are never passed through or consulted.
    parameter_id <- paste0(spec$fit_source_commit, ":native_column:", j)
    resolutions <- ints(spec$particle_resolutions); seeds <- ints(spec$seeds)
    checkpoints <- ints(spec$checkpoint_indices); maximum_N <- max(resolutions)
    rows <- list(); runs <- list(); stream_receipts <- list(); row_index <- 0L
    RNGkind("Mersenne-Twister", "Inversion", "Rejection")
    progress("TRAINING_INPUT_AUTHENTICATED", native_columns_present = native_columns,
      selected_native_column = j, training_rows = n, states = p)
    for (seed in seeds) {
      set.seed(seed)
      rng_before <- .Random.seed
      # R fills columns consecutively: all maximum_N particles for time 1,
      # then time 2. Smaller resolutions use the same per-time row prefix.
      u_v <- matrix(stats::runif(n*maximum_N), nrow = maximum_N, ncol = n)
      u_resample <- stats::runif(n)
      rng_after <- .Random.seed
      stream_name <- sprintf("uniform_stream_seed_%d.rds", seed)
      saveRDS(list(seed = seed, RNGkind = RNGkind(), training_rows = n,
        maximum_particles = maximum_N, order = "time_major_maximum_particle_prefix",
        u_v = u_v, u_resample = u_resample, RNGstate_before = rng_before,
        RNGstate_after = rng_after), file.path(output, stream_name), compress = TRUE)
      stream_receipts[[as.character(seed)]] <- list(seed = seed, RNGkind = RNGkind(),
        uniform_draw_count = n*maximum_N+n, file = stream_name,
        sha256 = unname(tools::sha256sum(file.path(output,stream_name))))
      for (N in resolutions) {
        progress("FILTER_PROBE_RUNNING", seed = seed, particles = N,
          completed_runs = length(runs), total_runs = length(seeds)*length(resolutions))
        started <- proc.time()
        auxiliary <- ind_caf_prior_auxiliaries("al", input$p0, input$sigma,
          u_v[seq_len(N),,drop=FALSE])
        result <- ind_caf_filter(input$y, input$FF, input$GG, input$m0, input$C0,
          input$df_mat, auxiliary, input$observed_prefix_length, parameter_id,
          checkpoints, u_resample, ess_fraction = spec$ess_fraction)
        timing <- proc.time() - started
        require(identical(.Random.seed, rng_after), "filter changed caller-supplied scientific RNG stream")
        moments <- lapply(result$checkpoints, function(cp) {
          w <- cp$weights
          mu <- as.numeric(cp$mean %*% w)
          centered <- cp$mean - mu
          covariance <- matrix(0, p, p)
          for (k in seq_along(w)) covariance <- covariance + w[k] *
            (matrix(cp$covariance[,,k],p,p) + tcrossprod(centered[,k]))
          ind_caf_psd(covariance, p, 1e-10, "checkpoint total mixture covariance")
          list(observed_prefix_length = cp$observed_prefix_length,
            mean = mu, covariance = covariance,
            covariance_includes_within_and_between_components = TRUE)
        })
        summary <- list(seed = seed, particles = N, CPU_seconds = sum(timing[1:2]),
          elapsed_seconds = unname(timing[["elapsed"]]),
          minimum_ESS = min(result$ESS), median_ESS = stats::median(result$ESS),
          resampling_count = sum(result$resampled), checkpoint_mixture_moments = moments)
        result$qualification_summary <- summary
        name <- sprintf("filter_seed_%d_particles_%03d.rds", seed, N)
        saveRDS(result, file.path(output, name), compress = TRUE)
        key <- sprintf("seed_%d_particles_%03d", seed, N)
        runs[[key]] <- c(summary, list(file = name,
          sha256 = unname(tools::sha256sum(file.path(output,name)))))
        for (cp in moments) {
          row_index <- row_index + 1L
          rows[[row_index]] <- data.frame(seed = seed, particles = N,
            observed_prefix_length = cp$observed_prefix_length,
            CPU_seconds = sum(timing[1:2]), elapsed_seconds = unname(timing[["elapsed"]]),
            minimum_ESS = min(result$ESS), median_ESS = stats::median(result$ESS),
            resampling_count = sum(result$resampled),
            weighted_mean = paste(format(cp$mean,digits=17),collapse=";"),
            total_covariance_column_major = paste(format(as.numeric(cp$covariance),digits=17),collapse=";"),
            covariance_includes_between_component_variation = TRUE,
            filter_accuracy_certified = FALSE, production_authorized = FALSE)
        }
        write.csv(do.call(rbind,rows),file.path(output,"filter_probe_summary.csv"),row.names=FALSE)
        progress("FILTER_PROBE_COMPLETED", seed = seed, particles = N,
          completed_runs = length(runs), total_runs = length(seeds)*length(resolutions))
        manifest()
        rm(auxiliary,result); gc(FALSE)
      }
    }
    for (x in spec$source_files) pin(x)
    pin(spec$protected_fit); pin(spec$native_cpp)
    require(!"exdqlm" %in% loadedNamespaces() && expiry > Sys.time(),
      "source/runtime qualification remained in scope")
    receipt <- list(schema_version = "ind_auxiliary_filter_qualification_receipt_v1",
      status = "QUALIFICATION_PROBE_COMPLETE_ACCURACY_NOT_CERTIFIED",
      source_commit = spec$source_commit, purpose_contract_sha256 = args[[4L]],
      original_fit = spec$protected_fit, original_fit_source = spec$fit_source_commit,
      native_cpp = spec$native_cpp, original_native_posterior_column = j,
      native_posterior_columns_present = native_columns,
      native_column_catalog_role = "columns_present_not_campaign_draw_selection",
      historical_metric_row_mapping_inferred = FALSE,
      training_rows = n, observed_checkpoint_indices = checkpoints, states = p,
      parameter_id = parameter_id, likelihood = "AL", p0 = input$p0, sigma = input$sigma,
      random_streams = stream_receipts, filter_probes = runs,
      scientific_uniform_draw_count = length(seeds)*(n*maximum_N+n),
      RNG_caller_state_restored_on_exit = TRUE,
      nested_resolution_rule = "time_major_maximum_particle_rows_1_through_N",
      filtering_weights = "normalize_within_the_one_fixed_native_parameter_only",
      future_response_values_used = 0L, parameter_weights_updated = FALSE,
      filter_accuracy_certified = FALSE, forecast_accuracy_certified = FALSE,
      numerical_threshold_selected_after_probe = FALSE,
      new_model_fits = 0L, forecasts_generated = 0L, scoring_cases = 0L,
      production_authorized = FALSE,
      numerical_environment = list(R = as.character(getRversion()), BLAS = blas,
        LD_PRELOAD = Sys.getenv("LD_PRELOAD"), logical_cpus = affinity,
        OMP_NUM_THREADS = Sys.getenv("OMP_NUM_THREADS"),
        OPENBLAS_NUM_THREADS = Sys.getenv("OPENBLAS_NUM_THREADS"),
        MKL_NUM_THREADS = Sys.getenv("MKL_NUM_THREADS")),
      finite_external_limits = spec$limits,
      scope = "one_AL_training_parameter_cost_and_stability_probe_not_campaign_enrollment")
    write_json(receipt, "qualification.json")
    progress("QUALIFICATION_PROBE_COMPLETE_ACCURACY_NOT_CERTIFIED", completed_runs = length(runs))
    manifest()
    cat("QUALIFICATION_PROBE_COMPLETE_ACCURACY_NOT_CERTIFIED runs=6 training_rows=500 fits=0 forecasts=0 production=FALSE\n")
    invisible(receipt)
  }, error = function(error) {
    try(write_json(list(schema_version = "ind_auxiliary_filter_qualification_failure_v1",
      status = "QUALIFICATION_PROBE_FAILED_NOT_PRODUCTION", error = conditionMessage(error),
      source_commit = spec$source_commit, purpose_contract_sha256 = args[[4L]],
      production_authorized = FALSE, filter_accuracy_certified = FALSE), "failure.json"), silent = TRUE)
    try(progress("QUALIFICATION_PROBE_FAILED_NOT_PRODUCTION", error = conditionMessage(error)), silent = TRUE)
    try(manifest(), silent = TRUE)
    stop(error)
  })
}
if (sys.nframe() == 0L) ind_caf_qualify()
