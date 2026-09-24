# Orchestration and score-packet helpers for recursive mean-design forecasts.

app_joint_recursive_contract_path <- function() {
  app_path("application/config/joint_qdesn_recursive_mean_forecast_contract_v1.csv")
}

app_joint_recursive_read_contract <- function(
  path = app_joint_recursive_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "recursive mean-design forecast contract")
  if (anyDuplicated(tab$name)) stop("Recursive contract names must be unique.", call. = FALSE)
  get <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing recursive contract field '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  nums <- function(name) as.numeric(strsplit(get(name), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    source_inventory_sha256 = get("source_inventory_sha256"),
    source_inventory_files = as.integer(get("source_inventory_files")),
    source_inventory_bytes = as.numeric(get("source_inventory_bytes")),
    tau = nums("tau_grid"),
    weights = nums("trapezoidal_weights"),
    origins = as.integer(get("origins")),
    horizons = as.integer(get("horizons")),
    score_rows = as.integer(get("score_rows")),
    oracle_paths_per_shard = as.integer(get("oracle_paths_per_shard")),
    oracle_primary_shards = as.integer(get("oracle_primary_shards")),
    oracle_split_tolerance = as.numeric(get("oracle_split_tolerance")),
    oracle_horizon1_tolerance = as.numeric(get("oracle_horizon1_tolerance")),
    state_draws = as.integer(get("state_draws")),
    state_draws_extension = as.integer(get("state_draws_extension")),
    mcmc_state_draws_per_chain = as.integer(get("mcmc_state_draws_per_chain")),
    mcmc_score_draws_per_chain = as.integer(get("mcmc_score_draws_per_chain")),
    vb_score_draws = as.integer(get("vb_score_draws")),
    score_chunk_size = as.integer(get("score_chunk_size")),
    mean_design_rms_gate = as.numeric(get("mean_design_rms_gate")),
    mean_design_score_gate = as.numeric(get("mean_design_score_gate")),
    tail_sensitivity_gate = as.numeric(get("tail_sensitivity_gate")),
    inverse_cdf_tail_rule = get("inverse_cdf_tail_rule"),
    workers = as.integer(get("workers")),
    rscript = get("rscript")
  )
  expected_tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  expected_weights <- c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)
  if (!identical(out$version, "joint_qdesn_recursive_mean_forecast_v1") ||
      !identical(out$tau, expected_tau) ||
      !identical(out$weights, expected_weights) ||
      out$origins != 33L || out$horizons != 30L || out$score_rows != 990L ||
      out$oracle_primary_shards != 16L || out$workers != 8L ||
      out$mcmc_score_draws_per_chain != 750L || out$vb_score_draws != 4000L ||
      !identical(out$inverse_cdf_tail_rule, "endpoint_clamp")) {
    stop("Recursive mean-design forecast contract is malformed.", call. = FALSE)
  }
  out
}

app_joint_recursive_dirs <- function(root) {
  root <- normalizePath(root, mustWork = FALSE)
  list(
    root = root,
    oracle_shards = file.path(root, "oracle_shards"),
    oracle_banks = file.path(root, "oracle_banks"),
    cells = file.path(root, "cells"),
    final = file.path(root, "final_packet"),
    logs = file.path(root, "logs")
  )
}

app_joint_recursive_source_files <- function(source_root) {
  c(
    transfer_inventory = file.path(source_root, "score_packet", "transfer_inventory.csv"),
    model_cell_plan = file.path(source_root, "model_cell_plan.csv"),
    mcmc_worker_plan = file.path(source_root, "mcmc_worker_plan.csv"),
    selected_backbones = file.path(source_root, "imported_selected_backbones.csv"),
    vb_initializer_manifest = file.path(source_root, "vb_initializer_manifest.csv"),
    mcmc_health = file.path(source_root, "mcmc_health_summary.csv"),
    vb_health = file.path(source_root, "vb_health_summary.csv")
  )
}

app_joint_recursive_verify_source <- function(source_root, contract) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  files <- app_joint_recursive_source_files(source_root)
  if (any(!file.exists(files))) stop("Recursive source runtime is incomplete.", call. = FALSE)
  inventory_sha <- app_sha256_file(files[["transfer_inventory"]])
  if (!identical(inventory_sha, contract$source_inventory_sha256)) {
    stop("Recursive source transfer-inventory hash differs.", call. = FALSE)
  }
  inventory <- app_read_csv(files[["transfer_inventory"]])
  app_check_required_columns(inventory, c("relative_path", "size_bytes", "sha256"),
    "recursive source transfer inventory")
  paths <- file.path(source_root, inventory$relative_path)
  exists <- file.exists(paths)
  sizes <- rep(NA_real_, length(paths))
  hashes <- rep(NA_character_, length(paths))
  sizes[exists] <- file.info(paths[exists])$size
  hashes[exists] <- vapply(paths[exists], app_sha256_file, character(1L))
  verified <- exists & sizes == inventory$size_bytes &
    tolower(hashes) == tolower(inventory$sha256)
  audit <- data.frame(
    relative_path = inventory$relative_path,
    expected_size_bytes = inventory$size_bytes,
    observed_size_bytes = sizes,
    expected_sha256 = inventory$sha256,
    observed_sha256 = hashes,
    verified = verified,
    stringsAsFactors = FALSE
  )
  if (nrow(inventory) != contract$source_inventory_files ||
      sum(inventory$size_bytes) != contract$source_inventory_bytes ||
      any(!verified)) {
    stop("Recursive source transfer inventory did not verify.", call. = FALSE)
  }
  audit
}

app_joint_recursive_find_scenario_file <- function(directory, scenario_id) {
  paths <- list.files(directory, pattern = "[.]rds$", full.names = TRUE)
  matches <- paths[grepl(paste0("_", scenario_id, "[.]rds$"), basename(paths))]
  if (length(matches) != 1L) {
    stop(sprintf("Expected one source RDS for scenario '%s' in %s.", scenario_id, directory), call. = FALSE)
  }
  normalizePath(matches, mustWork = TRUE)
}

app_joint_recursive_build_plans <- function(source_root, contract) {
  cells <- app_read_csv(file.path(source_root, "model_cell_plan.csv"))
  selected <- app_read_csv(file.path(source_root, "imported_selected_backbones.csv"))
  if (nrow(cells) != 32L || length(unique(cells$scenario_id)) != 8L ||
      nrow(selected) != 8L) stop("Recursive source cell cardinality differs.", call. = FALSE)
  cells$design_relative_path <- vapply(cells$scenario_id, function(id) {
    file.path("designs", basename(app_joint_recursive_find_scenario_file(
      file.path(source_root, "designs"), id
    )))
  }, character(1L))
  cells$fixture_relative_path <- vapply(cells$scenario_id, function(id) {
    file.path("fixtures", basename(app_joint_recursive_find_scenario_file(
      file.path(source_root, "fixtures"), id
    )))
  }, character(1L))
  cells$initializer_relative_path <- file.path("initializers", paste0(cells$model_cell_id, ".rds"))
  if (any(!file.exists(file.path(source_root, cells$initializer_relative_path)))) {
    stop("Recursive source initializers are incomplete.", call. = FALSE)
  }
  method <- rep(c("vb", "mcmc"), each = nrow(cells))
  cell_index <- rep(seq_len(nrow(cells)), times = 2L)
  plan <- cells[cell_index, , drop = FALSE]
  plan$inference_method <- method
  plan$worker_id <- seq_len(nrow(plan))
  plan$state_seed <- 202609240L + 1000L * plan$worker_id
  plan$score_seed <- 202609241L + 1000L * plan$worker_id
  scenario_order <- match(plan$scenario_id, unique(cells$scenario_id))
  plan$uniform_seed <- 202609242L + 10000L * scenario_order
  plan$sentinel <- FALSE
  sentinel_keys <- c(
    "asymmetric_laplace_tail__joint_qdesn_rhs__mcmc",
    "nonlinear_reservoir_friendly__joint_exqdesn_rhs__vb",
    "regime_shift__qdesn_rhs_independent__mcmc"
  )
  key <- paste(plan$model_cell_id, plan$inference_method, sep = "__")
  plan$sentinel[key %in% sentinel_keys] <- TRUE
  if (sum(plan$sentinel) != 3L) stop("Recursive sentinel plan is malformed.", call. = FALSE)

  oracle_primary <- expand.grid(
    scenario_id = unique(cells$scenario_id), shard_id = 1:2,
    stringsAsFactors = FALSE
  )
  oracle_extension <- expand.grid(
    scenario_id = unique(cells$scenario_id), shard_id = 3:4,
    stringsAsFactors = FALSE
  )
  oracle_primary$is_primary <- TRUE
  oracle_extension$is_primary <- FALSE
  oracle <- rbind(oracle_primary, oracle_extension)
  oracle <- oracle[order(!app_as_bool_vec(oracle$is_primary),
    match(oracle$scenario_id, unique(cells$scenario_id)), oracle$shard_id), , drop = FALSE]
  oracle$worker_id <- seq_len(nrow(oracle))
  oracle$fixture_relative_path <- vapply(oracle$scenario_id, function(id) {
    file.path("fixtures", basename(app_joint_recursive_find_scenario_file(
      file.path(source_root, "fixtures"), id
    )))
  }, character(1L))
  oracle$design_relative_path <- vapply(oracle$scenario_id, function(id) {
    file.path("designs", basename(app_joint_recursive_find_scenario_file(
      file.path(source_root, "designs"), id
    )))
  }, character(1L))
  oracle$seed <- 202609243L + 10000L * match(oracle$scenario_id, unique(cells$scenario_id)) +
    100L * oracle$shard_id
  list(cells = plan, oracle = oracle, selected = selected)
}

app_joint_recursive_select_block <- function(draws, block) {
  cols <- grep(paste0("^", block, "_[0-9]{4}$"), names(draws), value = TRUE)
  cols <- cols[order(as.integer(sub(paste0("^", block, "_"), "", cols)))]
  as.matrix(draws[, cols, drop = FALSE])
}

app_joint_recursive_couple_independent <- function(beta, alpha, p, seed) {
  beta <- as.matrix(beta); alpha <- as.matrix(alpha)
  K <- ncol(alpha); n <- nrow(alpha)
  if (ncol(beta) != K * p) stop("Independent draw blocks are malformed.", call. = FALSE)
  out_beta <- beta; out_alpha <- alpha
  for (k in seq_len(K)) {
    set.seed(as.integer((seed + 7919L * k) %% .Machine$integer.max))
    index <- sample.int(n)
    cols <- ((k - 1L) * p + 1L):(k * p)
    out_beta[, cols] <- beta[index, cols, drop = FALSE]
    out_alpha[, k] <- alpha[index, k]
  }
  list(beta = out_beta, alpha = out_alpha)
}

app_joint_recursive_mcmc_draws <- function(
  source_root, cell, n_per_chain, seed, use_all = FALSE
) {
  plan <- app_read_csv(file.path(source_root, "mcmc_worker_plan.csv"))
  jobs <- plan[plan$model_cell_id == cell$model_cell_id[[1L]], , drop = FALSE]
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (nrow(jobs) != 5L) stop("Recursive MCMC adapter requires five chains.", call. = FALSE)
  blocks <- lapply(seq_len(nrow(jobs)), function(index) {
    worker <- sprintf("worker_%04d", as.integer(jobs$worker_id[[index]]))
    path <- file.path(source_root, "mcmc_workers", worker, "posterior_draws.csv.gz")
    draws <- app_read_csv(path)
    beta <- app_joint_recursive_select_block(draws, "beta")
    alpha <- app_joint_recursive_select_block(draws, "alpha")
    selected <- if (isTRUE(use_all)) seq_len(nrow(beta)) else {
      app_joint_qdesn_postscore_even_indices(nrow(beta), n_per_chain)
    }
    beta <- beta[selected, , drop = FALSE]
    alpha <- alpha[selected, , drop = FALSE]
    if (identical(cell$fit_structure[[1L]], "independent")) {
      coupled <- app_joint_recursive_couple_independent(
        beta, alpha, as.integer(cell$p[[1L]]), seed + 1009L * index
      )
      beta <- coupled$beta; alpha <- coupled$alpha
    }
    list(
      beta = beta, alpha = alpha,
      chain_id = rep(as.integer(jobs$chain_id[[index]]), nrow(beta)),
      source_draw_index = selected
    )
  })
  list(
    beta = do.call(rbind, lapply(blocks, `[[`, "beta")),
    alpha = do.call(rbind, lapply(blocks, `[[`, "alpha")),
    chain_id = unlist(lapply(blocks, `[[`, "chain_id"), use.names = FALSE),
    source_draw_index = unlist(lapply(blocks, `[[`, "source_draw_index"), use.names = FALSE)
  )
}

app_joint_recursive_mvn_draws <- function(mean, covariance, n, seed) {
  covariance <- (as.matrix(covariance) + t(as.matrix(covariance))) / 2
  eig <- eigen(covariance, symmetric = TRUE)
  scale <- max(abs(eig$values), 1)
  material_negative <- min(eig$values) < -1e-8 * scale
  if (material_negative) stop("VB beta covariance is materially indefinite.", call. = FALSE)
  repaired <- pmax(eig$values, 0)
  set.seed(as.integer(seed))
  z <- matrix(stats::rnorm(as.integer(n) * length(mean)), nrow = as.integer(n))
  factor <- eig$vectors %*% diag(sqrt(repaired), nrow = length(repaired))
  draws <- sweep(z %*% t(factor), 2L, as.numeric(mean), "+")
  attr(draws, "covariance_repair") <- data.frame(
    min_eigenvalue = min(eig$values),
    clipped_eigenvalues = sum(eig$values < 0),
    material_negative = material_negative,
    stringsAsFactors = FALSE
  )
  draws
}

app_joint_recursive_vb_draws <- function(source_root, cell, n, seed) {
  fit <- readRDS(file.path(source_root, cell$initializer_relative_path[[1L]]))
  p <- as.integer(cell$p[[1L]]); K <- length(fit$tau)
  if (identical(cell$fit_structure[[1L]], "independent")) {
    beta <- matrix(NA_real_, nrow = n, ncol = p * K)
    repair <- vector("list", K)
    for (k in seq_len(K)) {
      one <- fit$fits[[k]]
      cols <- ((k - 1L) * p + 1L):(k * p)
      one_draws <- app_joint_recursive_mvn_draws(
        one$beta_mean, one$beta_cov, n, seed + 7919L * k
      )
      beta[, cols] <- one_draws
      repair[[k]] <- cbind(
        quantile_index = k,
        attr(one_draws, "covariance_repair")
      )
    }
  } else {
    beta <- app_joint_recursive_mvn_draws(fit$beta_mean, fit$beta_cov, n, seed)
    repair <- list(attr(beta, "covariance_repair"))
  }
  alpha <- matrix(rep(fit$alpha_mean, each = n), nrow = n, ncol = K)
  list(
    beta = beta, alpha = alpha,
    chain_id = rep(NA_integer_, n), source_draw_index = seq_len(n),
    covariance_repair = app_bind_rows_fill(repair),
    alpha_uncertainty_included = FALSE
  )
}

app_joint_recursive_contract_draw_rows <- function(q_raw, tau) {
  app_joint_qdesn_postscore_contract_rows(q_raw, tau)
}

app_joint_recursive_score_draws <- function(
  mean_design, beta, alpha, oracle, tau, weights, chunk_size,
  chain_id = NULL, source_draw_index = NULL
) {
  beta <- as.matrix(beta); alpha <- as.matrix(alpha)
  n_draw <- nrow(beta); n_time <- nrow(mean_design); p <- ncol(mean_design); K <- length(tau)
  if (ncol(beta) != p * K || nrow(alpha) != n_draw || ncol(alpha) != K) {
    stop("Final score draw dimensions differ.", call. = FALSE)
  }
  chain_id <- chain_id %||% rep(NA_integer_, n_draw)
  source_draw_index <- source_draw_index %||% seq_len(n_draw)
  chunks <- split(seq_len(n_draw), ceiling(seq_len(n_draw) / as.integer(chunk_size)))
  output <- lapply(chunks, function(index) {
    B <- length(index)
    q_raw <- matrix(NA_real_, nrow = n_time * B, ncol = K)
    for (k in seq_len(K)) {
      cols <- ((k - 1L) * p + 1L):(k * p)
      q <- mean_design %*% t(beta[index, cols, drop = FALSE])
      q <- sweep(q, 2L, alpha[index, k], "+")
      q_raw[, k] <- as.vector(q)
    }
    contracted <- app_joint_recursive_contract_draw_rows(q_raw, tau)
    dgp <- realized <- numeric(B)
    for (k in seq_len(K)) {
      qk <- matrix(contracted$q_contract[, k], nrow = n_time, ncol = B)
      dgp <- dgp + 2 * weights[[k]] * colMeans(
        app_joint_recursive_oracle_expected_matrix(oracle, qk, tau[[k]])
      )
      realized <- realized + 2 * weights[[k]] * colMeans(matrix(
        app_joint_qdesn_postscore_check_loss(
          rep(oracle$observed_y, B), as.vector(qk), tau[[k]]
        ), nrow = n_time, ncol = B
      ))
    }
    raw_cross <- pmax(contracted$raw_crossing, 0)
    contract_cross <- pmax(contracted$contract_crossing, 0)
    adjustment <- abs(contracted$q_contract - q_raw)
    data.frame(
      draw_index = index,
      chain_id = chain_id[index],
      source_draw_index = source_draw_index[index],
      origin_marginal_dgp_integrated_acrps = dgp,
      realized_acrps = realized,
      raw_crossing_pairs = colSums(matrix(
        rowSums(raw_cross > 1e-12), nrow = n_time, ncol = B
      )),
      contract_crossing_pairs = colSums(matrix(
        rowSums(contract_cross > 1e-12), nrow = n_time, ncol = B
      )),
      mean_abs_monotone_adjustment = colMeans(matrix(
        rowMeans(adjustment), nrow = n_time, ncol = B
      )),
      max_abs_monotone_adjustment = apply(matrix(
        apply(adjustment, 1L, max), nrow = n_time, ncol = B
      ), 2L, max),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(output)
}

app_joint_recursive_canonical_metrics <- function(
  design_matrix, beta, alpha, oracle, tau, weights
) {
  p <- ncol(design_matrix); K <- length(tau)
  q_raw <- matrix(NA_real_, nrow(design_matrix), K)
  for (k in seq_len(K)) {
    cols <- ((k - 1L) * p + 1L):(k * p)
    q_raw[, k] <- alpha[[k]] + as.vector(design_matrix %*% beta[cols])
  }
  contract <- app_joint_qdesn_apply_monotone_contract(q_raw, tau)
  score <- app_joint_recursive_oracle_point_score(
    oracle, contract$qhat_contract, tau, weights
  )
  error <- contract$qhat_contract - oracle$true_q
  data.frame(
    origin_marginal_dgp_integrated_acrps = score$origin_marginal_dgp_integrated_acrps,
    realized_acrps = score$realized_acrps,
    origin_marginal_oracle_quantile_mae = mean(abs(error)),
    origin_marginal_oracle_quantile_rmse = sqrt(mean(error^2)),
    raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
    mean_abs_monotone_adjustment = contract$mean_abs_adjustment,
    max_abs_monotone_adjustment = contract$max_abs_adjustment,
    stringsAsFactors = FALSE
  )
}

app_joint_recursive_draw_summary <- function(draws, inference_method) {
  score <- draws$origin_marginal_dgp_integrated_acrps
  out <- data.frame(
    posterior_score_mean = mean(score),
    posterior_score_median = stats::median(score),
    posterior_score_q025 = as.numeric(stats::quantile(score, 0.025, names = FALSE, type = 8)),
    posterior_score_q975 = as.numeric(stats::quantile(score, 0.975, names = FALSE, type = 8)),
    posterior_score_interval_width = as.numeric(diff(stats::quantile(
      score, c(0.025, 0.975), names = FALSE, type = 8
    ))),
    posterior_realized_acrps_mean = mean(draws$realized_acrps),
    raw_crossing_pairs = sum(draws$raw_crossing_pairs),
    contract_crossing_pairs = sum(draws$contract_crossing_pairs),
    score_mcse_mean = stats::sd(score) / sqrt(length(score)),
    stringsAsFactors = FALSE
  )
  if (identical(inference_method, "mcmc")) {
    split <- split(score, draws$chain_id)
    if (length(split) == 5L && length(unique(lengths(split))) == 1L) {
      diagnostic <- app_joint_exqdesn_modern_diagnostics(do.call(cbind, split))
      out$score_rank_rhat <- diagnostic$rank_rhat
      out$score_folded_rhat <- diagnostic$folded_rhat
      out$score_bulk_ess <- diagnostic$bulk_ess
      out$score_tail_ess <- diagnostic$tail_ess
      out$score_mcse_mean <- diagnostic$mcse_mean
    }
  } else {
    out$score_rank_rhat <- out$score_folded_rhat <- NA_real_
    out$score_bulk_ess <- out$score_tail_ess <- NA_real_
  }
  out
}

app_joint_recursive_cell_dir <- function(root, worker_id) {
  file.path(root, "cells", sprintf("worker_%04d", as.integer(worker_id)))
}

app_joint_recursive_atomic_manifest <- function(directory, paths) {
  app_joint_shared_write_manifest(directory, paths)
  manifest <- app_read_csv(file.path(directory, "artifact_manifest.csv"))
  if (!nrow(manifest)) stop("Recursive worker manifest is empty.", call. = FALSE)
  invisible(manifest)
}

app_joint_recursive_run_cell <- function(root, source_root, worker_id, contract) {
  dirs <- app_joint_recursive_dirs(root)
  plan <- app_read_csv(file.path(root, "cell_plan.csv"))
  cell <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(cell) != 1L) stop("Recursive forecast worker id is not unique.", call. = FALSE)
  final_dir <- app_joint_recursive_cell_dir(root, worker_id)
  done <- file.path(final_dir, "DONE")
  if (file.exists(done)) return(normalizePath(final_dir, mustWork = TRUE))
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  on.exit(if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

  design <- readRDS(file.path(source_root, cell$design_relative_path[[1L]]))
  fixture <- readRDS(file.path(source_root, cell$fixture_relative_path[[1L]]))
  selected <- app_read_csv(file.path(root, "selected_backbones.csv"))
  selected_row <- app_joint_recursive_selected_row(selected, cell$scenario_id[[1L]])
  teacher <- app_joint_recursive_teacher_forced_audit(design, fixture, selected_row)
  if (teacher$status[[1L]] != "pass") stop("Teacher-forced recursive design audit failed.", call. = FALSE)
  oracle_path <- file.path(dirs$oracle_banks, paste0(cell$scenario_id[[1L]], ".rds"))
  oracle <- readRDS(oracle_path)
  if (oracle$diagnostics$status[[1L]] != "pass") stop("Recursive DGP oracle is not frozen.", call. = FALSE)

  state_draws <- if (cell$inference_method[[1L]] == "mcmc") {
    app_joint_recursive_mcmc_draws(
      source_root, cell, contract$mcmc_state_draws_per_chain,
      cell$state_seed[[1L]], use_all = FALSE
    )
  } else app_joint_recursive_vb_draws(
    source_root, cell, contract$state_draws, cell$state_seed[[1L]]
  )
  set.seed(as.integer(cell$uniform_seed[[1L]]))
  uniforms <- matrix(stats::runif(nrow(state_draws$beta) * contract$score_rows),
    nrow = nrow(state_draws$beta), ncol = contract$score_rows
  )
  mean_result <- app_joint_recursive_mean_design(
    design, fixture, selected_row, state_draws$beta, state_draws$alpha,
    uniforms, contract$inverse_cdf_tail_rule
  )
  extended <- FALSE
  if (mean_result$diagnostics$standardized_rms_half_difference[[1L]] >
      contract$mean_design_rms_gate) {
    extended <- TRUE
    state_draws <- if (cell$inference_method[[1L]] == "mcmc") {
      app_joint_recursive_mcmc_draws(
        source_root, cell,
        contract$state_draws_extension %/% 5L,
        cell$state_seed[[1L]], use_all = FALSE
      )
    } else app_joint_recursive_vb_draws(
      source_root, cell, contract$state_draws_extension, cell$state_seed[[1L]]
    )
    set.seed(as.integer(cell$uniform_seed[[1L]]))
    uniforms <- matrix(stats::runif(nrow(state_draws$beta) * contract$score_rows),
      nrow = nrow(state_draws$beta), ncol = contract$score_rows
    )
    mean_result <- app_joint_recursive_mean_design(
      design, fixture, selected_row, state_draws$beta, state_draws$alpha,
      uniforms, contract$inverse_cdf_tail_rule
    )
  }
  mean_result$diagnostics$extended <- extended
  if (!mean_result$diagnostics$finite[[1L]] ||
      mean_result$diagnostics$standardized_rms_half_difference[[1L]] >
        contract$mean_design_rms_gate) {
    stop("Recursive mean-design stability gate failed.", call. = FALSE)
  }

  final_draws <- if (cell$inference_method[[1L]] == "mcmc") {
    app_joint_recursive_mcmc_draws(
      source_root, cell, contract$mcmc_score_draws_per_chain,
      cell$score_seed[[1L]], use_all = TRUE
    )
  } else app_joint_recursive_vb_draws(
    source_root, cell, contract$vb_score_draws, cell$score_seed[[1L]]
  )
  draws <- app_joint_recursive_score_draws(
    mean_result$mean_design, final_draws$beta, final_draws$alpha,
    oracle, contract$tau, contract$weights, contract$score_chunk_size,
    final_draws$chain_id, final_draws$source_draw_index
  )
  beta_mean <- colMeans(final_draws$beta); alpha_mean <- colMeans(final_draws$alpha)
  canonical <- app_joint_recursive_canonical_metrics(
    mean_result$mean_design, beta_mean, alpha_mean,
    oracle, contract$tau, contract$weights
  )
  half_scores <- vapply(mean_result$half_mean, function(z) {
    app_joint_recursive_canonical_metrics(
      z, beta_mean, alpha_mean, oracle, contract$tau, contract$weights
    )$origin_marginal_dgp_integrated_acrps[[1L]]
  }, numeric(1L))
  half_relative <- abs(diff(half_scores)) / max(abs(mean(half_scores)), 1e-12)
  mean_result$diagnostics$half_score_1 <- half_scores[[1L]]
  mean_result$diagnostics$half_score_2 <- half_scores[[2L]]
  mean_result$diagnostics$half_score_relative_difference <- half_relative
  if (half_relative > contract$mean_design_score_gate) {
    stop("Recursive half-sample canonical-score stability gate failed.", call. = FALSE)
  }

  tail <- data.frame(
    endpoint_clamp_score = NA_real_, truncated_grid_score = NA_real_,
    relative_difference = NA_real_, tolerance = contract$tail_sensitivity_gate,
    status = "not_applicable", stringsAsFactors = FALSE
  )
  if (app_as_bool_vec(cell$sentinel)[[1L]]) {
    truncated <- app_joint_recursive_mean_design(
      design, fixture, selected_row, state_draws$beta, state_draws$alpha,
      uniforms, "truncated_grid"
    )
    truncated_score <- app_joint_recursive_canonical_metrics(
      truncated$mean_design, beta_mean, alpha_mean,
      oracle, contract$tau, contract$weights
    )$origin_marginal_dgp_integrated_acrps[[1L]]
    relative <- abs(truncated_score - canonical$origin_marginal_dgp_integrated_acrps[[1L]]) /
      max(abs(canonical$origin_marginal_dgp_integrated_acrps[[1L]]), 1e-12)
    tail <- data.frame(
      endpoint_clamp_score = canonical$origin_marginal_dgp_integrated_acrps[[1L]],
      truncated_grid_score = truncated_score,
      relative_difference = relative,
      tolerance = contract$tail_sensitivity_gate,
      status = if (relative <= contract$tail_sensitivity_gate) "pass" else "review",
      stringsAsFactors = FALSE
    )
    if (tail$status[[1L]] != "pass") stop("Recursive tail sensitivity gate requires review.", call. = FALSE)
  }
  summary <- cbind(
    cell[, c("worker_id", "scenario_id", "model_cell_id", "model_id",
      "fit_structure", "likelihood_family", "design_class", "inference_method"), drop = FALSE],
    app_joint_recursive_draw_summary(draws, cell$inference_method[[1L]]),
    setNames(canonical, paste0("canonical_", names(canonical)))
  )
  summary$vb_alpha_uncertainty_included <- if (
    cell$inference_method[[1L]] == "vb"
  ) FALSE else NA
  summary$interval_scope <- if (cell$inference_method[[1L]] == "vb") {
    "partial_vb_readout_uncertainty_conditional_on_point_intercepts_and_mean_design"
  } else "mcmc_readout_uncertainty_conditional_on_mean_design"

  crossing <- data.frame(
    worker_id = cell$worker_id[[1L]],
    scenario_id = cell$scenario_id[[1L]],
    model_cell_id = cell$model_cell_id[[1L]],
    inference_method = cell$inference_method[[1L]],
    posterior_raw_crossing_pairs_mean = mean(draws$raw_crossing_pairs),
    posterior_raw_crossing_pairs_median = stats::median(draws$raw_crossing_pairs),
    posterior_contract_crossing_pairs_max = max(draws$contract_crossing_pairs),
    canonical_raw_crossing_pairs = canonical$raw_crossing_pairs[[1L]],
    canonical_contract_crossing_pairs = canonical$contract_crossing_pairs[[1L]],
    stringsAsFactors = FALSE
  )

  write_gz <- function(x, path) {
    con <- gzfile(path, "wt", compression = 9); on.exit(close(con), add = TRUE)
    utils::write.csv(x, con, row.names = FALSE, na = "")
    normalizePath(path, mustWork = TRUE)
  }
  paths <- c(
    summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
    mean_design = { saveRDS(mean_result$mean_design, file.path(tmp, "mean_design.rds")); normalizePath(file.path(tmp, "mean_design.rds")) },
    mean_design_diagnostics = app_write_csv(mean_result$diagnostics, file.path(tmp, "mean_design_diagnostics.csv")),
    posterior_score_draws = write_gz(draws, file.path(tmp, "posterior_score_draws.csv.gz")),
    quantile_action_summary = app_write_csv(canonical, file.path(tmp, "quantile_action_summary.csv")),
    crossing_summary = app_write_csv(crossing, file.path(tmp, "crossing_summary.csv")),
    teacher_forced_audit = app_write_csv(teacher, file.path(tmp, "teacher_forced_audit.csv")),
    tail_sensitivity = app_write_csv(tail, file.path(tmp, "tail_sensitivity.csv")),
    provenance = app_write_csv(data.frame(
      source_root = normalizePath(source_root),
      source_inventory_sha256 = contract$source_inventory_sha256,
      contract_sha256 = app_sha256_file(contract$path),
      git_head = system("git rev-parse HEAD", intern = TRUE),
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      stringsAsFactors = FALSE
    ), file.path(tmp, "provenance.csv"))
  )
  app_joint_recursive_atomic_manifest(tmp, paths)
  file.create(file.path(tmp, "DONE"))
  unlink(final_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(dirname(final_dir))
  if (!file.rename(tmp, final_dir)) stop("Could not publish recursive forecast worker.", call. = FALSE)
  normalizePath(final_dir, mustWork = TRUE)
}

app_joint_recursive_oracle_dir <- function(root, worker_id) {
  file.path(root, "oracle_shards", sprintf("worker_%04d", as.integer(worker_id)))
}

app_joint_recursive_manifest_ok <- function(directory) {
  manifest <- file.path(directory, "artifact_manifest.csv")
  file.exists(file.path(directory, "DONE")) && file.exists(manifest) &&
    isTRUE(tryCatch({
      audit <- app_joint_shared_verify_manifest(directory, manifest)
      nrow(audit) > 0L && all(app_as_bool_vec(audit$verified))
    }, error = function(e) FALSE))
}

app_joint_recursive_run_oracle_shard <- function(
  root, source_root, worker_id, contract
) {
  plan <- app_read_csv(file.path(root, "oracle_plan.csv"))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Recursive oracle worker id is not unique.", call. = FALSE)
  final_dir <- app_joint_recursive_oracle_dir(root, worker_id)
  if (app_joint_recursive_manifest_ok(final_dir)) {
    return(normalizePath(final_dir, mustWork = TRUE))
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  on.exit(if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  fixture <- readRDS(file.path(source_root, row$fixture_relative_path[[1L]]))
  design <- readRDS(file.path(source_root, row$design_relative_path[[1L]]))
  shard <- app_joint_recursive_dgp_shard(
    fixture, design$forecast_map, contract$oracle_paths_per_shard,
    as.integer(row$seed[[1L]])
  )
  shard_path <- file.path(tmp, "oracle_shard.rds")
  saveRDS(shard, shard_path, compress = "xz")
  summary <- data.frame(
    worker_id = as.integer(worker_id), scenario_id = row$scenario_id[[1L]],
    shard_id = as.integer(row$shard_id[[1L]]),
    is_primary = app_as_bool_vec(row$is_primary)[[1L]],
    seed = as.integer(row$seed[[1L]]), n_paths = shard$n_paths,
    rows = ncol(shard$response), finite = all(is.finite(shard$response)),
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  )
  paths <- c(
    oracle_shard = normalizePath(shard_path, mustWork = TRUE),
    summary = app_write_csv(summary, file.path(tmp, "summary.csv"))
  )
  app_joint_recursive_atomic_manifest(tmp, paths)
  file.create(file.path(tmp, "DONE"))
  unlink(final_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(dirname(final_dir))
  if (!file.rename(tmp, final_dir)) stop("Could not publish oracle shard.", call. = FALSE)
  normalizePath(final_dir, mustWork = TRUE)
}

app_joint_recursive_prepare <- function(
  root, source_root, contract_path = app_joint_recursive_contract_path()
) {
  contract <- app_joint_recursive_read_contract(contract_path)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  dirs <- app_joint_recursive_dirs(root)
  lapply(dirs, app_ensure_dir)
  frozen_path <- file.path(dirs$root, "frozen_contract.csv")
  if (file.exists(frozen_path) &&
      !identical(app_sha256_file(frozen_path), app_sha256_file(contract$path))) {
    stop("Existing runtime has a different frozen contract.", call. = FALSE)
  }
  if (!file.exists(frozen_path) && !file.copy(contract$path, frozen_path)) {
    stop("Could not freeze recursive forecast contract.", call. = FALSE)
  }

  source_audit <- app_joint_recursive_verify_source(source_root, contract)
  source_files <- app_joint_recursive_source_files(source_root)
  vb_health <- app_read_csv(source_files[["vb_health"]])
  mcmc_health <- app_read_csv(source_files[["mcmc_health"]])
  if (vb_health$completed_vb_components[[1L]] != 136L ||
      vb_health$failed_vb_components[[1L]] != 0L ||
      mcmc_health$completed_workers[[1L]] != 160L ||
      mcmc_health$failed_workers[[1L]] != 0L) {
    stop("Corrected source VB/MCMC completion gates did not pass.", call. = FALSE)
  }
  plans <- app_joint_recursive_build_plans(source_root, contract)
  if (nrow(plans$cells) != 64L || sum(plans$cells$inference_method == "vb") != 32L ||
      sum(plans$cells$inference_method == "mcmc") != 32L ||
      nrow(plans$oracle) != 32L || sum(app_as_bool_vec(plans$oracle$is_primary)) != 16L) {
    stop("Recursive worker-plan cardinality differs from contract.", call. = FALSE)
  }

  teacher <- lapply(unique(plans$cells$scenario_id), function(id) {
    design_path <- unique(plans$cells$design_relative_path[plans$cells$scenario_id == id])
    fixture_path <- unique(plans$cells$fixture_relative_path[plans$cells$scenario_id == id])
    design <- readRDS(file.path(source_root, design_path))
    fixture <- readRDS(file.path(source_root, fixture_path))
    selected <- app_joint_recursive_selected_row(plans$selected, id)
    audit <- app_joint_recursive_teacher_forced_audit(design, fixture, selected)
    if (nrow(design$forecast_map) != contract$score_rows ||
        length(unique(design$forecast_map$origin_index)) != contract$origins ||
        max(design$forecast_map$horizon) != contract$horizons) {
      audit$status <- "fail_geometry"
    }
    audit
  })
  teacher <- app_joint_qdesn_bind_rows(teacher)
  if (any(teacher$status != "pass")) {
    print(teacher)
    stop("Teacher-forced source-design equivalence failed.", call. = FALSE)
  }

  inventory <- app_read_csv(source_files[["transfer_inventory"]])
  seed_registry <- rbind(
    data.frame(stage = "oracle", worker_id = plans$oracle$worker_id,
      scenario_id = plans$oracle$scenario_id, seed = plans$oracle$seed,
      namespace = paste0("oracle_shard_", plans$oracle$shard_id),
      stringsAsFactors = FALSE),
    data.frame(stage = "state", worker_id = plans$cells$worker_id,
      scenario_id = plans$cells$scenario_id, seed = plans$cells$state_seed,
      namespace = paste0(plans$cells$inference_method, "_state"),
      stringsAsFactors = FALSE),
    data.frame(stage = "score", worker_id = plans$cells$worker_id,
      scenario_id = plans$cells$scenario_id, seed = plans$cells$score_seed,
      namespace = paste0(plans$cells$inference_method, "_score"),
      stringsAsFactors = FALSE),
    data.frame(stage = "uniform", worker_id = plans$cells$worker_id,
      scenario_id = plans$cells$scenario_id, seed = plans$cells$uniform_seed,
      namespace = "scenario_common_random_numbers",
      stringsAsFactors = FALSE)
  )
  source_summary <- data.frame(
    source_root = source_root,
    transfer_inventory_sha256 = app_sha256_file(source_files[["transfer_inventory"]]),
    files = nrow(inventory), bytes = sum(inventory$size_bytes),
    vb_components = vb_health$completed_vb_components[[1L]],
    mcmc_workers = mcmc_health$completed_workers[[1L]],
    verified = TRUE, checked_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  )
  paths <- c(
    frozen_contract = normalizePath(frozen_path, mustWork = TRUE),
    source_inventory = app_write_csv(inventory, file.path(dirs$root, "source_inventory.csv")),
    source_inventory_verification = app_write_csv(source_audit,
      file.path(dirs$root, "source_inventory_verification.csv")),
    source_summary = app_write_csv(source_summary, file.path(dirs$root, "source_summary.csv")),
    cell_plan = app_write_csv(plans$cells, file.path(dirs$root, "cell_plan.csv")),
    oracle_plan = app_write_csv(plans$oracle, file.path(dirs$root, "oracle_plan.csv")),
    selected_backbones = app_write_csv(plans$selected,
      file.path(dirs$root, "selected_backbones.csv")),
    seed_registry = app_write_csv(seed_registry, file.path(dirs$root, "seed_registry.csv")),
    origin_snapshot_manifest = app_write_csv(teacher,
      file.path(dirs$root, "origin_snapshot_manifest.csv"))
  )
  app_joint_shared_write_manifest(dirs$root, paths, "preflight_artifact_manifest.csv")
  list(root = dirs$root, source_root = source_root, teacher = teacher,
    cells = plans$cells, oracle = plans$oracle)
}

app_joint_recursive_oracle_status <- function(root) {
  plan <- app_read_csv(file.path(root, "oracle_plan.csv"))
  rows <- lapply(seq_len(nrow(plan)), function(index) {
    directory <- app_joint_recursive_oracle_dir(root, plan$worker_id[[index]])
    data.frame(plan[index, c("worker_id", "scenario_id", "shard_id", "is_primary")],
      status = if (app_joint_recursive_manifest_ok(directory)) "complete" else if (
        file.exists(file.path(directory, "FAILED"))) "failed" else "pending",
      stringsAsFactors = FALSE)
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_recursive_aggregate_oracles <- function(root, source_root, contract) {
  dirs <- app_joint_recursive_dirs(root)
  plan <- app_read_csv(file.path(root, "oracle_plan.csv"))
  scenarios <- unique(plan$scenario_id)
  diagnostics <- list()
  required_extensions <- list()
  banks <- character()
  for (id in scenarios) {
    rows <- plan[plan$scenario_id == id, , drop = FALSE]
    complete <- vapply(rows$worker_id, function(worker_id) {
      app_joint_recursive_manifest_ok(app_joint_recursive_oracle_dir(root, worker_id))
    }, logical(1L))
    primary <- app_as_bool_vec(rows$is_primary)
    if (!all(complete[primary])) {
      stop(sprintf("Primary oracle shards are incomplete for '%s'.", id), call. = FALSE)
    }
    use <- primary
    if (all(complete[!primary])) use <- rep(TRUE, nrow(rows))
    fixture <- readRDS(file.path(source_root, rows$fixture_relative_path[[1L]]))
    paths <- vapply(rows$worker_id[use], function(worker_id) {
      file.path(app_joint_recursive_oracle_dir(root, worker_id), "oracle_shard.rds")
    }, character(1L))
    oracle <- app_joint_recursive_combine_oracle_shards(
      paths, fixture, contract$tau, contract$weights,
      contract$oracle_horizon1_tolerance, contract$oracle_split_tolerance
    )
    oracle$diagnostics$extension_used <- sum(use) > sum(primary)
    diagnostics[[id]] <- oracle$diagnostics
    if (oracle$diagnostics$status[[1L]] != "pass" && !all(complete[!primary])) {
      required_extensions[[id]] <- rows[!primary, , drop = FALSE]
      next
    }
    if (oracle$diagnostics$status[[1L]] != "pass") {
      stop(sprintf("Extended oracle precision gate failed for '%s'.", id), call. = FALSE)
    }
    bank_path <- file.path(dirs$oracle_banks, paste0(id, ".rds"))
    saveRDS(oracle, bank_path, compress = "xz")
    banks[id] <- normalizePath(bank_path, mustWork = TRUE)
  }
  diagnostic_table <- app_joint_qdesn_bind_rows(diagnostics)
  app_write_csv(diagnostic_table, file.path(root, "dgp_oracle_diagnostics.csv"))
  extension <- if (length(required_extensions)) {
    app_joint_qdesn_bind_rows(required_extensions)
  } else plan[FALSE, , drop = FALSE]
  app_write_csv(extension, file.path(root, "oracle_extension_plan.csv"))
  if (nrow(extension)) return(list(status = "extension_required", plan = extension))
  manifest_rows <- lapply(names(banks), function(id) data.frame(
    scenario_id = id, relative_path = file.path("oracle_banks", basename(banks[[id]])),
    size_bytes = as.numeric(file.info(banks[[id]])$size),
    sha256 = app_sha256_file(banks[[id]]), stringsAsFactors = FALSE
  ))
  manifest <- app_joint_qdesn_bind_rows(manifest_rows)
  app_write_csv(manifest, file.path(root, "dgp_oracle_manifest.csv"))
  list(status = "complete", diagnostics = diagnostic_table, manifest = manifest)
}

app_joint_recursive_cell_status <- function(root) {
  plan <- app_read_csv(file.path(root, "cell_plan.csv"))
  rows <- lapply(seq_len(nrow(plan)), function(index) {
    directory <- app_joint_recursive_cell_dir(root, plan$worker_id[[index]])
    data.frame(plan[index, c("worker_id", "scenario_id", "model_cell_id",
      "inference_method", "sentinel")],
      status = if (app_joint_recursive_manifest_ok(directory)) "complete" else if (
        file.exists(file.path(directory, "FAILED"))) "failed" else "pending",
      stringsAsFactors = FALSE)
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_recursive_contrast_summary <- function(root, summaries) {
  read_draws <- function(row) {
    app_read_csv(file.path(app_joint_recursive_cell_dir(root, row$worker_id[[1L]]),
      "posterior_score_draws.csv.gz"))
  }
  summarize_pair <- function(left, right, type, label) {
    left_draw <- read_draws(left)
    right_draw <- read_draws(right)
    if (nrow(left_draw) != nrow(right_draw)) stop("Contrast draw counts differ.", call. = FALSE)
    delta <- left_draw$origin_marginal_dgp_integrated_acrps -
      right_draw$origin_marginal_dgp_integrated_acrps
    data.frame(
      scenario_id = left$scenario_id[[1L]],
      inference_method = left$inference_method[[1L]],
      contrast_type = type, contrast_label = label,
      left_model_cell_id = left$model_cell_id[[1L]],
      right_model_cell_id = right$model_cell_id[[1L]],
      mean_difference = mean(delta), median_difference = stats::median(delta),
      q025_difference = as.numeric(stats::quantile(delta, 0.025, names = FALSE, type = 8)),
      q975_difference = as.numeric(stats::quantile(delta, 0.975, names = FALSE, type = 8)),
      probability_left_better = mean(delta < 0),
      coupling = "deterministic_index_coupling_for_descriptive_contrast",
      stringsAsFactors = FALSE
    )
  }
  out <- list(); cursor <- 0L
  for (method in unique(summaries$inference_method)) {
    for (scenario in unique(summaries$scenario_id)) {
      block <- summaries[summaries$inference_method == method &
        summaries$scenario_id == scenario, , drop = FALSE]
      for (family in c("AL", "exAL")) {
        joint <- block[block$likelihood_family == family & block$fit_structure == "joint", , drop = FALSE]
        independent <- block[block$likelihood_family == family & block$fit_structure == "independent", , drop = FALSE]
        cursor <- cursor + 1L
        out[[cursor]] <- summarize_pair(joint, independent,
          "joint_minus_independent", paste(family, "joint minus independent"))
      }
      for (structure in c("joint", "independent")) {
        exal <- block[block$likelihood_family == "exAL" & block$fit_structure == structure, , drop = FALSE]
        al <- block[block$likelihood_family == "AL" & block$fit_structure == structure, , drop = FALSE]
        cursor <- cursor + 1L
        out[[cursor]] <- summarize_pair(exal, al,
          "exAL_minus_AL", paste(structure, "exAL minus AL"))
      }
    }
  }
  app_joint_qdesn_bind_rows(out)
}

app_joint_recursive_finalize <- function(root, contract) {
  dirs <- app_joint_recursive_dirs(root)
  status <- app_joint_recursive_cell_status(root)
  if (nrow(status) != 64L || any(status$status != "complete")) {
    stop("Recursive score packet requires 64 complete cells.", call. = FALSE)
  }
  oracle_manifest <- app_read_csv(file.path(root, "dgp_oracle_manifest.csv"))
  if (nrow(oracle_manifest) != 8L) stop("Recursive oracle manifest is incomplete.", call. = FALSE)
  summaries <- app_joint_qdesn_bind_rows(lapply(status$worker_id, function(worker_id) {
    app_read_csv(file.path(app_joint_recursive_cell_dir(root, worker_id), "summary.csv"))
  }))
  mean_diagnostics <- app_joint_qdesn_bind_rows(lapply(status$worker_id, function(worker_id) {
    x <- app_read_csv(file.path(app_joint_recursive_cell_dir(root, worker_id),
      "mean_design_diagnostics.csv"))
    x$worker_id <- worker_id
    x
  }))
  crossing <- app_joint_qdesn_bind_rows(lapply(status$worker_id, function(worker_id) {
    app_read_csv(file.path(app_joint_recursive_cell_dir(root, worker_id), "crossing_summary.csv"))
  }))
  tail <- app_joint_qdesn_bind_rows(lapply(status$worker_id, function(worker_id) {
    x <- app_read_csv(file.path(app_joint_recursive_cell_dir(root, worker_id), "tail_sensitivity.csv"))
    x$worker_id <- worker_id
    x
  }))
  if (any(!is.finite(summaries$posterior_score_mean)) ||
      any(summaries$canonical_contract_crossing_pairs != 0) ||
      any(crossing$posterior_contract_crossing_pairs_max != 0) ||
      any(mean_diagnostics$half_score_relative_difference > contract$mean_design_score_gate)) {
    stop("Recursive final scientific gates did not pass.", call. = FALSE)
  }
  contrasts <- app_joint_recursive_contrast_summary(root, summaries)
  winners <- app_joint_qdesn_bind_rows(lapply(split(summaries,
    interaction(summaries$scenario_id, summaries$inference_method, drop = TRUE)), function(x) {
      x[which.min(x$posterior_score_mean), c("scenario_id", "inference_method",
        "model_cell_id", "model_id", "fit_structure", "likelihood_family",
        "posterior_score_mean", "posterior_score_q025", "posterior_score_q975"), drop = FALSE]
    }))
  health <- data.frame(
    gate = c("oracle_banks", "vb_cells", "mcmc_cells", "all_cells",
      "finite_scores", "contract_crossings", "mean_design_stability"),
    expected = c(8L, 32L, 32L, 64L, 64L, 0L, 64L),
    observed = c(nrow(oracle_manifest),
      sum(status$status == "complete" & status$inference_method == "vb"),
      sum(status$status == "complete" & status$inference_method == "mcmc"),
      sum(status$status == "complete"), sum(is.finite(summaries$posterior_score_mean)),
      sum(crossing$posterior_contract_crossing_pairs_max),
      sum(mean_diagnostics$half_score_relative_difference <= contract$mean_design_score_gate)),
    status = "pass", stringsAsFactors = FALSE
  )
  app_ensure_dir(dirs$final)
  readme <- c(
    "# Recursive mean-design JOINT forecast packet",
    "",
    "This packet reuses the frozen corrected-v4 VB and MCMC fits. It does not refit models.",
    "Recursive response paths are synthesized from monotone seven-level quantile grids,",
    "the complete response-dependent readout design is averaged by origin and horizon,",
    "and final score intervals vary readout coefficients conditional on that mean design.",
    "VB intervals are partial because intercept covariance was not retained.",
    "The primary score is origin-marginal DGP-integrated finite-grid aCRPS."
  )
  readme_path <- file.path(dirs$final, "README.md")
  writeLines(readme, readme_path)
  paths <- c(
    summary = app_write_csv(summaries, file.path(dirs$final, "forecast_score_summary.csv")),
    contrasts = app_write_csv(contrasts, file.path(dirs$final, "posterior_contrast_summary.csv")),
    winners = app_write_csv(winners, file.path(dirs$final, "scenario_winner_summary.csv")),
    crossings = app_write_csv(crossing, file.path(dirs$final, "crossing_summary.csv")),
    mean_design = app_write_csv(mean_diagnostics, file.path(dirs$final, "mean_design_diagnostics.csv")),
    tail_sensitivity = app_write_csv(tail, file.path(dirs$final, "tail_sensitivity_summary.csv")),
    health = app_write_csv(health, file.path(dirs$final, "final_health_summary.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  app_joint_shared_write_manifest(dirs$final, paths)
  verification <- app_joint_shared_verify_manifest(dirs$final)
  if (!all(app_as_bool_vec(verification$verified))) {
    stop("Recursive final packet manifest did not verify.", call. = FALSE)
  }
  app_write_csv(verification, file.path(dirs$final, "artifact_manifest_verification.csv"))
  file.create(file.path(dirs$final, "DONE"))
  list(summary = summaries, contrasts = contrasts, winners = winners, health = health)
}
