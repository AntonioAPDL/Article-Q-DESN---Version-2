local({
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x));checks <<- checks+1L }
  source("scripts/diagnostics/glofas_collapsed_al_target.R",local=TRUE)
  source("scripts/diagnostics/glofas_al_future_score_projection.R",local=TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R",local=TRUE)
  source("scripts/diagnostics/glofas_variance_particle_reference.R",local=TRUE)
  block <- function(ix) list(index=ix,intercept_index=ix[1L],tau0=.3,intercept_prec=.2,
    slab_shape=2,slab_rate=4,zeta2_fixed=NULL)
  spec <- gcat_spec(6,list(beta=block(1:3),alpha=block(4:6)),.2,
    list(Y=c(shape=2,rate=1),G=c(shape=3,rate=.8)))
  F <- rbind(c(1,.2,-.1),c(1,.4,.1));D <- rbind(c(1,-.1,.3),c(1,.2,-.2))
  G <- rbind(seq(.08,.22,length.out=51),seq(.1,.24,length.out=51))
  eta <- seq(-.1,.1,length.out=spec$dimension)
  b <- gafsp_make_generated_al_binding(spec,F,D,G,reference_lag=.03,discrepancy_lag=-.01,
    known_baseline=c(.07,.08),particles=64L)
  exact <- gvar_exact_h2(b,eta)
  ok(is.finite(exact$log_evidence));ok(exact$member_factors==102L);ok(all(exact$member_weights==1))
  # With no response-lag dependence, both future Y factors integrate to one.
  independent <- gafsp_make_generated_al_binding(spec,F,D,G,known_baseline=c(.07,.08))
  physical <- gcat_decode(eta,spec)
  mu <- as.numeric(F%*%physical$coefficients[1:3]+D%*%physical$coefficients[4:6]+c(.07,.08))
  literal <- sum(gcpr_log_al(G[1,],mu[1],.2,physical$sigma["G"]))+
    sum(gcpr_log_al(G[2,],mu[2],.2,physical$sigma["G"]))
  ok(abs(gvar_exact_h2(independent,eta)$log_evidence-literal)<1e-10)
  # Every RHS coordinate cancels from the exact conditional future evidence.
  for(j in b$auxiliary) {
    change <- eta;change[j] <- change[j]+.03
    ok(identical(gvar_exact_h2(b,change)$log_evidence,exact$log_evidence))
  }
  empty <- gafsp_make_generated_al_binding(spec,F,D,NULL)
  ok(identical(gvar_exact_h2(empty,eta)$log_evidence,0))
  compare <- gvar_compare_h2(spec,F,D,G,list(eta),counts=c(8L,32L),replicates=4L)
  ok(nrow(compare$records)==8L);ok(nrow(compare$summary)==2L)
  ok(all(compare$records$complete));ok(all(!compare$summary$production_qualified))
  ok(all(is.finite(compare$summary$single_log_estimate_SD)))
  cat(sprintf("GLOFAS_VARIANCE_PARTICLE_REFERENCE_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
