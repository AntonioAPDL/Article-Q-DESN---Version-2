source("scripts/mq_independent_cdf_certificate.R")
source("scripts/mq_streaming_cdf_certificate.R")
scc_checks <- 0L
scc_check <- function(ok) { stopifnot(isTRUE(ok)); scc_checks <<- scc_checks + 1L }
scc_reject <- function(expr) scc_check(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
scc_close <- function(x, y, tol = 1e-13)
  isTRUE(all.equal(x, y, tolerance = tol, check.attributes = FALSE))
scc_had_rng <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
if (scc_had_rng) scc_original_rng <- get(".Random.seed", envir = .GlobalEnv)

scc_contract <- function(candidates) list(
  schema_version = "mq_streaming_cdf_certificate_contract_v1",
  method = "heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
  conditioning = "one_fixed_original_parameter_draw_and_observed_origin",
  validation_values = "iid_future_path_conditional_CDF_not_particle_filter",
  candidates_from_training_paths_only = TRUE, rng_namespace = "synthetic-future-law",
  draw_id = "original-chain1-draw1", origin_id = "observed-origin1",
  training_path_range = c(1L,65536L), validation_path_range = c(65537L,327680L),
  look_sizes = c(65536L,131072L,262144L), total_alpha = .05,
  alpha_per_look = rep(.05/3,3L), absolute_quantile_tolerance = .01,
  relative_quantile_tolerance = .01,
  training_split_diagnostic = data.frame(horizon = candidates$horizon,
    probability = candidates$probability, split_stream_absolute_difference = .004,
    split_stream_relative_difference = .006))

candidates <- data.frame(horizon = 1L, probability = c(.25,.75), quantile = c(-1,1))
contract <- scc_contract(candidates)
state <- mq_scc_init(candidates, contract)
scc_check(state$count == 0L && !state$terminal && state$next_look_index == 1L)
scc_check(identical(state$candidates_sha256, mq_scc_hash(candidates)))
scc_check(identical(state$contract_sha256, mq_scc_hash(contract)))
scc_check(nrow(state$blocks) == 0L && !state$raw_validation_matrix_retained)
scc_reject(mq_scc_evaluate(state))

N <- 65536L
variation <- .001*sin(seq_len(N)/31)
values <- cbind(.24+variation,.26+variation,.74+variation,.76+variation)
colnames(values) <- state$grid$endpoints$endpoint_id
first <- mq_scc_update(state, values[1:17,,drop=FALSE], 65537:65553)
scc_check(first$count == 17L && nrow(first$blocks) == 1L)
scc_check(identical(first$blocks$data_sha256[1L],
  mq_scc_hash(list(path_ids=65537:65553,values=values[1:17,,drop=FALSE]))))
scc_check(first$blocks$first_path_id == 65537L && first$blocks$last_path_id == 65553L)
scc_check(scc_close(first$mean,colMeans(values[1:17,,drop=FALSE])))
scc_reject(mq_scc_evaluate(first))
scc_reject(mq_scc_update(first,values[18:20,,drop=FALSE],65553:65555))
scc_reject(mq_scc_update(first,values[18:20,,drop=FALSE],c(65554,65556,65555)))
scc_reject(mq_scc_update(first,values[18:20,,drop=FALSE],c(65554,65554,65556)))
scc_reject(mq_scc_update(first,values[18:20,,drop=FALSE],c(65554,65555,65556.1)))
scc_reject(mq_scc_update(state,values[1:3,,drop=FALSE],65534:65536))
state <- first
starts <- seq.int(18L,N,by=128L)
for (a in starts) {
  b <- min(a+127L,N)
  state <- mq_scc_update(state,values[a:b,,drop=FALSE],65536L+seq.int(a,b))
}
scc_check(state$count == N && nrow(state$blocks) == length(starts)+1L)
scc_check(scc_close(state$mean,colMeans(values)))
scc_check(max(abs(state$M2/(N-1)-apply(values,2L,var))) < 1e-13)
scc_check(state$blocks$last_path_id[nrow(state$blocks)] == 131072L)
scc_reject(mq_scc_update(state,values[1,,drop=FALSE],131073L))
state <- mq_scc_evaluate(state)
certificate <- state$last_evaluation
scc_check(state$terminal && certificate$all_required_gates_pass)
scc_check(identical(certificate$status,"PASS_STREAMING_HELDOUT_FUTURE_CDF_QUANTILE_BOUND_ONLY"))
scc_check(length(state$look_history) == 1L && state$next_look_index == 2L)
scc_check(certificate$alpha == .05/3 && certificate$total_alpha == .05)
scc_check(certificate$alpha_spent == .05/3 && certificate$endpoint_count == 4L)
scc_check(!certificate$source_identity_authenticated &&
  !certificate$independent_stream_generation_authenticated &&
  !certificate$origin_filter_accuracy_certified && !certificate$particle_filter_accuracy_certified &&
  !certificate$production_authorized && certificate$no_campaign_wide_familywise_guarantee)
scc_check(certificate$random_draws_generated == 0L && certificate$new_model_fits == 0L &&
  !certificate$observational_future_truth_used && !certificate$raw_validation_matrix_retained)
scc_reject(mq_scc_evaluate(state))
scc_reject(mq_scc_update(state,values[1,,drop=FALSE],131073L))

# The streaming calculation equals the raw-matrix certificate at the same
# prespecified error allocation, including the unbiased n-1 variance.
raw_contract <- list(schema_version="mq_independent_cdf_certificate_contract_v1",
  method="heldout_conditional_CDF_empirical_Bernstein",
  conditioning=contract$conditioning,validation_values=contract$validation_values,
  candidates_from_training_paths_only=TRUE,rng_namespace=contract$rng_namespace,
  draw_id=contract$draw_id,origin_id=contract$origin_id,
  training_path_indices=seq_len(65536L),validation_path_indices=65536L+seq_len(N),
  alpha=.05/3,absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01)
raw <- mq_icc_certify(candidates,values,raw_contract)
scc_check(max(abs(raw$endpoint_evidence$mean-certificate$endpoint_evidence$mean)) < 1e-13)
scc_check(max(abs(raw$endpoint_evidence$sample_variance-
  certificate$endpoint_evidence$sample_variance)) < 1e-13)
scc_check(max(abs(raw$endpoint_evidence$radius-certificate$endpoint_evidence$radius)) < 1e-13)
scc_check(max(abs(raw$endpoint_evidence$CDF_LCB-certificate$endpoint_evidence$CDF_LCB)) < 1e-13)
scc_check(max(abs(raw$endpoint_evidence$CDF_UCB-certificate$endpoint_evidence$CDF_UCB)) < 1e-13)
scc_check(identical(raw$result$pass,certificate$result$pass))

# Different block partitions retain the same moments, while receipt hashes
# correctly bind the actual block partition rather than pretending otherwise.
one <- mq_scc_update(mq_scc_init(candidates,contract),values,65536L+seq_len(N))
one <- mq_scc_evaluate(one)
scc_check(max(abs(one$mean-state$mean)) < 1e-13)
scc_check(max(abs(one$M2-state$M2)) < 1e-13)
scc_check(!identical(one$last_chain_sha256,state$last_chain_sha256))

# Three fixed looks, no optional peeks, and no reset/recycling of the
# scientific validation IDs. A flat CDF stays conservatively REVIEW.
flat_candidates <- data.frame(horizon=1L,probability=.5,quantile=0)
flat_contract <- scc_contract(flat_candidates)
review <- mq_scc_init(flat_candidates,flat_contract)
for (look in seq_len(3L)) {
  needed <- flat_contract$look_sizes[look]-review$count
  val <- matrix(.5,needed,2L,dimnames=list(NULL,review$grid$endpoints$endpoint_id))
  if (look == 1L) {
    too_many <- rbind(val,val[1,,drop=FALSE])
    scc_reject(mq_scc_update(review,too_many,65536L+seq_len(nrow(too_many))))
  }
  ids <- seq.int(65537L+review$count,length.out=needed)
  review <- mq_scc_update(review,val,ids)
  review <- mq_scc_evaluate(review)
  ev <- review$last_evaluation
  scc_check(!ev$all_quantile_bounds_pass && !ev$all_required_gates_pass)
  scc_check(ev$look_index == look && ev$validation_paths == flat_contract$look_sizes[look])
  scc_check(scc_close(ev$alpha_spent,look*.05/3))
  scc_check(all(ev$endpoint_evidence$radius > 0)) # zero variance is not exactness
  if (look < 3L) {
    scc_check(!review$terminal)
    scc_reject(mq_scc_evaluate(review))
  }
}
scc_check(review$terminal && review$count == 262144L && length(review$look_history) == 3L)
scc_check(tail(review$blocks$last_path_id,1L) == 327680L)
scc_check(scc_close(review$last_evaluation$alpha_spent,.05))
scc_reject(mq_scc_evaluate(review))
scc_reject(mq_scc_update(review,val[1,,drop=FALSE],327681L))

# Strict lower / non-strict upper inequalities permit point masses. Failing
# the frozen split gate still prevents early PASS, without changing bounds.
atom_contract <- flat_contract
atom_contract$training_split_diagnostic$split_stream_absolute_difference <- .006
atom_contract$training_split_diagnostic$split_stream_relative_difference <- .007
atom <- mq_scc_init(flat_candidates,atom_contract)
atom_values <- matrix(rep(c(0,1),each=N),N,dimnames=list(NULL,atom$grid$endpoints$endpoint_id))
atom <- mq_scc_evaluate(mq_scc_update(atom,atom_values,65536L+seq_len(N)))
scc_check(atom$last_evaluation$all_quantile_bounds_pass &&
  !atom$last_evaluation$training_split_gate_pass && !atom$last_evaluation$all_required_gates_pass &&
  !atom$terminal)
or_contract <- flat_contract
or_contract$training_split_diagnostic$split_stream_relative_difference <- Inf
or_state <- mq_scc_init(flat_candidates,or_contract)
or_state <- mq_scc_evaluate(mq_scc_update(or_state,atom_values,65536L+seq_len(N)))
scc_check(or_state$terminal && or_state$last_evaluation$training_split_gate_pass)

# Mutating frozen candidates, alpha, count, endpoint statistics or block
# receipts is rejected before any further validation is consumed.
for (mutate in list(
  function(x) {x$candidates$quantile[1L] <- -2; x},
  function(x) {x$contract$alpha_per_look[1L] <- .05; x},
  function(x) {x$count <- x$count+1L; x},
  function(x) {x$mean[1L] <- 0; x},
  function(x) {x$M2[1L] <- 0; x},
  function(x) {x$blocks$data_sha256[1L] <- paste(rep("0",64L),collapse=""); x},
  function(x) {x$blocks$first_path_id[1L] <- 65536L; x},
  function(x) {x$blocks <- x$blocks[-1L,,drop=FALSE]; x},
  function(x) {x$grid$endpoints$y[1L] <- 999; x},
  function(x) {x$last_chain_sha256 <- "tamper"; x}
)) scc_reject(mq_scc_update(mutate(first),values[18,,drop=FALSE],65554L))
for (mutate in list(
  function(x) {x$training_path_range <- c(1,65537); x},
  function(x) {x$validation_path_range <- c(65536,327679); x},
  function(x) {x$look_sizes <- c(65535,131072,262144); x},
  function(x) {x$look_sizes <- c(65536,131072,262144,524288); x},
  function(x) {x$alpha_per_look <- rep(.05,3); x},
  function(x) {x$alpha_per_look <- c(.01,.02,.02); x},
  function(x) {x$total_alpha <- .051; x},
  function(x) {x$candidates_from_training_paths_only <- FALSE; x},
  function(x) {x$validation_values <- "particle_filter_values"; x},
  function(x) {x$conditioning <- "posterior_mixture"; x},
  function(x) {x$rng_namespace <- ""; x},
  function(x) {x$origin_id <- NA_character_; x},
  function(x) {x$absolute_quantile_tolerance <- .011; x},
  function(x) {x$relative_quantile_tolerance <- .011; x},
  function(x) {x$training_split_diagnostic <- NULL; x},
  function(x) {x$training_split_diagnostic$probability[1L] <- .2; x},
  function(x) {x$training_split_diagnostic$split_stream_absolute_difference[1L] <- NA_real_; x},
  function(x) {x$training_split_diagnostic$split_stream_relative_difference[1L] <- -1; x},
  function(x) {x$production_authorized <- TRUE; x},
  function(x) {x$particle_filter_accuracy_certified <- TRUE; x}
)) scc_reject(mq_scc_init(candidates,mutate(contract)))
for (mutate in list(
  function(x) {x[1L] <- NA_real_; x},
  function(x) {x[1L] <- -.Machine$double.eps; x},
  function(x) {x[1L] <- 1+.Machine$double.eps; x},
  function(x) {x[1L,1:2] <- c(.3,.2); x},
  function(x) {colnames(x) <- rev(colnames(x)); x},
  function(x) {x[,1L,drop=FALSE]}
)) scc_reject(mq_scc_update(mq_scc_init(candidates,contract),mutate(values[1:3,,drop=FALSE]),65537:65539))

ties <- data.frame(horizon=1L,probability=c(.25,.75),quantile=c(0,.02))
tied <- mq_scc_init(ties,scc_contract(ties))
tied_values <- matrix(c(.2,.4,.5,.8),1L,dimnames=list(NULL,tied$grid$endpoints$endpoint_id))
scc_check(tied$grid$endpoints$y[2L] == tied$grid$endpoints$y[3L])
scc_reject(mq_scc_update(tied,tied_values,65537L))
scc_check(identical(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE),scc_had_rng))
if (scc_had_rng) scc_check(identical(get(".Random.seed",envir=.GlobalEnv),scc_original_rng))
cat(sprintf("MQ_STREAMING_CDF_CERTIFICATE_CHECKS=%d PASS; fits=0 protected_reads=0 production=FALSE\n",scc_checks))
