"""Generate a separately named HB authority/path port with frozen math bytes.

The original525 files and numerical bodies remain untouched. This module only
prepares source; it cannot issue a grant, launch a payload or accept parity.
"""
from __future__ import annotations
import hashlib
from pathlib import Path

from .runtime_archive import require

TOY_MARKER = "source(file.path(root, 'application/R/pricefm_r129_al_fixedpoint_certificate.R'))\n"
BRIDGE_MARKER = "read64 <- function(path, n) {\n"

# This prefix is an additional host/resource gate. It does not provide the
# original tracer's mandatory current-run TSYNC proof/ACK; that handshake must
# be earned before the numerical entrypoint is sourced by the reviewed owner.
COMMON = '''r179_hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
r179_verify <- function(pin) {
  stopifnot(setequal(names(pin), c('path','sha256')),
    identical(r179_hash(pin$path), pin$sha256))
  pin$path
}
r179_binding_map <- function(x) {
  if (is.data.frame(x)) setNames(as.character(x$sha256), as.character(x$path)) else
    setNames(vapply(x, function(p) p$sha256, character(1)), vapply(x, function(p) p$path, character(1)))
}
r179_job_gate <- function(grant, role) {
  stopifnot(identical(grant$schema, 'pricefm_hb_scientific_stage_grant_v1'),
    identical(grant$role, role), identical(grant$job_id, Sys.getenv('SLURM_JOB_ID')),
    identical(grant$node, Sys.getenv('SLURMD_NODENAME')),
    !grepl('login|head|submit', grant$node, ignore.case = TRUE),
    identical(Sys.getenv('SLURM_CPUS_PER_TASK'), '1'), grant$memory_MiB == 8192,
    grant$max_new_numerical == 1L, grant$attempt_index == 1L,
    identical(grant$old_claims_reused, FALSE), identical(grant$old_costs_refunded, FALSE),
    identical(grant$authorizes_production_acceptance, FALSE))
  affinity <- trimws(sub('Cpus_allowed_list:', '',
    readLines('/proc/self/status')[startsWith(readLines('/proc/self/status'), 'Cpus_allowed_list:')]))
  stopifnot(length(grant$affinity) == 1L, identical(affinity, as.character(grant$affinity[[1L]])))
  expiry <- as.numeric(as.POSIXct(substr(grant$expires_UTC, 1L, 19L),
    format = '%Y-%m-%dT%H:%M:%S', tz = 'UTC'))
  stopifnot(is.finite(expiry), as.numeric(Sys.time()) < expiry,
    expiry <= grant$stage_deadline_epoch)
  pool <- jsonlite::read_json(r179_verify(grant$global_contract), simplifyVector = FALSE)
  stopifnot(identical(pool$schema, 'r179_hb_scientific_job_contract_v1'),
    identical(pool$job_id, grant$job_id), identical(pool$node, grant$node),
    pool$max_new_numerical == 1L, grant$stage_deadline_epoch <= pool$expires_epoch)
  fd <- Sys.getenv('R154_GLOBAL_PERMIT_LOCK_FD')
  stopifnot(grepl('^[0-9]+$', fd),
    identical(Sys.readlink(file.path('/proc/self/fd',fd)), pool$resource_lock),
    any(grepl('FLOCK.*WRITE',readLines(file.path('/proc/self/fdinfo',fd)))))
  review <- jsonlite::read_json(r179_verify(grant$source_review), simplifyVector = FALSE)
  stopifnot(identical(review$status, 'PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'),
    identical(review$execution_adapter_source, grant$execution_adapter_source),
    identical(review$job_id, grant$job_id), identical(review$node, grant$node),
    identical(review$role, grant$role), identical(review$scope_id, grant$scope_id),
    identical(sort(r179_binding_map(review$source_bindings)), sort(r179_binding_map(grant$source_bindings))))
  boundary <- jsonlite::read_json(r179_verify(grant$scientific_boundary_qualification), simplifyVector = FALSE)
  boundary_guard <- jsonlite::read_json(r179_verify(boundary$owned_guard), simplifyVector = FALSE)
  stopifnot(identical(boundary$status, 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'),
    identical(boundary$original_guard_source_preserved, TRUE),
    identical(boundary_guard$schema, 'r157_traced_bootstrap_guard_receipt_v1'),
    identical(boundary_guard$status, 'EXITED'), boundary_guard$returncode == 0,
    identical(boundary_guard$reaped, TRUE), identical(boundary_guard$drained, TRUE),
    identical(boundary_guard$all_newborns_kernel_traced_before_execution, TRUE),
    identical(boundary_guard$postbootstrap_TSYNC_scientific_fork_denial, TRUE),
    identical(boundary_guard$scientific_target_access_handshake, TRUE),
    identical(boundary_guard$CPU_accounting_complete, TRUE),
    length(boundary_guard$remaining_owned_lifetimes) == 0L,
    identical(Sys.getenv('R179_CURRENT_TSYNC_ACK_REQUIRED'), '1'))
  invisible(list(pool=pool,expiry=expiry))
}
'''

TOY_PREFIX = '''# Versioned HB authority prefix; scientific suffix is byte-identical.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 4L)
root <- normalizePath(args[[1L]], mustWork = TRUE)
grant_path <- normalizePath(args[[2L]], mustWork = TRUE)
grant_sha <- args[[3L]]; output <- args[[4L]]; stopifnot(startsWith(output, '/'))
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
pin <- function(path) list(path = normalizePath(path, mustWork = TRUE), sha256 = hash(path))
verify <- function(value) { r179_verify(value) }
stopifnot(identical(Sys.getenv('R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED'), '1'),
  identical(hash(grant_path),grant_sha), !file.exists(output))
grant <- jsonlite::read_json(grant_path, simplifyVector = FALSE)
checked_job <- r179_job_gate(grant,'TOY_PARITY')
stopifnot(identical(grant$status,'ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY'),
  identical(grant$authorizes_toy_optimizer,TRUE), identical(grant$authorizes_production_fits,FALSE),
  grant$maximum_optimizer_invocations == 8L, grant$maximum_total_optimizer_iterations == 30L,
  grant$maximum_n == 128L, grant$maximum_p == 32L,
  grant$maximum_CPU_seconds > 0, grant$maximum_CPU_seconds <= 300,
  grant$memory_GiB == 8, grant$cores == 1)
source_id <- grant$source
stopifnot(identical(source_id$kind,'R154_project_fullstate_consumer_pinned_CRAN111'))
expiry <- checked_job$expiry; pool <- checked_job$pool
for (binding in grant$source_bindings) verify(binding)
required <- file.path(root, c('application/R/pricefm_r129_al_fixedpoint_certificate.R',
  'application/R/524_toy_fullstate_consumer.R', 'application/R/525_project_fullstate_consumer.R'))
stopifnot(all(required %in% names(r179_binding_map(grant$source_bindings))),
  identical(pin(grant$entrypoint$path), grant$entrypoint),
  grant$entrypoint$path %in% names(r179_binding_map(grant$source_bindings)))
runtime <- jsonlite::read_json(verify(grant$actual_R_runtime_binding),simplifyVector=FALSE)
stopifnot(identical(normalizePath(Sys.readlink('/proc/self/exe')),normalizePath(runtime$actual_executable)),
  identical(hash(runtime$actual_executable),runtime$actual_executable_sha256),
  identical(hash(runtime$Rscript),runtime$Rscript_sha256),
  identical(normalizePath(grant$cran_library),normalizePath(dirname(runtime$package_path))))
'''


def suffix(raw, marker):
    require(raw.count(marker) == 1, 'exact frozen scientific boundary marker required')
    return raw[raw.index(marker):]


def generate_toy(original):
    body=suffix(original,TOY_MARKER)
    result=COMMON+TOY_PREFIX+body
    require(suffix(result,TOY_MARKER)==body,'toy scientific bytes changed')
    return result


def generate_bridge(original):
    body=suffix(original,BRIDGE_MARKER)
    prefix=original[:original.index(BRIDGE_MARKER)]
    old_global=prefix[prefix.index("global <- jsonlite::read_json"):prefix.index("manifest <- jsonlite::read_json(manifest_path")]
    replacement="checked_job <- r179_job_gate(grant,if(mode=='bridge') 'ZERO_UPDATE_BRIDGE' else 'NO3_AL300_PILOT')\n"
    prefix=prefix.replace(old_global,replacement)
    old="for (key in c('design_dir','output_dir','parent_dir','cran_adapter','cran_manifest','fixedpoint_helper'))"
    new="for (key in c('design_dir','output_dir','parent_dir','cran_adapter','cran_manifest','fixedpoint_helper','cran_library'))"
    require(prefix.count(old)==1,'exact old runtime path resolver required')
    prefix=prefix.replace(old,new)
    result=COMMON+prefix+body
    require(suffix(result,BRIDGE_MARKER)==body,'bridge/pilot scientific bytes changed')
    require('muscat_cpu30' not in result and "'30'" not in prefix,'old host authority leaked into HB port')
    return result


def write_ports(native_root,output):
    native_root=Path(native_root);output=Path(output)
    require(output.is_absolute() and not output.exists() and output.parent.is_dir(),'new exact source output required')
    original_toy=native_root/'application/tests/525_project_projection_toy_validation.R'
    original_bridge=native_root/'application/scripts/pricefm/525_project_bridge_or_pilot.R'
    toy=original_toy.read_text();bridge=original_bridge.read_text()
    results={'toy':generate_toy(toy),'bridge_or_pilot':generate_bridge(bridge)}
    output.mkdir(mode=0o700)
    pins={}
    for key,text in results.items():
        path=output/('r179_hb_'+key+'.R')
        with path.open('x') as f:f.write(text)
        marker=TOY_MARKER if key=='toy' else BRIDGE_MARKER
        original=toy if key=='toy' else bridge
        pins[key]={'path':str(path),'sha256':hashlib.sha256(text.encode()).hexdigest(),
                   'original_path':str(original_toy if key=='toy' else original_bridge),
                   'original_sha256':hashlib.sha256(original.encode()).hexdigest(),
                   'scientific_suffix_sha256':hashlib.sha256(suffix(original,marker).encode()).hexdigest(),
                   'scientific_suffix_byte_identical':True,'R_parsing_and_execution_not_performed':True}
    return pins
