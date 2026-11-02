#!/usr/bin/env Rscript
# Bounded synthetic profile, not an authentic-source qualifier or admission.
for (file in c("joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "latent_path_design.R", "joint_qdesn_pure_recursive_campaign.R",
  "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R")) source(file.path("application/R", file))
source("scripts/integrated_quantile_mq_batch.R")
source("scripts/mq_forecast_array_methods.R")
`%||%` <- function(a,b) if(is.null(a)) b else a
mqb_tau <- c(.05,.1,.25,.5,.75,.9,.95)
mqb_hash <- paste(rep("a",64L),collapse="")
ast <- parse(file="application/tests/test_integrated_quantile_mq_batch.R")
j <- which(vapply(ast,function(e)is.call(e)&&identical(e[[1L]],as.name("<-"))&&
  identical(e[[2L]],as.name("mqb_fixture")),logical(1L)))
stopifnot(length(j)==1L); eval(ast[[j]])
f <- mqb_fixture(); f$origins$o8$H <- 10L
a <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=512L,batch_size=128L,
  rng_mode="r46_first_step_qualified",rng_proof=app_iqf_mqb_rng_reference())))
draw <- f$posterior$draw_ids[1L]; ids <- 1:512
measure <- function(label,fun,repeats=3L) {
  invisible(gc()); times <- matrix(NA_real_,repeats,2L)
  for(i in seq_len(repeats)) {
    t <- system.time(out <- fun());times[i,] <- t[c("user.self","elapsed")]
  }
  data.frame(operation=label,repeats=repeats,user_median=median(times[,1L]),
    elapsed_median=median(times[,2L]),last_result_bytes=as.numeric(object.size(out)))
}
old <- app_iqf_mq_batch_paths(a,draw,"o8",ids)
new <- app_iqf_mq_batch_arrays(a,draw,"o8",ids)
stopifnot(identical(old$response,new$response),identical(old$ordered_quantiles,new$ordered_quantiles))
results <- list(measure("B512_H10_reference_path_lists",function()app_iqf_mq_batch_paths(a,draw,"o8",ids)),
  measure("B512_H10_array_without_coherence",function()app_iqf_mq_batch_arrays(a,draw,"o8",ids,FALSE)),
  measure("B512_H10_array_with_coherence",function()app_iqf_mq_batch_arrays(a,draw,"o8",ids,TRUE)))
q <- new$ordered_quantiles[,,10L]
kernels <- lapply(seq_len(nrow(q)),function(i)list(family="mq_grid",q=as.numeric(q[i,]),tau=mqb_tau))
stopifnot(isTRUE(all.equal(app_iqf_mq_matrix_inverse(q,mqb_tau,mqb_tau),
  app_iqf_mq_mixture_inverse(kernels,mqb_tau),tolerance=1e-12)))
results <- c(results,list(measure("N512_inverse_build_lists_and_sweep",function() {
  k <- lapply(seq_len(nrow(q)),function(i)list(family="mq_grid",q=as.numeric(q[i,]),tau=mqb_tau))
  app_iqf_mq_mixture_inverse(k,mqb_tau)
},20L),measure("N512_inverse_matrix_sweep",function()app_iqf_mq_matrix_inverse(q,mqb_tau,mqb_tau),20L)))
utils::write.csv(do.call(rbind,results),stdout(),row.names=FALSE)
profile <- function() {
  path <- tempfile("mq_array_synthetic_profile_")
  on.exit(unlink(path),add=TRUE)
  utils::Rprof(path,interval=.01)
  for(i in 1:3) invisible(app_iqf_mq_batch_arrays(a,draw,"o8",ids,TRUE))
  utils::Rprof(NULL)
  cat("PROFILE_ARRAY_WITH_COHERENCE_TOP10_BY_SELF\n")
  print(head(utils::summaryRprof(path)$by.self,10L))
}
profile()
cat("SYNTHETIC_ONLY=TRUE authentic_reads=0 production_authorized=FALSE\n")
