#!/usr/bin/env Rscript
# Read-only runtime observation. Loads the exact installed CRAN namespace only.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 2L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
out <- args[[2L]]; stopifnot(identical(out, '-') || !file.exists(out))
ns <- loadNamespace('exdqlm', lib.loc = library_path)
pkg <- normalizePath(find.package('exdqlm'), mustWork = TRUE)
stopifnot(identical(pkg, file.path(library_path, 'exdqlm')),
  identical(as.character(packageVersion('exdqlm')), '1.1.1'))
hash <- function(p) digest::digest(p, file = TRUE, algo = 'sha256')
files <- list.files(pkg, recursive = TRUE, full.names = TRUE, all.files = TRUE)
files <- files[!file.info(files)$isdir]
hashes <- setNames(lapply(files, hash), substring(files, nchar(pkg) + 2L))
status <- readLines('/proc/self/status')
maps <- readLines('/proc/self/maps')
shared <- unique(sub('^[^/]*', '', maps[grepl('/.*\\.so', maps)]))
stopifnot(all(file.exists(shared)))
record <- list(record_kind = 'actual_runtime_binding_no_target_arithmetic',
  host = Sys.info()[['nodename']], R = unclass(R.version),
  R_home = R.home(), actual_executable = Sys.readlink('/proc/self/exe'),
  actual_executable_sha256 = hash('/proc/self/exe'),
  Rscript = normalizePath(file.path(R.home('bin'), 'Rscript')),
  Rscript_sha256 = hash(file.path(R.home('bin'), 'Rscript')),
  package_path = pkg, package_files_sha256 = hashes,
  loaded_shared_object_sha256 = setNames(lapply(shared, hash), shared),
  description = unclass(utils::packageDescription('exdqlm', lib.loc = library_path)),
  extSoftVersion = as.list(extSoftVersion()), sessionInfo = capture.output(sessionInfo()),
  process_affinity = status[startsWith(status, 'Cpus_allowed_list:')],
  thread_environment = as.list(Sys.getenv(c('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
    'MKL_NUM_THREADS', 'BLIS_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS'))),
  posterior_fits = 0L, target_numeric_diagnoses = 0L, certificate_recomputations = 0L)
encoded <- jsonlite::toJSON(record, auto_unbox = TRUE, pretty = TRUE, null = 'null', digits = 17)
if (identical(out, '-')) {
  cat(encoded, '\n')
} else {
  con <- file(out, open = 'wx'); on.exit(close(con)); writeLines(encoded, con)
  cat('Observed actual R/CRAN runtime; no target arithmetic\n')
}
