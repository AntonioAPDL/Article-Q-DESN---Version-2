# Runtime provenance and fail-closed numerical-backend checks for latent-path fits.

app_latent_runtime_backend_env <- function() {
  c(
    "QDESN_NUMERICAL_BACKEND",
    "QDESN_BLAS_LIBRARY_PATH",
    "QDESN_BLAS_LIBRARY_SHA256",
    "LD_PRELOAD",
    "OMP_NUM_THREADS",
    "OMP_THREAD_LIMIT",
    "OPENBLAS_NUM_THREADS",
    "GOTO_NUM_THREADS",
    "MKL_NUM_THREADS",
    "BLIS_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS",
    "NUMEXPR_NUM_THREADS"
  )
}

app_latent_runtime_normalize_backend <- function(value = NULL) {
  value <- tolower(trimws(as.character(value %||% Sys.getenv(
    "QDESN_NUMERICAL_BACKEND",
    unset = "bundled_rblas"
  ))[[1L]]))
  aliases <- c(
    bundled = "bundled_rblas",
    rblas = "bundled_rblas",
    bundled_rblas = "bundled_rblas",
    openblas = "openblas_serial",
    openblas_serial = "openblas_serial",
    openblas_pthread = "openblas_pthread"
  )
  if (!value %in% names(aliases)) {
    stop(sprintf("Unsupported latent-path numerical backend '%s'.", value), call. = FALSE)
  }
  unname(aliases[[value]])
}

app_latent_runtime_cpu_affinity <- function(pid = Sys.getpid()) {
  path <- sprintf("/proc/%d/status", as.integer(pid))
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  hit <- grep("^Cpus_allowed_list:", lines, value = TRUE)
  if (!length(hit)) return(NA_character_)
  trimws(sub("^Cpus_allowed_list:", "", hit[[1L]]))
}

app_latent_runtime_loaded_numeric_libraries <- function(pid = Sys.getpid()) {
  path <- sprintf("/proc/%d/maps", as.integer(pid))
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  if (!length(lines)) return(character())
  fields <- strsplit(lines, "[[:space:]]+")
  paths <- vapply(fields, function(x) {
    hit <- x[grepl("^/", x)]
    if (length(hit)) utils::tail(hit, 1L) else NA_character_
  }, character(1L))
  paths <- unique(paths[!is.na(paths) & grepl(
    "(openblas|mkl|blis|libRblas|libRlapack|libblas|liblapack)",
    paths,
    ignore.case = TRUE
  )])
  sort(paths)
}

app_latent_runtime_file_manifest <- function(path) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) {
    return(list(path = NA_character_, sha256 = NA_character_, size_bytes = NA_real_))
  }
  path <- normalizePath(as.character(path[[1L]]), mustWork = TRUE)
  list(
    path = path,
    sha256 = app_sha256_file(path),
    size_bytes = as.numeric(file.info(path)$size)
  )
}

app_latent_runtime_engine_source_manifest <- function() {
  root <- app_repo_root()
  relative <- c(
    "application/R/latent_path_runtime_backend.R",
    "application/R/latent_path_checkpoint.R",
    "application/R/latent_path_design.R",
    "application/R/latent_path_vb_al.R",
    "application/R/fit_qdesn_latent_path.R",
    "application/R/fit_qdesn_discrepancy.R"
  )
  paths <- file.path(root, relative)
  present <- file.exists(paths)
  relative <- relative[present]
  paths <- paths[present]
  hashes <- vapply(paths, app_sha256_file, character(1L))
  names(hashes) <- relative
  git_value <- function(args) {
    out <- tryCatch(
      system2("git", c("-C", root, args), stdout = TRUE, stderr = FALSE),
      error = function(e) character()
    )
    if (length(out)) trimws(out[[1L]]) else NA_character_
  }
  status <- tryCatch(
    system2(
      "git",
      c("-C", root, "status", "--short", "--", relative),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(e) character()
  )
  list(
    source_head = git_value(c("rev-parse", "HEAD")),
    source_commit_tree = git_value(c("rev-parse", "HEAD^{tree}")),
    engine_source_hash = app_latent_path_contract_hash(
      as.list(hashes),
      prefix = "latent_runtime_engine_sources_"
    ),
    engine_source_dirty = length(status) > 0L,
    engine_source_status = paste(status, collapse = " | "),
    engine_source_files = paste(relative, collapse = ";")
  )
}

app_latent_runtime_validate_backend <- function(
  backend = NULL,
  library_path = NULL,
  library_sha256 = NULL,
  fail_closed = TRUE
) {
  backend <- app_latent_runtime_normalize_backend(backend)
  library_path <- as.character(library_path %||% Sys.getenv(
    "QDESN_BLAS_LIBRARY_PATH",
    unset = ""
  ))[[1L]]
  library_sha256 <- tolower(as.character(library_sha256 %||% Sys.getenv(
    "QDESN_BLAS_LIBRARY_SHA256",
    unset = ""
  ))[[1L]])
  preload <- Sys.getenv("LD_PRELOAD", unset = "")

  if (identical(backend, "bundled_rblas")) {
    undeclared_external <- nzchar(library_path) || grepl(
      "(openblas|mkl|blis)",
      preload,
      ignore.case = TRUE
    )
    if (isTRUE(fail_closed) && undeclared_external) {
      stop(
        "Bundled R BLAS cannot be combined with an undeclared external numerical backend.",
        call. = FALSE
      )
    }
    return(list(
      backend = backend,
      external_library = app_latent_runtime_file_manifest(NULL),
      preload = preload,
      verified = TRUE
    ))
  }

  if (!nzchar(library_path) || !nzchar(library_sha256)) {
    stop(
      "OpenBLAS backends require QDESN_BLAS_LIBRARY_PATH and QDESN_BLAS_LIBRARY_SHA256.",
      call. = FALSE
    )
  }
  manifest <- app_latent_runtime_file_manifest(library_path)
  if (!identical(tolower(manifest$sha256), library_sha256)) {
    stop(
      sprintf(
        "Numerical backend hash mismatch for %s: expected %s, observed %s.",
        manifest$path,
        library_sha256,
        manifest$sha256
      ),
      call. = FALSE
    )
  }
  preload_paths <- strsplit(preload, ":", fixed = TRUE)[[1L]]
  preload_paths <- normalizePath(preload_paths[nzchar(preload_paths)], mustWork = FALSE)
  if (isTRUE(fail_closed) && !manifest$path %in% preload_paths) {
    stop(
      sprintf("Verified OpenBLAS library is not present in LD_PRELOAD: %s.", manifest$path),
      call. = FALSE
    )
  }
  list(
    backend = backend,
    external_library = manifest,
    preload = preload,
    verified = TRUE
  )
}

app_latent_runtime_backend_manifest <- function(fail_closed = TRUE) {
  verified <- app_latent_runtime_validate_backend(fail_closed = fail_closed)
  loaded <- app_latent_runtime_loaded_numeric_libraries()
  blas_reported <- as.character(extSoftVersion()[["BLAS"]] %||% NA_character_)
  bundled_reported_external <- identical(verified$backend, "bundled_rblas") &&
    isTRUE(grepl("(openblas|mkl|blis)", blas_reported, ignore.case = TRUE))
  if (isTRUE(fail_closed) && identical(verified$backend, "bundled_rblas") &&
      isTRUE(bundled_reported_external)) {
    stop(
      sprintf(
        "Bundled R BLAS declaration conflicts with the active BLAS reported by R: %s.",
        blas_reported
      ),
      call. = FALSE
    )
  }
  if (isTRUE(fail_closed) && !identical(verified$backend, "bundled_rblas") &&
      !verified$external_library$path %in% loaded) {
    stop(
      sprintf(
        "Verified numerical backend was not loaded into the R process: %s.",
        verified$external_library$path
      ),
      call. = FALSE
    )
  }
  env_names <- app_latent_runtime_backend_env()
  env_values <- Sys.getenv(env_names, unset = "")
  names(env_values) <- env_names
  source_manifest <- app_latent_runtime_engine_source_manifest()
  data.frame(
    backend = verified$backend,
    backend_verified = isTRUE(verified$verified),
    external_library_path = verified$external_library$path,
    external_library_sha256 = verified$external_library$sha256,
    external_library_size_bytes = verified$external_library$size_bytes,
    ld_preload = verified$preload,
    loaded_numeric_libraries = paste(loaded, collapse = ";"),
    r_version = R.version.string,
    r_executable = file.path(R.home("bin"), "R"),
    blas_reported = blas_reported,
    lapack_reported = tryCatch(as.character(La_library()), error = function(e) NA_character_),
    cpu_affinity = app_latent_runtime_cpu_affinity(),
    omp_num_threads = env_values[["OMP_NUM_THREADS"]],
    omp_thread_limit = env_values[["OMP_THREAD_LIMIT"]],
    openblas_num_threads = env_values[["OPENBLAS_NUM_THREADS"]],
    goto_num_threads = env_values[["GOTO_NUM_THREADS"]],
    mkl_num_threads = env_values[["MKL_NUM_THREADS"]],
    blis_num_threads = env_values[["BLIS_NUM_THREADS"]],
    veclib_maximum_threads = env_values[["VECLIB_MAXIMUM_THREADS"]],
    numexpr_num_threads = env_values[["NUMEXPR_NUM_THREADS"]],
    source_head = source_manifest$source_head,
    source_commit_tree = source_manifest$source_commit_tree,
    engine_source_hash = source_manifest$engine_source_hash,
    engine_source_dirty = source_manifest$engine_source_dirty,
    engine_source_status = source_manifest$engine_source_status,
    engine_source_files = source_manifest$engine_source_files,
    stringsAsFactors = FALSE
  )
}

app_latent_runtime_backend_contract <- function(fail_closed = TRUE) {
  manifest <- app_latent_runtime_backend_manifest(fail_closed = fail_closed)
  stable_fields <- c(
    "backend", "backend_verified", "external_library_path",
    "external_library_sha256", "external_library_size_bytes", "r_version",
    "r_executable", "blas_reported", "lapack_reported", "omp_num_threads",
    "omp_thread_limit", "openblas_num_threads", "goto_num_threads",
    "mkl_num_threads", "blis_num_threads", "veclib_maximum_threads",
    "numexpr_num_threads"
  )
  as.list(manifest[1L, stable_fields, drop = FALSE])
}

app_latent_runtime_backend_fingerprint <- function(fail_closed = TRUE) {
  app_latent_path_contract_hash(
    app_latent_runtime_backend_contract(fail_closed = fail_closed),
    prefix = "latent_runtime_backend_"
  )
}
