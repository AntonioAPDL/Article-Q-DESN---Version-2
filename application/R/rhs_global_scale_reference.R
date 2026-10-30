# Reference calibration for the regularized-horseshoe global-scale hyperprior.
#
# The calculation follows the ordinary-horseshoe Gaussian reference relation
# described by Piironen and Vehtari (2017). For correlated designs and a
# finite-slab prior, the returned value is a reference scale rather than an
# exact prior expectation of model size.

app_rhs_reference_tau0 <- function(
    m0,
    r,
    n_fit,
    sigma_ref = 1,
    information_factor = 1) {
  scalar_finite <- function(x) {
    is.numeric(x) && length(x) == 1L && is.finite(x)
  }

  if (!scalar_finite(r) || r <= 1 || r != as.integer(r)) {
    stop("r must be an integer greater than one.", call. = FALSE)
  }
  if (!scalar_finite(m0) || m0 <= 0 || m0 >= r) {
    stop("m0 must satisfy 0 < m0 < r.", call. = FALSE)
  }
  if (!scalar_finite(n_fit) || n_fit <= 0 || n_fit != as.integer(n_fit)) {
    stop("n_fit must be a positive integer.", call. = FALSE)
  }
  if (!scalar_finite(sigma_ref) || sigma_ref <= 0) {
    stop("sigma_ref must be positive and finite.", call. = FALSE)
  }
  if (!scalar_finite(information_factor) || information_factor <= 0) {
    stop("information_factor must be positive and finite.", call. = FALSE)
  }

  (m0 / (r - m0)) *
    sigma_ref / sqrt(n_fit * information_factor)
}

app_rhs_reference_tau0_al <- function(m0, r, n_fit, p0, sigma_ref = 1) {
  if (!is.numeric(p0) || length(p0) != 1L || !is.finite(p0) ||
      p0 <= 0 || p0 >= 1) {
    stop("p0 must satisfy 0 < p0 < 1.", call. = FALSE)
  }

  app_rhs_reference_tau0(
    m0 = m0,
    r = r,
    n_fit = n_fit,
    sigma_ref = sigma_ref,
    information_factor = p0 * (1 - p0)
  )
}

app_rhs_reference_tau0_exal <- function(
    m0,
    r,
    n_fit,
    j_ref,
    sigma_ref = 1) {
  app_rhs_reference_tau0(
    m0 = m0,
    r = r,
    n_fit = n_fit,
    sigma_ref = sigma_ref,
    information_factor = j_ref
  )
}
