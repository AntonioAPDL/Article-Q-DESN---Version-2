# Only a reviewed compute-side r157 tracer may source a numerical entrypoint.
# Namespace bootstrap is fully owned; the unmodified C primitive establishes
# TSYNC fork denial and waits for the owning tracer's kernel-verified ACK.
spec_path <- Sys.getenv('R179_STAGE_BOOTSTRAP_SPEC')
spec_sha <- Sys.getenv('R179_STAGE_BOOTSTRAP_SPEC_SHA256')
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(nzchar(Sys.getenv('SLURM_JOB_ID')), grepl('^[0-9a-f]{64}$',spec_sha),
  identical(hash(spec_path),spec_sha))
spec <- jsonlite::read_json(spec_path,simplifyVector=FALSE)
stopifnot(identical(spec$schema,'r179_hb_scientific_bootstrap_spec_v1'),
  identical(spec$job_id,Sys.getenv('SLURM_JOB_ID')),
  identical(spec$node,Sys.getenv('SLURMD_NODENAME')),
  spec$role %in% c('TOY_PARITY','ZERO_UPDATE_BRIDGE','NO3_AL300_PILOT'),
  identical(hash(spec$fixedpoint_helper$path),spec$fixedpoint_helper$sha256),
  identical(hash(spec$boundary_library$path),spec$boundary_library$sha256),
  identical(hash(spec$scientific_entrypoint$path),spec$scientific_entrypoint$sha256))
source(spec$fixedpoint_helper$path)
ns <- r129_namespace(spec$library)
loadNamespace('digest');loadNamespace('jsonlite')
stopifnot(identical(digest::digest(body(get('.run_static_dqlm_cavi',ns)),algo='sha256'),
  spec$expected_stock_body_sha256))
dyn.load(spec$boundary_library$path)
stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))
# This flag follows the actual proof/ACK and cannot replace that external proof.
Sys.setenv(R179_CURRENT_TSYNC_ACK_REQUIRED='1')
source(spec$scientific_entrypoint$path)
