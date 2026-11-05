# Pure generated targets: no authentic payload access, application fit or launch.
local({
  source("scripts/diagnostics/glofas_collapsed_al_target.R", local = TRUE)
  source("scripts/diagnostics/glofas_al_future_score_projection.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  block <- function(ix) list(index = ix, intercept_index = ix[1L], tau0 = .3,
    intercept_prec = .2, slab_shape = 2, slab_rate = 4, zeta2_fixed = NULL)
  spec <- gcat_spec(6, list(beta = block(1:3), alpha = block(4:6)), .2,
    list(Y = c(shape = 2, rate = 1), G = c(shape = 3, rate = .8)))
  F <- matrix(c(1, .2, -.1), 1L); D <- matrix(c(1, -.1, .3), 1L)
  members <- matrix(seq(.08, .22, length.out = 51L), 1L)
  binding <- gafsp_make_generated_al_binding(spec, F, D, members, known_baseline = .07)
  p <- spec$dimension; active <- binding$active; aux <- binding$auxiliary
  m <- seq(-.1, .1, length.out = p); ls <- rep(log(.25), p)
  ok(p == 22L && length(active) == 8L && length(aux) == 14L)
  ok(gafsp_locked(binding) && gafsp_locked(binding$private) && gafsp_locked(binding$callbacks) &&
    !binding$production_qualified && !binding$authentic_reads_authorized)
  ok(identical(sort(c(active, aux)), seq_len(p)))
  e <- binding$evidence(m, 2026110511L)
  ok(e$complete && all(e$member_weights == 1) && length(e$member_weights) == 51L)

  # Pointwise future evidence is independent of every RHS coordinate.
  # The conditional score integrals vanish independently of its numerical value.
  for (j in aux) {
    delta <- rep(0, p); delta[j] <- .02
    plus <- binding$evidence(m + delta, 2026110511L)$log_estimate
    minus <- binding$evidence(m - delta, 2026110511L)$log_estimate
    ok(identical(plus, e$log_estimate) && identical(minus, e$log_estimate))
  }
  score_mean_integral <- stats::integrate(function(x) x / .25 * stats::dnorm(x),
    -Inf, Inf, rel.tol = 1e-11)$value
  score_sd_integral <- stats::integrate(function(x) (x^2 - 1) * stats::dnorm(x),
    -Inf, Inf, rel.tol = 1e-11)$value
  ok(abs(score_mean_integral * e$log_estimate) < 1e-10 &&
    abs(score_sd_integral * e$log_estimate) < 1e-10)

  # Fresh causal H2 particles give the same pointwise invariance, not just H1.
  b2 <- gafsp_make_generated_al_binding(spec, rbind(F, F), rbind(D, D),
    rbind(members, members + .02), reference_lag = .03, discrepancy_lag = -.01,
    known_baseline = c(.07, .08))
  h2 <- b2$evidence(m, 2026110513L)
  ok(h2$complete && h2$diagnostic_thresholds_passed)
  for (j in aux) {
    delta <- rep(0, p); delta[j] <- .015
    finite <- (b2$evidence(m + delta, 2026110513L)$log_estimate -
      b2$evidence(m - delta, 2026110513L)$log_estimate) / .03
    ok(identical(finite, 0))
  }

  old <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({ if (is.null(old)) { if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old, .GlobalEnv) }, add = TRUE)
  set.seed(2026110515L)
  epsilon <- matrix(stats::rnorm(32L * p), 32L, p)
  draws <- sweep(sweep(epsilon, 2L, exp(ls), "*"), 2L, m, "+")
  reward <- apply(draws, 1L, function(x) binding$evidence(as.numeric(x), 2026110517L)$log_estimate)
  raw <- gcpopt_score_gradient(m, ls, epsilon = epsilon, rewards = reward, include_entropy = FALSE)
  projected <- gafsp_project_future(raw, binding, evidence = binding$evidence)
  ok(any(abs(raw$gradient_mean[aux]) > 1e-4) && any(raw$mcse[c(aux, p + aux)] > 1e-4))
  ok(all(projected$gradient_mean[aux] == 0) && all(projected$gradient_log_sd[aux] == 0) &&
    all(projected$standardized_gradient_mean[aux] == 0) &&
    all(projected$mcse[c(aux, p + aux)] == 0) && all(projected$standardized_mcse_mean[aux] == 0))
  ok(identical(projected$gradient_mean[active], raw$gradient_mean[active]) &&
    identical(projected$gradient_log_sd[active], raw$gradient_log_sd[active]) &&
    identical(projected$mcse[c(active, p + active)], raw$mcse[c(active, p + active)]))
  ok(projected$future_projection$future_only && projected$future_projection$all_historical_parameters_remain_random)

  H <- rbind(c(1,.2,-.3,0,0,0), c(1,.4,.1,0,0,0),
    c(1,.2,-.3,1,.4,.2), c(1,.4,.1,1,-.2,.1))
  historical <- gcat_bind_historical(spec, H, c(.2,.3,.4,.7), c("Y","Y","G","G"))
  exact_history <- gcat_historical_elbo(m, ls, historical)
  combined_mean <- projected$gradient_mean + exact_history$gradient_mean
  combined_sd <- projected$gradient_log_sd + exact_history$gradient_log_sd
  ok(any(abs(exact_history$gradient_mean[aux]) > 1e-4) &&
    any(abs(exact_history$gradient_log_sd[aux]) > 1e-4))
  ok(identical(combined_mean[aux], exact_history$gradient_mean[aux]) &&
    identical(combined_sd[aux], exact_history$gradient_log_sd[aux]))
  ok(any(m[aux] + 1e-6 * combined_mean[aux] != m[aux]) &&
    any(ls[aux] + 1e-6 * combined_sd[aux] != ls[aux]))

  # The recognized first-horizon control has exact partial score moments.
  factory <- gafsp_first_horizon_control(binding)
  cv <- factory(m, ls)
  ok(identical(names(cv), c("evaluate", "expected_value", "score_mean", "score_log_sd",
    "freeze_policy", "moment_scope", "source_identity")))
  ok(isTRUE(gafsp_assert(binding, evidence = binding$evidence, surrogate = cv)))
  for (i in 1:5) ok(abs(cv$evaluate(as.numeric(draws[i, ])) -
    binding$evidence(as.numeric(draws[i, ]), 2026110517L)$log_estimate) < 1e-10)
  ok(all(cv$score_mean[aux] == 0) && all(cv$score_log_sd[aux] == 0) &&
    cv$score_mean[spec$scales["Y"]] == 0 && cv$score_log_sd[spec$scales["Y"]] == 0)
  step <- 1e-5
  for (j in seq_len(p)) {
    delta <- rep(0, p); delta[j] <- step
    gm <- (factory(m + delta, ls)$expected_value - factory(m - delta, ls)$expected_value) / (2 * step)
    gs <- (factory(m, ls + delta)$expected_value - factory(m, ls - delta)$expected_value) / (2 * step)
    ok(abs(gm - cv$score_mean[j]) < 2e-7 && abs(gs - cv$score_log_sd[j]) < 2e-7)
  }
  row <- c(F[1L, ], D[1L, ])
  location <- sum(row * m[1:6]) + .07
  sd_location <- sqrt(sum(row^2 * exp(2 * ls[1:6])))
  loss <- sum(vapply(members[1L, ], function(y) {
    f <- function(mu) (y - mu) * (spec$probability - (y < mu)) * stats::dnorm(mu, location, sd_location)
    stats::integrate(f, -Inf, y, rel.tol = 1e-10)$value +
      stats::integrate(f, y, Inf, rel.tol = 1e-10)$value
  }, numeric(1L)))
  si <- spec$scales["G"]
  inv_scale <- stats::integrate(function(x) exp(-m[si] - exp(ls[si]) * x) * stats::dnorm(x),
    -10, 10, rel.tol = 1e-11)$value
  numeric_value <- 51 * (log(spec$probability) + log1p(-spec$probability) - m[si]) - inv_scale * loss
  ok(abs(numeric_value - cv$expected_value) < 1e-9)
  projected_cv <- gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = cv)
  ok(all(projected_cv$gradient[ c(aux, p + aux) ] == 0))
  c2 <- gafsp_first_horizon_control(b2)(m, ls)
  ok(isTRUE(gafsp_assert(b2, evidence = b2$evidence, surrogate = c2)) &&
    abs(c2$evaluate(m) - h2$log_estimate) > .1) # H1 control is not all of H2.
  normalization <- 51 * (log(spec$probability) + log1p(-spec$probability) - m[si])
  ok(abs(c2$evaluate(m) - cv$evaluate(m) - normalization) < 1e-10 &&
    abs(c2$expected_value - cv$expected_value - normalization) < 1e-10 &&
    abs(c2$score_mean[si] - cv$score_mean[si] + 51) < 1e-10 &&
    identical(c2$score_log_sd, cv$score_log_sd))
  for (j in seq_len(p)) {
    delta <- rep(0, p); delta[j] <- step
    f2 <- gafsp_first_horizon_control(b2)
    gm <- (f2(m + delta, ls)$expected_value - f2(m - delta, ls)$expected_value) / (2 * step)
    gs <- (f2(m, ls + delta)$expected_value - f2(m, ls - delta)$expected_value) / (2 * step)
    ok(abs(gm - c2$score_mean[j]) < 2e-7 && abs(gs - c2$score_log_sd[j]) < 2e-7)
  }
  # Full fixed-design control retains every loss and normalizer. Frozen paths
  # are control inputs only; fresh SMC paths still define the actual evidence.
  full1 <- gafsp_full_frozen_design_control(binding)(m, ls)
  ok(identical(full1$expected_value, cv$expected_value) &&
    identical(full1$score_mean, cv$score_mean) && identical(full1$score_log_sd, cv$score_log_sd) &&
    abs(full1$evaluate(m) - cv$evaluate(m)) < 1e-12)
  anchor <- c(.15, -.1)
  full_factory <- gafsp_full_frozen_design_control(b2, anchor)
  full <- full_factory(m, ls)
  mu <- vapply(1:2, function(h) sum(F[1L, ] * m[1:3]) + sum(D[1L, ] * m[4:6]) +
    b2$fixture$known_baseline[h] + if (h == 1L) 0 else .02 * anchor[h - 1L], numeric(1L))
  literal <- sum(vapply(1:2, function(h) {
    residual <- b2$fixture$members[h, ] - mu[h]
    sum(log(spec$probability) + log1p(-spec$probability) - m[si] -
      residual * (spec$probability - (residual < 0)) * exp(-m[si]))
  }, numeric(1L)))
  ok(abs(full$evaluate(m) - literal) < 1e-10 &&
    isTRUE(gafsp_assert(b2, evidence = b2$evidence, surrogate = full)))
  total_loss <- sum(vapply(1:2, function(h) sum(vapply(b2$fixture$members[h, ], function(y) {
    f <- function(theta) (y-theta)*(spec$probability-(y<theta))*stats::dnorm(theta,mu[h],sd_location)
    stats::integrate(f,-Inf,y,rel.tol=1e-10)$value + stats::integrate(f,y,Inf,rel.tol=1e-10)$value
  }, numeric(1L))), numeric(1L)))
  numeric_full <- 102 * (log(spec$probability) + log1p(-spec$probability) - m[si]) - inv_scale * total_loss
  ok(abs(full$expected_value - numeric_full) < 1e-9)
  for (j in seq_len(p)) {
    delta <- rep(0, p); delta[j] <- step
    gm <- (full_factory(m+delta,ls)$expected_value-full_factory(m-delta,ls)$expected_value)/(2*step)
    gs <- (full_factory(m,ls+delta)$expected_value-full_factory(m,ls-delta)$expected_value)/(2*step)
    ok(abs(gm-full$score_mean[j]) < 3e-7 && abs(gs-full$score_log_sd[j]) < 3e-7)
  }
  full_projected <- gafsp_project_future(raw,b2,evidence=b2$evidence,surrogate=full)
  ok(all(full_projected$gradient_mean[aux]==0) && all(full_projected$gradient_log_sd[aux]==0))
  future_reward <- apply(draws,1L,function(x)b2$evidence(as.numeric(x),2026110519L)$log_estimate)
  control_reward <- apply(draws,1L,function(x)full$evaluate(as.numeric(x)))
  raw_h2 <- gcpopt_score_gradient(m,ls,epsilon=epsilon,rewards=future_reward,include_entropy=FALSE)
  controlled_h2 <- gcpopt_score_gradient(m,ls,epsilon=epsilon,rewards=future_reward-control_reward,include_entropy=FALSE)
  # This measurement is retained as a comparison, never a built-in assertion
  # that a valid control must reduce every component's variance.
  mcse_comparison <- c(raw=max(raw_h2$mcse),controlled=max(controlled_h2$mcse))
  ok(all(is.finite(mcse_comparison)) && all(mcse_comparison>=0))
  reject(gafsp_full_frozen_design_control(b2,anchor_path=0))
  reject(gafsp_full_frozen_design_control(b2,anchor_path=c(0,Inf)))
  reject(gafsp_full_frozen_design_control(b2,anchor_path=function(...)0))
  empty <- gafsp_make_generated_al_binding(spec, F, D, NULL)
  c0 <- gafsp_first_horizon_control(empty)(m, ls)
  ok(identical(c0$expected_value, 0) && c0$evaluate(m) == 0 &&
    all(c0$score_mean == 0) && all(c0$score_log_sd == 0))
  zero <- gafsp_make_generated_al_binding(spec, F * 0, D * 0, members)
  cz <- gafsp_first_horizon_control(zero)(m, ls)
  ok(is.finite(cz$expected_value) && all(cz$score_mean[1:6] == 0) && all(cz$score_log_sd[1:6] == 0))
  underflow <- gafsp_make_generated_al_binding(spec, F * 1e-300, D * 1e-300, members)
  reject(gafsp_first_horizon_control(underflow)(m, ls))

  # Missing roles, arbitrary masks/closures, changed seals or covariance fail closed.
  clone <- function(b, key, value, locked = TRUE) {
    out <- list2env(as.list.environment(b, all.names = TRUE), envir = new.env(parent = emptyenv()))
    assign(key, value, envir = out)
    if (locked) lockEnvironment(out, bindings = TRUE)
    out
  }
  reject(gafsp_project_future(raw, binding))
  reject(gafsp_project_future(raw, binding, factor = diag(p), evidence = binding$evidence))
  reject(gafsp_project_future(raw, binding, evidence = function(x, seed) e))
  reject(gafsp_project_future(raw, list(active = active, auxiliary = aux), evidence = binding$evidence))
  reject(gafsp_project_future(raw, clone(binding, "active", active[-1L]), evidence = binding$evidence))
  reject(gafsp_project_future(raw, clone(binding, "active", setdiff(active, spec$scales["G"])), evidence = binding$evidence))
  roles <- binding$roles; roles[1L] <- "unknown"
  reject(gafsp_project_future(raw, clone(binding, "roles", roles), evidence = binding$evidence))
  reject(gafsp_project_future(raw, clone(binding, "roles", binding$roles, FALSE), evidence = binding$evidence))
  sh <- binding$source_sha256; sh[1L] <- paste(rep("0", 64), collapse = "")
  reject(gafsp_project_future(raw, clone(binding, "source_sha256", sh), evidence = binding$evidence))
  modified <- binding$evidence; body(modified) <- quote(list(log_estimate = 0))
  reject(gafsp_project_future(raw, clone(binding, "evidence", modified), evidence = modified))
  bad <- raw; bad$gradient_log_sd[1L] <- Inf
  reject(gafsp_project_future(bad, binding, evidence = binding$evidence))
  bad <- raw; bad$mcse[1L] <- -1
  reject(gafsp_project_future(bad, binding, evidence = binding$evidence))
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = list(dependencies = active)))
  badcv <- cv; attr(badcv, "gafsp_control_token") <- NULL
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = badcv))
  badcv <- cv; badcv$score_mean[aux[1L]] <- 1
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = badcv))
  badcv <- cv; badcv$source_identity <- paste(rep("0", 64), collapse = "")
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = badcv))
  badcv <- cv; badcv$evaluate <- function(x) x[aux[1L]]
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = badcv))
  reject(gafsp_project_future(raw, b2, evidence = b2$evidence, surrogate = cv))
  original_point <- gafsp_control_point
  gafsp_control_point <- function(eta) eta[1L]
  reject(factory(m, ls))
  reject(gafsp_first_horizon_control(binding))
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = cv))
  gafsp_control_point <- original_point
  original_moments <- gafsp_h1_moments
  gafsp_h1_moments <- function(...) list(expected_value = 0)
  reject(factory(m, ls))
  reject(gafsp_project_future(raw, binding, evidence = binding$evidence, surrogate = cv))
  gafsp_h1_moments <- original_moments
  original_full_point <- gafsp_full_control_point
  gafsp_full_control_point <- function(eta) eta[1L]
  reject(full_factory(m, ls))
  reject(gafsp_project_future(raw, b2, evidence = b2$evidence, surrogate = full))
  gafsp_full_control_point <- original_full_point
  original_full_moments <- gafsp_full_h_moments
  gafsp_full_h_moments <- function(...) list(expected_value=0)
  reject(full_factory(m, ls))
  gafsp_full_h_moments <- original_full_moments
  badspec <- spec; badspec$scales <- badspec$scales["Y"]
  reject(gafsp_make_generated_al_binding(badspec, F, D, members))
  reject(gafsp_make_generated_al_binding(spec, F[, -1L, drop = FALSE], D, members))
  reject(gafsp_make_generated_al_binding(spec, F, D, matrix(.2, 1, 50)))
  reject(gafsp_make_generated_al_binding(spec, function(...) 0, D, members))

  # A changed source byte is rejected even if the caller supplies copied code.
  temporary <- tempfile("gafsp_text_source_"); dir.create(file.path(temporary, "scripts", "diagnostics"), recursive = TRUE)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  source_paths <- names(binding$source_sha256)
  ok(all(file.copy(source_paths, file.path(temporary, source_paths))))
  bcopy <- gafsp_make_generated_al_binding(spec, F, D, members, source_root = temporary)
  changed_path <- file.path(temporary, source_paths[1L])
  writeLines(c(readLines(changed_path, warn = FALSE), "# generated mutation fixture"), changed_path)
  reject(gafsp_assert(bcopy))
  reject(gafsp_make_generated_al_binding(spec, F, D, members, source_root = temporary))

  # Application-sized inventory, but only four tiny generated historical rows.
  big <- gcat_spec(2502L, list(beta = block(1:1501), alpha = block(1502:2502)), .5,
    list(Y = c(shape = 2, rate = 1), G = c(shape = 2, rate = 1)))
  Fb <- matrix(0, 1, 1501); Fb[1L] <- 1
  Db <- matrix(0, 1, 1001); Db[1L] <- 1
  bb <- gafsp_make_generated_al_binding(big, Fb, Db, matrix(.2, 1, 51))
  ok(bb$dimension == 7510L && length(bb$active) == 2504L && length(bb$auxiliary) == 5006L)
  zeros <- numeric(big$dimension)
  gb <- list(gradient_mean = zeros + 1, gradient_log_sd = zeros + 2,
    standardized_gradient_mean = zeros + 3, mcse = rep(4, 2L * big$dimension), standardized_mcse_mean = zeros + 5)
  pb <- gafsp_project_future(gb, bb, evidence = bb$evidence)
  ok(all(pb$gradient_mean[bb$auxiliary] == 0) && all(pb$gradient_log_sd[bb$auxiliary] == 0) &&
    all(pb$gradient_mean[bb$active] == 1) && all(pb$gradient_log_sd[bb$active] == 2))
  Hb <- matrix(0, 4, 2502); Hb[, 1L] <- 1; Hb[3:4, 1502L] <- 1
  bh <- gcat_bind_historical(big, Hb, c(.2,.3,.4,.7), c("Y","Y","G","G"))
  hb <- gcat_historical_elbo(rep(.01, big$dimension), rep(-2, big$dimension), bh)
  ok(all(abs(hb$gradient_mean[bb$auxiliary]) > 0) &&
    all(abs(hb$gradient_log_sd[bb$auxiliary]) > 0) &&
    identical((pb$gradient_mean + hb$gradient_mean)[bb$auxiliary], hb$gradient_mean[bb$auxiliary]))

  # End-to-end optimizer hook: integrate only the future RHS scores, then add
  # the nonzero exact historical derivatives. All RHS coordinates stay free.
  history_callback <- function(mean, log_sd, factor) gcat_historical_elbo(mean, log_sd, historical, factor)
  controls <- gcpopt_control(max_iterations = 2L, minimum_iterations = 1L, batch_size = 4L,
    learning_rate = .01, max_evaluations = 100L, max_wall_seconds = 30,
    max_inner_calls = 10000L, inner_call_bound = 128L)
  contract <- gcpopt_input_contract(binding$coordinate_names, "generated coefficients and log-positive parameters",
    list(fixture = "locked_AL_future_projection", features = F, discrepancy = D, members = members), binding$source_sha256)
  fit <- gcpopt_optimize(log_evidence_estimate = binding$evidence, initial_mean = m, initial_log_sd = ls,
    control = controls, input_contract = contract, analytic_historical = history_callback,
    control_variate = factory, future_projection = binding)
  ok(fit$completed_iterations == 2L && fit$future_projection_used && fit$control_variate_used && is.null(fit$failure))
  final_history <- gcat_historical_elbo(fit$mean, fit$log_sd, historical)
  ok(max(abs(fit$last_gradient$gradient_mean[aux] - final_history$gradient_mean[aux])) < 1e-12 &&
    max(abs(fit$last_gradient$gradient_log_sd[aux] - final_history$gradient_log_sd[aux])) < 1e-12)
  ok(any(fit$mean[aux] != m[aux]) && any(fit$log_sd[aux] != ls[aux]) && fit$all_parameter_dimensions_optimized)
  ok(!fit$posterior_accuracy_qualified && !fit$production_launch_authorized && fit$original_reads == 0L)
  unsafe_factory <- function(mean, log_sd, factor) {
    cv <- factory(mean, log_sd, factor); attr(cv, "gafsp_control_token") <- NULL; cv
  }
  unsafe <- gcpopt_optimize(log_evidence_estimate = binding$evidence, initial_mean = m, initial_log_sd = ls,
    control = controls, input_contract = contract, analytic_historical = history_callback,
    control_variate = unsafe_factory, future_projection = binding)
  ok(unsafe$completed_iterations == 0L && unsafe$evaluations == 0L && unsafe$inner_calls == 0L &&
    grepl("not authenticated", unsafe$failure, fixed = TRUE))
  cat(sprintf("GLOFAS_AL_FUTURE_SCORE_PROJECTION_PASS checks=%d original_reads=0 application_fits=0\n", checks))
})
