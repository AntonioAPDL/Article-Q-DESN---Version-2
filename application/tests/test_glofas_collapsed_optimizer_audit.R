local({
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R",local=TRUE)
  source("scripts/audit_glofas_collapsed_optimizer_generated.R",local=TRUE)
  control <- gcpopt_control(max_iterations=4L,minimum_iterations=1L,batch_size=4L,
    stable_iterations=2L,max_wall_seconds=30,max_evaluations=1000L,
    inner_call_bound=1L,max_inner_calls=10000L)
  result <- gcpoa_compute(c(generated=paste(rep("a",64),collapse="")),control)
  stopifnot(identical(as.character(result$summary$fixture),c("no_members","moderate_51","concentrated_51")),
    nrow(result$summary)==3L,all(result$summary$members==c(0L,51L,51L)),
    all(is.finite(result$summary$exact_achieved_ELBO)),
    all(!result$summary$application_qualified),
    all(!result$summary$optimizer_accuracy_gate[-1L]),
    all(result$summary$original_reads==0L),length(result$histories)==3L,
    all(vapply(result$histories,nrow,integer(1L))<=4L),
    result$summary$minimum_family_KL[3L]>.1,
    all(result$summary$reference_optimizer_convergence==0L))
  cat("GLOFAS_COLLAPSED_OPTIMIZER_AUDIT_PASS checks=11 fixtures=3 original_reads=0 application_fits=0\n")
})
