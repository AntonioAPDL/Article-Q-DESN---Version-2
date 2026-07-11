#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(yaml)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  idx <- match(flag, args)
  if (is.na(idx) || idx == length(args)) return(default)
  args[[idx + 1L]]
}

find_repo_root <- function() {
  here <- normalizePath(getwd(), mustWork = TRUE)
  candidates <- c(
    here,
    normalizePath(file.path(here, ".."), mustWork = FALSE),
    normalizePath(file.path(here, "..", ".."), mustWork = FALSE),
    normalizePath(file.path(here, "..", "..", ".."), mustWork = FALSE)
  )
  for (cand in candidates) {
    if (file.exists(file.path(cand, "application", "config", "pricefm_data_pipeline.yaml"))) {
      return(cand)
    }
  }
  stop("Could not locate Article-Q-DESN repo root. Run from the repo or a child directory.", call. = FALSE)
}

repo_root <- find_repo_root()
cfg_path <- get_arg("--smoke-config", "application/config/pricefm_desn_model_smoke.yaml")
force <- tolower(get_arg("--force", "false")) %in% c("1", "true", "yes", "y")

repo_path <- function(path) {
  if (grepl("^/", path)) path else file.path(repo_root, path)
}

cfg <- yaml::read_yaml(repo_path(cfg_path))$pricefm_desn_smoke
out_dir <- repo_path(cfg$run$output_dir)
adapter_dir <- repo_path(cfg$adapter$output_dir)
if (dir.exists(out_dir) && !force) {
  stop(out_dir, " exists; rerun with --force true", call. = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(file.path(adapter_dir, "adapter_manifest.json"))) {
  cmd <- c(
    repo_path("application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"),
    "--smoke-config", repo_path(cfg_path),
    "--force", "true"
  )
  status <- system2(repo_path("application/data_local/pricefm/venv/bin/python"), cmd)
  if (!identical(status, 0L)) stop("Adapter build failed.", call. = FALSE)
}

pkg_path <- cfg$package_path
if (!dir.exists(pkg_path)) stop("Package path does not exist: ", pkg_path, call. = FALSE)
suppressPackageStartupMessages(pkgload::load_all(pkg_path, quiet = TRUE))

read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
read_rows <- function(split) utils::read.csv(file.path(adapter_dir, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE)

X_train <- read_matrix(file.path(adapter_dir, "X_train.csv"))
y_train <- read_vector(file.path(adapter_dir, "y_train.csv"))
X_val <- read_matrix(file.path(adapter_dir, "X_val.csv"))
X_test <- read_matrix(file.path(adapter_dir, "X_test.csv"))
rows_train <- read_rows("train")
rows_val <- read_rows("val")
rows_test <- read_rows("test")
quantiles <- as.numeric(unlist(cfg$quantiles))
horizons <- as.integer(unlist(cfg$horizons))

write_json <- function(path, x) {
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE), file = path)
  cat("\n", file = path, append = TRUE)
}

package_sha <- tryCatch(exdqlm:::.qdesn_vb_package_sha(), error = function(e) NA_character_)
repo_state <- list(
  article_repo = repo_root,
  article_head = system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE),
  package_path = pkg_path,
  package_head = system2("git", c("-C", pkg_path, "rev-parse", "HEAD"), stdout = TRUE),
  package_sha = package_sha,
  config = cfg_path,
  adapter_dir = adapter_dir
)
write_json(file.path(out_dir, "repo_state.json"), repo_state)

prediction_rows <- list()
method_rows <- list()
exact_rows <- list()
warm_rows <- list()
trace_rows <- list()
parameter_rows <- list()

append_predictions <- function(method_id, split, rows, pred_mat) {
  pred_mat <- as.matrix(pred_mat)
  if (nrow(pred_mat) != nrow(rows) || ncol(pred_mat) != length(quantiles)) {
    stop("Prediction shape mismatch for ", method_id, " / ", split, call. = FALSE)
  }
  out <- do.call(rbind, lapply(seq_along(quantiles), function(j) {
    data.frame(
      method_id = method_id,
      split = split,
      origin_id = rows$origin_id,
      horizon = rows$horizon,
      tau = quantiles[[j]],
      pred_scaled = as.numeric(pred_mat[, j]),
      stringsAsFactors = FALSE
    )
  }))
  prediction_rows[[length(prediction_rows) + 1L]] <<- out
}

append_method <- function(...) {
  method_rows[[length(method_rows) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
}

append_warm <- function(...) {
  warm_rows[[length(warm_rows) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
}

append_trace <- function(...) {
  trace_rows[[length(trace_rows) + 1L]] <<- data.frame(...)
}

append_parameter <- function(...) {
  parameter_rows[[length(parameter_rows) + 1L]] <<- data.frame(...)
}

rhs_cfg <- cfg$rhs_ns
rhs <- list(
  tau0 = as.numeric(rhs_cfg$tau0 %||% 0.01),
  shrink_intercept = isTRUE(rhs_cfg$shrink_intercept %||% FALSE),
  freeze_tau_iters = as.integer(rhs_cfg$freeze_tau_iters %||% 0L),
  freeze_tau_warmup_iters = as.integer(rhs_cfg$freeze_tau_warmup_iters %||% 0L)
)

normal_predict_quantiles <- function(fit, X_new, seed) {
  pred <- exdqlm::normal_desn_posterior_predict(
    fit,
    X_new = X_new,
    nd = as.integer(cfg$run$nd_predictive %||% 400L),
    seed = as.integer(seed)
  )
  q <- apply(pred$yrep, 1L, stats::quantile, probs = quantiles, names = FALSE, type = 7)
  if (length(quantiles) == 1L) {
    matrix(as.numeric(q), ncol = 1L)
  } else {
    t(q)
  }
}

warm_cfg <- cfg$warm_start %||% list(enabled = FALSE)
warm_enabled <- isTRUE(warm_cfg$enabled)
warm_fallback_to_cold <- isTRUE(warm_cfg$fallback_to_cold %||% FALSE)
warm_record_diagnostics <- if (is.null(warm_cfg$record_diagnostics)) TRUE else isTRUE(warm_cfg$record_diagnostics)
training_cfg <- cfg$training %||% list()

as_config_vec <- function(x, default = character()) {
  if (is.null(x)) return(default)
  as.character(unlist(x, use.names = FALSE))
}

tau_key <- function(tau) sprintf("%.12g", as.numeric(tau))

horizon_group_label <- function(horizon) {
  horizon <- as.integer(horizon)
  start <- ((horizon - 1L) %/% 24L) * 24L + 1L
  end <- min(start + 23L, max(horizons))
  paste0(start, "-", end)
}

infer_integer_scale <- function(multiplier, max_scale = 20L) {
  multiplier <- as.numeric(multiplier)[1L]
  if (!is.finite(multiplier) || multiplier <= 0) {
    stop("horizon_weighting multiplier must be positive and finite.", call. = FALSE)
  }
  for (scale in seq_len(as.integer(max_scale))) {
    value <- multiplier * scale
    if (isTRUE(all.equal(value, round(value), tolerance = 1.0e-8))) {
      return(as.integer(scale))
    }
  }
  stop("horizon_weighting multiplier cannot be represented as integer frequencies within max_scale.", call. = FALSE)
}

parse_focus_mask <- function(rows, weighting_cfg) {
  focus <- weighting_cfg$focus %||% weighting_cfg$horizon_focus %||% NULL
  if (is.null(focus)) {
    focus <- weighting_cfg$horizon_group %||% NULL
  }
  if (is.null(focus)) {
    stop("enabled horizon_weighting requires focus/horizon_focus.", call. = FALSE)
  }
  row_horizon <- as.integer(rows$horizon)
  scope <- as.character(weighting_cfg$scope %||% "horizon_group")[1L]
  if (identical(scope, "horizon")) {
    focus_h <- as.integer(unlist(focus, use.names = FALSE))
    return(row_horizon %in% focus_h)
  }
  focus_group <- as.character(unlist(focus, use.names = FALSE))
  row_group <- vapply(row_horizon, horizon_group_label, character(1L))
  row_group %in% focus_group
}

build_horizon_weighting <- function(rows, weighting_cfg) {
  default <- list(
    enabled = FALSE,
    mode = "none",
    apply_to = character(),
    focus = "",
    multiplier = 1,
    base_frequency = 1L,
    focused_frequency = 1L,
    n_train_original = nrow(rows),
    n_train_weighted = nrow(rows),
    frequency = rep.int(1L, nrow(rows)),
    summary = data.frame()
  )
  if (is.null(weighting_cfg) || !isTRUE(weighting_cfg$enabled %||% FALSE)) {
    default$summary <- data.frame(
      enabled = FALSE,
      mode = "none",
      apply_to = "",
      focus = "",
      multiplier = 1,
      base_frequency = 1L,
      focused_frequency = 1L,
      n_train_original = nrow(rows),
      n_train_weighted = nrow(rows),
      n_focus_rows = 0L,
      stringsAsFactors = FALSE
    )
    return(default)
  }
  mode <- as.character(weighting_cfg$mode %||% "integer_frequency_replication")[1L]
  if (!identical(mode, "integer_frequency_replication")) {
    stop("Unsupported horizon_weighting mode: ", mode, call. = FALSE)
  }
  multiplier <- as.numeric(weighting_cfg$multiplier %||% 1)[1L]
  scale <- as.integer(weighting_cfg$integer_scale %||% infer_integer_scale(multiplier))
  base_frequency <- as.integer(weighting_cfg$base_frequency %||% scale)
  focused_frequency <- as.integer(round(multiplier * base_frequency))
  if (base_frequency < 1L || focused_frequency < 1L) {
    stop("horizon_weighting frequencies must be positive integers.", call. = FALSE)
  }
  focus_mask <- parse_focus_mask(rows, weighting_cfg)
  if (!any(focus_mask)) {
    stop("horizon_weighting focus matched zero training rows.", call. = FALSE)
  }
  frequency <- rep.int(base_frequency, nrow(rows))
  frequency[focus_mask] <- focused_frequency
  max_factor <- as.numeric(weighting_cfg$max_expansion_factor %||% 8)
  expansion_factor <- sum(frequency) / nrow(rows)
  if (is.finite(max_factor) && expansion_factor > max_factor) {
    stop(
      "horizon_weighting expansion factor ", round(expansion_factor, 4),
      " exceeds max_expansion_factor ", max_factor,
      call. = FALSE
    )
  }
  focus_text <- paste(as.character(unlist(weighting_cfg$focus %||% weighting_cfg$horizon_focus)), collapse = ",")
  apply_to <- as_config_vec(weighting_cfg$apply_to %||% "qdesn")
  summary <- data.frame(
    enabled = TRUE,
    mode = mode,
    apply_to = paste(apply_to, collapse = ","),
    focus = focus_text,
    multiplier = multiplier,
    base_frequency = base_frequency,
    focused_frequency = focused_frequency,
    n_train_original = nrow(rows),
    n_train_weighted = as.integer(sum(frequency)),
    n_focus_rows = as.integer(sum(focus_mask)),
    expansion_factor = as.numeric(expansion_factor),
    stringsAsFactors = FALSE
  )
  list(
    enabled = TRUE,
    mode = mode,
    apply_to = apply_to,
    focus = focus_text,
    multiplier = multiplier,
    base_frequency = base_frequency,
    focused_frequency = focused_frequency,
    n_train_original = nrow(rows),
    n_train_weighted = as.integer(sum(frequency)),
    frequency = frequency,
    summary = summary
  )
}

horizon_weighting <- build_horizon_weighting(rows_train, training_cfg$horizon_weighting %||% NULL)
qdesn_weighting_enabled <- isTRUE(horizon_weighting$enabled) && "qdesn" %in% horizon_weighting$apply_to
if (qdesn_weighting_enabled) {
  train_index_qdesn <- rep(seq_len(nrow(X_train)), times = horizon_weighting$frequency)
  X_q_train <- X_train[train_index_qdesn, , drop = FALSE]
  y_q_train <- y_train[train_index_qdesn]
} else {
  X_q_train <- X_train
  y_q_train <- y_train
}
qdesn_likelihoods <- unique(tolower(as_config_vec(cfg$qdesn_vb$likelihoods %||% c("al", "exal"))))
bad_likelihoods <- setdiff(qdesn_likelihoods, c("al", "exal"))
if (length(bad_likelihoods)) {
  stop("Unsupported qdesn_vb likelihood(s): ", paste(bad_likelihoods, collapse = ", "), call. = FALSE)
}
if (!length(qdesn_likelihoods)) {
  stop("qdesn_vb likelihoods must be nonempty.", call. = FALSE)
}

safe_sigma_from_fit <- function(fit) {
  val <- NA_real_
  if (!is.null(fit$qsiggam$sigma_mean)) {
    val <- as.numeric(fit$qsiggam$sigma_mean)[1L]
  } else if (!is.null(fit$misc$sigma_trace)) {
    st <- as.numeric(fit$misc$sigma_trace)
    st <- st[is.finite(st) & st > 0]
    if (length(st)) val <- utils::tail(st, 1L)
  } else if (!is.null(fit$omega2$mean) && is.finite(as.numeric(fit$omega2$mean)[1L])) {
    val <- sqrt(max(as.numeric(fit$omega2$mean)[1L], .Machine$double.eps))
  } else if (!is.null(fit$omega2$mode) && is.finite(as.numeric(fit$omega2$mode)[1L])) {
    val <- sqrt(max(as.numeric(fit$omega2$mode)[1L], .Machine$double.eps))
  }
  if (!is.finite(val) || val <= 0) NA_real_ else val
}

safe_gamma_from_fit <- function(fit) {
  val <- NA_real_
  if (!is.null(fit$qsiggam$gamma_mean)) {
    val <- as.numeric(fit$qsiggam$gamma_mean)[1L]
  } else if (!is.null(fit$misc$gamma_trace)) {
    gt <- as.numeric(fit$misc$gamma_trace)
    gt <- gt[is.finite(gt)]
    if (length(gt)) val <- utils::tail(gt, 1L)
  }
  if (!is.finite(val)) NA_real_ else val
}

safe_omega2_from_fit <- function(fit) {
  val <- as.numeric(fit$omega2$mean %||% fit$omega2$mode %||% NA_real_)[1L]
  if (!is.finite(val) || val <= 0) NA_real_ else val
}

numeric_trace <- function(x, n = NULL) {
  out <- as.numeric(x %||% numeric())
  if (!length(out) && !is.null(n)) out <- rep(NA_real_, n)
  out
}

trace_value <- function(x, i) {
  if (!length(x) || i > length(x)) return(NA_real_)
  as.numeric(x[[i]])
}

logical_trace_value <- function(x, i) {
  if (!length(x) || i > length(x)) return(NA)
  as.logical(x[[i]])
}

character_trace_value <- function(x, i) {
  if (!length(x) || i > length(x)) return(NA_character_)
  as.character(x[[i]])
}

record_fit_diagnostics <- function(method_id, model_family, likelihood_family,
                                   prior_family, tau, fit) {
  beta_m <- as.numeric(fit$qbeta$m %||% fit$beta$mean %||% numeric())
  beta_V <- as.matrix(fit$qbeta$V %||% fit$beta$cov %||% matrix(NA_real_, length(beta_m), length(beta_m)))
  append_parameter(
    method_id = method_id,
    model_family = model_family,
    likelihood_family = likelihood_family,
    prior_family = prior_family,
    tau = as.numeric(tau %||% NA_real_),
    beta_l2 = if (length(beta_m)) sqrt(sum(beta_m^2)) else NA_real_,
    beta_max_abs = if (length(beta_m)) max(abs(beta_m)) else NA_real_,
    beta_cov_trace = if (length(beta_V)) sum(diag(beta_V)) else NA_real_,
    sigma = safe_sigma_from_fit(fit),
    gamma = safe_gamma_from_fit(fit),
    omega2 = safe_omega2_from_fit(fit),
    stringsAsFactors = FALSE
  )

  if (!is.null(fit$trace) && is.data.frame(fit$trace) && nrow(fit$trace)) {
    for (i in seq_len(nrow(fit$trace))) {
      tr <- fit$trace[i, , drop = FALSE]
      append_trace(
        method_id = method_id,
        model_family = model_family,
        likelihood_family = likelihood_family,
        prior_family = prior_family,
        tau = as.numeric(tau %||% NA_real_),
        iter = as.integer(tr$iter %||% i),
        elbo = NA_real_,
        sigma = sqrt(as.numeric(tr$sigma2_mean %||% NA_real_)),
        gamma = NA_real_,
        omega2 = as.numeric(tr$sigma2_mean %||% NA_real_),
        beta_max_abs_delta = as.numeric(tr$beta_max_abs_delta %||% NA_real_),
        parameter_change = as.numeric(tr$beta_max_abs_delta %||% NA_real_),
        rhs_tau = NA_real_,
        rhs_c2 = NA_real_,
        rhs_lambda_mean = NA_real_,
        rhs_lambda_min = NA_real_,
        rhs_lambda_max = NA_real_,
        sigmagam_frozen = NA,
        sigmagam_update_performed = NA,
        sigmagam_update_reason = NA_character_,
        stringsAsFactors = FALSE
      )
    }
    return(invisible(NULL))
  }

  misc <- fit$misc %||% list()
  elbo <- numeric_trace(misc$elbo_trace %||% misc$elbo)
  sigma_trace <- numeric_trace(misc$sigma_trace)
  gamma_trace <- numeric_trace(misc$gamma_trace)
  new_term <- numeric_trace(misc$new_term_trace)
  rhs_tau <- numeric_trace(misc$rhs_tau_trace)
  rhs_c2 <- numeric_trace(misc$rhs_c2_trace)
  rhs_lambda_mean <- numeric_trace(misc$rhs_lambda_mean_trace)
  rhs_lambda_min <- numeric_trace(misc$rhs_lambda_min_trace)
  rhs_lambda_max <- numeric_trace(misc$rhs_lambda_max_trace)
  n_trace <- max(
    1L,
    length(elbo), length(sigma_trace), length(gamma_trace), length(new_term),
    length(rhs_tau), length(rhs_c2), length(rhs_lambda_mean),
    length(misc$sigmagam_frozen_trace %||% logical()),
    length(misc$sigmagam_update_performed_trace %||% logical())
  )
  for (i in seq_len(n_trace)) {
    append_trace(
      method_id = method_id,
      model_family = model_family,
      likelihood_family = likelihood_family,
      prior_family = prior_family,
      tau = as.numeric(tau %||% NA_real_),
      iter = i,
      elbo = trace_value(elbo, i),
      sigma = trace_value(sigma_trace, i),
      gamma = trace_value(gamma_trace, i),
      omega2 = NA_real_,
      beta_max_abs_delta = NA_real_,
      parameter_change = trace_value(new_term, i),
      rhs_tau = trace_value(rhs_tau, i),
      rhs_c2 = trace_value(rhs_c2, i),
      rhs_lambda_mean = trace_value(rhs_lambda_mean, i),
      rhs_lambda_min = trace_value(rhs_lambda_min, i),
      rhs_lambda_max = trace_value(rhs_lambda_max, i),
      sigmagam_frozen = logical_trace_value(misc$sigmagam_frozen_trace %||% logical(), i),
      sigmagam_update_performed = logical_trace_value(misc$sigmagam_update_performed_trace %||% logical(), i),
      sigmagam_update_reason = character_trace_value(misc$sigmagam_update_reason_trace %||% character(), i),
      stringsAsFactors = FALSE
    )
  }
  invisible(NULL)
}

make_vb_init_from_fit <- function(source_fit, components, n_rows, gamma_policy = "source") {
  init <- list()
  used <- character()
  components <- unique(as_config_vec(components))
  if (is.null(source_fit) || !length(components)) {
    return(list(init = init, components = used, sigma = NA_real_, gamma = NA_real_))
  }

  if ("beta" %in% components) {
    beta_m <- source_fit$qbeta$m %||% source_fit$beta$mean %||% NULL
    beta_V <- source_fit$qbeta$V %||% source_fit$beta$cov %||% NULL
    if (!is.null(beta_m) && !is.null(beta_V) &&
        length(beta_m) == ncol(X_q_train) &&
        all(dim(as.matrix(beta_V)) == c(ncol(X_q_train), ncol(X_q_train))) &&
        all(is.finite(beta_m)) && all(is.finite(beta_V))) {
      init$beta_m <- as.numeric(beta_m)
      init$beta_V <- as.matrix(beta_V)
      used <- c(used, "beta")
    }
  }

  if ("beta_state" %in% components && !is.null(source_fit$beta_prior$state)) {
    init$beta_state <- source_fit$beta_prior$state
    used <- c(used, "beta_state")
  }

  sigma0 <- safe_sigma_from_fit(source_fit)
  if ("sigma" %in% components && is.finite(sigma0) && sigma0 > 0) {
    init$sigma <- sigma0
    used <- c(used, "sigma")
  }

  gamma0 <- safe_gamma_from_fit(source_fit)
  if ("gamma" %in% components) {
    if (identical(gamma_policy, "zero")) {
      init$gamma <- 0
      gamma0 <- 0
      used <- c(used, "gamma_zero")
    } else if (is.finite(gamma0)) {
      init$gamma <- gamma0
      used <- c(used, "gamma")
    }
  }

  if ("local" %in% components &&
      !is.null(source_fit$qv$m_inv) && length(source_fit$qv$m_inv) == n_rows &&
      !is.null(source_fit$qv$m) && length(source_fit$qv$m) == n_rows &&
      !is.null(source_fit$qs$m) && length(source_fit$qs$m) == n_rows &&
      !is.null(source_fit$qs$m2) && length(source_fit$qs$m2) == n_rows) {
    init$v_inv <- as.numeric(source_fit$qv$m_inv)
    init$v_m <- as.numeric(source_fit$qv$m)
    init$s_m <- as.numeric(source_fit$qs$m)
    init$s_m2 <- as.numeric(source_fit$qs$m2)
    used <- c(used, "local")
  }

  list(init = init, components = used, sigma = sigma0, gamma = gamma0)
}

warm_tau_order <- function(likelihood) {
  qcfg <- warm_cfg$qdesn[[likelihood]] %||% list()
  proposed <- as.numeric(unlist(qcfg$tau_order %||% warm_cfg$qdesn$tau_order %||% numeric(), use.names = FALSE))
  proposed <- proposed[is.finite(proposed)]
  ordered <- proposed[proposed %in% quantiles]
  c(ordered, quantiles[!quantiles %in% ordered])
}

fit_normal <- function(method_id, prior_type) {
  seed <- as.integer(cfg$run$seed %||% 20260530L)
  start <- proc.time()[["elapsed"]]
  if (identical(prior_type, "scaled_ridge")) {
    fit <- exdqlm::normal_desn_fit(
      X_train, y_train,
      beta_prior_type = "scaled_ridge",
      prior = list(beta_ridge_tau2 = 1e4, intercept_var = 1e6),
      omega_prior = cfg$normal$omega_prior
    )
  } else {
    fit <- exdqlm::normal_desn_fit(
      X_train, y_train,
      beta_prior_type = "rhs_ns",
      omega_prior = cfg$normal$omega_prior,
      rhs = rhs,
      control = cfg$normal$vb_control
    )
  }
  elapsed <- proc.time()[["elapsed"]] - start
  append_predictions(method_id, "val", rows_val, normal_predict_quantiles(fit, X_val, seed + 11L))
  append_predictions(method_id, "test", rows_test, normal_predict_quantiles(fit, X_test, seed + 17L))
  append_method(
    method_id = method_id,
    model_family = "normal",
    likelihood_family = "normal",
    prior_family = prior_type,
    target_label = fit$target_label,
    preserves_full_data_target = TRUE,
    approximate = !isTRUE(fit$misc$exact_closed_form),
    chunking_mode = fit$misc$chunking$mode %||% "none",
    converged = fit$converged %||% TRUE,
    iter = if (!is.null(fit$trace)) nrow(fit$trace) else 1L,
    train_seconds = as.numeric(elapsed),
    n_train = nrow(X_train),
    n_features = ncol(X_train),
    warm_start_enabled = warm_enabled,
    warm_start_strategy = if (identical(prior_type, "rhs_ns")) "normal_rhs_internal_scaled_ridge_start" else "closed_form"
  )
  record_fit_diagnostics(
    method_id = method_id,
    model_family = "normal",
    likelihood_family = "normal",
    prior_family = prior_type,
    tau = NA_real_,
    fit = fit
  )
  if (warm_record_diagnostics && identical(prior_type, "rhs_ns")) {
    append_warm(
      method_id = method_id,
      likelihood_family = "normal",
      tau = NA_real_,
      fit_order = NA_integer_,
      init_source = "normal_scaled_ridge",
      init_components = "internal_package_default",
      fallback_used = FALSE,
      converged = fit$converged %||% TRUE,
      iter = if (!is.null(fit$trace)) nrow(fit$trace) else 1L,
      fit_seconds = NA_real_,
      sigma_init = NA_real_,
      gamma_init = NA_real_,
      beta_init_l2 = NA_real_
    )
  }
  fit
}

fit_quantile <- function(likelihood, tau, X_tr = X_q_train, y_tr = y_q_train,
                         chunking = cfg$qdesn_vb$chunking, init = list(),
                         init_source = "cold", init_components = character(),
                         fit_order = NA_integer_, record_warm = TRUE,
                         record_trace = TRUE) {
  ctrl <- exdqlm::exal_make_vb_control(
    max_iter = as.integer(cfg$qdesn_vb$max_iter),
    min_iter_elbo = as.integer(cfg$qdesn_vb$min_iter_elbo),
    tol = as.numeric(cfg$qdesn_vb$tol),
    tol_par = as.numeric(cfg$qdesn_vb$tol_par),
    n_samp_xi = as.integer(cfg$qdesn_vb$n_samp_xi),
    progress_every = 1000000L,
    verbose = FALSE,
    chunking = chunking
  )
  beta_prior_obj <- exdqlm::beta_prior("rhs_ns", rhs = rhs)
  fit_start <- proc.time()[["elapsed"]]
  fallback_used <- FALSE
  fit_call <- function(init_arg) {
    exdqlm::exal_ldvb_fit(
      y = y_tr,
      X = X_tr,
      p0 = tau,
      gamma_bounds = c(exdqlm:::L.fn(tau), exdqlm:::U.fn(tau)),
      likelihood_family = likelihood,
      al_fixed_gamma = 0,
      beta_prior_obj = beta_prior_obj,
      prior_sigma = cfg$qdesn_vb$prior_sigma,
      prior_gamma = cfg$qdesn_vb$prior_gamma,
      vb_control = ctrl,
      init = init_arg
    )
  }
  fit <- tryCatch(
    fit_call(init),
    error = function(e) {
      if (!warm_fallback_to_cold || !length(init)) stop(e)
      fallback_used <<- TRUE
      fit_call(list())
    }
  )
  fit_elapsed <- proc.time()[["elapsed"]] - fit_start
  if (warm_record_diagnostics && isTRUE(record_warm)) {
    append_warm(
      method_id = paste0("qdesn_", likelihood, "_rhs_ns_exact_chunked"),
      likelihood_family = likelihood,
      tau = as.numeric(tau),
      fit_order = as.integer(fit_order),
      init_source = init_source,
      init_components = paste(init_components, collapse = "+"),
      fallback_used = fallback_used,
      converged = isTRUE(fit$converged),
      iter = as.integer(fit$iter %||% NA_integer_),
      fit_seconds = as.numeric(fit_elapsed),
      sigma_init = as.numeric(init$sigma %||% NA_real_),
      gamma_init = as.numeric(init$gamma %||% NA_real_),
      beta_init_l2 = if (!is.null(init$beta_m)) sqrt(sum(as.numeric(init$beta_m)^2)) else NA_real_
    )
  }
  if (isTRUE(record_trace)) {
    record_fit_diagnostics(
      method_id = paste0("qdesn_", likelihood, "_rhs_ns_exact_chunked"),
      model_family = "qdesn_static_readout",
      likelihood_family = likelihood,
      prior_family = "rhs_ns",
      tau = tau,
      fit = fit
    )
  }
  fit
}

fit_qdesn_like <- function(likelihood, normal_fits = list(), fit_cache = list()) {
  method_id <- paste0("qdesn_", likelihood, "_rhs_ns_exact_chunked")
  start <- proc.time()[["elapsed"]]
  fits <- list()
  pred_val <- matrix(NA_real_, nrow(X_val), length(quantiles))
  pred_test <- matrix(NA_real_, nrow(X_test), length(quantiles))
  qcfg <- warm_cfg$qdesn[[likelihood]] %||% list()
  qwarm_enabled <- warm_enabled && isTRUE(qcfg$enabled %||% TRUE)
  components <- as_config_vec(qcfg$components %||% c("beta", "beta_state", "sigma"))
  fit_order <- warm_tau_order(likelihood)
  for (ord in seq_along(fit_order)) {
    tau <- fit_order[[ord]]
    source_fit <- NULL
    source_label <- "cold"
    gamma_policy <- as.character(qcfg$gamma_policy %||% "source")[1L]
    if (isTRUE(qwarm_enabled)) {
      if (identical(likelihood, "al")) {
        if (ord == 1L) {
          source_name <- as.character(qcfg$first_tau_source %||% "normal_rhs_ns")[1L]
          if (identical(source_name, "normal_rhs_ns")) {
            source_fit <- normal_fits$normal_rhs_ns
            source_label <- "normal_rhs_ns"
          } else if (identical(source_name, "normal_scaled_ridge")) {
            source_fit <- normal_fits$normal_scaled_ridge
            source_label <- "normal_scaled_ridge"
          }
        } else if (identical(as.character(qcfg$next_tau_source %||% "previous_al_tau")[1L], "previous_al_tau")) {
          prev_tau <- fit_order[[ord - 1L]]
          source_fit <- fits[[tau_key(prev_tau)]]
          source_label <- paste0("qdesn_al_tau_", tau_key(prev_tau))
        }
      } else if (identical(likelihood, "exal")) {
        source_name <- as.character(qcfg$source %||% "al_same_tau")[1L]
        if (identical(source_name, "al_same_tau")) {
          source_fit <- fit_cache$al[[tau_key(tau)]]
          source_label <- paste0("qdesn_al_tau_", tau_key(tau))
        }
        if (identical(as.character(qcfg$gamma_policy %||% "zero")[1L], "zero")) {
          gamma_policy <- "zero"
        }
      }
    }
    init_info <- make_vb_init_from_fit(source_fit, components, nrow(X_q_train), gamma_policy = gamma_policy)
    if (!length(init_info$components)) source_label <- "cold"
    fit <- fit_quantile(
      likelihood, tau,
      init = init_info$init,
      init_source = source_label,
      init_components = init_info$components,
      fit_order = ord
    )
    fits[[tau_key(tau)]] <- fit
  }
  for (j in seq_along(quantiles)) {
    tau <- quantiles[[j]]
    fit <- fits[[tau_key(tau)]]
    pred_val[, j] <- as.numeric(X_val %*% fit$qbeta$m)
    pred_test[, j] <- as.numeric(X_test %*% fit$qbeta$m)
  }
  elapsed <- proc.time()[["elapsed"]] - start
  append_predictions(method_id, "val", rows_val, pred_val)
  append_predictions(method_id, "test", rows_test, pred_test)
  append_method(
    method_id = method_id,
    model_family = "qdesn_static_readout",
    likelihood_family = likelihood,
    prior_family = "rhs_ns",
    target_label = "full_data_exact_chunked",
    preserves_full_data_target = TRUE,
    approximate = FALSE,
    chunking_mode = "exact",
    converged = all(vapply(fits, function(z) isTRUE(z$converged), logical(1))),
    iter = max(vapply(fits, function(z) as.integer(z$iter %||% NA_integer_), integer(1)), na.rm = TRUE),
    train_seconds = as.numeric(elapsed),
    n_train = nrow(X_q_train),
    n_features = ncol(X_train),
    warm_start_enabled = qwarm_enabled,
    warm_start_strategy = if (qwarm_enabled) "see_warm_start_diagnostics" else "cold"
  )
  invisible(fits)
}

run_exact_equivalence <- function() {
  spec <- cfg$exact_equivalence
  if (!isTRUE(spec$enabled)) return(invisible(NULL))
  n_eq <- min(as.integer(spec$train_rows %||% 600L), nrow(X_train))
  tau <- as.numeric(spec$quantile %||% 0.25)
  likelihood <- as.character(spec$likelihood %||% "al")
  X_sub <- X_train[seq_len(n_eq), , drop = FALSE]
  y_sub <- y_train[seq_len(n_eq)]
  fit_full <- fit_quantile(likelihood, tau, X_sub, y_sub, chunking = NULL, record_warm = FALSE, record_trace = FALSE)
  fit_exact <- fit_quantile(likelihood, tau, X_sub, y_sub, chunking = cfg$qdesn_vb$chunking, record_warm = FALSE, record_trace = FALSE)
  beta_diff <- max(abs(fit_full$qbeta$m - fit_exact$qbeta$m))
  cov_diff <- max(abs(fit_full$qbeta$V - fit_exact$qbeta$V))
  pred_diff <- max(abs(as.numeric(X_sub %*% fit_full$qbeta$m) - as.numeric(X_sub %*% fit_exact$qbeta$m)))
  exact_rows[[length(exact_rows) + 1L]] <<- data.frame(
    likelihood_family = likelihood,
    prior_family = "rhs_ns",
    tau = tau,
    n_rows = n_eq,
    beta_mean_max_abs_diff = beta_diff,
    beta_cov_max_abs_diff = cov_diff,
    train_prediction_max_abs_diff = pred_diff,
    tolerance = as.numeric(spec$tolerance %||% 1e-6),
    passed = isTRUE(max(beta_diff, cov_diff, pred_diff) <= as.numeric(spec$tolerance %||% 1e-6)),
    stringsAsFactors = FALSE
  )
}

normal_fits <- list()
normal_fits$normal_scaled_ridge <- fit_normal("normal_scaled_ridge", "scaled_ridge")
normal_fits$normal_rhs_ns <- fit_normal("normal_rhs_ns", "rhs_ns")
run_exact_equivalence()
fit_cache <- list()
if ("al" %in% qdesn_likelihoods) {
  fit_cache$al <- fit_qdesn_like("al", normal_fits = normal_fits, fit_cache = fit_cache)
}
if ("exal" %in% qdesn_likelihoods) {
  fit_cache$exal <- fit_qdesn_like("exal", normal_fits = normal_fits, fit_cache = fit_cache)
}

predictions <- do.call(rbind, prediction_rows)
methods <- do.call(rbind, method_rows)
utils::write.csv(predictions, file.path(out_dir, "model_predictions_scaled.csv"), row.names = FALSE)
utils::write.csv(methods, file.path(out_dir, "model_method_summary.csv"), row.names = FALSE)
utils::write.csv(horizon_weighting$summary, file.path(out_dir, "training_weight_summary.csv"), row.names = FALSE)
if (length(exact_rows)) {
  utils::write.csv(do.call(rbind, exact_rows), file.path(out_dir, "exact_equivalence.csv"), row.names = FALSE)
}
if (length(warm_rows)) {
  utils::write.csv(do.call(rbind, warm_rows), file.path(out_dir, "warm_start_diagnostics.csv"), row.names = FALSE)
}
if (length(trace_rows)) {
  utils::write.csv(do.call(rbind, trace_rows), file.path(out_dir, "model_trace_summary.csv"), row.names = FALSE)
}
if (length(parameter_rows)) {
  utils::write.csv(do.call(rbind, parameter_rows), file.path(out_dir, "model_parameter_summary.csv"), row.names = FALSE)
}

write_json(file.path(out_dir, "run_manifest.json"), list(
  config = cfg_path,
  adapter_dir = adapter_dir,
  output_dir = out_dir,
  methods = methods$method_id,
  quantiles = quantiles,
  horizons = horizons,
  qdesn_likelihoods = qdesn_likelihoods,
  horizon_weighting = as.list(horizon_weighting$summary[1, , drop = TRUE]),
  warm_start = warm_cfg
))

cat(out_dir, "\n")
