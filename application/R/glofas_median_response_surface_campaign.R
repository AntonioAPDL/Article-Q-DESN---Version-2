# Deterministic response-surface campaign for the GloFAS constrained p50 screen.

app_glofas_median_campaign_key <- function(alpha, rho, warm_start_policy = "auto") {
  paste(
    formatC(as.numeric(alpha), digits = 15L, format = "fg", flag = "#"),
    formatC(as.numeric(rho), digits = 15L, format = "fg", flag = "#"),
    as.character(warm_start_policy),
    sep = "\r"
  )
}

app_glofas_median_campaign_maximin_pairs <- function(
  alpha_values,
  rho_values,
  anchor_alpha,
  anchor_rho,
  n_select = 12L
) {
  alpha_values <- sort(unique(as.numeric(alpha_values)))
  rho_values <- sort(unique(as.numeric(rho_values)))
  n_select <- as.integer(n_select)
  if (!length(alpha_values) || !length(rho_values) || n_select < 1L) {
    stop("Maximin alpha/rho design requires nonempty support and a positive size.", call. = FALSE)
  }
  pool <- expand.grid(
    alpha = alpha_values,
    rho = rho_values,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  profile <- rbind(
    data.frame(alpha = alpha_values, rho = anchor_rho),
    data.frame(alpha = anchor_alpha, rho = rho_values)
  )
  profile_key <- app_glofas_median_campaign_key(profile$alpha, profile$rho)
  pool_key <- app_glofas_median_campaign_key(pool$alpha, pool$rho)
  pool <- pool[!pool_key %in% profile_key, , drop = FALSE]
  if (nrow(pool) < n_select) stop("Requested maximin design exceeds the available alpha/rho pool.", call. = FALSE)

  all_alpha <- log10(c(alpha_values, pool$alpha, profile$alpha))
  all_rho <- c(rho_values, pool$rho, profile$rho)
  alpha_range <- range(all_alpha)
  rho_range <- range(all_rho)
  transform <- function(x) {
    data.frame(
      alpha = if (diff(alpha_range) > 0) (log10(x$alpha) - alpha_range[[1L]]) / diff(alpha_range) else 0,
      rho = if (diff(rho_range) > 0) (x$rho - rho_range[[1L]]) / diff(rho_range) else 0
    )
  }
  pool_xy <- transform(pool)
  reference_xy <- transform(data.frame(alpha = anchor_alpha, rho = anchor_rho))
  selected <- integer()
  available <- seq_len(nrow(pool))
  for (i in seq_len(n_select)) {
    comparison <- if (length(selected)) rbind(reference_xy, pool_xy[selected, , drop = FALSE]) else reference_xy
    minimum_distance <- vapply(available, function(j) {
      sqrt(min((comparison$alpha - pool_xy$alpha[[j]])^2 + (comparison$rho - pool_xy$rho[[j]])^2))
    }, numeric(1L))
    best_distance <- max(minimum_distance)
    tied <- available[abs(minimum_distance - best_distance) <= 1e-14]
    tie_order <- order(pool$alpha[tied], pool$rho[tied])
    chosen <- tied[tie_order[[1L]]]
    selected <- c(selected, chosen)
    available <- setdiff(available, chosen)
  }
  out <- pool[selected, , drop = FALSE]
  out$selection_order <- seq_len(nrow(out))
  rownames(out) <- NULL
  out
}

app_glofas_median_campaign_verify_file <- function(path, expected_sha256, label) {
  resolved <- app_resolve_path(path, must_work = TRUE)
  actual <- tolower(app_sha256_file(resolved))
  expected <- tolower(as.character(expected_sha256 %||% ""))
  if (!nzchar(expected) || !identical(actual, expected)) {
    stop(sprintf("%s failed its SHA-256 contract.", label), call. = FALSE)
  }
  resolved
}

app_glofas_median_campaign_verify_anchor <- function(campaign) {
  anchor <- campaign$campaign$anchor %||% list()
  required <- c(
    "candidate_id", "ranking_path", "ranking_sha256", "config_path",
    "config_sha256", "fit_object_path", "fit_object_sha256"
  )
  missing <- required[!vapply(required, function(name) {
    value <- anchor[[name]]
    !is.null(value) && length(value) == 1L && nzchar(as.character(value))
  }, logical(1L))]
  if (length(missing)) {
    stop(sprintf("Campaign anchor is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  }
  ranking_path <- app_glofas_median_campaign_verify_file(
    anchor$ranking_path, anchor$ranking_sha256, "Stage-A ranking"
  )
  config_path <- app_glofas_median_campaign_verify_file(
    anchor$config_path, anchor$config_sha256, "Stage-A anchor config"
  )
  fit_path <- app_glofas_median_campaign_verify_file(
    anchor$fit_object_path, anchor$fit_object_sha256, "Stage-A anchor fit"
  )
  ranking <- app_read_csv(ranking_path)
  if (!all(c("candidate_id", "screen_rank") %in% names(ranking)) || !nrow(ranking)) {
    stop("Stage-A ranking is empty or lacks candidate_id/screen_rank.", call. = FALSE)
  }
  ranking <- ranking[order(as.integer(ranking$screen_rank), ranking$candidate_id), , drop = FALSE]
  candidate_id <- as.character(anchor$candidate_id)
  if (!identical(as.character(ranking$candidate_id[[1L]]), candidate_id)) {
    stop("The declared campaign anchor is not rank 1 in the frozen Stage-A ranking.", call. = FALSE)
  }
  list(
    candidate_id = candidate_id,
    ranking_path = ranking_path,
    config_path = config_path,
    fit_object_path = fit_path,
    ranking_row = ranking[1L, , drop = FALSE]
  )
}

app_glofas_median_campaign_candidate <- function(
  set_id,
  label,
  role,
  alpha_reference,
  alpha_discrepancy = alpha_reference,
  rho_reference,
  rho_discrepancy = rho_reference,
  tau_reference,
  tau_discrepancy,
  anchor,
  warm_start_policy = "auto",
  require_linked_desn = TRUE
) {
  warm_start_policy <- match.arg(warm_start_policy, c("auto", "cold"))
  metadata <- list(
    candidate_role = as.character(role),
    warm_start_policy = warm_start_policy,
    require_linked_desn = isTRUE(require_linked_desn),
    source_candidate_id = as.character(anchor$candidate_id)
  )
  if (identical(warm_start_policy, "auto")) {
    metadata$warm_start_source_fit_object <- anchor$fit_object_path
    metadata$warm_start_source_config <- anchor$config_path
  }
  list(
    set_id = as.character(set_id),
    candidate_label = as.character(label),
    parameters = list(
      reference = list(alpha = alpha_reference, rho = rho_reference, rhs_tau0 = tau_reference),
      discrepancy = list(alpha = alpha_discrepancy, rho = rho_discrepancy, rhs_tau0 = tau_discrepancy)
    ),
    metadata = metadata
  )
}

app_glofas_median_campaign_focused_candidates <- function(campaign, anchor) {
  entries <- campaign$campaign$focused_candidates %||% list()
  if (!length(entries)) {
    stop("Focused campaign requires at least one explicit candidate.", call. = FALSE)
  }
  required <- c(
    "set_id", "label", "role", "alpha_reference", "alpha_discrepancy",
    "rho_reference", "rho_discrepancy", "tau0_reference", "tau0_discrepancy",
    "warm_start_policy", "require_linked_desn"
  )
  candidates <- lapply(seq_along(entries), function(i) {
    entry <- entries[[i]]
    missing <- required[!vapply(required, function(name) {
      value <- entry[[name]]
      !is.null(value) && length(value) == 1L && !is.na(value[[1L]]) &&
        nzchar(as.character(value[[1L]]))
    }, logical(1L))]
    if (length(missing)) {
      stop(sprintf(
        "Focused candidate %d is missing: %s.",
        i, paste(missing, collapse = ", ")
      ), call. = FALSE)
    }
    numeric_values <- vapply(c(
      "alpha_reference", "alpha_discrepancy", "rho_reference",
      "rho_discrepancy", "tau0_reference", "tau0_discrepancy"
    ), function(name) as.numeric(entry[[name]]), numeric(1L))
    if (any(!is.finite(numeric_values)) ||
        any(numeric_values[c("alpha_reference", "alpha_discrepancy")] <= 0) ||
        any(numeric_values[c("alpha_reference", "alpha_discrepancy")] > 1) ||
        any(numeric_values[c("rho_reference", "rho_discrepancy")] <= 0) ||
        any(numeric_values[c("tau0_reference", "tau0_discrepancy")] <= 0)) {
      stop(sprintf("Focused candidate %d has invalid alpha, rho, or tau0 values.", i), call. = FALSE)
    }
    linked <- app_as_bool(entry$require_linked_desn)
    if (linked && (!isTRUE(all.equal(
      numeric_values[["alpha_reference"]], numeric_values[["alpha_discrepancy"]], tolerance = 0
    )) || !isTRUE(all.equal(
      numeric_values[["rho_reference"]], numeric_values[["rho_discrepancy"]], tolerance = 0
    )))) {
      stop(sprintf("Focused candidate %d declares linked DESNs but uses different dynamics.", i), call. = FALSE)
    }
    app_glofas_median_campaign_candidate(
      set_id = entry$set_id,
      label = entry$label,
      role = entry$role,
      alpha_reference = numeric_values[["alpha_reference"]],
      alpha_discrepancy = numeric_values[["alpha_discrepancy"]],
      rho_reference = numeric_values[["rho_reference"]],
      rho_discrepancy = numeric_values[["rho_discrepancy"]],
      tau_reference = numeric_values[["tau0_reference"]],
      tau_discrepancy = numeric_values[["tau0_discrepancy"]],
      anchor = anchor,
      warm_start_policy = as.character(entry$warm_start_policy),
      require_linked_desn = linked
    )
  })
  labels <- vapply(candidates, function(x) x$candidate_label, character(1L))
  if (anyDuplicated(labels)) stop("Focused candidate labels must be unique.", call. = FALSE)
  treatment_key <- vapply(candidates, function(x) {
    p <- x$parameters
    paste(
      formatC(c(
        p$reference$alpha, p$discrepancy$alpha,
        p$reference$rho, p$discrepancy$rho,
        p$reference$rhs_tau0, p$discrepancy$rhs_tau0
      ), digits = 15L, format = "fg", flag = "#"),
      x$metadata$warm_start_policy,
      sep = "\r",
      collapse = "\r"
    )
  }, character(1L))
  if (anyDuplicated(treatment_key)) {
    stop("Focused candidates contain duplicate scientific/initialization treatments.", call. = FALSE)
  }
  candidates
}

app_glofas_median_campaign_candidates <- function(campaign, anchor) {
  if (length(campaign$campaign$focused_candidates %||% list())) {
    return(app_glofas_median_campaign_focused_candidates(campaign, anchor))
  }
  design <- campaign$campaign$design %||% list()
  support <- campaign$campaign$support %||% list()
  anchor_alpha <- as.numeric(design$anchor_alpha %||% NA_real_)
  anchor_rho <- as.numeric(design$anchor_rho %||% NA_real_)
  anchor_tau_reference <- as.numeric(design$anchor_tau0_reference %||% NA_real_)
  anchor_tau_discrepancy <- as.numeric(design$anchor_tau0_discrepancy %||% NA_real_)
  alpha_values <- as.numeric(unlist(support$alpha, use.names = FALSE))
  rho_values <- as.numeric(unlist(support$rho, use.names = FALSE))
  interaction_count <- as.integer(design$interaction_count %||% 12L)
  tau_pairs <- campaign$campaign$tau_sentinels %||% list()
  block_pairs <- campaign$campaign$block_specific_alpha_pairs %||% list()

  add <- function(...) {
    candidates[[length(candidates) + 1L]] <<- app_glofas_median_campaign_candidate(...)
  }
  candidates <- list()

  add(
    "canary_warm_anchor", "warm_anchor", "repeatability_canary", anchor_alpha,
    rho_reference = anchor_rho, tau_reference = anchor_tau_reference,
    tau_discrepancy = anchor_tau_discrepancy, anchor = anchor
  )
  add(
    "canary_cold_anchor", "cold_anchor", "repeatability_canary", anchor_alpha,
    rho_reference = anchor_rho, tau_reference = anchor_tau_reference,
    tau_discrepancy = anchor_tau_discrepancy, anchor = anchor,
    warm_start_policy = "cold"
  )
  add(
    "canary_warm_alpha015", "warm_alpha_0p15", "coordinate_transfer_canary", 0.15,
    rho_reference = anchor_rho, tau_reference = anchor_tau_reference,
    tau_discrepancy = anchor_tau_discrepancy, anchor = anchor
  )
  add(
    "canary_cold_alpha015", "cold_alpha_0p15", "coordinate_transfer_canary", 0.15,
    rho_reference = anchor_rho, tau_reference = anchor_tau_reference,
    tau_discrepancy = anchor_tau_discrepancy, anchor = anchor,
    warm_start_policy = "cold"
  )

  for (value in alpha_values) {
    add(
      "linked_alpha_profile", sprintf("linked_alpha_%s", format(value, scientific = FALSE)),
      "linked_alpha_profile", value, rho_reference = anchor_rho,
      tau_reference = anchor_tau_reference, tau_discrepancy = anchor_tau_discrepancy,
      anchor = anchor
    )
  }
  for (value in rho_values) {
    add(
      "linked_rho_profile", sprintf("linked_rho_%s", format(value, scientific = FALSE)),
      "linked_rho_profile", anchor_alpha, rho_reference = value,
      tau_reference = anchor_tau_reference, tau_discrepancy = anchor_tau_discrepancy,
      anchor = anchor
    )
  }

  interactions <- app_glofas_median_campaign_maximin_pairs(
    alpha_values, rho_values, anchor_alpha, anchor_rho, interaction_count
  )
  for (i in seq_len(nrow(interactions))) {
    add(
      "linked_alpha_rho_maximin",
      sprintf("interaction_%02d", i),
      "linked_alpha_rho_interaction",
      interactions$alpha[[i]], rho_reference = interactions$rho[[i]],
      tau_reference = anchor_tau_reference, tau_discrepancy = anchor_tau_discrepancy,
      anchor = anchor
    )
  }

  for (i in seq_along(tau_pairs)) {
    pair <- tau_pairs[[i]]
    add(
      "tau0_sentinel", sprintf("tau0_sentinel_%02d", i), "tau0_sentinel",
      anchor_alpha, rho_reference = anchor_rho,
      tau_reference = as.numeric(pair$reference),
      tau_discrepancy = as.numeric(pair$discrepancy), anchor = anchor
    )
  }

  for (i in seq_along(block_pairs)) {
    pair <- block_pairs[[i]]
    alpha_reference <- as.numeric(pair$reference)
    alpha_discrepancy <- as.numeric(pair$discrepancy)
    add(
      "block_specific_alpha", sprintf("block_alpha_%02d", i), "block_specific_alpha",
      alpha_reference, alpha_discrepancy = alpha_discrepancy,
      rho_reference = anchor_rho, rho_discrepancy = anchor_rho,
      tau_reference = anchor_tau_reference, tau_discrepancy = anchor_tau_discrepancy,
      anchor = anchor,
      require_linked_desn = isTRUE(all.equal(alpha_reference, alpha_discrepancy, tolerance = 0))
    )
  }
  candidates
}

app_glofas_median_campaign_space <- function(campaign, anchor = NULL) {
  if (is.character(campaign) && length(campaign) == 1L) {
    campaign <- app_read_yaml(app_resolve_path(campaign, must_work = TRUE))
  }
  campaign <- app_glofas_median_screen_normalize_yaml_keys(campaign)
  if (is.null(anchor)) anchor <- app_glofas_median_campaign_verify_anchor(campaign)
  inference <- campaign$fixed$inference %||% list()
  if (as.integer(inference$max_iter %||% NA_integer_) != 150L ||
      as.integer(inference$max_iter_hard_cap %||% NA_integer_) != 150L) {
    stop("The authorized response-surface campaign requires max_iter=max_iter_hard_cap=150.", call. = FALSE)
  }
  scheduler <- campaign$scheduler %||% list()
  cores <- as.integer(unlist(scheduler$cores %||% integer(), use.names = FALSE))
  if (as.integer(scheduler$max_parallel %||% NA_integer_) != 20L ||
      length(cores) != 20L || anyDuplicated(cores)) {
    stop("The authorized response-surface campaign requires 20 unique one-worker cores.", call. = FALSE)
  }
  space <- campaign
  space$version <- "2.0"
  space$campaign <- NULL
  space$explicit_candidates <- app_glofas_median_campaign_candidates(campaign, anchor)
  space$candidate_sets <- list()
  space$linked_factorial <- NULL
  manifest <- app_glofas_median_screen_candidate_manifest(space)
  expected <- as.integer((space$execution %||% list())$expected_candidates %||% NA_integer_)
  if (!is.finite(expected) || nrow(manifest) != expected) {
    stop(sprintf("Campaign cardinality is %d, not the declared %s.", nrow(manifest), expected), call. = FALSE)
  }
  space
}
