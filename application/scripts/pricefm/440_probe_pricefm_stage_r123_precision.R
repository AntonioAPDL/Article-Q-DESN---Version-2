#!/usr/bin/env Rscript
# One Gaussian conditional per endpoint, holding all model parameters fixed.
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[[1L]], mustWork = TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
repo <- normalizePath(file.path(dirname(script), "..", "..", ".."))
source(file.path(repo, "application/R/pricefm_recursive_normal_fit.R"))
manifest <- jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = FALSE)
stopifnot(length(manifest) == 10L, file.exists(file.path(root, "terminal.json")))
output <- file.path(root, "closeout/conditional_precision_probe.csv")
stopifnot(!file.exists(output))
rows <- lapply(manifest, function(c) {
  fit <- readRDS(file.path(c$output_dir, "fit.rds"))
  pkgload::load_all(c$package_path, quiet = TRUE, export_all = TRUE)
  factory <- get("beta_prior", envir = asNamespace("exdqlm"))
  prior <- factory("rhs_ns", rhs = list(tau0 = c$tau0, init_tau = 1, shrink_intercept = FALSE, intercept_prec = 1e-16))
  P <- (fit$omega2$a / fit$omega2$b) * fit$stats$XtX +
    diag(prior$expected_prec(fit$beta_prior$state, fit$stats$p), fit$stats$p)
  h <- (fit$omega2$a / fit$omega2$b) * fit$stats$Xty
  direct <- app_pricefm_sym_solve(P, h)
  scale <- sqrt(diag(P))
  equilibrated <- app_pricefm_sym_solve(P / outer(scale, scale), h / scale)
  covariance <- equilibrated$inv / outer(scale, scale)
  mean <- equilibrated$x / scale
  delta <- mean - direct$x
  data.frame(fit_id = c$fit_id, direct_jitter = direct$jitter, equilibrated_jitter = equilibrated$jitter,
    direct_inverse_residual = max(abs(P %*% direct$inv - diag(fit$stats$p))),
    equilibrated_inverse_residual = max(abs(P %*% covariance - diag(fit$stats$p))),
    relative_mean_solver_difference = sqrt(sum(delta^2)) / max(1, sqrt(sum(direct$x^2))),
    prediction_rmse_solver_difference = sqrt(max(0, as.numeric(crossprod(delta, fit$stats$XtX %*% delta)) / fit$stats$n)),
    prior_hyperparameters_unchanged = identical(prior$hypers, fit$beta_prior$hypers))
})
utils::write.csv(do.call(rbind, rows), output, row.names = FALSE)
cat("R123 held-target Gaussian conditional probe complete; no optimization or fit mutation\n")
