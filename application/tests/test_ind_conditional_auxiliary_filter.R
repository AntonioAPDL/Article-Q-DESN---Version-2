# Synthetic filter qualification; no retained fit, true outcomes or new fit.
source("scripts/ind_conditional_auxiliary_filter.R")
caf_n <- 0L
caf_check <- function(ok) { stopifnot(isTRUE(ok)); caf_n <<- caf_n + 1L }
caf_close <- function(a, b, tol = 1e-11)
  isTRUE(all.equal(a, b, tolerance = tol, check.attributes = FALSE))
caf_reject <- function(expr) caf_check(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
set.seed(71348); caf_rng <- .Random.seed

# Native transform, not a Normal likelihood inferred from a Normal DGP label.
u <- matrix(c(.1, .4, .7, .9), 2L, 2L)
a <- ind_caf_prior_auxiliaries("al", .25, .7, u)
v <- qexp(as.numeric(u), rate = 1 / .7)
caf_check(caf_close(a$ex_f, matrix((8/3) * v, 2L)))
caf_check(caf_close(a$ex_q, matrix((32/3) * .7 * v, 2L)))
caf_check(a$proposal == "native_auxiliary_prior" && !a$production_authorized && a$random_draws_generated == 0L)
for (gamma in c(-.2, 0, .2)) {
  b <- ind_caf_prior_auxiliaries("exal", .5, .7, u, 1 - u, gamma)
  s <- qnorm((1 + as.numeric(1 - u)) / 2)
  ref <- ind_cfr_augmentation("exal", .5, .7, v, s, gamma)
  caf_check(caf_close(b$ex_f, matrix(ref$ex_f, 2L)))
  caf_check(caf_close(b$ex_q, matrix(ref$ex_q, 2L)))
}
for (bad in list(0, 1, -1, NA_real_, Inf)) {
  x <- u; x[1L] <- bad
  caf_reject(ind_caf_prior_auxiliaries("al", .5, 1, x))
}
caf_reject(ind_caf_prior_auxiliaries("al", .5, 1, u, u))
caf_reject(ind_caf_prior_auxiliaries("exal", .5, 1, u, u[, 1L, drop = FALSE]))
caf_reject(ind_caf_prior_auxiliaries("exal", .05, 1, u, u, gamma = 100))

# Gaussian fixture: identical particles exactly recover conditional Kalman law.
g <- list(y = c(1, -1, .2), FF = matrix(1, 1L, 3L), GG = matrix(1, 1L),
  m0 = 0, C0 = matrix(1, 1L), df_mat = matrix(.25, 1L),
  ex_f = matrix(0, 4L, 3L), ex_q = matrix(1, 4L, 3L),
  observed_prefix_length = 3L, parameter_id = "fixture-native-column-17",
  proposal_role = "finite_prior_fixture", checkpoint_indices = 1:3,
  u_resample = c(.2, .7, .4), ess_fraction = .5)
z <- do.call(ind_caf_filter_moments, g)
k <- ind_cfr_cpp_forward(g$y, g$FF, g$GG, 0, matrix(1, 1L),
  c(0, 0, 0), c(1, 1, 1), matrix(.25, 1L), 3L)
for (tt in 1:3) {
  ck <- z$checkpoints[[as.character(tt)]]
  caf_check(caf_close(ck$mean, matrix(rep(k$fm[, tt], 4L), 1L)))
  caf_check(caf_close(ck$covariance, array(rep(k$fC[, , tt], 4L), c(1L, 1L, 4L))))
  caf_check(caf_close(ck$weights, rep(.25, 4L)))
  caf_check(ck$observed_prefix_length == tt && ck$future_outcomes_used == 0L &&
    ck$parameter_id == g$parameter_id && !ck$production_authorized)
}
caf_check(caf_close(z$log_predictive_normalizers, k$lineage$Gaussian_log_predictive_weight))
caf_check(!any(z$resampled) && caf_close(z$ESS, rep(4, 3L)))
caf_check(all(z$log_weight_underflow_count == 0L) && all(z$zero_weight_count == 0L))
caf_check(!z$parameter_weights_updated && !z$numerical_accuracy_qualified && !z$production_authorized &&
  z$new_model_fits == 0L && z$random_draws_generated == 0L)

# Enumerate all four auxiliary histories of a two-point discrete prior. An
# independent bivariate Gaussian calculation gives posterior component weights
# and state moments, including history-dependent discount innovation W2.
q <- g
q$y <- c(.6, -.3); q$FF <- matrix(1, 1L, 2L)
q$ex_q <- as.matrix(expand.grid(c(.5, 2), c(.5, 2)))
q$ex_f <- .1 * q$ex_q
q$observed_prefix_length <- 2L; q$checkpoint_indices <- 1:2
q$u_resample <- c(.2, .7); q$ess_fraction <- 0
enum <- do.call(ind_caf_filter_moments, q)
ll <- mean2 <- var2 <- numeric(4L)
for (j in 1:4) {
  R1 <- 1.25; C1 <- R1 * q$ex_q[j, 1L] / (R1 + q$ex_q[j, 1L])
  S2 <- R1 + .25 * C1
  B <- matrix(c(R1 + q$ex_q[j, 1L], R1, R1, S2 + q$ex_q[j, 2L]), 2L)
  r <- q$y - q$ex_f[j, ]; covxy <- c(R1, S2)
  ll[j] <- -log(2*pi) - .5 * as.numeric(determinant(B, logarithm = TRUE)$modulus) -
    .5 * as.numeric(t(r) %*% solve(B, r))
  mean2[j] <- sum(covxy * solve(B, r))
  var2[j] <- S2 - sum(covxy * solve(B, covxy))
}
ew <- exp(ll - max(ll)); ew <- ew / sum(ew)
ec <- enum$checkpoints[["2"]]
caf_check(caf_close(ec$weights, ew))
caf_check(caf_close(as.numeric(ec$mean), mean2))
caf_check(caf_close(as.numeric(ec$covariance), var2))
caf_check(caf_close(sum(enum$log_predictive_normalizers), log(mean(exp(ll)))))
caf_check(caf_close(sum(ec$weights * ec$mean), sum(ew * mean2)))

# Explicit prior weights normalize WITHIN eta. They are not eta weights.
q$initial_weights <- c(0, 1, 2, 4)
weighted <- do.call(ind_caf_filter_moments, q)
expect <- exp(ll - max(ll)) * q$initial_weights; expect <- expect / sum(expect)
caf_check(caf_close(weighted$checkpoints[["2"]]$weights, expect))
caf_check(weighted$checkpoints[["2"]]$weights[1L] == 0)

# Systematic resampling excludes zero masses and is deterministic conditional u.
caf_check(identical(ind_caf_systematic_indices(c(0, .5, 0, .5), .5), c(2L, 2L, 4L, 4L)))
caf_check(identical(ind_caf_systematic_indices(c(0, 0, 1, 0), .2), rep(3L, 4L)))
caf_check(identical(ind_caf_systematic_indices(c(1, 0), 1 - .Machine$double.eps/2), c(1L, 1L)))
caf_check(all(ind_caf_systematic_indices(c(.1, .9, 0), 1 - .Machine$double.eps/2) %in% 1:2))
caf_check(all(ind_caf_systematic_indices(c(.5, .50000000001, 0), .5) %in% 1:2))
caf_reject(ind_caf_systematic_indices(c(.2, .2), .2))
caf_reject(ind_caf_systematic_indices(c(.5, .5), 1))
r <- g; r$y <- c(-10, .3, .4); r$ex_f[, 1L] <- c(-10, 5, 8, 20)
r$ess_fraction <- 1
rz <- do.call(ind_caf_filter_moments, r)
caf_check(rz$resampled[1L])
caf_check(all(rz$ancestry[, 1L] == 1L))
ul <- r; ul$ex_f[, 1L] <- c(-10, 1e4, 2e4, 3e4)
uz <- do.call(ind_caf_filter_moments, ul)
caf_check(uz$log_weight_underflow_count[1L] == 3L && uz$zero_weight_count[1L] == 3L)

# Prefix checkpoint causality survives resampling. No later-observation
# smoothing; no result depends on whether this prefix was the caller's last.
prefix <- r; prefix$y <- r$y[1:2]; prefix$FF <- r$FF[, 1:2, drop = FALSE]
prefix$ex_f <- r$ex_f[, 1:2, drop = FALSE]; prefix$ex_q <- r$ex_q[, 1:2, drop = FALSE]
prefix$u_resample <- r$u_resample[1:2]; prefix$observed_prefix_length <- 2L
prefix$checkpoint_indices <- 1:2
rp <- do.call(ind_caf_filter_moments, prefix)
changed <- r; changed$y[3L] <- 100
rc <- do.call(ind_caf_filter_moments, changed)
for (tt in 1:2) {
  caf_check(identical(rp$checkpoints[[as.character(tt)]], rz$checkpoints[[as.character(tt)]]))
  caf_check(identical(rc$checkpoints[[as.character(tt)]], rz$checkpoints[[as.character(tt)]]))
}
caf_check(identical(rp$ancestry, rz$ancestry[, 1:2, drop = FALSE]))

# Log normalization remains stable when all ordinary likelihoods underflow.
tail <- g; tail$y <- rep(1e4, 3L)
tz <- do.call(ind_caf_filter_moments, tail)
caf_check(all(is.finite(tz$log_predictive_normalizers)))
caf_check(caf_close(tz$checkpoints[["3"]]$weights, rep(.25, 4L)))

# Public native-prior wrapper only, not a hidden generic guided proposal.
wrapped <- ind_caf_filter(c(0, 1), matrix(1, 1L, 2L), matrix(1, 1L), 0,
  matrix(1, 1L), matrix(0, 1L), a, 2L, "native-1", 1:2, c(.2, .3))
caf_check(wrapped$proposal_role == "native_auxiliary_prior" && !wrapped$production_authorized)
caf_reject(ind_caf_filter(c(0, 1), matrix(1, 1L, 2L), matrix(1, 1L), 0,
  matrix(1, 1L), matrix(0, 1L), unclass(a), 2L, "native-1", 1:2, c(.2, .3)))

for (mutate in list(
  function(x) { x$y <- c(x$y, 9); x },
  function(x) { x$observed_prefix_length <- 2L; x },
  function(x) { x$FF <- function(y) y; x },
  function(x) { x$GG <- array(1, c(1L, 1L, 4L)); x },
  function(x) { x$checkpoint_indices <- c(2L, 1L); x },
  function(x) { x$checkpoint_indices <- c(1L, 1L); x },
  function(x) { x$checkpoint_indices <- 4L; x },
  function(x) { x$parameter_id <- character(); x },
  function(x) { x$proposal_role <- "unweighted_guided_proposal"; x },
  function(x) { x$C0[] <- -1; x },
  function(x) { x$df_mat[] <- -1; x },
  function(x) { x$ex_q[1L] <- 0; x },
  function(x) { x$ex_f[1L] <- Inf; x },
  function(x) { x$u_resample <- c(.2, .3); x },
  function(x) { x$u_resample[1L] <- 0; x },
  function(x) { x$ess_fraction <- 1.1; x },
  function(x) { x$initial_weights <- c(1, 2); x },
  function(x) { x$initial_weights <- rep(0, 4L); x }
)) caf_reject(do.call(ind_caf_filter_moments, mutate(g)))
caf_check(identical(.Random.seed, caf_rng))
cat(sprintf("IND_CONDITIONAL_AUXILIARY_FILTER_CHECKS=%d PASS; protected_reads=0 fits=0 production_launches=0\n", caf_n))
