# Prior-only experiment: frozen case-specific DESNs and original-order diagnostics.

app_joint_prior_contract <- function() {
  tab <- app_read_csv(app_path("application/config/joint_qdesn_fixed_backbone_prior_contract_v1.csv"))
  if (anyDuplicated(tab$name)) stop("Duplicate experiment contract keys.")
  out <- as.list(setNames(as.character(tab$value), tab$name))
  for (key in names(out)) {
    if (key %in% c("scenarios", "anchor_multipliers", "innovation_multipliers")) {
      out[[key]] <- strsplit(out[[key]], ";", fixed = TRUE)[[1L]]
      if (key != "scenarios") out[[key]] <- as.numeric(out[[key]])
    } else if (grepl("^[0-9.]+$", out[[key]])) out[[key]] <- as.numeric(out[[key]])
  }
  stopifnot(out$max_workers == 15, out$screen_replicates == 2, out$screen_chains == 2,
    out$confirmation_chains == 3, out$exal_mcmc_method == "M0_v_collapsed_support_logit",
    out$exal_vb_method == "VB1_structured_v", out$publication_allowed == "false",
    all(out$anchor_multipliers > 0), all(out$innovation_multipliers > 0))
  out$tau <- c(.05, .10, .25, .50, .75, .90, .95)
  out$weights <- c(.025, .1, .2, .25, .2, .1, .025)
  out
}

app_joint_prior_arms <- function(contract = app_joint_prior_contract()) {
  out <- expand.grid(anchor_multiplier = contract$anchor_multipliers,
    innovation_multiplier = contract$innovation_multipliers)
  out$arm_id <- sprintf("prior_%02d", seq_len(nrow(out)))
  out$baseline <- out$anchor_multiplier == 1 & out$innovation_multiplier == 1
  stopifnot(nrow(out) == 15L, sum(out$baseline) == 1L)
  out
}

app_joint_prior_vb_contract <- function(contract = app_joint_prior_contract()) {
  out <- app_joint_article_read_contract(app_path(
    "application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v4.csv"))
  out$evaluation_replicates <- 1L
  out$al_max_iter <- out$exal_max_iter <- as.integer(contract$vb_max_iterations)
  out$max_dense_dim <- 336L
  out
}

app_joint_prior_done <- function(path) {
  if (!file.exists(file.path(path, "DONE"))) return(FALSE)
  checked <- tryCatch(app_joint_shared_verify_manifest(path,
    file.path(path, "artifact_manifest.csv")), error = function(e) NULL)
  is.data.frame(checked) && nrow(checked) > 0 && all(checked$verified)
}

app_joint_prior_seal <- function(path) {
  paths <- list.files(path, full.names = TRUE)
  paths <- paths[!basename(paths) %in% c("DONE", "FAILED", "RUNNING", "artifact_manifest.csv", "stdout.log")]
  paths <- paths[!dir.exists(paths)]
  app_joint_shared_write_manifest(path, setNames(paths, basename(paths)))
  writeLines("VERIFIED", file.path(path, "DONE"))
  stopifnot(app_joint_prior_done(path))
}

app_joint_prior_verify_freeze <- function(root) {
  checked <- app_joint_shared_verify_manifest(root, file.path(root, "freeze_manifest.csv"))
  if (!nrow(checked) || any(!checked$verified)) stop("Experiment freeze changed.")
  source <- app_read_csv(file.path(root, "source_manifest.csv"))
  observed <- vapply(file.path(app_path(), source$relative_path), app_sha256_file, character(1L))
  if (!identical(unname(observed), as.character(source$sha256))) stop("Frozen source files changed.")
  head <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
  if (head != readLines(file.path(root, "source_head.txt"))) stop("Execution HEAD changed.")
  invisible(TRUE)
}

app_joint_prior_prepare <- function(root) {
  if (dir.exists(root)) stop("Preparation will not overwrite an existing experiment.")
  ct <- app_joint_prior_contract(); arms <- app_joint_prior_arms(ct)
  app_ensure_dir(root); saveRDS(ct, file.path(root, "contract.rds"))
  app_write_csv(arms, file.path(root, "arms.csv"))
  backbones <- app_read_csv(app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv"))
  backbones <- backbones[match(ct$scenarios, backbones$scenario_id), , drop = FALSE]
  stopifnot(nrow(backbones) == 2L, !anyNA(backbones$scenario_id),
    !any(backbones$raw_inputs_in_readout), all(backbones$full_states_all_layers))
  app_write_csv(backbones, file.path(root, "backbones.csv"))
  source <- unique(c(list.files(app_path("application/R"), "\\.R$", full.names = TRUE),
    list.files(app_path("application/scripts"), "joint.*\\.(R|sh)$", full.names = TRUE),
    list.files(app_path("application/config"), "joint.*\\.csv$", full.names = TRUE),
    app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv")))
  app_write_csv(data.frame(relative_path = substring(source, nchar(app_path()) + 2L),
    sha256 = vapply(source, app_sha256_file, character(1L))), file.path(root, "source_manifest.csv"))
  writeLines(system2("git", c("rev-parse", "HEAD"), stdout = TRUE), file.path(root, "source_head.txt"))
  writeLines(capture.output(sessionInfo()), file.path(root, "session_info.txt"))
  files <- list.files(root, full.names = TRUE)
  app_joint_shared_write_manifest(root, setNames(files, basename(files)))
  stopifnot(file.rename(file.path(root, "artifact_manifest.csv"), file.path(root, "freeze_manifest.csv")))
  app_joint_prior_stage_prepare(root, "screen")
  invisible(root)
}

app_joint_prior_verify_selection <- function(root) {
  x <- app_read_csv(file.path(root, "screen", "selection_manifest.csv"))
  sha <- vapply(file.path(root, "screen", x$relative_path), app_sha256_file, character(1L))
  if (!identical(unname(sha), x$sha256)) stop("Selection receipt changed.")
}

app_joint_prior_stage_prepare <- function(root, stage) {
  stopifnot(stage %in% c("screen", "confirmation"))
  app_joint_prior_verify_freeze(root)
  ct <- readRDS(file.path(root, "contract.rds")); arms <- app_read_csv(file.path(root, "arms.csv"))
  base <- arms$arm_id[arms$baseline]; dest <- file.path(root, stage)
  if (dir.exists(dest)) stop("Stage already prepared.")
  if (stage == "confirmation") {
    stopifnot(file.exists(file.path(root, "screen", "SELECTION_FROZEN")))
    app_joint_prior_verify_selection(root)
    selection <- app_read_csv(file.path(root, "screen", "selection.csv"))
    expected_keys <- as.vector(outer(ct$scenarios, c("AL", "exAL"), paste, sep = ":"))
    keys <- paste(selection$scenario_id, selection$likelihood, sep = ":")
    stopifnot(nrow(selection) == 4L, !anyDuplicated(keys), setequal(keys, expected_keys),
      all(selection$arm_id %in% arms$arm_id), all(selection$baseline_arm_id == base))
  }
  app_ensure_dir(dest)
  datasets <- expand.grid(scenario_id = ct$scenarios,
    replicate_id = seq_len(ct[[paste0(stage, "_replicates")]]), stringsAsFactors = FALSE)
  datasets$dataset_id <- seq_len(nrow(datasets))
  datasets$dgp_seed <- ct[[paste0(stage, "_seed_base")]] + datasets$dataset_id * 100L
  cells <- list()
  for (d in seq_len(nrow(datasets))) for (likelihood in c("AL", "exAL")) {
    scenario <- datasets$scenario_id[[d]]
    chosen <- if (stage == "screen") arms$arm_id else unique(c(base,
      selection$arm_id[selection$scenario_id == scenario & selection$likelihood == likelihood]))
    for (arm in chosen) cells[[length(cells) + 1L]] <- data.frame(dataset_id = d,
      scenario_id = scenario, replicate_id = datasets$replicate_id[[d]], likelihood = likelihood,
      structure = "joint", arm_id = arm, long_budget = FALSE)
    cells[[length(cells) + 1L]] <- data.frame(dataset_id = d, scenario_id = scenario,
      replicate_id = datasets$replicate_id[[d]], likelihood = likelihood,
      structure = "independent", arm_id = base, long_budget = FALSE)
    if (stage == "screen" && likelihood == "AL") cells[[length(cells) + 1L]] <- data.frame(
      dataset_id = d, scenario_id = scenario, replicate_id = datasets$replicate_id[[d]],
      likelihood = likelihood, structure = "joint", arm_id = base, long_budget = TRUE)
  }
  cells <- do.call(rbind, cells); cells$cell_id <- seq_len(nrow(cells))
  chains <- as.integer(ct[[paste0(stage, "_chains")]])
  jobs <- cells[rep(seq_len(nrow(cells)), each = chains), , drop = FALSE]
  jobs$chain_id <- rep(seq_len(chains), nrow(cells)); jobs$worker_id <- seq_len(nrow(jobs))
  offset <- if (stage == "screen") 0L else 1000000L
  jobs$chain_seed <- ct$chain_seed_base + offset + jobs$worker_id * 1009L
  jobs$start_seed <- ct$initialization_seed_base + offset + jobs$worker_id * 1009L
  for (k in seq_along(ct$tau)) jobs[[paste0("component_seed_", k)]] <-
    jobs$chain_seed + 100000L + k * 7919L
  warm <- unique(cells[cells$structure == "joint", c("dataset_id", "arm_id")])
  warm$worker_id <- seq_len(nrow(warm))
  app_write_csv(datasets, file.path(dest, "datasets.csv"))
  app_write_csv(cells, file.path(dest, "cells.csv")); app_write_csv(jobs, file.path(dest, "chains.csv"))
  app_write_csv(warm, file.path(dest, "warmups.csv"))
  paths <- list.files(dest, full.names = TRUE)
  app_joint_shared_write_manifest(dest, setNames(paths, basename(paths)))
  stopifnot(file.rename(file.path(dest, "artifact_manifest.csv"), file.path(dest, "plan_manifest.csv")))
  invisible(list(cells = cells, jobs = jobs))
}

app_joint_prior_context <- function(root, stage, dataset_id) {
  folder <- file.path(root, stage, "datasets", sprintf("dataset_%02d", dataset_id))
  if (!app_joint_prior_done(folder)) stop("Dataset context is not verified.")
  checked <- app_joint_shared_verify_manifest(folder, file.path(folder, "component_manifest.csv"))
  if (!all(checked$verified)) stop("Nested initialization files changed.")
  readRDS(file.path(folder, "context.rds"))
}

app_joint_prior_dataset <- function(root, stage, dataset_id) {
  ct <- readRDS(file.path(root, "contract.rds")); vc <- app_joint_prior_vb_contract(ct)
  row <- app_read_csv(file.path(root, stage, "datasets.csv"))[dataset_id, , drop = FALSE]
  selected <- app_read_csv(file.path(root, "backbones.csv"))
  selected <- selected[selected$scenario_id == row$scenario_id, , drop = FALSE]
  dgp <- app_joint_qdesn_load_simulation_registry()
  sc <- dgp[dgp$scenario_id == row$scenario_id, , drop = FALSE]
  sc$seed <- row$dgp_seed; sc$seed_role <- paste0("fixed_backbone_prior_", stage)
  fixture <- app_joint_qdesn_fixture_from_registry_row(sc); fixture$registry_row <- sc
  if (stage == "screen") {
    pure <- app_joint_pure_read_contract(); pure$max_readout_dimension <- 300L
    selector <- app_joint_pure_selector_fixture(fixture, pure)
    design <- app_joint_pure_build_design(selector, selected, pure, selector = TRUE)
    design$fit_local <- design$train_local; design$validation_local <- design$calibration_local
    full <- design$row_meta$full_time_index[design$calibration_local]
    design$forecast_map <- data.frame(origin_index = rep(1:5, each = 30L),
      horizon = rep(1:30, 5L), full_time_index = full)
    end <- max(design$row_meta$full_time_index)
    for (name in c("y", "mu", "sigma", "innovation", "innovation_raw")) {
      fixture[[name]] <- fixture[[name]][seq_len(end)]
    }
    fixture$true_q <- fixture$true_q[seq_len(end), , drop = FALSE]
    fixture$detailed_split <- fixture$detailed_split[seq_len(end), , drop = FALSE]
    fixture$Z <- fixture$Z[seq_len(end), , drop = FALSE]
    design$design_fingerprint <- digest::digest(design$Z[design$fit_local, ], algo = "sha256")
  } else design <- app_joint_pure_full_design(fixture, selected, app_joint_pure_read_contract())
  target_data <- list(y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE])
  gaussian <- app_joint_shared_quantile_gaussian_worker(NULL, design, selected, vc)
  context <- list(design = design, fixture = fixture, selected = selected,
    gaussian = gaussian$fit, vc = vc, data_hash = digest::digest(target_data, algo = "sha256"))
  # Reuse the established Gaussian -> median-outward AL -> paired exAL graph.
  folder <- file.path(root, stage, "datasets", sprintf("dataset_%02d", dataset_id))
  app_ensure_dir(folder); plan <- app_joint_shared_quantile_job_plan(vc)
  g <- plan[plan$model_id == "gaussian_rhs_initializer", , drop = FALSE]
  gdir <- app_joint_shared_quantile_worker_dir(folder, g$job_id)
  app_ensure_dir(gdir); saveRDS(gaussian$fit, file.path(gdir, "fit_initializer.rds"))
  for (i in which(plan$model_id %in% c("independent_qdesn_rhs", "independent_exqdesn_rhs"))) {
    job <- plan[i, , drop = FALSE]
    result <- if (job$model_id == "independent_qdesn_rhs") {
      app_joint_shared_quantile_independent_al_worker(folder, job, plan, design, vc)
    } else app_joint_shared_quantile_independent_exal_worker(folder, job, plan, design, vc)
    idir <- app_joint_shared_quantile_worker_dir(folder, job$job_id)
    app_ensure_dir(idir); saveRDS(result$fit, file.path(idir, "fit_initializer.rds"))
  }
  context$independent_al <- app_joint_shared_quantile_stack_independent(folder, plan, 1L,
    "independent_qdesn_rhs", design, slab_fixed = vc$rhs_slab_fixed)
  context$independent_exal <- app_joint_shared_quantile_stack_independent(folder, plan, 1L,
    "independent_exqdesn_rhs", design, slab_fixed = vc$rhs_slab_fixed)
  shards <- character()
  for (s in seq_len(ct$oracle_max_shards)) {
    path <- file.path(folder, sprintf("oracle_shard_%02d.rds", s))
    saveRDS(app_joint_recursive_dgp_shard(fixture, design$forecast_map,
      n_paths = ct$oracle_paths_per_shard, seed = as.integer(row$dgp_seed + 5000L + s)), path)
    shards <- c(shards, path)
    if (s %% 2L == 0L) {
      oracle <- app_joint_recursive_combine_oracle_shards(shards, fixture, ct$tau, ct$weights,
        ct$oracle_analytic_tolerance, ct$oracle_split_tolerance)
      if (oracle$diagnostics$status == "pass") break
    }
  }
  if (oracle$diagnostics$status != "pass") stop("Oracle integration failed after eight shards.")
  saveRDS(oracle, file.path(folder, "oracle.rds"))
  app_write_csv(oracle$diagnostics, file.path(folder, "oracle_diagnostics.csv"))
  saveRDS(context, file.path(folder, "context.rds"))
  # Compact nested initializers are covered by a separate nested manifest.
  paths <- list.files(file.path(folder, "workers"), recursive = TRUE, full.names = TRUE)
  app_joint_shared_write_manifest(folder, setNames(c(file.path(folder, "context.rds"), paths),
    c("context", paste0("component_", seq_along(paths)))), filename = "component_manifest.csv")
  app_joint_prior_seal(folder)
}

app_joint_prior_controls <- function(context, arm, independent = FALSE) {
  vc <- context$vc; g <- context$gaussian; tau0 <- context$selected$rhs_tau0[[1L]]
  list(tau0 = tau0, anchor_tau0 = tau0 * arm$anchor_multiplier[[1L]],
    innovation_tau0 = tau0 * arm$innovation_multiplier[[1L]],
    zeta2 = vc$rhs_slab_variance, anchor_zeta2 = vc$rhs_slab_variance,
    innovation_zeta2 = vc$rhs_slab_variance, slab_fixed = vc$rhs_slab_fixed,
    a_sigma = vc$a_sigma, b_sigma = vc$b_sigma,
    alpha_prior_mean = g$initializer$alpha_mean,
    alpha_prior_sd = g$initializer$alpha_prior_sd,
    alpha_min_spacing = if (independent) 0 else vc$alpha_min_spacing,
    sigma_bounds = c(vc$sigma_lower_bound, vc$sigma_upper_bound),
    max_dense_dim = max(300L, ncol(context$design$Z) * length(context$design$tau)), kappa = 1)
}

app_joint_prior_target <- function(context, controls, likelihood, structure) {
  digest::digest(list(version = "fixed_backbone_prior_target_v1", data = context$data_hash,
    likelihood = likelihood, structure = structure, tau = context$design$tau, controls = controls,
    gamma_prior = if (likelihood == "exAL") "none" else "not_applicable",
    hierarchy = if (structure == "joint") "first_quantile_anchor_adjacent_differences" else "independent"), algo = "sha256")
}

app_joint_prior_vb <- function(context, arm) {
  d <- context$design; vc <- context$vc; p <- ncol(d$Z); K <- length(d$tau)
  controls <- app_joint_prior_controls(context, arm); controls$sigma_bounds <- NULL
  init <- context$independent_al
  init$rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = controls$tau0,
    zeta2 = controls$zeta2, anchor_tau0 = controls$anchor_tau0,
    innovation_tau0 = controls$innovation_tau0, slab_fixed = controls$slab_fixed)
  common <- c(list(y = d$y[d$fit_local], Z = d$Z[d$fit_local, , drop = FALSE],
    tau = d$tau, max_iter = vc$al_max_iter, tol = vc$vb_tolerance,
    rhs_vb_inner = vc$rhs_vb_inner, rhs_freeze_iters = 0L), controls)
  al <- do.call(app_joint_qvp_fit_al_vb_tiny,
    c(common, list(init = app_joint_shared_quantile_reset_init(init))))
  exinit <- context$independent_exal; exinit$rhs_state <- al$rhs_state
  exal <- do.call(app_joint_exqdesn_fit_vb_dispatch, c(common, list(method_id = "VB1_structured_v",
    gamma_init = rep(0, K), diagnostic_stride = 20L, quadrature_nodes = c(4L, 8L, 12L),
    quadrature_tolerance = 1e-5, init = app_joint_shared_quantile_reset_init(exinit))))
  list(AL = al, exAL = exal)
}

app_joint_prior_warmup <- function(root, stage, worker_id) {
  row <- app_read_csv(file.path(root, stage, "warmups.csv"))[worker_id, , drop = FALSE]
  context <- app_joint_prior_context(root, stage, row$dataset_id)
  arms <- app_read_csv(file.path(root, "arms.csv")); arm <- arms[arms$arm_id == row$arm_id, , drop = FALSE]
  folder <- file.path(root, stage, "warmups", sprintf("worker_%03d", worker_id))
  app_ensure_dir(folder); fits <- app_joint_prior_vb(context, arm)
  saveRDS(fits, file.path(folder, "initializers.rds"))
  app_write_csv(data.frame(likelihood = c("AL", "exAL"),
    converged = vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    file.path(folder, "vb_health.csv"))
  app_joint_prior_seal(folder)
}

app_joint_prior_mcmc_fit <- function(context, arm, job, ct, stage) {
  d <- context$design; independent <- job$structure == "independent"
  controls <- app_joint_prior_controls(context, arm, independent)
  family <- tolower(job$likelihood); prefix <- if (job$long_budget) "confirmation" else stage
  args <- c(list(y = d$y[d$fit_local], Z = d$Z[d$fit_local, , drop = FALSE], tau = d$tau,
    n_iter = as.integer(ct[[paste0(prefix, "_", family, "_iterations")]]),
    burn = as.integer(ct[[paste0(prefix, "_", family, "_burn")]]),
    thin = as.integer(ct[[paste0(prefix, "_thin")]]), seed = as.integer(job$chain_seed),
    precision_repair = TRUE, precision_repair_start_rel = 1e-12, precision_repair_max_rel = 1e-8), controls)
  init <- if (independent) context[[paste0("independent_", family)]] else context$initializer
  init <- init[intersect(names(init), c("beta_mean", "alpha_mean", "sigma_mean", "gamma_mean", "fits"))]
  init <- app_joint_article_overdispersed_start(init,
    data.frame(chain_start_seed = as.integer(job$start_seed)), d$tau)
  args$init <- init
  if (!independent) {
    fit <- if (family == "al") do.call(app_joint_qvp_fit_al_mcmc_tiny, args) else {
      do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(list(method_id = ct$exal_mcmc_method), args))
    }
  } else {
    fits <- lapply(seq_along(d$tau), function(k) {
      one <- args; one$tau <- d$tau[[k]]; one$alpha_prior_mean <- args$alpha_prior_mean[[k]]
      one$init <- init$fits[[k]]; one$seed <- as.integer(job$chain_seed + 100000L + k * 7919L)
      if (family == "al") do.call(app_joint_qvp_fit_al_mcmc_tiny, one) else {
        do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(list(method_id = ct$exal_mcmc_method), one))
      }
    })
    fit <- list(beta_draws = do.call(cbind, lapply(fits, "[[", "beta_draws")),
      alpha_draws = do.call(cbind, lapply(fits, "[[", "alpha_draws")),
      sigma_draws = do.call(cbind, lapply(fits, "[[", "sigma_draws")),
      component_method_ids = vapply(fits,
        function(x) x$inference_method_id %||% "AL_latent_GIG_Gibbs", character(1L)),
      precision_components = lapply(fits, function(x) x$precision_repair_diagnostics %||% x$manifest))
    if (family == "exal") fit$gamma_draws <- do.call(cbind, lapply(fits, "[[", "gamma_draws"))
  }
  list(fit = fit, target_hash = app_joint_prior_target(context, controls, job$likelihood, job$structure),
    iterations = args$n_iter, burn = args$burn, thin = args$thin)
}

app_joint_prior_chain <- function(root, stage, worker_id) {
  ct <- readRDS(file.path(root, "contract.rds"))
  job <- app_read_csv(file.path(root, stage, "chains.csv"))[worker_id, , drop = FALSE]
  context <- app_joint_prior_context(root, stage, job$dataset_id)
  arms <- app_read_csv(file.path(root, "arms.csv")); arm <- arms[arms$arm_id == job$arm_id, , drop = FALSE]
  if (job$structure == "joint") {
    w <- app_read_csv(file.path(root, stage, "warmups.csv"))
    wid <- w$worker_id[w$dataset_id == job$dataset_id & w$arm_id == job$arm_id]
    wdir <- file.path(root, stage, "warmups", sprintf("worker_%03d", wid))
    stopifnot(length(wid) == 1L, app_joint_prior_done(wdir))
    context$initializer <- readRDS(file.path(wdir, "initializers.rds"))[[job$likelihood]]
  }
  folder <- file.path(root, stage, "chains", sprintf("worker_%04d", worker_id))
  app_ensure_dir(folder); started <- Sys.time()
  result <- app_joint_prior_mcmc_fit(context, arm, job, ct, stage)
  draws <- app_joint_article_draw_frame(result$fit)
  app_joint_article_write_gzip_csv(draws, file.path(folder, "posterior_draws.csv.gz"))
  method <- if (job$likelihood == "exAL") ct$exal_mcmc_method else "AL_latent_GIG_Gibbs"
  if (job$likelihood == "exAL") {
    observed <- result$fit$component_method_ids %||% result$fit$inference_method_id
    stopifnot(length(observed) > 0L, all(observed == method))
  }
  app_write_csv(cbind(job, data.frame(target_hash = result$target_hash, method = method,
    retained_draws = nrow(draws), iterations = result$iterations, burn = result$burn, thin = result$thin,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))), file.path(folder, "metadata.csv"))
  saveRDS(list(manifest = result$fit$manifest, diagnostics = result$fit$precision_repair_diagnostics,
    components = result$fit$precision_components), file.path(folder, "precision_diagnostics.rds"))
  app_joint_prior_seal(folder)
}

app_joint_prior_diagnostics <- function(frames) {
  cols <- setdiff(names(frames[[1L]]), "draw_index")
  do.call(rbind, lapply(cols, function(col) {
    m <- do.call(cbind, lapply(frames, "[[", col))
    split <- app_joint_exqdesn_split_chains(m)
    rhat <- app_joint_exqdesn_classic_rhat(app_joint_exqdesn_rank_normalize(split))
    folded <- app_joint_exqdesn_classic_rhat(app_joint_exqdesn_rank_normalize(abs(split - stats::median(split))))
    data.frame(parameter = col, rank_rhat = rhat, folded_rhat = folded)
  }))
}

app_joint_prior_functional_diagnostics <- function(frames, Z, tau) {
  p <- ncol(Z)
  probes <- unique(round(seq(1, nrow(Z), length.out = min(9L, nrow(Z)))))
  out <- list()
  for (k in seq_along(tau)) for (t in probes) {
    cols <- ((k - 1L) * p + 1L):(k * p)
    q <- lapply(frames, function(frame) {
      beta <- app_joint_recursive_select_block(frame, "beta")
      alpha <- app_joint_recursive_select_block(frame, "alpha")
      as.vector(beta[, cols, drop = FALSE] %*% Z[t, ]) + alpha[, k]
    })
    split <- app_joint_exqdesn_split_chains(do.call(cbind, q))
    out[[length(out) + 1L]] <- data.frame(forecast_row = t, tau = tau[[k]],
      rank_rhat = app_joint_exqdesn_classic_rhat(app_joint_exqdesn_rank_normalize(split)),
      folded_rhat = app_joint_exqdesn_classic_rhat(app_joint_exqdesn_rank_normalize(abs(split - stats::median(split)))))
  }
  do.call(rbind, out)
}

app_joint_prior_score <- function(root, stage, cell_id) {
  ct <- readRDS(file.path(root, "contract.rds"))
  job <- app_read_csv(file.path(root, stage, "cells.csv"))[cell_id, , drop = FALSE]
  context <- app_joint_prior_context(root, stage, job$dataset_id); d <- context$design
  plan <- app_read_csv(file.path(root, stage, "chains.csv")); chains <- plan[plan$cell_id == cell_id, , drop = FALSE]
  directories <- file.path(root, stage, "chains", sprintf("worker_%04d", chains$worker_id))
  if (!all(vapply(directories, app_joint_prior_done, logical(1L)))) stop("Score requires all verified chains.")
  frames <- lapply(directories, function(x) app_read_csv(file.path(x, "posterior_draws.csv.gz")))
  metadata <- do.call(rbind, lapply(directories, function(x) app_read_csv(file.path(x, "metadata.csv"))))
  stopifnot(length(unique(metadata$target_hash)) == 1L, length(unique(vapply(frames, nrow, integer(1L)))) == 1L)
  expected <- ceiling((metadata$iterations - metadata$burn) / metadata$thin)
  stopifnot(all(metadata$retained_draws == expected),
    all(vapply(frames, nrow, integer(1L)) == expected),
    identical(as.integer(metadata$chain_seed), as.integer(chains$chain_seed)))
  diagnostics <- app_joint_prior_diagnostics(frames)
  beta <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, block = "beta"))
  alpha <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, block = "alpha"))
  chain_id <- rep(chains$chain_id, vapply(frames, nrow, integer(1L)))
  source_index <- unlist(lapply(frames, function(x) x$draw_index))
  seed <- ct$score_seed_base + job$dataset_id * 1000L + ifelse(stage == "screen", 0L, 1000000L)
  if (job$structure == "independent") {
    offset <- 0L
    for (i in seq_along(frames)) {
      index <- offset + seq_len(nrow(frames[[i]])); offset <- max(index)
      coupled <- app_joint_recursive_couple_independent(beta[index, , drop = FALSE],
        alpha[index, , drop = FALSE], ncol(d$Z), as.integer(seed + i))
      beta[index, ] <- coupled$beta; alpha[index, ] <- coupled$alpha
    }
  }
  state_rows <- unlist(lapply(split(seq_along(chain_id), chain_id), function(index) {
    index[unique(round(seq(1, length(index), length.out = min(ct$state_draws_per_chain, length(index)))))]
  }), use.names = FALSE)
  set.seed(as.integer(seed))
  uniforms <- matrix(runif(length(state_rows) * nrow(d$forecast_map)), nrow = length(state_rows))
  recursive <- app_joint_recursive_mean_design(d, context$fixture, context$selected,
    beta[state_rows, , drop = FALSE], alpha[state_rows, , drop = FALSE], uniforms,
    half_assignment = app_joint_recursive_half_assignment(chain_id[state_rows]), diagnostic_group = chain_id[state_rows])
  oracle <- readRDS(file.path(root, stage, "datasets", sprintf("dataset_%02d", job$dataset_id), "oracle.rds"))
  scores <- app_joint_recursive_score_draws(recursive$mean_design, beta, alpha, oracle,
    ct$tau, ct$weights, ct$score_chunk_size, chain_id, source_index)
  if (any(!is.finite(scores$origin_marginal_dgp_integrated_acrps)) || any(scores$contract_crossing_pairs != 0)) stop("Invalid score outputs.")
  summary <- app_joint_recursive_draw_summary(scores, "mcmc")
  score_matrix <- do.call(cbind, split(scores$origin_marginal_dgp_integrated_acrps, scores$chain_id))
  modern <- app_joint_exqdesn_modern_diagnostics(score_matrix)
  summary$score_rank_rhat <- max(modern$rank_rhat, modern$folded_rhat)
  summary$score_bulk_ess <- modern$bulk_ess; summary$score_mcse_mean <- modern$mcse_mean
  functionals <- app_joint_prior_functional_diagnostics(frames, recursive$mean_design, ct$tau)
  summary$quantile_functional_max_rhat <- max(functionals$rank_rhat, functionals$folded_rhat)
  halves <- lapply(recursive$half_mean, function(Z) app_joint_recursive_score_draws(Z, beta, alpha, oracle,
    ct$tau, ct$weights, ct$score_chunk_size, chain_id, source_index))
  half_means <- vapply(halves, function(x) mean(x$origin_marginal_dgp_integrated_acrps), numeric(1L))
  chain_means <- colMeans(score_matrix)
  summary$state_half_score_relative_difference <- abs(diff(half_means)) / summary$posterior_score_mean
  summary$chain_score_relative_range <- diff(range(chain_means)) / summary$posterior_score_mean
  summary$functional_status <- if (all(is.finite(c(summary$score_rank_rhat,
      summary$quantile_functional_max_rhat, summary$state_half_score_relative_difference))) &&
    max(summary$score_rank_rhat, summary$quantile_functional_max_rhat) <= ct$functional_review_rhat &&
    max(summary$state_half_score_relative_difference, summary$chain_score_relative_range) <= ct$functional_review_relative_difference) "pass" else "review"
  canonical <- app_joint_recursive_canonical_metrics(recursive$mean_design, colMeans(beta), colMeans(alpha), oracle, ct$tau, ct$weights)
  names(canonical) <- paste0("canonical_", names(canonical))
  fit_raw <- matrix(NA_real_, length(d$fit_local), length(ct$tau))
  for (k in seq_along(ct$tau)) {
    cols <- ((k - 1L) * ncol(d$Z) + 1L):(k * ncol(d$Z))
    fit_raw[, k] <- as.vector(d$Z[d$fit_local, , drop = FALSE] %*% colMeans(beta)[cols]) + colMeans(alpha)[[k]]
  }
  fit_q <- app_joint_qdesn_apply_monotone_contract(fit_raw, ct$tau)$qhat_contract
  summary$fit_oracle_mae <- mean(abs(fit_q - d$true_q[d$fit_local, , drop = FALSE]))
  folder <- file.path(root, stage, "scores", sprintf("cell_%04d", cell_id)); app_ensure_dir(folder)
  app_write_csv(cbind(job, summary, canonical), file.path(folder, "summary.csv"))
  app_write_csv(diagnostics, file.path(folder, "parameter_diagnostics.csv"))
  app_write_csv(functionals, file.path(folder, "quantile_functional_diagnostics.csv"))
  app_write_csv(data.frame(chain_id = chains$chain_id, score_mean = chain_means), file.path(folder, "chain_scores.csv"))
  app_joint_article_write_gzip_csv(scores, file.path(folder, "score_draws.csv.gz"))
  saveRDS(recursive, file.path(folder, "mean_design.rds"))
  app_write_csv(recursive$diagnostics, file.path(folder, "state_diagnostics.csv"))
  app_joint_prior_seal(folder)
}

app_joint_prior_collect <- function(root, stage) {
  cells <- app_read_csv(file.path(root, stage, "cells.csv"))
  folders <- file.path(root, stage, "scores", sprintf("cell_%04d", cells$cell_id))
  if (!all(vapply(folders, app_joint_prior_done, logical(1L)))) stop("Incomplete scoring; selection forbidden.")
  for (kind in c("datasets", "warmups", "chains")) {
    plan <- app_read_csv(file.path(root, stage, paste0(kind, ".csv")))
    width <- switch(kind, datasets = 2L, warmups = 3L, chains = 4L)
    prefix <- if (kind == "datasets") "dataset_" else "worker_"
    paths <- file.path(root, stage, kind, sprintf(paste0(prefix, "%0", width, "d"), seq_len(nrow(plan))))
    if (!all(vapply(paths, app_joint_prior_done, logical(1L)))) stop("Source worker manifests incomplete or changed.")
    if (kind == "datasets") for (path in paths) {
      nested <- app_joint_shared_verify_manifest(path, file.path(path, "component_manifest.csv"))
      if (!all(nested$verified)) stop("Nested VB source changed.")
    }
  }
  do.call(rbind, lapply(folders, function(x) app_read_csv(file.path(x, "summary.csv"))))
}

app_joint_prior_select_rows <- function(rows, ct, baseline) {
  aggregate <- do.call(rbind, lapply(split(rows, rows$arm_id), function(x) {
    data.frame(arm_id = x$arm_id[[1L]], posterior_score_mean = mean(x$posterior_score_mean),
      canonical_score = mean(x$canonical_origin_marginal_dgp_integrated_acrps),
      functional_pass = all(x$functional_status == "pass"), replicate_count = nrow(x))
  }))
  if (any(aggregate$replicate_count != ct$screen_replicates)) stop("Incomplete matched selector replicates.")
  base <- aggregate[aggregate$arm_id == baseline, ]
  if (nrow(base) != 1L || any(!is.finite(aggregate$posterior_score_mean))) stop("Invalid baseline or scores.")
  eligible <- aggregate[aggregate$functional_pass &
    aggregate$posterior_score_mean < base$posterior_score_mean - ct$selection_epsilon, ]
  selected <- if (nrow(eligible)) eligible[order(eligible$posterior_score_mean), ][1L, ] else base
  data.frame(scenario_id = rows$scenario_id[[1L]], likelihood = rows$likelihood[[1L]],
    arm_id = selected$arm_id, baseline_arm_id = baseline, selector_mean = selected$posterior_score_mean,
    baseline_mean = base$posterior_score_mean, improvement = base$posterior_score_mean - selected$posterior_score_mean,
    interpretation = "internal_selection_only_not_article_promotion")
}

app_joint_prior_select <- function(root) {
  app_joint_prior_verify_freeze(root)
  tab <- app_joint_prior_collect(root, "screen"); ct <- readRDS(file.path(root, "contract.rds"))
  arms <- app_read_csv(file.path(root, "arms.csv")); baseline <- arms$arm_id[arms$baseline]
  rows <- tab[tab$structure == "joint" & !tab$long_budget, ]
  grouped <- split(rows, interaction(rows$scenario_id, rows$likelihood, drop = TRUE))
  selection <- lapply(grouped, app_joint_prior_select_rows, ct = ct, baseline = baseline)
  app_write_csv(tab, file.path(root, "screen", "complete_screen_scores.csv"))
  app_write_csv(do.call(rbind, selection), file.path(root, "screen", "selection.csv"))
  paths <- c("selection.csv", "complete_screen_scores.csv")
  app_write_csv(data.frame(relative_path = paths,
    sha256 = vapply(file.path(root, "screen", paths), app_sha256_file, character(1L))),
    file.path(root, "screen", "selection_manifest.csv"))
  writeLines("FROZEN_BEFORE_PROTECTED_CONFIRMATION", file.path(root, "screen", "SELECTION_FROZEN"))
  app_joint_prior_stage_prepare(root, "confirmation")
}

app_joint_prior_finalize <- function(root) {
  app_joint_prior_verify_freeze(root); app_joint_prior_verify_selection(root)
  tab <- app_joint_prior_collect(root, "confirmation")
  select <- app_read_csv(file.path(root, "screen", "selection.csv"))
  verdict <- lapply(seq_len(nrow(select)), function(i) {
    s <- select[i, ]; rows <- tab[tab$scenario_id == s$scenario_id & tab$likelihood == s$likelihood, ]
    baseline <- rows[rows$structure == "joint" & rows$arm_id == s$baseline_arm_id, ]
    candidate <- rows[rows$structure == "joint" & rows$arm_id == s$arm_id, ]
    independent <- rows[rows$structure == "independent", ]
    baseline <- baseline[order(baseline$replicate_id), ]; candidate <- candidate[order(candidate$replicate_id), ]
    delta <- candidate$posterior_score_mean - baseline$posterior_score_mean
    data.frame(scenario_id = s$scenario_id, likelihood = s$likelihood, arm_id = s$arm_id,
      baseline_mean = mean(baseline$posterior_score_mean), candidate_mean = mean(candidate$posterior_score_mean),
      independent_mean = mean(independent$posterior_score_mean), candidate_minus_baseline = mean(delta),
      replicate_improvement_count = sum(delta < 0), confirmation_replicates = length(delta),
      decision = if (s$arm_id == s$baseline_arm_id) "retain_baseline" else if (mean(delta) < 0 &&
        all(candidate$functional_status == "pass")) "numerical_improvement_integration_review" else "retain_baseline_review",
      claim = "descriptive_fresh_seed_evidence_no_article_fixture_supersession")
  })
  packet <- file.path(root, "closeout"); app_ensure_dir(packet)
  app_write_csv(tab, file.path(packet, "confirmation_scores.csv"))
  app_write_csv(do.call(rbind, verdict), file.path(packet, "decisions.csv"))
  contrasts <- list()
  for (i in seq_len(nrow(select))) for (replicate in sort(unique(tab$replicate_id))) {
    s <- select[i, ]
    rows <- tab[tab$scenario_id == s$scenario_id & tab$likelihood == s$likelihood & tab$replicate_id == replicate, ]
    candidate <- rows[rows$structure == "joint" & rows$arm_id == s$arm_id, ]
    for (reference in c("baseline", "independent")) {
      ref <- if (reference == "baseline") rows[rows$structure == "joint" & rows$arm_id == s$baseline_arm_id, ] else rows[rows$structure == "independent", ]
      stopifnot(nrow(candidate) == 1L, nrow(ref) == 1L)
      load <- function(id) app_read_csv(file.path(root, "confirmation", "scores", sprintf("cell_%04d", id), "score_draws.csv.gz"))$origin_marginal_dgp_integrated_acrps
      left <- load(candidate$cell_id); right <- load(ref$cell_id)
      set.seed(100000L + i * 100L + replicate * 10L + match(reference, c("baseline", "independent")))
      n <- min(length(left), length(right))
      delta <- if (candidate$cell_id == ref$cell_id) rep(0, n) else left[sample.int(length(left), n)] - right[sample.int(length(right), n)]
      contrasts[[length(contrasts) + 1L]] <- data.frame(scenario_id = s$scenario_id,
        likelihood = s$likelihood, replicate_id = replicate, reference = reference,
        mean_difference = mean(left) - mean(right), q025 = quantile(delta, .025, names = FALSE),
        q975 = quantile(delta, .975, names = FALSE),
        coupling = "independent_product_across_fitted_models_not_paired_parameter_posterior")
    }
  }
  app_write_csv(do.call(rbind, contrasts), file.path(packet, "posterior_score_contrasts.csv"))
  grDevices::pdf(file.path(packet, "prior_screen_comparison.pdf"), width = 11, height = 7)
  on.exit(grDevices::dev.off(), add = TRUE)
  screen <- app_read_csv(file.path(root, "screen", "complete_screen_scores.csv"))
  arms <- app_read_csv(file.path(root, "arms.csv"))
  for (scenario in unique(tab$scenario_id)) for (family in unique(tab$likelihood)) {
    x <- screen[screen$scenario_id == scenario & screen$likelihood == family &
      screen$structure == "joint" & !screen$long_budget, ]
    means <- vapply(arms$arm_id, function(id) mean(x$posterior_score_mean[x$arm_id == id]), numeric(1L))
    graphics::par(mar = c(5, 5, 4, 2))
    z <- matrix(means, nrow = 3L)
    graphics::image(1:3, 1:5, z, axes = FALSE, col = grDevices::hcl.colors(20, "YlOrRd", rev = TRUE),
      xlab = "Anchor multiplier", ylab = "Adjacent-difference multiplier",
      main = paste(scenario, family, "internal score response surface"))
    graphics::axis(1, at = 1:3, labels = c("1/3", "1", "3"))
    graphics::axis(2, at = 1:5, labels = c("0.1", "1/3", "1", "3", "10"))
    xy <- expand.grid(x = 1:3, y = 1:5)
    graphics::text(xy$x, xy$y, labels = format(round(means, 4), nsmall = 4), cex = .9)
    graphics::points(2, 3, pch = 0, cex = 3)
  }
  for (scenario in unique(tab$scenario_id)) for (family in unique(tab$likelihood)) {
    x <- tab[tab$scenario_id == scenario & tab$likelihood == family, ]
    label <- paste(x$structure, x$arm_id, "rep", x$replicate_id)
    graphics::par(mar = c(5, 13, 4, 2))
    graphics::plot(x$posterior_score_mean, seq_len(nrow(x)),
      xlim = range(x$posterior_score_q025, x$posterior_score_q975), yaxt = "n", ylab = "",
      xlab = "DGP-integrated finite-grid score (lower is better)",
      main = paste(scenario, family, "fresh-seed confirmation"), pch = 19,
      col = ifelse(x$structure == "joint", "#226A8F", "#A84254"))
    graphics::segments(x$posterior_score_q025, seq_len(nrow(x)), x$posterior_score_q975, seq_len(nrow(x)))
    graphics::axis(2, at = seq_len(nrow(x)), labels = label, las = 1, cex.axis = .75)
  }
  grDevices::dev.off(); on.exit(NULL)
  ct <- readRDS(file.path(root, "contract.rds"))
  git <- function(args) system2("git", args, stdout = TRUE)
  changed <- git(c("diff", "--name-only", paste0(ct$base_main, "..HEAD")))
  writeLines(c("# Frozen JOINT prior experiment", "",
    "No article or Overleaf replacement is authorized.",
    "All exAL chains use exact M0; scalar diagnostics do not require perfect mixing.",
    "A smaller mean is a descriptive gain. Score credible intervals are not MCSE or sampling-error confidence intervals.",
    "Runtime/posterior files remain excluded. Review decisions.csv before an article-fixture refit.",
    paste("Lane: JOINT; worktree:", getwd()), paste("Runtime/run tag:", root),
    "Transcript: user-provided JOINT conversation; no guessed transcript file path.",
    paste("Branch:", git(c("branch", "--show-current"))),
    paste("Upstream:", git(c("rev-parse", "--abbrev-ref", "@{upstream}"))),
    paste("HEAD:", git(c("rev-parse", "HEAD"))), paste("Base main:", ct$base_main),
    paste("Unique commits:", paste(git(c("rev-list", paste0(ct$base_main, "..HEAD"))), collapse = "; ")),
    paste("Git status:", paste(git(c("status", "--porcelain")), collapse = "; ")),
    paste("Ahead/behind:", git(c("rev-list", "--left-right", "--count", "HEAD...@{upstream}"))),
    "Changed files:", changed, "",
    "Run counts: screen 264/264 chains; confirmation see confirmation/chains.csv; zero failed exit receipts required.",
    "Tests and preflight: tracked implementation note; ignored startup verification log and capacity_preflight.csv.",
    "Evidence: freeze_manifest.csv, source_manifest.csv, both plan_manifest.csv files, selection_manifest.csv and nested worker artifact_manifest.csv files.",
    "Storage: compact initializers, compressed posterior draws and all score evidence retained; all runtime remains ignored.",
    "Article-safe files: none authorized for publication yet. Candidate scientific summary CSVs require separate article-fixture confirmation.",
    "Exclusions: application/cache/, local_trackers/, .codex_work/, all generated model objects/PDFs/logs.",
    "Risks: two confirmation replicates; relaxed functional-review threshold; prior selection is exploratory; broad score intervals can be genuine.",
    "Recommended merge order: scientific code/contract/tests first, reviewed article-fixture authority in a separate lane later.",
    "READY_FOR_INTEGRATION applies to scientific code only after coordinator independently verifies Git/tests/manifests; not article replacement."), file.path(packet, "HANDOFF.md"))
  app_joint_prior_seal(packet)
  writeLines("COMPLETE_READY_FOR_SCIENTIFIC_REVIEW", file.path(root, "COMPLETE"))
}
