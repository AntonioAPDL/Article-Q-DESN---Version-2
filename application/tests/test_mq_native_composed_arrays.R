# Complete temporary three-DLL build and generated-only composed path checks.
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
    normalizePath(file.path(dirname(f), "../.."), mustWork = TRUE)
  }
  setwd(root)
  for (f in c("00_packages.R", "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R", "latent_path_design.R",
      "joint_qdesn_pure_recursive_campaign.R", "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R"))
    source(file.path("application/R", f), local = FALSE)
  for (f in c("integrated_quantile_mq_batch.R", "mq_forecast_array_methods.R", "mq_native_key_hash.R",
      "mq_isoreg_batch.R", "mq_native_event_inverse.R", "mq_native_composed_arrays.R")) source(file.path("scripts", f), local = FALSE)
  `%||%` <- function(a, b) if (is.null(a)) b else a
  mqb_tau <- c(.05, .10, .25, .50, .75, .90, .95); mqb_hash <- strrep("a", 64L)
  ast <- parse(file = "application/tests/test_integrated_quantile_mq_batch.R")
  at <- which(vapply(ast, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("mqb_fixture")), logical(1L)))
  stopifnot(length(at) == 1L); eval(ast[[at]])
  checks <- 0L; ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE)}
  reject <- function(expr) ok(inherits(tryCatch({force(expr); NULL}, error = function(e) e), "error"))
  bits <- function(a, b) identical(a, b, num.eq = FALSE)
  receipt <- Sys.getenv("MQC_RECEIPT_ROOT", unset = "")
  if (!nzchar(receipt)) receipt <- tempfile("mq_composed_generated_receipt_")
  stopifnot(!file.exists(receipt), dir.create(receipt))
  build <- tempfile("mq_composed_generated_build_"); stopifnot(dir.create(build))
  roots <- c(build, receipt)
  output_check <- function() {
    files <- unlist(lapply(roots, list.files, full.names = TRUE, recursive = TRUE))
    stopifnot(sum(file.info(files)$size) < 64 * 1024^2)
  }
  original_sources <- mqc_source_pins()
  sourced_paths <- unique(c(file.path("application/R", c("00_packages.R", "joint_qvp_qdesn.R",
    "joint_exqdesn_exact_structured_inference.R", "latent_path_design.R",
    "joint_qdesn_pure_recursive_campaign.R", "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R")),
    file.path("scripts", c("integrated_quantile_mq_batch.R", "mq_forecast_array_methods.R", "mq_native_key_hash.R",
      "mq_isoreg_batch.R", "mq_native_event_inverse.R", "mq_native_composed_arrays.R")),
    "application/tests/test_integrated_quantile_mq_batch.R", "application/tests/test_mq_native_composed_arrays.R",
    names(original_sources)))
  all_source_hashes <- tools::sha256sum(sourced_paths)
  before_body <- deparse(body(app_iqf_mqb_paths_context), width.cutoff = 500L)
  before_formals <- formals(app_iqf_mqb_paths_context)
  before_environment <- environment(app_iqf_mqb_paths_context)
  ok(mqc_body_check())
  ok(mqc_body_check(compiler::cmpfun(app_iqf_mqb_paths_context), compiler::cmpfun(mqc_paths_context)))
  wrong <- mqc_paths_context; body(wrong)[[2L]] <- quote(invisible(TRUE)); reject(mqc_body_check(variant = wrong))
  wrong <- app_iqf_mqb_paths_context; formals(wrong)$include_trace <- TRUE; reject(mqc_body_check(reference = wrong))
  changed <- function(kind) {
    copy <- mqc_paths_context; b <- as.list(body(copy))
    if (kind == "guard") b[[2L]][[3L]] <- quote(NULL) else if (kind %in% c("namespace", "ids")) {
      at <- which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
        identical(x[[2L]], as.name("uniforms")), logical(1L)))
      b[[at]][[3L]][[if (kind == "namespace") 3L else 6L]] <-
        if (kind == "namespace") quote("wrong_namespace") else quote(rev(inner_ids))
    } else {
      at <- which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("for")), logical(1L)))
      loop <- as.list(b[[at]][[4L]])
      qi <- which(vapply(loop, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
        identical(x[[2L]], as.name("q")), logical(1L)))
      loop[[qi]][[3L]][[2L]] <- quote(mu * 0); b[[at]][[4L]] <- as.call(loop)
    }
    body(copy) <- as.call(b); copy
  }
  for (kind in c("guard", "namespace", "ids", "mu")) reject(mqc_body_check(variant = changed(kind)))
  old_env <- Sys.getenv(c("R_MAKEVARS_USER", "R_MAKEVARS_SITE", "MAKEFLAGS"), unset = NA_character_)
  restore <- function() for (n in names(old_env)) {
    if (is.na(old_env[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old_env[[n]]), n))
  }
  on.exit(restore(), add = TRUE)
  makevars <- file.path(build, "controlled.Makevars")
  native_lib <- normalizePath(R.home("lib"), mustWork = TRUE)
  writeLines(c("CC = /usr/bin/gcc", "CFLAGS = -O2 -fno-fast-math -ffp-contract=off",
    "PKG_CFLAGS = -fno-fast-math -ffp-contract=off", paste0("PKG_LIBS = -Wl,-rpath,", native_lib, " -lcrypto")), makevars)
  Sys.setenv(R_MAKEVARS_USER = makevars, R_MAKEVARS_SITE = "/dev/null", MAKEFLAGS = "-j1")
  names <- c(key = "mq_key_hash", isotonic = "mq_isoreg_batch", inverse = "mq_event_inverse")
  dlls <- logs <- list()
  for (name in names(names)) {
    stem <- names[[name]]; path <- file.path(build, paste0(stem, ".c"))
    stopifnot(file.copy(file.path("scripts/native", paste0(stem, ".c")), path))
    wd <- getwd(); setwd(build)
    log <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "--preclean", basename(path)), stdout = TRUE, stderr = TRUE)
    setwd(wd); cat(paste(log, collapse = "\n"), "\n")
    ok(is.null(attr(log, "status"))); ok(any(grepl("-ffp-contract=off", log, fixed = TRUE)))
    ok(any(grepl(paste0("-Wl,-rpath,", native_lib), log, fixed = TRUE)))
    so <- normalizePath(file.path(build, paste0(stem, .Platform$dynlib.ext)), mustWork = TRUE)
    dlls[[name]] <- list(path = so, sha256 = unname(tools::sha256sum(so))); logs[[name]] <- log
    output_check()
  }
  restore()
  reject(mqc_load(dlls)); candidate <- mqc_load(dlls, "generated_fixture_only")
  ok(!candidate$C_ABI_qualified && !candidate$source_runtime_authenticated && !candidate$production_authorized)
  proof <- app_iqf_mqb_rng_reference()
  set.seed(20261102); seed <- .Random.seed; kind <- RNGkind()
  rng_same <- function() ok(identical(.Random.seed, seed) && identical(RNGkind(), kind))
  fields <- c("paths", "response", "ordered_quantiles", "trace", "inner_ids", "draw_id", "origin_id",
    "coupling", "rng_namespace", "outer_conditioning", "production_authorized", "numerical_accuracy_qualified", "raw_coherence")
  fixture_rows <- list()
  for (config in list(list(D = 1L, activation = "identity", projection = FALSE, standardize = TRUE),
      list(D = 2L, activation = "tanh", projection = TRUE, standardize = TRUE),
      list(D = 3L, activation = "relu", projection = TRUE, standardize = FALSE))) {
    f <- do.call(mqb_fixture, config); f$origins <- f$origins["o8"]; f$origins$o8$H <- 30L
    adapter <- do.call(app_iqf_mq_batch_adapter, c(f, list(inner_paths = 2048L, batch_size = 128L,
      rng_mode = "r46_first_step_qualified", rng_proof = proof)))
    for (draw in f$posterior$draw_ids) {
      ids <- c(1L, 7L, 17L, 3L, 19L, 2048L)
      old <- app_iqf_mq_batch_arrays(adapter, draw, "o8", ids, include_trace = TRUE)
      new <- mqc_arrays(candidate, adapter, draw, "o8", ids, include_trace = TRUE, scope = "generated_fixture_only")
      for (field in fields) ok(bits(old[[field]], new[[field]]))
      for (h in 1:30) ok(bits(mqc_inverse(candidate, new$ordered_quantiles[, , h], f$tau, f$tau,
        scope = "generated_fixture_only"), app_iqf_mq_matrix_inverse(old$ordered_quantiles[, , h], f$tau, f$tau)))
      full_u <- mqk_candidate_uniforms(candidate$key, f$rng_namespace, draw, "o8", ids, 30L, proof)
      parts_u <- rbind(mqk_candidate_uniforms(candidate$key, f$rng_namespace, draw, "o8", ids[1:2], 30L, proof),
        mqk_candidate_uniforms(candidate$key, f$rng_namespace, draw, "o8", ids[3:6], 30L, proof))
      ok(bits(full_u, parts_u))
      for (part in list(ids[1:2], ids[3:6])) {
        a <- app_iqf_mq_batch_arrays(adapter, draw, "o8", part, include_trace = TRUE)
        b <- mqc_arrays(candidate, adapter, draw, "o8", part, include_trace = TRUE, scope = "generated_fixture_only")
        for (field in fields) ok(bits(a[[field]], b[[field]]))
      }
      fixture_rows[[length(fixture_rows) + 1L]] <- data.frame(D = config$D, draw_id = draw,
        horizons = 30L, levels = 7L, paths = length(ids), separate_draw_target = TRUE, exact_parity = TRUE)
      rng_same()
    }
  }
  reject(mqc_arrays(candidate, adapter, f$posterior$draw_ids[1L], "o8", 1:2))
  bad <- adapter; bad$rng_mode <- "native_scoped"
  reject(mqc_arrays(candidate, bad, f$posterior$draw_ids[1L], "o8", 1:2, scope = "generated_fixture_only"))
  reject(mqc_arrays(candidate, adapter, f$posterior$draw_ids[1L], "o8", c(1L, 1L), scope = "generated_fixture_only"))
  reject(mqc_inverse(candidate, matrix(0, 1L, 7L), f$tau, f$tau))

  # One generated staged-kernel benchmark: fixed B1024, H30, original 128-ID
  # partitions, separate training/validation IDs, one declared parameter draw.
  f <- mqb_fixture(D = 2L, activation = "tanh", projection = TRUE, standardize = TRUE)
  f$origins <- f$origins["o8"]; f$origins$o8$H <- 30L
  adapter <- do.call(app_iqf_mq_batch_adapter, c(f, list(inner_paths = 2048L, batch_size = 128L,
    rng_mode = "r46_first_step_qualified", rng_proof = proof)))
  draw <- f$posterior$draw_ids[1L]; timings <- list()
  run <- function(method) {
    whole <- proc.time()
    timed <- function(stage, work) {
      start <- proc.time(); value <- force(work); elapsed <- proc.time() - start
      timings[[length(timings) + 1L]] <<- data.frame(method = method, stage = stage,
        user_cpu_s = unname(elapsed["user.self"]), system_cpu_s = unname(elapsed["sys.self"]),
        wall_s = unname(elapsed["elapsed"]), paths_per_stage = 1024L, partition = 128L, horizons = 30L, draw_id = draw)
      value
    }
    generate <- function(ids) {
      output <- array(NA_real_, c(length(ids), 7L, 30L))
      for (first in seq.int(1L, length(ids), by = 128L)) {
        at <- first:min(length(ids), first + 127L)
        z <- if (method == "reference") app_iqf_mq_batch_arrays(adapter, draw, "o8", ids[at], collect_coherence = FALSE) else
          mqc_arrays(candidate, adapter, draw, "o8", ids[at], collect_coherence = FALSE, scope = "generated_fixture_only")
        output[at, , ] <- z$ordered_quantiles
      }
      output
    }
    training <- timed("training_paths", generate(1:1024))
    quantiles <- timed("inversion", vapply(1:30, function(h) {
      if (method == "reference") app_iqf_mq_matrix_inverse(training[, , h], f$tau, f$tau) else
        mqc_inverse(candidate, training[, , h], f$tau, f$tau, scope = "generated_fixture_only")
    }, numeric(7L)))
    validation <- timed("validation_paths", generate(1025:2048))
    cdf <- timed("validation_CDF", vapply(1:30, function(h) {
      endpoints <- as.vector(rbind(quantiles[, h] - pmax(.01, .01 * abs(quantiles[, h])),
        quantiles[, h] + pmax(.01, .01 * abs(quantiles[, h]))))
      if (method == "reference") app_iqf_mq_matrix_cdf(endpoints, validation[, , h], f$tau) else
        mqc_cdf(candidate, endpoints, validation[, , h], f$tau, scope = "generated_fixture_only")
    }, numeric(14L)))
    elapsed <- proc.time() - whole
    timings[[length(timings) + 1L]] <<- data.frame(method = method, stage = "whole_staged_kernel",
      user_cpu_s = unname(elapsed["user.self"]), system_cpu_s = unname(elapsed["sys.self"]),
      wall_s = unname(elapsed["elapsed"]), paths_per_stage = 1024L, partition = 128L, horizons = 30L, draw_id = draw)
    list(training = training, quantiles = quantiles, validation = validation, cdf = cdf)
  }
  reference <- run("reference"); composed <- run("composed")
  for (field in names(reference)) ok(bits(reference[[field]], composed[[field]]))
  rng_same()
  ok(identical(before_body, deparse(body(app_iqf_mqb_paths_context), width.cutoff = 500L)))
  ok(identical(before_formals, formals(app_iqf_mqb_paths_context)))
  ok(identical(before_environment, environment(app_iqf_mqb_paths_context)))
  ok(identical(unname(tools::sha256sum(names(original_sources))), unname(original_sources)))
  ok(identical(all_source_hashes, tools::sha256sum(sourced_paths)))
  maps <- readLines("/proc/self/maps", warn = FALSE)
  libR <- normalizePath(file.path(native_lib, "libR.so"), mustWork = TRUE)
  map_paths <- sub("^(?:\\S+\\s+){5}", "", maps, perl = TRUE)
  libR_paths <- unique(grep("/libR\\.so( \\(deleted\\))?$", map_paths, value = TRUE))
  ok(identical(libR_paths, libR)); ok(any(grepl("libcrypto", maps, fixed = TRUE)))
  loaded <- getLoadedDLLs()
  dll_paths <- vapply(loaded, function(x) x[["path"]], "")
  for (x in dlls) ok(x$path %in% dll_paths && identical(unname(tools::sha256sum(x$path)), x$sha256))
  mapped_files <- unique(grep("/(libR\\.so|libcrypto|mq_(key_hash|isoreg_batch|event_inverse)\\.so)", map_paths, value = TRUE))
  ok(length(mapped_files) >= 5L && all(file.exists(mapped_files)) &&
    !any(grepl("(deleted)", mapped_files, fixed = TRUE)))
  bindings <- data.frame(path = mapped_files, sha256 = unname(tools::sha256sum(mapped_files)))
  write.csv(do.call(rbind, timings), file.path(receipt, "generated_stage_timings.csv"), row.names = FALSE)
  write.csv(do.call(rbind, fixture_rows), file.path(receipt, "generated_parity_cases.csv"), row.names = FALSE)
  writeLines(maps, file.path(receipt, "actual_process_maps.txt"))
  write.csv(data.frame(name = names(dll_paths), path = dll_paths), file.path(receipt, "actual_loaded_DLLs.csv"), row.names = FALSE)
  write.csv(bindings, file.path(receipt, "actual_native_code_mappings.csv"), row.names = FALSE)
  write.csv(data.frame(path = sourced_paths, size_bytes = as.numeric(file.info(sourced_paths)$size),
    sha256 = unname(all_source_hashes)), file.path(receipt, "all_sourced_code_bindings.csv"), row.names = FALSE)
  jsonlite::write_json(list(status = "GENERATED_COMPOSITION_PARITY_NOT_NATIVE_RUNTIME_QUALIFICATION",
    checks = checks, R = as.character(getRversion()), digest = as.character(utils::packageVersion("digest")),
    compiler = system2("/usr/bin/gcc", "--version", stdout = TRUE), compiler_logs = logs,
    controlled_Makevars = readLines(makevars), native_R_libdir = native_lib, dlls = dlls,
    all_sourced_code_sha256 = as.list(all_source_hashes),
    source_pins = as.list(original_sources), frozen_commits = candidate$frozen_commits,
    source_runtime_authenticated = FALSE, C_ABI_qualified = FALSE, authentic_speedup_claimed = FALSE,
    parameter_draws_pooled = FALSE, production_authorized = FALSE, actual_scientific_reads = 0L),
    file.path(receipt, "GENERATED_COMPOSITION_RECEIPT.json"), auto_unbox = TRUE, pretty = TRUE, digits = 17)
  output_check()
  cat(sprintf("MQ_COMPOSED_GENERATED_PASS checks=%d receipt=%s production_authorized=FALSE\n", checks, receipt))
  print(do.call(rbind, timings), row.names = FALSE)
})
