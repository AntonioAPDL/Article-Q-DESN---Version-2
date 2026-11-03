# One temporary build; generated-only exact projection and recursive path tests.
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
    normalizePath(file.path(dirname(f), "../.."), mustWork = TRUE)
  }
  setwd(root); source("scripts/mq_isoreg_batch.R", local = TRUE)
  checks <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE)}
  reject <- function(expr) {
    e <- tryCatch({force(expr); NULL}, error = function(e) e)
    ok(inherits(e, "error"))
  }
  bits_equal <- function(a, b) identical(a, b, num.eq = FALSE)
  before_rng <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  old_sources <- c("application/R/integrated_quantile_forecast.R", "scripts/mq_forecast_array_methods.R")
  old_hashes <- tools::sha256sum(old_sources)
  before_env <- Sys.getenv(c("R_MAKEVARS_USER", "R_MAKEVARS_SITE"), unset = NA_character_)
  build <- tempfile("mq_isoreg_generated_build_"); stopifnot(dir.create(build))
  # Generated build artifacts only; never install or write into the repository.
  stopifnot(file.copy("scripts/native/mq_isoreg_batch.c", file.path(build, "mq_isoreg_batch.c")))
  makevars <- file.path(build, "controlled.Makevars")
  writeLines(c("CFLAGS = -O2 -fno-fast-math -ffp-contract=off",
    "PKG_CFLAGS = -fno-fast-math -ffp-contract=off"), makevars)
  Sys.setenv(R_MAKEVARS_USER = makevars, R_MAKEVARS_SITE = "/dev/null")
  oldwd <- getwd(); setwd(build)
  compilation <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "--preclean", "mq_isoreg_batch.c"),
    stdout = TRUE, stderr = TRUE)
  setwd(oldwd)
  for (name in names(before_env)) {
    if (is.na(before_env[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, setNames(list(before_env[[name]]), name))
  }
  cat(paste(compilation, collapse = "\n"), "\n")
  ok(is.null(attr(compilation, "status")))
  ok(any(grepl("-fno-fast-math", compilation, fixed = TRUE)) &&
    any(grepl("-ffp-contract=off", compilation, fixed = TRUE)))
  path <- normalizePath(file.path(build, paste0("mq_isoreg_batch", .Platform$dynlib.ext)), mustWork = TRUE)
  candidate <- mqi_load(path, unname(tools::sha256sum(path)), "generated_fixture_only")
  ok(identical(candidate$dll[["dynamicLookup"]], FALSE))
  ok(identical(names(getDLLRegisteredRoutines(candidate$dll)[[".Call"]]), "mqi_project"))
  call_candidate <- function(q) mqi_project(q, candidate, "generated_fixture_only")
  reference <- function(q) {
    if (typeof(q) != "double") storage.mode(q) <- "double"
    out <- q
    for (i in seq_len(nrow(q))) if (any(diff(q[i, ]) < 0))
      out[i, ] <- stats::isoreg(seq_len(ncol(q)), q[i, ])$yf
    out
  }
  signed <- c(-0, 0, -0, 0, -0, 0, -0)
  eps <- .Machine$double.eps; subnormal <- .Machine$double.xmin * eps
  corpus <- rbind(-3:3, rev(-3:3), rep(0, 7), c(0, 1, 1, -1, 2, 2, 1),
    signed, c(1, -0, 0, -1, 0, 0, 1),
    1 + eps * c(0, 1, 0, 2, 2, 1, 3),
    1e15 + c(1, 0, 3, 2, 2, 5, 4),
    subnormal * c(2, 1, 0, -2, -1, 3, 2),
    1e-250 * c(1, -2, 3, 0, -1, 2, 1),
    c(1e100, -1e100, 1, 0, -2, 1e-100, 0),
    rep(1e308, 7), seq(-1e200, 1e200, length.out = 7))
  dimnames(corpus) <- list(paste0("r", seq_len(nrow(corpus))), paste0("p", 1:7))
  original <- serialize(corpus, NULL, version = 3L)
  got <- call_candidate(corpus); expected <- reference(corpus)
  ok(bits_equal(got, expected)); ok(identical(serialize(corpus, NULL, version = 3L), original))
  ok(bits_equal(got[5L, ], corpus[5L, ]))
  ok(bits_equal(got[12L, ], corpus[12L, ])) # ordered row bypasses overflowing sum
  for (k in c(2L, 7L, 16L)) {
    x <- matrix(sin(seq_len(1024L * k) * .337) * 10 + cos(seq_len(1024L * k) * .19), 1024L, k)
    ok(bits_equal(call_candidate(x), reference(x)))
    # Distinct scales/cancellation and duplicated values preserve native arithmetic.
    for (scale in c(1e-150, 1, 1e150)) {
      y <- x[1:32, , drop = FALSE] * scale
      y[2L, ] <- rev(y[1L, ]); y[3L, ] <- rep(y[1L, 1L], k)
      ok(bits_equal(call_candidate(y), reference(y)))
    }
  }
  ok(bits_equal(call_candidate(matrix(c(2, 1), 1L)), reference(matrix(c(2, 1), 1L))))
  ok(bits_equal(call_candidate(matrix(4:1, 2L)), reference(matrix(4:1, 2L))))
  for (value in c(NA_real_, NaN, Inf, -Inf)) {
    x <- matrix(0, 2L, 7L); x[1L, 1L] <- value
    reject(call_candidate(x)); reject(.Call(candidate$symbol, x))
  }
  overflow <- matrix(c(1e308, 1e308, -1e307, 0, 0, 0, 0), 1L)
  reject(reference(overflow)); reject(call_candidate(overflow))
  for (x in list(matrix(0, 0L, 7L), matrix(0, 2L, 1L), matrix(0, 1L, 65L),
      matrix(1 + 1i, 2L, 2L), c(1, 0), list(1, 0))) reject(call_candidate(x))
  reject(.Call(candidate$symbol, matrix(4:1, 2L))) # C entry checks REALSXP independently
  reject(.Call(candidate$symbol, c(1, 0)))
  reject(.Call("mqi_project", matrix(c(1, 0), 1L), PACKAGE = candidate$dll[["name"]]))
  reject(mqi_project(corpus, candidate)); reject(mqi_load(path, candidate$sha256))
  reject(mqi_load(path, strrep("0", 64), "generated_fixture_only"))
  contract <- mqi_contract()
  ok(!contract$production_authorized && !contract$default_backend_changed &&
    !contract$authentic_full_unit_speedup_demonstrated)

  # Separate parameter-draw-specific recursive generated paths, never pooled.
  source("application/R/integrated_quantile_forecast.R", local = TRUE)
  path_test <- function(project) {
    paths <- array(0, c(16L, 30L, 2L)); kernels <- array(0, c(16L, 7L, 30L, 2L))
    tau <- c(.05, .10, .25, .50, .75, .90, .95)
    for (draw in 1:2) {
      past <- rep(draw / 10, 16L)
      for (h in 1:30) {
        base <- .6 * past + .05 * sin(1:16 + h) + draw / 100
        raw <- outer(base, c(1, 1.1, .9, 1, 1.2, .8, 1)) +
          matrix(rep(c(-1, .4, -.3, 0, .9, .2, 1.5), each = 16L), 16L)
        ordered <- project(raw); kernels[, , h, draw] <- ordered
        u <- (sin((1:16) * 17 + h * 31) + 1) / 2
        past <- vapply(1:16, function(i) app_iqf_mq_grid_inverse(ordered[i, ], tau, u[i]), 0)
        paths[, h, draw] <- past
      }
    }
    list(paths = paths, kernels = kernels)
  }
  native_paths <- path_test(reference); candidate_paths <- path_test(call_candidate)
  ok(bits_equal(native_paths, candidate_paths))
  ok(!identical(candidate_paths$paths[, , 1L], candidate_paths$paths[, , 2L]))
  ok(identical(old_hashes, tools::sha256sum(old_sources)))
  after_rng <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  ok(identical(before_rng, after_rng))
  cat(sprintf("MQ_ISOREG_BATCH_GENERATED_PASS checks=%d R=%s temporary_DLL_sha256=%s production_authorized=FALSE\n",
    checks, getRversion(), candidate$sha256))
  dyn.unload(path)
})
