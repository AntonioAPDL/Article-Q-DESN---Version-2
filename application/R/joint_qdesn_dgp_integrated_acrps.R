# Post-Phase178 DGP-integrated finite-grid quantile scoring.

app_joint_qdesn_postscore_contract_path <- function() {
  app_path("application/config/joint_qdesn_post_phase178_dgp_score_contract_v1.csv")
}

app_joint_qdesn_postscore_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  c(app_joint_exqdesn_phase176_dirs(cache_root), list(
    postscore_contract = file.path(
      cache_root, "joint_qdesn_post_phase178_dgp_score_contract_20260819"
    ),
    postscore_work = file.path(
      cache_root, "joint_qdesn_post_phase178_dgp_score_audit_20260819_work"
    ),
    postscore_audit = file.path(
      cache_root, "joint_qdesn_post_phase178_dgp_score_audit_20260819"
    )
  ))
}

app_joint_qdesn_postscore_split <- function(x) {
  trimws(strsplit(as.character(x)[[1L]], ";", fixed = TRUE)[[1L]])
}

app_joint_qdesn_postscore_contract_value <- function(contract, name) {
  hit <- contract[contract$contract_name == name, , drop = FALSE]
  if (nrow(hit) != 1L) {
    stop(sprintf("Score contract must contain exactly one '%s' row.", name), call. = FALSE)
  }
  as.character(hit$value[[1L]])
}

app_joint_qdesn_postscore_read_contract <- function(
  path = app_joint_qdesn_postscore_contract_path()
) {
  contract <- app_read_csv(path)
  required <- c(
    "contract_section", "contract_name", "value", "value_type", "rationale"
  )
  app_check_required_columns(contract, required, "post-Phase178 score contract")
  if (anyDuplicated(contract$contract_name)) {
    stop("Post-Phase178 score contract names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_qdesn_postscore_contract_value(contract, name)
  num <- function(name) as.numeric(get(name))
  int <- function(name) as.integer(get(name))
  num_vec <- function(name) as.numeric(app_joint_qdesn_postscore_split(get(name)))
  int_vec <- function(name) as.integer(app_joint_qdesn_postscore_split(get(name)))
  tau <- num_vec("tau_grid")
  weights <- num_vec("quadrature_weights_qs")
  expected_weights <- c(
    (tau[[2L]] - tau[[1L]]) / 2,
    (tau[3:length(tau)] - tau[1:(length(tau) - 2L)]) / 2,
    (tau[[length(tau)]] - tau[[length(tau) - 1L]]) / 2
  )
  if (!identical(tau, sort(unique(tau))) || any(tau <= 0 | tau >= 1) ||
      length(weights) != length(tau) ||
      max(abs(weights - expected_weights)) > 1e-12 ||
      !identical(tolower(get("renormalize_weights")), "false")) {
    stop("Post-Phase178 tau or trapezoidal-weight contract is malformed.", call. = FALSE)
  }
  list(
    table = contract,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    tau = tau,
    weights_qs = weights,
    score_draws_per_chain = int("score_draws_per_chain"),
    sensitivity_draws_per_chain = int("sensitivity_draws_per_chain"),
    chunk_size = int("chunk_size"),
    primary_pairing_seed = int("primary_pairing_seed"),
    sensitivity_pairing_seeds = int_vec("sensitivity_pairing_seeds"),
    practical_relative_margin = num("practical_relative_margin"),
    posterior_probability_floor = num("posterior_probability_floor"),
    protected_replicate_direction_floor = num("protected_replicate_direction_floor"),
    oracle_recovery_ratio_ceiling = num("oracle_recovery_ratio_ceiling"),
    score_rank_rhat_ceiling = num("score_rank_rhat_ceiling"),
    score_bulk_ess_floor = num("score_bulk_ess_floor"),
    score_tail_ess_floor = num("score_tail_ess_floor"),
    raw_crossing_rate_review = num("raw_crossing_rate_review"),
    standardized_adjustment_review = num("standardized_adjustment_review"),
    regret_tolerance = num("regret_tolerance"),
    analytic_integration_tolerance = num("analytic_integration_tolerance"),
    monte_carlo_tolerance = num("monte_carlo_tolerance"),
    expected_workers = int("expected_workers"),
    expected_candidate_replicates = int("expected_candidate_replicates"),
    expected_target_cells = int("expected_target_cells")
  )
}

app_joint_qdesn_postscore_with_seed <- function(seed, code) {
  old <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else NULL
  on.exit({
    if (is.null(old)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    } else assign(".Random.seed", old, envir = .GlobalEnv)
  }, add = TRUE)
  set.seed(as.integer(seed))
  force(code)
}

app_joint_qdesn_postscore_even_indices <- function(n, target) {
  n <- as.integer(n)[[1L]]
  target <- min(n, as.integer(target)[[1L]])
  if (n <= 0L || target <= 0L) stop("Draw counts must be positive.", call. = FALSE)
  if (target == n) return(seq_len(n))
  as.integer(floor(((seq_len(target) - 0.5) * n) / target) + 1L)
}

app_joint_qdesn_postscore_normal_abs <- function(a, mean = 0, sd = 1) {
  z <- (a - mean) / sd
  2 * sd * stats::dnorm(z) + (a - mean) * (2 * stats::pnorm(z) - 1)
}

app_joint_qdesn_postscore_standardized_mean <- function(sc) {
  family <- as.character(sc$distribution_family[[1L]])
  if (family %in% c("gaussian", "laplace", "student_t", "gaussian_mixture")) {
    return(0)
  }
  if (identical(family, "asymmetric_laplace")) {
    p <- as.numeric(sc$al_tau[[1L]])
    raw_mean <- (1 - 2 * p) / (p * (1 - p))
    return(raw_mean / app_joint_qvp_al_sd(p))
  }
  stop(sprintf("Unsupported DGP family '%s'.", family), call. = FALSE)
}

app_joint_qdesn_postscore_expected_abs_standardized <- function(z, sc) {
  family <- as.character(sc$distribution_family[[1L]])
  z <- as.numeric(z)
  if (identical(family, "gaussian")) {
    return(2 * stats::dnorm(z) + z * (2 * stats::pnorm(z) - 1))
  }
  if (identical(family, "laplace")) {
    b <- 1 / sqrt(2)
    return(abs(z) + b * exp(-abs(z) / b))
  }
  if (identical(family, "student_t")) {
    df <- as.numeric(sc$df[[1L]])
    scale <- sqrt(df / (df - 2))
    a <- scale * z
    raw <- a * (2 * stats::pt(a, df = df) - 1) +
      2 * (df + a^2) * stats::dt(a, df = df) / (df - 1)
    return(raw / scale)
  }
  if (identical(family, "asymmetric_laplace")) {
    p <- as.numeric(sc$al_tau[[1L]])
    scale <- app_joint_qvp_al_sd(p)
    a <- scale * z
    raw_mean <- (1 - 2 * p) / (p * (1 - p))
    raw_abs <- ifelse(
      a < 0,
      raw_mean - a + 2 * p * exp((1 - p) * a) / (1 - p),
      a - raw_mean + 2 * (1 - p) * exp(-p * a) / p
    )
    return(raw_abs / scale)
  }
  if (identical(family, "gaussian_mixture")) {
    mix <- app_joint_qvp_registry_mixture_params(sc)
    moments <- app_joint_qvp_gaussian_mixture_moments(
      mix$weight, mix$mean1, mix$sd1, mix$mean2, mix$sd2
    )
    a <- moments$mean + moments$sd * z
    raw <- mix$weight * app_joint_qdesn_postscore_normal_abs(
      a, mix$mean1, mix$sd1
    ) + (1 - mix$weight) * app_joint_qdesn_postscore_normal_abs(
      a, mix$mean2, mix$sd2
    )
    return(raw / moments$sd)
  }
  stop(sprintf("Unsupported DGP family '%s'.", family), call. = FALSE)
}

app_joint_qdesn_postscore_expected_check_standardized <- function(q, tau, sc) {
  q <- as.numeric(q)
  tau <- as.numeric(tau)
  if (length(tau) == 1L) tau <- rep(tau, length(q))
  if (length(q) != length(tau) || any(!is.finite(q)) ||
      any(!is.finite(tau)) || any(tau <= 0 | tau >= 1)) {
    stop("Expected standardized check loss received invalid q or tau.", call. = FALSE)
  }
  mean_z <- app_joint_qdesn_postscore_standardized_mean(sc)
  0.5 * app_joint_qdesn_postscore_expected_abs_standardized(q, sc) +
    (tau - 0.5) * (mean_z - q)
}

app_joint_qdesn_postscore_expected_check <- function(q, tau, mu, sigma, sc) {
  q <- as.numeric(q); mu <- as.numeric(mu); sigma <- as.numeric(sigma)
  n <- max(length(q), length(mu), length(sigma), length(tau))
  q <- rep(q, length.out = n); mu <- rep(mu, length.out = n)
  sigma <- rep(sigma, length.out = n); tau <- rep(tau, length.out = n)
  if (any(!is.finite(c(q, mu, sigma, tau))) || any(sigma <= 0)) {
    stop("Expected check loss requires finite values and positive scale.", call. = FALSE)
  }
  sigma * app_joint_qdesn_postscore_expected_check_standardized(
    (q - mu) / sigma, tau, sc
  )
}

app_joint_qdesn_postscore_standardized_density <- function(z, sc) {
  family <- as.character(sc$distribution_family[[1L]])
  if (identical(family, "gaussian")) return(stats::dnorm(z))
  if (identical(family, "laplace")) {
    b <- 1 / sqrt(2)
    return(exp(-abs(z) / b) / (2 * b))
  }
  if (identical(family, "student_t")) {
    df <- as.numeric(sc$df[[1L]])
    scale <- sqrt(df / (df - 2))
    return(scale * stats::dt(scale * z, df = df))
  }
  if (identical(family, "asymmetric_laplace")) {
    p <- as.numeric(sc$al_tau[[1L]])
    scale <- app_joint_qvp_al_sd(p)
    raw <- scale * z
    return(scale * p * (1 - p) * ifelse(
      raw < 0, exp((1 - p) * raw), exp(-p * raw)
    ))
  }
  if (identical(family, "gaussian_mixture")) {
    mix <- app_joint_qvp_registry_mixture_params(sc)
    moments <- app_joint_qvp_gaussian_mixture_moments(
      mix$weight, mix$mean1, mix$sd1, mix$mean2, mix$sd2
    )
    raw <- moments$mean + moments$sd * z
    return(moments$sd * (
      mix$weight * stats::dnorm(raw, mix$mean1, mix$sd1) +
        (1 - mix$weight) * stats::dnorm(raw, mix$mean2, mix$sd2)
    ))
  }
  stop(sprintf("Unsupported DGP family '%s'.", family), call. = FALSE)
}

app_joint_qdesn_postscore_expected_check_numerical <- function(
  q, tau, sc, rel.tol = 1e-10
) {
  stats::integrate(function(z) {
    u <- z - q
    u * (tau - as.numeric(u < 0)) *
      app_joint_qdesn_postscore_standardized_density(z, sc)
  }, lower = -Inf, upper = Inf, rel.tol = rel.tol, subdivisions = 2000L)$value
}

app_joint_qdesn_postscore_standardized_random <- function(n, sc, seed) {
  app_joint_qdesn_postscore_with_seed(
    seed, app_joint_qvp_registry_standardized_innovation(n, sc)$standardized
  )
}

app_joint_qdesn_postscore_check_loss <- function(y, q, tau) {
  u <- y - q
  u * (tau - as.numeric(u < 0))
}

app_joint_qdesn_postscore_contract_rows <- function(q_raw, tau, tolerance = 1e-12) {
  q_raw <- as.matrix(q_raw)
  K <- ncol(q_raw)
  if (K != length(tau)) stop("Quantile matrix and tau grid differ.", call. = FALSE)
  crossing <- q_raw[, seq_len(K - 1L), drop = FALSE] -
    q_raw[, 2:K, drop = FALSE]
  crossed <- which(rowSums(crossing > tolerance) > 0L)
  q_contract <- q_raw
  if (length(crossed)) {
    fixed <- vapply(crossed, function(ii) {
      app_isotonic_quantiles(tau, q_raw[ii, ])
    }, numeric(K))
    q_contract[crossed, ] <- t(fixed)
  }
  contract_crossing <- q_contract[, seq_len(K - 1L), drop = FALSE] -
    q_contract[, 2:K, drop = FALSE]
  list(
    q_contract = q_contract,
    raw_crossing = crossing,
    contract_crossing = contract_crossing,
    adjusted_rows = crossed
  )
}

app_joint_qdesn_postscore_score_matrix <- function(
  qhat, y, mu, sigma, sc, tau, weights
) {
  qhat <- as.matrix(qhat)
  if (nrow(qhat) != length(y) || ncol(qhat) != length(tau) ||
      length(mu) != nrow(qhat) || length(sigma) != nrow(qhat)) {
    stop("Point score inputs do not align.", call. = FALSE)
  }
  expected_tau <- realized_tau <- numeric(length(tau))
  for (kk in seq_along(tau)) {
    expected_tau[[kk]] <- mean(app_joint_qdesn_postscore_expected_check(
      qhat[, kk], tau[[kk]], mu, sigma, sc
    ))
    realized_tau[[kk]] <- mean(app_joint_qdesn_postscore_check_loss(
      y, qhat[, kk], tau[[kk]]
    ))
  }
  list(
    dgp_integrated_acrps = sum(weights * 2 * expected_tau),
    realized_acrps = sum(weights * 2 * realized_tau),
    expected_check_loss_by_tau = expected_tau,
    realized_check_loss_by_tau = realized_tau
  )
}

app_joint_qdesn_postscore_validation_scenarios <- function() {
  data.frame(
    distribution_family = c(
      "gaussian", "laplace", "student_t", "asymmetric_laplace",
      "gaussian_mixture"
    ),
    df = c(NA, NA, 5, NA, NA),
    al_tau = c(NA, NA, NA, 0.20, NA),
    mixture_weight = c(NA, NA, NA, NA, 0.65),
    mixture_mean_1 = c(NA, NA, NA, NA, -0.8),
    mixture_sd_1 = c(NA, NA, NA, NA, 0.7),
    mixture_mean_2 = c(NA, NA, NA, NA, 1.2),
    mixture_sd_2 = c(NA, NA, NA, NA, 1.1),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_postscore_formula_audit <- function(
  contract = app_joint_qdesn_postscore_read_contract(),
  mc_n = 150000L,
  seed = 17819100L
) {
  scenarios <- app_joint_qdesn_postscore_validation_scenarios()
  grid <- expand.grid(
    scenario_row = seq_len(nrow(scenarios)),
    tau = c(0.10, 0.50, 0.90),
    standardized_q = c(-1.4, -0.2, 0.8, 2.0),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  rows <- lapply(seq_len(nrow(grid)), function(ii) {
    spec <- grid[ii, , drop = FALSE]
    sc <- scenarios[spec$scenario_row[[1L]], , drop = FALSE]
    analytic <- app_joint_qdesn_postscore_expected_check_standardized(
      spec$standardized_q[[1L]], spec$tau[[1L]], sc
    )
    numerical <- app_joint_qdesn_postscore_expected_check_numerical(
      spec$standardized_q[[1L]], spec$tau[[1L]], sc
    )
    draws <- app_joint_qdesn_postscore_standardized_random(
      mc_n, sc, seed + ii
    )
    monte_carlo <- mean(app_joint_qdesn_postscore_check_loss(
      draws, spec$standardized_q[[1L]], spec$tau[[1L]]
    ))
    data.frame(
      distribution_family = sc$distribution_family[[1L]],
      tau = spec$tau[[1L]], standardized_q = spec$standardized_q[[1L]],
      analytic_expected_check_loss = analytic,
      numerical_expected_check_loss = numerical,
      monte_carlo_expected_check_loss = monte_carlo,
      analytic_numerical_abs_error = abs(analytic - numerical),
      analytic_monte_carlo_abs_error = abs(analytic - monte_carlo),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$analytic_status <- ifelse(
    out$analytic_numerical_abs_error <= contract$analytic_integration_tolerance,
    "pass", "fail"
  )
  out$monte_carlo_status <- ifelse(
    out$analytic_monte_carlo_abs_error <= contract$monte_carlo_tolerance,
    "pass", "fail"
  )
  out
}

app_joint_qdesn_postscore_oracle_minimum_audit <- function(
  contract = app_joint_qdesn_postscore_read_contract()
) {
  scenarios <- app_joint_qdesn_postscore_validation_scenarios()
  rows <- lapply(seq_len(nrow(scenarios)), function(ii) {
    sc <- scenarios[ii, , drop = FALSE]
    app_joint_qdesn_bind_rows(lapply(contract$tau, function(tau) {
      q_star <- app_joint_qvp_registry_standardized_quantile(tau, sc)
      offsets <- c(-0.25, -0.05, 0, 0.05, 0.25)
      scores <- vapply(q_star + offsets, function(q) {
        app_joint_qdesn_postscore_expected_check_standardized(q, tau, sc)
      }, numeric(1L))
      data.frame(
        distribution_family = sc$distribution_family[[1L]], tau = tau,
        true_standardized_quantile = q_star,
        oracle_expected_check_loss = scores[[3L]],
        minimum_grid_expected_check_loss = min(scores),
        oracle_regret_on_local_grid = scores[[3L]] - min(scores),
        status = if (which.min(scores) == 3L &&
          scores[[3L]] - min(scores) <= contract$regret_tolerance) "pass" else "fail",
        stringsAsFactors = FALSE
      )
    }))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_postscore_verify_phase178_sources <- function(
  dirs, contract = app_joint_qdesn_postscore_read_contract()
) {
  audit_check <- app_joint_exqdesn_verify_manifest(
    dirs$phase178_m0_audit, "phase178_m0_audit"
  )
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(
    dirs$phase178_m0_freeze, "phase178_post_m0_exact_ranking_freeze"
  )
  assessment <- app_read_csv(file.path(dirs$phase178_m0_audit, "assessment.csv"))
  case_summary <- app_read_csv(file.path(
    dirs$phase178_m0_audit, "case_replicate_summary.csv"
  ))
  worker_inventory <- app_read_csv(file.path(
    dirs$phase178_m0_audit, "worker_manifest_inventory.csv"
  ))
  if (any(audit_check$status != "pass") || any(freeze$verification$status != "pass") ||
      nrow(freeze$plan) != contract$expected_workers ||
      nrow(worker_inventory) != contract$expected_workers ||
      any(worker_inventory$status != "pass") ||
      nrow(case_summary) != contract$expected_candidate_replicates ||
      assessment$target_cells[[1L]] != contract$expected_target_cells ||
      assessment$failed_workers[[1L]] != 0L ||
      any(case_summary$implementation_status != "pass") ||
      any(case_summary$fit_contract_crossing_pairs != 0L) ||
      any(case_summary$forecast_contract_crossing_pairs != 0L)) {
    stop("Phase178 source-completeness gate failed.", call. = FALSE)
  }
  source_files <- c(
    phase178_audit_manifest = file.path(dirs$phase178_m0_audit, "artifact_manifest.csv"),
    phase178_freeze_manifest = file.path(dirs$phase178_m0_freeze, "artifact_manifest.csv"),
    phase178_fixture_manifest = file.path(dirs$phase178_fixtures, "artifact_manifest.csv")
  )
  source_manifest <- data.frame(
    source_id = names(source_files), source_path = normalizePath(source_files),
    size_bytes = as.numeric(file.info(source_files)$size),
    sha256 = vapply(source_files, app_sha256_file, character(1L)),
    status = "pass", stringsAsFactors = FALSE
  )
  list(
    audit_check = audit_check, freeze = freeze, assessment = assessment,
    case_summary = case_summary, worker_inventory = worker_inventory,
    source_manifest = source_manifest
  )
}

app_joint_qdesn_postscore_quadrature_rows <- function(contract) {
  data.frame(
    quantile_index = seq_along(contract$tau), tau = contract$tau,
    weight_on_twice_check_loss = contract$weights_qs,
    coefficient_on_check_loss = 2 * contract$weights_qs,
    cumulative_weight = cumsum(contract$weights_qs),
    renormalized = FALSE, stringsAsFactors = FALSE
  )
}

app_joint_qdesn_postscore_freeze_contract <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = NULL,
  force = FALSE
) {
  dirs <- app_joint_qdesn_postscore_dirs(cache_root)
  if (is.null(out_dir)) out_dir <- dirs$postscore_contract
  contract <- app_joint_qdesn_postscore_read_contract()
  source <- app_joint_qdesn_postscore_verify_phase178_sources(dirs, contract)
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "postscore_contract")
    if (all(check$status == "pass")) {
      return(list(out_dir = normalizePath(out_dir), reused = TRUE))
    }
  }
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  quadrature <- app_joint_qdesn_postscore_quadrature_rows(contract)
  coupling <- contract$table[contract$table$contract_section == "coupling", , drop = FALSE]
  decision <- contract$table[contract$table$contract_section %in% c(
    "decision", "diagnostics", "numeric", "source"
  ), , drop = FALSE]
  readiness <- data.frame(
    phase_id = "post_phase178_dgp_score_contract_freeze",
    gate_status = "pass",
    phase178_workers = nrow(source$freeze$plan),
    phase178_candidate_replicates = nrow(source$case_summary),
    tau_levels = length(contract$tau), quadrature_weight_sum = sum(contract$weights_qs),
    protected_scores_inspected = FALSE,
    legacy_phase179_launcher_authorized = FALSE,
    dense_grid_authorized = FALSE,
    recommendation = "run_current_grid_dgp_integrated_score_audit",
    stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Post-Phase178 DGP-integrated score contract", "",
    "This artifact freezes the seven-level score, posterior coupling, decision-margin,",
    "and source-completeness rules before protected DGP-integrated scores are computed.",
    "Phase178 remains historically ranked by its original oracle-MAE contract.",
    "The existing Phase179 launcher and the separate 19-level refit remain blocked."
  ), readme, useBytes = TRUE)
  paths <- c(
    score_contract = write(contract$table, "score_contract.csv"),
    quadrature_weight_contract = write(quadrature, "quadrature_weight_contract.csv"),
    posterior_draw_coupling_contract = write(coupling, "posterior_draw_coupling_contract.csv"),
    decision_margin_contract = write(decision, "decision_margin_contract.csv"),
    source_manifest_verification = write(source$source_manifest, "source_manifest_verification.csv"),
    phase178_audit_manifest_verification = write(
      source$audit_check, "phase178_audit_manifest_verification.csv"
    ),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior score contract.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish score contract.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "postscore_contract")
  if (any(check$status != "pass")) stop("Published score contract failed verification.", call. = FALSE)
  list(out_dir = final_dir, readiness = readiness, reused = FALSE)
}

app_joint_qdesn_postscore_forecast_context <- function(loaded, fixture) {
  forecast <- app_joint_exqdesn_phase173_forecast_fixture(
    loaded$artifacts, fixture$scenario_id, fixture
  )
  observed <- loaded$artifacts$observed[
    loaded$artifacts$observed$scenario_id == fixture$scenario_id, , drop = FALSE
  ]
  match_index <- match(forecast$row_meta$full_time_index, observed$full_time_index)
  if (anyNA(match_index) || anyDuplicated(forecast$row_meta$full_time_index) ||
      anyDuplicated(observed$full_time_index) ||
      any(forecast$row_meta$full_time_index !=
        forecast$row_meta$origin_full_time_index + forecast$row_meta$horizon) ||
      any(forecast$row_meta$full_time_index <=
        forecast$row_meta$fit_window_end_full_time_index) ||
      any(forecast$row_meta$origin_full_time_index <
        forecast$row_meta$fit_window_end_full_time_index)) {
    stop("Forecast/DGP alignment or previsibility gate failed.", call. = FALSE)
  }
  registry <- loaded$artifacts$frozen_registry
  sc <- registry[registry$scenario_id == fixture$scenario_id, , drop = FALSE]
  if (nrow(sc) != 1L) stop("Could not resolve one frozen DGP registry row.", call. = FALSE)
  mu <- as.numeric(observed$mu[match_index])
  sigma <- as.numeric(observed$sigma[match_index])
  if (any(!is.finite(c(forecast$y, forecast$Z, forecast$true_q, mu, sigma))) ||
      any(sigma <= 0)) {
    stop("Forecast context contains nonfinite values or nonpositive DGP scale.", call. = FALSE)
  }
  audit <- data.frame(
    scenario_id = fixture$scenario_id,
    forecast_rows = nrow(forecast$Z),
    unique_forecast_rows = length(unique(forecast$row_meta$full_time_index)),
    one_to_one_dgp_join = !anyNA(match_index),
    origin_horizon_alignment = all(
      forecast$row_meta$full_time_index ==
        forecast$row_meta$origin_full_time_index + forecast$row_meta$horizon
    ),
    strict_previsibility = all(
      forecast$row_meta$full_time_index >
        forecast$row_meta$fit_window_end_full_time_index
    ),
    origin_not_before_fit_end = all(
      forecast$row_meta$origin_full_time_index >=
        forecast$row_meta$fit_window_end_full_time_index
    ),
    finite_context = all(is.finite(c(forecast$y, forecast$Z, forecast$true_q, mu, sigma))),
    positive_scale = all(sigma > 0),
    status = "pass", stringsAsFactors = FALSE
  )
  list(forecast = forecast, mu = mu, sigma = sigma, sc = sc, audit = audit)
}

app_joint_qdesn_postscore_per_tau_indices <- function(
  selected, K, fit_structure, pairing_seed, chain_id
) {
  if (identical(fit_structure, "joint")) {
    return(rep(list(selected), K))
  }
  lapply(seq_len(K), function(kk) {
    seed <- as.integer((pairing_seed + 1009L * chain_id + 7919L * kk) %%
      .Machine$integer.max)
    app_joint_qdesn_postscore_with_seed(seed, sample(selected, length(selected)))
  })
}

app_joint_qdesn_postscore_chain_draws <- function(
  fit, forecast, y, mu, sigma, sc, tau, weights, fit_structure,
  chain_id, pairing_seed, draws_per_chain, chunk_size, oracle_score
) {
  K <- length(tau); p <- ncol(forecast$Z); n_time <- nrow(forecast$Z)
  n_keep <- nrow(fit$beta_draws)
  if (ncol(fit$beta_draws) != K * p || ncol(fit$alpha_draws) != K) {
    stop("Posterior draw dimensions do not match the forecast fixture.", call. = FALSE)
  }
  selected <- app_joint_qdesn_postscore_even_indices(n_keep, draws_per_chain)
  index_by_tau <- app_joint_qdesn_postscore_per_tau_indices(
    selected, K, fit_structure, pairing_seed, chain_id
  )
  X <- cbind(intercept = 1, forecast$Z)
  chunks <- split(seq_along(selected), ceiling(seq_along(selected) / chunk_size))
  output <- lapply(chunks, function(position) {
    B <- length(position)
    q_raw <- matrix(NA_real_, nrow = n_time * B, ncol = K)
    for (kk in seq_len(K)) {
      source_index <- index_by_tau[[kk]][position]
      beta_index <- ((kk - 1L) * p + 1L):(kk * p)
      theta <- cbind(
        fit$alpha_draws[source_index, kk],
        fit$beta_draws[source_index, beta_index, drop = FALSE]
      )
      q_raw[, kk] <- as.vector(X %*% t(theta))
    }
    contract <- app_joint_qdesn_postscore_contract_rows(q_raw, tau)
    q_contract <- contract$q_contract
    raw_crossing <- pmax(contract$raw_crossing, 0)
    contract_crossing <- pmax(contract$contract_crossing, 0)
    raw_pair_count <- matrix(
      rowSums(raw_crossing > 1e-12), nrow = n_time, ncol = B
    )
    contract_pair_count <- matrix(
      rowSums(contract_crossing > 1e-12), nrow = n_time, ncol = B
    )
    raw_max <- matrix(
      apply(raw_crossing, 1L, max), nrow = n_time, ncol = B
    )
    adjustment <- abs(q_contract - q_raw)
    row_mean_adjustment <- rowMeans(adjustment)
    row_max_adjustment <- apply(adjustment, 1L, max)
    sigma_matrix <- matrix(rep(sigma, times = B), nrow = n_time, ncol = B)
    dgp_raw <- dgp_contract <- realized_raw <- realized_contract <- numeric(B)
    for (kk in seq_len(K)) {
      raw_k <- matrix(q_raw[, kk], nrow = n_time, ncol = B)
      contract_k <- matrix(q_contract[, kk], nrow = n_time, ncol = B)
      mu_rep <- rep(mu, times = B); sigma_rep <- rep(sigma, times = B)
      y_rep <- rep(y, times = B)
      dgp_raw <- dgp_raw + weights[[kk]] * 2 * colMeans(matrix(
        app_joint_qdesn_postscore_expected_check(
          as.vector(raw_k), tau[[kk]], mu_rep, sigma_rep, sc
        ), nrow = n_time, ncol = B
      ))
      dgp_contract <- dgp_contract + weights[[kk]] * 2 * colMeans(matrix(
        app_joint_qdesn_postscore_expected_check(
          as.vector(contract_k), tau[[kk]], mu_rep, sigma_rep, sc
        ), nrow = n_time, ncol = B
      ))
      realized_raw <- realized_raw + weights[[kk]] * 2 * colMeans(matrix(
        app_joint_qdesn_postscore_check_loss(
          y_rep, as.vector(raw_k), tau[[kk]]
        ), nrow = n_time, ncol = B
      ))
      realized_contract <- realized_contract + weights[[kk]] * 2 * colMeans(matrix(
        app_joint_qdesn_postscore_check_loss(
          y_rep, as.vector(contract_k), tau[[kk]]
        ), nrow = n_time, ncol = B
      ))
    }
    data.frame(
      chain_id = chain_id,
      score_draw_index_within_chain = position,
      anchor_source_draw_index = selected[position],
      pairing_seed = pairing_seed,
      dgp_integrated_acrps_raw = dgp_raw,
      dgp_integrated_acrps = dgp_contract,
      expected_oracle_acrps = oracle_score,
      expected_regret = dgp_contract - oracle_score,
      realized_acrps_raw = realized_raw,
      realized_acrps = realized_contract,
      raw_crossing_pairs = colSums(raw_pair_count),
      contract_crossing_pairs = colSums(contract_pair_count),
      max_raw_crossing_magnitude = apply(raw_max, 2L, max),
      mean_abs_adjustment_over_sigma = colMeans(
        matrix(row_mean_adjustment, nrow = n_time, ncol = B) / sigma_matrix
      ),
      max_abs_adjustment = apply(
        matrix(row_max_adjustment, nrow = n_time, ncol = B), 2L, max
      ),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(output)
}

app_joint_qdesn_postscore_draw_diagnostics <- function(draws, contract) {
  split_score <- split(draws$dgp_integrated_acrps, draws$chain_id)
  lengths_score <- lengths(split_score)
  if (length(split_score) < 2L || length(unique(lengths_score)) != 1L) {
    stop("Score diagnostics require equal retained draws across at least two chains.", call. = FALSE)
  }
  matrix_score <- do.call(cbind, split_score)
  diag <- app_joint_exqdesn_modern_diagnostics(matrix_score)
  data.frame(
    posterior_score_mean = mean(draws$dgp_integrated_acrps),
    posterior_score_median = stats::median(draws$dgp_integrated_acrps),
    posterior_score_q025 = as.numeric(stats::quantile(
      draws$dgp_integrated_acrps, 0.025, names = FALSE, type = 8
    )),
    posterior_score_q975 = as.numeric(stats::quantile(
      draws$dgp_integrated_acrps, 0.975, names = FALSE, type = 8
    )),
    posterior_regret_mean = mean(draws$expected_regret),
    posterior_realized_acrps_mean = mean(draws$realized_acrps),
    score_rank_rhat = diag$rank_rhat,
    score_folded_rhat = diag$folded_rhat,
    score_bulk_ess = diag$bulk_ess,
    score_tail_ess = diag$tail_ess,
    score_mcse_mean = diag$mcse_mean,
    raw_crossing_pairs = sum(draws$raw_crossing_pairs),
    contract_crossing_pairs = sum(draws$contract_crossing_pairs),
    mean_abs_adjustment_over_sigma = mean(draws$mean_abs_adjustment_over_sigma),
    max_abs_adjustment = max(draws$max_abs_adjustment),
    score_functional_status = if (
      all(is.finite(c(diag$rank_rhat, diag$bulk_ess, diag$tail_ess))) &&
        diag$rank_rhat <= contract$score_rank_rhat_ceiling &&
        diag$bulk_ess >= contract$score_bulk_ess_floor &&
        diag$tail_ess >= contract$score_tail_ess_floor
    ) "pass" else "review",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_postscore_chain_allocation <- function(draws) {
  chains <- sort(unique(draws$chain_id))
  if (length(chains) < 4L) return(data.frame())
  groups <- list(
    first_half = chains[seq_len(length(chains) / 2L)],
    second_half = chains[length(chains) / 2L + seq_len(length(chains) / 2L)],
    odd = chains[seq(1L, length(chains), 2L)],
    even = chains[seq(2L, length(chains), 2L)]
  )
  app_joint_qdesn_bind_rows(lapply(names(groups), function(id) {
    x <- draws$dgp_integrated_acrps[draws$chain_id %in% groups[[id]]]
    data.frame(
      allocation_id = id, chains = paste(groups[[id]], collapse = ";"),
      n_draws = length(x), score_mean = mean(x), score_median = stats::median(x),
      score_q025 = as.numeric(stats::quantile(x, 0.025, names = FALSE, type = 8)),
      score_q975 = as.numeric(stats::quantile(x, 0.975, names = FALSE, type = 8)),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_postscore_case_meta <- function(jobs, context) {
  data.frame(
    mcmc_case_id = jobs$mcmc_case_id[[1L]],
    phase178_template_id = jobs$phase178_template_id[[1L]],
    case_id = jobs$case_id[[1L]],
    scenario_id = jobs$scenario_ids[[1L]],
    base_scenario_id = jobs$base_scenario_id[[1L]],
    dgp_replicate_id = jobs$dgp_replicate_id[[1L]],
    validation_partition = jobs$validation_partition[[1L]],
    fit_structure = jobs$fit_structure[[1L]],
    variant_id = jobs$variant_id[[1L]],
    candidate_role = jobs$candidate_role[[1L]],
    design_role = jobs$design_role[[1L]],
    distribution_family = context$sc$distribution_family[[1L]],
    dynamics_class = context$sc$dynamics_class[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_postscore_case <- function(jobs, freeze, contract) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  loaded <- app_joint_exqdesn_phase178_load_candidate_fixture(
    jobs[1L, , drop = FALSE], freeze$config$fixture_dir[[1L]]
  )
  fixture <- loaded$fixture
  context <- app_joint_qdesn_postscore_forecast_context(loaded, fixture)
  forecast <- context$forecast
  fits <- app_joint_exqdesn_phase178_load_m0_fits(jobs, fixture)
  meta <- app_joint_qdesn_postscore_case_meta(jobs, context)
  oracle <- app_joint_qdesn_postscore_score_matrix(
    forecast$true_q, forecast$y, context$mu, context$sigma, context$sc,
    fixture$tau, contract$weights_qs
  )
  primary <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(ii) {
    app_joint_qdesn_postscore_chain_draws(
      fit = fits[[ii]], forecast = forecast, y = forecast$y,
      mu = context$mu, sigma = context$sigma, sc = context$sc,
      tau = fixture$tau, weights = contract$weights_qs,
      fit_structure = jobs$fit_structure[[1L]], chain_id = jobs$chain_id[[ii]],
      pairing_seed = contract$primary_pairing_seed,
      draws_per_chain = contract$score_draws_per_chain,
      chunk_size = contract$chunk_size,
      oracle_score = oracle$dgp_integrated_acrps
    )
  }))
  if (any(!is.finite(as.matrix(primary[vapply(primary, is.numeric, logical(1L))]))) ||
      any(primary$contract_crossing_pairs != 0L) ||
      min(primary$expected_regret) < -contract$regret_tolerance) {
    stop(sprintf("Draw-level score contract failed for '%s'.", meta$mcmc_case_id), call. = FALSE)
  }
  primary <- cbind(meta[rep(1L, nrow(primary)), , drop = FALSE], primary)

  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  canonical_raw <- app_joint_qdesn_predict_fit(pooled, forecast$Z, fixture$tau)
  canonical_contract <- app_joint_qdesn_apply_monotone_contract(
    canonical_raw, fixture$tau
  )
  canonical_score <- app_joint_qdesn_postscore_score_matrix(
    canonical_contract$qhat_contract, forecast$y, context$mu, context$sigma,
    context$sc, fixture$tau, contract$weights_qs
  )
  canonical_tau <- data.frame(
    meta,
    quantile_index = seq_along(fixture$tau), tau = fixture$tau,
    expected_check_loss = canonical_score$expected_check_loss_by_tau,
    realized_check_loss = canonical_score$realized_check_loss_by_tau,
    stringsAsFactors = FALSE
  )
  canonical <- cbind(meta, data.frame(
    canonical_action_dgp_integrated_acrps = canonical_score$dgp_integrated_acrps,
    canonical_action_realized_acrps = canonical_score$realized_acrps,
    expected_oracle_acrps = oracle$dgp_integrated_acrps,
    canonical_action_expected_regret =
      canonical_score$dgp_integrated_acrps - oracle$dgp_integrated_acrps,
    canonical_raw_crossing_pairs = sum(
      canonical_contract$raw_crossing$n_crossing_pairs
    ),
    canonical_contract_crossing_pairs = sum(
      canonical_contract$contract_crossing$n_crossing_pairs
    ),
    canonical_mean_abs_adjustment = canonical_contract$mean_abs_adjustment,
    canonical_max_abs_adjustment = canonical_contract$max_abs_adjustment,
    stringsAsFactors = FALSE
  ))

  diagnostics <- cbind(
    meta, app_joint_qdesn_postscore_draw_diagnostics(primary, contract)
  )
  opportunities <- nrow(primary) * nrow(forecast$Z) * (length(fixture$tau) - 1L)
  diagnostics$raw_crossing_opportunities <- opportunities
  diagnostics$raw_crossing_rate <- diagnostics$raw_crossing_pairs / opportunities
  diagnostics$coherence_status <- if (
    diagnostics$contract_crossing_pairs != 0L
  ) "fail" else if (
    diagnostics$raw_crossing_rate > contract$raw_crossing_rate_review ||
      diagnostics$mean_abs_adjustment_over_sigma >
        contract$standardized_adjustment_review
  ) "review" else "pass"

  allocation <- app_joint_qdesn_postscore_chain_allocation(primary)
  if (nrow(allocation)) allocation <- cbind(
    meta[rep(1L, nrow(allocation)), , drop = FALSE], allocation
  )
  sensitivity <- data.frame()
  if (identical(jobs$fit_structure[[1L]], "independent")) {
    all_seeds <- c(contract$primary_pairing_seed, contract$sensitivity_pairing_seeds)
    sensitivity <- app_joint_qdesn_bind_rows(lapply(all_seeds, function(seed) {
      draws <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(ii) {
        app_joint_qdesn_postscore_chain_draws(
          fit = fits[[ii]], forecast = forecast, y = forecast$y,
          mu = context$mu, sigma = context$sigma, sc = context$sc,
          tau = fixture$tau, weights = contract$weights_qs,
          fit_structure = "independent", chain_id = jobs$chain_id[[ii]],
          pairing_seed = seed,
          draws_per_chain = contract$sensitivity_draws_per_chain,
          chunk_size = contract$chunk_size,
          oracle_score = oracle$dgp_integrated_acrps
        )
      }))
      data.frame(
        pairing_seed = seed, n_draws = nrow(draws),
        posterior_score_mean = mean(draws$dgp_integrated_acrps),
        posterior_score_median = stats::median(draws$dgp_integrated_acrps),
        posterior_score_q025 = as.numeric(stats::quantile(
          draws$dgp_integrated_acrps, 0.025, names = FALSE, type = 8
        )),
        posterior_score_q975 = as.numeric(stats::quantile(
          draws$dgp_integrated_acrps, 0.975, names = FALSE, type = 8
        )),
        raw_crossing_rate = sum(draws$raw_crossing_pairs) /
          (nrow(draws) * nrow(forecast$Z) * (length(fixture$tau) - 1L)),
        stringsAsFactors = FALSE
      )
    }))
    sensitivity <- cbind(
      meta[rep(1L, nrow(sensitivity)), , drop = FALSE], sensitivity
    )
  } else {
    sensitivity <- cbind(meta, data.frame(
      pairing_seed = NA_integer_, n_draws = nrow(primary),
      posterior_score_mean = mean(primary$dgp_integrated_acrps),
      posterior_score_median = stats::median(primary$dgp_integrated_acrps),
      posterior_score_q025 = as.numeric(stats::quantile(
        primary$dgp_integrated_acrps, 0.025, names = FALSE, type = 8
      )),
      posterior_score_q975 = as.numeric(stats::quantile(
        primary$dgp_integrated_acrps, 0.975, names = FALSE, type = 8
      )),
      raw_crossing_rate = diagnostics$raw_crossing_rate,
      stringsAsFactors = FALSE
    ))
  }

  source_rows <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(jobs)), function(ii) {
    worker_dir <- jobs$worker_output_dir[[ii]]
    check <- app_joint_exqdesn_verify_manifest(
      worker_dir, sprintf("postscore_source_worker_%04d", jobs$worker_id[[ii]])
    )
    data.frame(
      meta,
      worker_id = jobs$worker_id[[ii]], chain_id = jobs$chain_id[[ii]],
      worker_output_dir = normalizePath(worker_dir),
      worker_manifest_sha256 = app_sha256_file(file.path(worker_dir, "artifact_manifest.csv")),
      worker_manifest_entries = nrow(check),
      worker_manifest_status = if (all(check$status == "pass")) "pass" else "fail",
      retained_draws = nrow(fits[[ii]]$beta_draws),
      score_draws_selected = contract$score_draws_per_chain,
      stringsAsFactors = FALSE
    )
  }))
  previsibility <- cbind(meta, context$audit)
  list(
    draws = primary, diagnostics = diagnostics, canonical = canonical,
    canonical_tau = canonical_tau, allocation = allocation,
    pairing_sensitivity = sensitivity, source = source_rows,
    previsibility = previsibility
  )
}

app_joint_qdesn_postscore_write_gzip_csv <- function(x, path) {
  con <- gzfile(path, open = "wt", compression = 9)
  on.exit(close(con), add = TRUE)
  utils::write.csv(x, con, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

app_joint_qdesn_postscore_cell_dir <- function(work_dir, mcmc_case_id) {
  file.path(work_dir, "cells", mcmc_case_id)
}

app_joint_qdesn_postscore_cell_complete <- function(path) {
  manifest <- file.path(path, "artifact_manifest.csv")
  if (!file.exists(manifest)) return(FALSE)
  check <- tryCatch(
    app_joint_exqdesn_verify_manifest(path, "postscore_cell"),
    error = function(e) NULL
  )
  !is.null(check) && nrow(check) > 0L && all(check$status == "pass")
}

app_joint_qdesn_postscore_write_cell <- function(result, path) {
  final_dir <- normalizePath(path, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  paths <- c(
    posterior_draws = app_joint_qdesn_postscore_write_gzip_csv(
      result$draws, file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
    ),
    score_functional_diagnostics = write(
      result$diagnostics, "score_functional_diagnostics.csv"
    ),
    canonical_action = write(result$canonical, "canonical_action.csv"),
    canonical_action_by_tau = write(
      result$canonical_tau, "canonical_action_by_tau.csv"
    ),
    chain_allocation = write(result$allocation, "chain_allocation.csv"),
    pairing_sensitivity = write(result$pairing_sensitivity, "pairing_sensitivity.csv"),
    source_inventory = write(result$source, "source_inventory.csv"),
    previsibility = write(result$previsibility, "previsibility.csv")
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) unlink(final_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(dirname(final_dir))
  if (!file.rename(tmp, final_dir)) stop("Could not publish score cell checkpoint.", call. = FALSE)
  if (!app_joint_qdesn_postscore_cell_complete(final_dir)) {
    stop("Score cell checkpoint manifest failed.", call. = FALSE)
  }
  invisible(final_dir)
}

app_joint_qdesn_postscore_read_cell <- function(path) {
  if (!app_joint_qdesn_postscore_cell_complete(path)) {
    stop(sprintf("Incomplete score cell checkpoint: %s", path), call. = FALSE)
  }
  list(
    draws = app_read_csv(file.path(path, "posterior_dgp_integrated_acrps_draws.csv.gz")),
    diagnostics = app_read_csv(file.path(path, "score_functional_diagnostics.csv")),
    canonical = app_read_csv(file.path(path, "canonical_action.csv")),
    canonical_tau = app_read_csv(file.path(path, "canonical_action_by_tau.csv")),
    allocation = app_read_csv(file.path(path, "chain_allocation.csv")),
    pairing_sensitivity = app_read_csv(file.path(path, "pairing_sensitivity.csv")),
    source = app_read_csv(file.path(path, "source_inventory.csv")),
    previsibility = app_read_csv(file.path(path, "previsibility.csv"))
  )
}

app_joint_qdesn_postscore_pair_scalar_draws <- function(
  left, right, seed, left_label, right_label
) {
  chains <- intersect(sort(unique(left$chain_id)), sort(unique(right$chain_id)))
  if (length(chains) < 2L) stop("Score contrasts require at least two matched chains.", call. = FALSE)
  app_joint_qdesn_bind_rows(lapply(chains, function(chain_id) {
    a <- left[left$chain_id == chain_id, , drop = FALSE]
    b <- right[right$chain_id == chain_id, , drop = FALSE]
    n <- min(nrow(a), nrow(b))
    if (!n) stop("Score contrast has an empty matched chain.", call. = FALSE)
    a <- a[seq_len(n), , drop = FALSE]
    b_index <- app_joint_qdesn_postscore_with_seed(
      as.integer((seed + 1291L * chain_id) %% .Machine$integer.max),
      sample(seq_len(n), n)
    )
    b <- b[b_index, , drop = FALSE]
    data.frame(
      chain_id = chain_id, contrast_draw_index_within_chain = seq_len(n),
      contrast_seed = seed,
      left_label = left_label, right_label = right_label,
      left_score = a$dgp_integrated_acrps,
      right_score = b$dgp_integrated_acrps,
      score_delta = a$dgp_integrated_acrps - b$dgp_integrated_acrps,
      relative_score_delta =
        (a$dgp_integrated_acrps - b$dgp_integrated_acrps) /
          pmax(abs(b$dgp_integrated_acrps), .Machine$double.eps),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_postscore_contrast_summary_row <- function(
  draws, contract, meta
) {
  margin <- contract$practical_relative_margin
  cbind(meta, data.frame(
    n_draws = nrow(draws),
    score_delta_mean = mean(draws$score_delta),
    score_delta_median = stats::median(draws$score_delta),
    score_delta_q025 = as.numeric(stats::quantile(
      draws$score_delta, 0.025, names = FALSE, type = 8
    )),
    score_delta_q975 = as.numeric(stats::quantile(
      draws$score_delta, 0.975, names = FALSE, type = 8
    )),
    relative_score_delta_mean = mean(draws$relative_score_delta),
    probability_lower_score = mean(draws$score_delta < 0),
    probability_practical_superiority = mean(
      draws$relative_score_delta < -margin
    ),
    probability_noninferior = mean(draws$relative_score_delta < margin),
    stringsAsFactors = FALSE
  ))
}

app_joint_qdesn_postscore_candidate_parity_contrasts <- function(
  draws, contract
) {
  keys <- unique(draws[, c(
    "case_id", "base_scenario_id", "fit_structure", "dgp_replicate_id"
  ), drop = FALSE])
  detail <- list(); summary <- list(); cursor <- 1L
  for (ii in seq_len(nrow(keys))) {
    key <- keys[ii, , drop = FALSE]
    block <- draws[
      draws$case_id == key$case_id &
        draws$dgp_replicate_id == key$dgp_replicate_id, , drop = FALSE
    ]
    parity_id <- unique(block$phase178_template_id[block$variant_id == "parity"])
    if (length(parity_id) != 1L) stop("Candidate contrast cannot resolve parity.", call. = FALSE)
    parity <- block[block$phase178_template_id == parity_id, , drop = FALSE]
    candidate_ids <- setdiff(unique(block$phase178_template_id), parity_id)
    for (candidate_id in candidate_ids) {
      candidate <- block[block$phase178_template_id == candidate_id, , drop = FALSE]
      paired <- app_joint_qdesn_postscore_pair_scalar_draws(
        candidate, parity,
        contract$primary_pairing_seed + 50000L + cursor,
        candidate_id, parity_id
      )
      variant <- unique(candidate$variant_id)
      meta <- data.frame(
        case_id = key$case_id, base_scenario_id = key$base_scenario_id,
        fit_structure = key$fit_structure,
        dgp_replicate_id = key$dgp_replicate_id,
        candidate_template_id = candidate_id,
        candidate_variant_id = variant,
        parity_template_id = parity_id,
        stringsAsFactors = FALSE
      )
      detail[[cursor]] <- cbind(meta[rep(1L, nrow(paired)), , drop = FALSE], paired)
      summary[[cursor]] <- app_joint_qdesn_postscore_contrast_summary_row(
        paired, contract, meta
      )
      cursor <- cursor + 1L
    }
  }
  list(
    draws = app_joint_qdesn_bind_rows(detail),
    summary = app_joint_qdesn_bind_rows(summary)
  )
}

app_joint_qdesn_postscore_joint_independent_contrasts <- function(
  draws, contract
) {
  keys <- unique(draws[, c(
    "base_scenario_id", "dgp_replicate_id", "variant_id"
  ), drop = FALSE])
  detail <- list(); summary <- list(); cursor <- 1L
  for (ii in seq_len(nrow(keys))) {
    key <- keys[ii, , drop = FALSE]
    block <- draws[
      draws$base_scenario_id == key$base_scenario_id &
        draws$dgp_replicate_id == key$dgp_replicate_id &
        draws$variant_id == key$variant_id, , drop = FALSE
    ]
    joint_ids <- unique(block$mcmc_case_id[block$fit_structure == "joint"])
    independent_ids <- unique(block$mcmc_case_id[block$fit_structure == "independent"])
    if (length(joint_ids) != 1L || length(independent_ids) != 1L) next
    joint <- block[block$mcmc_case_id == joint_ids, , drop = FALSE]
    independent <- block[block$mcmc_case_id == independent_ids, , drop = FALSE]
    paired <- app_joint_qdesn_postscore_pair_scalar_draws(
      joint, independent,
      contract$primary_pairing_seed + 90000L + cursor,
      joint_ids, independent_ids
    )
    meta <- data.frame(
      base_scenario_id = key$base_scenario_id,
      dgp_replicate_id = key$dgp_replicate_id,
      variant_id = key$variant_id,
      joint_mcmc_case_id = joint_ids,
      independent_mcmc_case_id = independent_ids,
      stringsAsFactors = FALSE
    )
    detail[[cursor]] <- cbind(meta[rep(1L, nrow(paired)), , drop = FALSE], paired)
    summary[[cursor]] <- app_joint_qdesn_postscore_contrast_summary_row(
      paired, contract, meta
    )
    cursor <- cursor + 1L
  }
  list(
    draws = app_joint_qdesn_bind_rows(detail),
    summary = app_joint_qdesn_bind_rows(summary)
  )
}

app_joint_qdesn_postscore_pairing_stability <- function(sensitivity, contract) {
  groups <- split(
    sensitivity,
    interaction(sensitivity$mcmc_case_id, drop = TRUE, lex.order = TRUE)
  )
  app_joint_qdesn_bind_rows(lapply(groups, function(x) {
    metadata <- x[1L, c(
      "mcmc_case_id", "phase178_template_id", "case_id",
      "base_scenario_id", "dgp_replicate_id", "fit_structure", "variant_id"
    ), drop = FALSE]
    if (identical(x$fit_structure[[1L]], "joint")) {
      return(data.frame(
        metadata,
        coupling_variants = nrow(x),
        maximum_relative_mean_shift = 0,
        maximum_q025_shift = 0,
        maximum_q975_shift = 0,
        pairing_status = "not_applicable",
        stringsAsFactors = FALSE
      ))
    }
    score_columns <- c(
      "posterior_score_mean", "posterior_score_q025", "posterior_score_q975"
    )
    if (any(!is.finite(as.matrix(x[, score_columns, drop = FALSE])))) {
      stop("Nonfinite independent product-posterior sensitivity score")
    }
    reference_index <- which(
      !is.na(x$pairing_seed) & x$pairing_seed == contract$primary_pairing_seed
    )
    if (!length(reference_index)) reference_index <- 1L
    reference <- x[reference_index[[1L]], , drop = FALSE]
    spread <- max(abs(x$posterior_score_mean - reference$posterior_score_mean[[1L]])) /
      pmax(abs(reference$posterior_score_mean[[1L]]), .Machine$double.eps)
    data.frame(
      metadata,
      coupling_variants = nrow(x),
      maximum_relative_mean_shift = spread,
      maximum_q025_shift = max(x$posterior_score_q025) - min(x$posterior_score_q025),
      maximum_q975_shift = max(x$posterior_score_q975) - min(x$posterior_score_q975),
      pairing_status = if (spread <= contract$practical_relative_margin) "pass" else "review",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_postscore_template_aggregate <- function(
  summary, phase178_case_summary, pairing_stability
) {
  source <- phase178_case_summary[, c(
    "mcmc_case_id", "forecast_truth_mae", "fit_truth_mae",
    "forecast_check_loss_mean", "forecast_crps_grid_mean"
  ), drop = FALSE]
  summary <- merge(summary, source, by = "mcmc_case_id", all.x = TRUE, sort = FALSE)
  summary <- merge(
    summary,
    pairing_stability[, c("mcmc_case_id", "pairing_status", "maximum_relative_mean_shift"), drop = FALSE],
    by = "mcmc_case_id", all.x = TRUE, sort = FALSE
  )
  summary$pairing_status[is.na(summary$pairing_status)] <- "not_applicable"
  groups <- split(
    summary,
    interaction(summary$case_id, summary$phase178_template_id, drop = TRUE, lex.order = TRUE)
  )
  aggregate <- app_joint_qdesn_bind_rows(lapply(groups, function(x) {
    data.frame(
      case_id = x$case_id[[1L]], base_scenario_id = x$base_scenario_id[[1L]],
      fit_structure = x$fit_structure[[1L]],
      phase178_template_id = x$phase178_template_id[[1L]],
      variant_id = x$variant_id[[1L]], protected_replicates = nrow(x),
      median_posterior_score_mean = stats::median(x$posterior_score_mean),
      median_canonical_action_score = stats::median(
        x$canonical_action_dgp_integrated_acrps
      ),
      median_expected_regret = stats::median(x$posterior_regret_mean),
      median_forecast_truth_mae = stats::median(x$forecast_truth_mae),
      median_fit_truth_mae = stats::median(x$fit_truth_mae),
      median_realized_acrps = stats::median(x$forecast_crps_grid_mean),
      maximum_score_rank_rhat = max(x$score_rank_rhat),
      minimum_score_bulk_ess = min(x$score_bulk_ess),
      minimum_score_tail_ess = min(x$score_tail_ess),
      maximum_raw_crossing_rate = max(x$raw_crossing_rate),
      all_contract_crossings_zero = all(x$contract_crossing_pairs == 0L),
      score_functional_pass_fraction = mean(x$score_functional_status == "pass"),
      coherence_pass_fraction = mean(x$coherence_status == "pass"),
      pairing_pass_fraction = mean(x$pairing_status %in% c("pass", "not_applicable")),
      stringsAsFactors = FALSE
    )
  }))
  parity <- aggregate[aggregate$variant_id == "parity", c(
    "case_id", "median_posterior_score_mean", "median_forecast_truth_mae",
    "median_fit_truth_mae"
  ), drop = FALSE]
  names(parity)[-1L] <- paste0("parity_", names(parity)[-1L])
  aggregate <- merge(aggregate, parity, by = "case_id", all.x = TRUE, sort = FALSE)
  aggregate$score_ratio_vs_parity <- aggregate$median_posterior_score_mean /
    aggregate$parity_median_posterior_score_mean
  aggregate$forecast_truth_mae_ratio_vs_parity <- aggregate$median_forecast_truth_mae /
    aggregate$parity_median_forecast_truth_mae
  aggregate$fit_truth_mae_ratio_vs_parity <- aggregate$median_fit_truth_mae /
    aggregate$parity_median_fit_truth_mae
  list(case_replicate = summary, aggregate = aggregate)
}

app_joint_qdesn_postscore_decisions <- function(
  aggregate, candidate_contrast_summary, contract
) {
  contrast_groups <- split(
    candidate_contrast_summary,
    interaction(
      candidate_contrast_summary$case_id,
      candidate_contrast_summary$candidate_template_id,
      drop = TRUE, lex.order = TRUE
    )
  )
  contrast_aggregate <- app_joint_qdesn_bind_rows(lapply(contrast_groups, function(x) {
    data.frame(
      case_id = x$case_id[[1L]],
      candidate_template_id = x$candidate_template_id[[1L]],
      candidate_variant_id = x$candidate_variant_id[[1L]],
      protected_replicates = nrow(x),
      median_relative_score_delta = stats::median(x$relative_score_delta_mean),
      median_probability_lower_score = stats::median(x$probability_lower_score),
      median_probability_practical_superiority = stats::median(
        x$probability_practical_superiority
      ),
      median_probability_noninferior = stats::median(x$probability_noninferior),
      lower_score_replicate_fraction = mean(x$score_delta_mean < 0),
      practical_superiority_replicate_fraction = mean(
        x$relative_score_delta_mean < -contract$practical_relative_margin
      ),
      stringsAsFactors = FALSE
    )
  }))
  decisions <- app_joint_qdesn_bind_rows(lapply(split(aggregate, aggregate$case_id), function(x) {
    parity <- x[x$variant_id == "parity", , drop = FALSE]
    if (nrow(parity) != 1L) stop("Decision audit requires one parity template per case.", call. = FALSE)
    challengers <- x[x$variant_id != "parity", , drop = FALSE]
    challengers <- merge(
      challengers, contrast_aggregate,
      by.x = c("case_id", "phase178_template_id", "variant_id"),
      by.y = c("case_id", "candidate_template_id", "candidate_variant_id"),
      all.x = TRUE, sort = FALSE
    )
    if (nrow(challengers)) {
      challengers$hard_eligible <- with(challengers,
        all_contract_crossings_zero & protected_replicates.x == 3L)
      challengers$stability_eligible <- with(challengers,
        score_functional_pass_fraction == 1 & coherence_pass_fraction == 1 &
          pairing_pass_fraction == 1)
      challengers$oracle_safeguard <- with(challengers,
        forecast_truth_mae_ratio_vs_parity <= contract$oracle_recovery_ratio_ceiling &
          fit_truth_mae_ratio_vs_parity <= contract$oracle_recovery_ratio_ceiling)
      challengers$superiority_supported <- with(challengers,
        score_ratio_vs_parity <= 1 - contract$practical_relative_margin &
          practical_superiority_replicate_fraction >=
            contract$protected_replicate_direction_floor &
          median_probability_practical_superiority >=
            contract$posterior_probability_floor &
          hard_eligible & stability_eligible & oracle_safeguard)
      eligible <- challengers[challengers$superiority_supported, , drop = FALSE]
    } else eligible <- challengers
    winner <- if (nrow(eligible)) {
      eligible[order(eligible$median_posterior_score_mean, eligible$phase178_template_id), , drop = FALSE][1L, ]
    } else parity[1L, ]
    selected_is_parity <- winner$variant_id[[1L]] == "parity"
    all_source_pass <- all(x$all_contract_crossings_zero)
    any_functional_review <- any(x$score_functional_pass_fraction < 1)
    data.frame(
      case_id = parity$case_id[[1L]],
      base_scenario_id = parity$base_scenario_id[[1L]],
      fit_structure = parity$fit_structure[[1L]],
      selected_template_id = winner$phase178_template_id[[1L]],
      selected_variant_id = winner$variant_id[[1L]],
      parity_template_id = parity$phase178_template_id[[1L]],
      selected_is_parity = selected_is_parity,
      selected_median_dgp_integrated_acrps = winner$median_posterior_score_mean[[1L]],
      selected_score_ratio_vs_parity = winner$score_ratio_vs_parity[[1L]],
      original_phase178_metric = "forecast_truth_mae",
      article_action_metric = "dgp_integrated_acrps",
      gate_status = if (!all_source_pass) "fail" else if (any_functional_review) "review" else "pass",
      decision_reason = if (!all_source_pass) {
        "contract_or_source_failure"
      } else if (!selected_is_parity) {
        "challenger_passes_predeclared_practical_superiority_rule"
      } else if (any_functional_review) {
        "retain_parity_and_review_score_functional_stability"
      } else {
        "retain_parity_under_predeclared_near_tie_rule"
      },
      next_action = "freeze_phase179_selected_versus_parity_from_postscore_decision",
      stringsAsFactors = FALSE
    )
  }))
  list(contrast_aggregate = contrast_aggregate, decisions = decisions)
}

app_joint_qdesn_postscore_run_cells <- function(
  groups, freeze, contract, work_dir, cores = 8L
) {
  ids <- sort(names(groups))
  paths <- setNames(vapply(ids, function(id) {
    app_joint_qdesn_postscore_cell_dir(work_dir, id)
  }, character(1L)), ids)
  pending <- ids[!vapply(paths, app_joint_qdesn_postscore_cell_complete, logical(1L))]
  if (length(pending)) {
    app_ensure_dir(file.path(work_dir, "failures"))
    run_one <- function(id) {
      tryCatch({
        result <- app_joint_qdesn_postscore_case(groups[[id]], freeze, contract)
        app_joint_qdesn_postscore_write_cell(result, paths[[id]])
        data.frame(mcmc_case_id = id, status = "complete", message = "", stringsAsFactors = FALSE)
      }, error = function(e) {
        receipt <- data.frame(
          mcmc_case_id = id, status = "failed", message = conditionMessage(e),
          timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
          stringsAsFactors = FALSE
        )
        app_joint_qvp_write_csv(
          receipt, file.path(work_dir, "failures", paste0(id, ".csv"))
        )
        receipt
      })
    }
    result <- if (.Platform$OS.type != "windows" && cores > 1L) {
      parallel::mclapply(
        pending, run_one, mc.cores = min(as.integer(cores), length(pending)),
        mc.preschedule = FALSE
      )
    } else lapply(pending, run_one)
    status <- app_joint_qdesn_bind_rows(result)
    if (any(status$status != "complete")) {
      stop(sprintf(
        "Postscore cell failures: %s",
        paste(status$mcmc_case_id[status$status != "complete"], collapse = ", ")
      ), call. = FALSE)
    }
  }
  complete <- vapply(paths, app_joint_qdesn_postscore_cell_complete, logical(1L))
  if (!all(complete)) stop("Postscore cell checkpoint set is incomplete.", call. = FALSE)
  paths
}

app_joint_qdesn_postscore_collect_cells <- function(paths) {
  results <- lapply(paths, app_joint_qdesn_postscore_read_cell)
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  list(
    draws = bind("draws"), diagnostics = bind("diagnostics"),
    canonical = bind("canonical"), canonical_tau = bind("canonical_tau"),
    allocation = bind("allocation"), pairing_sensitivity = bind("pairing_sensitivity"),
    source = bind("source"), previsibility = bind("previsibility")
  )
}

app_joint_qdesn_postscore_replicate_stability <- function(case_replicate) {
  groups <- split(
    case_replicate,
    interaction(
      case_replicate$case_id, case_replicate$phase178_template_id,
      drop = TRUE, lex.order = TRUE
    )
  )
  app_joint_qdesn_bind_rows(lapply(groups, function(x) {
    data.frame(
      case_id = x$case_id[[1L]], base_scenario_id = x$base_scenario_id[[1L]],
      fit_structure = x$fit_structure[[1L]],
      phase178_template_id = x$phase178_template_id[[1L]],
      variant_id = x$variant_id[[1L]], replicates = nrow(x),
      score_mean_across_replicates = mean(x$posterior_score_mean),
      score_sd_across_replicates = stats::sd(x$posterior_score_mean),
      score_min = min(x$posterior_score_mean), score_max = max(x$posterior_score_mean),
      canonical_score_mean = mean(x$canonical_action_dgp_integrated_acrps),
      realized_acrps_mean = mean(x$forecast_crps_grid_mean),
      forecast_truth_mae_mean = mean(x$forecast_truth_mae),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_postscore_prepare_phase179_templates <- function(
  decisions, freeze
) {
  selected <- freeze$controls[
    match(decisions$selected_template_id, freeze$controls$phase178_template_id),
    , drop = FALSE
  ]
  parity <- freeze$controls[
    match(decisions$parity_template_id, freeze$controls$phase178_template_id),
    , drop = FALSE
  ]
  if (anyNA(selected$phase178_template_id) || anyNA(parity$phase178_template_id)) {
    stop("Postscore decision could not resolve frozen Phase178 templates.", call. = FALSE)
  }
  selected$postscore_confirmation_role <- ifelse(
    decisions$selected_is_parity, "parity", "selected_challenger"
  )
  parity$postscore_confirmation_role <- "parity"
  out <- app_joint_qdesn_bind_rows(list(selected, parity))
  out[!duplicated(out$phase178_template_id), , drop = FALSE]
}

app_joint_qdesn_postscore_run_audit <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  contract_dir = NULL,
  out_dir = NULL,
  work_dir = NULL,
  cores = 8L,
  force = FALSE
) {
  dirs <- app_joint_qdesn_postscore_dirs(cache_root)
  if (is.null(contract_dir)) contract_dir <- dirs$postscore_contract
  if (is.null(out_dir)) out_dir <- dirs$postscore_audit
  if (is.null(work_dir)) work_dir <- dirs$postscore_work
  contract_check <- app_joint_exqdesn_verify_manifest(contract_dir, "postscore_contract")
  if (any(contract_check$status != "pass")) stop("Frozen score contract failed verification.", call. = FALSE)
  contract <- app_joint_qdesn_postscore_read_contract()
  frozen_contract <- app_read_csv(file.path(contract_dir, "score_contract.csv"))
  if (!identical(contract$table, frozen_contract)) {
    stop("Tracked and frozen score contracts differ.", call. = FALSE)
  }
  source <- app_joint_qdesn_postscore_verify_phase178_sources(dirs, contract)
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "postscore_audit")
    if (all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        assessment = app_read_csv(file.path(out_dir, "assessment.csv")),
        reused = TRUE
      ))
    }
  }
  groups <- split(source$freeze$plan, source$freeze$plan$mcmc_case_id)
  if (length(groups) != contract$expected_candidate_replicates) {
    stop("Phase178 score group count differs from the frozen contract.", call. = FALSE)
  }
  paths <- app_joint_qdesn_postscore_run_cells(
    groups, source$freeze, contract, work_dir, cores
  )
  result <- app_joint_qdesn_postscore_collect_cells(paths)
  if (nrow(result$diagnostics) != contract$expected_candidate_replicates ||
      nrow(result$canonical) != contract$expected_candidate_replicates ||
      any(result$diagnostics$contract_crossing_pairs != 0L) ||
      any(result$previsibility$status != "pass") ||
      any(result$source$worker_manifest_status != "pass")) {
    stop("Collected postscore evidence failed source or implementation gates.", call. = FALSE)
  }

  formula_audit <- app_joint_qdesn_postscore_formula_audit(contract)
  oracle_audit <- app_joint_qdesn_postscore_oracle_minimum_audit(contract)
  if (any(formula_audit$analytic_status != "pass") ||
      any(formula_audit$monte_carlo_status != "pass") ||
      any(oracle_audit$status != "pass")) {
    stop("DGP expected-loss formula validation failed.", call. = FALSE)
  }
  pairing_stability <- app_joint_qdesn_postscore_pairing_stability(
    result$pairing_sensitivity, contract
  )
  score_summary <- merge(
    result$diagnostics, result$canonical,
    by = c(
      "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
      "base_scenario_id", "dgp_replicate_id", "validation_partition",
      "fit_structure", "variant_id", "candidate_role", "design_role",
      "distribution_family", "dynamics_class"
    ), all = FALSE, sort = FALSE
  )
  template <- app_joint_qdesn_postscore_template_aggregate(
    score_summary, source$case_summary, pairing_stability
  )
  compatibility <- template$case_replicate
  compatibility$realized_acrps_abs_difference <- abs(
    compatibility$canonical_action_realized_acrps -
      compatibility$forecast_crps_grid_mean
  )
  compatibility$compatibility_status <- ifelse(
    compatibility$realized_acrps_abs_difference <= 1e-10, "pass", "fail"
  )
  if (any(compatibility$compatibility_status != "pass")) {
    stop("Canonical realized aCRPS does not reproduce the frozen Phase178 score.", call. = FALSE)
  }
  candidate_contrast <- app_joint_qdesn_postscore_candidate_parity_contrasts(
    result$draws, contract
  )
  joint_contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(
    result$draws, contract
  )
  decision <- app_joint_qdesn_postscore_decisions(
    template$aggregate, candidate_contrast$summary, contract
  )
  phase179_templates <- app_joint_qdesn_postscore_prepare_phase179_templates(
    decision$decisions, source$freeze
  )
  replicate_stability <- app_joint_qdesn_postscore_replicate_stability(
    template$case_replicate
  )
  cell_inventory <- data.frame(
    mcmc_case_id = names(paths), cell_dir = normalizePath(paths),
    cell_manifest_sha256 = vapply(
      paths, function(path) app_sha256_file(file.path(path, "artifact_manifest.csv")),
      character(1L)
    ),
    status = "pass", stringsAsFactors = FALSE
  )
  source_completeness <- data.frame(
    scope = c(
      "phase178_targeted_candidate_replicates",
      "balanced_article_scenario_model_rows"
    ),
    expected_rows = c(contract$expected_candidate_replicates, 32L),
    source_complete_rows = c(nrow(result$diagnostics), 0L),
    status = c("complete", "source_incomplete"),
    rationale = c(
      "All targeted Phase178 candidate-replicate posterior checkpoints are reconstructable.",
      "Phase178 is targeted recovery evidence and cannot supply a complete 32-row draw-level article packet."
    ), stringsAsFactors = FALSE
  )
  original_decision <- app_read_csv(file.path(
    dirs$phase178_m0_audit, "selection_decision.csv"
  ))
  original_decision$ranking_authority <- "phase178_original_forecast_oracle_mae"

  hard_fail <- any(decision$decisions$gate_status == "fail") ||
    any(compatibility$compatibility_status == "fail") ||
    any(result$diagnostics$contract_crossing_pairs != 0L)
  review <- any(decision$decisions$gate_status == "review") ||
    any(pairing_stability$pairing_status == "review") ||
    any(result$diagnostics$coherence_status == "review")
  assessment <- data.frame(
    phase_id = "post_phase178_current_grid_dgp_integrated_score_audit",
    gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    phase178_workers = contract$expected_workers,
    source_complete_candidate_replicates = nrow(result$diagnostics),
    target_cells = nrow(decision$decisions),
    selected_nonparity = sum(!decision$decisions$selected_is_parity),
    score_functional_review_rows = sum(
      result$diagnostics$score_functional_status == "review"
    ),
    coherence_review_rows = sum(result$diagnostics$coherence_status == "review"),
    contract_crossing_pairs = sum(result$diagnostics$contract_crossing_pairs),
    original_phase178_ranking_preserved = TRUE,
    legacy_phase179_launcher_authorized = FALSE,
    dense_grid_authorized = FALSE,
    recommendation = if (hard_fail) {
      "repair_postscore_implementation_before_phase179"
    } else {
      "freeze_phase179_from_postscore_selected_templates_after_review"
    },
    stringsAsFactors = FALSE
  )

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Post-Phase178 current-grid DGP-integrated score audit", "",
    "This audit rescored only the 45 source-complete targeted Phase178 candidate-replicates.",
    "The original Phase178 oracle-MAE ranking is preserved in a separate table.",
    "Primary metric: known-DGP expected finite-grid quantile score (`dgp_integrated_acrps`).",
    "Posterior mean and equal-tailed 95% credible interval describe score uncertainty.",
    "No scalar predictive density is inferred from the joint AL/exAL composite likelihood.",
    "The 32-row article packet and the later 19-level refit remain source-incomplete/deferred."
  ), readme, useBytes = TRUE)
  paths_out <- c(
    source_retention_inventory = write(result$source, "source_retention_inventory.csv"),
    source_manifest_verification = write(source$source_manifest, "source_manifest_verification.csv"),
    cell_checkpoint_manifest = write(cell_inventory, "cell_checkpoint_manifest.csv"),
    score_contract = write(contract$table, "score_contract.csv"),
    quadrature_weight_contract = write(
      app_joint_qdesn_postscore_quadrature_rows(contract), "quadrature_weight_contract.csv"
    ),
    posterior_draw_coupling_contract = write(
      contract$table[contract$table$contract_section == "coupling", , drop = FALSE],
      "posterior_draw_coupling_contract.csv"
    ),
    dgp_family_parameterization_audit = write(
      formula_audit, "dgp_family_parameterization_audit.csv"
    ),
    oracle_minimum_audit = write(oracle_audit, "oracle_minimum_audit.csv"),
    forecast_previsibility_audit = write(
      result$previsibility, "forecast_previsibility_audit.csv"
    ),
    posterior_dgp_integrated_acrps_draws = app_joint_qdesn_postscore_write_gzip_csv(
      result$draws, file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
    ),
    posterior_dgp_integrated_acrps_summary = write(
      template$case_replicate, "posterior_dgp_integrated_acrps_summary.csv"
    ),
    canonical_action_dgp_integrated_acrps = write(
      result$canonical, "canonical_action_dgp_integrated_acrps.csv"
    ),
    canonical_action_by_tau = write(
      result$canonical_tau, "canonical_action_by_tau.csv"
    ),
    candidate_parity_contrast_draws = app_joint_qdesn_postscore_write_gzip_csv(
      candidate_contrast$draws, file.path(tmp, "candidate_parity_contrast_draws.csv.gz")
    ),
    candidate_parity_contrast_summary = write(
      candidate_contrast$summary, "candidate_parity_contrast_summary.csv"
    ),
    joint_independent_score_contrast_draws = app_joint_qdesn_postscore_write_gzip_csv(
      joint_contrast$draws, file.path(tmp, "joint_independent_score_contrast_draws.csv.gz")
    ),
    joint_independent_score_contrast_summary = write(
      joint_contrast$summary, "joint_independent_score_contrast_summary.csv"
    ),
    expected_oracle_score_summary = write(
      result$canonical[, c(
        "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
        "base_scenario_id", "dgp_replicate_id", "expected_oracle_acrps"
      ), drop = FALSE], "expected_oracle_score_summary.csv"
    ),
    expected_regret_summary = write(
      template$case_replicate[, c(
        "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
        "base_scenario_id", "dgp_replicate_id", "posterior_regret_mean",
        "canonical_action_expected_regret"
      ), drop = FALSE], "expected_regret_summary.csv"
    ),
    realized_expected_score_comparison = write(
      compatibility, "realized_expected_score_comparison.csv"
    ),
    raw_contract_crossing_summary = write(
      result$diagnostics[, c(
        "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
        "base_scenario_id", "dgp_replicate_id", "fit_structure", "variant_id",
        "raw_crossing_pairs", "raw_crossing_opportunities", "raw_crossing_rate",
        "contract_crossing_pairs", "mean_abs_adjustment_over_sigma",
        "max_abs_adjustment", "coherence_status"
      ), drop = FALSE], "raw_contract_crossing_summary.csv"
    ),
    pairing_seed_sensitivity = write(
      result$pairing_sensitivity, "pairing_seed_sensitivity.csv"
    ),
    pairing_stability = write(pairing_stability, "pairing_stability.csv"),
    chain_allocation_sensitivity = write(
      result$allocation, "chain_allocation_sensitivity.csv"
    ),
    score_functional_mcmc_diagnostics = write(
      result$diagnostics, "score_functional_mcmc_diagnostics.csv"
    ),
    replicate_stability_summary = write(
      replicate_stability, "replicate_stability_summary.csv"
    ),
    candidate_metric_aggregate = write(
      template$aggregate, "candidate_metric_aggregate.csv"
    ),
    candidate_contrast_aggregate = write(
      decision$contrast_aggregate, "candidate_contrast_aggregate.csv"
    ),
    phase178_original_decision = write(
      original_decision, "phase178_original_decision.csv"
    ),
    decision_audit = write(decision$decisions, "decision_audit.csv"),
    phase179_selected_templates = write(
      phase179_templates, "phase179_selected_templates.csv"
    ),
    source_completeness_summary = write(
      source_completeness, "source_completeness_summary.csv"
    ),
    assessment = write(assessment, "assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths_out, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior postscore audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish postscore audit.", call. = FALSE)
  final_check <- app_joint_exqdesn_verify_manifest(final_dir, "postscore_audit")
  if (any(final_check$status != "pass")) stop("Postscore audit manifest failed.", call. = FALSE)
  list(
    out_dir = final_dir, assessment = assessment,
    decisions = decision$decisions, reused = FALSE
  )
}
