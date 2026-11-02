#!/usr/bin/env Rscript
# Synthetic numeric/recursive fixtures only. No fit, forecast truth or runtime
# payload is read. Reuse the existing synthetic fixture definition, not its
# test execution or any production source discovery.
for (file in c("joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "latent_path_design.R", "joint_qdesn_pure_recursive_campaign.R",
  "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R")) source(file.path("application/R", file))
source("scripts/integrated_quantile_mq_batch.R")
source("scripts/mq_forecast_array_methods.R")
`%||%` <- function(a, b) if (is.null(a)) b else a
mq_array_n <- 0L
mq_array_check <- function(x) { stopifnot(isTRUE(x)); mq_array_n <<- mq_array_n + 1L }
mq_array_close <- function(a, b, tolerance = 1e-11)
  isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))
mq_array_reject <- function(expr) mq_array_check(inherits(tryCatch({ force(expr); NULL }, error = identity), "error"))
mqb_tau <- c(.05, .1, .25, .5, .75, .9, .95)
mqb_hash <- paste(rep("a", 64L), collapse = "")
fixture_ast <- parse(file = "application/tests/test_integrated_quantile_mq_batch.R")
fixture_index <- which(vapply(fixture_ast, function(e) is.call(e) && identical(e[[1L]], as.name("<-")) &&
  identical(e[[2L]], as.name("mqb_fixture")), logical(1L)))
stopifnot(length(fixture_index) == 1L)
eval(fixture_ast[[fixture_index]])

set.seed(18722)
for (case in seq_len(40L)) {
  N <- (case %% 19L) + 1L; K <- length(mqb_tau)
  q <- matrix(stats::rnorm(N*K), N, K)
  if (case %% 2L == 0L) q <- t(apply(q, 1L, sort))
  if (case %% 3L == 0L) q[, 2:4] <- q[, 1L]
  if (case %% 7L == 0L) q[1L, ] <- 0
  p <- c(.01, mqb_tau, .99)
  kernels <- lapply(seq_len(N), function(i) list(family = "mq_grid", q = as.numeric(q[i, ]), tau = mqb_tau))
  seed <- .Random.seed
  reference <- app_iqf_mq_mixture_inverse(kernels, p, 1e-8)
  actual <- app_iqf_mq_matrix_inverse(q, mqb_tau, p, 1e-8)
  if (!mq_array_close(actual, reference, 1e-12)) stop(paste("Matrix parity case",case,
    "maximum difference",max(abs(actual-reference))),call.=FALSE)
  mq_array_check(mq_array_close(actual, reference, 1e-12))
  mq_array_check(identical(.Random.seed, seed))
}
for (q in list(matrix(0, 1L, 7L), matrix(rep(c(-2,-2,-1,0,1,2,2), 2L), 2L, byrow = TRUE),
  matrix(seq(0, 6)*1e-320, 1L))) {
  kernels <- lapply(seq_len(nrow(q)), function(i) list(family = "mq_grid", q = as.numeric(q[i, ]), tau = mqb_tau))
  mq_array_check(mq_array_close(app_iqf_mq_matrix_inverse(q, mqb_tau, c(.01,.05,.5,.95,.99)),
    app_iqf_mq_mixture_inverse(kernels, c(.01,.05,.5,.95,.99)), 1e-12))
}
for (mutate in list(function(z) {z[1L] <- NA_real_; z}, function(z) {z[1L] <- Inf; z}))
  mq_array_reject(app_iqf_mq_matrix_inverse(mutate(matrix(1:14, 2L)), mqb_tau, .5))
mq_array_reject(app_iqf_mq_matrix_inverse(matrix(1:14, 2L), rev(mqb_tau), .5))
mq_array_reject(app_iqf_mq_matrix_inverse(matrix(1:14, 2L), mqb_tau, c(0,.5)))
mq_array_reject(app_iqf_mq_matrix_inverse(matrix(1:14, 2L), mqb_tau, .5, 0))
mq_array_reject(app_iqf_mq_matrix_inverse(1:7, mqb_tau, .5))

# Array and reference interfaces generate identical paths at all supported
# layer/activation/projection shapes, including H30 and arbitrary path IDs.
for (config in list(list(D=1L, activation="identity", projection=FALSE, standardize=TRUE),
  list(D=2L, activation="tanh", projection=FALSE, standardize=TRUE),
  list(D=3L, activation="relu", projection=TRUE, standardize=FALSE))) {
  f <- do.call(mqb_fixture, config); f$origins$o8$H <- 30L
  scalar <- do.call(app_iqf_desn_adapter, c(f, list(family = "mq_grid")))
  for (mode in c("native_scoped", "r46_first_step_qualified")) {
    batched <- do.call(app_iqf_mq_batch_adapter, c(f, list(inner_paths = 23L, batch_size = 3L,
      rng_mode = mode, rng_proof = if (mode == "native_scoped") NULL else app_iqf_mqb_rng_reference())))
    ids <- c(2L, 9L, 1L, 23L)
    seed <- .Random.seed; kind <- RNGkind()
    old <- app_iqf_mq_batch_paths(batched, f$posterior$draw_ids[1L], "o8", ids, TRUE)
    arrays <- app_iqf_mq_batch_arrays(batched, f$posterior$draw_ids[1L], "o8", ids, include_trace = TRUE)
    mq_array_check(is.null(arrays$paths) && !is.null(old$paths) && !is.null(arrays$raw_coherence))
    mq_array_check(identical(arrays$response, old$response) && identical(arrays$ordered_quantiles, old$ordered_quantiles))
    mq_array_check(identical(arrays$trace, old$trace))
    mq_array_check(!"raw_coherence" %in% names(old) && !"numerical_adapter" %in% names(old))
    mq_array_check(identical(.Random.seed, seed) && identical(RNGkind(), kind))
    for (i in seq_along(ids)) {
      one <- scalar$path(f$posterior$draw_ids[1L], "o8", ids[i])
      mq_array_check(mq_array_close(one$response, arrays$response[i, ]))
      mq_array_check(mq_array_close(do.call(rbind,lapply(one$kernels, `[[`, "q")),
        t(matrix(arrays$ordered_quantiles[i, , ], length(mqb_tau), 30L))))
    }
    coh <- arrays$raw_coherence; app_iqf_mqc_validate(coh)
    mq_array_check(all(coh$exposure_count == length(ids)))
    for (h in 1:30) {
      raw <- arrays$trace[[h]]$raw_quantiles
      projected <- arrays$trace[[h]]$ordered_quantiles
      mq_array_check(identical(as.numeric(coh$crossing_count[h, ]),
        as.numeric(colSums(raw[, -length(mqb_tau), drop=FALSE] > raw[, -1L, drop=FALSE]))))
      mq_array_check(mq_array_close(coh$adjustment_absolute_sum[h, ], colSums(abs(raw-projected))))
    }
    a <- app_iqf_mq_batch_arrays(batched, f$posterior$draw_ids[1L], "o8", ids[1:2])
    b <- app_iqf_mq_batch_arrays(batched, f$posterior$draw_ids[1L], "o8", ids[3:4])
    merged <- mq_coherence_merge(list(b$raw_coherence, a$raw_coherence))
    for (name in c("crossing_count","exposure_count","positive_gap_sum","maximum_positive_gap",
      "adjustment_absolute_sum","adjustment_squared_sum","maximum_absolute_adjustment"))
      mq_array_check(mq_array_close(merged[[name]],coh[[name]],1e-12))
    mq_array_check(identical(merged$path_ranges,coh$path_ranges))
    mq_array_reject(mq_coherence_merge(list(a$raw_coherence, a$raw_coherence)))
    mq_array_reject(app_iqf_mq_batch_arrays(batched,f$posterior$draw_ids[1L],"o8",24L))
    mq_array_reject(app_iqf_mq_batch_arrays(batched,f$posterior$draw_ids[1L],"o8",1:2,crossing_tolerance=-1))
  }
}
f <- mqb_fixture(); f$origins$o8$H <- 1L
one_adapter <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=1L)))
one <- app_iqf_mq_batch_arrays(one_adapter,f$posterior$draw_ids[1L],"o8",1L)
mq_array_check(identical(dim(one$response),c(1L,1L)) &&
  identical(dim(one$ordered_quantiles),c(1L,7L,1L)))
app_iqf_mqc_validate(one$raw_coherence)
mq_array_check(all(one$raw_coherence$exposure_count==1))

# Different inner resolutions must not silently change the outer measure.
tau <- c(.1,.5,.9)
make_coh <- function(raw, ids, draw) {
  ordered <- t(apply(raw,1L,function(x)app_iqf_grid(x,tau)$q))
  s <- app_iqf_mqc_init(1L,tau,ids,draw,"origin1","synthetic_weights")
  app_iqf_mqc_update(s,raw,ordered,1L)
}
a <- make_coh(matrix(rep(c(1,0,2),each=2L),2L),1:2,"drawA")
b <- make_coh(matrix(rep(c(0,1,2),each=20L),20L),3:22,"drawB")
w <- mq_coherence_weighted_summary(list(a,b),c(.5,.5))
mq_array_check(w$weighted_adjacent_crossing_rate[1,1]==.5 && w$overall_weighted_crossing_rate==.25)
mq_array_check(abs(w$overall_weighted_crossing_rate - sum(a$crossing_count+b$crossing_count)/
  sum(a$exposure_count+b$exposure_count))>.1)
mq_array_check(all(w$member_path_counts==c(2,20)) && !w$production_authorized)
mq_array_reject(mq_coherence_weighted_summary(list(a,b),c(1,1)))
mq_array_reject(mq_coherence_weighted_summary(list(a,b),c(0,1)))
mq_array_reject(mq_coherence_weighted_summary(list(a,a),c(.5,.5)))
bad <- b;bad$tolerance <- .1
mq_array_reject(mq_coherence_weighted_summary(list(a,bad),c(.5,.5)))
for (mutate in list(function(s){s$crossing_count[1] <- 3;s},
  function(s){s$exposure_count[1] <- 0;s},function(s){s$updated_horizons[1] <- FALSE;s},
  function(s){s$production_authorized <- TRUE;s},function(s){s$path_ranges$last[1] <- 100;s}))
  mq_array_reject(app_iqf_mqc_validate(mutate(a)))
mq_array_reject(app_iqf_mqc_update(a,matrix(0,2,3),matrix(0,2,3),1L))
mq_array_reject(app_iqf_mqc_ranges(c(1,1)))
mq_array_check(identical(app_iqf_mqc_ranges(c(10L,2L,1L,5L,4L)),data.frame(first=c(1L,4L,10L),last=c(2L,5L,10L))))

cat(sprintf("MQ_FORECAST_ARRAY_METHOD_CHECKS=%d PASS; authentic_reads=0 fits=0 scientific_forecasts=0 production=FALSE\n",mq_array_n))
