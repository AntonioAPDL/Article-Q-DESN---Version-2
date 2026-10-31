# Compute-only zero-target/zero-optimizer native boundary qualification.
# The owning unchanged r157 tracer supplies proof/ACK FDs and checks the actual
# kernel TSYNC call/program before acknowledging access. Child output alone
# cannot establish success.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(identical(hash(args[[1L]]), args[[2L]]))
spec <- jsonlite::read_json(args[[1L]], simplifyVector = FALSE)
stopifnot(identical(hash(spec$namespace_fixture$path), spec$namespace_fixture$sha256),
  identical(hash(spec$scientific_boundary_library$path), spec$scientific_boundary_library$sha256),
  identical(spec$scientific_data_read, FALSE), spec$optimizer_invocations == 0L)
source(spec$namespace_fixture$path)
dyn.load(spec$scientific_boundary_library$path)
stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))
cat(jsonlite::toJSON(list(status='BOUNDARY_CHILD_ACKNOWLEDGED_AWAIT_PARENT_KERNEL_PROOF',
  nonce=args[[3L]], job_id=Sys.getenv('SLURM_JOB_ID'), node=Sys.getenv('SLURMD_NODENAME'),
  optimizer_invocations=0L,scientific_data_read=FALSE,models=0L),auto_unbox=TRUE), '\n')
