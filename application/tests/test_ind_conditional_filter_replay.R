# Synthetic deterministic qualification fixtures. No protected evidence or fit.
source("scripts/ind_conditional_filter_replay.R")
cfr_n <- 0L
cfr_check <- function(ok) { stopifnot(isTRUE(ok)); cfr_n <<- cfr_n + 1L }
cfr_reject <- function(expr) {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  cfr_check(inherits(err, "error"))
}
cfr_close <- function(x, y, tol = 1e-12) isTRUE(all.equal(x, y, tolerance = tol, check.attributes = FALSE))

policy <- ind_cfr_policy()
cfr_check(policy$native_backend == "C++" && policy$native_mode == "fast")
cfr_check(!policy$static_parameter_marginal && !policy$native_execution_performed &&
  !policy$later_origin_filter_implemented && !policy$production_authorized)
cfr_check(policy$source_sha256 == "f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065")
D <- ind_cfr_discount_matrix(c(.8, .5), c(2L, 1L))
cfr_check(cfr_close(D, rbind(c(.25, .25, 0), c(.25, .25, 0), c(0, 0, 1))))
cfr_check(identical(ind_cfr_discount_matrix(1, 2L), matrix(0, 2L, 2L)))
for (expr in list(quote(ind_cfr_discount_matrix(0, 2)), quote(ind_cfr_discount_matrix(1.1, 2)),
  quote(ind_cfr_discount_matrix(.9, 1.5)), quote(ind_cfr_discount_matrix(c(.9, .8), 2)),
  quote(ind_cfr_discount_matrix(.9, 2, 3)))) cfr_reject(eval(expr))

al <- ind_cfr_augmentation("al", .25, .5, c(1, 2))
cfr_check(cfr_close(al$ex_f, c(8/3, 16/3)))
cfr_check(cfr_close(al$ex_q, c(16/3, 32/3)))
ex0 <- ind_cfr_augmentation("exal", .25, .5, c(1, 2), c(.3, .7), 0)
cfr_check(identical(al$ex_f, ex0$ex_f) && identical(al$ex_q, ex0$ex_q))
for (g in c(-.2, .2)) {
  e <- ind_cfr_augmentation("exal", .5, 2, c(.3, .8), c(.2, .6), g)
  r <- (.5 - as.numeric(g < 0)) / (2 * pnorm(-abs(g)) * exp(g*g/2)) + as.numeric(g < 0)
  A <- (1 - 2*r)/(r*(1-r)); B <- 2/(r*(1-r)); C <- 1/(as.numeric(g > 0) - r)
  cfr_check(cfr_close(e$ex_f, A*c(.3, .8) + 2*C*abs(g)*c(.2, .6)))
  cfr_check(cfr_close(e$ex_q, 2*B*c(.3, .8)))
  cfr_check(!e$static_parameter_marginal && e$random_draws_generated == 0L)
}
for (expr in list(quote(ind_cfr_augmentation("al", 0, 1, 1)),
  quote(ind_cfr_augmentation("al", .5, -1, 1)), quote(ind_cfr_augmentation("al", .5, 1, 0)),
  quote(ind_cfr_augmentation("al", .5, 1, 1, gamma = .1)),
  quote(ind_cfr_augmentation("al", .5, 1, 1, s = 1)),
  quote(ind_cfr_augmentation("exal", .5, 1, c(1, 2), s = 1, gamma = .1)),
  quote(ind_cfr_augmentation("exal", .5, 1, 1, s = -1, gamma = .1)),
  quote(ind_cfr_augmentation("exal", .05, 1, 1, s = 1, gamma = 100)))) cfr_reject(eval(expr))

fixture <- list(y = c(1, 2), FF = matrix(1, 1L, 2L), GG = matrix(1, 1L, 1L),
  m0 = 0, C0 = matrix(1, 1L, 1L), ex_f = c(0, 0), ex_q = c(1, 1),
  df_mat = matrix(0, 1L, 1L), observed_prefix_length = 2L)
set.seed(453); saved_rng <- .Random.seed
z <- do.call(ind_cfr_cpp_forward, fixture)
cfr_check(identical(.Random.seed, saved_rng))

# A later observed prefix must not alter an earlier forward-filter checkpoint.
prefix <- fixture
prefix$y <- prefix$y[1L]; prefix$FF <- prefix$FF[,1L,drop=FALSE]
prefix$ex_f <- prefix$ex_f[1L]; prefix$ex_q <- prefix$ex_q[1L]
prefix$observed_prefix_length <- 1L
one <- do.call(ind_cfr_cpp_forward, prefix)
later <- fixture; later$y[2L] <- 1000
changed_later <- do.call(ind_cfr_cpp_forward, later)
cfr_check(identical(one$fm[,1L], z$fm[,1L]))
cfr_check(identical(one$fC[,,1L], z$fC[,,1L]))
cfr_check(identical(changed_later$fm[,1L], z$fm[,1L]))
cfr_check(identical(changed_later$fC[,,1L], z$fC[,,1L]))
cfr_check(cfr_close(z$fm, matrix(c(.5, 1), 1L)))
cfr_check(cfr_close(z$fC, array(c(.5, 1/3), c(1L, 1L, 2L))))
cfr_check(cfr_close(z$lineage$a, matrix(c(0, .5), 1L)))
cfr_check(cfr_close(z$lineage$Q, c(2, 1.5)))
cfr_check(all(z$lineage$W == 0) && !any(z$lineage$native_Q_floor_applied))
cfr_check(cfr_close(sum(z$lineage$Gaussian_log_predictive_weight), -log(2*pi) - .5*log(3) - 1))
cfr_check(!z$training_augmentation_integrated && !z$static_parameter_marginal &&
  z$state_uncertainty_integrated_conditionally && z$new_model_fits == 0L && z$forecasts_generated == 0L)

# Initial m0/C0 refer to the state before y1, not an already-filtered y1 state.
time <- fixture; time$GG <- matrix(2, 1L); time$observed_prefix_length <- 2L
t1 <- do.call(ind_cfr_cpp_forward, time)
cfr_check(cfr_close(t1$lineage$P[,,1L], 4))
cfr_check(cfr_close(t1$fm[,1L], .8))

# Rotation demonstrates the noncommuting covariance correction exactly.
rot <- matrix(c(0, 1, -1, 0), 2L)
x <- ind_cfr_cpp_forward(0, matrix(c(1, 0), 2L, 1L), rot, c(0, 0), diag(c(1, 4)),
  0, 1, ind_cfr_discount_matrix(.8, 2L), 1L)
cfr_check(cfr_close(x$lineage$P[,,1L], diag(c(4, 1))))
cfr_check(cfr_close(x$lineage$W[,,1L], diag(c(1, .25))))
cfr_check(cfr_close(x$lineage$R[,,1L], diag(c(5, 1.25))))
old_R <- rot %*% diag(c(1, 4)) %*% t(rot) + ind_cfr_discount_matrix(.8, 2L)*diag(c(1, 4))
cfr_check(cfr_close(old_R, diag(c(4.25, 2))) && !cfr_close(old_R, x$lineage$R[,,1L]))

# The finite-horizon input is precisely the observed prefix; no silent trimming.
for (mutate in list(
  function(a) { a$observed_prefix_length <- 1L; a },
  function(a) { a$y <- c(a$y, 99); a },
  function(a) { a$FF <- matrix(1, 1L, 3L); a },
  function(a) { a$GG <- array(1, c(1L,1L,3L)); a },
  function(a) { a$GG <- matrix(1, 1L, 2L); a },
  function(a) { a$ex_f <- c(0, NA); a },
  function(a) { a$ex_q <- c(1, -1); a },
  function(a) { a$m0 <- NA_real_; a },
  function(a) { a$C0 <- matrix(-1, 1L); a },
  function(a) { a$df_mat <- matrix(-1, 1L); a },
  function(a) { a$tolerance <- 0; a }
)) cfr_reject(do.call(ind_cfr_cpp_forward, mutate(fixture)))
cfr_reject(ind_cfr_cpp_forward(c(1, 2), matrix(1, 1L, 2L), matrix(1, 1L),
  0, matrix(1, 1L), c(0, 0), c(1, 1), matrix(0, 1L)))
cfr_reject(ind_cfr_cpp_forward(0, matrix(c(1, 0), 2L, 1L), diag(2), c(0, 0),
  matrix(c(1, .2, 0, 1), 2L), 0, 1, diag(2), 1L))

# Preserve and disclose the actual C++ zero-Q floor; do not introduce R caps.
floor <- fixture; floor$C0[] <- 0; floor$ex_q[] <- 0; floor$y[] <- 0
ff <- do.call(ind_cfr_cpp_forward, floor)
cfr_check(all(ff$lineage$native_Q_floor_applied) && all(ff$lineage$Q == 1e-12))
large <- fixture; large$C0[] <- 1e9
huge <- do.call(ind_cfr_cpp_forward, large)
cfr_check(huge$lineage$P[,,1L] > 1e8)

native <- z[c("fm", "fC", "standard.forecast.errors")]
parity <- ind_cfr_compare_native(z, native, 1e-10, 1e-10)
cfr_check(parity$status == "NATIVE_FORWARD_PARITY_PASS" && all(parity$fields$pass))
wrong <- native; wrong$fm[1L] <- wrong$fm[1L] + .01
cfr_check(ind_cfr_compare_native(z, wrong, 1e-10, 1e-10)$status == "NATIVE_FORWARD_PARITY_FAIL")
wrong <- native; wrong$fC <- wrong$fC[,,1L]
cfr_reject(ind_cfr_compare_native(z, wrong, 1e-10, 1e-10))
cfr_reject(ind_cfr_compare_native(z, native, 0, 1e-10))
cfr_check(identical(.Random.seed, saved_rng))
spec <- jsonlite::read_json("configs/ind_conditional_filter_specification_20261101.json")
cfr_check(identical(spec$author_confirmation, "Use this corrected specification"))
cfr_check(!spec$allow_refit && !spec$allow_production_launch && !spec$allow_article_promotion)
cfr_check(!spec$later_parameter_reweighting && spec$preserve_original_draw_ids_and_weights)
cfr_check(spec$native_cpp_sha256 == policy$source_sha256 && spec$observed_backend_cases == 54L)
cat(sprintf("IND_CONDITIONAL_CPP_FORWARD_REPLAY_CHECKS=%d PASS; protected_reads=0 fits=0 forecasts=0\n", cfr_n))
