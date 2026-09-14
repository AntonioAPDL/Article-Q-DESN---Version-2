# Validity-first Search Phase II for the GloFAS Normal DESN bridge.
#
# Model jobs receive history and oracle PRISM/ERA5 covariates only. Future USGS
# and retrospective GloFAS values live in separate scoring packets and are read
# only after a recursive forecast has been written.

app_glofas_search2_final_origin <- function() as.Date("2022-12-25")

app_glofas_search2_assert_git_state <- function(expected_head = NULL, require_synced = TRUE) {
  git <- function(args) {
    out <- suppressWarnings(system2("git", c("-C", app_repo_root(), args), stdout = TRUE, stderr = TRUE))
    if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) {
      stop(sprintf("Search-II Git check failed: git %s.", paste(args, collapse = " ")), call. = FALSE)
    }
    out
  }
  status <- git(c("status", "--porcelain", "--untracked-files=normal"))
  if (length(status)) stop("Search-II execution requires a clean committed worktree.", call. = FALSE)
  head <- git(c("rev-parse", "HEAD"))[[1L]]
  if (!is.null(expected_head) && !identical(head, as.character(expected_head))) {
    stop("Search-II execution HEAD differs from the frozen run manifest.", call. = FALSE)
  }
  upstream <- git(c("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"))[[1L]]
  divergence <- strsplit(git(c("rev-list", "--left-right", "--count", paste0(upstream, "...HEAD")))[[1L]], "[[:space:]]+")[[1L]]
  divergence <- as.integer(divergence[nzchar(divergence)])
  if (isTRUE(require_synced) && (length(divergence) != 2L || any(divergence != 0L))) {
    stop("Search-II execution branch must be exactly synchronized with its upstream.", call. = FALSE)
  }
  list(head = head, upstream = upstream, behind = divergence[[1L]], ahead = divergence[[2L]])
}

app_glofas_search2_fold_registry <- function() {
  out <- data.frame(
    fold_id = c(
      "fold_2018_12_25", "fold_2019_12_25", "fold_2020_12_25",
      "fold_2021_11_12", "fold_2021_12_21", "fold_2022_05_11"
    ),
    origin_date = as.Date(c(
      "2018-12-25", "2019-12-25", "2020-12-25",
      "2021-11-12", "2021-12-21", "2022-05-11"
    )),
    primary_horizon = 28L,
    secondary_horizon = 30L,
    retrospective_product = "v3.1 LISFLOOD",
    primary = TRUE,
    stringsAsFactors = FALSE
  )
  app_glofas_search2_validate_folds(out)
  out
}

app_glofas_search2_validate_folds <- function(folds, final_origin = app_glofas_search2_final_origin()) {
  required <- c("fold_id", "origin_date", "primary_horizon", "secondary_horizon")
  missing <- setdiff(required, names(folds))
  if (length(missing)) stop(sprintf("Search-II folds are missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  folds$origin_date <- as.Date(folds$origin_date)
  if (!nrow(folds) || any(is.na(folds$origin_date)) || anyDuplicated(folds$fold_id)) {
    stop("Search-II folds require unique IDs and finite origins.", call. = FALSE)
  }
  if (any(folds$origin_date >= as.Date(final_origin))) {
    stop("Search-II tuning folds must precede the final 2022-12-25 origin.", call. = FALSE)
  }
  starts <- folds$origin_date + 1L
  ends <- folds$origin_date + as.integer(folds$secondary_horizon)
  for (i in seq_len(nrow(folds))) {
    other <- setdiff(seq_len(nrow(folds)), i)
    overlap <- other[starts[[i]] <= ends[other] & ends[[i]] >= starts[other]]
    if (length(overlap)) stop("Search-II scoring windows must not overlap.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_search2_default_data_root <- function() {
  candidates <- unique(c(
    Sys.getenv("APP_GLOFAS_MULTICUTOFF_ROOT", unset = ""),
    file.path(app_repo_root(), "application/data_local/frozen_inputs/glofas_multicutoff_project1_20260911"),
    file.path(sub("__wt__.*$", "", app_repo_root()), "application/data_local/frozen_inputs/glofas_multicutoff_project1_20260911")
  ))
  hit <- candidates[nzchar(candidates) & dir.exists(candidates)]
  if (!length(hit)) stop("The frozen GloFAS multi-cutoff input root is unavailable.", call. = FALSE)
  normalizePath(hit[[1L]], mustWork = TRUE)
}

app_glofas_search2_master_paths <- function(data_root = app_glofas_search2_default_data_root()) {
  bundle <- file.path(data_root, "bundles", "cutoff_date=2022-12-25")
  paths <- c(
    reference = file.path(bundle, "reference", "reference_gauge_history.csv"),
    retrospective = file.path(bundle, "glofas", "glofas_retrospective.csv"),
    covariates = file.path(bundle, "covariates", "ppt_soil_history.csv")
  )
  missing <- paths[!file.exists(paths)]
  if (length(missing)) stop(sprintf("Missing Search-II source files: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  paths
}

app_glofas_search2_load_master <- function(data_root = app_glofas_search2_default_data_root()) {
  paths <- app_glofas_search2_master_paths(data_root)
  ref <- app_read_csv(paths[["reference"]])
  ret <- app_read_csv(paths[["retrospective"]])
  cov <- app_read_csv(paths[["covariates"]])
  app_check_required_columns(ref, c("date", "streamflow"), "Search-II USGS history")
  app_check_required_columns(ret, c("date", "glofas_streamflow"), "Search-II GloFAS retrospective")
  app_check_required_columns(cov, c("date", "ppt", "soil"), "Search-II covariate history")
  x <- Reduce(function(a, b) merge(a, b, by = "date", all = FALSE, sort = FALSE), list(
    data.frame(date = as.Date(ref$date), usgs = as.numeric(ref$streamflow)),
    data.frame(date = as.Date(ret$date), glofas = as.numeric(ret$glofas_streamflow)),
    data.frame(date = as.Date(cov$date), ppt = as.numeric(cov$ppt), soil = as.numeric(cov$soil))
  ))
  x <- x[order(x$date), , drop = FALSE]
  x <- x[!duplicated(x$date), , drop = FALSE]
  if (!nrow(x) || any(!is.finite(as.matrix(x[, c("usgs", "glofas", "ppt", "soil")]))) ||
      any(diff(x$date) != 1)) {
    stop("Search-II master history must be finite, unique, and daily contiguous.", call. = FALSE)
  }
  x$usgs_log1p <- log1p(pmax(x$usgs, 0))
  x$glofas_log1p <- log1p(pmax(x$glofas, 0))
  x$discrepancy_log1p <- x$glofas_log1p - x$usgs_log1p
  list(
    data = x,
    paths = paths,
    sha256 = setNames(vapply(paths, app_sha256_file, character(1L)), names(paths)),
    data_root = normalizePath(data_root, mustWork = TRUE)
  )
}

app_glofas_search2_base_cfg <- function() {
  list(
    data = list(transform = list(response = "log1p", forecast = "log1p")),
    covariates = list(
      enabled = TRUE,
      variables = c("ppt", "soil"),
      readout = list(use_scaled = TRUE, scale_reference = "retrospective_train")
    )
  )
}

app_glofas_search2_covariate_timeline <- function(x, origin_date, train_start) {
  origin_date <- as.Date(origin_date)
  train_start <- as.Date(train_start)
  ref <- x[x$date >= train_start & x$date <= origin_date, , drop = FALSE]
  if (!nrow(ref)) stop("Search-II fold has no covariate scaling reference.", call. = FALSE)
  out <- data.frame(
    date = as.Date(x$date), ppt = as.numeric(x$ppt), soil = as.numeric(x$soil),
    ppt_role = ifelse(x$date <= origin_date, "retrospective_realized", "oracle_realized_future"),
    soil_role = ifelse(x$date <= origin_date, "retrospective_realized", "oracle_realized_future"),
    stringsAsFactors = FALSE
  )
  scale_params <- list()
  for (v in c("ppt", "soil")) {
    mu <- mean(ref[[v]])
    s <- stats::sd(ref[[v]])
    if (!is.finite(s) || s <= 0) s <- 1
    out[[paste0(v, "_scaled")]] <- (out[[v]] - mu) / s
    scale_params[[v]] <- list(center = mu, scale = s)
  }
  attr(out, "variables") <- c("ppt", "soil")
  attr(out, "scale_params") <- scale_params
  attr(out, "cutoff_date") <- as.character(origin_date)
  attr(out, "covariate_future_policy") <- "oracle_realized"
  attr(out, "covariate_source_provider") <- "frozen_prism_era5_archive"
  out
}

app_glofas_search2_make_fold_packets <- function(master, fold_row, target = c("reference", "discrepancy")) {
  target <- match.arg(target)
  fold_row <- fold_row[1L, , drop = FALSE]
  origin <- as.Date(fold_row$origin_date[[1L]])
  horizon <- as.integer(fold_row$secondary_horizon[[1L]])
  future_dates <- seq.Date(origin + 1L, origin + horizon, by = "day")
  x <- master$data
  train_start <- min(x$date)
  hist <- x[x$date >= train_start & x$date <= origin, , drop = FALSE]
  future <- x[match(future_dates, x$date), , drop = FALSE]
  if (!nrow(hist) || nrow(future) != horizon || any(is.na(future$date))) {
    stop(sprintf("Fold %s is not covered by the master history.", fold_row$fold_id[[1L]]), call. = FALSE)
  }
  response <- if (identical(target, "reference")) hist$usgs_log1p else hist$discrepancy_log1p
  raw_response <- if (identical(target, "reference")) hist$usgs else hist$glofas - hist$usgs
  panel <- data.frame(
    origin_date = hist$date,
    target_date = hist$date,
    horizon = 0L,
    member = NA_character_,
    is_retrospective = TRUE,
    is_ensemble = FALSE,
    y_reference = raw_response,
    g_glofas = hist$glofas,
    y_transformed = response,
    g_transformed = hist$glofas_log1p,
    split = "train",
    cutoff_id = as.character(fold_row$fold_id[[1L]]),
    stringsAsFactors = FALSE
  )
  timeline_source <- x[x$date >= train_start & x$date <= max(future_dates), , drop = FALSE]
  timeline <- app_glofas_search2_covariate_timeline(timeline_source, origin, train_start)
  panel <- app_attach_model_covariates(panel, timeline)
  model_packet <- list(
    version = "glofas_search_phase2_model_packet_v1",
    fold_id = as.character(fold_row$fold_id[[1L]]),
    target = target,
    origin_date = origin,
    future_dates = future_dates,
    panel_bundle = list(
      panel = panel,
      cutoff = data.frame(
        cutoff_id = as.character(fold_row$fold_id[[1L]]),
        train_start = train_start,
        train_end = origin,
        origin_date = origin,
        eval_start = origin + 1L,
        eval_end = origin + horizon,
        stringsAsFactors = FALSE
      )
    ),
    source_hashes = master$sha256,
    leakage_contract = "contains_history_and_oracle_covariates_only_no_future_response_truth"
  )
  future_target <- if (identical(target, "reference")) future$usgs_log1p else future$discrepancy_log1p
  scoring_packet <- data.frame(
    fold_id = as.character(fold_row$fold_id[[1L]]),
    target = target,
    origin_date = origin,
    date = future_dates,
    horizon = seq_len(horizon),
    observed = future_target,
    primary_28 = seq_len(horizon) <= as.integer(fold_row$primary_horizon[[1L]]),
    stringsAsFactors = FALSE
  )
  list(model = model_packet, scoring = scoring_packet)
}

app_glofas_search2_input_dimension <- function(output_lag_max, covariate_lag_max) {
  as.integer(output_lag_max) + 2L * (as.integer(covariate_lag_max) + 1L)
}

app_glofas_search2_win_scale <- function(effective_input_gain, pi_in, input_dimension) {
  effective_input_gain / sqrt(as.numeric(pi_in) * as.numeric(input_dimension))
}

app_glofas_search2_geometries <- function(target = c("reference", "discrepancy")) {
  target <- match.arg(target)
  widths <- if (identical(target, "reference")) c(1500L, 2500L, 3000L, 4000L, 5000L) else c(1500L, 2000L, 2500L, 3000L, 4000L)
  d1 <- data.frame(D = 1L, n_vector = as.character(widths), n_state_features = widths, stringsAsFactors = FALSE)
  d2 <- data.frame(
    D = 2L,
    n_vector = if (identical(target, "reference")) c("1500,1500", "2500,2500") else c("1250,1250", "2000,2000"),
    n_state_features = if (identical(target, "reference")) c(3000L, 5000L) else c(2500L, 4000L),
    stringsAsFactors = FALSE
  )
  rbind(d1, d2)
}

app_glofas_search2_pool <- function(target = c("reference", "discrepancy")) {
  target <- match.arg(target)
  geoms <- app_glofas_search2_geometries(target)
  axes <- expand.grid(
    geometry_index = seq_len(nrow(geoms)),
    output_lag_max = c(180L, 360L, 540L),
    covariate_lag_max = c(90L, 180L, 360L),
    alpha = if (identical(target, "reference")) c(0.40, 0.50, 0.60, 0.75) else c(0.60, 0.70, 0.80, 0.90, 0.95),
    rho = if (identical(target, "reference")) c(0.60, 0.75, 0.90, 0.99) else c(0.30, 0.50, 0.70, 0.85, 0.95),
    pi_w = c(0.005, 0.01, 0.03, 0.10),
    pi_in = c(0.10, 0.30, 1.00),
    effective_input_gain = c(0.50, 1.00, 2.00, 3.00, 4.84),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  out <- cbind(axes, geoms[axes$geometry_index, , drop = FALSE])
  out$geometry_index <- NULL
  out$target <- target
  out$input_dimension <- mapply(app_glofas_search2_input_dimension, out$output_lag_max, out$covariate_lag_max)
  out$win_scale_global <- mapply(app_glofas_search2_win_scale, out$effective_input_gain, out$pi_in, out$input_dimension)
  out$win_scale_bias <- out$win_scale_global
  out
}

app_glofas_search2_numeric_features <- function(x) {
  cols <- c(
    "D", "n_state_features", "output_lag_max", "covariate_lag_max", "alpha", "rho",
    "pi_w", "pi_in", "effective_input_gain"
  )
  Z <- as.matrix(x[, cols, drop = FALSE])
  Z[, "n_state_features"] <- log(Z[, "n_state_features"])
  Z[, "pi_w"] <- log10(Z[, "pi_w"])
  Z[, "pi_in"] <- log10(Z[, "pi_in"])
  center <- colMeans(Z)
  scale <- apply(Z, 2L, stats::sd)
  scale[!is.finite(scale) | scale <= 0] <- 1
  sweep(sweep(Z, 2L, center, "-"), 2L, scale, "/")
}

app_glofas_search2_maximin <- function(pool, n, start_index = 1L) {
  n <- min(as.integer(n), nrow(pool))
  if (n < 1L) return(pool[FALSE, , drop = FALSE])
  Z <- app_glofas_search2_numeric_features(pool)
  selected <- as.integer(start_index)
  min_distance <- rowSums((Z - matrix(Z[start_index, ], nrow(Z), ncol(Z), byrow = TRUE))^2)
  min_distance[selected] <- -Inf
  while (length(selected) < n) {
    next_index <- which.max(min_distance)
    selected <- c(selected, next_index)
    distance <- rowSums((Z - matrix(Z[next_index, ], nrow(Z), ncol(Z), byrow = TRUE))^2)
    min_distance <- pmin(min_distance, distance)
    min_distance[selected] <- -Inf
  }
  pool[selected, , drop = FALSE]
}

app_glofas_search2_authoritative_row <- function(target = c("reference", "discrepancy"), state_scaling = "none") {
  target <- match.arg(target)
  out <- if (identical(target, "reference")) {
    data.frame(D = 1L, n_vector = "3000", n_state_features = 3000L, output_lag_max = 360L,
      covariate_lag_max = 180L, alpha = 0.50, rho = 0.90, pi_w = 0.03, pi_in = 1,
      effective_input_gain = 0.18 * sqrt(app_glofas_search2_input_dimension(360L, 180L)), stringsAsFactors = FALSE)
  } else {
    data.frame(D = 1L, n_vector = "2500", n_state_features = 2500L, output_lag_max = 360L,
      covariate_lag_max = 180L, alpha = 0.80, rho = 0.70, pi_w = 0.03, pi_in = 1,
      effective_input_gain = 0.18 * sqrt(app_glofas_search2_input_dimension(360L, 180L)), stringsAsFactors = FALSE)
  }
  out$target <- target
  out$input_dimension <- app_glofas_search2_input_dimension(out$output_lag_max, out$covariate_lag_max)
  out$win_scale_global <- 0.18
  out$win_scale_bias <- 0.18
  out$state_scaling <- state_scaling
  out
}

app_glofas_search2_candidate_manifest <- function(target = c("reference", "discrepancy"), n_space_filling = 64L) {
  target <- match.arg(target)
  pool <- app_glofas_search2_pool(target)
  anchor <- app_glofas_search2_authoritative_row(target, state_scaling = "train_zscore")
  combined <- app_bind_rows_fill(list(pool, anchor))
  combined_features <- app_glofas_search2_numeric_features(combined)
  distance <- rowSums((combined_features[seq_len(nrow(pool)), , drop = FALSE] -
    matrix(combined_features[nrow(combined_features), ], nrow(pool), ncol(combined_features), byrow = TRUE))^2)
  selected <- app_glofas_search2_maximin(pool, n_space_filling, start_index = which.min(distance))
  selected$state_scaling <- "train_zscore"
  selected$candidate_role <- "space_filling_primary"
  anchors <- rbind(
    transform(app_glofas_search2_authoritative_row(target, "none"), candidate_role = "phase1_legacy_anchor"),
    transform(anchor, candidate_role = "phase1_standardized_anchor")
  )
  tau_pilots <- do.call(rbind, lapply(c(1, 10, 10000), function(tau2) {
    transform(anchor, candidate_role = paste0("ridge_tau2_pilot_", format(tau2, scientific = TRUE)), ridge_tau2 = tau2)
  }))
  # Keep explicit anchors when a maximin point lands on the same specification.
  out <- app_bind_rows_fill(list(anchors, tau_pilots, selected))
  out$ridge_tau2[is.na(out$ridge_tau2)] <- 100
  out$m <- out$output_lag_max
  out$washout <- 500L
  out$seed <- if (identical(target, "reference")) 20260512L else 20261521L
  out$intercept_var <- 1.0e6
  out$sigma_a <- 2
  out$sigma_b <- 1
  out$input_bound <- "none"
  out$act_f <- "tanh"
  out$act_k <- "identity"
  out$standardize_inputs <- TRUE
  out$dlm_extension_enabled <- FALSE
  out$geometry_label <- paste0("D", out$D, "_n", gsub(",", "x", out$n_vector))
  key_cols <- c("target", "n_vector", "output_lag_max", "covariate_lag_max", "alpha", "rho", "pi_w", "pi_in",
    "win_scale_global", "state_scaling", "ridge_tau2")
  key <- do.call(paste, c(out[key_cols], sep = "|"))
  out <- out[!duplicated(key), , drop = FALSE]
  out$candidate_id <- sprintf("search2_%s_%03d", substr(target, 1L, 3L), seq_len(nrow(out)))
  out$priority <- seq_len(nrow(out))
  rownames(out) <- NULL
  out[, c("candidate_id", "priority", setdiff(names(out), c("candidate_id", "priority"))), drop = FALSE]
}

app_glofas_search2_expand_jobs <- function(candidates, folds, method = "ridge", stage = "ridge_screen") {
  idx <- expand.grid(candidate_index = seq_len(nrow(candidates)), fold_index = seq_len(nrow(folds)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  out <- cbind(candidates[idx$candidate_index, , drop = FALSE], folds[idx$fold_index, , drop = FALSE])
  out$method <- method
  out$stage <- stage
  out$job_id <- paste(stage, out$candidate_id, out$fold_id, sep = "__")
  out$memory_weight <- ifelse(out$n_state_features <= 2500, 1L, ifelse(out$n_state_features <= 4000, 2L, 3L))
  rownames(out) <- NULL
  out[, c("job_id", "stage", "method", "memory_weight", setdiff(names(out), c("job_id", "stage", "method", "memory_weight"))), drop = FALSE]
}

app_glofas_search2_calibrated_tau0 <- function(m0, p_penalized, sigma_ref, n_fit) {
  m0 <- as.numeric(m0)
  p_penalized <- as.numeric(p_penalized)
  if (!is.finite(m0) || m0 <= 0 || m0 >= p_penalized) stop("m0 must lie in (0, p_penalized).", call. = FALSE)
  if (!is.finite(sigma_ref) || sigma_ref <= 0 || !is.finite(n_fit) || n_fit <= 0) {
    stop("Calibrated tau0 requires positive sigma_ref and n_fit.", call. = FALSE)
  }
  m0 / (p_penalized - m0) * sigma_ref / sqrt(n_fit)
}

app_glofas_search2_prior_specs <- function(include_legacy = TRUE) {
  out <- data.frame(
    prior_id = c("cal_m025_learned", "cal_m100_learned", "cal_m300_learned", "cal_m100_fixed4", "cal_m100_fixed16"),
    prior_mode = "calibrated_m0",
    m0 = c(25, 100, 300, 100, 100),
    rhs_zeta2_fixed = c(NA, NA, NA, 4, 16),
    rhs_a_zeta = 2,
    rhs_b_zeta = 4,
    stringsAsFactors = FALSE
  )
  if (isTRUE(include_legacy)) {
    out <- rbind(out, data.frame(
      prior_id = "phase1_legacy_tau0", prior_mode = "legacy_tau0", m0 = NA_real_, rhs_zeta2_fixed = NA_real_,
      rhs_a_zeta = 2, rhs_b_zeta = 4, stringsAsFactors = FALSE
    ))
  }
  out
}

app_glofas_search2_select_rhs_architectures <- function(ridge_aggregate, candidates, n_top = 8L, n_diverse = 11L) {
  score <- ridge_aggregate[is.finite(ridge_aggregate$mean_primary_crps), , drop = FALSE]
  if ("promotion_eligible" %in% names(score)) {
    score <- score[!is.na(score$promotion_eligible) & score$promotion_eligible, , drop = FALSE]
  }
  if (!nrow(score)) stop("No guardrail-eligible Ridge architecture is available for RHS screening.", call. = FALSE)
  score <- score[order(score$mean_primary_crps, score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
  anchor_ids <- as.character(candidates$candidate_id[candidates$candidate_role == "phase1_legacy_anchor"])
  if (length(anchor_ids) != 1L) stop("RHS selection requires exactly one Phase I legacy anchor per target.", call. = FALSE)
  ranked_ids <- setdiff(as.character(score$candidate_id), anchor_ids)
  top_ids <- utils::head(ranked_ids, n_top)
  remaining <- candidates[
    !candidates$candidate_id %in% c(anchor_ids, top_ids) & candidates$candidate_id %in% score$candidate_id,
    , drop = FALSE
  ]
  diverse_ids <- if (nrow(remaining)) {
    as.character(app_glofas_search2_maximin(remaining, n_diverse)$candidate_id)
  } else character()
  ids <- unique(c(anchor_ids, top_ids, diverse_ids))
  out <- candidates[match(ids, candidates$candidate_id), , drop = FALSE]
  out$rhs_selection_role <- ifelse(
    out$candidate_id %in% anchor_ids, "phase1_legacy_anchor",
    ifelse(out$candidate_id %in% top_ids, "ridge_top", "ridge_diverse")
  )
  out
}

app_glofas_search2_rhs_manifest <- function(architectures, folds, prior_specs = app_glofas_search2_prior_specs(), stage = "rhs_pilot") {
  idx <- expand.grid(
    candidate_index = seq_len(nrow(architectures)), fold_index = seq_len(nrow(folds)), prior_index = seq_len(nrow(prior_specs)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  out <- cbind(
    architectures[idx$candidate_index, , drop = FALSE],
    folds[idx$fold_index, , drop = FALSE],
    prior_specs[idx$prior_index, , drop = FALSE]
  )
  out$method <- "rhs"
  out$stage <- stage
  out$rhs_max_iter <- 100L
  out$rhs_min_iter <- 30L
  out$rhs_tol <- 1.0e-4
  out$rhs_update_every <- 1L
  out$rhs_freeze_tau_warmup_iters <- 0L
  out$rhs_min_tau_updates <- 10L
  out$rhs_freeze_beta_warmup_iters <- 20L
  out$rhs_min_beta_updates <- 30L
  out$design_group_id <- paste(out$target, out$candidate_id, out$fold_id, sep = "__")
  out$job_id <- paste(stage, out$candidate_id, out$prior_id, out$fold_id, sep = "__")
  out$memory_weight <- ifelse(out$n_state_features <= 2500, 1L, ifelse(out$n_state_features <= 4000, 2L, 3L))
  rownames(out) <- NULL
  out[, c("job_id", "stage", "method", "memory_weight", setdiff(names(out), c("job_id", "stage", "method", "memory_weight"))), drop = FALSE]
}

app_glofas_search2_compact_warm_start <- function(candidate_row, design, ridge_fit) {
  out <- list(
    type = "glofas_normal_part1_ridge_warm_start", version = "0.1",
    candidate_id = as.character(candidate_row$candidate_id[[1L]]),
    design = list(colnames = colnames(design$X)),
    fit = list(
      beta_mean = as.numeric(ridge_fit$beta_mean), beta_var_diag = as.numeric(ridge_fit$beta_var_diag),
      sigma_a = ridge_fit$sigma_a, sigma_b = ridge_fit$sigma_b, sigma2_mean = ridge_fit$sigma2_mean,
      p = ridge_fit$p
    )
  )
  class(out) <- c("glofas_normal_part1_ridge_warm_start", "list")
  out
}

app_glofas_search2_light_state_diagnostics <- function(design, seed = 1L) {
  X <- as.matrix(design$X_raw %||% design$X)
  if (ncol(X) > 1L) X <- X[, -1L, drop = FALSE]
  set.seed(as.integer(seed))
  rows <- if (nrow(X) > 2000L) sort(sample.int(nrow(X), 2000L)) else seq_len(nrow(X))
  cols <- if (ncol(X) > 256L) sort(sample.int(ncol(X), 256L)) else seq_len(ncol(X))
  report <- app_compute_state_matrix_diagnostics(
    X[rows, cols, drop = FALSE],
    config = app_reservoir_diagnostic_config(
      washout = 0L, max_corr_features_full = 256L, max_svd_rows = 2000L, max_svd_features = 256L,
      large_matrix_policy = "subsample", low_effective_rank_action = "repair",
      saturation_fraction_warn = 0.30, saturation_fraction_reject = 0.60
    ),
    matrix_role = "sampled_reservoir_readout",
    metadata = list(sampled_rows = length(rows), sampled_features = length(cols), total_rows = nrow(X), total_features = ncol(X))
  )
  data.frame(
    diagnostic_decision = as.character(report$decision),
    finite_pass = isTRUE(report$finite_pass),
    sampled_dead_fraction = as.numeric(report$dead_fraction),
    sampled_saturation_fraction = as.numeric(report$saturation_fraction),
    sampled_relative_effective_rank = as.numeric(report$relative_effective_rank_entropy),
    sampled_condition_z = as.numeric(report$condition_z),
    sampled_near_duplicate_fraction = as.numeric(report$near_duplicate_fraction),
    sampled_rows = length(rows), sampled_features = length(cols),
    stringsAsFactors = FALSE
  )
}

app_glofas_search2_resolve_rhs_tau0 <- function(job_row, ridge_fit, p, n_fit) {
  mode <- as.character(job_row$prior_mode[[1L]] %||% "legacy_tau0")
  if (identical(mode, "legacy_tau0")) {
    return(if (identical(as.character(job_row$target[[1L]]), "reference")) 1 else 0.001)
  }
  app_glofas_search2_calibrated_tau0(
    m0 = as.numeric(job_row$m0[[1L]]), p_penalized = p - 1L,
    sigma_ref = sqrt(as.numeric(ridge_fit$sigma2_mean)), n_fit = n_fit
  )
}

app_glofas_search2_historical_scores <- function(design, fit) {
  mu <- as.numeric(design$X %*% fit$beta_mean)
  observed <- as.numeric(design$y)
  sigma <- sqrt(as.numeric(fit$sigma2_mean))
  if (!is.finite(sigma) || sigma <= 0) sigma <- stats::sd(observed - mu)
  windows <- c(all = length(observed), last1000 = min(1000L, length(observed)),
    last200 = min(200L, length(observed)), last50 = min(50L, length(observed)))
  values <- list()
  for (name in names(windows)) {
    idx <- utils::tail(seq_along(observed), windows[[name]])
    error <- mu[idx] - observed[idx]
    values[[paste0("historical_", name, "_mae")]] <- mean(abs(error))
    values[[paste0("historical_", name, "_rmse")]] <- sqrt(mean(error^2))
    values[[paste0("historical_", name, "_plugin_crps")]] <- mean(app_glofas_normal_crps(
      observed[idx], mu[idx], rep(sigma, length(idx))
    ))
  }
  as.data.frame(values, stringsAsFactors = FALSE)
}

app_glofas_search2_coefficient_diagnostics <- function(design, fit, top_n = 50L) {
  table <- app_glofas_normal_rhs_coefficient_table(fit, design$feature_info)
  table$coefficient_basis <- as.character((design$readout_scaler %||% list())$mode %||% "none")
  keep <- table$is_intercept | table$abs_mean_rank <= as.integer(top_n)
  activity <- app_glofas_normal_rhs_activity_summary(table)
  activity$coefficient_basis <- table$coefficient_basis[[1L]]
  list(top = table[keep, , drop = FALSE], activity = activity)
}

app_glofas_search2_prepare_fit_inputs <- function(model_packet, job_row) {
  job_row <- job_row[1L, , drop = FALSE]
  design <- app_glofas_oracle_build_part1_design(
    app_glofas_search2_base_cfg(), job_row, model_packet$panel_bundle
  )
  method <- as.character(job_row$method[[1L]])
  warm_path <- as.character(app_glofas_normal_part1_row_value(job_row, "ridge_warm_start_path", NA_character_))
  warm_hash <- as.character(app_glofas_normal_part1_row_value(job_row, "ridge_warm_start_sha256", NA_character_))
  reuse_warm <- identical(method, "rhs") && !is.na(warm_path) && nzchar(warm_path)
  if (reuse_warm) {
    warm_path <- normalizePath(warm_path, mustWork = TRUE)
    if (is.na(warm_hash) || !nzchar(warm_hash) || !identical(app_sha256_file(warm_path), warm_hash)) {
      stop("Search-II Ridge warm-start hash mismatch.", call. = FALSE)
    }
    warm <- readRDS(warm_path)
    if (!inherits(warm, "glofas_normal_part1_ridge_warm_start") ||
        !identical(as.character(warm$candidate_id), as.character(job_row$candidate_id[[1L]])) ||
        !identical(as.character(warm$design$colnames), colnames(design$X))) {
      stop("Search-II Ridge warm start does not match the rebuilt design.", call. = FALSE)
    }
    ridge_fit <- warm$fit
  } else {
    ridge_fit <- app_glofas_normal_ridge_fit(
      design$X, design$y,
      ridge_tau2 = as.numeric(job_row$ridge_tau2[[1L]]),
      intercept_var = as.numeric(job_row$intercept_var[[1L]]),
      sigma_a = as.numeric(job_row$sigma_a[[1L]]), sigma_b = as.numeric(job_row$sigma_b[[1L]])
    )
    warm <- app_glofas_search2_compact_warm_start(job_row, design, ridge_fit)
  }
  list(design = design, ridge_fit = ridge_fit, ridge_warm_start = warm, ridge_warm_start_reused = reuse_warm)
}

app_glofas_search2_fit_and_forecast <- function(model_packet, job_row, forecast_backend = "auto", prepared = NULL) {
  job_row <- job_row[1L, , drop = FALSE]
  started <- Sys.time()
  method <- as.character(job_row$method[[1L]])
  prepared <- prepared %||% app_glofas_search2_prepare_fit_inputs(model_packet, job_row)
  design <- prepared$design
  ridge_fit <- prepared$ridge_fit
  warm <- prepared$ridge_warm_start
  rhs_tau0 <- NA_real_
  fit <- ridge_fit
  if (identical(method, "rhs")) {
    rhs_tau0 <- app_glofas_search2_resolve_rhs_tau0(job_row, ridge_fit, ncol(design$X), nrow(design$X))
    zeta <- suppressWarnings(as.numeric(job_row$rhs_zeta2_fixed[[1L]] %||% NA_real_))
    fit <- app_glofas_normal_rhs_fit(
      design$X, design$y, warm, tau0 = rhs_tau0,
      a_zeta = as.numeric(job_row$rhs_a_zeta[[1L]] %||% 2),
      b_zeta = as.numeric(job_row$rhs_b_zeta[[1L]] %||% 4),
      zeta2_fixed = if (is.finite(zeta)) zeta else NULL,
      max_iter = as.integer(job_row$rhs_max_iter[[1L]] %||% 100L),
      min_iter = as.integer(job_row$rhs_min_iter[[1L]] %||% 30L),
      tol = as.numeric(job_row$rhs_tol[[1L]] %||% 1.0e-4),
      rhs_update_every = as.integer(job_row$rhs_update_every[[1L]] %||% 1L),
      freeze_tau_warmup_iters = as.integer(job_row$rhs_freeze_tau_warmup_iters[[1L]] %||% 0L),
      min_tau_updates = as.integer(job_row$rhs_min_tau_updates[[1L]] %||% 0L),
      freeze_beta_warmup_iters = as.integer(job_row$rhs_freeze_beta_warmup_iters[[1L]] %||% 0L),
      min_beta_updates = as.integer(job_row$rhs_min_beta_updates[[1L]] %||% 0L)
    )
  } else if (!identical(method, "ridge")) {
    stop(sprintf("Unsupported Search-II method '%s'.", method), call. = FALSE)
  }
  fitted <- list(method = method, candidate_row = job_row, design = design, fit = fit)
  forecast <- app_glofas_oracle_recursive_forecast(
    fitted, future_dates = as.Date(model_packet$future_dates),
    covariate_timeline = attr(model_packet$panel_bundle$panel, "model_covariate_timeline", exact = TRUE),
    forecast_backend = forecast_backend
  )
  diagnostics <- app_glofas_search2_light_state_diagnostics(design, seed = as.integer(job_row$seed[[1L]]))
  historical <- app_glofas_search2_historical_scores(design, fit)
  coefficients <- app_glofas_search2_coefficient_diagnostics(design, fit)
  path <- data.frame(
    job_id = as.character(job_row$job_id[[1L]]),
    candidate_id = as.character(job_row$candidate_id[[1L]]),
    fold_id = as.character(job_row$fold_id[[1L]]),
    target = as.character(job_row$target[[1L]]),
    method = method,
    prior_id = as.character(job_row$prior_id[[1L]] %||% NA_character_),
    origin_date = as.Date(model_packet$origin_date),
    date = as.Date(forecast$future_dates), horizon = seq_along(forecast$future_dates),
    pred_mean = as.numeric(forecast$pred_mean), pred_sd = as.numeric(forecast$pred_sd),
    stringsAsFactors = FALSE
  )
  trace <- fit$trace %||% data.frame()
  summary <- cbind(job_row, data.frame(
    status = "forecast_completed_unscored", n_train = nrow(design$X), p = ncol(design$X),
    rhs_tau0_effective = rhs_tau0,
    fit_converged = if (identical(method, "ridge")) TRUE else isTRUE(fit$converged),
    fit_iterations = if (identical(method, "ridge")) 0L else as.integer(fit$iterations),
    ridge_warm_start_reused = isTRUE(prepared$ridge_warm_start_reused),
    forecast_backend = as.character(forecast$forecast_backend),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE
  ), diagnostics, historical)
  list(
    summary = summary, path = path, trace = trace,
    coefficient_top = coefficients$top, coefficient_activity = coefficients$activity,
    ridge_warm_start = warm
  )
}

app_glofas_search2_score_forecast <- function(path, scoring_packet) {
  scoring_packet$date <- as.Date(scoring_packet$date)
  path$date <- as.Date(path$date)
  idx <- match(path$date, scoring_packet$date)
  if (any(is.na(idx)) || any(path$fold_id != scoring_packet$fold_id[idx]) || any(path$target != scoring_packet$target[idx])) {
    stop("Search-II model output does not match its sealed scoring packet.", call. = FALSE)
  }
  observed <- as.numeric(scoring_packet$observed[idx])
  detail <- cbind(path, data.frame(
    observed = observed,
    crps = app_glofas_normal_crps(observed, path$pred_mean, path$pred_sd),
    abs_error = abs(path$pred_mean - observed),
    squared_error = (path$pred_mean - observed)^2,
    primary_28 = as.logical(scoring_packet$primary_28[idx]),
    stringsAsFactors = FALSE
  ))
  score_rows <- lapply(c("primary_28", "secondary_30"), function(window) {
    keep <- if (identical(window, "primary_28")) detail$primary_28 else rep(TRUE, nrow(detail))
    data.frame(
      job_id = detail$job_id[[1L]], candidate_id = detail$candidate_id[[1L]], fold_id = detail$fold_id[[1L]],
      target = detail$target[[1L]], method = detail$method[[1L]], score_window = window,
      n_score = sum(keep), mean_crps = mean(detail$crps[keep]), mae = mean(detail$abs_error[keep]),
      rmse = sqrt(mean(detail$squared_error[keep])), stringsAsFactors = FALSE
    )
  })
  list(summary = do.call(rbind, score_rows), detail = detail)
}

app_glofas_search2_aggregate_scores <- function(score_summaries, require_folds = NULL) {
  primary <- score_summaries[score_summaries$score_window == "primary_28", , drop = FALSE]
  secondary <- score_summaries[score_summaries$score_window == "secondary_30", , drop = FALSE]
  keys <- unique(primary[, intersect(c(
    "candidate_id", "target", "method", "prior_id", "candidate_role", "rhs_selection_role",
    "D", "n_state_features"
  ), names(primary)), drop = FALSE])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    hit <- rep(TRUE, nrow(primary))
    for (nm in names(keys)) {
      left <- as.character(primary[[nm]])
      right <- as.character(keys[[nm]][[i]])
      hit <- hit & ((is.na(left) & is.na(right)) | (!is.na(left) & !is.na(right) & left == right))
    }
    p <- primary[hit, , drop = FALSE]
    hit2 <- rep(TRUE, nrow(secondary))
    for (nm in names(keys)) {
      left <- as.character(secondary[[nm]])
      right <- as.character(keys[[nm]][[i]])
      hit2 <- hit2 & ((is.na(left) & is.na(right)) | (!is.na(left) & !is.na(right) & left == right))
    }
    s <- secondary[hit2, , drop = FALSE]
    diagnostic_columns <- intersect(c(
      grep("^historical_", names(p), value = TRUE), "runtime_seconds",
      "sampled_saturation_fraction", "sampled_relative_effective_rank"
    ), names(p))
    diagnostics <- if (length(diagnostic_columns)) {
      as.data.frame(lapply(p[diagnostic_columns], function(value) mean(as.numeric(value), na.rm = TRUE)), stringsAsFactors = FALSE)
    } else keys[i, FALSE, drop = FALSE]
    logical_rate <- function(name, default = NA_real_) {
      if (!name %in% names(p)) return(default)
      mean(as.logical(p[[name]]), na.rm = TRUE)
    }
    cbind(data.frame(
      keys[i, , drop = FALSE], n_folds = nrow(p),
      mean_primary_crps = mean(p$mean_crps), worst_primary_crps = max(p$mean_crps), sd_primary_crps = stats::sd(p$mean_crps),
      mean_secondary_crps = mean(s$mean_crps), mean_primary_mae = mean(p$mae), mean_primary_rmse = mean(p$rmse),
      fit_convergence_rate = logical_rate("fit_converged"),
      finite_pass_rate = logical_rate("finite_pass"),
      diagnostic_reject_rate = if ("diagnostic_decision" %in% names(p)) mean(p$diagnostic_decision == "reject", na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    ), diagnostics)
  })
  out <- app_bind_rows_fill(rows)
  expected_folds <- if (is.null(require_folds)) max(out$n_folds) else as.integer(require_folds)
  out$complete_fold_pass <- out$n_folds == expected_folds
  out$numerical_pass <- out$complete_fold_pass & is.finite(out$mean_primary_crps) & is.finite(out$worst_primary_crps)
  if ("fit_convergence_rate" %in% names(out)) {
    out$numerical_pass <- out$numerical_pass & (is.na(out$fit_convergence_rate) | out$fit_convergence_rate == 1)
  }
  if ("finite_pass_rate" %in% names(out)) {
    out$numerical_pass <- out$numerical_pass & (is.na(out$finite_pass_rate) | out$finite_pass_rate == 1)
  }
  if ("diagnostic_reject_rate" %in% names(out)) {
    out$numerical_pass <- out$numerical_pass & (is.na(out$diagnostic_reject_rate) | out$diagnostic_reject_rate == 0)
  }
  out$guardrail_baseline_available <- FALSE
  out$historical_all_rmse_ratio <- NA_real_
  out$historical_last200_rmse_ratio <- NA_real_
  out$historical_guardrail_pass <- NA
  grouping <- intersect(c("target", "method", "prior_id"), names(out))
  group_key <- if (length(grouping)) {
    do.call(paste, c(lapply(out[grouping], function(x) ifelse(is.na(x), "<NA>", x)), sep = "|"))
  } else rep("all", nrow(out))
  for (group in unique(group_key)) {
    idx <- which(group_key == group)
    baseline <- idx[as.character(out$candidate_role[idx]) == "phase1_legacy_anchor"]
    if (length(baseline) != 1L || !all(c("historical_all_rmse", "historical_last200_rmse") %in% names(out))) next
    all_base <- as.numeric(out$historical_all_rmse[baseline])
    recent_base <- as.numeric(out$historical_last200_rmse[baseline])
    if (!is.finite(all_base) || all_base <= 0 || !is.finite(recent_base) || recent_base <= 0) next
    out$guardrail_baseline_available[idx] <- TRUE
    out$historical_all_rmse_ratio[idx] <- out$historical_all_rmse[idx] / all_base
    out$historical_last200_rmse_ratio[idx] <- out$historical_last200_rmse[idx] / recent_base
    out$historical_guardrail_pass[idx] <- out$historical_all_rmse_ratio[idx] <= 1.01 &
      out$historical_last200_rmse_ratio[idx] <= 1.03
  }
  out$promotion_eligible <- out$numerical_pass &
    (is.na(out$historical_guardrail_pass) | out$historical_guardrail_pass)
  rounded <- round(out$mean_primary_crps, 4)
  saturation <- if ("sampled_saturation_fraction" %in% names(out)) out$sampled_saturation_fraction else rep(Inf, nrow(out))
  effective_rank <- if ("sampled_relative_effective_rank" %in% names(out)) out$sampled_relative_effective_rank else rep(-Inf, nrow(out))
  runtime <- if ("runtime_seconds" %in% names(out)) out$runtime_seconds else rep(Inf, nrow(out))
  dimension <- if ("n_state_features" %in% names(out)) out$n_state_features else rep(Inf, nrow(out))
  selection_columns <- intersect(c("target", "method", "prior_id"), names(out))
  selection_group <- if (length(selection_columns)) {
    do.call(paste, c(lapply(out[selection_columns], function(x) ifelse(is.na(x), "<NA>", x)), sep = "|"))
  } else rep("all", nrow(out))
  out <- out[order(
    selection_group, !out$promotion_eligible, rounded, out$worst_primary_crps,
    !ifelse(is.na(out$historical_guardrail_pass), TRUE, out$historical_guardrail_pass),
    saturation, -effective_rank, runtime, dimension
  ), , drop = FALSE]
  selection_group <- if (length(selection_columns)) {
    do.call(paste, c(lapply(out[selection_columns], function(x) ifelse(is.na(x), "<NA>", x)), sep = "|"))
  } else rep("all", nrow(out))
  out$rank <- ave(seq_len(nrow(out)), selection_group, FUN = seq_along)
  out$promotion_rank <- NA_integer_
  out$equivalence_4dp <- FALSE
  for (group in unique(selection_group)) {
    idx <- which(selection_group == group)
    eligible <- idx[out$promotion_eligible[idx]]
    if (!length(eligible)) next
    out$promotion_rank[eligible] <- seq_along(eligible)
    out$equivalence_4dp[idx] <- round(out$mean_primary_crps[idx], 4) ==
      round(out$mean_primary_crps[eligible[[1L]]], 4)
  }
  rownames(out) <- NULL
  out
}

app_glofas_search2_validate_model_packet <- function(packet) {
  if (!identical(packet$version, "glofas_search_phase2_model_packet_v1")) stop("Unknown Search-II model packet.", call. = FALSE)
  if (!identical(packet$leakage_contract, "contains_history_and_oracle_covariates_only_no_future_response_truth")) {
    stop("Search-II leakage contract is absent.", call. = FALSE)
  }
  forbidden <- c("future_truth", "observed", "usgs_future", "glofas_future")
  if (length(intersect(forbidden, names(packet)))) stop("Model packet contains a forbidden future-truth field.", call. = FALSE)
  panel <- packet$panel_bundle$panel
  if (any(as.Date(panel$target_date) > as.Date(packet$origin_date))) stop("Model panel extends beyond its origin.", call. = FALSE)
  if (max(as.Date(panel$target_date)) != as.Date(packet$origin_date)) stop("Model history must end at its origin.", call. = FALSE)
  if (as.Date(packet$origin_date) >= app_glofas_search2_final_origin()) stop("Final test origin cannot enter Search-II tuning.", call. = FALSE)
  invisible(TRUE)
}
