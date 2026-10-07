source("application/R/00_packages.R")
app_set_repo_root(getwd())
source(app_path("application/R/glofas_part4_exal_inner_audit.R"))
source(app_path("application/R/latent_path_vb_exal.R"))
source(app_path("application/R/latent_path_vb_joint.R"))

make_fit <- function(change, quadrature_y, quadrature_g, recorded = FALSE) {
  list(vb_diagnostics = list(
    converged = recorded,
    iteration_trace = data.frame(
      iteration = c(1L, 30L),
      parameter_change = c(1, change),
      convergence_eligible = c(FALSE, TRUE)
    ),
    quadrature_trace = data.frame(
      iteration = rep(30L, 6L),
      source = rep(c("Y", "G"), each = 3L),
      nodes_per_panel = rep(c(4L, 8L, 12L), 2L),
      relative_change = c(Inf, 1e-4, quadrature_y, Inf, 1e-4, quadrature_g)
    )
  ))
}

stable <- make_fit(5e-5, 5e-7, 7e-7, recorded = TRUE)
stable_gate <- app_glofas_part4_exal_inner_gate(stable, 0.5)
stopifnot(
  stable_gate$parameter_pass,
  stable_gate$quadrature_pass,
  stable_gate$recomputed_converged,
  identical(stable_gate$blocker, "none")
)

quadrature_limited <- make_fit(5e-6, 5e-7, 1.5e-6)
quadrature_gate <- app_glofas_part4_exal_inner_gate(quadrature_limited, 0.5)
stopifnot(
  quadrature_gate$parameter_pass,
  !quadrature_gate$quadrature_pass,
  identical(quadrature_gate$blocker, "quadrature")
)

tail_limited <- make_fit(0.04, 5e-7, 7e-7)
tail_gate <- app_glofas_part4_exal_inner_gate(tail_limited, 0.05)
stopifnot(
  !tail_gate$parameter_pass,
  tail_gate$quadrature_pass,
  identical(tail_gate$blocker, "parameter_change")
)

decision_table <- rbind(
  transform(tail_gate, quantile_level = 0.05),
  transform(stable_gate, quantile_level = 0.50),
  transform(tail_gate, quantile_level = 0.95)
)
stopifnot(identical(
  app_glofas_part4_exal_probe_decision(decision_table),
  "EXAL_TAIL_UPDATE_MAP_REQUIRES_CORRECTION"
))

moments <- list(
  Y = c(sigma_mean = 1, gamma_mean = 0, inv_B_sigma_mean = 2),
  G = c(sigma_mean = 2, gamma_mean = 1, inv_B_sigma_mean = 3)
)
local <- app_latent_exal_initial_local_state(list(
  block_moments = moments,
  latent_mean = c(1, 2), latent_inv_mean = c(3, 4),
  s_mean = c(0.5, 0.6), s2_mean = c(1.5, 1.6)
), moments, 2L)
stopifnot(
  local$local_factors_reused,
  local$block_moments_reused,
  identical(local$latent_mean, c(1, 2)),
  identical(local$block_moments$G, moments$G)
)

mock_fit <- list(
  summary = list(
    theta_mean = 1:2, theta_cov = diag(2),
    y_future_mean = 3:4, y_future_cov = diag(2),
    sigma_mean = c(Y = 1, G = 2), gamma_mean = c(Y = 0, G = 1)
  ),
  variational_state = list(
    block_moments = moments,
    latent_mean = c(1, 2), latent_inv_mean = c(3, 4),
    s_mean = c(0.5, 0.6), s2_mean = c(1.5, 1.6)
  )
)
full <- app_latent_joint_initial_state(mock_fit)
legacy <- app_latent_joint_initial_state(mock_fit, include_local_factors = FALSE)
stopifnot(
  isTRUE(full$provenance$local_factor_state_complete),
  identical(full$latent_mean, c(1, 2)),
  !isTRUE(legacy$provenance$local_factor_state_complete),
  is.null(legacy$latent_mean)
)

make_quadrature <- function(nodes, change, offset = 0, converged = TRUE) {
  list(
    log_normalizer = 10 + offset,
    branch_mass = c(negative = 0.4 + offset, positive = 0.6 - offset),
    moments = c(sigma_mean = 1 + offset, gamma_mean = 0.2 + offset),
    nodes_per_panel = nodes,
    relative_change = change,
    converged = converged
  )
}
candidate_quadrature <- list(
  Y = make_quadrature(16L, 5e-7, 2e-8),
  G = make_quadrature(16L, 7e-7, 3e-8)
)
reference_quadrature <- list(
  Y = make_quadrature(48L, 5e-9),
  G = make_quadrature(48L, 7e-9)
)
certificate <- app_glofas_part4_exal_quadrature_certificate(
  candidate_quadrature, reference_quadrature
)
stopifnot(nrow(certificate) == 2L, all(certificate$passed))
component_table <- app_glofas_part4_exal_quadrature_component_table(
  candidate_quadrature, reference_quadrature
)
stopifnot(
  nrow(component_table) == 10L,
  all(component_table$relative_difference >= 0),
  max(component_table$relative_difference) < 1e-6
)
reference_quadrature$G$converged <- FALSE
failed_certificate <- app_glofas_part4_exal_quadrature_certificate(
  candidate_quadrature, reference_quadrature
)
stopifnot(!failed_certificate$passed[failed_certificate$source == "G"])

cat("PASS: Part 4 exAL inner audit decomposition\n")
