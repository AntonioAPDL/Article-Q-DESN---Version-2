#!/usr/bin/env Rscript
# Focused independent-family gate, not a full joint-prior audit.
args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag) args[[match(flag, args) + 1L]]
normal <- normalizePath(arg("--normal-runtime"), mustWork = TRUE)
cran <- normalizePath(arg("--cran-library"), mustWork = TRUE)
output <- arg("--output")
stopifnot(!file.exists(output))

pkgload::load_all(normal, quiet = TRUE, export_all = TRUE)
factory <- get("beta_prior", envir = asNamespace("exdqlm"))
results <- list()
for (p in c(7L, 31L, 257L, 577L)) {
  left <- factory("rhs_ns", rhs = list(tau0 = 2e-4, init_tau = .2, shrink_intercept = FALSE))
  right <- factory("rhs_ns", rhs = list(tau0 = 2e-4, init_tau = 2, shrink_intercept = FALSE))
  stopifnot(identical(left$hypers, right$hypers))
  a <- left$init(p); b <- right$init(p)
  expected <- ((p - 1) + 1) / 2
  stopifnot(a$a_tau == expected, b$a_tau == expected, a$tau2 != b$tau2)
  q <- list(m = rep(.1, p), V = diag(.01, p))
  a <- left$update(a, q); b <- right$update(b, q)
  stopifnot(a$a_tau == expected, b$a_tau == expected,
            identical(left$hypers, right$hypers), is.finite(left$elbo(a, q)$elbo))
  results[[paste0("normal_p", p)]] <- TRUE
}
unloadNamespace("exdqlm")
ns <- loadNamespace("exdqlm", lib.loc = cran)
description <- utils::packageDescription("exdqlm", lib.loc = cran)
stopifnot(description$Version == "1.1.1", description$Repository == "CRAN")
make <- get(".static_beta_prior_make", envir = ns)
for (p in c(7L, 31L, 257L, 577L)) {
  priors <- lapply(c(0, 8), function(center) make("rhs_ns", p, rep(center, p), diag(1e6, p),
      list(tau0 = 2e-4, shrink_intercept = FALSE, freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L)))
  stopifnot(identical(priors[[1]]$controls, priors[[2]]$controls))
  q <- list(m = rep(.1, p), V = diag(.01, p))
  a <- priors[[1]]$init_vb(); b <- priors[[2]]$init_vb()
  stopifnot(a$a_tau == p / 2, b$a_tau == p / 2,
            all(priors[[1]]$beta_system_vb(a)$h == 0), all(priors[[2]]$beta_system_vb(b)$h == 0),
            isTRUE(all.equal(priors[[1]]$elbo_vb(a, q), priors[[2]]$elbo_vb(b, q))))
  a <- priors[[1]]$update_vb(a, q)
  stopifnot(a$a_tau == p / 2)
  results[[paste0("al_p", p)]] <- TRUE
}
# Product Gaussian HS term contributes -d/2 log(tau2); the IG(1/2,1/xi)
# auxiliary contributes -3/2 log(tau2). IG(shape,rate) has -(shape+1) log(tau2).
for (d in c(6L, 30L, 256L, 576L)) {
  rate <- .7
  kernel <- function(x) -(d / 2 + 1.5) * log(x) - rate / x
  inverse_gamma <- function(x) -(((d + 1) / 2) + 1) * log(x) - rate / x
  stopifnot(abs((kernel(.3) - kernel(2)) - (inverse_gamma(.3) - inverse_gamma(2))) < 1e-10)
}
jsonlite::write_json(list(status = "R123_PRIOR_GATE_PASS", checks = results,
  prior_representation = "NS_product_Gaussian_HS_and_slab_project_convention",
  inverse_gamma_convention = "shape_rate_for_inverse_variable",
  intercept_shrunk = FALSE, warm_start_is_prior_center = FALSE,
  scope = "independent_Normal_and_AL_VB_only_not_full_historical_or_joint_audit"),
  output, auto_unbox = TRUE, pretty = TRUE)
cat("R123 prior gate passed\n")
