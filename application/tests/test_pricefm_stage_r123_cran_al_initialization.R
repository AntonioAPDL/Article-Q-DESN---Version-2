#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag) args[[match(flag, args) + 1L]]
cran <- normalizePath(arg("--cran-library"), mustWork = TRUE)
output <- arg("--output")
stopifnot(!file.exists(output))
ns <- loadNamespace("exdqlm", lib.loc = cran)
description <- utils::packageDescription("exdqlm", lib.loc = cran)
stopifnot(description$Version == "1.1.1", description$Repository == "CRAN")
archive <- normalizePath(file.path(cran, "..", "..", "runtime_sources",
  "exdqlm_cran_1p1p1", "exdqlm_1.1.1.tar.gz"), mustWork = TRUE)
archive_sha <- strsplit(system2("sha256sum", shQuote(archive), stdout = TRUE), " ")[[1L]][1L]
stopifnot(archive_sha == "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e")
matched <- list()
for (file in c("utils.R", "static_beta_prior.R", "exalStaticLDVB.R")) {
  expressions <- parse(text = system2("tar", c("-xOf", shQuote(archive), paste0("exdqlm/R/", file)), stdout = TRUE))
  for (name in c(".run_static_dqlm_cavi", ".static_rhs_ns_init_vb_state",
                 ".static_rhs_ns_update_vb", ".static_rhs_ns_elbo_vb", "exalStaticLDVB")) {
    where <- which(vapply(expressions, function(e) is.call(e) && identical(e[[1L]], as.name("<-")) &&
      identical(e[[2L]], as.name(name)), logical(1)))
    if (length(where)) {
      archived <- eval(expressions[[where]][[3L]], envir = ns)
      stopifnot(identical(body(archived), body(get(name, ns))),
        identical(formals(archived), formals(get(name, ns))))
      matched[[name]] <- TRUE
    }
  }
}
stopifnot(length(matched) == 5L)

set.seed(123)
X <- cbind(1, matrix(rnorm(480), 80, 6))
y <- as.numeric(X %*% c(.1, .2, -.1, rep(0, 4))) + rnorm(80, sd = .2)
controls <- list(tau0 = 2e-4, shrink_intercept = FALSE,
  freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L)
api <- get("exalStaticLDVB", ns)
fit <- function(seed, beta, sigma) {
  set.seed(seed)
  api(y, X, .5, beta_prior = "rhs_ns", beta_prior_controls = controls,
    a_sigma = 1, b_sigma = 1, init = list(beta = beta, sigma = sigma),
    dqlm.ind = TRUE, max_iter = 3L, n.samp = 2L, verbose = FALSE)
}
a <- fit(1, rep(0, 7), .2)
b <- fit(2, rep(0, 7), .2)
c <- fit(1, rep(.3, 7), .8)
stopifnot(identical(a$beta_prior$controls, b$beta_prior$controls),
  identical(a$beta_prior$controls, c$beta_prior$controls),
  identical(a$qbeta, b$qbeta), !isTRUE(all.equal(a$qbeta$m, c$qbeta$m)),
  a$beta_prior$state$a_tau == 7 / 2, c$beta_prior$state$a_tau == 7 / 2,
  a$qsig$a == 1 + 1.5 * nrow(X), c$qsig$a == a$qsig$a)

make <- get(".static_beta_prior_make", ns)
prior <- make("rhs_ns", 7, rep(0, 7), diag(1e6, 7), controls)
q <- list(m = rep(.1, 7), V = diag(.01, 7))
state <- prior$init_vb()
kernel <- prior$elbo_vb(state, q)
stopifnot(is.finite(kernel), all(prior$beta_system_vb(state)$h == 0))
# The public AL stop flag monitors beta means, sigma and ELBO, not a
# separately certified covariance/RHS/latent-state fixed point.
engine <- paste(deparse(get(".run_static_dqlm_cavi", ns)), collapse = "\n")
stopifnot(grepl("d_beta <- max(abs(m_beta - prev_m_beta))", engine, fixed = TRUE),
  grepl("d_state = d_beta", engine, fixed = TRUE),
  !is.null(a$qv), !is.null(a$beta_prior$state), isFALSE(a$converged))
jsonlite::write_json(list(status = "R123_CRAN_AL_INITIALIZATION_PASS",
  package_version = description$Version, package_repository = description$Repository,
  source_archive_sha256 = archive_sha, installed_function_bodies_match_archive = matched,
  seed_changes_prior = FALSE, upstream_beta_sigma_changes_prior = FALSE,
  shape = 7 / 2, shrinkage_dimension = 6,
  full_variational_stationarity_claim = FALSE,
  scope = "isolated_independent_AL_VB_public_API_only_not_joint_or_MCMC"),
  output, auto_unbox = TRUE, pretty = TRUE)
cat("R123 exact CRAN AL initialization test passed\n")
