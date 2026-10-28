# Exact tested package/filter prefix, followed by an independently admitted payload.
root <- normalizePath(Sys.getenv('R157_PROJECT_ROOT'))
manifest <- jsonlite::read_json(file.path(root,'application/config/pricefm/525_conditional_pilot_plan.json'))
original <- jsonlite::read_json(manifest$original_manifest$path)
source(original$targets[[1L]]$contract$fixedpoint_helper)
ns <- r129_namespace(original$targets[[1L]]$contract$cran_library)
stopifnot(is.environment(ns),is.function(get('.run_static_dqlm_cavi',ns)))
loadNamespace('digest')
dyn.load(Sys.getenv('R157_BOUNDARY_LIBRARY'))
stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))
# Scientific inputs/optimizer are unreachable until the owning tracer ACKs.
kind <- Sys.getenv('R157_PROJECT_KIND')
stopifnot(kind %in% c('toy','production'))
source(file.path(root,if(kind=='toy') 'application/tests/525_project_projection_toy_validation.R'
  else 'application/scripts/pricefm/525_project_bridge_or_pilot.R'))
