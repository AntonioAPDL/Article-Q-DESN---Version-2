# Fully traced package bootstrap; zero optimizer calls/real target data.
# All original scientific fixture text is sourced only after TSYNC denial ACK.
args <- commandArgs(TRUE); stopifnot(length(args)==2L)
root <- normalizePath(args[[1L]]); output <- normalizePath(args[[2L]])
manifest <- jsonlite::read_json(file.path(root,'application/config/pricefm/525_conditional_pilot_plan.json'))
original <- jsonlite::read_json(manifest$original_manifest$path)
source(original$targets[[1L]]$contract$fixedpoint_helper)
ns <- r129_namespace(original$targets[[1L]]$contract$cran_library)
stopifnot(is.environment(ns),is.function(get('.run_static_dqlm_cavi',ns)))
loadNamespace('digest')
dyn.load(Sys.getenv('R157_BOUNDARY_LIBRARY'))
stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))
stopifnot(inherits(try(system('true',intern=TRUE),silent=TRUE),'try-error'))
source(file.path(root,'application/tests/525_source_metadata_test.R'))
