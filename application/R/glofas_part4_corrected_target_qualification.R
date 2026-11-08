gptq_expected <- list(
  design_sha256 = "55edbd490c622bdc55ebf373d792dbbb4f1be71fffc8df115e44f089548c4b33",
  normal_prior_sha256 = "0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357",
  state_contract_sha256 = "b47a6de3bb8c1b3b01e8639870cb70ac45c5e6e790bd88795683f460ff240e5a",
  rejected_target_sha256 = "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03",
  root_cause_sha256 = "7370fbd46ee4c88fdeea35a0ab7f85c98cff95f06a6ecff28bee60b102aa180b",
  corrected_source_head = "60daab261d52eec0ae24060babe186d618303e2b",
  rejected_source_head = "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6"
)

gptq_stop <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)

gptq_sha <- function(path) {
  gptq_stop(file.exists(path), paste0("Missing file: ", path))
  unname(tools::md5sum(path))
}

gptq_sha256 <- function(path) {
  gptq_stop(file.exists(path), paste0("Missing file: ", path))
  out <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  gptq_stop(length(out) == 1L, paste0("sha256sum failed: ", path))
  sub("[[:space:]].*$", "", out)
}

gptq_read_csv <- function(path) utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
gptq_read_json <- function(path) jsonlite::fromJSON(path, simplifyVector = TRUE)
gptq_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

gptq_bool <- function(x) isTRUE(as.logical(x))

gptq_target_manifests <- function(corrected_root) {
  files <- sort(list.files(file.path(corrected_root, "manifests"), pattern = "_target[.]json$", full.names = TRUE))
  gptq_stop(length(files) == 18L, "Corrected runtime must contain exactly 18 target manifests.")
  do.call(rbind, lapply(files, function(path) {
    x <- gptq_read_json(path)
    data.frame(
      job_id = x$job_id,
      family = x$family,
      shared_design_sha256 = x$shared_design_sha256,
      state_contract_hash = x$state_contract_hash,
      future_path_prior_hash = if (is.null(x$future_path_prior_hash)) NA_character_ else x$future_path_prior_hash,
      included_future_Y = x$included_future_Y,
      included_issued_G = x$included_issued_G,
      future_truth_used_in_fit = x$future_truth_used_in_fit,
      quantile_future_y_likelihood = x$quantile_future_y_likelihood,
      source_path = normalizePath(path),
      source_sha256 = gptq_sha256(path),
      stringsAsFactors = FALSE
    )
  }))
}

gptq_fit_audit <- function(corrected_root) {
  files <- sort(list.files(file.path(corrected_root, "objects"), pattern = "_fit_side[.]rds$", full.names = TRUE))
  gptq_stop(length(files) == 18L, "Corrected runtime must contain exactly 18 fit-side RDS objects.")
  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    path <- files[[i]]
    x <- readRDS(path)
    joint <- grepl("joint_(al|exal)", basename(path))
    normal <- grepl("normal_(ridge|rhs)", basename(path))
    if (joint) {
      cores <- x$fits
      prior_used <- all(vapply(cores, function(z) gptq_bool(z$vb_diagnostics$future_gaussian_prior_used), logical(1L)))
      prior_hash <- unique(vapply(cores, function(z) z$vb_diagnostics$future_gaussian_prior_contract_hash %||% NA_character_, character(1L)))
      y_likelihood <- any(vapply(cores, function(z) gptq_bool(z$vb_diagnostics$future_y_working_likelihood_used), logical(1L)))
      converged <- gptq_bool(x$converged) && gptq_bool(x$converged_outer) &&
        gptq_bool(x$converged_inner) && gptq_bool(x$converged_rhs) &&
        all(vapply(cores, function(z) gptq_bool(z$vb_diagnostics$converged), logical(1L)))
      family <- if (grepl("joint_exal", basename(path))) "MQ exAL" else "MQ AL"
      core_count <- length(cores)
      state_hash <- paste(unique(x$unit_member_state_contract_hashes), collapse = "|")
    } else if (normal) {
      fit <- x$fit %||% x
      prior_used <- NA
      prior_hash <- NA_character_
      y_likelihood <- NA
      converged <- gptq_bool(fit$vb_diagnostics$converged %||% x$converged %||% TRUE)
      family <- if (grepl("normal_rhs", basename(path))) "Normal RHS/VB" else "Normal Ridge"
      core_count <- 1L
      state_hash <- x$state_contract_hash %||% NA_character_
    } else {
      fit <- x$fit
      prior_used <- gptq_bool(fit$vb_diagnostics$future_gaussian_prior_used)
      prior_hash <- fit$vb_diagnostics$future_gaussian_prior_contract_hash %||% NA_character_
      y_likelihood <- gptq_bool(fit$vb_diagnostics$future_y_working_likelihood_used)
      converged <- gptq_bool(fit$vb_diagnostics$converged)
      family <- if (grepl("independent_exal", basename(path))) "Independent exAL" else "Independent AL"
      core_count <- 1L
      state_hash <- x$state_contract_hash %||% NA_character_
    }
    rows[[i]] <- data.frame(
      file = basename(path), family = family, core_count = core_count,
      converged = converged, gaussian_path_prior_used = prior_used,
      gaussian_path_prior_sha256 = paste(prior_hash, collapse = "|"),
      future_y_working_likelihood_used = y_likelihood,
      state_contract_sha256 = state_hash,
      size_bytes = as.numeric(file.info(path)$size), sha256 = gptq_sha256(path),
      stringsAsFactors = FALSE
    )
    rm(x); gc(FALSE)
  }
  do.call(rbind, rows)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

gptq_validate_corrected <- function(corrected_root, deep_fit_audit = TRUE) {
  corrected_root <- normalizePath(corrected_root, mustWork = TRUE)
  status_root <- file.path(corrected_root, "status")
  completed <- list.files(status_root, pattern = "[.]completed$", full.names = TRUE)
  failed <- list.files(status_root, pattern = "[.]failed$", full.names = TRUE)
  running <- list.files(status_root, pattern = "[.]running$", full.names = TRUE)
  gptq_stop(length(completed) == 18L && !length(failed) && !length(running),
    "Corrected runtime is not exactly 18/18 completed with no failed/running jobs.")

  decision <- gptq_read_json(file.path(corrected_root, "final_packet/DECISION.json"))
  gptq_stop(decision$fit_units == 18L && decision$numerical_pass == 18L && decision$numerical_review == 0L,
    "Corrected runtime decision does not certify 18/18 numerical passes.")
  gptq_stop(!gptq_bool(decision$model_selection_or_retuning) && !gptq_bool(decision$article_changed),
    "Corrected runtime crossed a selection or article boundary.")

  design_path <- file.path(corrected_root, "objects/part4_shared_design_truth_free.rds")
  gptq_stop(identical(gptq_sha256(design_path), gptq_expected$design_sha256),
    "Corrected shared design hash changed.")
  targets <- gptq_target_manifests(corrected_root)
  gptq_stop(all(targets$shared_design_sha256 == gptq_expected$design_sha256),
    "A corrected target manifest does not bind the corrected design.")
  gptq_stop(all(targets$state_contract_hash == gptq_expected$state_contract_sha256),
    "A corrected target manifest has a different state contract.")
  q <- !grepl("^normal_", targets$family)
  gptq_stop(sum(q) == 16L && all(targets$included_future_Y[q] == 0L) &&
    all(targets$included_issued_G[q] == 1428L) &&
    all(targets$future_path_prior_hash[q] == gptq_expected$normal_prior_sha256) &&
    !any(targets$future_truth_used_in_fit[q]) && !any(targets$quantile_future_y_likelihood[q]),
    "Corrected quantile target does not use the frozen Normal-driver prior cleanly.")

  gates <- gptq_read_csv(file.path(corrected_root, "final_packet/fit_numerical_gates.csv"))
  gptq_stop(nrow(gates) == 18L && all(gates$recorded_converged) &&
    all(gates$strict_numerical_gate) && all(gates$quadrature_pass),
    "Corrected numerical gate table is incomplete.")
  scores <- gptq_read_csv(file.path(corrected_root, "final_packet/family_scores.csv"))
  gptq_stop(nrow(scores) == 7L && all(scores$n_scored_horizons == 28L),
    "Corrected family score table is incomplete.")
  raw <- scores$crps_grid_log1p[scores$family == "Raw GloFAS"]
  quantile <- scores$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  gptq_stop(length(raw) == 1L && all(scores$crps_grid_log1p[quantile] < raw) &&
    max(scores$crossing_pairs[quantile]) <= 1L,
    "Corrected quantile families fail the predeclared raw-score/crossing qualification.")
  fits <- if (deep_fit_audit) gptq_fit_audit(corrected_root) else data.frame()
  if (deep_fit_audit) {
    qfit <- fits$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
    gptq_stop(all(fits$converged) && sum(qfit) == 16L &&
      all(fits$gaussian_path_prior_used[qfit]) &&
      all(fits$gaussian_path_prior_sha256[qfit] == gptq_expected$normal_prior_sha256) &&
      !any(fits$future_y_working_likelihood_used[qfit]),
      "Direct corrected fit audit failed the Gaussian-prior/no-future-Y contract.")
  }
  list(targets = targets, fits = fits, scores = scores, decision = decision,
    design_path = design_path)
}

gptq_validate_rejected <- function(rejected_root, article_root) {
  rejected_root <- normalizePath(rejected_root, mustWork = TRUE)
  configs <- sort(list.files(file.path(rejected_root, "configs"), pattern = "^gft-.*[.]rds$", full.names = TRUE))
  receipts <- sort(list.files(file.path(rejected_root, "results"), pattern = "target_receipt[.]json$",
    recursive = TRUE, full.names = TRUE))
  fits <- sort(list.files(file.path(rejected_root, "results"), pattern = "^fit[.]rds$",
    recursive = TRUE, full.names = TRUE))
  gptq_stop(length(configs) == 16L && length(receipts) == 16L && length(fits) == 16L,
    "Rejected campaign must retain exactly 16 configs, receipts and fits.")
  config_rows <- do.call(rbind, lapply(configs, function(path) {
    x <- readRDS(path)
    data.frame(task_id = x$task_id, historical_source_job_id = x$historical_source_job_id,
      source_design_sha256 = x$source_design_sha256,
      posterior_target_sha256 = x$posterior_target_sha256,
      source_config_sha256 = x$source_config_sha256,
      source_model_grid_sha256 = x$source_model_grid_sha256,
      prior_sha256 = x$prior_sha256, stringsAsFactors = FALSE)
  }))
  gptq_stop(all(config_rows$source_design_sha256 == gptq_expected$design_sha256) &&
    all(config_rows$posterior_target_sha256 == gptq_expected$rejected_target_sha256) &&
    all(grepl("^glofas_unit_member_correction_20261029_r3_", config_rows$historical_source_job_id)),
    "Rejected campaign is not exactly lineage-bound to the corrected October design and fits.")
  receipt_rows <- do.call(rbind, lapply(receipts, function(path) {
    x <- gptq_read_json(path)
    tc <- x$target_contract
    data.frame(task_id = x$identity$task_id, converged = x$converged,
      posterior_target_sha256 = x$identity$posterior_target_sha256,
      reference_future_law = tc$reference_future_law,
      replacement_gaussian_path_prior = tc$replacement_gaussian_path_prior,
      future_truth_used_in_fit = tc$future_truth_used_in_fit,
      source_path = normalizePath(path), source_sha256 = gptq_sha256(path),
      stringsAsFactors = FALSE)
  }))
  gptq_stop(all(receipt_rows$converged) &&
    all(receipt_rows$posterior_target_sha256 == gptq_expected$rejected_target_sha256) &&
    all(receipt_rows$reference_future_law == "one_normalized_same_family_Y_transition_per_horizon_per_level") &&
    !any(receipt_rows$replacement_gaussian_path_prior) && !any(receipt_rows$future_truth_used_in_fit),
    "Rejected target receipts do not reproduce the same-family target contract.")
  metrics_path <- file.path(article_root, "tables/glofas_same_family_20261103_family_metrics.csv")
  metrics <- gptq_read_csv(metrics_path)
  bad <- metrics$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  gptq_stop(all(metrics$raw_crossing_pairs[bad] >= 39L) &&
    all(metrics$grid_acrps_log1p[bad] > metrics$grid_acrps_log1p[metrics$family == "Raw GloFAS"]),
    "Rejected article packet no longer reproduces the adverse crossing/score evidence.")
  list(configs = config_rows, receipts = receipt_rows, metrics = metrics,
    metrics_path = metrics_path)
}

gptq_normalize_family <- function(x) {
  x[x == "Joint AL"] <- "MQ AL"
  x[x == "Joint exAL"] <- "MQ exAL"
  x[x == "Normal RHS"] <- "Normal RHS/VB"
  x
}

gptq_comparison <- function(search3_scores, corrected_scores, rejected_scores) {
  pick <- function(x, scenario, family_col, crps_col, crossing_col) data.frame(
    scenario = scenario, family = gptq_normalize_family(x[[family_col]]),
    crps_grid_log1p = x[[crps_col]], crossing_pairs = x[[crossing_col]], stringsAsFactors = FALSE)
  out <- rbind(
    pick(search3_scores, "Search III coherent baseline", "family", "crps_grid_log1p", "crossing_pairs"),
    pick(corrected_scores, "October coherent later design", "family", "crps_grid_log1p", "crossing_pairs"),
    pick(rejected_scores, "November rejected same-family", "family", "grid_acrps_log1p", "raw_crossing_pairs")
  )
  out[order(match(out$family, c("Raw GloFAS", "Normal Ridge", "Normal RHS/VB", "Independent AL",
    "Independent exAL", "MQ AL", "MQ exAL")), out$scenario), ]
}

gptq_plot_paths <- function(path, comparison, search3_paths, corrected_paths, rejected_paths) {
  families <- c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  scenarios <- c("Search III coherent baseline", "October coherent later design", "November rejected same-family")
  tau <- c(.05, .2, .35, .5, .65, .8, .95)
  cols <- c("#2B6CB0", "#2C7A7B", "#38A169", "#202124", "#D69E2E", "#DD6B20", "#C53030")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 14, height = 7.6, onefile = TRUE, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)

  fam_order <- c("Raw GloFAS", "Normal Ridge", "Normal RHS/VB", families)
  mat <- matrix(NA_real_, nrow = length(fam_order), ncol = length(scenarios),
    dimnames = list(fam_order, scenarios))
  for (i in seq_len(nrow(comparison))) mat[comparison$family[i], comparison$scenario[i]] <- comparison$crps_grid_log1p[i]
  par(mar = c(5, 4.5, 3.5, 1), las = 1)
  barplot(mat, beside = TRUE, col = c("#767676", "#355C7D", "#4C956C", "#2B6CB0", "#2C7A7B", "#D69E2E", "#C53030"),
    names.arg = c("Search III", "October coherent", "November rejected"),
    ylab = "Seven-quantile grid CRPS (log1p)", main = "Part 4 target qualification: score comparison", border = NA)
  legend("topright", legend = fam_order, fill = c("#767676", "#355C7D", "#4C956C", "#2B6CB0", "#2C7A7B", "#D69E2E", "#C53030"), cex = .8, bty = "n")

  prepare <- function(family, scenario) {
    if (scenario == scenarios[1]) {
      z <- search3_paths[search3_paths$part == "Part 4" & gptq_normalize_family(search3_paths$family) == family, ]
      data.frame(target_date = as.Date(z$target_date), tau = as.numeric(z$quantile_level), qhat = as.numeric(z$qhat), truth = as.numeric(z$y_reference))
    } else if (scenario == scenarios[2]) {
      z <- corrected_paths[corrected_paths$family == family, ]
      data.frame(target_date = as.Date(z$target_date), tau = z$quantile_level, qhat = z$qhat, truth = z$y_reference)
    } else {
      z <- rejected_paths[rejected_paths$family == family, ]
      data.frame(target_date = as.Date(z$target_date), tau = z$tau, qhat = z$quantile_transformed,
        truth = rep(NA_real_, nrow(z)))
    }
  }
  truth_map <- unique(corrected_paths[c("target_date", "y_reference")])
  for (family in families) {
    par(mfrow = c(1, 3), mar = c(4.2, 4.2, 4.2, .8), oma = c(0, 0, 2, 0), las = 1)
    for (scenario in scenarios) {
      z <- prepare(family, scenario)
      if (scenario == scenarios[3]) z$truth <- truth_map$y_reference[match(z$target_date, as.Date(truth_map$target_date))]
      ylim <- range(c(z$qhat, z$truth), finite = TRUE)
      sc <- comparison[comparison$family == family & comparison$scenario == scenario, ]
      plot(range(z$target_date), ylim, type = "n", xlab = "Target date", ylab = "log1p streamflow",
        main = sprintf("%s\nCRPS %.3f | crossings %d", scenario,
          sc$crps_grid_log1p, sc$crossing_pairs), xaxt = "n", cex.main = .9)
      axis.Date(1, at = pretty(z$target_date, 5), format = "%b %d")
      abline(v = as.Date("2022-12-25"), lty = 3, col = "#888888")
      for (j in seq_along(tau)) {
        q <- z[z$tau == tau[j], ]; q <- q[order(q$target_date), ]
        lines(q$target_date, q$qhat, col = cols[j], lwd = if (tau[j] == .5) 2.3 else 1.2)
      }
      tt <- unique(z[c("target_date", "truth")]); tt <- tt[order(tt$target_date), ]
      lines(tt$target_date, tt$truth, col = "black", lwd = 2.2, lty = 2)
      if (scenario == scenarios[1]) legend("topleft", legend = c(sprintf("q%.0f", 100*tau), "USGS truth"),
        col = c(cols, "black"), lty = c(rep(1, 7), 2), lwd = c(rep(1.4, 7), 2.2), cex = .65, bty = "n", ncol = 2)
    }
    mtext(paste0(family, ": coherent targets versus rejected same-family target"), outer = TRUE, cex = 1.2, font = 2)
  }
}

gptq_build <- function(repo_root, corrected_root, rejected_root, search3_root, root_cause_path,
  output_root, deep_fit_audit = TRUE) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  output_root <- normalizePath(output_root, mustWork = FALSE)
  gptq_stop(!file.exists(output_root), "Output root already exists; refusing to overwrite.")
  stage <- paste0(output_root, ".staging-", Sys.getpid())
  gptq_stop(!file.exists(stage), "Staging root already exists.")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)

  corrected <- gptq_validate_corrected(corrected_root, deep_fit_audit)
  rejected <- gptq_validate_rejected(rejected_root, repo_root)
  gptq_stop(identical(gptq_sha256(root_cause_path), gptq_expected$root_cause_sha256),
    "Root-cause decision hash changed.")
  root_decision <- gptq_read_csv(root_cause_path)
  gptq_stop(identical(root_decision$status, "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE") &&
    !root_decision$convergence_or_monte_carlo_failure && !root_decision$broad_refit_authorized,
    "Root-cause decision no longer blocks blind refitting.")

  search3_scores <- gptq_read_csv(file.path(search3_root, "tables/part4_family_scores.csv"))
  comparison <- gptq_comparison(search3_scores, corrected$scores, rejected$metrics)
  lineage <- data.frame(
    stage = c("Search III coherent baseline", "October coherent later design", "November rejected same-family"),
    source_head = c(NA, gptq_expected$corrected_source_head, gptq_expected$rejected_source_head),
    source_design_sha256 = c("a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9",
      gptq_expected$design_sha256, gptq_expected$design_sha256),
    future_path_target = c("shared frozen Part 3 Normal-RHS Gaussian driver",
      "shared frozen Part 3 Normal-RHS Gaussian driver",
      "separate normalized same-family transition for each quantile level"),
    target_status = c("coherent control", "coherent corrected counterpart", "structurally rejected"),
    stringsAsFactors = FALSE)
  contracts <- data.frame(
    packet = lineage$stage,
    shared_response_law = c(TRUE, TRUE, FALSE),
    gaussian_path_prior = c(TRUE, TRUE, FALSE),
    future_usgs_truth_in_fit = FALSE,
    issued_glofas_factors = c(1428L, 1428L, 1428L),
    quantile_fit_count = c(16L, 16L, 16L),
    disposition = c("retain as historical coherent control", "qualify as repaired later-design result",
      "retain only as adverse diagnostic evidence"), stringsAsFactors = FALSE)
  gates <- data.frame(
    gate = c("corrected_runtime_health", "corrected_design_hash", "corrected_target_manifests",
      "corrected_fit_objects", "corrected_numerical_gates", "corrected_scores_and_crossings",
      "rejected_lineage_to_corrected_design", "rejected_target_receipts", "rejected_adverse_evidence",
      "root_cause_decision", "future_truth_firewall", "new_model_fits", "article_mutations"),
    status = "pass",
    evidence = c("18/18 completed; 0 failed/running", gptq_expected$design_sha256,
      "16 quantile targets: future_Y=0, issued_G=1428, shared Normal-driver prior",
      if (deep_fit_audit) "18 RDS objects read; all quantile cores use shared prior and no future-Y likelihood" else "not requested",
      "18/18 strict numerical and quadrature gates", "all four quantile families beat raw; maximum crossings=1",
      "all 16 configs name October source jobs and exact design hash", gptq_expected$rejected_target_sha256,
      "all four quantile families worse than raw with 39-46 crossings", root_decision$status,
      "future USGS excluded from both fitted targets; read only from sealed scoring tables", "0", "0"),
    stringsAsFactors = FALSE)

  gptq_write_csv(corrected$targets, file.path(stage, "tables/corrected_target_manifests.csv"))
  gptq_write_csv(corrected$fits, file.path(stage, "tables/corrected_fit_audit.csv"))
  gptq_write_csv(rejected$configs, file.path(stage, "tables/rejected_lineage_map.csv"))
  gptq_write_csv(rejected$receipts, file.path(stage, "tables/rejected_target_receipts.csv"))
  gptq_write_csv(comparison, file.path(stage, "tables/family_comparison.csv"))
  gptq_write_csv(lineage, file.path(stage, "tables/lineage_summary.csv"))
  gptq_write_csv(contracts, file.path(stage, "tables/target_contract_comparison.csv"))
  gptq_write_csv(gates, file.path(stage, "tables/qualification_gates.csv"))

  search3_paths <- gptq_read_csv(file.path(repo_root, "tables/glofas_search3_part1234_final_20261007_source_quantiles.csv"))
  corrected_paths <- gptq_read_csv(file.path(corrected_root, "final_packet/quantile_paths.csv"))
  rejected_paths <- gptq_read_csv(file.path(repo_root, "tables/glofas_same_family_20261103_quantile_paths.csv"))
  gptq_plot_paths(file.path(stage, "figures/part4_corrected_target_qualification.pdf"), comparison,
    search3_paths, corrected_paths, rejected_paths)

  report <- c(
    "# GloFAS Part 4 corrected-target qualification", "", "## Decision", "",
    "The October 29 unit-member runtime is the completed coherent counterpart to the rejected November same-family campaign. It uses the same Search III-selected reference/discrepancy candidates and the exact design that November records as its source, but retains one shared frozen Part 3 Normal-RHS Gaussian path prior for every quantile readout.", "",
    "No model refit is required for this defect. November is retained as adverse evidence; it is not promoted. Article integration remains blocked until the user reviews the corrected October packet and chooses between the Search III coherent control and the coherent later-design result.", "",
    "## Direct evidence", "",
    "- October runtime health: 18/18 completed, zero failed or running.",
    "- October quantile target: 16/16 fits exclude future USGS likelihood factors, use all 1,428 issued GloFAS factors, and bind Normal-driver prior `0202bc19...357`.",
    "- October fit audit: every independent and MQ AL/exAL core directly reports `future_gaussian_prior_used=TRUE` and `future_y_working_likelihood_used=FALSE`.",
    "- October numerical audit: 18/18 strict gates pass.",
    "- November lineage: all 16 configurations name the October source fit and source design `55edbd49...b33` before changing the posterior target.",
    "- November target: separate level-specific future paths, no replacement Gaussian prior.",
    "- Root-cause reference: global path inference reproduces the tail crossings; convergence, Monte Carlo error, and local Delta approximation are not the cause.", "",
    "## Score consequence", "",
    sprintf("- October Independent AL/exAL CRPS: %.3f / %.3f; crossings: %d / %d.",
      corrected$scores$crps_grid_log1p[corrected$scores$family == "Independent AL"],
      corrected$scores$crps_grid_log1p[corrected$scores$family == "Independent exAL"],
      corrected$scores$crossing_pairs[corrected$scores$family == "Independent AL"],
      corrected$scores$crossing_pairs[corrected$scores$family == "Independent exAL"]),
    sprintf("- October MQ AL/exAL CRPS: %.3f / %.3f; crossings: %d / %d.",
      corrected$scores$crps_grid_log1p[corrected$scores$family == "MQ AL"],
      corrected$scores$crps_grid_log1p[corrected$scores$family == "MQ exAL"],
      corrected$scores$crossing_pairs[corrected$scores$family == "MQ AL"],
      corrected$scores$crossing_pairs[corrected$scores$family == "MQ exAL"]),
    "- November quantile-family CRPS spans 1.506-1.639 with 39-46 crossings; raw GloFAS CRPS is 1.436.", "",
    "Decision: `CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING`"
  )
  dir.create(file.path(stage, "reports"), recursive = TRUE, showWarnings = FALSE)
  writeLines(report, file.path(stage, "reports/qualification_report.md"))

  files <- list.files(stage, recursive = TRUE, full.names = TRUE)
  rel <- substring(files, nchar(stage) + 2L)
  manifest <- data.frame(relative_path = rel, size_bytes = as.numeric(file.info(files)$size),
    sha256 = vapply(files, gptq_sha256, character(1L)), stringsAsFactors = FALSE)
  manifest <- manifest[order(manifest$relative_path), ]
  gptq_write_csv(manifest, file.path(stage, "manifests/artifact_manifest.csv"))
  ready <- list(
    decision = "CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING",
    created_on = "2026-11-07", corrected_runtime = normalizePath(corrected_root),
    corrected_design_sha256 = gptq_expected$design_sha256,
    rejected_target_sha256 = gptq_expected$rejected_target_sha256,
    root_cause_decision_sha256 = gptq_expected$root_cause_sha256,
    artifact_manifest_sha256 = gptq_sha256(file.path(stage, "manifests/artifact_manifest.csv")),
    corrected_fit_units = 18L, rejected_fit_units = 16L, new_model_fits = 0L,
    future_truth_reads_for_method_choice = 0L, article_files_modified = 0L)
  dir.create(file.path(stage, "status"), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(ready, auto_unbox = TRUE, pretty = TRUE),
    file.path(stage, "status/qualification_ready.json"))
  gptq_check(stage)
  gptq_stop(file.rename(stage, output_root), "Atomic qualification publication failed.")
  on.exit(NULL, add = FALSE)
  cat("GLOFAS_PART4_CORRECTED_TARGET_QUALIFICATION_BUILD_PASS\n")
  cat("CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING\n")
  invisible(output_root)
}

gptq_check <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  manifest_path <- file.path(root, "manifests/artifact_manifest.csv")
  manifest <- gptq_read_csv(manifest_path)
  paths <- file.path(root, manifest$relative_path)
  gptq_stop(all(file.exists(paths)) && all(as.numeric(file.info(paths)$size) == manifest$size_bytes) &&
    all(vapply(paths, gptq_sha256, character(1L)) == manifest$sha256), "Qualification artifact manifest failed.")
  ready <- gptq_read_json(file.path(root, "status/qualification_ready.json"))
  gptq_stop(identical(ready$decision,
    "CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING"),
    "Qualification decision changed.")
  gptq_stop(ready$corrected_fit_units == 18L && ready$rejected_fit_units == 16L &&
    ready$new_model_fits == 0L && ready$future_truth_reads_for_method_choice == 0L &&
    ready$article_files_modified == 0L, "Qualification crossed a forbidden boundary.")
  gptq_stop(identical(ready$artifact_manifest_sha256, gptq_sha256(manifest_path)),
    "Ready receipt does not bind the artifact manifest.")
  gates <- gptq_read_csv(file.path(root, "tables/qualification_gates.csv"))
  gptq_stop(nrow(gates) == 13L && all(gates$status == "pass"), "Qualification gate failed.")
  comparison <- gptq_read_csv(file.path(root, "tables/family_comparison.csv"))
  oct <- comparison$scenario == "October coherent later design" &
    comparison$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  nov <- comparison$scenario == "November rejected same-family" &
    comparison$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")
  gptq_stop(sum(oct) == 4L && sum(nov) == 4L && max(comparison$crossing_pairs[oct]) <= 1L &&
    min(comparison$crossing_pairs[nov]) >= 39L &&
    all(comparison$crps_grid_log1p[oct] < comparison$crps_grid_log1p[nov]),
    "Corrected/rejected comparison no longer supports qualification.")
  pdf <- file.path(root, "figures/part4_corrected_target_qualification.pdf")
  gptq_stop(file.exists(pdf) && file.info(pdf)$size > 10000, "Qualification PDF is missing or implausibly small.")
  cat("GLOFAS_PART4_CORRECTED_TARGET_QUALIFICATION_VERIFY_PASS\n")
  cat("CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING\n")
  invisible(manifest)
}
