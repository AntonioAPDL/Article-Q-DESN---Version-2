# A numerical purpose is separate from the zero-optimizer metadata owner.
# Source bytes and grant metadata may be verified during bootstrap; all target
# and numerical entrypoint evaluation follows the actual parent TSYNC ACK.
args <- commandArgs(TRUE)
stopifnot(length(args) >= 3L)
spec_path <- args[[1L]]; spec_sha <- args[[2L]]
hash <- function(p) digest::digest(p, file=TRUE, algo='sha256')
stopifnot(grepl('^[0-9a-f]{64}$',spec_sha),identical(hash(spec_path),spec_sha))
spec <- jsonlite::read_json(spec_path,simplifyVector=FALSE)
stopifnot(identical(spec$schema,'r182_hb_numerical_bootstrap_v1'),
  identical(args[[3L]],spec$nonce),
  spec$role %in% c('TOY_PARITY','ZERO_UPDATE_BRIDGE'),
  identical(spec$job_id,Sys.getenv('SLURM_JOB_ID')),
  identical(spec$node,Sys.getenv('SLURMD_NODENAME')),
  identical(Sys.getenv('SLURM_CPUS_PER_TASK'),'1'),
  identical(hash(spec$fixedpoint_helper$path),spec$fixedpoint_helper$sha256),
  identical(hash(spec$boundary_library$path),spec$boundary_library$sha256),
  identical(hash(spec$scientific_entrypoint$path),spec$scientific_entrypoint$sha256))
source(spec$fixedpoint_helper$path)
ns <- r129_namespace(spec$library)
loadNamespace('digest');loadNamespace('jsonlite')
stopifnot(identical(digest::digest(body(get('.run_static_dqlm_cavi',ns)),algo='sha256'),
  spec$expected_stock_body_sha256))
for (pin in spec$source_parse_files) {
  stopifnot(identical(hash(pin$path),pin$sha256))
  invisible(parse(file=pin$path,keep.source=FALSE))
}
cat(jsonlite::toJSON(list(status='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT',
  role=spec$role,job_id=spec$job_id,node=spec$node,nonce=spec$nonce,
  source_files=spec$source_parse_files,optimizer_invocations=0L,scientific_target_data_read=FALSE),
  auto_unbox=TRUE,digits=17), '\n')
flush(stdout())
# The owning parent validates this exact parse frame in the original tracer's
# pre-ACK capture callback. The C primitive blocks until that parent returns a
# kernel-verified ACK; no numerical entrypoint can pass this barrier first.
dyn.load(spec$boundary_library$path)
stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))
Sys.setenv(R179_CURRENT_TSYNC_ACK_REQUIRED='1')
# The unmodified port reads commandArgs. Supply only its original positional
# contract after the kernel proof/ACK. This wrapper does not change its math.
saved_commandArgs <- commandArgs
commandArgs <- function(trailingOnly=FALSE) {
  if (isTRUE(trailingOnly)) unlist(spec$entrypoint_args,use.names=FALSE)
  else saved_commandArgs(FALSE)
}
source(spec$scientific_entrypoint$path)
