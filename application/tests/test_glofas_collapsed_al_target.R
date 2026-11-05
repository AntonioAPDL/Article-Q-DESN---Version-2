# Exact historical marginal-AL/NS target; generated in-memory arrays only.
local({
  source("scripts/diagnostics/glofas_collapsed_al_target.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_vi.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  block <- function(ix, fixed = NULL) list(index = ix, intercept_index = ix[1L], tau0 = .3,
    intercept_prec = .2, slab_shape = 2, slab_rate = 4, zeta2_fixed = fixed)
  spec <- gcat_spec(6, list(beta = block(1:3), alpha = block(4:6)), .2,
    list(Y = c(shape = 2, rate = 1), G = c(shape = 3, rate = .8)))
  ok(spec$dimension == 22L && length(spec$positive) == 16L &&
    spec$historical_auxiliaries == "AL_mixture_variables_integrated_out_exactly")
  H <- rbind(c(1,.2,-.3,0,0,0), c(1,.4,.1,0,0,0),
    c(1,.2,-.3,1,.4,.2), c(1,.4,.1,1,-.2,.1))
  z <- c(.2,.3,.4,.7); src <- c("Y","Y","G","G")
  binding <- gcat_bind_historical(spec, H, z, src)
  m <- seq(-.15, .1, length.out = spec$dimension)
  ls <- rep(log(.25), spec$dimension)
  density <- gcat_log_historical(m, binding)
  decoded <- gcat_decode(m, spec)
  literal <- sum(gcpr_log_al(z, as.numeric(H %*% m[1:6]), .2, decoded$sigma[src]))
  ig <- function(x, a, b) a * log(b) - lgamma(a) - (a + 1) * log(x) - b / x
  prior <- sum(vapply(c("Y","G"), function(s) ig(decoded$sigma[s],
    spec$scale_prior[[s]]["shape"], spec$scale_prior[[s]]["rate"]), numeric(1L)))
  for (b in spec$blocks) prior <- prior + gcpr_ns_log_joint(m[b$penalized],
    exp(m[b$tau]), exp(m[b$lambda]), exp(m[b$slab]), exp(m[b$xi]), exp(m[b$nu]),
    b$tau0, b$slab_shape, b$slab_rate) + stats::dnorm(m[b$intercept_index], 0,
      1 / sqrt(b$intercept_prec), log = TRUE)
  ok(abs(density - (literal + prior + sum(m[spec$positive]))) < 1e-12)
  ok(abs(gcat_log_prior(m, spec, "transformed") - gcat_log_prior(m, spec, "physical") -
    sum(m[spec$positive])) < 1e-12)
  analytic <- gcat_historical_elbo(m, ls, binding)
  step <- 1e-5
  for (j in seq_len(spec$dimension)) {
    delta <- rep(0, spec$dimension); delta[j] <- step
    gm <- (gcat_historical_elbo(m + delta, ls, binding)$value -
      gcat_historical_elbo(m - delta, ls, binding)$value) / (2 * step)
    gs <- (gcat_historical_elbo(m, ls + delta, binding)$value -
      gcat_historical_elbo(m, ls - delta, binding)$value) / (2 * step)
    ok(abs(gm - analytic$gradient_mean[j]) < 2e-7)
    ok(abs(gs - analytic$gradient_log_sd[j]) < 2e-7)
  }
  # Independent Gaussian integration of all analytic scalar prior moments and
  # AL expected check loss. Sobol/MC noise is not used to excuse a gradient.
  for (mu in c(-.2,.4)) for (sd in c(.1,.5)) {
    y <- .3; p <- .2
    direct <- stats::integrate(function(t) gcpr_rho(y - t, p) *
      stats::dnorm(t, mu, sd), -Inf, y, rel.tol = 1e-11)$value +
      stats::integrate(function(t) gcpr_rho(y - t, p) *
      stats::dnorm(t, mu, sd), y, Inf, rel.tol = 1e-11)$value
    r <- y - mu; a <- r / sd
    closed <- sd * stats::dnorm(a) + r * (p - stats::pnorm(a, lower.tail = FALSE))
    ok(abs(direct - closed) < 1e-10)
  }
  # Independent deterministic tensor Gaussian integration on all 22 variables
  # is unnecessary: exact Normal mgf moments determine every prior term.
  # A fixed-seed MC check tests the full point-density expectation jointly.
  old <- if (exists(".Random.seed", .GlobalEnv)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({ if (is.null(old)) { if (exists(".Random.seed", .GlobalEnv)) rm(".Random.seed", envir=.GlobalEnv)
    } else assign(".Random.seed",old,.GlobalEnv) }, add=TRUE)
  set.seed(2026110507)
  values <- replicate(4000L, {
    x <- m + exp(ls) * stats::rnorm(spec$dimension)
    gcat_log_historical(x, binding)
  })
  entropy <- sum(ls) + .5 * spec$dimension * (1 + log(2 * pi))
  err <- mean(values) + entropy - analytic$value
  ok(abs(err) < 5 * stats::sd(values) / sqrt(length(values)))
  ok(analytic$entropy_included && analytic$jacobian_count == 1L && !analytic$production_qualified)
  # Fixing only a slab is allowed if explicitly supplied; it is not a frozen
  # regression coefficient or a silent replacement of a learned slab.
  fixed <- gcat_spec(6, list(beta=block(1:3,4),alpha=block(4:6,9)), .5,
    list(Y=c(shape=2,rate=1),G=c(shape=2,rate=1)))
  ok(fixed$dimension == spec$dimension - 2L && all(vapply(fixed$blocks,
    function(b) !length(b$slab), logical(1L))))
  bf <- gcat_bind_historical(fixed,H,z,src)
  mf <- rep(.1,fixed$dimension); sf <- rep(-1,fixed$dimension)
  af <- gcat_historical_elbo(mf,sf,bf)
  ok(is.finite(gcat_log_historical(mf,bf)) && all(is.finite(af$gradient_mean)))
  reject(gcat_historical_elbo(m,ls,binding,factor=diag(spec$dimension)))
  reject(gcat_log_historical(m[-1L],binding))
  bad <- m; names(bad) <- rev(spec$coordinate_names); reject(gcat_log_historical(bad,binding))
  bad <- m; bad[spec$scales[1L]] <- 1000; reject(gcat_log_historical(bad,binding))
  reject(gcat_bind_historical(spec,H,z,src,rep(1/51,4)))
  badH <- H; badH[1L,4L] <- 1; reject(gcat_bind_historical(spec,badH,z,src))
  reject(gcat_bind_historical(spec,H,z,rep("Y",4L)))
  badblocks <- spec$blocks; badblocks$alpha <- block(c(3,5,6))
  reject(gcat_spec(6,badblocks,.2,spec$scale_prior))
  reject(gcat_log_prior(m,spec,"unknown_measure"))
  # Prior global conditional retains (r+1)/2, excluding intercepts.
  b <- spec$blocks$beta
  xs <- c(.05,.2,.9)
  log_values <- vapply(xs,function(tau) {
    x <- m; x[b$tau] <- log(tau)
    gcat_log_prior(x,spec,"physical")
  },numeric(1L))
  expected <- vapply(xs,function(tau) ig(tau,(length(b$penalized)+1)/2,
    exp(-m[b$xi]) + .5*sum(m[b$penalized]^2*exp(-m[b$lambda]))),numeric(1L))
  ok(diff(range(log_values-expected)) < 1e-10)
  # All source-specific scales and regression blocks enter the future
  # evidence. There is no replacement Gaussian path or 1/51 weighting.
  loc <- function(h,past,parameters) parameters$coefficients[1L] +
    parameters$coefficients[2L] * if(length(past)) tail(past,1) else 0
  mem <- function(h,past,parameters) loc(h,past,parameters) + parameters$coefficients[4L]
  ev <- gcat_make_evidence(spec,matrix(rep(.2,51),1,51),loc,mem,1L,particles=16L)
  e <- ev(m,2026110511L)
  expected <- sum(gcpr_log_al(rep(.2,51),m[1L]+m[4L],.2,decoded$sigma["G"]))
  ok(e$complete && abs(e$log_estimate-expected)<1e-10 &&
    e$source_scale_convention=="Y_future_G_members" && all(e$member_weights==1))
  # The final future-Y law integrates out: changing sigmaY alone cannot
  # change H1 member evidence; sigmaG and discrepancy coefficients can.
  my <- m; my[spec$scales["Y"]] <- my[spec$scales["Y"]]+.2
  mg <- m; mg[spec$scales["G"]] <- mg[spec$scales["G"]]+.2
  ma <- m; ma[4L] <- ma[4L]+.1
  ok(abs(ev(my,2026110511L)$log_estimate-e$log_estimate)<1e-10 &&
    abs(ev(mg,2026110511L)$log_estimate-e$log_estimate)>.01 &&
    abs(ev(ma,2026110511L)$log_estimate-e$log_estimate)>.01)
  empty <- gcat_make_evidence(spec,NULL,loc,mem,2L)
  ok(identical(empty(m,2026110511L)$log_estimate,0) && empty(m,2026110511L)$callback_calls==0L)
  reject(gcat_make_evidence(spec,matrix(.2,1,50),loc,mem,1L))
  # Verify the actual application-sized parameter inventory using generated
  # four-row arrays only; this is NOT a native runtime or accuracy benchmark.
  big <- gcat_spec(2502,list(beta=block(1:1501),alpha=block(1502:2502)),.5,
    list(Y=c(shape=2,rate=1),G=c(shape=2,rate=1)))
  hb <- matrix(0,4,2502); hb[,1] <- 1; hb[3:4,1502] <- 1
  bb <- gcat_bind_historical(big,hb,z,src)
  eb <- gcat_historical_elbo(rep(.01,big$dimension),rep(-2,big$dimension),bb)
  ok(big$dimension==7510L && length(eb$gradient_mean)==7510L &&
    length(eb$gradient_log_sd)==7510L && all(is.finite(c(eb$value,eb$gradient_mean,eb$gradient_log_sd))))
  cat(sprintf("GLOFAS_COLLAPSED_AL_TARGET_PASS checks=%d parameter_dimensions=%d original_reads=0 application_fits=0\n",n,spec$dimension))
})
