# Exact conditional H2 reference for the locked generated affine AL fixture.
# This does not qualify the retained nonlinear DESNs or an uncertain-parameter
# application posterior. All51 unit factors and both source scales are kept.
gvar_exact_h2 <- function(binding, eta) {
  gafsp_assert(binding)
  stopifnot(binding$fixture$horizon==2L)
  decoded <- binding$private$gcat_decode(eta,binding$spec)
  if(is.null(binding$fixture$members)) return(list(log_evidence=0,member_factors=0L,
    terminal_Y_integral=1,production_qualified=FALSE))
  spec <- binding$spec; f <- binding$fixture; theta <- decoded$coefficients
  muY <- sum(f$reference_features[1L,]*theta[spec$blocks$beta$index])
  muG <- as.numeric(f$reference_features %*% theta[spec$blocks$beta$index] +
    f$discrepancy_features %*% theta[spec$blocks$alpha$index] + f$known_baseline)
  sigmaY <- unname(decoded$sigma["Y"]);sigmaG <- unname(decoded$sigma["G"])
  lag <- f$reference_lag+f$discrepancy_lag;p <- spec$probability
  first <- sum(gcpr_log_al(f$members[1L,],muG[1L],p,sigmaG))
  piece <- gcpr_piecewise(c(1,rep(-lag,51L)),c(-muY,f$members[2L,]-muG[2L]),
    c(sigmaY,rep(sigmaG,51L)),p)
  list(log_evidence=first+piece$log_integral,first_horizon_log_likelihood=first,
    integrated_future_Y1_mean=piece$mean,terminal_Y_integral=1,
    sigmaY=sigmaY,sigmaG=sigmaG,member_factors=102L,member_weights=rep(1,102L),
    scope="Exact piecewise-exponential affine H2 conditional reference; parameters held fixed, both source scales retained",
    original_reads=0L,production_qualified=FALSE)
}
gvar_compare_h2 <- function(spec, reference_features, discrepancy_features, members,
    eta_points, counts=c(16L,64L,256L),replicates=16L,
    reference_lag=.03,discrepancy_lag=-.01,known_baseline=c(.07,.08)) {
  stopifnot(is.list(eta_points),length(eta_points)>=1L,length(eta_points)<=8L,
    is.numeric(counts),length(counts)>=1L,length(counts)<=4L,!anyDuplicated(counts),
    all(counts>=2&counts<=4096&counts==floor(counts)),is.numeric(replicates),
    length(replicates)==1L,is.finite(replicates),replicates==floor(replicates),
    replicates>=4L,replicates<=64L)
  rows <- list();summary <- list()
  for(i in seq_along(eta_points)) for(n in counts) {
    b <- gafsp_make_generated_al_binding(spec,reference_features,discrepancy_features,members,
      reference_lag=reference_lag,discrepancy_lag=discrepancy_lag,
      known_baseline=known_baseline,particles=as.integer(n))
    exact <- gvar_exact_h2(b,eta_points[[i]])$log_evidence
    records <- vector("list",replicates)
    for(j in seq_len(replicates)) {
      seed <- 2026111000L+100L*i+j
      started <- proc.time()[["elapsed"]]
      x <- b$evidence(eta_points[[i]],seed)
      elapsed <- proc.time()[["elapsed"]]-started
      records[[j]] <- data.frame(point=i,particles=n,replicate=j,seed=seed,
        complete=x$complete,particle_thresholds_passed=x$diagnostic_thresholds_passed,
        exact_log_evidence=exact,estimated_log_evidence=x$log_estimate,
        relative_evidence=if(isTRUE(x$complete)) exp(x$log_estimate-exact) else NA_real_,
        minimum_ESS=x$min_ess,minimum_initial_ancestors=x$min_unique_ancestors,
        callback_calls=x$callback_calls,elapsed_seconds=as.numeric(elapsed),production_qualified=FALSE)
    }
    table <- do.call(rbind,records);rows[[length(rows)+1L]] <- table
    complete <- all(table$complete)&all(is.finite(table$relative_evidence))
    values <- if(complete) table$relative_evidence else rep(NA_real_,replicates)
    log_values <- if(complete) table$estimated_log_evidence else rep(NA_real_,replicates)
    summary[[length(summary)+1L]] <- data.frame(point=i,particles=n,replicates=replicates,
      all_complete=complete,all_particle_thresholds_passed=all(table$particle_thresholds_passed),
      mean_relative_evidence=mean(values),relative_evidence_MCSE=stats::sd(values)/sqrt(replicates),
      mean_log_estimate=mean(log_values),empirical_Jensen_gap=exact-mean(log_values),
      single_log_estimate_SD=stats::sd(log_values),mean_log_estimate_MCSE=stats::sd(log_values)/sqrt(replicates),
      mean_evidence_reference_check=complete&&abs(mean(values)-1)<=5*stats::sd(values)/sqrt(replicates)+.01,
      single_estimate_precision_review=!complete||stats::sd(log_values)>.01,
      production_qualified=FALSE)
  }
  list(records=do.call(rbind,rows),summary=do.call(rbind,summary),
    interpretation="Finite replicated diagnostics; realized log estimates/gaps are not certified lower bounds or proof of full parameter accuracy",
    original_reads=0L,production_qualified=FALSE)
}
