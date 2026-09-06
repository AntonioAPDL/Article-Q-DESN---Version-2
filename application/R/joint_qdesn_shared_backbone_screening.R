# Scenario-specific Gaussian screening for a shared JOINT QDESN backbone.

app_joint_shared_default_root <- function() {
  app_path("application/cache/joint_qdesn_shared_backbone_pilot_20260906")
}

app_joint_shared_contract_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_contract_v1.csv")
}

app_joint_shared_axes_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_candidate_axes_v1.csv")
}

app_joint_shared_scenario_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_scenario_registry_v1.csv")
}

app_joint_shared_read_scenarios <- function(path = app_joint_shared_scenario_path()) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("enabled", "scenario_id", "scenario_order", "role", "selection_unit"),
    "shared-backbone scenario registry")
  if (anyDuplicated(x$scenario_id)) stop("Shared-backbone scenario IDs must be unique.", call. = FALSE)
  x$enabled <- app_as_bool_vec(x$enabled)
  x[order(x$scenario_order), , drop = FALSE]
}

app_joint_shared_default_authority_registry <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase180_balanced_dgp_score_freeze_20260824/final_selected_cell_registry.csv"
}

app_joint_shared_split_values <- function(x, numeric = FALSE) {
  out <- trimws(strsplit(as.character(x)[[1L]], ";", fixed = TRUE)[[1L]])
  if (isTRUE(numeric)) {
    out <- suppressWarnings(as.numeric(out))
    if (!length(out) || any(!is.finite(out))) stop("Malformed numeric-vector contract value.", call. = FALSE)
  }
  out
}

app_joint_shared_read_contract <- function(path = app_joint_shared_contract_path()) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("section", "name", "value", "type", "description"), "shared-backbone contract")
  if (anyDuplicated(x$name)) stop("Shared-backbone contract names must be unique.", call. = FALSE)
  get <- function(name) {
    row <- x[x$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing unique contract field '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  out <- list(
    table = x,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    authority_registry_sha256 = get("authority_registry_sha256"),
    authority_manifest_sha256 = get("authority_manifest_sha256"),
    pilot_scenario = get("pilot_scenario"),
    tau = app_joint_shared_split_values(get("quantile_grid"), TRUE),
    desn_washout_rows = as.integer(get("desn_washout_rows")),
    fit_rows = as.integer(get("fit_rows")),
    inner_training_rows = as.integer(get("inner_training_rows")),
    inner_calibration_rows = as.integer(get("inner_calibration_rows")),
    protected_validation_rows = as.integer(get("protected_validation_rows")),
    novel_candidate_count = as.integer(get("novel_candidate_count")),
    advance_count = as.integer(get("advance_count")),
    ridge_tau2 = as.numeric(get("ridge_tau2")),
    intercept_variance = as.numeric(get("intercept_variance")),
    sigma_shape = as.numeric(get("sigma_shape")),
    sigma_rate = as.numeric(get("sigma_rate")),
    calibration_replicates = as.integer(get("calibration_replicates")),
    calibration_seed_base = as.integer(get("calibration_seed_base")),
    rhs_tau0_grid = app_joint_shared_split_values(get("tau0_grid"), TRUE),
    rhs_max_iter = as.integer(get("max_iter")),
    rhs_min_iter = as.integer(get("min_iter")),
    rhs_tolerance = as.numeric(get("tolerance")),
    max_workers = as.integer(get("max_workers")),
    blas_threads = as.integer(get("blas_threads")),
    nice_level = as.integer(get("nice_level")),
    max_condition_number = as.numeric(get("max_condition_number")),
    max_state_saturation = as.numeric(get("max_state_saturation"))
  )
  if (out$inner_training_rows + out$inner_calibration_rows != out$fit_rows) {
    stop("Inner training/calibration rows must partition the fit window.", call. = FALSE)
  }
  if (!identical(out$tau, sort(unique(out$tau))) || any(out$tau <= 0 | out$tau >= 1)) {
    stop("Shared-backbone quantile grid must be strictly increasing in (0,1).", call. = FALSE)
  }
  out
}

app_joint_shared_read_axes <- function(path = app_joint_shared_axes_path()) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c("axis", "values", "role"), "shared-backbone candidate axes")
  if (anyDuplicated(x$axis)) stop("Candidate axes must be unique.", call. = FALSE)
  value <- function(axis, numeric = FALSE) {
    row <- x[x$axis == axis, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing candidate axis '%s'.", axis), call. = FALSE)
    app_joint_shared_split_values(row$values[[1L]], numeric)
  }
  list(
    table = x,
    depth = as.integer(value("depth", TRUE)),
    retained_state_budget = as.integer(value("retained_state_budget", TRUE)),
    width_shape = value("width_shape"),
    state_reduction = tolower(value("state_reduction")) == "true",
    alpha_schedule = value("alpha_schedule"),
    rho = value("rho", TRUE),
    input_scale = value("input_scale", TRUE),
    design_class = value("design_class"),
    pi_w = value("pi_w", TRUE),
    pi_in = value("pi_in", TRUE)
  )
}

app_joint_shared_widths <- function(D, budget, shape, reduction) {
  D <- as.integer(D); budget <- as.integer(budget)
  weights <- if (identical(shape, "flat")) rep(1, D) else rev(seq_len(D))
  retained <- pmax(1L, floor(budget * weights / sum(weights)))
  while (sum(retained) < budget) retained[[which.min(retained)]] <- retained[[which.min(retained)]] + 1L
  while (sum(retained) > budget) retained[[which.max(retained)]] <- retained[[which.max(retained)]] - 1L
  n <- retained
  if (isTRUE(reduction) && D > 1L) n[seq_len(D - 1L)] <- pmin(256L, 2L * retained[seq_len(D - 1L)])
  n_tilde <- if (D > 1L) retained[seq_len(D - 1L)] else integer(0)
  list(n = as.integer(n), n_tilde = as.integer(n_tilde), retained = retained)
}

app_joint_shared_alpha <- function(D, schedule) {
  D <- as.integer(D)
  switch(schedule,
    fast = rep(0.80, D), balanced = rep(0.50, D), slow = rep(0.20, D),
    fast_to_slow = seq(0.80, 0.20, length.out = D),
    slow_to_fast = seq(0.20, 0.80, length.out = D),
    stop(sprintf("Unknown alpha schedule '%s'.", schedule), call. = FALSE)
  )
}

app_joint_shared_vec_label <- function(x) paste(format(x, trim = TRUE, scientific = FALSE), collapse = ";")

app_joint_shared_architecture_signature <- function(row) {
  fields <- c("design_class", "D", "n", "n_tilde", "alpha", "rho", "pi_w", "pi_in", "input_scale")
  text <- paste(paste(fields, vapply(fields, function(nm) as.character(row[[nm]][[1L]]), character(1L)), sep = "="), collapse = "|")
  app_joint_qvp_sha256_text(text)
}

app_joint_shared_candidate_universe <- function(axes = app_joint_shared_read_axes()) {
  grid <- expand.grid(
    D = axes$depth,
    retained_state_budget = axes$retained_state_budget,
    width_shape = axes$width_shape,
    state_reduction = axes$state_reduction,
    alpha_schedule = axes$alpha_schedule,
    rho_scalar = axes$rho,
    input_scale = axes$input_scale,
    design_class = axes$design_class,
    pi_w_scalar = axes$pi_w,
    stringsAsFactors = FALSE
  )
  rows <- lapply(seq_len(nrow(grid)), function(ii) {
    g <- grid[ii, , drop = FALSE]
    D <- as.integer(g$D[[1L]])
    widths <- app_joint_shared_widths(D, g$retained_state_budget[[1L]], g$width_shape[[1L]], g$state_reduction[[1L]])
    alpha <- app_joint_shared_alpha(D, g$alpha_schedule[[1L]])
    row <- data.frame(
      design_class = g$design_class[[1L]], D = D,
      n = app_joint_shared_vec_label(widths$n),
      n_tilde = app_joint_shared_vec_label(widths$n_tilde),
      retained_state_budget = sum(widths$retained), width_shape = g$width_shape[[1L]],
      state_reduction = isTRUE(g$state_reduction[[1L]]),
      alpha_schedule = g$alpha_schedule[[1L]], alpha = app_joint_shared_vec_label(alpha),
      rho = app_joint_shared_vec_label(rep(g$rho_scalar[[1L]], D)),
      pi_w = app_joint_shared_vec_label(rep(g$pi_w_scalar[[1L]], D)),
      pi_in = app_joint_shared_vec_label(rep(axes$pi_in[[1L]], D)),
      input_scale = as.numeric(g$input_scale[[1L]]), stringsAsFactors = FALSE
    )
    row$architecture_signature <- app_joint_shared_architecture_signature(row)
    row
  })
  out <- app_bind_rows_fill(rows)
  out <- out[!duplicated(out$architecture_signature), , drop = FALSE]
  out <- out[order(out$architecture_signature), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_joint_shared_maximin <- function(candidates, n) {
  n <- as.integer(n)
  if (nrow(candidates) <= n) return(candidates)
  encode <- data.frame(
    D = candidates$D,
    budget = candidates$retained_state_budget,
    reduction = as.numeric(candidates$state_reduction),
    alpha_first = vapply(strsplit(candidates$alpha, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    alpha_last = vapply(strsplit(candidates$alpha, ";", fixed = TRUE), function(x) as.numeric(tail(x, 1L)), numeric(1L)),
    rho = vapply(strsplit(candidates$rho, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    input_scale = candidates$input_scale,
    pi_w = vapply(strsplit(candidates$pi_w, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L)),
    hybrid = as.numeric(candidates$design_class == "hybrid")
  )
  X <- as.matrix(encode)
  X <- apply(X, 2L, function(z) if (diff(range(z)) > 0) (z - min(z)) / diff(range(z)) else rep(0, length(z)))
  start <- order(-rowSums((X - 0.5)^2), candidates$architecture_signature)[[1L]]
  selected <- start
  min_d2 <- rowSums((X - matrix(X[start, ], nrow(X), ncol(X), byrow = TRUE))^2)
  while (length(selected) < n) {
    min_d2[selected] <- -Inf
    next_i <- order(-min_d2, candidates$architecture_signature)[[1L]]
    selected <- c(selected, next_i)
    d2 <- rowSums((X - matrix(X[next_i, ], nrow(X), ncol(X), byrow = TRUE))^2)
    min_d2 <- pmin(min_d2, d2)
  }
  candidates[selected, , drop = FALSE]
}

app_joint_shared_authority_anchor <- function(authority, scenario_id) {
  required <- c("scenario_id", "source_model_id", "candidate_id", "design_role", "design_class", "tau0", "zeta2", "alpha_prior_sd")
  app_check_required_columns(authority, required, "authoritative winner registry")
  rows <- authority[authority$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(rows) != 4L || length(unique(rows$source_model_id)) != 4L) {
    stop(sprintf("Expected four authoritative quantile rows for '%s'.", scenario_id), call. = FALSE)
  }
  signatures <- unique(paste(rows$design_role, rows$design_class, sep = "|"))
  if (length(signatures) != 1L || unique(rows$design_role) != "frozen_base_fixture") {
    stop("Current authority does not deduplicate to one frozen-base design; implement explicit design extraction before continuing.", call. = FALSE)
  }
  audit <- rows[, required, drop = FALSE]
  audit$deduplication_group <- paste0(scenario_id, "__current_authority_design_01")
  audit$mandatory_anchor <- TRUE
  anchor <- data.frame(
    candidate_id = paste0(scenario_id, "__authority_frozen_base_fixture"),
    candidate_role = "mandatory_authority_anchor", scenario_id = scenario_id,
    design_class = "direct", D = 0L, n = "", n_tilde = "",
    retained_state_budget = 0L, width_shape = "direct", state_reduction = FALSE,
    alpha_schedule = "direct", alpha = "", rho = "", pi_w = "", pi_in = "",
    input_scale = NA_real_, reservoir_seed = NA_integer_,
    architecture_signature = app_joint_qvp_sha256_text(paste(scenario_id, signatures, sep = "|")),
    stringsAsFactors = FALSE
  )
  list(anchor = anchor, audit = audit)
}

app_joint_shared_candidates <- function(scenario_id, authority, n_novel = 192L) {
  anchor <- app_joint_shared_authority_anchor(authority, scenario_id)
  universe <- app_joint_shared_candidate_universe()
  novel <- app_joint_shared_maximin(universe, n_novel)
  novel <- novel[order(novel$architecture_signature), , drop = FALSE]
  novel$candidate_id <- sprintf("%s__ridge_%03d", scenario_id, seq_len(nrow(novel)))
  novel$candidate_role <- "novel_shared_backbone"
  novel$scenario_id <- scenario_id
  novel$reservoir_seed <- 202609600L + seq_len(nrow(novel))
  novel <- novel[, names(anchor$anchor), drop = FALSE]
  out <- rbind(anchor$anchor, novel)
  rownames(out) <- NULL
  list(candidates = out, authority_audit = anchor$audit, universe = universe)
}

app_joint_shared_fixture_for_seed <- function(registry_row, seed, seed_role) {
  row <- registry_row
  row$seed <- as.integer(seed)
  row$seed_role <- as.character(seed_role)
  app_joint_qdesn_fixture_from_registry_row(row)
}

app_joint_shared_selector_fixture <- function(fixture, contract) {
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit")
  if (sum(fixture$detailed_split$role == "desn_washout") != contract$desn_washout_rows ||
      sum(fixture$detailed_split$role == "fit") != contract$fit_rows ||
      sum(fixture$detailed_split$role == "validation") != contract$protected_validation_rows) {
    stop("Full fixture geometry does not match the shared-backbone contract.", call. = FALSE)
  }
  list(
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_class,
    distribution_family = fixture$distribution_family,
    dynamics_class = fixture$dynamics_class,
    y = fixture$y[keep],
    Z = fixture$Z[keep, , drop = FALSE],
    tau = fixture$tau,
    true_q = fixture$true_q[keep, , drop = FALSE],
    detailed_split = fixture$detailed_split[keep, , drop = FALSE],
    seed = fixture$seed,
    seed_role = fixture$seed_role,
    selector_fixture = TRUE,
    protected_rows_persisted = 0L,
    protected_rows_declared = contract$protected_validation_rows
  )
}

app_joint_shared_selection_indices <- function(fixture, contract) {
  split <- fixture$detailed_split
  washout <- which(split$role == "desn_washout")
  fit <- which(split$role == "fit")
  protected <- which(split$role == "validation")
  if (length(washout) != contract$desn_washout_rows || length(fit) != contract$fit_rows ||
      length(protected) != 0L || !isTRUE(fixture$selector_fixture) ||
      as.integer(fixture$protected_rows_persisted) != 0L ||
      as.integer(fixture$protected_rows_declared) != contract$protected_validation_rows) {
    stop("Fixture geometry does not match the shared-backbone contract.", call. = FALSE)
  }
  inner_train <- fit[seq_len(contract$inner_training_rows)]
  list(
    analysis = c(washout, fit),
    scale_reference = inner_train,
    inner_train = inner_train,
    inner_calibration = fit[seq.int(contract$inner_training_rows + 1L, contract$fit_rows)],
    protected = protected
  )
}

app_joint_shared_parse_num_vec <- function(x) {
  if (!nzchar(as.character(x)[[1L]])) return(numeric(0))
  as.numeric(strsplit(as.character(x)[[1L]], ";", fixed = TRUE)[[1L]])
}

app_joint_shared_design <- function(fixture, candidate, contract) {
  idx <- app_joint_shared_selection_indices(fixture, contract)
  raw <- as.matrix(fixture$Z[idx$analysis, , drop = FALSE])
  storage.mode(raw) <- "double"
  if (!all(is.finite(raw))) stop("Source design contains nonfinite values.", call. = FALSE)
  analysis_full <- idx$analysis
  ref_local <- match(idx$scale_reference, analysis_full)
  train_local <- match(idx$inner_train, analysis_full)
  cal_local <- match(idx$inner_calibration, analysis_full)
  scale_params <- app_joint_exqdesn_phase151_scale_params(raw, seq_len(nrow(raw)) %in% ref_local)
  raw_scaled <- app_qdesn_reservoir_scale_inputs(raw, scale_params = scale_params)$X
  cls <- as.character(candidate$design_class[[1L]])
  state_raw <- matrix(numeric(0), nrow(raw), 0L)
  reservoir <- NULL
  if (!identical(cls, "direct")) {
    D <- as.integer(candidate$D[[1L]])
    reservoir <- app_qdesn_generate_article_reservoir(
      list(reservoir = list(
        D = D,
        n = as.integer(app_joint_shared_parse_num_vec(candidate$n[[1L]])),
        n_tilde = as.integer(app_joint_shared_parse_num_vec(candidate$n_tilde[[1L]])),
        m = ncol(raw_scaled), alpha = app_joint_shared_parse_num_vec(candidate$alpha[[1L]]),
        rho = app_joint_shared_parse_num_vec(candidate$rho[[1L]]),
        pi_w = app_joint_shared_parse_num_vec(candidate$pi_w[[1L]]),
        pi_in = app_joint_shared_parse_num_vec(candidate$pi_in[[1L]]),
        w_dist = "uniform", in_dist = "uniform", act_f = "tanh", act_k = "identity"
      )),
      seed = as.integer(candidate$reservoir_seed[[1L]]), m_input = ncol(raw_scaled)
    )
    meta <- list(standardize_inputs = FALSE, lag_center = rep(0, ncol(raw_scaled)),
      lag_scale = rep(1, ncol(raw_scaled)), input_bound = "none",
      win_scale_global = as.numeric(candidate$input_scale[[1L]]),
      win_scale_bias = as.numeric(candidate$input_scale[[1L]]))
    state_raw <- app_qdesn_roll_article_reservoir(raw_scaled, reservoir, meta)$X_all
  }
  if (ncol(state_raw)) {
    center <- colMeans(state_raw[train_local, , drop = FALSE])
    scale <- apply(state_raw[train_local, , drop = FALSE], 2L, stats::sd)
    scale[!is.finite(scale) | scale <= 1e-10] <- 1
    states <- sweep(sweep(state_raw, 2L, center, "-"), 2L, scale, "/")
    colnames(states) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(states))))
  } else states <- state_raw
  Z <- switch(cls, direct = raw, reservoir = states, hybrid = cbind(raw, states),
    stop(sprintf("Unknown design class '%s'.", cls), call. = FALSE))
  colnames(Z) <- make.unique(colnames(Z))
  X <- cbind(`(Intercept)` = 1, Z)
  train_X <- X[train_local, , drop = FALSE]
  cond <- tryCatch(kappa(train_X, exact = FALSE), error = function(e) Inf)
  saturation <- if (ncol(state_raw)) mean(abs(state_raw[train_local, , drop = FALSE]) > 0.99) else 0
  list(
    X = X, y = fixture$y[analysis_full], true_q = fixture$true_q[analysis_full, , drop = FALSE],
    tau = fixture$tau, train_local = train_local, calibration_local = cal_local,
    feature_names = colnames(X), reservoir = reservoir,
    diagnostic = data.frame(
      n_analysis = length(analysis_full), n_train = length(train_local), n_calibration = length(cal_local),
      protected_rows_loaded = 0L, n_features = ncol(X), effective_rank = qr(train_X)$rank,
      condition_number = cond, state_saturation_fraction = saturation,
      finite_design = all(is.finite(X)), stringsAsFactors = FALSE
    )
  )
}

app_joint_shared_weights <- function(tau) {
  c((tau[[2L]] - tau[[1L]]) / 2,
    (tau[3:length(tau)] - tau[1:(length(tau) - 2L)]) / 2,
    (tau[[length(tau)]] - tau[[length(tau) - 1L]]) / 2)
}

app_joint_shared_acrps <- function(y, qhat, tau) {
  qhat <- as.matrix(qhat); y <- as.numeric(y); tau <- as.numeric(tau)
  if (nrow(qhat) != length(y) || ncol(qhat) != length(tau)) stop("aCRPS dimensions do not conform.", call. = FALSE)
  weights <- app_joint_shared_weights(tau)
  loss <- vapply(seq_along(tau), function(k) app_check_loss(y, qhat[, k], tau[[k]]), numeric(length(y)))
  as.numeric(2 * loss %*% weights)
}

app_joint_shared_score_ridge <- function(fixture, candidate, contract) {
  started <- Sys.time()
  design <- app_joint_shared_design(fixture, candidate, contract)
  tr <- design$train_local; va <- design$calibration_local
  fit <- app_glofas_normal_ridge_fit(
    design$X[tr, , drop = FALSE], design$y[tr], ridge_tau2 = contract$ridge_tau2,
    intercept_var = contract$intercept_variance, sigma_a = contract$sigma_shape,
    sigma_b = contract$sigma_rate
  )
  pred <- app_glofas_normal_predict(fit, design$X[va, , drop = FALSE], chunk_size = 64L)
  qhat <- outer(pred$sd, stats::qnorm(design$tau), "*") + pred$mean
  score <- app_joint_shared_acrps(design$y[va], qhat, design$tau)
  oracle <- qhat - design$true_q[va, , drop = FALSE]
  diagnostic_pass <- isTRUE(design$diagnostic$finite_design[[1L]]) &&
    is.finite(design$diagnostic$condition_number[[1L]]) &&
    design$diagnostic$condition_number[[1L]] <= contract$max_condition_number &&
    is.finite(design$diagnostic$state_saturation_fraction[[1L]]) &&
    design$diagnostic$state_saturation_fraction[[1L]] <= contract$max_state_saturation
  summary <- cbind(candidate, design$diagnostic, data.frame(
    status = "completed", observational_selector = "realized_finite_grid_acrps",
    hard_gate_status = if (diagnostic_pass) "pass" else "fail",
    calibration_acrps_mean = mean(score), calibration_acrps_sd = stats::sd(score),
    calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(design$y[va], pred$mean, pred$sd)),
    calibration_mae = mean(abs(pred$mean - design$y[va])),
    calibration_rmse = sqrt(mean((pred$mean - design$y[va])^2)),
    calibration_oracle_quantile_mae = mean(abs(oracle)),
    calibration_oracle_quantile_rmse = sqrt(mean(oracle^2)),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE
  ))
  detail <- data.frame(
    calibration_row = seq_along(va), y = design$y[va], pred_mean = pred$mean,
    pred_sd = pred$sd, realized_acrps = score, stringsAsFactors = FALSE
  )
  list(summary = summary, detail = detail)
}

app_joint_shared_write_manifest <- function(dir, paths, filename = "artifact_manifest.csv") {
  labels <- names(paths)
  if (is.null(labels) || length(labels) != length(paths) || any(!nzchar(labels))) {
    stop("Manifest paths must have nonempty unique labels.", call. = FALSE)
  }
  paths <- normalizePath(unname(paths), mustWork = TRUE)
  root <- paste0(normalizePath(dir, mustWork = TRUE), .Platform$file.sep)
  relative <- ifelse(startsWith(paths, root), substring(paths, nchar(root) + 1L), paths)
  out <- data.frame(label = labels, relative_path = relative,
    size_bytes = as.numeric(file.info(paths)$size), sha256 = vapply(paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  app_write_csv(out, file.path(dir, filename))
}

app_joint_shared_verify_manifest <- function(dir, manifest = file.path(dir, "artifact_manifest.csv")) {
  x <- app_read_csv(manifest)
  app_check_required_columns(x, c("label", "relative_path", "size_bytes", "sha256"), "shared-backbone manifest")
  rows <- lapply(seq_len(nrow(x)), function(ii) {
    path <- file.path(dir, x$relative_path[[ii]])
    observed_size <- if (file.exists(path)) as.numeric(file.info(path)$size) else NA_real_
    observed_sha <- if (file.exists(path)) app_sha256_file(path) else NA_character_
    data.frame(label = x$label[[ii]], exists = file.exists(path),
      size_match = isTRUE(all.equal(observed_size, as.numeric(x$size_bytes[[ii]]))),
      sha256_match = identical(observed_sha, as.character(x$sha256[[ii]])), stringsAsFactors = FALSE)
  })
  out <- app_bind_rows_fill(rows)
  out$verified <- out$exists & out$size_match & out$sha256_match
  out
}

app_joint_shared_git_state <- function() {
  get <- function(args) trimws(system2("git", args, stdout = TRUE, stderr = TRUE))
  data.frame(
    branch = get(c("rev-parse", "--abbrev-ref", "HEAD")),
    head = get(c("rev-parse", "HEAD")),
    upstream = tryCatch(get(c("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")), error = function(e) ""),
    stringsAsFactors = FALSE
  )
}

app_joint_shared_prepare_ridge <- function(
  out_dir = app_joint_shared_default_root(),
  authority_registry = app_joint_shared_default_authority_registry(),
  scenario_id = NULL
) {
  contract <- app_joint_shared_read_contract()
  scenario_id <- as.character(scenario_id %||% contract$pilot_scenario)
  scenarios <- app_joint_shared_read_scenarios()
  selected_scenario <- scenarios[scenarios$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(selected_scenario) != 1L || !isTRUE(selected_scenario$enabled[[1L]]) ||
      !identical(selected_scenario$selection_unit[[1L]], "scenario_specific")) {
    stop("Requested pilot scenario is not uniquely enabled under the scenario-specific contract.", call. = FALSE)
  }
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty shared-backbone output directory.", call. = FALSE)
  }
  app_ensure_dir(out_dir); app_ensure_dir(file.path(out_dir, "fixtures")); app_ensure_dir(file.path(out_dir, "workers"))
  authority_registry <- normalizePath(authority_registry, mustWork = TRUE)
  authority_manifest <- file.path(dirname(authority_registry), "artifact_manifest.csv")
  authority_registry_sha <- app_sha256_file(authority_registry)
  authority_manifest_sha <- app_sha256_file(authority_manifest)
  if (!identical(authority_registry_sha, contract$authority_registry_sha256) ||
      !identical(authority_manifest_sha, contract$authority_manifest_sha256)) {
    stop("Authoritative Phase180 source hashes do not match the frozen contract.", call. = FALSE)
  }
  parent <- app_read_csv(authority_manifest)
  parent_row <- parent[parent$relative_path == basename(authority_registry), , drop = FALSE]
  if (nrow(parent_row) != 1L || !identical(as.character(parent_row$sha256[[1L]]), authority_registry_sha)) {
    stop("Authoritative registry is not verified by its parent manifest.", call. = FALSE)
  }
  authority <- app_read_csv(authority_registry)
  built <- app_joint_shared_candidates(scenario_id, authority, contract$novel_candidate_count)
  registry <- app_joint_qdesn_load_simulation_registry()
  row <- registry[registry$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Pilot scenario is missing from the DGP registry.", call. = FALSE)
  seeds <- contract$calibration_seed_base + seq_len(contract$calibration_replicates) - 1L
  fixture_paths <- character(length(seeds))
  for (ii in seq_along(seeds)) {
    fixture <- app_joint_shared_fixture_for_seed(row, seeds[[ii]], paste0("shared_backbone_inner_calibration_rep", ii))
    fixture <- app_joint_shared_selector_fixture(fixture, contract)
    fixture_paths[[ii]] <- file.path(out_dir, "fixtures", sprintf("calibration_rep_%02d.rds", ii))
    saveRDS(fixture, fixture_paths[[ii]], version = 3L, compress = "xz")
  }
  jobs <- merge(
    built$candidates,
    data.frame(replicate_id = seq_along(seeds), dgp_seed = seeds, fixture_path = fixture_paths, stringsAsFactors = FALSE),
    by = NULL
  )
  jobs$worker_id <- seq_len(nrow(jobs))
  jobs <- jobs[, c("worker_id", setdiff(names(jobs), "worker_id")), drop = FALSE]
  split <- data.frame(
    scenario_id = scenario_id, desn_washout_rows = contract$desn_washout_rows,
    fit_rows = contract$fit_rows, inner_training_rows = contract$inner_training_rows,
    inner_calibration_rows = contract$inner_calibration_rows,
    protected_validation_rows = contract$protected_validation_rows,
    protected_rows_available_to_selector = 0L,
    split_rule = "chronological_350_train_150_calibration_within_500_fit_rows",
    stringsAsFactors = FALSE
  )
  api <- data.frame(
    component = c("gaussian_ridge", "gaussian_rhs_vb", "reservoir_generator"),
    function_name = c("app_glofas_normal_ridge_fit", "app_glofas_normal_rhs_fit", "app_qdesn_generate_article_reservoir"),
    available = c(exists("app_glofas_normal_ridge_fit"), exists("app_glofas_normal_rhs_fit"), exists("app_qdesn_generate_article_reservoir")),
    source_policy = c("integrated_generic_statistical_core", "integrated_generic_statistical_core", "integrated_generic_statistical_core"),
    stringsAsFactors = FALSE
  )
  if (!all(api$available)) stop("Required integrated Gaussian/reservoir APIs are unavailable.", call. = FALSE)
  source_verification <- data.frame(
    source = c("phase180_selected_cell_registry", "phase180_artifact_manifest"),
    path = c(authority_registry, authority_manifest),
    expected_sha256 = c(contract$authority_registry_sha256, contract$authority_manifest_sha256),
    observed_sha256 = c(authority_registry_sha, authority_manifest_sha),
    verified = c(identical(authority_registry_sha, contract$authority_registry_sha256),
      identical(authority_manifest_sha, contract$authority_manifest_sha256)),
    stringsAsFactors = FALSE
  )
  cpu_plan <- data.frame(
    stage = c("ridge", "gaussian_rhs_vb"),
    expected_workers = c(nrow(jobs), contract$advance_count * length(contract$rhs_tau0_grid) * contract$calibration_replicates),
    concurrent_workers = contract$max_workers,
    blas_threads_per_worker = contract$blas_threads,
    nice_level = contract$nice_level,
    protected_rows_available = 0L,
    stringsAsFactors = FALSE
  )
  git_state <- app_joint_shared_git_state()
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(out_dir, "frozen_contract.csv")),
    frozen_scenario_registry = app_write_csv(scenarios, file.path(out_dir, "frozen_scenario_registry.csv")),
    candidate_registry = app_write_csv(built$candidates, file.path(out_dir, "ridge_candidate_registry.csv")),
    candidate_universe = app_write_csv(built$universe, file.path(out_dir, "candidate_universe.csv")),
    authority_audit = app_write_csv(built$authority_audit, file.path(out_dir, "authoritative_design_anchor_registry.csv")),
    observational_split = app_write_csv(split, file.path(out_dir, "observational_split_contract.csv")),
    api_preflight = app_write_csv(api, file.path(out_dir, "gaussian_api_preflight.csv")),
    source_verification = app_write_csv(source_verification, file.path(out_dir, "source_manifest_verification.csv")),
    cpu_plan = app_write_csv(cpu_plan, file.path(out_dir, "cpu_memory_plan.csv")),
    git_state = app_write_csv(git_state, file.path(out_dir, "source_git_state.csv")),
    worker_plan = app_write_csv(jobs, file.path(out_dir, "ridge_worker_plan.csv")),
    authority_snapshot = app_write_csv(authority, file.path(out_dir, "authority_registry_snapshot.csv"))
  )
  fixture_manifest <- data.frame(
    replicate_id = seq_along(seeds), dgp_seed = seeds,
    relative_path = file.path("fixtures", basename(fixture_paths)),
    size_bytes = as.numeric(file.info(fixture_paths)$size),
    sha256 = vapply(fixture_paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE
  )
  files <- c(files, fixture_manifest = app_write_csv(fixture_manifest, file.path(out_dir, "fixture_manifest.csv")))
  readiness <- data.frame(
    status = "READY_TO_LAUNCH_RIDGE", scenario_id = scenario_id,
    candidates = nrow(built$candidates), novel_candidates = sum(built$candidates$candidate_role == "novel_shared_backbone"),
    authority_anchors = sum(built$candidates$candidate_role == "mandatory_authority_anchor"),
    calibration_replicates = length(seeds), expected_workers = nrow(jobs), max_concurrent_workers = contract$max_workers,
    selection_window = "observational_fit_only", protected_selection_rows = 0L,
    stringsAsFactors = FALSE
  )
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(out_dir, "launch_readiness.csv")))
  readme <- c(
    "# JOINT shared-backbone Regime Shift pilot",
    "",
    "This packet contains only observational-window Gaussian screening artifacts.",
    "The persisted selector fixtures contain 500 washout and 500 fit rows; protected forecast rows are absent.",
    "",
    "```bash",
    sprintf("bash application/scripts/launch_joint_qdesn_shared_backbone_pipeline.sh %s", out_dir),
    "```"
  )
  writeLines(readme, file.path(out_dir, "README.md"))
  files <- c(files, readme = file.path(out_dir, "README.md"))
  app_joint_shared_write_manifest(out_dir, files)
  list(out_dir = out_dir, jobs = jobs, readiness = readiness)
}

app_joint_shared_select_top30 <- function(aggregate, advance_count) {
  passing <- aggregate[aggregate$hard_gate_status == "pass", , drop = FALSE]
  passing <- passing[order(passing$calibration_acrps_mean,
    passing$calibration_acrps_between_rep_sd,
    passing$calibration_exact_gaussian_crps_mean,
    passing$candidate_id), , drop = FALSE]
  if (nrow(passing) < advance_count) stop("Fewer than the required number of ridge designs passed hard gates.", call. = FALSE)
  passing$pure_metric_rank <- seq_len(nrow(passing))
  pure <- head(passing, advance_count)
  mandatory <- passing$candidate_role == "mandatory_authority_anchor"
  selected <- pure
  missing <- passing[mandatory & !passing$candidate_id %in% selected$candidate_id, , drop = FALSE]
  if (nrow(missing)) {
    removable <- which(selected$candidate_role != "mandatory_authority_anchor")
    if (length(removable) < nrow(missing)) stop("Too many mandatory anchors for the top-30 contract.", call. = FALSE)
    selected <- selected[-tail(removable, nrow(missing)), , drop = FALSE]
    selected <- rbind(selected, missing)
  }
  selected <- selected[order(selected$calibration_acrps_mean,
    selected$calibration_acrps_between_rep_sd,
    selected$calibration_exact_gaussian_crps_mean,
    selected$candidate_id), , drop = FALSE]
  selected$advancement_rank <- seq_len(nrow(selected))
  if (nrow(selected) != advance_count || !all(passing$candidate_id[mandatory] %in% selected$candidate_id)) {
    stop("Authority-protected top-30 selection contract failed.", call. = FALSE)
  }
  list(passing = passing, pure = pure, selected = selected)
}

app_joint_shared_run_ridge_worker <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); worker_id <- as.integer(worker_id)
  jobs <- app_read_csv(file.path(root, "ridge_worker_plan.csv"))
  row <- jobs[jobs$worker_id == worker_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Ridge worker_id is not unique.", call. = FALSE)
  out <- file.path(root, "workers", sprintf("worker_%04d", worker_id)); app_ensure_dir(out)
  done <- file.path(out, "DONE")
  if (file.exists(done) && file.exists(file.path(out, "summary.csv"))) return(invisible(out))
  contract <- app_joint_shared_read_contract(file.path(root, "frozen_contract.csv"))
  fixture <- readRDS(as.character(row$fixture_path[[1L]]))
  started <- Sys.time()
  result <- tryCatch(app_joint_shared_score_ridge(fixture, row, contract), error = function(e) e)
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED")); return(invisible(out))
  }
  app_write_csv(result$summary, file.path(out, "summary.csv"))
  app_write_csv(result$detail, file.path(out, "calibration_detail.csv"))
  writeLines("completed", done)
  invisible(out)
}

app_joint_shared_ridge_health <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  jobs <- app_read_csv(file.path(root, "ridge_worker_plan.csv"))
  dirs <- file.path(root, "workers", sprintf("worker_%04d", jobs$worker_id))
  completed <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "summary.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(expected = nrow(jobs), completed = sum(completed), failed = sum(failed),
    remaining = sum(!completed & !failed), completion_fraction = mean(completed),
    status = if (all(completed)) "complete" else if (any(failed)) "failed" else "running", stringsAsFactors = FALSE)
}

app_joint_shared_finalize_ridge <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); health <- app_joint_shared_ridge_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Ridge screening is not complete and failure-free.", call. = FALSE)
  }
  files <- list.files(file.path(root, "workers"), pattern = "summary[.]csv$", recursive = TRUE, full.names = TRUE)
  scores <- app_bind_rows_fill(lapply(files, app_read_csv))
  numeric_cols <- c("calibration_acrps_mean", "calibration_exact_gaussian_crps", "calibration_oracle_quantile_mae",
    "condition_number", "state_saturation_fraction", "runtime_seconds")
  for (nm in intersect(numeric_cols, names(scores))) scores[[nm]] <- as.numeric(scores[[nm]])
  if (nrow(scores) != health$expected[[1L]] || any(scores$status != "completed") || any(!is.finite(scores$calibration_acrps_mean))) {
    stop("Collected ridge scores violate completion/finite-score gates.", call. = FALSE)
  }
  groups <- split(scores, scores$candidate_id)
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) data.frame(
    candidate_id = x$candidate_id[[1L]], candidate_role = x$candidate_role[[1L]], scenario_id = x$scenario_id[[1L]],
    architecture_signature = x$architecture_signature[[1L]], design_class = x$design_class[[1L]], D = x$D[[1L]],
    n = x$n[[1L]], n_tilde = x$n_tilde[[1L]], retained_state_budget = x$retained_state_budget[[1L]],
    width_shape = x$width_shape[[1L]], state_reduction = x$state_reduction[[1L]], alpha = x$alpha[[1L]],
    rho = x$rho[[1L]], pi_w = x$pi_w[[1L]], pi_in = x$pi_in[[1L]], input_scale = x$input_scale[[1L]],
    reservoir_seed = x$reservoir_seed[[1L]], replicate_count = nrow(x),
    hard_gate_status = if (all(x$hard_gate_status == "pass")) "pass" else "fail",
    calibration_acrps_mean = mean(x$calibration_acrps_mean),
    calibration_acrps_between_rep_sd = stats::sd(x$calibration_acrps_mean),
    calibration_exact_gaussian_crps_mean = mean(x$calibration_exact_gaussian_crps),
    maximum_condition_number = max(x$condition_number), maximum_state_saturation = max(x$state_saturation_fraction),
    runtime_seconds_total = sum(x$runtime_seconds), stringsAsFactors = FALSE
  )))
  contract <- app_joint_shared_read_contract(file.path(root, "frozen_contract.csv"))
  frontier <- app_joint_shared_select_top30(aggregate, contract$advance_count)
  pure <- frontier$pure
  selected <- frontier$selected
  app_write_csv(scores, file.path(root, "ridge_scores_by_replicate.csv"))
  app_write_csv(aggregate, file.path(root, "ridge_candidate_aggregate.csv"))
  app_write_csv(pure, file.path(root, "ridge_pure_metric_top30.csv"))
  app_write_csv(selected, file.path(root, "ridge_authority_protected_top30.csv"))
  rhs <- merge(selected, data.frame(rhs_tau0 = contract$rhs_tau0_grid, stringsAsFactors = FALSE), by = NULL)
  reps <- unique(app_read_csv(file.path(root, "ridge_worker_plan.csv"))[, c("replicate_id", "dgp_seed", "fixture_path")])
  rhs <- merge(rhs, reps, by = NULL); rhs$rhs_worker_id <- seq_len(nrow(rhs))
  rhs$rhs_candidate_id <- paste(rhs$candidate_id, paste0("tau0_", format(rhs$rhs_tau0, scientific = TRUE)), paste0("rep", rhs$replicate_id), sep = "__")
  app_write_csv(rhs, file.path(root, "rhs_worker_plan.csv"))
  app_write_csv(data.frame(status = "READY_TO_LAUNCH_RHS", expected_workers = nrow(rhs),
    max_concurrent_workers = contract$max_workers, protected_selection_rows = 0L, stringsAsFactors = FALSE),
    file.path(root, "rhs_launch_readiness.csv"))
  app_write_csv(app_joint_shared_ridge_health(root), file.path(root, "ridge_final_health.csv"))
  list(aggregate = aggregate, selected = selected, rhs_jobs = rhs)
}

app_joint_shared_ridge_warm_start <- function(fit, candidate, design) {
  warm <- list(type = "glofas_normal_part1_ridge_warm_start", version = "0.1",
    candidate_id = as.character(candidate$candidate_id[[1L]]),
    design = list(colnames = colnames(design$X)),
    fit = list(beta_mean = fit$beta_mean, beta_var_diag = fit$beta_var_diag,
      sigma_a = fit$sigma_a, sigma_b = fit$sigma_b, sigma2_mean = fit$sigma2_mean,
      ridge_tau2 = fit$ridge_tau2, intercept_var = fit$intercept_var,
      n_train = fit$n_train, p = fit$p))
  class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
  warm
}

app_joint_shared_run_rhs_worker <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); jobs <- app_read_csv(file.path(root, "rhs_worker_plan.csv"))
  row <- jobs[jobs$rhs_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("RHS worker_id is not unique.", call. = FALSE)
  out <- file.path(root, "rhs_workers", sprintf("worker_%04d", as.integer(worker_id))); app_ensure_dir(out)
  if (file.exists(file.path(out, "DONE")) && file.exists(file.path(out, "summary.csv"))) return(invisible(out))
  contract <- app_joint_shared_read_contract(file.path(root, "frozen_contract.csv")); fixture <- readRDS(row$fixture_path[[1L]])
  started <- Sys.time()
  result <- tryCatch({
    design <- app_joint_shared_design(fixture, row, contract); tr <- design$train_local; va <- design$calibration_local
    ridge <- app_glofas_normal_ridge_fit(design$X[tr, , drop = FALSE], design$y[tr], contract$ridge_tau2,
      contract$intercept_variance, contract$sigma_shape, contract$sigma_rate)
    warm <- app_joint_shared_ridge_warm_start(ridge, row, design)
    fit <- app_glofas_normal_rhs_fit(design$X[tr, , drop = FALSE], design$y[tr], warm,
      tau0 = row$rhs_tau0[[1L]], max_iter = contract$rhs_max_iter,
      min_iter = contract$rhs_min_iter, tol = contract$rhs_tolerance)
    pred <- app_glofas_normal_predict(fit, design$X[va, , drop = FALSE], chunk_size = 64L)
    qhat <- outer(pred$sd, stats::qnorm(design$tau), "*") + pred$mean
    score <- app_joint_shared_acrps(design$y[va], qhat, design$tau)
    summary <- data.frame(rhs_worker_id = row$rhs_worker_id[[1L]], rhs_candidate_id = row$rhs_candidate_id[[1L]],
      candidate_id = row$candidate_id[[1L]], replicate_id = row$replicate_id[[1L]], rhs_tau0 = row$rhs_tau0[[1L]],
      status = "completed", calibration_acrps_mean = mean(score),
      calibration_exact_gaussian_crps = mean(app_glofas_normal_crps(design$y[va], pred$mean, pred$sd)),
      converged = fit$converged, iterations = fit$iterations, final_delta = fit$final_delta,
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE)
    list(summary = summary, trace = fit$trace)
  }, error = function(e) e)
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result), stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED")); return(invisible(out))
  }
  app_write_csv(result$summary, file.path(out, "summary.csv"))
  app_write_csv(result$trace, file.path(out, "vb_trace.csv"))
  writeLines("completed", file.path(out, "DONE")); invisible(out)
}

app_joint_shared_finalize_rhs <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_shared_rhs_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Gaussian RHS screening is not complete and failure-free.", call. = FALSE)
  }
  files <- list.files(file.path(root, "rhs_workers"), pattern = "summary[.]csv$", recursive = TRUE, full.names = TRUE)
  scores <- app_bind_rows_fill(lapply(files, app_read_csv))
  plan <- app_read_csv(file.path(root, "rhs_worker_plan.csv"))
  if (nrow(scores) != nrow(plan) || any(scores$status != "completed") ||
      any(!is.finite(scores$calibration_acrps_mean))) {
    stop("Collected RHS scores violate completion/finite-score gates.", call. = FALSE)
  }
  idx <- match(scores$rhs_worker_id, plan$rhs_worker_id)
  if (anyNA(idx) || anyDuplicated(scores$rhs_worker_id)) stop("RHS worker results do not match the frozen plan.", call. = FALSE)
  missing_cols <- setdiff(names(plan), names(scores))
  scores <- cbind(scores, plan[idx, missing_cols, drop = FALSE])
  groups <- split(scores, paste(scores$candidate_id, format(scores$rhs_tau0, scientific = TRUE), sep = "__"))
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) data.frame(
    scenario_id = x$scenario_id[[1L]], candidate_id = x$candidate_id[[1L]],
    candidate_role = x$candidate_role[[1L]], architecture_signature = x$architecture_signature[[1L]],
    design_class = x$design_class[[1L]], D = x$D[[1L]], n = x$n[[1L]], n_tilde = x$n_tilde[[1L]],
    retained_state_budget = x$retained_state_budget[[1L]], width_shape = x$width_shape[[1L]],
    state_reduction = x$state_reduction[[1L]], alpha = x$alpha[[1L]], rho = x$rho[[1L]],
    pi_w = x$pi_w[[1L]], pi_in = x$pi_in[[1L]], input_scale = x$input_scale[[1L]],
    reservoir_seed = x$reservoir_seed[[1L]], rhs_tau0 = x$rhs_tau0[[1L]],
    replicate_count = nrow(x), calibration_acrps_mean = mean(x$calibration_acrps_mean),
    calibration_acrps_between_rep_sd = stats::sd(x$calibration_acrps_mean),
    calibration_exact_gaussian_crps_mean = mean(x$calibration_exact_gaussian_crps),
    convergence_fraction = mean(app_as_bool_vec(x$converged)), maximum_final_delta = max(x$final_delta),
    mean_iterations = mean(x$iterations), runtime_seconds_total = sum(x$runtime_seconds),
    stringsAsFactors = FALSE
  )))
  aggregate <- aggregate[order(aggregate$calibration_acrps_mean,
    aggregate$calibration_acrps_between_rep_sd,
    aggregate$calibration_exact_gaussian_crps_mean,
    -aggregate$convergence_fraction,
    aggregate$candidate_id,
    aggregate$rhs_tau0), , drop = FALSE]
  aggregate$selection_rank <- seq_len(nrow(aggregate))
  selected <- aggregate[1L, , drop = FALSE]
  parity <- aggregate[aggregate$candidate_role == "mandatory_authority_anchor", , drop = FALSE]
  parity <- parity[order(parity$calibration_acrps_mean, parity$rhs_tau0), , drop = FALSE]
  parity <- parity[1L, , drop = FALSE]
  selected$parity_candidate_id <- parity$candidate_id[[1L]]
  selected$parity_best_tau0 <- parity$rhs_tau0[[1L]]
  selected$parity_calibration_acrps_mean <- parity$calibration_acrps_mean[[1L]]
  selected$absolute_acrps_gain_vs_parity <- parity$calibration_acrps_mean[[1L]] - selected$calibration_acrps_mean[[1L]]
  selected$relative_acrps_gain_vs_parity <- selected$absolute_acrps_gain_vs_parity / parity$calibration_acrps_mean[[1L]]
  selected$selection_window <- "observational_fit_only_350_train_150_calibration"
  selected$protected_rows_used_for_selection <- 0L
  selected$next_stage <- "freeze_full_500_row_design_then_fit_six_model_vb_comparison"
  decision <- data.frame(
    status = "SHARED_BACKBONE_SELECTED_NOT_YET_QUANTILE_FIT",
    scenario_id = selected$scenario_id,
    selected_candidate_id = selected$candidate_id,
    selected_rhs_tau0 = selected$rhs_tau0,
    selected_is_authority_anchor = selected$candidate_role == "mandatory_authority_anchor",
    selected_acrps = selected$calibration_acrps_mean,
    parity_acrps = parity$calibration_acrps_mean,
    absolute_gain_vs_parity = selected$absolute_acrps_gain_vs_parity,
    all_rhs_workers_complete = TRUE,
    any_worker_failure = FALSE,
    protected_rows_used_for_selection = 0L,
    stringsAsFactors = FALSE
  )
  outputs <- c(
    rhs_scores = app_write_csv(scores, file.path(root, "rhs_scores_by_replicate.csv")),
    rhs_aggregate = app_write_csv(aggregate, file.path(root, "rhs_candidate_aggregate.csv")),
    selected_backbone = app_write_csv(selected, file.path(root, "selected_shared_backbone.csv")),
    decision = app_write_csv(decision, file.path(root, "shared_backbone_selection_decision.csv")),
    rhs_health = app_write_csv(health, file.path(root, "rhs_final_health.csv"))
  )
  app_joint_shared_write_manifest(root, outputs, filename = "final_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, file.path(root, "final_artifact_manifest.csv"))
  if (!all(verification$verified)) stop("Final shared-backbone artifact manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "final_manifest_verification.csv"))
  list(scores = scores, aggregate = aggregate, selected = selected, decision = decision)
}

app_joint_shared_rhs_health <- function(root) {
  jobs <- app_read_csv(file.path(root, "rhs_worker_plan.csv")); dirs <- file.path(root, "rhs_workers", sprintf("worker_%04d", jobs$rhs_worker_id))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "summary.csv")); fail <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(jobs), completed = sum(done), failed = sum(fail), remaining = sum(!done & !fail),
    completion_fraction = mean(done), status = if (all(done)) "complete" else if (any(fail)) "failed" else "running", stringsAsFactors = FALSE)
}
