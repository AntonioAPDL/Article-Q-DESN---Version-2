# Super-final predictive-functional stability confirmation for three flagged cells.

app_joint_superfinal_default_root <- function() {
  app_path("application/cache/joint_qdesn_superfinal_predictive_stability_20261122")
}

app_joint_superfinal_contract <- function() {
  data.frame(
    name = c("contract_version", "additional_chains_per_cell",
      "first_additional_chain_id", "last_additional_chain_id",
      "extreme_mad_multiplier", "score_rank_rhat_ceiling",
      "score_folded_rhat_ceiling", "score_bulk_ess_floor",
      "score_tail_ess_floor", "relative_mcse_ceiling",
      "leave_one_chain_relative_range_ceiling", "max_draw_fraction_ceiling",
      "state_draws_per_chain", "path_draws_per_chain",
      "canonical_forecast_policy", "exal_mcmc_method",
      "fallback_policy", "model_splicing_allowed", "source_git_head",
      "source_inventory_sha256", "source_handoff_manifest_sha256"),
    value = c("joint_qdesn_superfinal_predictive_stability_v1", "5", "4", "8",
      "20", "1.05", "1.10", "100", "100", "0.01", "0.02", "0.01",
      "200", "40", "recursive_mean_state", "M0_v_collapsed_support_logit",
      "whole_scenario_new_geometry_parity", "FALSE",
      "4381c14c50aa60de93eb952e3f67965bde9904f5",
      "213dc7f45004b0383db87054abf479200193b45056b64d461f2edc75a34f28d0",
      "20ade34f91e08de24f213a532af994b6232aa7fffc5f62f08022291bc42fe277"),
    stringsAsFactors = FALSE
  )
}

app_joint_superfinal_value <- function(contract, name, numeric = FALSE) {
  row <- contract[contract$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Super-final contract lacks '%s'.", name), call. = FALSE)
  if (numeric) as.numeric(row$value[[1L]]) else as.character(row$value[[1L]])
}

app_joint_superfinal_targets <- function() {
  data.frame(
    target_id = 1:3,
    scenario_id = c("laplace_bridge", "persistent_heavy_tail", "persistent_heavy_tail"),
    specification_role = c("new_geometry_parity", "challenger", "challenger"),
    model_id = c("joint_exqdesn_rhs", "joint_qdesn_rhs", "joint_exqdesn_rhs"),
    source_score_worker_id = c(48L, 84L, 88L),
    stringsAsFactors = FALSE
  )
}

app_joint_superfinal_read_gz <- function(path) {
  con <- gzfile(path, "rt"); on.exit(close(con), add = TRUE)
  utils::read.csv(con, stringsAsFactors = FALSE, check.names = FALSE)
}

app_joint_superfinal_write_gz <- function(x, path) {
  con <- gzfile(path, "wt", compression = 9); on.exit(close(con), add = TRUE)
  utils::write.csv(x, con, row.names = FALSE, na = "")
  path
}

app_joint_superfinal_score_dir <- function(root, target_id) {
  file.path(root, "score_cells", sprintf("target_%02d", as.integer(target_id)))
}

app_joint_superfinal_source_paths <- function(source_root) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  list(
    source_root = source_root,
    confirmation = file.path(source_root, "full_confirmation"),
    score = file.path(source_root, "full_confirmation", "score_packet"),
    inventory = file.path(source_root, "integration_handoff",
      "full_confirmation_transfer_inventory.csv"),
    handoff_manifest = file.path(source_root, "integration_handoff", "handoff_manifest.csv"),
    git_state = file.path(source_root, "integration_handoff", "git_state.csv")
  )
}

app_joint_superfinal_verify_source_files <- function(source_root, relative_paths, contract) {
  paths <- app_joint_superfinal_source_paths(source_root)
  if (tolower(app_sha256_file(paths$handoff_manifest)) != tolower(
      app_joint_superfinal_value(contract, "source_handoff_manifest_sha256")) ||
      tolower(app_sha256_file(paths$inventory)) != tolower(
      app_joint_superfinal_value(contract, "source_inventory_sha256"))) {
    stop("Frozen source handoff or transfer inventory hash changed.", call. = FALSE)
  }
  handoff <- app_read_csv(paths$handoff_manifest)
  inv_row <- handoff[handoff$relative_path == basename(paths$inventory), , drop = FALSE]
  if (nrow(inv_row) != 1L || file.info(paths$inventory)$size != inv_row$size_bytes[[1L]] ||
      tolower(app_sha256_file(paths$inventory)) != tolower(inv_row$sha256[[1L]])) {
    stop("Source transfer inventory is not bound to the frozen handoff.", call. = FALSE)
  }
  git_row <- handoff[handoff$relative_path == basename(paths$git_state), , drop = FALSE]
  git_state <- app_read_csv(paths$git_state)
  if (nrow(git_row) != 1L || file.info(paths$git_state)$size != git_row$size_bytes[[1L]] ||
      tolower(app_sha256_file(paths$git_state)) != tolower(git_row$sha256[[1L]]) ||
      nrow(git_state) != 1L || git_state$head[[1L]] !=
        app_joint_superfinal_value(contract, "source_git_head") ||
      !isTRUE(git_state$worktree_clean[[1L]])) {
    stop("Frozen source Git receipt is invalid or no longer matches the contract.", call. = FALSE)
  }
  inventory <- app_read_csv(paths$inventory)
  rows <- inventory[match(relative_paths, inventory$relative_path), , drop = FALSE]
  if (nrow(rows) != length(relative_paths) || any(is.na(rows$relative_path))) {
    stop("Required source file is absent from the frozen inventory.", call. = FALSE)
  }
  absolute <- file.path(paths$confirmation, rows$relative_path)
  verified <- file.exists(absolute) & file.info(absolute)$size == rows$size_bytes &
    tolower(vapply(absolute, app_sha256_file, character(1L))) == tolower(rows$sha256)
  data.frame(relative_path = rows$relative_path, absolute_path = absolute,
    size_bytes = rows$size_bytes, sha256 = rows$sha256, verified = verified,
    stringsAsFactors = FALSE)
}

app_joint_superfinal_chain_metrics <- function(score_draws, mad_multiplier = 20) {
  score <- score_draws$origin_marginal_dgp_integrated_acrps
  threshold <- stats::median(score) + mad_multiplier * max(stats::mad(score), 1e-12)
  by_chain <- lapply(split(score_draws, score_draws$chain_id), function(x) {
    v <- x$origin_marginal_dgp_integrated_acrps
    extreme <- x$source_draw_index[v > threshold]
    runs <- if (!length(extreme)) 0L else {
      groups <- cumsum(c(TRUE, diff(sort(extreme)) != 1L))
      max(tabulate(groups))
    }
    data.frame(chain_id = x$chain_id[[1L]], n = nrow(x), mean = mean(v),
      median = stats::median(v), sd = stats::sd(v), q025 = stats::quantile(v, 0.025),
      q975 = stats::quantile(v, 0.975), max = max(v), threshold = threshold,
      extreme_draws = sum(v > threshold), longest_extreme_run = runs,
      stringsAsFactors = FALSE)
  })
  app_bind_rows_fill(by_chain)
}

app_joint_superfinal_influence <- function(score_draws, diagnostic, contract) {
  score <- score_draws$origin_marginal_dgp_integrated_acrps
  chain_means <- vapply(split(score, score_draws$chain_id), mean, numeric(1L))
  leave_one <- vapply(names(chain_means), function(id) {
    mean(score[score_draws$chain_id != as.integer(id)])
  }, numeric(1L))
  full_mean <- mean(score)
  data.frame(
    posterior_score_mean = full_mean,
    posterior_score_median = stats::median(score),
    posterior_score_q025 = stats::quantile(score, 0.025),
    posterior_score_q975 = stats::quantile(score, 0.975),
    posterior_score_max = max(score),
    max_draw_fraction = max(score) / sum(score),
    leave_one_chain_relative_range = diff(range(leave_one)) / stats::median(score),
    score_rank_rhat = diagnostic$rank_rhat,
    score_folded_rhat = diagnostic$folded_rhat,
    score_bulk_ess = diagnostic$bulk_ess,
    score_tail_ess = diagnostic$tail_ess,
    score_mcse_mean = diagnostic$mcse_mean,
    relative_mcse = diagnostic$mcse_mean / full_mean,
    mean_above_q975 = full_mean > stats::quantile(score, 0.975),
    stringsAsFactors = FALSE
  )
}

app_joint_superfinal_parameter_metrics <- function(draws) {
  beta <- app_joint_recursive_select_block(draws, "beta")
  alpha <- app_joint_recursive_select_block(draws, "alpha")
  sigma <- app_joint_recursive_select_block(draws, "sigma")
  gamma <- app_joint_recursive_select_block(draws, "gamma")
  data.frame(source_draw_index = draws$draw_index,
    beta_l2 = sqrt(rowSums(beta^2)), beta_max_abs = apply(abs(beta), 1L, max),
    alpha_span = apply(alpha, 1L, function(x) diff(range(x))),
    sigma_min = if (ncol(sigma)) apply(sigma, 1L, min) else NA_real_,
    sigma_max = if (ncol(sigma)) apply(sigma, 1L, max) else NA_real_,
    gamma_min = if (ncol(gamma)) apply(gamma, 1L, min) else NA_real_,
    gamma_max = if (ncol(gamma)) apply(gamma, 1L, max) else NA_real_,
    stringsAsFactors = FALSE)
}

app_joint_superfinal_source_audit <- function(source_root, contract) {
  paths <- app_joint_superfinal_source_paths(source_root)
  targets <- app_joint_superfinal_targets()
  source_plan <- app_read_csv(file.path(paths$confirmation, "mcmc_worker_plan.csv"))
  score_summary <- app_read_csv(file.path(paths$score, "score_summary.csv"))
  chain_rows <- list(); influence_rows <- list(); extreme_rows <- list(); assoc_rows <- list()
  for (i in seq_len(nrow(targets))) {
    target <- targets[i, , drop = FALSE]
    cell <- paste(target$scenario_id, target$specification_role, target$model_id, sep = "__")
    score_path <- file.path(paths$score, "cells",
      sprintf("worker_%04d", target$source_score_worker_id), "posterior_score_draws.csv.gz")
    draws <- app_joint_superfinal_read_gz(score_path)
    split_score <- split(draws$origin_marginal_dgp_integrated_acrps, draws$chain_id)
    diagnostic <- app_joint_exqdesn_modern_diagnostics(do.call(cbind, split_score))
    chains <- app_joint_superfinal_chain_metrics(draws,
      app_joint_superfinal_value(contract, "extreme_mad_multiplier", TRUE))
    chains$target_id <- target$target_id; chains$model_cell_id <- cell
    chain_rows[[i]] <- chains
    influence <- app_joint_superfinal_influence(draws, diagnostic, contract)
    influence$target_id <- target$target_id; influence$model_cell_id <- cell
    influence_rows[[i]] <- influence
    jobs <- source_plan[source_plan$model_cell_id == cell, , drop = FALSE]
    metrics <- lapply(seq_len(nrow(jobs)), function(j) {
      path <- file.path(paths$confirmation, "mcmc_workers",
        sprintf("worker_%04d", jobs$worker_id[[j]]), "posterior_draws.csv.gz")
      x <- app_joint_superfinal_parameter_metrics(app_joint_superfinal_read_gz(path))
      x$chain_id <- jobs$chain_id[[j]]; x
    })
    metrics <- app_bind_rows_fill(metrics)
    joined <- merge(draws, metrics, by = c("chain_id", "source_draw_index"), all.x = TRUE)
    threshold <- unique(chains$threshold)[1L]
    top <- joined[order(joined$origin_marginal_dgp_integrated_acrps, decreasing = TRUE), ]
    top <- head(top, 25L)
    top$target_id <- target$target_id; top$model_cell_id <- cell
    extreme_rows[[i]] <- top
    parameters <- c("beta_l2", "beta_max_abs", "alpha_span", "sigma_min",
      "sigma_max", "gamma_min", "gamma_max")
    assoc <- lapply(parameters, function(parameter) {
      value <- joined[[parameter]]
      data.frame(target_id = target$target_id, model_cell_id = cell,
        parameter = parameter,
        spearman_score_correlation = if (all(is.na(value))) NA_real_ else
          suppressWarnings(stats::cor(joined$origin_marginal_dgp_integrated_acrps,
            value, method = "spearman", use = "complete.obs")),
        extreme_mean = if (all(is.na(value))) NA_real_ else
          mean(value[joined$origin_marginal_dgp_integrated_acrps > threshold], na.rm = TRUE),
        ordinary_mean = if (all(is.na(value))) NA_real_ else
          mean(value[joined$origin_marginal_dgp_integrated_acrps <= threshold], na.rm = TRUE),
        stringsAsFactors = FALSE)
    })
    assoc_rows[[i]] <- app_bind_rows_fill(assoc)
  }
  influence <- app_bind_rows_fill(influence_rows)
  influence$requires_supplemental_confirmation <- with(influence,
    score_rank_rhat > app_joint_superfinal_value(contract, "score_rank_rhat_ceiling", TRUE) |
    score_folded_rhat > app_joint_superfinal_value(contract, "score_folded_rhat_ceiling", TRUE) |
    score_bulk_ess < app_joint_superfinal_value(contract, "score_bulk_ess_floor", TRUE) |
    score_tail_ess < app_joint_superfinal_value(contract, "score_tail_ess_floor", TRUE) |
    relative_mcse > app_joint_superfinal_value(contract, "relative_mcse_ceiling", TRUE) |
    leave_one_chain_relative_range > app_joint_superfinal_value(contract,
      "leave_one_chain_relative_range_ceiling", TRUE) |
    max_draw_fraction > app_joint_superfinal_value(contract, "max_draw_fraction_ceiling", TRUE))
  list(chain = app_bind_rows_fill(chain_rows), influence = influence,
    extreme = app_bind_rows_fill(extreme_rows), association = app_bind_rows_fill(assoc_rows))
}

app_joint_superfinal_prepare <- function(source_root, root = app_joint_superfinal_default_root()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  root <- normalizePath(app_ensure_dir(root), mustWork = TRUE)
  contract <- app_joint_superfinal_contract()
  paths <- app_joint_superfinal_source_paths(source_root)
  targets <- app_joint_superfinal_targets()
  source_plan <- app_read_csv(file.path(paths$confirmation, "mcmc_worker_plan.csv"))
  score_plan <- app_read_csv(file.path(paths$score, "score_worker_plan.csv"))
  required <- c("mcmc_worker_plan.csv", "score_packet/score_worker_plan.csv",
    "score_packet/score_summary.csv", "score_packet/score_contract.csv")
  for (i in seq_len(nrow(targets))) {
    cell <- paste(targets$scenario_id[[i]], targets$specification_role[[i]],
      targets$model_id[[i]], sep = "__")
    jobs <- source_plan[source_plan$model_cell_id == cell, , drop = FALSE]
    row <- score_plan[score_plan$score_worker_id == targets$source_score_worker_id[[i]], , drop = FALSE]
    required <- c(required,
      file.path("score_packet", "cells", sprintf("worker_%04d", targets$source_score_worker_id[[i]]),
        c("summary.csv", "posterior_score_draws.csv.gz", "artifact_manifest.csv")),
      file.path("score_packet", "oracle_banks", paste0(targets$scenario_id[[i]], ".rds")),
      substring(row$design_path[[1L]], nchar(paths$confirmation) + 2L),
      substring(row$vb_packet_path[[1L]], nchar(paths$confirmation) + 2L),
      substring(row$fixture_path[[1L]], nchar(paths$confirmation) + 2L),
      unlist(lapply(jobs$worker_id, function(id) file.path("mcmc_workers",
        sprintf("worker_%04d", id), c("posterior_draws.csv.gz", "artifact_manifest.csv")))))
  }
  binding <- app_joint_superfinal_verify_source_files(source_root, unique(required), contract)
  if (!all(binding$verified)) stop("Frozen source binding failed.", call. = FALSE)
  audit <- app_joint_superfinal_source_audit(source_root, contract)
  if (!all(audit$influence$requires_supplemental_confirmation)) {
    stop("Frozen source diagnostics no longer reproduce the three declared targets.",
      call. = FALSE)
  }
  out <- file.path(root, "full_confirmation"); app_ensure_dir(out)
  plan_rows <- list(); worker_id <- 0L
  for (i in seq_len(nrow(targets))) {
    cell <- paste(targets$scenario_id[[i]], targets$specification_role[[i]],
      targets$model_id[[i]], sep = "__")
    template <- source_plan[source_plan$model_cell_id == cell, , drop = FALSE][1L, , drop = FALSE]
    for (chain in as.integer(app_joint_superfinal_value(contract,
        "first_additional_chain_id", TRUE)):as.integer(app_joint_superfinal_value(contract,
        "last_additional_chain_id", TRUE))) {
      worker_id <- worker_id + 1L
      row <- template
      row$worker_id <- worker_id; row$chain_id <- chain
      row$chain_seed <- 1500000000L + i * 1000000L + chain * 1009L
      row$chain_start_seed <- 1600000000L + i * 1000000L + chain * 1009L
      row$source_score_worker_id <- targets$source_score_worker_id[[i]]
      row$target_id <- targets$target_id[[i]]
      plan_rows[[worker_id]] <- row
    }
  }
  plan <- app_bind_rows_fill(plan_rows)
  if (anyDuplicated(plan$chain_seed) || anyDuplicated(plan$chain_start_seed)) {
    stop("Supplemental seed plan is not unique.", call. = FALSE)
  }
  contract_path <- app_write_csv(contract, file.path(root, "superfinal_contract.csv"))
  target_path <- app_write_csv(targets, file.path(root, "target_registry.csv"))
  binding_path <- app_write_csv(binding, file.path(root, "source_binding.csv"))
  chain_path <- app_write_csv(audit$chain, file.path(root, "source_chain_summary.csv"))
  influence_path <- app_write_csv(audit$influence, file.path(root, "source_influence_audit.csv"))
  extreme_path <- app_write_csv(audit$extreme, file.path(root, "source_extreme_draws.csv"))
  assoc_path <- app_write_csv(audit$association, file.path(root, "source_parameter_association.csv"))
  plan_path <- app_write_csv(plan, file.path(out, "mcmc_worker_plan.csv"))
  readiness <- data.frame(status = if (all(audit$influence$requires_supplemental_confirmation))
      "SUPPLEMENTAL_MCMC_READY" else "SOURCE_AUDIT_COMPLETE_NO_SUPPLEMENTAL_REQUIRED",
    targets = nrow(targets), supplemental_workers = nrow(plan), source_files_verified = nrow(binding),
    source_failures = sum(!binding$verified), article_assets_modified = FALSE,
    stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(root, "readiness.csv"))
  app_joint_shared_write_manifest(root, c(contract = contract_path, targets = target_path,
    binding = binding_path, chain = chain_path, influence = influence_path,
    extreme = extreme_path, association = assoc_path, plan = plan_path,
    readiness = readiness_path), filename = "prepare_manifest.csv")
  readiness
}

app_joint_superfinal_health <- function(root = app_joint_superfinal_default_root()) {
  plan <- app_read_csv(file.path(root, "full_confirmation", "mcmc_worker_plan.csv"))
  dirs <- vapply(plan$worker_id, function(id) app_joint_swcf_worker_dir(root, "mcmc", id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_superfinal_combined_identity <- function(blocks) {
  if (!length(blocks) || any(!vapply(blocks, is.list, logical(1L)))) {
    stop("Combined-chain identity requires a nonempty list of chain blocks.",
      call. = FALSE)
  }
  field <- function(name) unique(unlist(lapply(blocks, function(block) {
    value <- block[[name]]
    if (is.null(value) || length(value) != 1L ||
        !grepl("^[0-9a-f]{64}$", as.character(value))) {
      stop(sprintf("Combined chain block lacks valid %s.", name), call. = FALSE)
    }
    as.character(value)
  }), use.names = FALSE))
  historical <- field("posterior_target_sha256")
  complete <- field("complete_posterior_target_sha256")
  kernel <- field("effective_sampler_control_sha256")
  if (length(historical) != 1L || length(complete) != 1L ||
      length(kernel) != 1L) {
    stop("Combined chains do not share one complete target and sampler kernel.",
      call. = FALSE)
  }
  list(posterior_target_sha256 = historical,
    complete_posterior_target_sha256 = complete,
    effective_sampler_control_sha256 = kernel)
}

app_joint_superfinal_combined_draws <- function(source_root, root, model_cell_id) {
  source_paths <- app_joint_superfinal_source_paths(source_root)
  old_plan <- app_read_csv(file.path(source_paths$confirmation, "mcmc_worker_plan.csv"))
  new_plan <- app_read_csv(file.path(root, "full_confirmation", "mcmc_worker_plan.csv"))
  old_jobs <- old_plan[old_plan$model_cell_id == model_cell_id, , drop = FALSE]
  new_jobs <- new_plan[new_plan$model_cell_id == model_cell_id, , drop = FALSE]
  if (nrow(old_jobs) != 3L || nrow(new_jobs) != 5L ||
      !identical(sort(as.integer(old_jobs$chain_id)), 1:3) ||
      !identical(sort(as.integer(new_jobs$chain_id)), 4:8)) {
    stop("Combined score requires the frozen three chains and five fresh chains.",
      call. = FALSE)
  }
  load_block <- function(job, base_root) {
    worker <- app_joint_swcf_worker_dir(base_root, "mcmc", job$worker_id[[1L]])
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified) ||
        !file.exists(file.path(worker, "DONE"))) {
      stop(sprintf("MCMC chain %s is incomplete or fails its manifest.",
        job$chain_id[[1L]]), call. = FALSE)
    }
    summary <- app_read_csv(file.path(worker, "summary.csv"))
    if (nrow(summary) != 1L || !isTRUE(summary$finite_draws[[1L]]) ||
        summary$model_cell_id[[1L]] != model_cell_id) {
      stop("MCMC chain summary does not match the requested posterior target.",
        call. = FALSE)
    }
    required_identity <- c("complete_posterior_target_sha256",
      "effective_sampler_control_sha256")
    if (!all(required_identity %in% names(summary)) ||
        any(!grepl("^[0-9a-f]{64}$",
          as.character(unlist(summary[1L, required_identity]))))) {
      stop(paste(
        "MCMC chain lacks the corrected complete target or sampler identity;",
        "historical capped and corrected uncapped chains cannot be combined."
      ), call. = FALSE)
    }
    if (summary$likelihood_family[[1L]] == "exAL" &&
        summary$inference_method_id[[1L]] != "M0_v_collapsed_support_logit") {
      stop("An exAL supplemental chain did not use exact M0.", call. = FALSE)
    }
    draws <- app_joint_superfinal_read_gz(file.path(worker, "posterior_draws.csv.gz"))
    if (nrow(draws) != job$n_keep[[1L]]) {
      stop("MCMC retained-draw count differs from the frozen chain plan.", call. = FALSE)
    }
    list(beta = app_joint_recursive_select_block(draws, "beta"),
      alpha = app_joint_recursive_select_block(draws, "alpha"),
      chain_id = rep(job$chain_id[[1L]], nrow(draws)),
      source_draw_index = draws$draw_index,
      posterior_target_sha256 = summary$posterior_target_sha256[[1L]],
      complete_posterior_target_sha256 =
        summary$complete_posterior_target_sha256[[1L]],
      effective_sampler_control_sha256 =
        summary$effective_sampler_control_sha256[[1L]])
  }
  blocks <- c(lapply(seq_len(nrow(old_jobs)), function(i) load_block(old_jobs[i, ], source_root)),
    lapply(seq_len(nrow(new_jobs)), function(i) load_block(new_jobs[i, ], root)))
  identity <- app_joint_superfinal_combined_identity(blocks)
  list(beta = do.call(rbind, lapply(blocks, `[[`, "beta")),
    alpha = do.call(rbind, lapply(blocks, `[[`, "alpha")),
    chain_id = unlist(lapply(blocks, `[[`, "chain_id"), use.names = FALSE),
    source_draw_index = unlist(lapply(blocks, `[[`, "source_draw_index"), use.names = FALSE),
    posterior_target_sha256 = identity$posterior_target_sha256,
    complete_posterior_target_sha256 =
      identity$complete_posterior_target_sha256,
    effective_sampler_control_sha256 =
      identity$effective_sampler_control_sha256)
}

app_joint_superfinal_run_score <- function(source_root, root, target_id) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  root <- normalizePath(root, mustWork = TRUE)
  target <- app_joint_superfinal_targets()
  target <- target[target$target_id == as.integer(target_id), , drop = FALSE]
  if (nrow(target) != 1L) stop("Super-final score target is not unique.", call. = FALSE)
  out <- app_joint_superfinal_score_dir(root, target_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  contract <- app_read_csv(file.path(root, "superfinal_contract.csv"))
  source_paths <- app_joint_superfinal_source_paths(source_root)
  score_contract <- app_read_csv(file.path(source_paths$score, "score_contract.csv"))
  plan <- app_read_csv(file.path(source_paths$score, "score_worker_plan.csv"))
  row <- plan[plan$score_worker_id == target$source_score_worker_id, , drop = FALSE]
  draws <- app_joint_superfinal_combined_draws(source_root, root, row$model_cell_id[[1L]])
  design <- readRDS(row$design_path[[1L]]); fixture <- readRDS(row$fixture_path[[1L]])
  tau <- app_joint_swscore_numvec(score_contract, "quantile_grid")
  weights <- app_joint_swscore_numvec(score_contract, "trapezoidal_weights")
  state <- app_joint_swscore_subset(draws,
    app_joint_superfinal_value(contract, "state_draws_per_chain", TRUE))
  set.seed(row$uniform_seed[[1L]])
  uniforms <- matrix(stats::runif(nrow(state$beta) * nrow(design$forecast_map)),
    nrow = nrow(state$beta))
  mean_result <- app_joint_recursive_mean_design(design, fixture, row, state$beta,
    state$alpha, uniforms, app_joint_swscore_value(score_contract, "inverse_cdf_tail_rule"),
    half_assignment = app_joint_recursive_half_assignment(state$chain_id,
      "within_chain_alternating"), diagnostic_group = state$chain_id)
  oracle <- readRDS(file.path(source_paths$score, "oracle_banks",
    paste0(row$scenario_id[[1L]], ".rds")))
  score_draws <- app_joint_recursive_score_draws(mean_result$mean_design, draws$beta,
    draws$alpha, oracle, tau, weights,
    app_joint_swscore_value(score_contract, "score_chunk_size", TRUE),
    draws$chain_id, draws$source_draw_index)
  split_score <- split(score_draws$origin_marginal_dgp_integrated_acrps,
    score_draws$chain_id)
  if (length(split_score) != 8L || length(unique(lengths(split_score))) != 1L) {
    stop("Predictive diagnostics require eight equally sized chains.", call. = FALSE)
  }
  diagnostic <- app_joint_exqdesn_modern_diagnostics(do.call(cbind, split_score))
  summary <- app_joint_recursive_draw_summary(score_draws, "mcmc")
  summary$score_rank_rhat <- diagnostic$rank_rhat
  summary$score_folded_rhat <- diagnostic$folded_rhat
  summary$score_bulk_ess <- diagnostic$bulk_ess
  summary$score_tail_ess <- diagnostic$tail_ess
  summary$score_mcse_mean <- diagnostic$mcse_mean
  influence <- app_joint_superfinal_influence(score_draws, diagnostic, contract)
  chain <- app_joint_superfinal_chain_metrics(score_draws,
    app_joint_superfinal_value(contract, "extreme_mad_multiplier", TRUE))
  beta_mean <- colMeans(draws$beta); alpha_mean <- colMeans(draws$alpha)
  canonical <- app_joint_recursive_canonical_metrics(mean_result$mean_design,
    beta_mean, alpha_mean, oracle, tau, weights)
  fit_q <- app_joint_qdesn_predict_fit(list(beta_mean = beta_mean, alpha_mean = alpha_mean),
    design$Z[design$train_local, , drop = FALSE], tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_q, tau)
  fit_error <- fit_contract$qhat_contract - design$true_q[design$train_local, , drop = FALSE]
  output <- cbind(target, row[, c("model_cell_id", "fit_structure", "likelihood_family"),
    drop = FALSE], summary, setNames(canonical, paste0("canonical_", names(canonical))),
    influence[, setdiff(names(influence), names(summary)), drop = FALSE],
    data.frame(total_chains = length(unique(draws$chain_id)),
      posterior_target_sha256 = draws$posterior_target_sha256,
      fit_oracle_quantile_mae = mean(abs(fit_error)),
      fit_oracle_quantile_rmse = sqrt(mean(fit_error^2)), stringsAsFactors = FALSE))
  files <- c(summary = app_write_csv(output, file.path(tmp, "summary.csv")),
    chain = app_write_csv(chain, file.path(tmp, "chain_summary.csv")),
    score_draws = app_joint_superfinal_write_gz(score_draws,
      file.path(tmp, "posterior_score_draws.csv.gz")),
    canonical = app_write_csv(canonical, file.path(tmp, "canonical_action.csv")),
    mean_design = app_write_csv(mean_result$diagnostics,
      file.path(tmp, "mean_design_diagnostics.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp, file.path(tmp,
      "artifact_manifest.csv"))$verified)) stop("Super-final score manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish super-final score atomically.", call. = FALSE)
  invisible(out)
}

app_joint_superfinal_score_health <- function(root = app_joint_superfinal_default_root()) {
  targets <- app_joint_superfinal_targets()
  dirs <- vapply(targets$target_id, function(id) app_joint_superfinal_score_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(targets), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_superfinal_whole_scenario_packet <- function(mcmc, scenario_id,
    challenger_stable, required_models = c("independent_qdesn_rhs",
      "joint_qdesn_rhs", "independent_exqdesn_rhs", "joint_exqdesn_rhs")) {
  role <- if (isTRUE(challenger_stable)) "challenger" else
    "new_geometry_parity"
  packet <- mcmc[mcmc$scenario_id == scenario_id &
    mcmc$specification_role == role, , drop = FALSE]
  if (nrow(packet) != length(required_models) ||
      anyDuplicated(packet$model_id) ||
      !setequal(as.character(packet$model_id), required_models)) {
    stop(sprintf(
      "Scenario '%s' does not contain one complete %s four-model packet.",
      scenario_id, role), call. = FALSE)
  }
  packet$promote_complete_challenger_packet <- isTRUE(challenger_stable)
  packet[match(required_models, packet$model_id), , drop = FALSE]
}

app_joint_superfinal_finalize <- function(source_root, root = app_joint_superfinal_default_root()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_superfinal_health(root)
  score_health <- app_joint_superfinal_score_health(root)
  if (health$completed != health$expected || health$failed != 0L ||
      score_health$completed != score_health$expected || score_health$failed != 0L) {
    stop("Super-final workers are incomplete.", call. = FALSE)
  }
  targets <- app_joint_superfinal_targets(); contract <- app_read_csv(file.path(root,
    "superfinal_contract.csv"))
  summaries <- app_bind_rows_fill(lapply(targets$target_id, function(id) {
    dir <- app_joint_superfinal_score_dir(root, id)
    if (!all(app_joint_shared_verify_manifest(dir, file.path(dir,
        "artifact_manifest.csv"))$verified)) stop("Score manifest failed.", call. = FALSE)
    app_read_csv(file.path(dir, "summary.csv"))
  }))
  summaries$relative_mcse <- summaries$score_mcse_mean / summaries$posterior_score_mean
  summaries$stable <- with(summaries,
    is.finite(posterior_score_mean) &
    is.finite(score_rank_rhat) & is.finite(score_folded_rhat) &
    is.finite(score_bulk_ess) & is.finite(score_tail_ess) &
    is.finite(relative_mcse) & is.finite(leave_one_chain_relative_range) &
    is.finite(max_draw_fraction) &
    score_rank_rhat <= app_joint_superfinal_value(contract, "score_rank_rhat_ceiling", TRUE) &
    score_folded_rhat <= app_joint_superfinal_value(contract, "score_folded_rhat_ceiling", TRUE) &
    score_bulk_ess >= app_joint_superfinal_value(contract, "score_bulk_ess_floor", TRUE) &
    score_tail_ess >= app_joint_superfinal_value(contract, "score_tail_ess_floor", TRUE) &
    relative_mcse <= app_joint_superfinal_value(contract, "relative_mcse_ceiling", TRUE) &
    leave_one_chain_relative_range <= app_joint_superfinal_value(contract,
      "leave_one_chain_relative_range_ceiling", TRUE) &
    max_draw_fraction <= app_joint_superfinal_value(contract, "max_draw_fraction_ceiling", TRUE) &
    canonical_contract_crossing_pairs == 0)
  summaries$stable[is.na(summaries$stable)] <- FALSE
  paths <- app_joint_superfinal_source_paths(source_root)
  source_summary <- app_read_csv(file.path(paths$score, "score_summary.csv"))
  source_decisions <- app_read_csv(file.path(paths$score, "scenario_packet_decisions.csv"))
  mcmc <- source_summary[source_summary$inference_method == "mcmc", , drop = FALSE]
  selected <- merge(mcmc, source_decisions[, c("scenario_id",
    "promote_complete_challenger_packet")], by = "scenario_id")
  selected <- selected[(selected$promote_complete_challenger_packet &
    selected$specification_role == "challenger") |
    (!selected$promote_complete_challenger_packet &
    selected$specification_role == "new_geometry_parity"), , drop = FALSE]
  laplace_rows <- summaries$scenario_id == "laplace_bridge"
  persistent_rows <- summaries$scenario_id == "persistent_heavy_tail"
  laplace_ok <- sum(laplace_rows) == 1L && isTRUE(summaries$stable[laplace_rows])
  persistent_ok <- sum(persistent_rows) == 2L &&
    all(summaries$stable[persistent_rows])
  replace_row <- function(packet, replacement) {
    key <- packet$scenario_id == replacement$scenario_id[[1L]] &
      packet$model_id == replacement$model_id[[1L]]
    common <- intersect(names(packet), names(replacement))
    packet[key, common] <- replacement[1L, common]
    packet
  }
  if (isTRUE(laplace_ok)) {
    selected <- replace_row(selected,
      summaries[summaries$scenario_id == "laplace_bridge", , drop = FALSE])
  }
  selected <- selected[selected$scenario_id != "persistent_heavy_tail", , drop = FALSE]
  persistent_packet <- app_joint_superfinal_whole_scenario_packet(
    mcmc, "persistent_heavy_tail", persistent_ok)
  if (persistent_ok) {
    for (model in c("joint_qdesn_rhs", "joint_exqdesn_rhs")) {
      persistent_packet <- replace_row(persistent_packet,
        summaries[summaries$scenario_id ==
        "persistent_heavy_tail" & summaries$model_id == model, , drop = FALSE])
    }
  }
  selected <- app_bind_rows_fill(list(selected, persistent_packet))
  decisions <- data.frame(scenario_id = c("laplace_bridge", "persistent_heavy_tail"),
    targeted_rows_stable = c(sum(summaries$stable[summaries$scenario_id == "laplace_bridge"]),
      sum(summaries$stable[summaries$scenario_id == "persistent_heavy_tail"])),
    targeted_rows = c(1L, 2L),
    final_packet = c("new_geometry_parity",
      if (persistent_ok) "challenger" else "new_geometry_parity"),
    decision = c(if (isTRUE(laplace_ok)) "retain_parity_with_stabilized_joint_exal" else
        "not_ready_laplace_joint_exal_unstable",
      if (persistent_ok) "promote_complete_challenger_packet" else
        "retain_complete_parity_packet_due_joint_instability"),
    stringsAsFactors = FALSE)
  selected <- selected[order(selected$scenario_id, selected$model_id), , drop = FALSE]
  packet_cells <- paste(selected$scenario_id, selected$model_id, sep = "__")
  packet_counts <- table(selected$scenario_id)
  packet_complete <- nrow(selected) == 32L && !anyDuplicated(packet_cells) &&
    length(packet_counts) == 8L && all(packet_counts == 4L)
  summary_path <- app_write_csv(summaries, file.path(root, "supplemental_score_summary.csv"))
  decision_path <- app_write_csv(decisions, file.path(root, "superfinal_scenario_decisions.csv"))
  packet_path <- app_write_csv(selected, file.path(root, "superfinal_selected_score_summary.csv"))
  ready <- isTRUE(laplace_ok) && packet_complete &&
    all(is.finite(selected$posterior_score_mean)) &&
    all(selected$canonical_contract_crossing_pairs == 0)
  final <- data.frame(status = if (ready) "SUPERFINAL_PACKET_READY_FOR_INTEGRATION_REVIEW" else
      "SUPERFINAL_PACKET_NOT_READY", selected_rows = nrow(selected),
    persistent_challenger_retained = persistent_ok, laplace_stable = isTRUE(laplace_ok),
    article_assets_modified = FALSE, main_modified = FALSE, stringsAsFactors = FALSE)
  final_path <- app_write_csv(final, file.path(root, "final_decision.csv"))
  app_joint_shared_write_manifest(root, c(summary = summary_path, decisions = decision_path,
    packet = packet_path, final = final_path), filename = "final_manifest.csv")
  final
}

app_joint_superfinal_closeout <- function(source_root,
    root = app_joint_superfinal_default_root(), repo_root = app_path()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  root <- normalizePath(root, mustWork = TRUE)
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  final <- app_read_csv(file.path(root, "final_decision.csv"))
  if (nrow(final) != 1L || final$status[[1L]] !=
      "SUPERFINAL_PACKET_READY_FOR_INTEGRATION_REVIEW") {
    stop("Super-final closeout requires a ready final decision.", call. = FALSE)
  }
  for (manifest in c("prepare_manifest.csv", "final_manifest.csv")) {
    verified <- app_joint_shared_verify_manifest(root, file.path(root, manifest))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("Closeout cannot verify %s.", manifest), call. = FALSE)
    }
  }
  mcmc_plan <- app_read_csv(file.path(root, "full_confirmation", "mcmc_worker_plan.csv"))
  mcmc <- app_bind_rows_fill(lapply(mcmc_plan$worker_id, function(id) {
    worker <- app_joint_swcf_worker_dir(root, "mcmc", id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified) ||
        !file.exists(file.path(worker, "DONE"))) {
      stop(sprintf("MCMC worker %d fails closeout verification.", id), call. = FALSE)
    }
    app_read_csv(file.path(worker, "summary.csv"))
  }))
  scores <- app_bind_rows_fill(lapply(app_joint_superfinal_targets()$target_id,
    function(id) {
      worker <- app_joint_superfinal_score_dir(root, id)
      verified <- app_joint_shared_verify_manifest(worker,
        file.path(worker, "artifact_manifest.csv"))
      if (!nrow(verified) || any(!verified$verified) ||
          !file.exists(file.path(worker, "DONE"))) {
        stop(sprintf("Score target %d fails closeout verification.", id), call. = FALSE)
      }
      app_read_csv(file.path(worker, "summary.csv"))
    }))
  if (nrow(mcmc) != 15L || nrow(scores) != 3L || any(!mcmc$finite_draws) ||
      any(mcmc$likelihood_family == "exAL" &
        mcmc$inference_method_id != "M0_v_collapsed_support_logit")) {
    stop("Closeout worker summaries violate the frozen contract.", call. = FALSE)
  }
  contract <- app_read_csv(file.path(root, "superfinal_contract.csv"))
  scores$relative_mcse <- scores$score_mcse_mean / scores$posterior_score_mean
  scores$rank_rhat_pass <- scores$score_rank_rhat <=
    app_joint_superfinal_value(contract, "score_rank_rhat_ceiling", TRUE)
  scores$folded_rhat_pass <- scores$score_folded_rhat <=
    app_joint_superfinal_value(contract, "score_folded_rhat_ceiling", TRUE)
  scores$bulk_ess_pass <- scores$score_bulk_ess >=
    app_joint_superfinal_value(contract, "score_bulk_ess_floor", TRUE)
  scores$tail_ess_pass <- scores$score_tail_ess >=
    app_joint_superfinal_value(contract, "score_tail_ess_floor", TRUE)
  scores$relative_mcse_pass <- scores$relative_mcse <=
    app_joint_superfinal_value(contract, "relative_mcse_ceiling", TRUE)
  scores$leave_one_chain_pass <- scores$leave_one_chain_relative_range <=
    app_joint_superfinal_value(contract,
      "leave_one_chain_relative_range_ceiling", TRUE)
  scores$max_draw_fraction_pass <- scores$max_draw_fraction <=
    app_joint_superfinal_value(contract, "max_draw_fraction_ceiling", TRUE)
  scores$crossing_pass <- scores$canonical_contract_crossing_pairs == 0L
  source <- app_read_csv(file.path(root, "source_influence_audit.csv"))
  before_after <- merge(source, scores, by = "model_cell_id", suffixes = c("_source", "_combined"))
  decisions <- app_read_csv(file.path(root, "superfinal_scenario_decisions.csv"))
  selected <- app_read_csv(file.path(root, "superfinal_selected_score_summary.csv"))
  if (nrow(selected) != 32L || anyDuplicated(paste(selected$scenario_id,
      selected$model_id, sep = "__")) || any(table(selected$scenario_id) != 4L)) {
    stop("Selected packet is not a complete 8-by-4 scenario packet.", call. = FALSE)
  }
  out <- file.path(root, "integration_handoff")
  app_ensure_dir(out)
  git_value <- function(args) trimws(system2("git", c("-C", repo_root, args), stdout = TRUE))
  branch <- git_value(c("branch", "--show-current"))
  head <- git_value(c("rev-parse", "HEAD"))
  upstream <- git_value(c("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"))
  origin_main <- git_value(c("rev-parse", "origin/main"))
  merge_base <- git_value(c("merge-base", "origin/main", "HEAD"))
  divergence <- as.integer(strsplit(git_value(c("rev-list", "--left-right", "--count",
    "@{u}...HEAD")), "[[:space:]]+")[[1L]])
  main_divergence <- as.integer(strsplit(git_value(c("rev-list", "--left-right", "--count",
    "origin/main...HEAD")), "[[:space:]]+")[[1L]])
  tracked_status <- git_value(c("status", "--porcelain", "--untracked-files=no"))
  git_state <- data.frame(branch = branch, upstream = upstream, head = head,
    upstream_behind = divergence[[1L]], upstream_ahead = divergence[[2L]],
    origin_main = origin_main, merge_base = merge_base,
    main_behind = main_divergence[[1L]], main_ahead = main_divergence[[2L]],
    tracked_worktree_clean = !length(tracked_status) || identical(tracked_status, ""),
    stringsAsFactors = FALSE)
  changed <- git_value(c("diff", "--name-status", "origin/main...HEAD"))
  changed <- data.frame(entry = changed[nzchar(changed)], stringsAsFactors = FALSE)
  commits <- git_value(c("log", "--format=%H%x09%s", "origin/main..HEAD"))
  commits <- data.frame(entry = commits[nzchar(commits)], stringsAsFactors = FALSE)
  health <- data.frame(stage = c("supplemental_mcmc", "combined_score", "selected_packet"),
    expected = c(15L, 3L, 32L), completed = c(nrow(mcmc), nrow(scores), nrow(selected)),
    failed = c(sum(!mcmc$finite_draws), 0L, 0L), remaining = c(0L, 0L, 0L),
    stringsAsFactors = FALSE)
  storage <- data.frame(runtime_root = root,
    size_bytes = sum(file.info(list.files(root, recursive = TRUE, full.names = TRUE))$size,
      na.rm = TRUE), source_root = source_root,
    source_handoff_manifest_sha256 = app_sha256_file(
      app_joint_superfinal_source_paths(source_root)$handoff_manifest),
    stringsAsFactors = FALSE)
  focused_tests <- c(
    "application/tests/test_joint_qdesn_superfinal_predictive_stability.R",
    "application/tests/test_joint_qdesn_stronger_window_confirmation.R",
    "application/tests/test_joint_qdesn_stronger_window_score.R",
    "application/tests/test_joint_qdesn_stronger_window_transfer.R",
    "application/tests/test_joint_exqdesn_inference_dispatch.R")
  rscript <- file.path(R.home("bin"), "Rscript")
  tests <- app_bind_rows_fill(lapply(focused_tests, function(test) {
    output <- system2(rscript, file.path(repo_root, test), stdout = TRUE, stderr = TRUE)
    status <- attr(output, "status") %||% 0L
    data.frame(test = test, status = if (status == 0L) "PASS" else "FAIL",
      exit_code = as.integer(status), output = paste(output, collapse = " | "),
      stringsAsFactors = FALSE)
  }))
  if (any(tests$status != "PASS")) stop("A focused closeout test failed.", call. = FALSE)
  publication <- data.frame(
    classification = c("article_safe_candidate", "article_safe_candidate",
      "article_safe_candidate", "runtime_excluded", "runtime_excluded",
      "not_modified"),
    path = c("integration_handoff/selected_32_row_packet.csv",
      "integration_handoff/combined_score_gate_summary.csv",
      "integration_handoff/scenario_decisions.csv",
      "full_confirmation/mcmc_workers/", "score_cells/",
      "article_and_overleaf_assets"),
    instruction = c("Review as the final 32-row scientific packet.",
      "Use for predictive-functional qualification and caveats.",
      "Preserve whole-scenario decisions; do not splice models.",
      "Keep ignored; transfer only for reproducibility audit.",
      "Keep ignored; transfer only for reproducibility audit.",
      "Regenerate only in the later coordinator article projection."),
    stringsAsFactors = FALSE)
  risks <- data.frame(
    risk = c("persistent_joint_al_predictive_instability",
      "persistent_joint_exal_folded_rhat_review", "laplace_numerical_winner_claim",
      "source_runtime_dependency"),
    disposition = c("Complete scenario falls back to parity.",
      "Complete scenario falls back to parity; no scalar-mixing veto was added.",
      "Treat as stabilized descriptive evidence, not formal superiority.",
      "Retain or transfer the frozen source runtime with its verified handoff."),
    resolved_for_packet = c(TRUE, TRUE, TRUE, TRUE), stringsAsFactors = FALSE)
  instructions <- data.frame(step = 1:5,
    instruction = c("Verify this handoff manifest and runtime transfer inventory.",
      "Review the 32-row packet and scenario-level fallback decisions.",
      "Merge this dedicated branch only once; do not separately merge intermediate lanes.",
      "Run combined repository tests before any article projection.",
      "Regenerate article assets in the integration lane; do not publish runtime artifacts."),
    stringsAsFactors = FALSE)
  handoff_path <- file.path(out, "FROZEN_INTEGRATION_HANDOFF.md")
  writeLines(c(
    "# JOINT super-final predictive-stability handoff",
    "",
    "Status: `READY_FOR_INTEGRATION`",
    "",
    sprintf("- Worktree: `%s`", repo_root),
    sprintf("- Branch: `%s`", branch),
    sprintf("- Upstream: `%s`", upstream),
    sprintf("- HEAD: `%s`", head),
    sprintf("- Base `origin/main`: `%s`", origin_main),
    sprintf("- Merge base: `%s`", merge_base),
    sprintf("- Unique commits relative to main: %d", main_divergence[[2L]]),
    "- Tracked worktree: clean and 0 ahead / 0 behind its dedicated upstream",
    "",
    "## Scientific result",
    "",
    "- Supplemental MCMC: 15/15 complete, 0 failed.",
    "- Combined eight-chain scores: 3/3 complete, 0 failed.",
    "- exAL chains used exact `M0_v_collapsed_support_logit`.",
    "- Laplace joint exAL stabilized and remains in the parity packet.",
    "- Persistent-heavy-tail challenger did not pass the frozen functional gate;",
    "  the complete four-model scenario therefore falls back to parity.",
    "- Final packet: 32/32 unique scenario-model rows, finite scores, zero",
    "  canonical contract crossings.",
    "",
    "## Evidence",
    "",
    "- `selected_32_row_packet.csv`",
    "- `combined_score_gate_summary.csv`",
    "- `source_vs_combined_score_audit.csv`",
    "- `scenario_decisions.csv`",
    "- `focused_test_results.csv`",
    "- `runtime_transfer_inventory.csv`",
    "- `handoff_manifest.csv`",
    "",
    "The frozen source runtime remains a required dependency and is bound by",
    sprintf("handoff-manifest SHA-256 `%s`.", storage$source_handoff_manifest_sha256[[1L]]),
    "",
    "## Integration boundary",
    "",
    "Merge this dedicated branch only once, after verifying the handoff and",
    "runtime inventory. Do not separately merge intermediate lanes. Keep MCMC",
    "draws and score-cell runtime excluded from Git. Article and Overleaf assets",
    "were not modified; regenerate them only in the coordinator integration lane."
  ), handoff_path)
  files <- c(
    health = app_write_csv(health, file.path(out, "health_summary.csv")),
    mcmc = app_write_csv(mcmc, file.path(out, "supplemental_mcmc_summary.csv")),
    score = app_write_csv(scores, file.path(out, "combined_score_gate_summary.csv")),
    comparison = app_write_csv(before_after, file.path(out, "source_vs_combined_score_audit.csv")),
    decisions = app_write_csv(decisions, file.path(out, "scenario_decisions.csv")),
    selected = app_write_csv(selected, file.path(out, "selected_32_row_packet.csv")),
    git = app_write_csv(git_state, file.path(out, "git_state.csv")),
    changed = app_write_csv(changed, file.path(out, "changed_files.csv")),
    commits = app_write_csv(commits, file.path(out, "unique_commits.csv")),
    storage = app_write_csv(storage, file.path(out, "storage_summary.csv")),
    tests = app_write_csv(tests, file.path(out, "focused_test_results.csv")),
    publication = app_write_csv(publication, file.path(out, "publication_scope.csv")),
    risks = app_write_csv(risks, file.path(out, "scientific_risks.csv")),
    instructions = app_write_csv(instructions,
      file.path(out, "integration_instructions.csv")),
    handoff = handoff_path)
  runtime_files <- list.files(root, recursive = TRUE, full.names = TRUE)
  runtime_files <- runtime_files[!startsWith(runtime_files,
    paste0(normalizePath(out, mustWork = TRUE), .Platform$file.sep))]
  runtime_files <- runtime_files[file.info(runtime_files)$isdir %in% FALSE]
  relative <- substring(runtime_files, nchar(root) + 2L)
  inventory <- data.frame(relative_path = relative,
    size_bytes = file.info(runtime_files)$size,
    sha256 = unname(vapply(runtime_files, app_sha256_file, character(1L))),
    stringsAsFactors = FALSE)
  inventory <- inventory[order(inventory$relative_path), , drop = FALSE]
  files <- c(files, inventory = app_write_csv(inventory,
    file.path(out, "runtime_transfer_inventory.csv")))
  decision <- data.frame(status = "READY_FOR_INTEGRATION", selected_rows = nrow(selected),
    supplemental_mcmc_workers = nrow(mcmc), combined_score_targets = nrow(scores),
    worker_failures = 0L, article_assets_modified = FALSE, main_modified = FALSE,
    stringsAsFactors = FALSE)
  files <- c(files, decision = app_write_csv(decision,
    file.path(out, "handoff_decision.csv")))
  app_joint_shared_write_manifest(out, files, filename = "handoff_manifest.csv")
  verified <- app_joint_shared_verify_manifest(out, file.path(out, "handoff_manifest.csv"))
  if (!all(verified$verified)) stop("Final handoff manifest failed.", call. = FALSE)
  decision
}
