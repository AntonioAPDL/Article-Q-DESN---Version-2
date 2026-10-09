#!/usr/bin/env Rscript

# Bounded regression checks for supplementary identities and source labels.
# These tests do not fit a model, inspect runtime objects, or authenticate
# historical scientific execution, quadrature tolerances, or convergence.
local({
  if (exists("app_repo_root", mode = "function")) {
    root <- app_repo_root()
  } else {
    file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(file_arg) != 1L) {
      stop("Run this test with Rscript or source it from the repository harness.",
           call. = FALSE)
    }
    root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)),
                                    "..", ".."), mustWork = TRUE)
  }
  source(file.path(root, "application/R/00_packages.R"), local = TRUE)
  app_set_repo_root(root)
  source(file.path(root, "application/R/joint_qvp_qdesn.R"), local = TRUE)
  source(file.path(root, "application/R/joint_exqdesn_exact_structured_inference.R"),
         local = TRUE)

  receipt <- data.frame(check = character(), status = character(),
                        max_error = numeric(), stringsAsFactors = FALSE)
  record <- function(name, error, tolerance = 1e-9) {
    if (!is.finite(error) || error > tolerance) {
      stop(sprintf("%s: error %.12g exceeds %.12g.", name, error, tolerance),
           call. = FALSE)
    }
    receipt <<- rbind(receipt, data.frame(check = name, status = "PASS",
                                         max_error = error))
  }

  # Complete Gaussian product mass includes the scale-dependent factor.
  grid <- expand.grid(beta = c(-2, 0.25, 1), a = c(0.2, 2), b = c(0.7, 3))
  left <- with(grid, dnorm(beta, 0, sqrt(a), log = TRUE) +
                      dnorm(0, beta, sqrt(b), log = TRUE))
  right <- with(grid, dnorm(0, 0, sqrt(a + b), log = TRUE) +
                       dnorm(beta, 0, sqrt(a * b / (a + b)), log = TRUE))
  record("Gaussian product retains scale-dependent mass", max(abs(left - right)))

  # r slope factors plus IG(1/2,1/xi) give shape (r+1)/2, not an intercept.
  r <- c(1, 6, 120)
  record("Global IG shape counts slopes", max(abs(-r / 2 - 3 / 2 + (r + 1) / 2 + 1)))
  record("Global IG implementation matches identity",
         max(abs(vapply(r, app_joint_qvp_rhs_tau2_shape, numeric(1)) - (r + 1) / 2)))

  # The original-coordinate lognormal entropy includes E(log Jacobian).
  eta_mean <- 0.4
  eta_sd <- 0.6
  gaussian_entropy <- 0.5 * log(2 * pi * exp(1) * eta_sd^2)
  lognormal_entropy <- integrate(function(x) {
    f <- dlnorm(x, eta_mean, eta_sd)
    -f * dlnorm(x, eta_mean, eta_sd, log = TRUE)
  }, 0, Inf, rel.tol = 1e-11)$value
  record("Transformed entropy includes Jacobian once",
         abs(lognormal_entropy - gaussian_entropy - eta_mean))

  target_mean <- -0.2
  target_sd <- 0.9
  expect_eta <- function(fun) integrate(function(eta) {
    fun(eta) * dnorm(eta, eta_mean, eta_sd)
  }, eta_mean - 10 * eta_sd, eta_mean + 10 * eta_sd, rel.tol = 1e-11)$value
  original_elbo <- expect_eta(function(eta) {
    dlnorm(exp(eta), target_mean, target_sd, log = TRUE) -
      dlnorm(exp(eta), eta_mean, eta_sd, log = TRUE)
  })
  transformed_elbo <- expect_eta(function(eta) {
    dlnorm(exp(eta), target_mean, target_sd, log = TRUE) + eta -
      dnorm(eta, eta_mean, eta_sd, log = TRUE)
  })
  record("Equivalent-coordinate ELBOs agree", abs(original_elbo - transformed_elbo))

  # Repeated observations are Gaussian density-evaluation arguments.
  y <- rep(c(-0.5, 0.4, 1.2), 2)
  mu <- seq(-0.3, 0.8, length.out = 6)
  variance <- seq(0.6, 1.4, length.out = 6)
  scalar_eval <- sum(dnorm(y, mu, sqrt(variance), log = TRUE))
  stacked_eval <- -length(y) / 2 * log(2 * pi) - 0.5 * sum(log(variance)) -
    0.5 * sum((y - mu)^2 / variance)
  record("Stacked density equals univariate product", abs(scalar_eval - stacked_eval))

  # Adjacent-difference moments must retain multivariate slope covariance.
  covariance <- matrix(c(1, 0.6, 0.6, 2), 2)
  mean <- c(0.2, -0.3)
  difference <- matrix(c(1, -1, 0, 1), 2)
  matrix_second <- diag(difference %*% (covariance + tcrossprod(mean)) %*% t(difference))
  scalar_second <- c(covariance[1, 1] + mean[1]^2,
    covariance[1, 1] + covariance[2, 2] - 2 * covariance[1, 2] + (mean[2] - mean[1])^2)
  record("Increment moments retain covariance", max(abs(matrix_second - scalar_second)))

  # Match the unweighted v-augmentation kernel on both shape branches.
  residual_mean <- c(-0.4, 0.2, 1)
  residual_second <- residual_mean^2 + c(0.05, 0.1, 0.15)
  v_mean <- c(0.8, 1.1, 1.5)
  v_inv <- c(1.6, 1.2, 0.9)
  s_mean <- c(0.5, 0.8, 0.4)
  s_second <- s_mean^2 + c(0.1, 0.2, 0.08)
  for (shape in c(-0.25, 0.25)) {
    constants <- app_joint_exqdesn_constants(0.5, shape)
    A <- constants$A
    B <- constants$B
    D <- constants$lambda
    nu <- -0.8 - 1.5 * length(residual_mean)
    chi <- 2 * 0.6 + 2 * sum(v_mean) +
      sum(residual_second * v_inv - 2 * A * residual_mean + A^2 * v_mean) / B
    psi <- D^2 * sum(s_second * v_inv) / B
    c_shape <- -length(residual_mean) / 2 * log(B) +
      D * sum(s_mean * (residual_mean * v_inv - A)) / B
    terms <- app_joint_exqdesn_structured_terms(shape, 0.5, "v",
      residual_mean, residual_second, v_mean, v_inv, s_mean, s_second,
      a_sigma = 0.8, b_sigma = 0.6)
    record(paste("Structured v kernel, shape", shape), max(abs(c(nu - terms$nu,
      chi - terms$chi, psi - terms$psi, c_shape - terms$cross - terms$log_shape))))

    direct_log_kernel <- function(sigma) {
      -0.5 * length(residual_mean) * log(sigma * B) -
        sum(residual_second * v_inv - 2 * A * residual_mean + A^2 * v_mean -
          2 * sigma * D * s_mean * (residual_mean * v_inv - A) +
          sigma^2 * D^2 * s_second * v_inv) / (2 * B * sigma) -
        length(residual_mean) * log(sigma) - sum(v_mean) / sigma -
        (0.8 + 1) * log(sigma) - 0.6 / sigma
    }
    sigma_grid <- c(0.2, 0.7, 1.8)
    collapsed_kernel <- c_shape + (nu - 1) * log(sigma_grid) -
      0.5 * (chi / sigma_grid + psi * sigma_grid)
    record(paste("Direct augmented expansion, shape", shape),
           max(abs(vapply(sigma_grid, direct_log_kernel, numeric(1)) - collapsed_kernel)))

    numeric_mass <- integrate(function(sigma) {
      exp((nu - 1) * log(sigma) - 0.5 * (chi / sigma + psi * sigma))
    }, 0, Inf, rel.tol = 1e-10)$value
    analytic_mass <- exp(app_joint_exqdesn_gig_log_integral(nu, chi, psi))
    record(paste("Analytic scale integral, shape", shape),
           abs(numeric_mass / analytic_mass - 1), 1e-8)
    for (power in c(-1, 1, 2)) {
      numeric_moment <- integrate(function(sigma) {
        exp((nu + power - 1) * log(sigma) - 0.5 * (chi / sigma + psi * sigma))
      }, 0, Inf, rel.tol = 1e-10)$value / numeric_mass
      analytic_moment <- app_joint_exqdesn_gig_moment(nu, chi, psi, power)
      record(paste("Conditional scale moment", power, "shape", shape),
             abs(numeric_moment / analytic_moment - 1), 1e-8)
    }
  }

  nu <- -4
  chi <- 3
  numeric_mass <- integrate(function(sigma) {
    exp((nu - 1) * log(sigma) - chi / (2 * sigma))
  }, 0, Inf, rel.tol = 1e-11)$value
  record("AL-limit scale integral", abs(numeric_mass / (gamma(-nu) * (chi / 2)^nu) - 1))

  # Stable source labels and the corrected numbered ELBO environment.
  supplement <- paste(readLines(file.path(root, "qdesn-supplement.tex"),
                                warn = FALSE), collapse = "\n")
  for (label in c("eq:supp_ns_full_prior", "eq:supp_generic_vb_scale_family",
                  "eq:supp_elbo_transformed_coordinates", "eq:supp_joint_stacked_likelihood",
                  "subsec:supp_structured_exal_vb", "eq:supp_structured_scale_shape_kernel",
                  "eq:supp_structured_scale_integral", "eq:supp_structured_mixed_moments")) {
    record(paste("Supplement label", label),
           if (grepl(paste0("\\label{", label, "}"), supplement, fixed = TRUE)) 0 else Inf)
  }
  label_position <- regexpr("\\label{eq:supp_generic_elbo}", supplement, fixed = TRUE)[1]
  if (label_position < 0) stop("Missing generic ELBO label.", call. = FALSE)
  before_label <- substr(supplement, 1, label_position - 1)
  equation_starts <- gregexpr("\\begin{equation}", before_label, fixed = TRUE)[[1]]
  equation_start <- tail(equation_starts[equation_starts > 0], 1)
  numbered_prefix <- substr(before_label, equation_start, nchar(before_label))
  record("ELBO label belongs to a numbered equation",
         if (length(equation_start) == 1L &&
             !grepl("\\end{equation}", numbered_prefix, fixed = TRUE)) 0 else Inf)

  print(receipt, row.names = FALSE)
  cat("PRO_REVIEW_SUPPLEMENT_MATH_PASS", nrow(receipt), "\n")
})
