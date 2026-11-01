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
if (identical(spec$role,'ZERO_UPDATE_BRIDGE')) {
  base::options(error=base::local({
    measure_names <- c('beta_posterior_sd_rms','covariance_whitened_rms',
      'elbo_relative','predictor_rms','rhs_joint_log_rates',
      'rhs_start_log_precision','sigma_relative')
    rhs_number_names <- c('unit_iterations','dispersed_iterations',
      'unit_residual','dispersed_residual')
    rhs_boolean_names <- c('unit_converged','dispersed_converged')
    named <- function(value,labels) { names(value) <- labels;value }
    original_limits <- named(base::as.list(c(1e-4,1e-4,1e-8,1e-6,1e-6,1e-6,1e-6)),measure_names)
    text_ok <- function(value,limit) base::is.character(value) && base::length(value)==1L &&
      !base::is.na(value) && base::nchar(value,type='bytes')<=limit
    pin_ok <- function(value) base::is.list(value) && !base::is.object(value) &&
      base::setequal(base::names(value),c('path','sha256')) &&
      text_ok(value$path,1024L) && base::grepl('^/[A-Za-z0-9_./-]+$',value$path) &&
      text_ok(value$sha256,64L) && base::grepl('^[0-9a-f]{64}$',value$sha256)
    context_complete <- base::is.list(spec$source_parse_files) &&
      base::length(spec$source_parse_files)==5L &&
      base::all(base::vapply(spec$source_parse_files,pin_ok,base::logical(1L))) &&
      pin_ok(spec$scientific_entrypoint) && pin_ok(list(path=spec_path,sha256=spec_sha)) &&
      text_ok(spec$job_id,32L) && text_ok(spec$node,128L) && text_ok(spec$nonce,128L)
    bounded_text <- function(value,limit) if (text_ok(value,limit)) value else 'UNAVAILABLE'
    context <- list(role='ZERO_UPDATE_BRIDGE',job_id=bounded_text(spec$job_id,32L),
      node=bounded_text(spec$node,128L),nonce=bounded_text(spec$nonce,128L),
      source_files=if(context_complete) spec$source_parse_files else list(),
      entrypoint=if(context_complete) spec$scientific_entrypoint else NULL,
      bootstrap_spec=if(context_complete) list(path=spec_path,sha256=spec_sha) else NULL,
      context_complete=context_complete)
    field <- function(object,key) {
      if ((!base::is.list(object) && !base::is.atomic(object)) || base::is.object(object) ||
          !base::is.null(base::dim(object)) || base::length(object)>64L) return(NULL)
      index <- base::match(key,base::names(object),nomatch=0L)
      if (index==0L) NULL else object[[index]]
    }
    scalar <- function(value,kind='number') {
      if (base::is.null(value)) return(list(available=FALSE,label='UNAVAILABLE'))
      if (!base::is.atomic(value) || base::length(value)!=1L ||
          !base::is.null(base::dim(value)) || base::is.object(value))
        return(list(available=FALSE,label='REDACTED_NONSCALAR'))
      if (identical(kind,'boolean')) {
        if (!base::is.logical(value)) return(list(available=FALSE,label='REDACTED_TYPE'))
        if (base::is.na(value)) return(list(available=TRUE,kind='nonfinite',label='NA'))
        return(list(available=TRUE,kind='boolean',value=base::isTRUE(value)))
      }
      if (!base::typeof(value) %in% c('integer','double'))
        return(list(available=FALSE,label='REDACTED_TYPE'))
      if (base::is.nan(value)) return(list(available=TRUE,kind='nonfinite',label='NaN'))
      if (base::is.na(value)) return(list(available=TRUE,kind='nonfinite',label='NA'))
      if (!base::is.finite(value)) return(list(available=TRUE,kind='nonfinite',
        label=if(value>0) 'Inf' else '-Inf'))
      list(available=TRUE,kind='number',value=base::as.double(value[[1L]]))
    }
    object <- function(name) {
      if (!base::exists(name,envir=.GlobalEnv,inherits=FALSE) ||
          base::bindingIsActive(name,.GlobalEnv)) return(NULL)
      value <- base::get(name,envir=.GlobalEnv,inherits=FALSE)
      if (!base::is.list(value) || base::is.object(value) ||
          !base::is.null(base::dim(value)) || base::length(value)>64L) NULL else value
    }
    certificate <- function(value) {
      numbers <- function(container,names) named(base::lapply(names,
        function(key) scalar(field(container,key))),names)
      rhs <- field(value,'rhs_reconstruction')
      list(available=!base::is.null(value),
        measures=numbers(field(value,'measures'),measure_names),
        limits=numbers(field(value,'limits'),measure_names),
        certified=scalar(field(value,'certified'),'boolean'),
        raw_reconstructed_elbo=scalar(field(value,'raw_reconstructed_elbo')),
        raw_next_elbo=scalar(field(value,'raw_next_elbo')),
        rhs_reconstruction=c(numbers(rhs,rhs_number_names),named(
          base::lapply(rhs_boolean_names,function(key) scalar(field(rhs,key),'boolean')),rhs_boolean_names)))
    }
    function() {
      base::tryCatch({
        fallback <- c(list(schema='r188_post_ACK_bridge_scalar_diagnostic_v1',
          status='R188_BRIDGE_SCALARS_AFTER_ACK_FAILED_NOT_ACCEPTANCE'),context,
          list(diagnostic_available=FALSE,logging='UNAVAILABLE',original_limits=original_limits,
            current_cert=list(available=FALSE),old_cert=list(available=FALSE),
            terminal_sigma=list(available=FALSE,label='UNAVAILABLE'),R_exit_status=1L,
            numerical_acceptance=FALSE))
        encode <- function(value) jsonlite::toJSON(value,auto_unbox=TRUE,digits=17,null='null',na='null')
        text <- base::tryCatch(encode(c(list(schema='r188_post_ACK_bridge_scalar_diagnostic_v1',
          status='R188_BRIDGE_SCALARS_AFTER_ACK_FAILED_NOT_ACCEPTANCE'),context,
          list(diagnostic_available=context_complete,logging='SCALAR_WHITELIST_ONLY',original_limits=original_limits,
            current_cert=certificate(object('cert')),old_cert=certificate(object('old_cert')),
            terminal_sigma=scalar(field(object('terminal'),'sigma')),R_exit_status=1L,
            numerical_acceptance=FALSE))),error=function(error) encode(fallback))
        if (base::nchar(text,type='bytes')>16384L) text <- encode(fallback)
        if (base::nchar(text,type='bytes')<=16384L) {
          base::cat(text,'\n',sep='');base::flush(base::stdout())
        }
      },error=function(error) base::invisible(NULL))
      base::quit(status=1L,save='no',runLast=FALSE)
    }
  }))
}
source(spec$scientific_entrypoint$path)
