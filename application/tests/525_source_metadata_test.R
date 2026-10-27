#!/usr/bin/env Rscript
# Source/AST and opaque checkpoint serialization only. ZERO optimizer calls.
args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
root <- normalizePath(args[[1L]]); output <- normalizePath(args[[2L]])
source(file.path(root, 'application/R/525_project_fullstate_consumer.R'))
manifest <- jsonlite::read_json(file.path(root, 'application/config/pricefm/525_conditional_pilot_plan.json'))
original <- jsonlite::read_json(manifest$original_manifest$path)
source(original$targets[[1L]]$contract$fixedpoint_helper)
ns <- r129_namespace(original$targets[[1L]]$contract$cran_library)
stock <- get('.run_static_dqlm_cavi', ns)
original_body <- body(stock)
stopifnot(identical(digest::digest(original_body, algo='sha256'), manifest$expected_stock_body_sha256))
ctx <- list2env(list(origin='checkpoint_fixture_not_real_target', source=list(kind='metadata_fixture'),
 posterior_target_sha256='not_a_scientific_target', data_references=list(X=list(path='opaque_X_reference',sha256=paste(rep('a',64),collapse='')),y=list(path='opaque_y_reference',sha256=paste(rep('b',64),collapse=''))),
 original_failed=list(), checkpoint_entries=list(), disk_bytes=1024^2),parent=emptyenv())
projected <- r525_make_engine(ns,ctx,output)
items <- as.list(body(projected))
stopifnot(grepl('r525_gate_bound',paste(deparse(items[[2L]]),collapse=' ')))
items <- items[-2L]
restore <- which(vapply(items,function(x)grepl('r525_restore_bound',paste(deparse(x),collapse=' ')),logical(1)))
stopifnot(length(restore)==1L); items <- items[-restore]
loop_index <- which(vapply(items,function(x)is.call(x)&&identical(x[[1L]],as.name('for')),logical(1)))
stopifnot(length(loop_index)==1L)
loop <- items[[loop_index]]; loop_items <- as.list(loop[[4L]])
hook <- which(vapply(loop_items,identical,logical(1),quote(r525_checkpoint_bound(environment()))))
stopifnot(length(hook)==1L, identical(loop_items[[hook+1L]][[2L]],quote(step$stop_now)))
loop[[4L]] <- as.call(loop_items[-hook]); items[[loop_index]] <- loop
stopifnot(identical(as.call(items),original_body),identical(body(get('.run_static_dqlm_cavi',ns)),original_body))
# Fixed literal fixture is deliberately not a valid production factor state.
frame <- list2env(list(m_beta=c(0,0),V_beta=diag(2),a_q=5,b_q=4,kappa=1.25,
 chi=c(1,1),psi=2,nu=c(1,1),ell=c(1,1),mlogv=c(0,0),
 beta_state=list(opaque_fixture=TRUE),beta_prior_obj=list(controls=list(fixture=TRUE)),
 iter=1L,stable_count=3L,step=list(stop_now=FALSE),controls=list(fixture=TRUE),converged=FALSE,
 elbo_trace=c(1),seq.sigma=1,delta_beta=0,delta_sigma=0,delta_elbo=0),parent=emptyenv())
set.seed(710); rng <- .Random.seed
stopifnot(dir.create(file.path(output,'checkpoints')))
r525_checkpoint(frame,ctx,output)
stopifnot(length(ctx$checkpoint_entries)==1L)
entry <- ctx$checkpoint_entries[[1L]]
state <- readRDS(entry$state_pin$path)
stopifnot(identical(state$factors$origin,'checkpoint_fixture_not_real_target'),
 identical(state$factors$qbeta$m,c(0,0)),identical(state$factors$rhs_state,list(opaque_fixture=TRUE)),
 identical(state$optimizer$RNG_before_post_sampling,rng),state$optimizer$completed_sweep==1L,
 identical(state$data_references,ctx$data_references),
 identical(entry$state_pin$sha256,digest::digest(entry$state_pin$path,file=TRUE,algo='sha256')),
 !('X' %in% names(state)),!('y' %in% names(state)),
 identical(state$optimizer$stable_count,3L),isFALSE(state$optimizer$resume_supported_by_this_adapter))
stopifnot(inherits(try(suppressWarnings(r525_checkpoint(frame,ctx,output)),silent=TRUE),'try-error'))
# Closed production dimension/admission checks stay in place.
stopifnot(inherits(try(r525_closed_data_limits(ctx,matrix(0,2,2),c(0,0)),silent=TRUE),'try-error'))
proof <- list(schema='r154_project_metadata_source_test_v1',stock_AST_exactly_preserved=TRUE,
 checkpoint_opaque_fixture_IO_verified=TRUE,production_guard_rejects_fixture=TRUE,
 optimizer_invocations=0L,production_data_used=FALSE,numerical_parity_proved=FALSE)
jsonlite::write_json(proof,file.path(output,'metadata_proof.json'),auto_unbox=TRUE,pretty=TRUE)
cat('PASS source/AST/opaque checkpoint I/O; zero optimizer; numerical parity still pending\n')
