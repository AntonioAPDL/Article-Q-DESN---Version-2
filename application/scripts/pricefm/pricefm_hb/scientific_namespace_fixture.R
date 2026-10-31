# Compute-only namespace/body metadata qualification. No optimizer or data input.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L, grepl('^[0-9a-f]{64}$', args[[2L]]),
  grepl('^[0-9a-f]{32}$', args[[3L]]), nzchar(Sys.getenv('SLURM_JOB_ID')),
  identical(Sys.getenv('SLURM_CPUS_PER_TASK'), '1'))
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(identical(hash(args[[1L]]), args[[2L]]))
spec <- jsonlite::read_json(args[[1L]], simplifyVector = FALSE)
stopifnot(identical(spec$schema, 'r179_scientific_namespace_fixture_spec_v1'),
  identical(spec$optimizer_invocations, 0L) || identical(spec$optimizer_invocations, 0),
  identical(spec$scientific_data_read, FALSE),
  identical(spec$job_id, Sys.getenv('SLURM_JOB_ID')),
  identical(spec$node, Sys.getenv('SLURMD_NODENAME')),
  !grepl('login|head|submit', spec$node, ignore.case = TRUE))
actual_affinity <- trimws(sub('Cpus_allowed_list:', '',
  readLines('/proc/self/status')[startsWith(readLines('/proc/self/status'), 'Cpus_allowed_list:')]))
stopifnot(length(spec$affinity) == 1L, identical(actual_affinity, as.character(spec$affinity[[1L]])))
library <- normalizePath(spec$library, mustWork = TRUE)
stopifnot(length(spec$package_versions) == 48L,
  identical(spec$fixedpoint_helper$sha256, 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571'),
  identical(spec$expected_stock_body_sha256, '3637a96c29305a0e3f7df19ecf96f85b77f98f0dbb0e783773d217ba2be6dde6'),
  identical(as.character(getRversion()), '4.6.0'), identical(normalizePath(R.home()), normalizePath(spec$R_HOME)))
versions <- list()
for (name in names(spec$package_versions)) {
  ns <- loadNamespace(name, lib.loc = library)
  stopifnot(identical(as.character(getNamespaceVersion(name)), spec$package_versions[[name]]),
    identical(normalizePath(find.package(name)), normalizePath(file.path(library, name))))
  versions[[name]] <- as.character(getNamespaceVersion(name))
}
stopifnot(identical(hash(spec$fixedpoint_helper$path), spec$fixedpoint_helper$sha256))
source(spec$fixedpoint_helper$path)
ns <- r129_namespace(library)
stock <- get('.run_static_dqlm_cavi', ns)
stock_body_sha <- digest::digest(body(stock), algo = 'sha256')
stopifnot(identical(stock_body_sha, spec$expected_stock_body_sha256))
required <- spec$required_package_DLLs
allowed <- spec$allowed_package_DLLs
native_R <- list(path = file.path(spec$R_HOME, 'bin', 'exec', 'R'))
native_R$sha256 <- hash(native_R$path)
stopifnot(identical(native_R$sha256, '9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'))
cat(jsonlite::toJSON(list(status = 'OBSERVED_NAMESPACE_AND_STOCK_BEFORE_DLL_VALIDATION',
  nonce = args[[3L]], job_id = Sys.getenv('SLURM_JOB_ID'), node = Sys.getenv('SLURMD_NODENAME'),
  package_count = length(versions), stock_body_sha256 = stock_body_sha,
  optimizer_invocations = 0L, scientific_data_read = FALSE), auto_unbox = TRUE), '\n', file = stderr())
infos <- getLoadedDLLs()
entry_names <- names(infos)
stopifnot(length(entry_names) == length(infos), !anyDuplicated(entry_names))
loaded <- list()
builtins <- list()
for (i in seq_along(infos)) {
  entry_name <- entry_names[[i]]
  name <- infos[[i]][['name']]
  path <- infos[[i]][['path']]
  stopifnot(is.character(entry_name), length(entry_name) == 1L, nzchar(entry_name),
    is.character(name), length(name) == 1L, nzchar(name),
    is.character(path), length(path) == 1L, nzchar(path))
  if (identical(entry_name, 'base') && identical(name, 'base') && identical(path, 'base')) {
    builtins[[length(builtins) + 1L]] <- list(entry_name = 'base', name = 'base', path = 'base',
      kind = 'R_INTRINSIC_NO_EXTERNAL_FILE', external_file = FALSE, native_R = native_R)
  } else {
    # Missing/pseudo/nonfile entries are errors. The exact builtin above is
    #the only exception; no unknown entry can be silently skipped.
    stopifnot(!identical(entry_name, 'base'), !identical(name, 'base'),
      grepl('^/', path), isTRUE(utils::file_test('-f', path)))
    canonical <- normalizePath(path, mustWork = TRUE)
    stopifnot(canonical %in% names(allowed))
    loaded[[length(loaded) + 1L]] <- list(entry_name = entry_name, name = name,
      path = canonical, sha256 = hash(canonical))
  }
}
stopifnot(length(builtins) == 1L)
dll_paths <- vapply(loaded, function(x) x$path, character(1))
stopifnot(!anyDuplicated(dll_paths))
stopifnot(length(required) == 6L, length(allowed) == 34L, all(names(required) %in% dll_paths))
for (path in names(required)) stopifnot(identical(hash(path), required[[path]]))
for (item in loaded) {
  stopifnot(item$path %in% names(allowed), identical(item$sha256, allowed[[item$path]]))
}
result <- list(status = 'PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY',
  role = 'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER', nonce = args[[3L]],
  job_id = Sys.getenv('SLURM_JOB_ID'), node = Sys.getenv('SLURMD_NODENAME'),
  affinity = unlist(spec$affinity), R_version = as.character(getRversion()), R_home = R.home(),
  package_versions = versions, stock_body_sha256 = stock_body_sha, loaded_DLLs = loaded, builtin_DLLs = builtins,
  package_library = library, optimizer_invocations = 0L, models = 0L,
  scientific_data_read = FALSE, scientific_boundary_proved = FALSE,
  numerical_parity_proved = FALSE, host_glibc_is_actual_compute_host = TRUE)
cat(jsonlite::toJSON(result, auto_unbox = TRUE, digits = 17, null = 'null'), '\n')
