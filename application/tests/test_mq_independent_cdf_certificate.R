source("application/R/integrated_quantile_forecast.R")
source("scripts/mq_independent_cdf_certificate.R")
icc_n <- 0L
icc_check <- function(ok) { stopifnot(isTRUE(ok)); icc_n <<- icc_n + 1L }
icc_reject <- function(expr) icc_check(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
icc_close <- function(a, b, tol = 1e-12)
  isTRUE(all.equal(a, b, tolerance = tol, check.attributes = FALSE))
set.seed(93074); icc_rng <- .Random.seed

icc_contract <- function(n) list(schema_version = "mq_independent_cdf_certificate_contract_v1",
  method = "heldout_conditional_CDF_empirical_Bernstein",
  conditioning = "one_fixed_original_parameter_draw_and_observed_origin",
  validation_values = "iid_future_path_conditional_CDF_not_particle_filter",
  candidates_from_training_paths_only = TRUE, rng_namespace = "synthetic-mq-future-law",
  draw_id = "original-chain1-draw1", origin_id = "observed-origin1",
  training_path_indices = 1:64, validation_path_indices = 64L + seq_len(n),
  alpha = .05, absolute_quantile_tolerance = .01, relative_quantile_tolerance = .01)
candidate <- data.frame(horizon = 1L, probability = .5, quantile = 0)
g <- mq_icc_candidates(candidate)
icc_check(identical(g$endpoint_count, 2L))
icc_check(icc_close(g$endpoints$y, c(-.01,.01)))
icc_check(identical(g$endpoints$side, c("lower", "upper")))
N <- 10000L
values <- matrix(rep(pnorm(g$endpoints$y), each = N), N, dimnames = list(NULL,g$endpoints$endpoint_id))
out <- mq_icc_certify(candidate, values, icc_contract(N))
icc_check(identical(out$status, "PASS_HELDOUT_FUTURE_CDF_QUANTILE_BOUND_ONLY"))
icc_check(all(out$result$pass))
icc_check(icc_close(out$endpoint_evidence$sample_variance, c(0,0)))
icc_check(icc_close(out$endpoint_evidence$radius, rep(7*log(4*2/.05)/(3*(N-1)),2)))
icc_check(out$endpoint_evidence$radius[1L] > 0) # no zero-variance MC shortcut
icc_check(!out$particle_filter_accuracy_certified && !out$origin_filter_accuracy_certified &&
  !out$independent_stream_generation_authenticated && !out$source_identity_authenticated &&
  !out$production_authorized && out$no_campaign_wide_familywise_guarantee)
icc_check(out$random_draws_generated == 0L && out$new_model_fits == 0L && !out$observational_future_truth_used)

# Correct n-1 sample variance and finite-union allocation across all endpoints.
small <- matrix(c(.1,.2,.3,.4,.6,.7,.8,.9),4L,
  dimnames=list(NULL,g$endpoints$endpoint_id))
z <- mq_icc_certify(candidate, small, icc_contract(4L))
v <- apply(small,2L,var); r <- sqrt(2*v*log(4*2/.05)/4) + 7*log(4*2/.05)/(3*3)
icc_check(icc_close(z$endpoint_evidence$radius, r))
icc_check(icc_close(z$endpoint_evidence$mean, colMeans(small)))
icc_check(all(z$endpoint_evidence$CDF_LCB >= 0 & z$endpoint_evidence$CDF_UCB <= 1))
icc_check(identical(z$status, "REVIEW_HELDOUT_FUTURE_CDF_QUANTILE_BOUND"))
strict <- icc_contract(N); strict$alpha <- .025
s <- mq_icc_certify(candidate, values, strict)
icc_check(all(s$endpoint_evidence$radius > out$endpoint_evidence$radius))

many <- data.frame(horizon = rep(1:2,each=2L), probability = rep(c(.25,.75),2L),
  quantile = rep(qnorm(c(.25,.75)),2L))
gm <- mq_icc_candidates(many)
vm <- matrix(rep(pnorm(gm$endpoints$y),each=N),N,
  dimnames=list(NULL,gm$endpoints$endpoint_id))
om <- mq_icc_certify(many,vm,icc_contract(N))
icc_check(om$endpoint_count == 8L)
icc_check(all(om$result$pass))
icc_check(icc_close(om$endpoint_evidence$radius,rep(7*log(4*8/.05)/(3*(N-1)),8)))

# Large-magnitude quantiles use the existing absolute-OR-relative radius,
# rather than accidentally requiring both criteria.
large <- candidate; large$quantile <- 100
gl <- mq_icc_candidates(large)
icc_check(icc_close(gl$delta,1))
icc_check(icc_close(gl$endpoints$y,c(99,101)))

# A point mass can be certified with strict-lower/non-strict-upper CDF
# inequalities. A false midpoint on a flat CDF is rejected, never inverted
# as a root. A correct atom at exactly p can also remain conservatively REVIEW.
atomN <- 100L
atom <- matrix(rep(c(0,1),each=atomN),atomN,
  dimnames=list(NULL,g$endpoints$endpoint_id))
pa <- mq_icc_certify(candidate,atom,icc_contract(atomN))
icc_check(all(pa$result$pass))
flat <- atom; flat[] <- .5
pf <- mq_icc_certify(candidate,flat,icc_contract(atomN))
icc_check(!any(pf$result$pass))
boundary <- atom; boundary[,2L] <- .5
pb <- mq_icc_certify(candidate,boundary,icc_contract(atomN))
icc_check(!any(pb$result$pass))

# Same-path and prefix-overlap validation are forbidden. Merely changing an
# administrative role or calling particles "validation paths" does not pass.
for (mutate in list(
  function(x) {x$validation_path_indices <- x$training_path_indices; x},
  function(x) {x$validation_path_indices[1L] <- 64L; x},
  function(x) {x$training_path_indices <- c(1L,2L,2L); x},
  function(x) {x$validation_path_indices[2L] <- x$validation_path_indices[1L]; x},
  function(x) {x$validation_path_indices[1L] <- 64.5; x},
  function(x) {x$validation_path_indices <- x$validation_path_indices[-1L]; x},
  function(x) {x$candidates_from_training_paths_only <- FALSE; x},
  function(x) {x$validation_values <- "resampled_filter_particles"; x},
  function(x) {x$conditioning <- "updated_static_parameter_posterior"; x},
  function(x) {x$rng_namespace <- ""; x},
  function(x) {x$draw_id <- NA_character_; x},
  function(x) {x$alpha <- .1; x},
  function(x) {x$alpha <- 0; x},
  function(x) {x$absolute_quantile_tolerance <- .011; x},
  function(x) {x$relative_quantile_tolerance <- .011; x}
)) icc_reject(mq_icc_certify(candidate,values,mutate(icc_contract(N))))
for (mutate in list(
  function(x) {x[1L] <- NA_real_; x},
  function(x) {x[1L] <- -1e-12; x},
  function(x) {x[1L] <- 1+1e-12; x},
  function(x) {x[1L,] <- c(.9,.1); x},
  function(x) {colnames(x) <- rev(colnames(x)); x},
  function(x) {x[,1L,drop=FALSE]}
)) icc_reject(mq_icc_certify(candidate,mutate(values),icc_contract(N)))
icc_reject(mq_icc_candidates(many[-1L,]))
bad <- many; bad$quantile[1:2] <- rev(bad$quantile[1:2])
icc_reject(mq_icc_candidates(bad))
bad <- candidate; bad$probability <- 1
icc_reject(mq_icc_candidates(bad))

# Equal endpoint arguments in two candidate brackets must receive equal CDF
# values for each path, not merely weakly increasing values.
tie <- data.frame(horizon=1L,probability=c(.25,.75),quantile=c(0,.02))
gt <- mq_icc_candidates(tie)
tv <- matrix(rep(c(.2,.4,.5,.8),each=100L),100L,
  dimnames=list(NULL,gt$endpoints$endpoint_id))
icc_check(identical(gt$endpoints$y[2L],gt$endpoints$y[3L]))
icc_reject(mq_icc_certify(tie,tv,icc_contract(100L)))

# Structural H1 exactness needs the separate source-derived proof. Zero
# sample variance alone never reaches this branch.
qtau <- c(.05,.5,.95); qq <- c(-1,0,1)
kernel <- list(family="mq_grid",q=qq,tau=qtau)
hash64 <- paste(rep("a",64),collapse="")
proof <- list(schema_version="mq_identical_first_kernel_source_proof_v1",horizon=1L,
  construction="deterministic_observed_prefix_no_future_response_in_first_features",
  all_first_path_kernels_identical_by_source=TRUE,
  source_commit=paste(rep("b",40),collapse=""),source_manifest_sha256=hash64,
  posterior_target_sha256=hash64,kernel_sha256=app_iqf_hash(kernel),
  draw_id="original-chain1-draw1",origin_id="observed-origin1")
exact <- mq_icc_exact_first_horizon(qq,qtau,c(.01,.05,.5,.95,.99),proof)
icc_check(icc_close(exact$quantile,c(-1,-1,0,1,1)))
icc_check(!exact$production_authorized && !exact$source_identity_authenticated &&
  !exact$origin_filter_accuracy_certified && !exact$particle_filter_accuracy_certified)
icc_check(exact$future_Monte_Carlo_error == 0 && exact$random_draws_generated == 0L)
for (mutate in list(
  function(x) {x$source_commit <- "short"; x},
  function(x) {x$source_manifest_sha256 <- NULL; x},
  function(x) {x$kernel_sha256 <- hash64; x},
  function(x) {x$horizon <- 2L; x},
  function(x) {x$all_first_path_kernels_identical_by_source <- FALSE; x},
  function(x) {x$construction <- "zero_sample_variance"; x}
)) icc_reject(mq_icc_exact_first_horizon(qq,qtau,.5,mutate(proof)))
icc_reject(mq_icc_exact_first_horizon(qq,qtau,.5,list(sample_variance=0)))
icc_check(identical(.Random.seed,icc_rng))
cat(sprintf("MQ_INDEPENDENT_CDF_CERTIFICATE_CHECKS=%d PASS; fits=0 protected_reads=0 production=FALSE\n",icc_n))
