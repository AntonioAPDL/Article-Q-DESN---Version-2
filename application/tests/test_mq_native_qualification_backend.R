#!/usr/bin/env Rscript
# Generated fixtures only. This test cannot issue an authentic purpose.
local({
  stopifnot(length(commandArgs(trailingOnly = TRUE)) == 0L)
  filearg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else
    normalizePath(file.path(dirname(sub("^--file=", "", filearg[1L])), "../.."), mustWork = TRUE)
  setwd(root)
  for (f in c("00_packages.R", "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R", "latent_path_design.R",
      "joint_qdesn_pure_recursive_campaign.R", "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R"))
    source(file.path("application/R", f), local = FALSE)
  for (f in c("integrated_quantile_mq_batch.R", "mq_forecast_array_methods.R", "mq_native_qualification_backend.R"))
    source(file.path("scripts", f), local = FALSE)
  `%||%` <- function(a, b) if (is.null(a)) b else a
  mqb_tau <- c(.05,.1,.25,.5,.75,.9,.95); mqb_hash <- strrep("a", 64L)
  ast <- parse(file = "application/tests/test_integrated_quantile_mq_batch.R")
  at <- which(vapply(ast, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("mqb_fixture")), logical(1L)))
  stopifnot(length(at) == 1L); eval(ast[[at]])
  checks <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE)}
  reject <- function(expr) ok(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
  bits <- function(a, b) identical(a, b, num.eq = FALSE)
  before_body <- deparse(body(app_iqf_mqb_paths_context), width.cutoff = 500L)
  before_formals <- formals(app_iqf_mqb_paths_context); before_env <- environment(app_iqf_mqb_paths_context)
  files <- c(names(mqnk_frozen_sources()), "scripts/mq_native_qualification_backend.R",
    "application/tests/test_mq_native_qualification_backend.R", "scripts/mq_native_composed_arrays.R")
  before_sha <- tools::sha256sum(files)
  output <- Sys.getenv("MQNK_TEST_OUTPUT", unset = "")
  if (!nzchar(output)) output <- tempfile("mq_native_backend_generated_")
  stopifnot(!file.exists(output), dir.exists(dirname(output)), dir.create(output))
  output <- normalizePath(output, mustWork = TRUE)
  build <- file.path(output, "build"); stopifnot(dir.create(build))
  output_check <- function() {
    paths <- list.files(output, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    stopifnot(all(file.exists(paths)), !any(nzchar(Sys.readlink(paths))), sum(file.info(paths)$size) <= 128*1024^2)
  }
  oldenv <- Sys.getenv(c("R_MAKEVARS_USER", "R_MAKEVARS_SITE", "MAKEFLAGS", "PKG_LIBS"), unset = NA_character_)
  restore <- function() for (n in names(oldenv)) {
    if (is.na(oldenv[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(oldenv[[n]]), n))
  }
  on.exit(restore(), add = TRUE)
  makevars <- file.path(build, "controlled.Makevars")
  lib <- normalizePath(R.home("lib"), mustWork = TRUE)
  writeLines(c("CC = /usr/bin/gcc", "CFLAGS = -O2 -fno-fast-math -ffp-contract=off",
    "PKG_CFLAGS = -fno-fast-math -ffp-contract=off", paste0("PKG_LIBS = -Wl,-rpath,", lib, " -lcrypto")), makevars)
  Sys.setenv(R_MAKEVARS_USER = makevars, R_MAKEVARS_SITE = "/dev/null", MAKEFLAGS = "-j1",
    PKG_LIBS = paste0("-Wl,-rpath,", lib, " -lcrypto"))
  stems <- c(key = "mq_key_hash", isotonic = "mq_isoreg_batch", inverse = "mq_event_inverse")
  manifest <- list(schema_version = "mq_native_retained_build_receipt_v1", source_commit = "synthetic",
    source_tree = "synthetic", R_home = normalizePath(R.home(), mustWork = TRUE), R_libdir = lib, dlls = list())
  for (name in names(stems)) {
    source <- paste0("scripts/native/", stems[[name]], ".c")
    stopifnot(file.copy(source, file.path(build, basename(source))))
    setwd(build)
    log <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "--preclean", basename(source)), stdout = TRUE, stderr = TRUE)
    setwd(root); writeLines(log, file.path(output, paste0(name, "_build.log")))
    ok(is.null(attr(log, "status"))); ok(any(grepl("-fno-fast-math", log, fixed = TRUE)))
    ok(any(grepl("-ffp-contract=off", log, fixed = TRUE))); ok(any(grepl(paste0("-Wl,-rpath,", lib), log, fixed = TRUE)))
    dll <- normalizePath(file.path(build, paste0(stems[[name]], .Platform$dynlib.ext)), mustWork = TRUE)
    manifest$dlls[[name]] <- list(path = dll, size_bytes = as.numeric(file.info(dll)$size),
      sha256 = unname(tools::sha256sum(dll)), source_path = source, source_sha256 = unname(tools::sha256sum(source)))
  }
  restore(); output_check()
  # Exercise the genuine-mode FILE/OBJECT identity branch with generated
  # libraries and synthetic metadata only. This does not call mqnk_load,
  # create an authentic context or grant any numerical execution permission.
  manifest_file <- file.path(output, "generated_retained_build_receipt.json")
  jsonlite::write_json(manifest, manifest_file, auto_unbox = TRUE, pretty = TRUE, digits = 17)
  bound <- jsonlite::read_json(manifest_file, simplifyVector = FALSE)
  attr(bound, "receipt_path") <- normalizePath(manifest_file, mustWork = TRUE)
  attr(bound, "receipt_sha256") <- unname(tools::sha256sum(manifest_file))
  metadata_context <- list(source_commit = bound$source_commit, source_tree = bound$source_tree,
    retained_build_receipt_sha256 = attr(bound, "receipt_sha256"))
  before_names <- names(bound)
  ok(mqnk_manifest_check(bound, metadata_context, synthetic = FALSE))
  ok(identical(names(bound), before_names))
  plain <- bound; attr(plain, "receipt_path") <- NULL; attr(plain, "receipt_sha256") <- NULL
  ok(identical(plain, jsonlite::read_json(manifest_file, simplifyVector = FALSE)))
  # These exact source, object, file, hash and attribute mutations must fail.
  bad <- bound; bad$extra_permission <- TRUE; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; bad$source_commit <- "wrong"; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; bad$source_tree <- "wrong"; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad_context <- metadata_context; bad_context$retained_build_receipt_sha256 <- strrep("0", 64L)
  reject(mqnk_manifest_check(bound, bad_context, FALSE))
  bad <- bound; attr(bad, "receipt_path") <- file.path(output, "missing_receipt.json")
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; attr(bad, "receipt_sha256") <- strrep("0", 64L)
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; attr(bad, "receipt_path") <- NULL; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; attr(bad, "receipt_sha256") <- NULL; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  for (key in c("class", "dim", "unreviewed_metadata")) {
    bad <- bound
    attr(bad, key) <- if (key == "dim") length(bad) else "forged"
    reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  }
  bad <- bound; names(bad)[1L] <- "changed_schema_name"
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; names(bad)[2L] <- names(bad)[1L]
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; names(bad)[2L] <- ""; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  bad <- bound; names(bad)[2L] <- NA_character_; reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  reordered <- bound[rev(seq_along(bound))]
  attr(reordered, "receipt_path") <- attr(bound, "receipt_path")
  attr(reordered, "receipt_sha256") <- attr(bound, "receipt_sha256")
  reject(mqnk_manifest_check(reordered, metadata_context, FALSE))
  json_alias <- file.path(output, "generated_receipt_symlink.json")
  ok(file.symlink(manifest_file, json_alias))
  bad <- bound; attr(bad, "receipt_path") <- json_alias
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  stopifnot(unlink(json_alias) == 0L) # Disposable generated symlink only.
  bad <- bound; bad$dlls$key$source_sha256 <- strrep("0", 64L)
  reject(mqnk_manifest_check(bad, metadata_context, FALSE))
  changed_file <- file.path(output, "changed_generated_receipt.json")
  jsonlite::write_json(bad, changed_file, auto_unbox = TRUE, pretty = TRUE, digits = 17)
  changed <- bound; attr(changed, "receipt_path") <- normalizePath(changed_file, mustWork = TRUE)
  attr(changed, "receipt_sha256") <- unname(tools::sha256sum(changed_file))
  changed_context <- metadata_context; changed_context$retained_build_receipt_sha256 <- attr(changed, "receipt_sha256")
  reject(mqnk_manifest_check(changed, changed_context, FALSE))
  parsed_changed <- jsonlite::read_json(changed_file, simplifyVector = FALSE)
  attr(parsed_changed, "receipt_path") <- attr(changed, "receipt_path")
  attr(parsed_changed, "receipt_sha256") <- attr(changed, "receipt_sha256")
  reject(mqnk_manifest_check(parsed_changed, changed_context, FALSE))
  output_check()
  proof <- app_iqf_mqb_rng_reference()
  synthetic_context <- function(draw, phase = "training") structure(list(
    schema_version = "mq_native_synthetic_context_v1", mode = "synthetic_backend_contract_test_v1",
    canonical_source_root = root, phase = phase,
    unit_identity = list(model_cell_id = "synthetic_only", draw_id = draw, origin_id = "o8",
      rng_namespace = "synthetic_pure_MQ_batch_v1", H = 30L, tau = mqb_tau),
    training_path_range = c(1L,128L), validation_path_range = c(129L,256L),
    external_gate_verified = FALSE, runtime_verified = FALSE, production_authorized = FALSE,
    refit_authorized = FALSE, scoring_authorized = FALSE, article_authorized = FALSE, C_ABI_qualified = FALSE),
    class = "mq_native_synthetic_context_v1")
  ctx <- synthetic_context("draw1")
  reject(mqnk_enroll(manifest, ctx))
  reject(mqnk_load(manifest, ctx))
  bad <- ctx; bad$mode <- "generated_fixture_only"; reject(mqnk_load_synthetic(manifest, bad))
  bad <- ctx; bad$C_ABI_qualified <- TRUE; reject(mqnk_load_synthetic(manifest, bad))
  bad <- ctx; bad$training_path_range <- c(1L,130L); reject(mqnk_load_synthetic(manifest, bad))
  bad <- ctx; bad$unit_identity$H <- 30.5; reject(mqnk_load_synthetic(manifest, bad))
  bad <- manifest; bad$dlls$key$sha256 <- strrep("0", 64); reject(mqnk_load_synthetic(bad, ctx))
  bad <- manifest; bad$dlls$inverse$source_sha256 <- strrep("0", 64); reject(mqnk_load_synthetic(bad, ctx))
  bad <- manifest; bad$dlls$isotonic$size_bytes <- 9*1024^2; reject(mqnk_load_synthetic(bad, ctx))
  bad <- manifest; bad$R_libdir <- "/usr/lib64/R/lib"; reject(mqnk_load_synthetic(bad, ctx))
  ok(mqnk_body_check())
  ok(mqnk_body_check(compiler::cmpfun(app_iqf_mqb_paths_context), compiler::cmpfun(mqnk_paths_context)))
  changed <- function(kind) {
    f <- mqnk_paths_context; b <- as.list(body(f))
    if (kind == "guard") b[[2L]][[3L]] <- quote(NULL) else if (kind %in% c("namespace", "ids")) {
      at <- which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
        identical(x[[2L]], as.name("uniforms")), logical(1L)))
      b[[at]][[3L]][[if (kind == "namespace") 3L else 6L]] <- if (kind == "namespace") quote("wrong") else quote(rev(inner_ids))
    } else {
      at <- which(vapply(b, function(x) is.call(x) && identical(x[[1L]], as.name("for")), logical(1L)))
      loop <- as.list(b[[at]][[4L]])
      qi <- which(vapply(loop, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
        identical(x[[2L]], as.name("q")), logical(1L)))
      loop[[qi]][[3L]][[if (kind == "head") 1L else 3L]] <- if (kind == "head") quote(identity) else quote(mu*0)
      b[[at]][[4L]] <- as.call(loop)
    }
    body(f) <- as.call(b); f
  }
  for (kind in c("guard", "namespace", "ids", "head", "mu")) reject(mqnk_body_check(variant = changed(kind)))
  fields <- c("paths", "response", "ordered_quantiles", "trace", "inner_ids", "draw_id", "origin_id", "coupling",
    "rng_namespace", "outer_conditioning", "production_authorized", "numerical_accuracy_qualified", "raw_coherence")
  set.seed(35108); seed <- .Random.seed; kind <- RNGkind()
  records <- list()
  for (D in 1:3) {
    f <- mqb_fixture(D = D, activation = c("identity", "tanh", "relu")[D], projection = D > 1L, standardize = D < 3L)
    f$origins <- f$origins["o8"]; f$origins$o8$H <- 30L
    adapter <- do.call(app_iqf_mq_batch_adapter, c(f, list(inner_paths = 256L, batch_size = 128L,
      rng_mode = "r46_first_step_qualified", rng_proof = proof)))
    for (draw in f$posterior$draw_ids) {
      ctx <- synthetic_context(draw); handle <- mqnk_load_synthetic(manifest, ctx)
      ok(environmentIsLocked(handle)); reject(handle$context <- ctx)
      load_only <- new.env(parent = emptyenv()); class(load_only) <- "mq_native_load_only_v1"
      lockEnvironment(load_only, bindings = TRUE)
      reject(mqnk_handle_check(load_only))
      touched <- FALSE
      reject(mqnk_arrays(load_only, {touched <- TRUE; stop("must not inspect forecast input")}, draw, "o8", 1L, phase = "training"))
      reject(mqnk_inverse(load_only, {touched <- TRUE; stop("must not inspect forecast input")}, f$tau, f$tau))
      reject(mqnk_cdf_values(load_only, 0, {touched <- TRUE; stop("must not inspect forecast input")}, f$tau))
      reject(mqnk_cdf_values_internal(load_only, 0, {touched <- TRUE; stop("must not inspect forecast input")}, f$tau))
      reject(mqnk_project(load_only, {touched <- TRUE; stop("must not inspect forecast input")}))
      reject(mqnk_uniforms(load_only, f$rng_namespace, draw, "o8", 1L, 30L, proof))
      ok(!touched)
      ids <- c(1L,7L,17L,3L,19L,128L)
      reference <- app_iqf_mqb_paths_context(adapter$batch_context, draw, "o8", ids,
        include_trace = TRUE, include_paths = TRUE, collect_coherence = TRUE)
      native <- mqnk_paths_context(adapter$batch_context, draw, "o8", ids, include_trace = TRUE,
        include_paths = TRUE, collect_coherence = TRUE, handle = handle, phase = "training")
      for (field in fields) ok(bits(reference[[field]], native[[field]]))
      for (h in 1:30) {
        q <- native$ordered_quantiles[, , h]
        ok(bits(mqnk_inverse(handle, q, f$tau, f$tau), app_iqf_mq_matrix_inverse(q, f$tau, f$tau)))
        ys <- as.numeric(rbind(q[1L, ], q[1L, ] + .01))
        values <- mqnk_cdf_values(handle, ys, q, f$tau)
        old_values <- vapply(ys, function(y) vapply(seq_len(nrow(q)), function(i)
          app_iqf_kernel_cdf(y, list(family = "mq_grid", q = q[i, ], tau = f$tau)), numeric(1L)), numeric(nrow(q)))
        ok(bits(values, old_values))
      }
      whole <- mqnk_uniforms(handle, f$rng_namespace, draw, "o8", ids, 30L, proof)
      parts <- rbind(mqnk_uniforms(handle, f$rng_namespace, draw, "o8", ids[1:2], 30L, proof),
        mqnk_uniforms(handle, f$rng_namespace, draw, "o8", ids[3:6], 30L, proof))
      ok(bits(whole, parts))
      for (part in list(ids[1:2], ids[3:6])) {
        a <- app_iqf_mq_batch_arrays(adapter, draw, "o8", part, include_trace = TRUE)
        b <- mqnk_arrays(handle, adapter, draw, "o8", part, include_trace = TRUE, phase = "training")
        for (field in fields) ok(bits(a[[field]], b[[field]]))
      }
      for (bad in list(c(1L,1L), c(0L,1L), 129L, 1.5, 1+1i))
        reject(mqnk_arrays(handle, adapter, draw, "o8", bad, phase = "training"))
      reject(mqnk_arrays(handle, adapter, draw, "o8", ids))
      reject(mqnk_arrays(handle, adapter, "other", "o8", ids, phase = "training"))
      reject(mqnk_arrays(handle, adapter, draw, "o8", ids, phase = "validation"))
      bad <- adapter; bad$batch_context$rng_namespace <- "other"
      reject(mqnk_arrays(handle, bad, draw, "o8", ids, phase = "training"))
      validation <- mqnk_load_synthetic(manifest, synthetic_context(draw, "validation"))
      a <- app_iqf_mq_batch_arrays(adapter, draw, "o8", c(129L,256L), include_trace = TRUE)
      b <- mqnk_arrays(validation, adapter, draw, "o8", c(129L,256L), include_trace = TRUE, phase = "validation")
      for (field in fields) ok(bits(a[[field]], b[[field]]))
      ok(identical(.Random.seed, seed) && identical(RNGkind(), kind))
      records[[length(records)+1L]] <- data.frame(D = D, draw = draw, H = 30L, K = 7L, generated_only = TRUE)
    }
  }
  for (q in list(matrix(rep(c(-2,-2,0,0,1,1,2), 3L), 3L, byrow = TRUE),
      matrix(rep(c(1,0,-1,3,2,5,4), 3L), 3L, byrow = TRUE), matrix(0, 2L, 7L))) {
    p <- c(.95,.05,.5,.5,.1)
    ok(bits(mqnk_inverse(handle, q, mqb_tau, p), app_iqf_mq_matrix_inverse(q, mqb_tau, p)))
  }
  reject(mqnk_cdf_values(handle, 1+1i, matrix(0,1L,7L), mqb_tau))
  reject(mqnk_inverse(handle, matrix(0,1L,7L), mqb_tau, mqb_tau, tolerance = 1e-7))
  ok(identical(.Random.seed, seed) && identical(RNGkind(), kind))
  rm(".Random.seed", envir = .GlobalEnv)
  invisible(mqnk_uniforms(handle, f$rng_namespace, draw, "o8", 1:2, 30L, proof))
  ok(!exists(".Random.seed", .GlobalEnv, inherits = FALSE) && identical(RNGkind(), kind))
  assign(".Random.seed", seed, .GlobalEnv)
  ok(identical(before_body, deparse(body(app_iqf_mqb_paths_context), width.cutoff = 500L)))
  ok(identical(before_formals, formals(app_iqf_mqb_paths_context)) && identical(before_env, environment(app_iqf_mqb_paths_context)))
  ok(identical(before_sha, tools::sha256sum(files)))
  maps <- readLines("/proc/self/maps", warn = FALSE); writeLines(maps, file.path(output, "maps.txt"))
  paths <- unique(sub("^(?:\\S+\\s+){5}", "", maps, perl = TRUE))
  actual_libR <- grep("/libR\\.so( \\(deleted\\))?$", paths, value = TRUE)
  ok(identical(actual_libR, normalizePath(file.path(lib, "libR.so"), mustWork = TRUE)))
  write.csv(data.frame(path = files, sha256 = unname(before_sha)), file.path(output, "source_pins.csv"), row.names = FALSE)
  write.csv(do.call(rbind, records), file.path(output, "generated_cases.csv"), row.names = FALSE)
  jsonlite::write_json(list(status = "GENERATED_BACKEND_CONTRACT_TEST_ONLY", checks = checks, build = manifest,
    authentic_input_reads = 0L, production_authorized = FALSE, C_ABI_qualified = FALSE),
    file.path(output, "RECEIPT.json"), auto_unbox = TRUE, pretty = TRUE, digits = 17)
  output_check()
  cat(sprintf("MQ_NATIVE_BACKEND_GENERATED_PASS checks=%d output=%s\n", checks, output))
})
