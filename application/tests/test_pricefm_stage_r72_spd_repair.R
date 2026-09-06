args <- commandArgs(trailingOnly = TRUE)
library_path <- if (length(args)) args[[1L]] else {
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_pricefm_r72_spd_repair"
}

description <- utils::packageDescription("exdqlm", lib.loc = library_path)
namespace <- loadNamespace("exdqlm", lib.loc = library_path)
stopifnot(
  identical(as.character(description$Version), "1.1.1.9001"),
  identical(as.character(description$Repository), "PriceFM-local"),
  identical(
    as.character(description[["Config/PriceFM/base-tarball-sha256"]]),
    "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
  )
)

set.seed(72)
n <- 80L
X <- cbind(1, matrix(stats::rnorm(n * 4L), nrow = n))
y <- as.numeric(X %*% c(0.2, -0.1, 0.3, 0, 0.15) + stats::rnorm(n, sd = 0.2))
fit <- get("exalStaticLDVB", envir = namespace)(
  y = y,
  X = X,
  p0 = 0.5,
  beta_prior = "rhs_ns",
  beta_prior_controls = list(
    tau0 = 0.001,
    init_tau = 1,
    freeze_tau_iters = 5L,
    freeze_tau_warmup_iters = 5L
  ),
  dqlm.ind = TRUE,
  n.samp = 5L,
  vb_control = get("exal_make_vb_control", envir = namespace)(
    max_iter = 8L,
    tol = 1e-4,
    n_samp_xi = 10L,
    verbose = FALSE
  ),
  verbose = FALSE
)
stopifnot(
  length(fit$qbeta$m) == ncol(X),
  all(is.finite(fit$qbeta$m)),
  is.data.frame(fit$diagnostics$spd_factorization),
  nrow(fit$diagnostics$spd_factorization) == fit$iter,
  all(fit$diagnostics$spd_factorization$factorization_path %in% c(
    "direct", "legacy_absolute_1e-10", "scale_aware_symmetric_relative"
  )),
  is.data.frame(fit$diagnostics$vb_trace),
  identical(fit$diagnostics$rhs$preflight$init_tau_source, "init_tau")
)
