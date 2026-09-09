# Fixed article-fixture confirmation workflow for the JOINT shared backbones.

app_joint_article_contract_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v1.csv")
}

app_joint_article_corrected_contract_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_article_confirmation_contract_v2.csv")
}

app_joint_article_host_profiles_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_article_confirmation_host_profiles_v1.csv")
}

app_joint_article_default_root <- function(
  contract = app_joint_article_read_contract()
) {
  app_path("application/cache", contract$run_tag)
}

app_joint_article_default_source_runtime <- function(
  contract = app_joint_article_read_contract()
) {
  file.path(contract$source_worktree, contract$source_runtime_relative_path)
}

app_joint_article_contract_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Article confirmation contract requires one '%s' row.", name),
         call. = FALSE)
  }
  as.character(row$value[[1L]])
}

app_joint_article_read_contract <- function(
  path = app_joint_article_contract_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "JOINT article confirmation contract")
  if (anyDuplicated(tab$name)) {
    stop("JOINT article confirmation contract names must be unique.",
         call. = FALSE)
  }
  get <- function(name) app_joint_article_contract_value(tab, name)
  has <- function(name) name %in% tab$name
  get_optional <- function(name, default) if (has(name)) get(name) else default
  bool <- function(name) identical(tolower(get(name)), "true")
  bool_optional <- function(name, default) {
    if (has(name)) identical(tolower(get(name)), "true") else isTRUE(default)
  }
  num <- function(name) as.numeric(get(name))
  num_optional <- function(name, default) if (has(name)) as.numeric(get(name)) else default
  int <- function(name) as.integer(get(name))
  nums <- function(name) as.numeric(strsplit(get(name), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    run_tag = get("run_tag"),
    execution_branch = get_optional(
      "execution_branch", "work/joint-qdesn-article-confirmation-jerez-20260907"),
    host_profile_id = get_optional("host_profile_id", "jerez_20260907"),
    source_worktree = get("source_worktree"),
    source_head = get("source_head"),
    source_runtime_relative_path = get("source_runtime_relative_path"),
    source_hashes = c(
      final_artifact_manifest.csv = get("final_artifact_manifest_sha256"),
      final_decision.csv = get("final_decision_sha256"),
      final_health.csv = get("final_health_sha256"),
      nested_manifest_verification.csv = get("nested_manifest_verification_sha256"),
      selected_family_backbones.csv = get("selected_family_backbones_sha256"),
      seven_family_vb_score_aggregate.csv = get("seven_family_vb_score_aggregate_sha256"),
      seven_family_joint_independent_contrasts.csv = get("seven_family_joint_independent_contrasts_sha256"),
      future_article_fixture_mcmc_plan.csv = get("future_article_fixture_mcmc_plan_sha256")
    ),
    expected_source_jobs = int("expected_source_jobs"),
    expected_source_failures = int("expected_source_failures"),
    expected_selected_backbones = int("expected_selected_backbones"),
    expected_vb_aggregate_rows = int("expected_vb_aggregate_rows"),
    expected_contrast_rows = int("expected_contrast_rows"),
    expected_future_cells = int("expected_future_cells"),
    article_fixture_refit_mode = bool("article_fixture_refit_mode"),
    scenario_specific_backbones = bool("scenario_specific_backbones"),
    global_specification_selected = bool("global_specification_selected"),
    article_fixture_used_for_selection = bool("article_fixture_used_for_selection"),
    desn_or_tau0_screen_allowed = bool("desn_or_tau0_screen_allowed"),
    tau = nums("quantile_grid"),
    center_out_order = nums("center_out_order"),
    expected_gaussian_refits = int("expected_gaussian_refits"),
    expected_independent_al_refits = int("expected_independent_al_refits"),
    expected_independent_exal_refits = int("expected_independent_exal_refits"),
    expected_joint_al_refits = int("expected_joint_al_refits"),
    expected_joint_exal_refits = int("expected_joint_exal_refits"),
    expected_total_components = int("expected_total_components"),
    expected_top_level_initializers = int("expected_top_level_initializers"),
    gaussian_rhs_max_iter = int("gaussian_rhs_max_iter"),
    gaussian_rhs_min_iter = int("gaussian_rhs_min_iter"),
    gaussian_rhs_tolerance = num("gaussian_rhs_tolerance"),
    al_max_iter = int("al_max_iter"),
    exal_max_iter = int("exal_max_iter"),
    vb_tolerance = num("vb_tolerance"),
    rhs_vb_inner = int("rhs_vb_inner"),
    rhs_freeze_iters = int("rhs_freeze_iters"),
    ridge_tau2 = num("ridge_tau2"),
    intercept_variance = num("intercept_variance"),
    sigma_shape = num("sigma_shape"),
    sigma_rate = num("sigma_rate"),
    a_sigma = num("a_sigma"),
    b_sigma = num("b_sigma"),
    alpha_prior_sd_multiplier = num("alpha_prior_sd_multiplier"),
    alpha_min_spacing = num("alpha_min_spacing"),
    rhs_slab_variance = num_optional("rhs_slab_variance", NA_real_),
    rhs_slab_fixed = bool_optional("rhs_slab_fixed", FALSE),
    coefficient_hierarchy = get_optional(
      "coefficient_hierarchy", "first_quantile_anchor_adjacent_differences"),
    ordered_intercepts = bool_optional("ordered_intercepts", TRUE),
    alpha_prior_center_policy = get_optional(
      "alpha_prior_center_policy", "gaussian_location_quantiles"),
    alpha_prior_sd_policy = get_optional(
      "alpha_prior_sd_policy", "gaussian_residual_scale_multiplier"),
    sigma_lower_bound = num_optional("sigma_lower_bound", 0),
    sigma_upper_bound = num_optional("sigma_upper_bound", Inf),
    posterior_target_hash_required = bool_optional(
      "posterior_target_hash_required", TRUE),
    projection_rule = get_optional(
      "projection_rule", "weighted_isotonic_equal_weights"),
    draw_coupling = get_optional(
      "draw_coupling", "matched_draw_index_with_repeated_permutation_sensitivity"),
    max_dense_dim = int("max_dense_dim"),
    exal_vb_method = get("exal_vb_method"),
    gamma_init_policy = get("gamma_init_policy"),
    exal_mcmc_method = get("exal_mcmc_method"),
    al_mcmc_method = get("al_mcmc_method"),
    al_chains_per_cell = int("al_chains_per_cell"),
    exal_chains_per_cell = int("exal_chains_per_cell"),
    al_n_iter = int("al_n_iter"), al_burn = int("al_burn"),
    al_thin = int("al_thin"), exal_n_iter = int("exal_n_iter"),
    exal_burn = int("exal_burn"), exal_thin = int("exal_thin"),
    total_chain_workers = int("total_chain_workers"),
    initial_concurrency = int("initial_concurrency"),
    maximum_concurrency = int("maximum_concurrency"),
    fixture_seed_source = get("fixture_seed_source"),
    chain_seed_base = int("chain_seed_base"),
    component_seed_stride = int("component_seed_stride"),
    vb_component_seed_base = as.integer(get_optional(
      "vb_component_seed_base", "202609800")),
    cell_seed_stride = int("cell_seed_stride"),
    chain_seed_stride = int("chain_seed_stride"),
    chain_start_jitter_seed_base = int("chain_start_jitter_seed_base"),
    blas_threads = int("blas_threads"),
    min_data_free_gib = num("min_data_free_gib"),
    production_launched = bool("production_launched"),
    retain_broad_model_dumps = bool("retain_broad_model_dumps"),
    dry_run_preflight_required = bool("dry_run_preflight_required"),
    primary_score = get("primary_score"),
    secondary_scores = strsplit(get("secondary_scores"), ";", fixed = TRUE)[[1L]],
    retain_oracle_recovery = bool("retain_oracle_recovery"),
    retain_crossing_diagnostics = bool("retain_crossing_diagnostics"),
    retain_functional_stability = bool("retain_functional_stability"),
    retain_gamma_sigma_diagnostics = bool("retain_gamma_sigma_diagnostics")
  )
  expected_tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  if (!identical(out$tau, expected_tau) ||
      !identical(out$center_out_order, c(0.50, 0.25, 0.75, 0.10, 0.90, 0.05, 0.95)) ||
      out$expected_gaussian_refits != 8L ||
      out$expected_independent_al_refits != 56L ||
      out$expected_independent_exal_refits != 56L ||
      out$expected_joint_al_refits != 8L ||
      out$expected_joint_exal_refits != 8L ||
      out$expected_total_components != 136L ||
      out$expected_top_level_initializers != 32L ||
      out$expected_future_cells != 32L ||
      out$total_chain_workers != 160L ||
      out$blas_threads != 1L ||
      out$global_specification_selected ||
      out$article_fixture_used_for_selection ||
      out$desn_or_tau0_screen_allowed ||
      out$production_launched ||
      out$retain_broad_model_dumps) {
    stop("JOINT article confirmation contract violates the frozen scope.",
         call. = FALSE)
  }
  if (!identical(out$exal_vb_method, "VB1_structured_v") ||
      !identical(out$exal_mcmc_method, "M0_v_collapsed_support_logit") ||
      !identical(out$primary_score, "dgp_integrated_finite_grid_acrps")) {
    stop("JOINT article confirmation inference or scoring method is not frozen.",
         call. = FALSE)
  }
  app_joint_qvp_validate_sigma_bounds(c(
    out$sigma_lower_bound, out$sigma_upper_bound))
  if (identical(out$version, "joint_shared_backbone_article_confirmation_v2")) {
    if (!is.finite(out$rhs_slab_variance) || out$rhs_slab_variance != 1 ||
        !out$rhs_slab_fixed ||
        !identical(out$coefficient_hierarchy,
          "first_quantile_anchor_adjacent_differences") ||
        !out$ordered_intercepts ||
        !identical(out$alpha_prior_center_policy,
          "gaussian_location_quantiles") ||
        !identical(out$alpha_prior_sd_policy,
          "gaussian_residual_scale_multiplier") ||
        out$sigma_lower_bound != 0 || !is.infinite(out$sigma_upper_bound) ||
        !out$posterior_target_hash_required ||
        !identical(out$execution_branch,
          "work/joint-qdesn-corrected-article-comparison-jerez-20260909") ||
        !identical(out$host_profile_id, "jerez_corrected_20260909") ||
        out$al_chains_per_cell != 5L || out$exal_chains_per_cell != 5L ||
        out$initial_concurrency != 50L || out$maximum_concurrency != 50L) {
      stop("Corrected JOINT article confirmation contract violates the common-posterior gate.",
        call. = FALSE)
    }
  }
  out
}

app_joint_article_resolve_posterior_target <- function(root, job, design,
    contract) {
  plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  gaussian_job <- app_joint_article_find_job(
    plan, job$scenario_id[[1L]], "gaussian_rhs_initializer")
  gaussian <- app_joint_article_load_vb_fit(root, gaussian_job)
  zeta2 <- if (isTRUE(contract$rhs_slab_fixed)) {
    value <- as.numeric(contract$rhs_slab_variance)
    if (length(value) != 1L || !is.finite(value) || value <= 0) {
      stop("A fixed RHS slab requires one positive finite contract variance.",
        call. = FALSE)
    }
    value[[1L]]
  } else {
    as.numeric(gaussian$initializer$zeta2)[[1L]]
  }
  alpha_mean <- as.numeric(gaussian$initializer$alpha_mean)
  alpha_sd <- as.numeric(gaussian$initializer$alpha_prior_sd)
  data_design_fingerprint <- design$posterior_data_design_fingerprint %||%
    app_joint_qvp_sha256_text(paste(
      "joint_qdesn_posterior_data_design_v1",
      paste(design$fit_local, collapse = ";"),
      paste(colnames(design$Z), collapse = ";"),
      paste(format(design$y[design$fit_local], digits = 17L,
        scientific = TRUE), collapse = ";"),
      paste(format(design$Z[design$fit_local, , drop = FALSE], digits = 17L,
        scientific = TRUE), collapse = ";"),
      sep = "|"
    ))
  target <- app_joint_posterior_contract(
    likelihood_family = job$likelihood_family[[1L]],
    fit_structure = job$fit_structure[[1L]],
    tau = design$tau,
    design_fingerprint = data_design_fingerprint,
    kappa = 1,
    tau0 = as.numeric(job$rhs_tau0[[1L]]),
    zeta2 = zeta2,
    slab_fixed = contract$rhs_slab_fixed,
    a_sigma = contract$a_sigma,
    b_sigma = contract$b_sigma,
    alpha_prior_mean = alpha_mean,
    alpha_prior_sd = alpha_sd,
    alpha_min_spacing = if (job$fit_structure[[1L]] == "joint") {
      contract$alpha_min_spacing
    } else 0,
    sigma_bounds = c(contract$sigma_lower_bound, contract$sigma_upper_bound),
    coefficient_hierarchy = if (job$fit_structure[[1L]] == "joint") {
      contract$coefficient_hierarchy
    } else {
      "independent_quantile_specific_rhs"
    },
    ordered_intercepts = job$fit_structure[[1L]] == "joint" &&
      contract$ordered_intercepts,
    gamma_prior_type = "none",
    score_definition = contract$primary_score,
    projection_rule = contract$projection_rule,
    draw_coupling = contract$draw_coupling
  )
  target
}

app_joint_article_read_host_profile <- function(
  profile_id = "jerez_20260907",
  path = app_joint_article_host_profiles_path()
) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c(
    "profile_id", "host", "required_rscript", "r_library_root",
    "runtime_root", "source_worktree", "initial_concurrency",
    "maximum_concurrency", "min_data_free_gib", "blas_threads",
    "production_launched"
  ), "JOINT article confirmation host profiles")
  row <- tab[tab$profile_id == profile_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Host profile is not unique.", call. = FALSE)
  row
}

app_joint_article_git_value <- function(args, root = app_repo_root()) {
  out <- tryCatch(system2("git", c("-C", root, args), stdout = TRUE, stderr = TRUE),
    error = function(e) NA_character_)
  if (!length(out)) "" else trimws(out[[1L]])
}

app_joint_article_assert_execution_branch <- function(
  contract = app_joint_article_read_contract()
) {
  branch <- app_joint_article_git_value(c("rev-parse", "--abbrev-ref", "HEAD"))
  if (!identical(branch, contract$execution_branch)) {
    stop(sprintf(
      "This workflow must run only from the dedicated JOINT branch '%s'.",
      contract$execution_branch),
         call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_article_execution_git_state <- function() {
  data.frame(
    branch = app_joint_article_git_value(c("rev-parse", "--abbrev-ref", "HEAD")),
    head = app_joint_article_git_value(c("rev-parse", "HEAD")),
    upstream = app_joint_article_git_value(c("rev-parse", "@{upstream}")),
    ahead_behind = app_joint_article_git_value(c("rev-list", "--left-right", "--count", "@{upstream}...HEAD")),
    tracked_status = app_joint_article_git_value(c("status", "--porcelain", "--untracked-files=no")),
    stringsAsFactors = FALSE
  )
}

app_joint_article_assert_clean_execution <- function(
  contract = app_joint_article_read_contract(), require_synced = TRUE
) {
  app_joint_article_assert_execution_branch(contract)
  state <- app_joint_article_execution_git_state()
  if (!identical(state$tracked_status[[1L]], "")) {
    stop("Production workers require a clean tracked execution worktree.",
         call. = FALSE)
  }
  if (isTRUE(require_synced) && !identical(state$ahead_behind[[1L]], "0\t0")) {
    stop("Production workers require the execution branch to be synchronized with upstream.",
         call. = FALSE)
  }
  invisible(state)
}

app_joint_article_data_free_gib <- function(path = "/data") {
  out <- system2("df", c("-Pk", path), stdout = TRUE)
  parts <- strsplit(trimws(out[[length(out)]]), "[[:space:]]+")[[1L]]
  as.numeric(parts[[4L]]) / 1024^2
}

app_joint_article_competing_processes <- function() {
  user <- Sys.info()[["user"]]
  lines <- tryCatch(system2(
    "ps", c("-u", user, "-o", "pid=,args="), stdout = TRUE, stderr = FALSE
  ), error = function(e) character())
  if (!length(lines)) return(character())
  pid <- suppressWarnings(as.integer(sub("^\\s*([0-9]+).*$", "\\1", lines)))
  patterns <- c(
    "pricefm", "glofas", "phase182",
    "joint_qdesn_shared_backbone_article_confirmation_jerez_20260907"
  )
  keep <- Reduce(`|`, lapply(patterns, grepl, lines, ignore.case = TRUE))
  trimws(lines[keep & !is.na(pid) & pid != Sys.getpid()])
}

app_joint_article_assert_capacity_authorized <- function(contract) {
  if (identical(contract$version,
      "joint_shared_backbone_article_confirmation_v2") &&
      !identical(Sys.getenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED"),
        "JEREZ_50_IDLE")) {
    stop(paste(
      "Corrected production requires",
      "JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED=JEREZ_50_IDLE",
      "after verifying that PriceFM and other scientific campaigns are inactive."
    ), call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_article_host_preflight <- function(
  contract = app_joint_article_read_contract(),
  profile = NULL
) {
  if (is.null(profile)) {
    profile <- app_joint_article_read_host_profile(contract$host_profile_id)
  }
  data_free <- app_joint_article_data_free_gib("/data")
  thread_vars <- c(
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"
  )
  thread_values <- Sys.getenv(thread_vars, unset = "1")
  lib_ok <- identical(.libPaths(), as.character(profile$r_library_root[[1L]]))
  required_rscript <- normalizePath(
    as.character(profile$required_rscript[[1L]]), mustWork = FALSE)
  active_rscript <- normalizePath(file.path(R.home("bin"), "Rscript"),
    mustWork = FALSE)
  required_install_root <- normalizePath(
    file.path(dirname(required_rscript), ".."), mustWork = FALSE)
  active_install_root <- normalizePath(
    file.path(R.home(), "..", ".."), mustWork = FALSE)
  rscript_ok <- file.exists(required_rscript) &&
    identical(active_install_root, required_install_root)
  expected_host <- as.character(profile$host[[1L]])
  host_ok <- Sys.info()[["nodename"]] %in% c(expected_host, sub("\\..*$", "", expected_host))
  logical_cores <- parallel::detectCores(logical = TRUE)
  competing <- app_joint_article_competing_processes()
  expected_runtime_root <- file.path("application", "cache", contract$run_tag)
  profile_ok <- as.integer(profile$initial_concurrency[[1L]]) ==
      contract$initial_concurrency &&
    as.integer(profile$maximum_concurrency[[1L]]) ==
      contract$maximum_concurrency &&
    as.numeric(profile$min_data_free_gib[[1L]]) == contract$min_data_free_gib &&
    as.integer(profile$blas_threads[[1L]]) == contract$blas_threads &&
    identical(as.character(profile$runtime_root[[1L]]), expected_runtime_root) &&
    identical(as.character(profile$source_worktree[[1L]]),
      contract$source_worktree) &&
    !app_as_bool_vec(profile$production_launched)[[1L]]
  out <- data.frame(
    host = Sys.info()[["nodename"]],
    expected_host = expected_host,
    host_ok = host_ok,
    profile_id = profile$profile_id[[1L]],
    profile_contract_ok = profile_ok,
    r_home = R.home(),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    active_rscript = active_rscript,
    required_rscript = required_rscript,
    active_install_root = active_install_root,
    required_install_root = required_install_root,
    rscript_ok = rscript_ok,
    lib_paths = paste(.libPaths(), collapse = ";"),
    expected_library_root = profile$r_library_root[[1L]],
    library_root_ok = lib_ok,
    data_free_gib = data_free,
    min_data_free_gib = contract$min_data_free_gib,
    data_free_ok = data_free >= contract$min_data_free_gib,
    logical_cores = logical_cores,
    required_logical_cores = contract$maximum_concurrency,
    logical_cores_ok = is.finite(logical_cores) &&
      logical_cores >= contract$maximum_concurrency,
    competing_process_count = length(competing),
    competing_processes = paste(competing, collapse = " || "),
    competing_processes_ok = !length(competing),
    thread_values = paste(paste(thread_vars, thread_values, sep = "="), collapse = ";"),
    one_thread_policy = all(thread_values == "1"),
    production_launched = FALSE,
    stringsAsFactors = FALSE
  )
  if (!out$host_ok[[1L]] || !out$profile_contract_ok[[1L]] ||
      !out$rscript_ok[[1L]] || !out$library_root_ok[[1L]] ||
      !out$data_free_ok[[1L]] || !out$logical_cores_ok[[1L]] ||
      !out$competing_processes_ok[[1L]] || !out$one_thread_policy[[1L]]) {
    stop("Host preflight failed host/profile, R executable/library, compute/storage capacity, competing-process, or one-thread policy.",
         call. = FALSE)
  }
  out
}

app_joint_article_source_files <- function(source_root) {
  c(
    final_artifact_manifest.csv = file.path(source_root, "final_artifact_manifest.csv"),
    final_decision.csv = file.path(source_root, "final_decision.csv"),
    final_health.csv = file.path(source_root, "final_health.csv"),
    nested_manifest_verification.csv = file.path(source_root, "nested_manifest_verification.csv"),
    selected_family_backbones.csv = file.path(source_root, "selected_family_backbones.csv"),
    seven_family_vb_score_aggregate.csv = file.path(source_root, "seven_family_vb_score_aggregate.csv"),
    seven_family_joint_independent_contrasts.csv = file.path(source_root, "seven_family_joint_independent_contrasts.csv"),
    future_article_fixture_mcmc_plan.csv = file.path(source_root, "future_article_fixture_mcmc_plan.csv")
  )
}

app_joint_article_verify_handoff_hashes <- function(contract) {
  handoff <- app_path("local_trackers/joint_qdesn_jerez_migration_handoff_20260907.md")
  if (!file.exists(handoff)) {
    return(data.frame(source = "handoff", path = handoff, verified = NA,
      note = "ignored handoff not present", stringsAsFactors = FALSE))
  }
  text <- paste(readLines(handoff, warn = FALSE), collapse = "\n")
  rows <- lapply(names(contract$source_hashes), function(name) {
    data.frame(
      source = "handoff", path = handoff, artifact = name,
      expected_sha256 = unname(contract$source_hashes[[name]]),
      artifact_present = grepl(name, text, fixed = TRUE),
      hash_present = grepl(unname(contract$source_hashes[[name]]), text, fixed = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out$verified <- out$artifact_present & out$hash_present
  if (any(!out$verified)) {
    stop("Pasted source hashes differ from the Muscat handoff.",
         call. = FALSE)
  }
  out
}

app_joint_article_verify_source <- function(
  source_root = app_joint_article_default_source_runtime(),
  contract = app_joint_article_read_contract()
) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  source_worktree <- normalizePath(contract$source_worktree, mustWork = TRUE)
  expected_runtime <- normalizePath(file.path(
    source_worktree, contract$source_runtime_relative_path), mustWork = TRUE)
  if (!identical(source_root, expected_runtime)) {
    stop("Source runtime is not under the frozen detached source worktree.",
         call. = FALSE)
  }
  head <- app_joint_article_git_value(c("rev-parse", "HEAD"), source_worktree)
  branch <- app_joint_article_git_value(c("rev-parse", "--abbrev-ref", "HEAD"), source_worktree)
  status <- app_joint_article_git_value(c("status", "--porcelain", "--untracked-files=no"), source_worktree)
  source_git <- data.frame(
    source_worktree = source_worktree, head = head, branch = branch,
    tracked_status_clean = identical(status, ""),
    detached = identical(branch, "HEAD"), stringsAsFactors = FALSE
  )
  if (!identical(head, contract$source_head) || !source_git$tracked_status_clean[[1L]] ||
      !source_git$detached[[1L]]) {
    stop("Frozen source worktree must be detached, clean, and at the required HEAD.",
         call. = FALSE)
  }
  files <- app_joint_article_source_files(source_root)
  if (any(!file.exists(files))) stop("Frozen source runtime is missing required files.",
    call. = FALSE)
  top <- data.frame(
    artifact = names(files), path = normalizePath(files, mustWork = TRUE),
    expected_sha256 = unname(contract$source_hashes[names(files)]),
    observed_sha256 = vapply(files, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  top$hash_verified <- top$expected_sha256 == top$observed_sha256
  if (any(!top$hash_verified)) stop("Frozen source top-level hash verification failed.",
    call. = FALSE)
  handoff <- app_joint_article_verify_handoff_hashes(contract)
  manifest <- app_joint_shared_verify_manifest(source_root, files[["final_artifact_manifest.csv"]])
  if (!nrow(manifest) || any(!manifest$verified)) {
    stop("Frozen source final artifact manifest failed verification.",
         call. = FALSE)
  }
  health <- app_read_csv(files[["final_health.csv"]])
  nested <- app_read_csv(files[["nested_manifest_verification.csv"]])
  selected <- app_read_csv(files[["selected_family_backbones.csv"]])
  aggregate <- app_read_csv(files[["seven_family_vb_score_aggregate.csv"]])
  contrasts <- app_read_csv(files[["seven_family_joint_independent_contrasts.csv"]])
  future <- app_read_csv(files[["future_article_fixture_mcmc_plan.csv"]])
  app_check_required_columns(health, c("expected", "completed", "failed", "status"),
    "frozen source final_health")
  app_check_required_columns(nested, c("scenario_id", "artifact_kind", "all_verified"),
    "frozen source nested manifest verification")
  app_check_required_columns(selected, c(
    "scenario_id", "candidate_id", "architecture_signature", "design_class",
    "rhs_tau0", "protected_rows_used_for_selection"
  ), "frozen selected family backbones")
  app_check_required_columns(aggregate, c(
    "scenario_id", "model_id", "window", "dgp_integrated_acrps_mean",
    "contract_crossing_pairs"
  ), "frozen source VB aggregate")
  app_check_required_columns(contrasts, c(
    "likelihood", "joint_minus_independent", "joint_improves"
  ), "frozen source contrasts")
  app_check_required_columns(future, c(
    "scenario_id", "candidate_id", "architecture_signature", "design_class",
    "rhs_tau0", "model_id", "fit_structure", "likelihood_family",
    "article_seed", "article_fixture_used_for_selection", "mcmc_status"
  ), "frozen future article fixture MCMC plan")
  if (sum(as.integer(health$completed)) != contract$expected_source_jobs ||
      sum(as.integer(health$failed)) != contract$expected_source_failures ||
      any(health$status != "complete") ||
      !all(app_as_bool_vec(nested$all_verified)) ||
      nrow(selected) != contract$expected_selected_backbones ||
      anyDuplicated(selected$scenario_id) ||
      length(unique(selected$architecture_signature)) != contract$expected_selected_backbones ||
      any(as.integer(selected$protected_rows_used_for_selection) != 0L) ||
      nrow(aggregate) != contract$expected_vb_aggregate_rows ||
      any(!is.finite(as.numeric(aggregate$dgp_integrated_acrps_mean))) ||
      any(as.integer(aggregate$contract_crossing_pairs) != 0L) ||
      nrow(contrasts) != contract$expected_contrast_rows ||
      any(!is.finite(as.numeric(contrasts$joint_minus_independent))) ||
      nrow(future) != contract$expected_future_cells ||
      anyDuplicated(paste(future$scenario_id, future$model_id)) ||
      length(unique(future$scenario_id)) != contract$expected_selected_backbones ||
      length(unique(future$model_id)) != 4L ||
      any(app_as_bool_vec(future$article_fixture_used_for_selection)) ||
      any(!grepl("NOT_LAUNCHED", future$mcmc_status, fixed = TRUE))) {
    stop("Frozen source completion counts or article-selection boundaries failed.",
         call. = FALSE)
  }
  list(
    source_root = source_root, source_git = source_git, top_hashes = top,
    handoff_hashes = handoff, manifest_verification = manifest,
    health = health, nested = nested, selected = selected,
    aggregate = aggregate, contrasts = contrasts, future = future
  )
}

app_joint_article_model_map <- function() {
  data.frame(
    model_id = c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
      "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc"),
    vb_model_id = c("joint_qdesn_rhs", "independent_qdesn_rhs",
      "joint_exqdesn_rhs", "independent_exqdesn_rhs"),
    display_label = c("Joint QDESN, AL, RHS", "Independent QDESN, AL, RHS",
      "Joint exQDESN, exAL, RHS", "Independent exQDESN, exAL, RHS"),
    stringsAsFactors = FALSE
  )
}

app_joint_article_cell_id <- function(scenario_id, model_id) {
  paste(scenario_id, sub("_mcmc$", "", model_id), sep = "__")
}

app_joint_article_build_designs <- function(out_dir, source, contract) {
  registry <- app_joint_qdesn_load_simulation_registry()
  selected <- source$selected
  future <- source$future
  scenario_order <- unique(future$scenario_id)
  selected <- selected[match(scenario_order, selected$scenario_id), , drop = FALSE]
  if (anyNA(selected$scenario_id)) stop("Selected backbones do not cover future scenarios.",
    call. = FALSE)
  selected$scenario_order <- seq_len(nrow(selected))
  selected$article_seed <- vapply(selected$scenario_id, function(id) {
    seeds <- unique(future$article_seed[future$scenario_id == id])
    if (length(seeds) != 1L) stop("Article seed is not unique by scenario.",
      call. = FALSE)
    as.integer(seeds[[1L]])
  }, integer(1L))
  app_ensure_dir(file.path(out_dir, "fixtures"))
  app_ensure_dir(file.path(out_dir, "designs"))
  fixture_rows <- design_rows <- list()
  for (ii in seq_len(nrow(selected))) {
    sc <- registry[registry$scenario_id == selected$scenario_id[[ii]], , drop = FALSE]
    if (nrow(sc) != 1L) stop("Article scenario is not unique in the DGP registry.",
      call. = FALSE)
    sc$seed <- selected$article_seed[[ii]]
    sc$seed_role <- "joint_article_fixture_confirmation_seed"
    fixture <- app_joint_qdesn_fixture_from_registry_row(sc)
    fixture$registry_row <- sc
    design <- app_joint_shared_quantile_full_design(
      fixture, selected[ii, , drop = FALSE], contract)
    fixture_path <- file.path(out_dir, "fixtures",
      sprintf("%02d_%s.rds", ii, selected$scenario_id[[ii]]))
    design_path <- file.path(out_dir, "designs",
      sprintf("%02d_%s.rds", ii, selected$scenario_id[[ii]]))
    saveRDS(fixture, fixture_path, version = 3L, compress = "xz")
    saveRDS(design, design_path, version = 3L, compress = "xz")
    fixture_rows[[ii]] <- data.frame(
      scenario_order = ii, scenario_id = selected$scenario_id[[ii]],
      article_seed = selected$article_seed[[ii]],
      seed_role = fixture$seed_role,
      fixture_path = normalizePath(fixture_path, mustWork = TRUE),
      size_bytes = as.numeric(file.info(fixture_path)$size),
      sha256 = app_sha256_file(fixture_path),
      article_fixture_used_for_selection = FALSE,
      stringsAsFactors = FALSE
    )
    design_rows[[ii]] <- data.frame(
      scenario_order = ii, scenario_id = selected$scenario_id[[ii]],
      selected_candidate_id = selected$candidate_id[[ii]],
      selected_architecture_signature = selected$architecture_signature[[ii]],
      selected_design_class = selected$design_class[[ii]],
      selected_rhs_tau0 = as.numeric(selected$rhs_tau0[[ii]]),
      design_path = normalizePath(design_path, mustWork = TRUE),
      design_fingerprint = design$design_fingerprint,
      p = ncol(design$Z), fit_rows = length(design$fit_local),
      validation_rows = length(design$validation_local),
      scored_forecast_rows = length(design$score_local),
      size_bytes = as.numeric(file.info(design_path)$size),
      sha256 = app_sha256_file(design_path),
      article_fixture_used_for_selection = FALSE,
      stringsAsFactors = FALSE
    )
  }
  list(
    selected = selected,
    fixture_manifest = app_joint_qdesn_bind_rows(fixture_rows),
    design_manifest = app_joint_qdesn_bind_rows(design_rows)
  )
}

app_joint_article_vb_worker_dir <- function(root, job_id) {
  file.path(root, "workers", sprintf("worker_%04d", as.integer(job_id)))
}

app_joint_article_mcmc_worker_dir <- function(root, worker_id) {
  file.path(root, "mcmc_workers", sprintf("worker_%04d", as.integer(worker_id)))
}

app_joint_article_find_job <- function(plan, scenario_id, model_id, tau = NA_real_) {
  keep <- plan$scenario_id == scenario_id & plan$model_id == model_id
  if (is.finite(tau)) keep <- keep & is.finite(plan$tau) & abs(plan$tau - tau) < 1e-12
  row <- plan[keep, , drop = FALSE]
  if (nrow(row) != 1L) stop("Could not resolve a unique article VB dependency.",
    call. = FALSE)
  row
}

app_joint_article_dependency_rows <- function(plan, job) {
  scenario <- job$scenario_id[[1L]]
  model <- job$model_id[[1L]]
  if (model == "gaussian_rhs_initializer") return(plan[FALSE, , drop = FALSE])
  if (model == "independent_qdesn_rhs") {
    if (is.finite(job$parent_tau[[1L]])) {
      return(app_joint_article_find_job(plan, scenario, model, job$parent_tau[[1L]]))
    }
    return(app_joint_article_find_job(plan, scenario, "gaussian_rhs_initializer"))
  }
  if (model == "independent_exqdesn_rhs") {
    return(app_joint_article_find_job(plan, scenario, "independent_qdesn_rhs",
      job$tau[[1L]]))
  }
  if (model == "joint_qdesn_rhs") {
    return(plan[plan$scenario_id == scenario &
      plan$model_id == "independent_qdesn_rhs", , drop = FALSE])
  }
  if (model == "joint_exqdesn_rhs") {
    return(plan[plan$scenario_id == scenario &
      plan$model_id %in% c("independent_exqdesn_rhs", "joint_qdesn_rhs"),
      , drop = FALSE])
  }
  stop("Unknown article VB dependency model.", call. = FALSE)
}

app_joint_article_build_vb_plan <- function(selected, design_manifest, contract) {
  rows <- list()
  add <- function(scenario_row, stage_order, stage_id, model_id,
                  tau = NA_real_, parent_tau = NA_real_) {
    design <- design_manifest[design_manifest$scenario_id == scenario_row$scenario_id[[1L]], ,
      drop = FALSE]
    rows[[length(rows) + 1L]] <<- data.frame(
      job_id = length(rows) + 1L,
      scenario_order = scenario_row$scenario_order[[1L]],
      scenario_id = scenario_row$scenario_id[[1L]],
      replicate_id = scenario_row$scenario_order[[1L]],
      stage_order = as.integer(stage_order), stage_id = stage_id,
      model_id = model_id, tau = as.numeric(tau),
      parent_tau = as.numeric(parent_tau),
      article_seed = scenario_row$article_seed[[1L]],
      selected_candidate_id = scenario_row$candidate_id[[1L]],
      selected_architecture_signature = scenario_row$architecture_signature[[1L]],
      selected_design_class = scenario_row$design_class[[1L]],
      selected_rhs_tau0 = as.numeric(scenario_row$rhs_tau0[[1L]]),
      design_path = design$design_path[[1L]],
      design_fingerprint = design$design_fingerprint[[1L]],
      launch_status = "NOT_LAUNCHED",
      stringsAsFactors = FALSE
    )
  }
  for (ii in seq_len(nrow(selected))) {
    scenario <- selected[ii, , drop = FALSE]
    add(scenario, 1L, "gaussian_rhs_refit", "gaussian_rhs_initializer")
    order <- app_joint_shared_quantile_continuation_order(contract$tau)
    order <- order[match(contract$center_out_order, order$tau), , drop = FALSE]
    for (kk in seq_len(nrow(order))) {
      add(scenario, 1L + order$continuation_stage[[kk]],
        sprintf("independent_al_stage_%02d", order$continuation_stage[[kk]]),
        "independent_qdesn_rhs", order$tau[[kk]], order$parent_tau[[kk]])
    }
    for (tau in contract$tau) {
      add(scenario, 6L, "independent_structured_exal", "independent_exqdesn_rhs",
        tau, tau)
    }
    add(scenario, 7L, "joint_al", "joint_qdesn_rhs")
    add(scenario, 8L, "joint_structured_exal", "joint_exqdesn_rhs")
  }
  plan <- app_joint_qdesn_bind_rows(rows)
  plan <- plan[order(plan$stage_order, plan$scenario_order, plan$job_id), , drop = FALSE]
  plan$job_id <- seq_len(nrow(plan))
  plan$dependency_job_ids <- vapply(seq_len(nrow(plan)), function(ii) {
    paste(app_joint_article_dependency_rows(plan, plan[ii, , drop = FALSE])$job_id,
      collapse = ";")
  }, character(1L))
  plan$component_seed <- as.integer(contract$vb_component_seed_base + plan$job_id)
  counts <- table(plan$model_id)
  if (nrow(plan) != contract$expected_total_components ||
      unname(counts[["gaussian_rhs_initializer"]]) != contract$expected_gaussian_refits ||
      unname(counts[["independent_qdesn_rhs"]]) != contract$expected_independent_al_refits ||
      unname(counts[["independent_exqdesn_rhs"]]) != contract$expected_independent_exal_refits ||
      unname(counts[["joint_qdesn_rhs"]]) != contract$expected_joint_al_refits ||
      unname(counts[["joint_exqdesn_rhs"]]) != contract$expected_joint_exal_refits ||
      anyDuplicated(plan$component_seed)) {
    stop("Article VB plan violates the 136-component contract.", call. = FALSE)
  }
  for (ii in seq_len(nrow(plan))) {
    deps <- app_joint_article_dependency_rows(plan, plan[ii, , drop = FALSE])
    if (nrow(deps) && any(deps$stage_order >= plan$stage_order[[ii]])) {
      stop("Article VB dependency graph is not strictly stage ordered.",
           call. = FALSE)
    }
  }
  plan
}

app_joint_article_build_model_cells <- function(future, design_manifest, contract) {
  map <- app_joint_article_model_map()
  cells <- merge(future, map, by = "model_id", all.x = TRUE, sort = FALSE)
  if (anyNA(cells$vb_model_id)) stop("Future source plan contains an unknown model.",
    call. = FALSE)
  cells$cell_index <- seq_len(nrow(cells))
  cells$model_cell_id <- app_joint_article_cell_id(cells$scenario_id, cells$model_id)
  dm <- design_manifest[, c("scenario_order", "scenario_id", "design_path",
    "design_fingerprint", "p", "fit_rows", "validation_rows", "scored_forecast_rows"),
    drop = FALSE]
  cells <- merge(cells, dm, by = "scenario_id", all.x = TRUE, sort = FALSE)
  cells <- cells[order(cells$scenario_order, match(cells$model_id, map$model_id)), ,
    drop = FALSE]
  cells$cell_index <- seq_len(nrow(cells))
  cells$model_cell_id <- app_joint_article_cell_id(cells$scenario_id, cells$model_id)
  cells$initializer_relative_path <- file.path("initializers",
    paste0(cells$model_cell_id, ".rds"))
  cells$initializer_status <- "PENDING_VB_GATE"
  if (nrow(cells) != contract$expected_top_level_initializers ||
      anyDuplicated(cells$model_cell_id) ||
      any(app_as_bool_vec(cells$article_fixture_used_for_selection))) {
    stop("Article model-cell plan violates the 32-cell contract.", call. = FALSE)
  }
  by_scenario <- split(cells, cells$scenario_id)
  same_design <- vapply(by_scenario, function(x) length(unique(x$design_fingerprint)) == 1L,
    logical(1L))
  if (!all(same_design)) {
    stop("Article designs must be shared across all four models within a scenario.",
         call. = FALSE)
  }
  cells
}

app_joint_article_build_mcmc_plan <- function(cells, contract) {
  rows <- list()
  worker_id <- 0L
  for (ii in seq_len(nrow(cells))) {
    cell <- cells[ii, , drop = FALSE]
    n_chains <- if (cell$likelihood_family[[1L]] == "exAL") {
      contract$exal_chains_per_cell
    } else contract$al_chains_per_cell
    for (chain_id in seq_len(n_chains)) {
      worker_id <- worker_id + 1L
      row <- cell
      row$worker_id <- worker_id
      row$chain_id <- chain_id
      row$wave_id <- as.integer(ceiling(worker_id / contract$initial_concurrency))
      row$chain_seed <- as.integer(
        contract$chain_seed_base +
          row$cell_index[[1L]] * contract$cell_seed_stride +
          chain_id * contract$chain_seed_stride
      )
      row$chain_start_seed <- as.integer(
        contract$chain_start_jitter_seed_base +
          row$cell_index[[1L]] * contract$cell_seed_stride +
          chain_id * contract$chain_seed_stride
      )
      row$tau_seed_stride <- contract$component_seed_stride
      row$n_chains <- n_chains
      row$n_iter <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_n_iter
      } else contract$al_n_iter
      row$burn <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_burn
      } else contract$al_burn
      row$thin <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_thin
      } else contract$al_thin
      row$n_keep <- as.integer((row$n_iter - row$burn) / row$thin)
      row$inference_method_id <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_mcmc_method
      } else contract$al_mcmc_method
      row$launch_status <- "BLOCKED_UNTIL_VB_136_OF_136"
      rows[[worker_id]] <- row
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (nrow(out) != contract$total_chain_workers ||
      anyDuplicated(out$worker_id) || anyDuplicated(out$chain_seed) ||
      anyDuplicated(out$chain_start_seed) ||
      anyDuplicated(paste(out$model_cell_id, out$chain_id)) ||
      any(out$chain_seed >= .Machine$integer.max) ||
      any(out$chain_start_seed >= .Machine$integer.max)) {
    stop("Article MCMC plan violates worker or seed uniqueness.",
         call. = FALSE)
  }
  out
}

app_joint_article_component_seed_plan <- function(mcmc_plan, tau) {
  rows <- lapply(seq_len(nrow(mcmc_plan)), function(ii) {
    job <- mcmc_plan[ii, , drop = FALSE]
    if (job$fit_structure[[1L]] == "joint") {
      return(data.frame(
        worker_id = job$worker_id[[1L]], model_cell_id = job$model_cell_id[[1L]],
        chain_id = job$chain_id[[1L]], quantile_index = NA_integer_,
        tau = NA_real_, component_seed = job$chain_seed[[1L]],
        seed_role = "joint_multiquantile_component", stringsAsFactors = FALSE
      ))
    }
    data.frame(
      worker_id = job$worker_id[[1L]], model_cell_id = job$model_cell_id[[1L]],
      chain_id = job$chain_id[[1L]], quantile_index = seq_along(tau),
      tau = tau, component_seed = as.integer(
        job$chain_seed[[1L]] + seq_along(tau) * job$tau_seed_stride[[1L]]
      ),
      seed_role = "independent_quantile_component", stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$component_seed) ||
      any(out$component_seed >= .Machine$integer.max)) {
    stop("Article MCMC component seeds collide or overflow.", call. = FALSE)
  }
  out
}

app_joint_article_atomic_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  app_write_csv(x, tmp)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) stop("Could not atomically publish CSV.",
    call. = FALSE)
  invisible(path)
}

app_joint_article_prepare <- function(
  out_dir = app_joint_article_default_root(),
  source_root = app_joint_article_default_source_runtime(),
  contract_path = app_joint_article_contract_path(),
  force = FALSE,
  dry_run = TRUE
) {
  contract <- app_joint_article_read_contract(contract_path)
  app_joint_article_assert_execution_branch(contract)
  if (!isTRUE(dry_run) && contract$dry_run_preflight_required) {
    stop("Production preparation requires a separate explicit launch instruction.",
         call. = FALSE)
  }
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (identical(contract$version,
      "joint_shared_backbone_article_confirmation_v2")) {
    expected_out_dir <- normalizePath(
      app_path("application/cache", contract$run_tag), mustWork = FALSE)
    if (!identical(out_dir, expected_out_dir)) {
      stop("Corrected JOINT preparation requires the contract-owned isolated runtime root.",
        call. = FALSE)
    }
  }
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    if (!isTRUE(force)) {
      existing <- tryCatch(app_joint_shared_verify_manifest(out_dir),
        error = function(e) NULL)
      if (!is.null(existing) && all(existing$verified)) {
        return(list(
          out_dir = normalizePath(out_dir, mustWork = TRUE),
          readiness = app_read_csv(file.path(out_dir, "launch_free_preflight.csv")),
          reused = TRUE
        ))
      }
      stop("Refusing to overwrite a nonempty article confirmation runtime without --force.",
           call. = FALSE)
    }
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) {
      stop("Could not quarantine previous article confirmation runtime.",
           call. = FALSE)
    }
  }
  app_ensure_dir(out_dir); app_ensure_dir(file.path(out_dir, "workers"))
  app_ensure_dir(file.path(out_dir, "mcmc_workers")); app_ensure_dir(file.path(out_dir, "initializers"))
  source <- app_joint_article_verify_source(source_root, contract)
  host <- app_joint_article_host_preflight(contract)
  designs <- app_joint_article_build_designs(out_dir, source, contract)
  vb_plan <- app_joint_article_build_vb_plan(designs$selected, designs$design_manifest,
    contract)
  cells <- app_joint_article_build_model_cells(source$future, designs$design_manifest,
    contract)
  mcmc_plan <- app_joint_article_build_mcmc_plan(cells, contract)
  component_seeds <- app_joint_article_component_seed_plan(mcmc_plan, contract$tau)
  seed_audit <- data.frame(
    seed_namespace = c("article_fixture", "vb_component", "mcmc_chain",
      "mcmc_component", "chain_start_jitter"),
    seed_count = c(
      length(unique(designs$selected$article_seed)),
      length(unique(vb_plan$component_seed)),
      length(unique(mcmc_plan$chain_seed)),
      length(unique(component_seeds$component_seed)),
      length(unique(mcmc_plan$chain_start_seed))
    ),
    duplicate_count = c(
      anyDuplicated(designs$selected$article_seed),
      anyDuplicated(vb_plan$component_seed),
      anyDuplicated(mcmc_plan$chain_seed),
      anyDuplicated(component_seeds$component_seed),
      anyDuplicated(mcmc_plan$chain_start_seed)
    ),
    stringsAsFactors = FALSE
  )
  if (any(seed_audit$duplicate_count != 0L)) {
    stop("Article confirmation seed audit failed.", call. = FALSE)
  }
  scoring_contract <- data.frame(
    primary_score = contract$primary_score,
    posterior_score_center = "mean;median",
    posterior_interval = "equal_tailed_95_percent",
    secondary_scores = paste(contract$secondary_scores, collapse = ";"),
    oracle_recovery = "fit_and_forecast_mae_rmse",
    crossing_diagnostics = "raw_before_contract;contract_after_monotone",
    functional_stability = "chain_replicate_posterior_functionals",
    gamma_sigma_diagnostics = "retained_for_exal",
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    status = "LAUNCH_FREE_PREFLIGHT_READY",
    expected_vb_components = nrow(vb_plan),
    expected_top_level_initializers = nrow(cells),
    expected_mcmc_workers = nrow(mcmc_plan),
    source_jobs_completed = sum(as.integer(source$health$completed)),
    source_failures = sum(as.integer(source$health$failed)),
    selected_backbones = nrow(source$selected),
    future_cells = nrow(source$future),
    source_hashes_verified = all(source$top_hashes$hash_verified),
    nested_manifests_verified = all(source$nested$all_verified),
    article_fixture_used_for_selection = FALSE,
    desn_or_tau0_screen_launched = FALSE,
    vb_production_launched = FALSE,
    mcmc_production_launched = FALSE,
    production_launched = FALSE,
    dry_run_preflight = TRUE,
    stringsAsFactors = FALSE
  )
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(out_dir, "frozen_contract.csv")),
    execution_git_state = app_write_csv(app_joint_article_execution_git_state(), file.path(out_dir, "execution_git_state.csv")),
    host_preflight = app_write_csv(host, file.path(out_dir, "host_preflight.csv")),
    source_git_state = app_write_csv(source$source_git, file.path(out_dir, "source_git_state.csv")),
    source_top_hash_verification = app_write_csv(source$top_hashes, file.path(out_dir, "source_top_hash_verification.csv")),
    source_manifest_verification = app_write_csv(source$manifest_verification, file.path(out_dir, "source_manifest_verification.csv")),
    source_nested_manifest_verification = app_write_csv(source$nested, file.path(out_dir, "source_nested_manifest_verification.csv")),
    source_health = app_write_csv(source$health, file.path(out_dir, "source_final_health.csv")),
    imported_selected_backbones = app_write_csv(designs$selected, file.path(out_dir, "imported_selected_backbones.csv")),
    source_vb_score_aggregate = app_write_csv(source$aggregate, file.path(out_dir, "source_vb_score_aggregate.csv")),
    source_joint_independent_contrasts = app_write_csv(source$contrasts, file.path(out_dir, "source_joint_independent_contrasts.csv")),
    source_future_mcmc_plan = app_write_csv(source$future, file.path(out_dir, "source_future_article_fixture_mcmc_plan.csv")),
    fixture_manifest = app_write_csv(designs$fixture_manifest, file.path(out_dir, "fixture_manifest.csv")),
    design_manifest = app_write_csv(designs$design_manifest, file.path(out_dir, "design_manifest.csv")),
    vb_worker_plan = app_write_csv(vb_plan, file.path(out_dir, "vb_worker_plan.csv")),
    model_cell_plan = app_write_csv(cells, file.path(out_dir, "model_cell_plan.csv")),
    mcmc_worker_plan = app_write_csv(mcmc_plan, file.path(out_dir, "mcmc_worker_plan.csv")),
    component_seed_plan = app_write_csv(component_seeds, file.path(out_dir, "component_seed_plan.csv")),
    seed_audit = app_write_csv(seed_audit, file.path(out_dir, "seed_audit.csv")),
    scoring_contract = app_write_csv(scoring_contract, file.path(out_dir, "scoring_contract.csv")),
    launch_free_preflight = app_write_csv(readiness, file.path(out_dir, "launch_free_preflight.csv"))
  )
  writeLines(c(
    "# JOINT article-fixture confirmation preflight", "",
    "This runtime packet verifies the frozen shared-backbone evidence and prepares the article-window VB/MCMC graph.",
    "It has not launched production VB or MCMC.",
    "MCMC workers are blocked until all 136 VB components and all 32 compact initializers verify."
  ), file.path(out_dir, "README.md"), useBytes = TRUE)
  files <- c(files, README = file.path(out_dir, "README.md"))
  app_joint_shared_write_manifest(out_dir, files)
  verification <- app_joint_shared_verify_manifest(out_dir)
  if (any(!verification$verified)) {
    stop("Article confirmation preflight manifest failed verification.",
         call. = FALSE)
  }
  list(out_dir = out_dir, readiness = readiness, vb_plan = vb_plan,
    cells = cells, mcmc_plan = mcmc_plan)
}

app_joint_article_vb_health <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  dirs <- vapply(plan$job_id, function(id) app_joint_article_vb_worker_dir(root, id),
    character(1L))
  done <- file.exists(file.path(dirs, "DONE")) &
    file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) |
    file.exists(file.path(dirs, "failure.csv"))
  data.frame(
    expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), completion_fraction = mean(done),
    status = if (all(done)) "complete" else if (any(failed)) "failed" else "pending_or_running",
    stringsAsFactors = FALSE
  )
}

app_joint_article_vb_health_by_stage <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  rows <- lapply(split(plan, plan$stage_id), function(x) {
    dirs <- vapply(x$job_id, function(id) app_joint_article_vb_worker_dir(root, id),
      character(1L))
    done <- file.exists(file.path(dirs, "DONE")) &
      file.exists(file.path(dirs, "artifact_manifest.csv"))
    failed <- file.exists(file.path(dirs, "FAILED")) |
      file.exists(file.path(dirs, "failure.csv"))
    data.frame(
      stage_order = x$stage_order[[1L]], stage_id = x$stage_id[[1L]],
      expected = nrow(x), completed = sum(done), failed = sum(failed),
      remaining = sum(!done & !failed), stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$stage_order, out$stage_id), , drop = FALSE]
}

app_joint_article_check_vb <- function(root, require_complete = FALSE) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  health <- app_joint_article_vb_health(root)
  by_stage <- app_joint_article_vb_health_by_stage(root)
  cells <- app_read_csv(file.path(root, "model_cell_plan.csv"))
  ready <- health$completed[[1L]] == contract$expected_total_components &&
    health$failed[[1L]] == 0L
  init_done <- file.exists(file.path(root, "vb_initializer_manifest.csv")) &&
    sum(file.exists(file.path(root, cells$initializer_relative_path))) ==
      contract$expected_top_level_initializers
  summary <- data.frame(
    gate = if (isTRUE(require_complete)) "vb_complete_required" else "launch_free_preflight",
    expected_vb_components = health$expected[[1L]],
    completed_vb_components = health$completed[[1L]],
    failed_vb_components = health$failed[[1L]],
    remaining_vb_components = health$remaining[[1L]],
    expected_top_level_initializers = contract$expected_top_level_initializers,
    completed_top_level_initializers = sum(file.exists(file.path(root, cells$initializer_relative_path))),
    mcmc_launch_blocked = !ready || !init_done,
    production_launched = FALSE,
    gate_status = if (isTRUE(require_complete) && (!ready || !init_done)) "fail" else "pass",
    stringsAsFactors = FALSE
  )
  app_joint_article_atomic_write_csv(summary, file.path(root, "vb_health_summary.csv"))
  app_joint_article_atomic_write_csv(by_stage, file.path(root, "vb_health_by_stage.csv"))
  list(summary = summary, by_stage = by_stage, health = health)
}

app_joint_article_run_vb_worker <- function(root, job_id) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  job <- plan[plan$job_id == as.integer(job_id), , drop = FALSE]
  if (nrow(job) != 1L) stop("Article VB job_id is not unique.", call. = FALSE)
  out <- app_joint_article_vb_worker_dir(root, job_id)
  if (file.exists(file.path(out, "DONE")) &&
      file.exists(file.path(out, "artifact_manifest.csv"))) {
    return(invisible(out))
  }
  deps <- app_joint_article_dependency_rows(plan, job)
  if (nrow(deps)) {
    ready <- vapply(deps$job_id, function(id) file.exists(file.path(
      app_joint_article_vb_worker_dir(root, id), "DONE")), logical(1L))
    if (!all(ready)) stop("Article VB dependency is not complete.", call. = FALSE)
  }
  selected <- app_read_csv(file.path(root, "imported_selected_backbones.csv"))
  selected <- selected[selected$scenario_id == job$scenario_id[[1L]], , drop = FALSE]
  if (nrow(selected) != 1L) stop("Worker could not resolve selected scenario backbone.",
    call. = FALSE)
  design <- readRDS(job$design_path[[1L]])
  if (!identical(design$design_fingerprint, job$design_fingerprint[[1L]])) {
    stop("Article worker design fingerprint differs from the frozen plan.",
         call. = FALSE)
  }
  tmp <- paste0(out, ".tmp.", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  started <- Sys.time()
  result <- tryCatch({
    set.seed(as.integer(job$component_seed[[1L]]))
    if (job$model_id[[1L]] == "gaussian_rhs_initializer") {
      app_joint_shared_quantile_gaussian_worker(job, design, selected, contract)
    } else if (job$model_id[[1L]] == "independent_qdesn_rhs") {
      app_joint_shared_quantile_independent_al_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "independent_exqdesn_rhs") {
      app_joint_shared_quantile_independent_exal_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "joint_qdesn_rhs") {
      app_joint_shared_quantile_joint_al_worker(root, job, plan, design, contract)
    } else if (job$model_id[[1L]] == "joint_exqdesn_rhs") {
      app_joint_shared_quantile_joint_exal_worker(root, job, plan, design, contract)
    } else stop("Unknown article VB model_id.", call. = FALSE)
  }, error = function(e) e)
  if (inherits(result, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(job, data.frame(
      status = "failed", error_message = conditionMessage(result),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    unlink(tmp, recursive = TRUE, force = TRUE)
    stop(conditionMessage(result), call. = FALSE)
  }
  fit <- result$fit
  compact <- if (job$model_id[[1L]] == "gaussian_rhs_initializer") {
    fit
  } else app_joint_shared_quantile_compact_fit(fit)
  prediction <- if (job$model_id[[1L]] == "gaussian_rhs_initializer") {
    result$prediction
  } else {
    list(
      tau = fit$tau,
      qhat_fit = app_joint_qdesn_predict_fit(
        fit, design$Z[design$fit_local, , drop = FALSE], fit$tau),
      qhat_validation = app_joint_qdesn_predict_fit(
        fit, design$Z[design$validation_local, , drop = FALSE], fit$tau)
    )
  }
  finite <- all(is.finite(c(
    compact$beta_mean, compact$alpha_mean, compact$sigma_mean,
    compact$gamma_mean %||% numeric(), prediction$qhat_fit,
    prediction$qhat_validation
  ))) && all(compact$sigma_mean > 0)
  if (!finite) stop("Article VB worker produced nonfinite output.", call. = FALSE)
  fit_path <- file.path(tmp, "fit_initializer.rds")
  prediction_path <- file.path(tmp, "prediction.rds")
  saveRDS(compact, fit_path, version = 3L, compress = "xz")
  saveRDS(prediction, prediction_path, version = 3L, compress = "xz")
  trace_path <- app_write_csv(
    if (!is.null(result$trace)) result$trace else app_joint_shared_quantile_trace_frame(fit),
    file.path(tmp, "vb_trace.csv"))
  scale_path <- app_write_csv(app_joint_shared_quantile_scale_trace_frame(fit),
    file.path(tmp, "scale_shape_trace.csv"))
  summary <- cbind(job[, c("job_id", "scenario_id", "stage_order", "stage_id",
    "model_id", "tau", "parent_tau", "component_seed")], data.frame(
      status = "completed", finite_output = finite,
      inference_method_id = compact$inference_method_id %||%
        if (job$model_id[[1L]] == "gaussian_rhs_initializer") "gaussian_rhs_vb" else NA_character_,
      fit_structure = compact$fit_structure %||% NA_character_,
      iterations = as.integer(compact$iterations_completed %||%
        fit$iterations %||% nrow(app_joint_shared_quantile_trace_frame(fit))),
      converged = isTRUE(compact$converged %||% fit$converged),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      design_fingerprint = design$design_fingerprint,
      execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
      production_launched = TRUE,
      stringsAsFactors = FALSE
    ))
  summary_path <- app_write_csv(summary, file.path(tmp, "summary.csv"))
  manifest <- data.frame(
    label = c("summary", "fit_initializer", "prediction", "vb_trace",
      "scale_shape_trace"),
    relative_path = c("summary.csv", "fit_initializer.rds", "prediction.rds",
      "vb_trace.csv", "scale_shape_trace.csv"),
    size_bytes = as.numeric(file.info(c(summary_path, fit_path, prediction_path,
      trace_path, scale_path))$size),
    sha256 = vapply(c(summary_path, fit_path, prediction_path, trace_path,
      scale_path), app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_write_csv(manifest, file.path(tmp, "artifact_manifest.csv"))
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) {
    quarantine <- paste0(out, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out, quarantine)) stop("Could not quarantine stale VB worker.",
      call. = FALSE)
  }
  if (!file.rename(tmp, out)) stop("Could not publish article VB worker output.",
    call. = FALSE)
  invisible(out)
}

app_joint_article_vb_worker_state <- function(root, plan = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  if (is.null(plan)) plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  dirs <- vapply(plan$job_id, function(id) app_joint_article_vb_worker_dir(root, id),
    character(1L))
  data.frame(
    job_id = plan$job_id,
    done = file.exists(file.path(dirs, "DONE")) &
      file.exists(file.path(dirs, "artifact_manifest.csv")),
    failed = file.exists(file.path(dirs, "FAILED")) |
      file.exists(file.path(dirs, "failure.csv")),
    stringsAsFactors = FALSE
  )
}

app_joint_article_ready_vb_jobs <- function(root, plan = NULL, state = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  if (is.null(plan)) plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  if (is.null(state)) state <- app_joint_article_vb_worker_state(root, plan)
  if (any(state$failed)) return(integer())
  completed <- state$job_id[state$done]
  pending <- plan$job_id[!plan$job_id %in% completed]
  ready <- vapply(pending, function(id) {
    job <- plan[plan$job_id == id, , drop = FALSE]
    deps <- app_joint_article_dependency_rows(plan, job)
    !nrow(deps) || all(deps$job_id %in% completed)
  }, logical(1L))
  pending[ready]
}

app_joint_article_run_vb_queue <- function(
  root,
  max_workers = 32L,
  require_synced = TRUE
) {
  root <- normalizePath(root, mustWork = TRUE)
  if (!identical(Sys.getenv("JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION"), "VB")) {
    stop("Refusing VB launch without JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=VB.",
         call. = FALSE)
  }
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  app_joint_article_assert_clean_execution(contract, require_synced = require_synced)
  app_joint_article_assert_capacity_authorized(contract)
  app_joint_article_host_preflight(contract)
  max_workers <- as.integer(max_workers)[[1L]]
  if (!is.finite(max_workers) || is.na(max_workers) || max_workers < 1L ||
      max_workers > contract$maximum_concurrency) {
    stop(sprintf("VB max_workers must be between 1 and the frozen ceiling %d.",
      contract$maximum_concurrency), call. = FALSE)
  }
  Sys.setenv(
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
  )
  app_write_csv(data.frame(
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    root = root, max_workers = max_workers,
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    production_phase = "VB",
    mcmc_launched = FALSE,
    stringsAsFactors = FALSE
  ), file.path(root, "vb_queue_launch_receipt.csv"))
  repeat {
    plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
    state <- app_joint_article_vb_worker_state(root, plan)
    health <- app_joint_article_vb_health(root)
    app_joint_article_atomic_write_csv(health, file.path(root, "vb_queue_health.csv"))
    if (health$failed[[1L]] > 0L) {
      stop("VB queue stopped because at least one worker failed.", call. = FALSE)
    }
    if (health$completed[[1L]] == contract$expected_total_components) break
    ready <- app_joint_article_ready_vb_jobs(root, plan, state)
    ready <- ready[!ready %in% state$job_id[state$done]]
    if (!length(ready)) {
      stop("VB queue has pending work but no dependency-ready jobs.", call. = FALSE)
    }
    batch <- head(ready, max_workers)
    batch_id <- length(list.files(root,
      pattern = "^vb_queue_batch_[0-9][0-9][0-9][.]csv$")) + 1L
    batch_receipt <- data.frame(
      launched_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      job_id = batch,
      stringsAsFactors = FALSE
    )
    app_write_csv(batch_receipt, file.path(root, sprintf(
      "vb_queue_batch_%03d.csv", batch_id
    )))
    run_one <- function(job_id) {
      tryCatch({
        app_joint_article_run_vb_worker(root, job_id)
        data.frame(job_id = job_id, status = "completed", error_message = "",
          stringsAsFactors = FALSE)
      }, error = function(e) {
        data.frame(job_id = job_id, status = "failed",
          error_message = conditionMessage(e), stringsAsFactors = FALSE)
      })
    }
    result <- if (.Platform$OS.type != "windows" && length(batch) > 1L) {
      parallel::mclapply(batch, run_one,
        mc.cores = min(max_workers, length(batch)), mc.preschedule = FALSE)
    } else lapply(batch, run_one)
    result <- app_joint_qdesn_bind_rows(result)
    app_write_csv(result, file.path(root, sprintf(
      "vb_queue_batch_%03d_result.csv", batch_id)))
    if (any(result$status != "completed")) {
      stop("VB queue batch failed; inspect worker failure.csv files.",
           call. = FALSE)
    }
  }
  final_health <- app_joint_article_check_vb(root, require_complete = FALSE)
  if (final_health$health$completed[[1L]] != contract$expected_total_components ||
      final_health$health$failed[[1L]] != 0L) {
    stop("VB queue finished without satisfying the 136/136 gate.",
         call. = FALSE)
  }
  app_write_csv(data.frame(
    completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    vb_components_completed = final_health$health$completed[[1L]],
    vb_components_failed = final_health$health$failed[[1L]],
    production_phase = "VB",
    mcmc_launched = FALSE,
    stringsAsFactors = FALSE
  ), file.path(root, "vb_queue_completion_receipt.csv"))
  final_health
}

app_joint_article_load_vb_fit <- function(root, job) {
  path <- file.path(app_joint_article_vb_worker_dir(root, job$job_id[[1L]]),
    "fit_initializer.rds")
  if (!file.exists(path)) stop("Required article VB initializer is missing.",
    call. = FALSE)
  readRDS(path)
}

app_joint_article_stack_independent_for_cell <- function(root, plan, cell, contract) {
  design <- readRDS(cell$design_path[[1L]])
  jobs <- plan[plan$scenario_id == cell$scenario_id[[1L]] &
    plan$model_id == cell$vb_model_id[[1L]], , drop = FALSE]
  jobs <- jobs[order(jobs$tau), , drop = FALSE]
  fits <- lapply(seq_len(nrow(jobs)), function(ii) app_joint_article_load_vb_fit(
    root, jobs[ii, , drop = FALSE]))
  p <- ncol(design$Z)
  beta <- unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE)
  cov <- as.matrix(Matrix::bdiag(lapply(fits, function(x) as.matrix(x$beta_cov))))
  out <- list(
    beta_mean = beta, beta_cov = cov,
    alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
    tau = design$tau, fits = fits,
    fit_structure = "independent",
    source_vb_model_id = cell$vb_model_id[[1L]]
  )
  if (cell$likelihood_family[[1L]] == "exAL") {
    out$gamma_mean <- vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L))
    out$inference_method_id <- contract$exal_vb_method
  } else {
    out$inference_method_id <- "AL_VB"
  }
  gaussian <- app_joint_article_load_vb_fit(root,
    app_joint_article_find_job(plan, cell$scenario_id[[1L]], "gaussian_rhs_initializer"))
  out$rhs_state <- app_joint_qvp_initialize_rhs_state(length(design$tau), p,
    tau0 = gaussian$rhs_tau0, zeta2 = gaussian$initializer$zeta2,
    slab_fixed = contract$rhs_slab_fixed)
  out$rhs_state <- app_joint_qvp_update_rhs_vb_state(
    out$rhs_state, beta, cov, length(design$tau), p,
    n_inner = contract$rhs_vb_inner)$state
  out
}

app_joint_article_initializer_rows <- function(init, cell, contract) {
  blocks <- list(
    beta = as.numeric(init$beta_mean), alpha = as.numeric(init$alpha_mean),
    sigma = as.numeric(init$sigma_mean)
  )
  if (!is.null(init$gamma_mean)) blocks$gamma <- as.numeric(init$gamma_mean)
  if (any(!is.finite(unlist(blocks, use.names = FALSE))) ||
      any(blocks$sigma <= 0)) {
    stop("Compact article initializer contains invalid values.", call. = FALSE)
  }
  app_joint_qdesn_bind_rows(lapply(names(blocks), function(block) {
    data.frame(
      model_cell_id = cell$model_cell_id[[1L]],
      scenario_id = cell$scenario_id[[1L]],
      model_id = cell$model_id[[1L]],
      likelihood_family = cell$likelihood_family[[1L]],
      fit_structure = cell$fit_structure[[1L]],
      parameter_block = block,
      parameter_index = seq_along(blocks[[block]]),
      value = blocks[[block]],
      vb_method_id = init$inference_method_id %||%
        if (cell$likelihood_family[[1L]] == "exAL") contract$exal_vb_method else "AL_VB",
      mcmc_method_id = if (cell$likelihood_family[[1L]] == "exAL") {
        contract$exal_mcmc_method
      } else contract$al_mcmc_method,
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_article_finalize_vb <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  check <- app_joint_article_check_vb(root, require_complete = FALSE)
  if (check$health$completed[[1L]] != contract$expected_total_components ||
      check$health$failed[[1L]] != 0L) {
    stop("Cannot finalize article VB before all 136 components are complete and failure-free.",
         call. = FALSE)
  }
  plan <- app_read_csv(file.path(root, "vb_worker_plan.csv"))
  cells <- app_read_csv(file.path(root, "model_cell_plan.csv"))
  rows <- manifest_rows <- list()
  for (ii in seq_len(nrow(cells))) {
    cell <- cells[ii, , drop = FALSE]
    init <- if (cell$fit_structure[[1L]] == "joint") {
      app_joint_article_load_vb_fit(root,
        app_joint_article_find_job(plan, cell$scenario_id[[1L]], cell$vb_model_id[[1L]]))
    } else app_joint_article_stack_independent_for_cell(root, plan, cell, contract)
    init$type <- "joint_article_compact_initializer_v1"
    init$model_cell_id <- cell$model_cell_id[[1L]]
    init$scenario_id <- cell$scenario_id[[1L]]
    init$model_id <- cell$model_id[[1L]]
    init$design_fingerprint <- cell$design_fingerprint[[1L]]
    path <- file.path(root, cell$initializer_relative_path[[1L]])
    saveRDS(init, path, version = 3L, compress = "xz")
    rows[[ii]] <- app_joint_article_initializer_rows(init, cell, contract)
    manifest_rows[[ii]] <- data.frame(
      model_cell_id = cell$model_cell_id[[1L]], scenario_id = cell$scenario_id[[1L]],
      model_id = cell$model_id[[1L]], likelihood_family = cell$likelihood_family[[1L]],
      fit_structure = cell$fit_structure[[1L]], relative_path = cell$initializer_relative_path[[1L]],
      size_bytes = as.numeric(file.info(path)$size), sha256 = app_sha256_file(path),
      finite_values = TRUE,
      vb_method_id = init$inference_method_id %||% NA_character_,
      mcmc_method_id = if (cell$likelihood_family[[1L]] == "exAL") {
        contract$exal_mcmc_method
      } else contract$al_mcmc_method,
      stringsAsFactors = FALSE
    )
  }
  init_rows <- app_joint_qdesn_bind_rows(rows)
  manifest <- app_joint_qdesn_bind_rows(manifest_rows)
  if (nrow(manifest) != contract$expected_top_level_initializers ||
      anyDuplicated(manifest$model_cell_id) ||
      any(!manifest$finite_values) ||
      any(manifest$likelihood_family == "exAL" &
        manifest$mcmc_method_id != contract$exal_mcmc_method)) {
    stop("Article VB initializer manifest violates the 32-cell gate.",
         call. = FALSE)
  }
  init_rows_path <- app_write_csv(init_rows, file.path(root, "vb_initialization_rows.csv"))
  init_manifest_path <- app_write_csv(manifest, file.path(root, "vb_initializer_manifest.csv"))
  summary <- data.frame(
    status = "VB_COMPLETE_INITIALIZERS_READY_MCMC_STILL_NOT_LAUNCHED",
    vb_components_completed = contract$expected_total_components,
    top_level_initializers = nrow(manifest),
    mcmc_launch_gate_ready = TRUE,
    production_launched = FALSE,
    stringsAsFactors = FALSE
  )
  summary_path <- app_write_csv(summary, file.path(root, "vb_finalization_summary.csv"))
  worker_registry <- app_joint_qdesn_bind_rows(lapply(plan$job_id, function(id) {
    path <- file.path(app_joint_article_vb_worker_dir(root, id), "artifact_manifest.csv")
    data.frame(
      job_id = id,
      relative_path = file.path("workers", sprintf("worker_%04d", id),
        "artifact_manifest.csv"),
      size_bytes = as.numeric(file.info(path)$size),
      sha256 = app_sha256_file(path),
      stringsAsFactors = FALSE
    )
  }))
  worker_registry_path <- app_write_csv(worker_registry,
    file.path(root, "vb_worker_artifact_registry.csv"))
  initializer_paths <- stats::setNames(
    file.path(root, manifest$relative_path),
    paste0("initializer__", sprintf("%02d", seq_len(nrow(manifest))))
  )
  worker_manifest_paths <- stats::setNames(
    file.path(root, worker_registry$relative_path),
    paste0("worker_manifest__", sprintf("%03d", worker_registry$job_id))
  )
  closeout_files <- c(
    vb_finalization_summary = summary_path,
    vb_initialization_rows = init_rows_path,
    vb_initializer_manifest = init_manifest_path,
    vb_worker_artifact_registry = worker_registry_path,
    vb_worker_plan = file.path(root, "vb_worker_plan.csv"),
    model_cell_plan = file.path(root, "model_cell_plan.csv"),
    mcmc_worker_plan = file.path(root, "mcmc_worker_plan.csv"),
    source_top_hash_verification = file.path(root, "source_top_hash_verification.csv"),
    source_nested_manifest_verification = file.path(root, "source_nested_manifest_verification.csv"),
    host_preflight = file.path(root, "host_preflight.csv"),
    initializer_paths,
    worker_manifest_paths
  )
  app_joint_shared_write_manifest(root, closeout_files,
    filename = "vb_final_artifact_manifest.csv")
  closeout <- app_joint_shared_verify_manifest(root,
    file.path(root, "vb_final_artifact_manifest.csv"))
  if (any(!closeout$verified)) {
    stop("Article VB final artifact manifest failed verification.",
         call. = FALSE)
  }
  app_write_csv(closeout, file.path(root, "vb_final_manifest_verification.csv"))
  list(summary = summary, manifest = manifest, initialization_rows = init_rows,
    worker_registry = worker_registry, closeout = closeout)
}

app_joint_article_reconstruct_init <- function(rows, cell, tau, p) {
  get <- function(block, required = TRUE) {
    x <- rows[rows$model_cell_id == cell$model_cell_id[[1L]] &
      rows$parameter_block == block, , drop = FALSE]
    value <- as.numeric(x$value[order(x$parameter_index)])
    if (required && !length(value)) stop("Article initializer block is missing.",
      call. = FALSE)
    value
  }
  out <- list(
    beta_mean = get("beta"),
    alpha_mean = get("alpha"),
    sigma_mean = get("sigma"),
    gamma_mean = get("gamma", cell$likelihood_family[[1L]] == "exAL")
  )
  if (length(out$beta_mean) != length(tau) * p ||
      length(out$alpha_mean) != length(tau) ||
      length(out$sigma_mean) != length(tau) ||
      any(!is.finite(c(out$beta_mean, out$alpha_mean, out$sigma_mean))) ||
      any(out$sigma_mean <= 0) ||
      (cell$likelihood_family[[1L]] == "exAL" &&
        (length(out$gamma_mean) != length(tau) ||
          any(!is.finite(out$gamma_mean))))) {
    stop("Malformed compact article initializer rows.", call. = FALSE)
  }
  if (cell$fit_structure[[1L]] == "independent") {
    out$fits <- lapply(seq_along(tau), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      one <- list(beta_mean = out$beta_mean[idx],
        alpha_mean = out$alpha_mean[[k]], sigma_mean = out$sigma_mean[[k]])
      if (cell$likelihood_family[[1L]] == "exAL") {
        one$gamma_mean <- out$gamma_mean[[k]]
      }
      one
    })
  }
  out
}

app_joint_article_overdispersed_start <- function(init, job, tau) {
  app_joint_posterior_assert_initialization_only(init)
  set.seed(as.integer(job$chain_start_seed[[1L]]))
  K <- length(tau)
  p <- length(init$beta_mean) / K
  beta_scale <- pmax(abs(init$beta_mean), 0.05)
  alpha_scale <- pmax(abs(init$alpha_mean), 0.05)
  out <- init
  out$beta_mean <- init$beta_mean + stats::rnorm(length(init$beta_mean), 0, 0.05 * beta_scale)
  out$alpha_mean <- sort(init$alpha_mean + stats::rnorm(K, 0, 0.05 * alpha_scale))
  out$sigma_mean <- pmax(init$sigma_mean * exp(stats::rnorm(K, 0, 0.08)), 1e-8)
  if (!is.null(init$gamma_mean) && length(init$gamma_mean)) {
    out$gamma_mean <- vapply(seq_along(tau), function(k) {
      eta <- app_joint_exqdesn_gamma_to_support_eta(tau[[k]], init$gamma_mean[[k]])
      app_joint_exqdesn_support_eta_to_gamma(tau[[k]], eta + stats::rnorm(1L, 0, 0.06))
    }, numeric(1L))
  }
  if (!is.null(out$fits)) {
    out$fits <- lapply(seq_len(K), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      one <- list(beta_mean = out$beta_mean[idx],
        alpha_mean = out$alpha_mean[[k]], sigma_mean = out$sigma_mean[[k]])
      if (!is.null(out$gamma_mean) && length(out$gamma_mean)) {
        one$gamma_mean <- out$gamma_mean[[k]]
      }
      one
    })
  }
  out$init_source <- "deterministic_overdispersed_vb_start"
  out
}

app_joint_article_mcmc_attempt_root <- function(root, attempt_dir = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  if (is.null(attempt_dir) || !nzchar(as.character(attempt_dir)[[1L]])) {
    return(root)
  }
  normalizePath(attempt_dir, mustWork = TRUE)
}

app_joint_article_mcmc_failure_inventory <- function(root, attempt_dir = NULL) {
  attempt_root <- app_joint_article_mcmc_attempt_root(root, attempt_dir)
  worker_root <- file.path(attempt_root, "mcmc_workers")
  files <- list.files(worker_root, pattern = "failure[.]csv$", recursive = TRUE,
    full.names = TRUE)
  empty <- data.frame(
    worker_id = integer(), scenario_id = character(), model_id = character(),
    chain_id = integer(), likelihood_family = character(),
    fit_structure = character(), error_message = character(),
    runtime_seconds = numeric(), recorded_at = character(),
    failure_path = character(), failure_sha256 = character(),
    stringsAsFactors = FALSE
  )
  if (!length(files)) return(empty)
  rows <- lapply(files, function(path) {
    x <- app_read_csv(path)
    x$failure_path <- normalizePath(path, mustWork = TRUE)
    x$failure_sha256 <- app_sha256_file(path)
    x
  })
  out <- app_joint_qdesn_bind_rows(rows)
  keep <- intersect(names(empty), names(out))
  out <- out[, keep, drop = FALSE]
  missing <- setdiff(names(empty), names(out))
  for (name in missing) out[[name]] <- empty[[name]]
  out[order(out$worker_id), names(empty), drop = FALSE]
}

app_joint_article_mcmc_completed_inventory <- function(root, attempt_dir = NULL) {
  attempt_root <- app_joint_article_mcmc_attempt_root(root, attempt_dir)
  worker_root <- file.path(attempt_root, "mcmc_workers")
  files <- list.files(worker_root, pattern = "posterior_summary[.]csv$",
    recursive = TRUE, full.names = TRUE)
  if (!length(files)) {
    return(data.frame(
      worker_id = integer(), scenario_id = character(), model_id = character(),
      chain_id = integer(), likelihood_family = character(),
      fit_structure = character(), n_keep = integer(),
      precision_repair_count = integer(),
      precision_repair_max_relative_jitter = numeric(),
      runtime_seconds = numeric(), execution_code_commit = character(),
      worker_dir = character(), manifest_verified = logical(),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(files, function(path) {
    x <- app_read_csv(path)
    worker_dir <- dirname(path)
    x$worker_dir <- normalizePath(worker_dir, mustWork = TRUE)
    x$manifest_verified <- app_joint_article_mcmc_manifest_verified(worker_dir)
    x
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_article_mcmc_start_preflight <- function(root, worker_ids = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  plan <- plan[plan$likelihood_family == "exAL", , drop = FALSE]
  if (!is.null(worker_ids)) {
    plan <- plan[plan$worker_id %in% as.integer(worker_ids), , drop = FALSE]
  }
  if (!nrow(plan)) {
    return(data.frame(
      worker_id = integer(), scenario_id = character(), model_id = character(),
      chain_id = integer(), tau = numeric(), sigma_start = numeric(),
      gamma_start = numeric(), support_lower = numeric(),
      support_upper = numeric(), support_eta = numeric(),
      B = numeric(), weight_proxy = numeric(), status = character(),
      stringsAsFactors = FALSE
    ))
  }
  init_rows <- app_read_csv(file.path(root, "vb_initialization_rows.csv"))
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    job <- plan[ii, , drop = FALSE]
    design <- readRDS(job$design_path[[1L]])
    init <- app_joint_article_reconstruct_init(init_rows, job, design$tau,
      ncol(design$Z))
    start <- app_joint_article_overdispersed_start(init, job, design$tau)
    support <- app_joint_qvp_exal_support(design$tau)
    app_joint_qdesn_bind_rows(lapply(seq_along(design$tau), function(k) {
      constants <- tryCatch(
        app_joint_qvp_exal_constants(design$tau[[k]], start$gamma_mean[[k]]),
        error = function(e) NULL
      )
      B <- if (is.null(constants)) NA_real_ else constants$B[[1L]]
      eta <- tryCatch(app_joint_exqdesn_gamma_to_support_eta(
        design$tau[[k]], start$gamma_mean[[k]]
      ), error = function(e) NA_real_)
      weight_proxy <- 1 / (B * start$sigma_mean[[k]]^2)
      ok <- is.finite(start$sigma_mean[[k]]) && start$sigma_mean[[k]] > 0 &&
        is.finite(start$gamma_mean[[k]]) &&
        start$gamma_mean[[k]] > support$lower[[k]] &&
        start$gamma_mean[[k]] < support$upper[[k]] &&
        is.finite(eta) && is.finite(B) && B > 0 &&
        is.finite(weight_proxy) && weight_proxy > 0
      data.frame(
        worker_id = job$worker_id[[1L]],
        scenario_id = job$scenario_id[[1L]],
        model_id = job$model_id[[1L]],
        chain_id = job$chain_id[[1L]],
        tau = design$tau[[k]],
        sigma_start = start$sigma_mean[[k]],
        gamma_start = start$gamma_mean[[k]],
        support_lower = support$lower[[k]],
        support_upper = support$upper[[k]],
        support_eta = eta,
        B = B,
        weight_proxy = weight_proxy,
        status = if (ok) "pass" else "fail",
        stringsAsFactors = FALSE
      )
    }))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_article_mcmc_initial_precision_audit <- function(root,
  worker_ids = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  app_require_namespace("Matrix")
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  plan <- plan[plan$likelihood_family == "exAL", , drop = FALSE]
  if (!is.null(worker_ids)) {
    plan <- plan[plan$worker_id %in% as.integer(worker_ids), , drop = FALSE]
  }
  if (!nrow(plan)) {
    return(data.frame(
      worker_id = integer(), scenario_id = character(), model_id = character(),
      chain_id = integer(), dimension = integer(), fit_rows = integer(),
      p = integer(), K = integer(), dense_chol_ok = logical(),
      sparse_chol_ok = logical(), min_eigen = numeric(), max_eigen = numeric(),
      condition_number = numeric(), min_weight = numeric(),
      max_weight = numeric(), min_precision_diag = numeric(),
      max_precision_diag = numeric(), status = character(),
      stringsAsFactors = FALSE
    ))
  }
  init_rows <- app_read_csv(file.path(root, "vb_initialization_rows.csv"))
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    job <- plan[ii, , drop = FALSE]
    design <- readRDS(job$design_path[[1L]])
    Z <- design$Z[design$fit_local, , drop = FALSE]
    y <- design$y[design$fit_local]
    tau <- design$tau
    K <- length(tau)
    p <- ncol(Z)
    init <- app_joint_article_reconstruct_init(init_rows, job, tau, p)
    init <- app_joint_article_overdispersed_start(init, job, tau)
    target <- app_joint_article_resolve_posterior_target(root, job, design,
      app_joint_article_read_contract(file.path(root, "frozen_contract.csv")))
    set.seed(as.integer(job$chain_seed[[1L]]))
    constants <- app_joint_qvp_exal_constants(tau, init$gamma_mean)
    v <- matrix(rep(init$sigma_mean, each = length(y)), nrow = length(y),
      ncol = K)
    s <- matrix(abs(stats::rnorm(length(y) * K)), nrow = length(y), ncol = K)
    rhs_state <- app_joint_qvp_initialize_rhs_state(
      K, p, tau0 = as.numeric(job$rhs_tau0[[1L]]), zeta2 = target$zeta2,
      slab_fixed = target$slab_fixed
    )
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor,
      prior_state$innovations)
    work <- app_joint_qvp_build_working_response(
      y = y, Z = Z, beta = init$beta_mean, alpha = init$alpha_mean,
      tau = tau, sigma = init$sigma_mean, v = v, kappa = 1,
      likelihood = "exal", gamma = init$gamma_mean, s = s
    )
    beta_update <- app_joint_qvp_beta_gaussian_update(
      work$Z_stack, work$y_star, work$weights, prior$P_beta
    )
    dense <- as.matrix(beta_update$precision)
    dense_chol_ok <- !inherits(try(chol(dense), silent = TRUE), "try-error")
    sparse_chol_ok <- !inherits(try(Matrix::Cholesky(
      Matrix::forceSymmetric(beta_update$precision), LDL = FALSE, perm = TRUE
    ), silent = TRUE), "try-error")
    ev <- eigen(dense, symmetric = TRUE, only.values = TRUE)$values
    diag_values <- diag(dense)
    data.frame(
      worker_id = job$worker_id[[1L]],
      scenario_id = job$scenario_id[[1L]],
      model_id = job$model_id[[1L]],
      chain_id = job$chain_id[[1L]],
      dimension = length(beta_update$mean),
      fit_rows = length(y),
      p = p,
      K = K,
      dense_chol_ok = dense_chol_ok,
      sparse_chol_ok = sparse_chol_ok,
      min_eigen = min(ev),
      max_eigen = max(ev),
      condition_number = max(ev) / max(min(ev), .Machine$double.eps),
      min_weight = min(work$weights),
      max_weight = max(work$weights),
      min_precision_diag = min(diag_values),
      max_precision_diag = max(diag_values),
      status = if (dense_chol_ok && sparse_chol_ok &&
        all(is.finite(c(ev, work$weights, diag_values))) &&
        min(ev) > 0) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_article_write_mcmc_failure_audit <- function(root,
  attempt_dir = NULL, out_dir = NULL, worker_ids = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  attempt_root <- app_joint_article_mcmc_attempt_root(root, attempt_dir)
  if (is.null(out_dir) || !nzchar(as.character(out_dir)[[1L]])) {
    stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
    out_dir <- file.path(root, "diagnostics",
      paste0("mcmc_failure_audit_", stamp))
  }
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (dir.exists(out_dir)) {
    stop("MCMC failure audit output directory already exists.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  failure_inventory <- app_joint_article_mcmc_failure_inventory(root,
    attempt_root)
  if (is.null(worker_ids)) worker_ids <- unique(failure_inventory$worker_id)
  completed_inventory <- app_joint_article_mcmc_completed_inventory(root,
    attempt_root)
  start_preflight <- app_joint_article_mcmc_start_preflight(root, worker_ids)
  initial_precision <- app_joint_article_mcmc_initial_precision_audit(root,
    worker_ids)
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  plan_subset <- plan[plan$worker_id %in% as.integer(worker_ids), ,
    drop = FALSE]
  assessment <- data.frame(
    audit_status = if (nrow(failure_inventory)) {
      "joint_exal_precision_failure_localized"
    } else {
      "no_failures_found"
    },
    root = root,
    source_attempt_dir = attempt_root,
    failed_workers = nrow(failure_inventory),
    failed_joint_exal_workers = sum(
      failure_inventory$model_id == "joint_exqdesn_rhs_mcmc"
    ),
    completed_workers_in_attempt = nrow(completed_inventory),
    start_preflight_failures = sum(start_preflight$status != "pass"),
    initial_precision_failures = sum(initial_precision$status != "pass"),
    initial_precision_all_pass = all(initial_precision$status == "pass"),
    precision_repair_recommendation =
      "enable_strict_scale_aware_precision_draw_repair_for_exal",
    tau_or_tau0_change_recommended = FALSE,
    production_relaunch_required = nrow(failure_inventory) > 0L,
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# JOINT Article MCMC Failure Audit",
    "",
    "This audit is generated from ignored runtime evidence. It does not modify",
    "production worker directories, selected backbones, tau grids, tau0 values,",
    "article assets, or source evidence.",
    "",
    "The audit reconstructs deterministic exAL chain starts and the first",
    "beta precision update from the frozen article worker plan. A passing",
    "initial precision audit means failures occurred during dynamic MCMC",
    "state evolution rather than from malformed compact VB initializers."
  ), readme, useBytes = TRUE)
  paths <- c(
    README = readme,
    assessment = app_write_csv(assessment, file.path(out_dir,
      "audit_assessment.csv")),
    failure_inventory = app_write_csv(failure_inventory, file.path(out_dir,
      "failed_worker_inventory.csv")),
    completed_inventory = app_write_csv(completed_inventory, file.path(out_dir,
      "completed_worker_inventory.csv")),
    worker_plan_subset = app_write_csv(plan_subset, file.path(out_dir,
      "failed_worker_plan_subset.csv")),
    start_preflight = app_write_csv(start_preflight, file.path(out_dir,
      "failed_worker_start_preflight.csv")),
    initial_precision = app_write_csv(initial_precision, file.path(out_dir,
      "failed_worker_initial_precision.csv"))
  )
  queue_files <- c(
    mcmc_queue_launch_receipt = file.path(attempt_root,
      "mcmc_queue_launch_receipt.csv"),
    mcmc_execution_git_state = file.path(attempt_root,
      "mcmc_execution_git_state.csv"),
    mcmc_health_summary = file.path(attempt_root, "mcmc_health_summary.csv"),
    mcmc_queue_health = file.path(attempt_root, "mcmc_queue_health.csv")
  )
  queue_files <- queue_files[file.exists(queue_files)]
  if (length(queue_files)) {
    copied <- file.path(out_dir, basename(queue_files))
    file.copy(queue_files, copied, overwrite = FALSE)
    names(copied) <- names(queue_files)
    paths <- c(paths, copied)
  }
  app_joint_shared_write_manifest(out_dir, paths)
  verification <- app_joint_shared_verify_manifest(out_dir,
    file.path(out_dir, "artifact_manifest.csv"))
  app_write_csv(verification, file.path(out_dir,
    "artifact_manifest_verification.csv"))
  list(
    out_dir = out_dir,
    assessment = assessment,
    failure_inventory = failure_inventory,
    start_preflight = start_preflight,
    initial_precision = initial_precision,
    manifest_verification = verification
  )
}

app_joint_article_mcmc_launch_guard <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  health <- app_joint_article_vb_health(root)
  cells <- app_read_csv(file.path(root, "model_cell_plan.csv"))
  manifest_path <- file.path(root, "vb_initializer_manifest.csv")
  final_manifest_path <- file.path(root, "vb_final_artifact_manifest.csv")
  if (health$completed[[1L]] != contract$expected_total_components ||
      health$failed[[1L]] != 0L || !file.exists(manifest_path) ||
      !file.exists(final_manifest_path)) {
    stop("MCMC launch blocked: VB is not 136/136 with a 32-initializer manifest.",
         call. = FALSE)
  }
  manifest <- app_read_csv(manifest_path)
  paths_ok <- file.exists(file.path(root, manifest$relative_path))
  if (nrow(manifest) != contract$expected_top_level_initializers ||
      any(!paths_ok) || anyDuplicated(manifest$model_cell_id) ||
      !setequal(manifest$model_cell_id, cells$model_cell_id)) {
    stop("MCMC launch blocked: compact initializer manifest does not verify.",
         call. = FALSE)
  }
  final_check <- app_joint_shared_verify_manifest(root, final_manifest_path)
  if (any(!final_check$verified)) {
    stop("MCMC launch blocked: VB final artifact manifest does not verify.",
         call. = FALSE)
  }
  TRUE
}

app_joint_article_assert_mcmc_production_allowed <- function(
  contract, require_synced = TRUE
) {
  if (!identical(Sys.getenv("JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION"), "MCMC")) {
    stop("Refusing MCMC launch without JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC.",
         call. = FALSE)
  }
  app_joint_article_assert_clean_execution(contract, require_synced = require_synced)
  app_joint_article_assert_capacity_authorized(contract)
  app_joint_article_host_preflight(contract)
  invisible(TRUE)
}

app_joint_article_draw_frame <- function(fit) {
  blocks <- list(
    beta = as.data.frame(fit$beta_draws, check.names = FALSE),
    alpha = as.data.frame(fit$alpha_draws, check.names = FALSE),
    sigma = as.data.frame(fit$sigma_draws, check.names = FALSE)
  )
  if (!is.null(fit$gamma_draws)) {
    blocks$gamma <- as.data.frame(fit$gamma_draws, check.names = FALSE)
  }
  n <- vapply(blocks, nrow, integer(1L))
  if (!length(n) || length(unique(n)) != 1L || any(n <= 0L)) {
    stop("Article posterior draw blocks are malformed.", call. = FALSE)
  }
  out <- data.frame(draw_index = seq_len(n[[1L]]), stringsAsFactors = FALSE)
  for (name in names(blocks)) {
    block <- blocks[[name]]
    names(block) <- sprintf("%s_%04d", name, seq_len(ncol(block)))
    out[names(block)] <- block
  }
  if (any(!is.finite(as.matrix(out[, -1L, drop = FALSE])))) {
    stop("Article posterior draw frame contains nonfinite values.",
         call. = FALSE)
  }
  out
}

app_joint_article_write_gzip_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  con <- gzfile(path, open = "wt")
  on.exit(close(con), add = TRUE)
  write.csv(x, con, row.names = FALSE, na = "")
  invisible(path)
}

app_joint_article_mcmc_manifest_verified <- function(worker_dir) {
  manifest_path <- file.path(worker_dir, "artifact_manifest.csv")
  if (!file.exists(file.path(worker_dir, "DONE")) || !file.exists(manifest_path)) {
    return(FALSE)
  }
  check <- tryCatch(app_joint_shared_verify_manifest(worker_dir, manifest_path),
    error = function(e) NULL)
  is.data.frame(check) && nrow(check) > 0L && all(check$verified)
}

app_joint_article_mcmc_worker_state <- function(root, plan = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  if (is.null(plan)) plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  dirs <- vapply(plan$worker_id, function(id) app_joint_article_mcmc_worker_dir(root, id),
    character(1L))
  done <- vapply(dirs, app_joint_article_mcmc_manifest_verified, logical(1L))
  malformed_done <- file.exists(file.path(dirs, "DONE")) &
    file.exists(file.path(dirs, "artifact_manifest.csv")) & !done
  data.frame(
    worker_id = plan$worker_id,
    done = done,
    failed = file.exists(file.path(dirs, "FAILED")) |
      file.exists(file.path(dirs, "failure.csv")) | malformed_done,
    stringsAsFactors = FALSE
  )
}

app_joint_article_record_mcmc_failure <- function(root, worker_id, error_message,
  started = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  out <- app_joint_article_mcmc_worker_dir(root, worker_id)
  app_ensure_dir(out)
  job <- tryCatch({
    plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
    plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  }, error = function(e) data.frame())
  if (!nrow(job)) {
    job <- data.frame(worker_id = as.integer(worker_id), stringsAsFactors = FALSE)
  }
  failure <- cbind(job, data.frame(
    status = "failed",
    error_message = as.character(error_message),
    runtime_seconds = if (is.null(started)) NA_real_ else
      as.numeric(difftime(Sys.time(), started, units = "secs")),
    recorded_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  ))
  app_write_csv(failure, file.path(out, "failure.csv"))
  writeLines("failed", file.path(out, "FAILED"))
  invisible(out)
}

app_joint_article_run_mcmc_worker <- function(root, worker_id, require_synced = TRUE) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  app_joint_article_assert_mcmc_production_allowed(
    contract, require_synced = require_synced)
  app_joint_article_mcmc_launch_guard(root)
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  job <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(job) != 1L) stop("Article MCMC worker_id is not unique.", call. = FALSE)
  out <- app_joint_article_mcmc_worker_dir(root, worker_id)
  if (app_joint_article_mcmc_manifest_verified(out)) {
    return(invisible(out))
  }
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(out, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out, quarantine)) stop("Could not quarantine incomplete MCMC worker.",
      call. = FALSE)
  }
  tmp <- paste0(out, ".tmp.", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  design <- readRDS(job$design_path[[1L]])
  init_rows <- app_read_csv(file.path(root, "vb_initialization_rows.csv"))
  init <- app_joint_article_reconstruct_init(init_rows, job, design$tau, ncol(design$Z))
  target <- app_joint_article_resolve_posterior_target(root, job, design, contract)
  init <- app_joint_article_overdispersed_start(init, job, design$tau)
  started <- Sys.time()
  common <- list(
    y = design$y[design$fit_local],
    Z = design$Z[design$fit_local, , drop = FALSE],
    tau = design$tau,
    n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]),
    thin = as.integer(job$thin[[1L]]), seed = as.integer(job$chain_seed[[1L]]),
    kappa = 1, tau0 = as.numeric(job$rhs_tau0[[1L]]),
    zeta2 = target$zeta2, a_sigma = target$a_sigma, b_sigma = target$b_sigma,
    slab_fixed = target$slab_fixed,
    alpha_prior_mean = target$alpha_prior_mean,
    alpha_prior_sd = target$alpha_prior_sd,
    alpha_min_spacing = target$alpha_min_spacing,
    max_dense_dim = 0L,
    sigma_bounds = target$sigma_bounds,
    init = init
  )
  fit <- if (job$likelihood_family[[1L]] == "exAL") {
    common$precision_repair <- TRUE
    common$precision_repair_start_rel <- 1.0e-12
    common$precision_repair_max_rel <- 1.0e-8
    common$precision_repair_growth <- 10
    common$gamma_init <- init$gamma_mean
    common$gamma_slice_width <- 1
    common$gamma_slice_max_steps <- 100L
    if (job$fit_structure[[1L]] == "joint") {
      do.call(app_joint_exqdesn_fit_mcmc_dispatch,
        c(list(method_id = contract$exal_mcmc_method), common))
    } else {
      common$tau_seed_stride <- as.integer(job$tau_seed_stride[[1L]])
      do.call(app_joint_exqdesn_fit_independent_mcmc_dispatch,
        c(list(method_id = contract$exal_mcmc_method), common))
    }
  } else if (job$fit_structure[[1L]] == "joint") {
    do.call(app_joint_qvp_fit_al_mcmc_tiny, common)
  } else {
    tau_seed_stride <- as.integer(job$tau_seed_stride[[1L]])
    fits <- lapply(seq_along(design$tau), function(k) {
      one <- common
      one$tau <- design$tau[[k]]
      one$seed <- as.integer(job$chain_seed[[1L]] + k * tau_seed_stride)
      one$alpha_min_spacing <- 0
      one$alpha_prior_mean <- target$alpha_prior_mean[[k]]
      one$alpha_prior_sd <- target$alpha_prior_sd[[k]]
      one$init <- init$fits[[k]]
      do.call(app_joint_qvp_fit_al_mcmc_tiny, one)
    })
    app_joint_qdesn_phase122_combine_independent_chain(
      fits, design$Z[design$fit_local, , drop = FALSE],
      design$tau, job$chain_id[[1L]], job$chain_seed[[1L]])
  }
  draws <- app_joint_article_draw_frame(fit)
  qhat_fit <- app_joint_qdesn_predict_fit(
    fit, design$Z[design$fit_local, , drop = FALSE], design$tau)
  qhat_forecast_all <- app_joint_qdesn_predict_fit(
    fit, design$Z[design$validation_local, , drop = FALSE], design$tau)
  qhat_fit_contract <- app_joint_qdesn_apply_monotone_contract(qhat_fit, design$tau)
  qhat_forecast_contract <- app_joint_qdesn_apply_monotone_contract(qhat_forecast_all, design$tau)
  summary <- data.frame(
    worker_id = job$worker_id[[1L]], model_cell_id = job$model_cell_id[[1L]],
    scenario_id = job$scenario_id[[1L]], model_id = job$model_id[[1L]],
    likelihood_family = job$likelihood_family[[1L]],
    fit_structure = job$fit_structure[[1L]],
    inference_method_id = job$inference_method_id[[1L]],
    chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
    n_iter = job$n_iter[[1L]], burn = job$burn[[1L]],
    thin = job$thin[[1L]], n_keep = nrow(draws),
    fit_raw_crossing_pairs = sum(qhat_fit_contract$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(qhat_fit_contract$contract_crossing$n_crossing_pairs),
    forecast_raw_crossing_pairs = sum(qhat_forecast_contract$raw_crossing$n_crossing_pairs),
    forecast_contract_crossing_pairs = sum(qhat_forecast_contract$contract_crossing$n_crossing_pairs),
    gamma_sigma_diagnostics_retained = job$likelihood_family[[1L]] == "exAL",
    precision_repair_enabled = isTRUE(fit$precision_repair_enabled %||% FALSE),
    precision_repair_count = as.integer(fit$precision_repair_count %||% 0L),
    precision_repair_max_relative_jitter =
      as.numeric(fit$precision_repair_max_rel_used %||% 0),
    posterior_target_sha256 = target$hash,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    production_launched = TRUE,
    stringsAsFactors = FALSE
  )
  precision_diagnostics <- fit$precision_repair_diagnostics %||% data.frame(
    status = character(), backend = character(), dimension = integer(),
    attempt = integer(), jitter_relative = numeric(),
    jitter_absolute = numeric(), diagonal_scale = numeric(),
    error_message = character(), iteration = integer(),
    min_weight = numeric(), max_weight = numeric(),
    min_sigma = numeric(), max_sigma = numeric(),
    min_gamma = numeric(), max_gamma = numeric(),
    stringsAsFactors = FALSE
  )
  paths <- c(
    posterior_draws = app_joint_article_write_gzip_csv(draws,
      file.path(tmp, "posterior_draws.csv.gz")),
    posterior_summary = app_write_csv(summary, file.path(tmp, "posterior_summary.csv")),
    posterior_target_contract = app_write_csv(target$fields,
      file.path(tmp, "posterior_target_contract.csv")),
    precision_repair_diagnostics = app_write_csv(precision_diagnostics,
      file.path(tmp, "precision_repair_diagnostics.csv")),
    qhat_fit_mean = app_write_csv(as.data.frame(qhat_fit),
      file.path(tmp, "qhat_fit_mean.csv")),
    qhat_validation_mean = app_write_csv(as.data.frame(qhat_forecast_all),
      file.path(tmp, "qhat_validation_mean.csv"))
  )
  app_joint_shared_write_manifest(tmp, paths)
  writeLines("completed", file.path(tmp, "DONE"))
  if (!file.rename(tmp, out)) stop("Could not publish article MCMC worker output.",
    call. = FALSE)
  invisible(out)
}

app_joint_article_run_mcmc_queue <- function(
  root,
  max_workers = 40L,
  require_synced = TRUE
) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  app_joint_article_assert_mcmc_production_allowed(
    contract, require_synced = require_synced)
  max_workers <- as.integer(max_workers)[[1L]]
  if (!is.finite(max_workers) || is.na(max_workers) || max_workers < 1L ||
      max_workers > contract$maximum_concurrency) {
    stop(sprintf("MCMC max_workers must be between 1 and the frozen ceiling %d.",
      contract$maximum_concurrency), call. = FALSE)
  }
  app_joint_article_mcmc_launch_guard(root)
  Sys.setenv(
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
  )
  lock_dir <- file.path(root, "mcmc_queue.lock")
  if (!dir.create(lock_dir, showWarnings = FALSE)) {
    stop("MCMC queue lock already exists; refusing a duplicate launch.",
         call. = FALSE)
  }
  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)
  app_write_csv(data.frame(
    pid = Sys.getpid(),
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    root = root,
    max_workers = max_workers,
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    production_phase = "MCMC",
    stringsAsFactors = FALSE
  ), file.path(lock_dir, "owner.csv"))
  app_write_csv(app_joint_article_execution_git_state(),
    file.path(root, "mcmc_execution_git_state.csv"))
  app_write_csv(data.frame(
    started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    root = root,
    max_workers = max_workers,
    execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
    production_phase = "MCMC",
    stringsAsFactors = FALSE
  ), file.path(root, "mcmc_queue_launch_receipt.csv"))
  repeat {
    plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
    state <- app_joint_article_mcmc_worker_state(root, plan)
    health <- app_joint_article_check_mcmc(root)$summary
    health$completed_workers <- sum(state$done)
    health$failed_workers <- sum(state$failed)
    health$remaining_workers <- sum(!state$done & !state$failed)
    health$production_launched <- any(state$done)
    health$gate_status <- if (health$launch_gate_ready[[1L]] &&
        health$completed_workers[[1L]] == nrow(plan) &&
        health$failed_workers[[1L]] == 0L) "pass" else "fail"
    app_joint_article_atomic_write_csv(health, file.path(root, "mcmc_queue_health.csv"))
    if (!isTRUE(health$launch_gate_ready[[1L]])) {
      stop("MCMC queue stopped because the VB/initializer launch gate is not ready.",
           call. = FALSE)
    }
    if (health$failed_workers[[1L]] > 0L) {
      stop("MCMC queue stopped because at least one worker failed.",
           call. = FALSE)
    }
    if (health$completed_workers[[1L]] == nrow(plan)) break
    pending <- state$worker_id[!state$done & !state$failed]
    if (!length(pending)) {
      stop("MCMC queue has remaining work but no runnable workers.",
           call. = FALSE)
    }
    batch <- head(pending, max_workers)
    batch_id <- length(list.files(root,
      pattern = "^mcmc_queue_batch_[0-9][0-9][0-9][.]csv$")) + 1L
    app_write_csv(data.frame(
      launched_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      worker_id = batch,
      stringsAsFactors = FALSE
    ), file.path(root, sprintf("mcmc_queue_batch_%03d.csv", batch_id)))
    run_one <- function(worker_id) {
      started <- Sys.time()
      tryCatch({
        app_joint_article_run_mcmc_worker(root, worker_id, require_synced = FALSE)
        data.frame(worker_id = worker_id, status = "completed",
          error_message = "", stringsAsFactors = FALSE)
      }, error = function(e) {
        app_joint_article_record_mcmc_failure(root, worker_id,
          conditionMessage(e), started = started)
        data.frame(worker_id = worker_id, status = "failed",
          error_message = conditionMessage(e), stringsAsFactors = FALSE)
      })
    }
    result <- if (.Platform$OS.type != "windows" && length(batch) > 1L) {
      parallel::mclapply(batch, run_one,
        mc.cores = min(max_workers, length(batch)), mc.preschedule = FALSE)
    } else lapply(batch, run_one)
    result <- app_joint_qdesn_bind_rows(result)
    app_write_csv(result, file.path(root, sprintf(
      "mcmc_queue_batch_%03d_result.csv", batch_id)))
    if (any(result$status != "completed")) {
      stop("MCMC queue batch failed; inspect worker failure.csv files.",
           call. = FALSE)
    }
  }
  final_health <- app_joint_article_check_mcmc(root)
  if (!identical(final_health$summary$gate_status[[1L]], "pass")) {
    stop("MCMC queue finished without satisfying the 160/160 gate.",
         call. = FALSE)
  }
  app_write_csv(data.frame(
    completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    mcmc_workers_completed = final_health$summary$completed_workers[[1L]],
    mcmc_workers_failed = final_health$summary$failed_workers[[1L]],
    production_phase = "MCMC",
    stringsAsFactors = FALSE
  ), file.path(root, "mcmc_queue_completion_receipt.csv"))
  final <- app_joint_article_finalize_confirmation(root)
  list(summary = final_health$summary, final = final)
}

app_joint_article_check_mcmc <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  launch_ready <- tryCatch({
    app_joint_article_mcmc_launch_guard(root); TRUE
  }, error = function(e) FALSE)
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  state <- app_joint_article_mcmc_worker_state(root, plan)
  summary <- data.frame(
    expected_workers = nrow(plan), completed_workers = sum(state$done),
    failed_workers = sum(state$failed),
    remaining_workers = sum(!state$done & !state$failed),
    launch_gate_ready = launch_ready,
    production_launched = any(state$done),
    gate_status = if (launch_ready && all(state$done) && !any(state$failed)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  app_joint_article_atomic_write_csv(summary, file.path(root, "mcmc_health_summary.csv"))
  list(summary = summary)
}

app_joint_article_finalize_confirmation <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_article_read_contract(file.path(root, "frozen_contract.csv"))
  check <- app_joint_article_check_mcmc(root)
  if (!identical(check$summary$gate_status[[1L]], "pass")) {
    stop("Cannot finalize JOINT article confirmation before all MCMC workers verify.",
         call. = FALSE)
  }
  plan <- app_read_csv(file.path(root, "mcmc_worker_plan.csv"))
  worker_verification <- app_joint_qdesn_bind_rows(lapply(plan$worker_id, function(id) {
    dir <- app_joint_article_mcmc_worker_dir(root, id)
    check_one <- app_joint_shared_verify_manifest(dir, file.path(dir, "artifact_manifest.csv"))
    cbind(data.frame(worker_id = id, stringsAsFactors = FALSE), check_one)
  }))
  if (any(!worker_verification$verified)) {
    stop("Article MCMC worker manifest verification failed.", call. = FALSE)
  }
  worker_verification_path <- app_write_csv(worker_verification,
    file.path(root, "mcmc_worker_manifest_verification.csv"))
  posterior_summary <- app_joint_qdesn_bind_rows(lapply(plan$worker_id, function(id) {
    app_read_csv(file.path(app_joint_article_mcmc_worker_dir(root, id),
      "posterior_summary.csv"))
  }))
  if (nrow(posterior_summary) != contract$total_chain_workers ||
      anyDuplicated(posterior_summary$worker_id) ||
      any(!app_as_bool_vec(posterior_summary$production_launched))) {
    stop("Article MCMC posterior summary registry is malformed.",
         call. = FALSE)
  }
  target_hash_audit <- app_joint_article_target_hash_audit(
    posterior_summary, contract)
  target_hash_audit_path <- app_write_csv(target_hash_audit,
    file.path(root, "mcmc_posterior_target_hash_audit.csv"))
  posterior_summary_path <- app_write_csv(posterior_summary,
    file.path(root, "mcmc_posterior_summary_registry.csv"))
  worker_registry <- app_joint_qdesn_bind_rows(lapply(plan$worker_id, function(id) {
    path <- file.path(app_joint_article_mcmc_worker_dir(root, id),
      "artifact_manifest.csv")
    data.frame(
      worker_id = id,
      relative_path = file.path("mcmc_workers", sprintf("worker_%04d", id),
        "artifact_manifest.csv"),
      size_bytes = as.numeric(file.info(path)$size),
      sha256 = app_sha256_file(path),
      stringsAsFactors = FALSE
    )
  }))
  worker_registry_path <- app_write_csv(worker_registry,
    file.path(root, "mcmc_worker_artifact_registry.csv"))
  assessment <- data.frame(
    status = "MCMC_COMPLETE_READY_FOR_SCORE_PACKET",
    mcmc_workers_completed = check$summary$completed_workers[[1L]],
    mcmc_workers_failed = check$summary$failed_workers[[1L]],
    worker_manifests_verified = length(unique(worker_verification$worker_id)),
    posterior_target_cells_verified = nrow(target_hash_audit),
    production_launched = TRUE,
    article_assets_modified = FALSE,
    primary_score = "dgp_integrated_finite_grid_acrps",
    completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  )
  assessment_path <- app_write_csv(assessment,
    file.path(root, "final_confirmation_assessment.csv"))
  worker_manifest_paths <- stats::setNames(
    file.path(root, worker_registry$relative_path),
    paste0("mcmc_worker_manifest__", sprintf("%03d", worker_registry$worker_id))
  )
  optional <- c(
    mcmc_queue_launch_receipt = file.path(root, "mcmc_queue_launch_receipt.csv"),
    mcmc_queue_completion_receipt = file.path(root, "mcmc_queue_completion_receipt.csv"),
    mcmc_execution_git_state = file.path(root, "mcmc_execution_git_state.csv")
  )
  optional <- optional[file.exists(optional)]
  closeout_files <- c(
    final_confirmation_assessment = assessment_path,
    mcmc_health_summary = file.path(root, "mcmc_health_summary.csv"),
    mcmc_worker_plan = file.path(root, "mcmc_worker_plan.csv"),
    model_cell_plan = file.path(root, "model_cell_plan.csv"),
    scoring_contract = file.path(root, "scoring_contract.csv"),
    vb_final_artifact_manifest = file.path(root, "vb_final_artifact_manifest.csv"),
    mcmc_posterior_summary_registry = posterior_summary_path,
    mcmc_posterior_target_hash_audit = target_hash_audit_path,
    mcmc_worker_manifest_verification = worker_verification_path,
    mcmc_worker_artifact_registry = worker_registry_path,
    optional,
    worker_manifest_paths
  )
  app_joint_shared_write_manifest(root, closeout_files,
    filename = "mcmc_final_artifact_manifest.csv")
  closeout <- app_joint_shared_verify_manifest(root,
    file.path(root, "mcmc_final_artifact_manifest.csv"))
  if (any(!closeout$verified)) {
    stop("Article MCMC final artifact manifest failed verification.",
         call. = FALSE)
  }
  app_write_csv(closeout, file.path(root, "mcmc_final_manifest_verification.csv"))
  list(assessment = assessment, summary = check$summary,
    worker_verification = worker_verification, closeout = closeout)
}

app_joint_article_target_hash_audit <- function(posterior_summary, contract) {
  if (!isTRUE(contract$posterior_target_hash_required)) {
    return(data.frame(
      model_cell_id = character(), n_chains = integer(),
      posterior_target_sha256 = character(), verified = logical(),
      stringsAsFactors = FALSE
    ))
  }
  app_check_required_columns(posterior_summary, c(
    "model_cell_id", "likelihood_family", "posterior_target_sha256"
  ), "JOINT article posterior target summary")
  hashes <- trimws(as.character(posterior_summary$posterior_target_sha256))
  if (any(!grepl("^[0-9a-f]{64}$", hashes))) {
    stop("Posterior-target hashes must be nonempty lowercase SHA-256 values.",
      call. = FALSE)
  }
  groups <- split(seq_len(nrow(posterior_summary)), posterior_summary$model_cell_id)
  rows <- lapply(names(groups), function(cell_id) {
    idx <- groups[[cell_id]]
    unique_hash <- unique(hashes[idx])
    likelihood <- unique(as.character(posterior_summary$likelihood_family[idx]))
    if (length(unique_hash) != 1L) {
      stop(sprintf("Posterior target differs across chains for model cell '%s'.",
        cell_id), call. = FALSE)
    }
    if (length(likelihood) != 1L || !likelihood %in% c("AL", "exAL")) {
      stop(sprintf("Likelihood family is malformed for model cell '%s'.",
        cell_id), call. = FALSE)
    }
    expected_chains <- if (likelihood == "exAL") {
      as.integer(contract$exal_chains_per_cell)
    } else {
      as.integer(contract$al_chains_per_cell)
    }
    if (length(idx) != expected_chains) {
      stop(sprintf("Model cell '%s' has %d chains; expected %d.",
        cell_id, length(idx), expected_chains), call. = FALSE)
    }
    data.frame(
      model_cell_id = cell_id,
      likelihood_family = likelihood,
      n_chains = length(idx),
      posterior_target_sha256 = unique_hash,
      verified = TRUE,
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  expected_cells <- as.integer(contract$expected_top_level_initializers)
  if (nrow(out) != expected_cells || anyDuplicated(out$model_cell_id)) {
    stop("Posterior-target hash audit does not cover the complete model-cell grid.",
      call. = FALSE)
  }
  out[order(out$model_cell_id), , drop = FALSE]
}

app_joint_article_parity_fixture <- function() {
  contract <- app_joint_article_read_contract()
  set.seed(20260907)
  Z <- cbind(x1 = stats::rnorm(18), x2 = stats::rnorm(18))
  X <- cbind(`(Intercept)` = 1, Z)
  y <- 0.25 + 0.4 * Z[, 1] - 0.2 * Z[, 2] + stats::rnorm(18, sd = 0.25)
  ridge <- app_glofas_normal_ridge_fit(X, y)
  candidate <- data.frame(candidate_id = "parity", rhs_tau0 = 0.5,
    stringsAsFactors = FALSE)
  design <- list(X = X, Z = Z, y = y, fit_local = seq_along(y),
    design_fingerprint = app_joint_qvp_sha256_text(paste(round(Z, 10), collapse = ";")))
  warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
  gaussian <- app_glofas_normal_rhs_fit(
    X, y, warm, tau0 = 0.5, max_iter = 6L, min_iter = 2L, tol = 1e-4)
  init <- app_joint_shared_quantile_gaussian_init(gaussian, design, contract$tau, contract)
  al <- app_joint_qvp_fit_al_vb_tiny(
    y = y, Z = Z, tau = 0.5, max_iter = 2L, tol = 1e-5,
    tau0 = 0.5, a_sigma = 2, b_sigma = 1,
    alpha_prior_mean = init$alpha_mean[[4L]],
    alpha_prior_sd = init$alpha_prior_sd, max_dense_dim = 300L,
    init = list(
      beta_mean = init$beta_mean[7:8],
      beta_cov = init$beta_cov[7:8, 7:8, drop = FALSE],
      alpha_mean = init$alpha_mean[[4L]],
      sigma_mean = init$sigma_mean[[4L]],
      rhs_state = list(anchor = init$rhs_state$anchor),
      iterations_completed = 0L
    ))
  qhat <- app_joint_qdesn_predict_fit(al, Z, 0.5)
  data.frame(
    fixture_id = "tiny_api_parity_20260907",
    design_fingerprint = design$design_fingerprint,
    beta_length = length(init$beta_mean),
    beta_cov_nrow = nrow(init$beta_cov),
    alpha_length = length(init$alpha_mean),
    sigma_length = length(init$sigma_mean),
    al_beta_sum = round(sum(al$beta_mean), 12),
    al_alpha = round(al$alpha_mean[[1L]], 12),
    al_sigma = round(al$sigma_mean[[1L]], 12),
    qhat_sha12 = substr(app_joint_qvp_sha256_text(
      paste(format(qhat, digits = 16), collapse = ";")), 1L, 12L),
    monotone_contract_crossings = sum(app_joint_qdesn_apply_monotone_contract(
      cbind(qhat, qhat + 0.1), c(0.5, 0.75))$contract_crossing$n_crossing_pairs),
    primary_score = contract$primary_score,
    stringsAsFactors = FALSE
  )
}
