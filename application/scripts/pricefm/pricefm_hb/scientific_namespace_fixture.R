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
dll_paths <- unique(vapply(getLoadedDLLs(), function(x) x[['path']], character(1)))
dll_paths <- dll_paths[nzchar(dll_paths)]
loaded <- lapply(dll_paths, function(path) list(path = normalizePath(path, mustWork = TRUE), sha256 = hash(path)))
result <- list(status = 'PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY',
  role = 'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER', nonce = args[[3L]],
  job_id = Sys.getenv('SLURM_JOB_ID'), node = Sys.getenv('SLURMD_NODENAME'),
  affinity = unlist(spec$affinity), R_version = as.character(getRversion()), R_home = R.home(),
  package_versions = versions, stock_body_sha256 = stock_body_sha, loaded_DLLs = loaded,
  package_library = library, optimizer_invocations = 0L, models = 0L,
  scientific_data_read = FALSE, scientific_boundary_proved = FALSE,
  numerical_parity_proved = FALSE, host_glibc_is_actual_compute_host = TRUE)
cat(jsonlite::toJSON(result, auto_unbox = TRUE, digits = 17, null = 'null'), '\n')
