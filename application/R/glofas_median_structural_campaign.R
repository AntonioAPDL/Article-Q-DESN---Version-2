# Deterministic structural campaign for the constrained GloFAS p50 screen.

app_glofas_median_structural_validate_block <- function(x, label) {
  allowed <- c("D", "n", "n_tilde", "m", "reservoir_lag_max", "direct_lag_max", "alpha", "rho", "tau0")
  unknown <- setdiff(names(x), allowed)
  if (length(unknown)) {
    stop(sprintf("%s contains unsupported fields: %s.", label, paste(unknown, collapse = ", ")), call. = FALSE)
  }
  required <- c("D", "n", "m", "direct_lag_max", "alpha", "rho", "tau0")
  missing <- required[!vapply(required, function(name) {
    value <- x[[name]]
    !is.null(value) && length(value) == 1L && !is.na(value[[1L]])
  }, logical(1L))]
  if (length(missing)) {
    stop(sprintf("%s is missing: %s.", label, paste(missing, collapse = ", ")), call. = FALSE)
  }

  D <- as.integer(x$D)
  n <- as.integer(x$n)
  m <- as.integer(x$m)
  reservoir_lag_max <- as.integer(x$reservoir_lag_max %||% m)
  direct_lag_max <- as.integer(x$direct_lag_max)
  if (!is.finite(D) || D < 1L || !is.finite(n) || n < 1L ||
      !is.finite(m) || m < 1L || !is.finite(reservoir_lag_max) ||
      reservoir_lag_max != m || !is.finite(direct_lag_max) ||
      direct_lag_max < 0L || direct_lag_max > m) {
    stop(sprintf(
      "%s requires positive D/n/m, reservoir_lag_max=m, and 0 <= direct_lag_max <= m.",
      label
    ), call. = FALSE)
  }
  n_tilde <- if (D == 1L) integer(0) else as.integer(x$n_tilde %||% n)
  if (D > 1L && (!is.finite(n_tilde) || n_tilde != n)) {
    stop(sprintf("%s requires n_tilde=n so no layer reduction is introduced.", label), call. = FALSE)
  }
  app_glofas_median_screen_validate_value(paste0(label, ".alpha"), x$alpha)
  app_glofas_median_screen_validate_value(paste0(label, ".rho"), x$rho)
  app_glofas_median_screen_validate_value(paste0(label, ".rhs_tau0"), x$tau0)

  out <- list(
    D = D,
    n = n,
    m = m,
    reservoir_output_lag_max = reservoir_lag_max,
    reservoir_covariate_lag_max = reservoir_lag_max,
    direct_output_lag_max = direct_lag_max,
    direct_covariate_lag_max = direct_lag_max,
    alpha = as.numeric(x$alpha),
    rho = as.numeric(x$rho),
    rhs_tau0 = as.numeric(x$tau0)
  )
  if (D > 1L) out$n_tilde <- n_tilde
  out
}

app_glofas_median_structural_candidate <- function(set, profile, center, anchor) {
  allowed_set <- c("set_id", "role", "profiles")
  unknown_set <- setdiff(names(set), allowed_set)
  if (length(unknown_set)) {
    stop(sprintf("Structural profile set contains unsupported fields: %s.", paste(unknown_set, collapse = ", ")), call. = FALSE)
  }
  allowed_profile <- c("label", "both", "reference", "discrepancy", "warm_start_policy")
  unknown_profile <- setdiff(names(profile), allowed_profile)
  if (length(unknown_profile)) {
    stop(sprintf("Structural profile contains unsupported fields: %s.", paste(unknown_profile, collapse = ", ")), call. = FALSE)
  }
  set_id <- as.character(set$set_id %||% "")
  role <- as.character(set$role %||% "")
  label <- as.character(profile$label %||% "")
  if (!nzchar(set_id) || grepl("[^A-Za-z0-9_.-]", set_id) || !nzchar(role) || !nzchar(label)) {
    stop("Structural profile sets require path-safe set_id plus nonempty role and label.", call. = FALSE)
  }
  warm_start_policy <- match.arg(
    tolower(as.character(profile$warm_start_policy %||% "auto")),
    c("auto", "cold")
  )
  both <- profile$both %||% list()
  reference <- app_qdesn_deep_merge(
    app_qdesn_deep_merge(center$reference %||% list(), both),
    profile$reference %||% list()
  )
  discrepancy <- app_qdesn_deep_merge(
    app_qdesn_deep_merge(center$discrepancy %||% list(), both),
    profile$discrepancy %||% list()
  )
  reference <- app_glofas_median_structural_validate_block(reference, "reference")
  discrepancy <- app_glofas_median_structural_validate_block(discrepancy, "discrepancy")
  metadata <- list(
    source_candidate_id = as.character(anchor$candidate_id),
    warm_start_policy = warm_start_policy,
    candidate_role = role,
    require_linked_desn = FALSE
  )
  if (identical(warm_start_policy, "auto")) {
    metadata$warm_start_source_fit_object <- anchor$fit_object_path
    metadata$warm_start_source_config <- anchor$config_path
  }
  list(
    set_id = set_id,
    candidate_label = label,
    parameters = list(reference = reference, discrepancy = discrepancy),
    metadata = metadata
  )
}

app_glofas_median_structural_candidates <- function(campaign, anchor) {
  center <- campaign$campaign$center %||% list()
  if (!is.list(center$reference) || !is.list(center$discrepancy)) {
    stop("Structural campaign center requires reference and discrepancy blocks.", call. = FALSE)
  }
  sets <- campaign$campaign$profile_sets %||% list()
  if (!length(sets)) stop("Structural campaign requires at least one profile set.", call. = FALSE)
  candidates <- list()
  for (i in seq_along(sets)) {
    profiles <- sets[[i]]$profiles %||% list()
    if (!length(profiles)) {
      stop(sprintf("Structural profile set %d has no profiles.", i), call. = FALSE)
    }
    for (profile in profiles) {
      candidates[[length(candidates) + 1L]] <- app_glofas_median_structural_candidate(
        sets[[i]], profile, center, anchor
      )
    }
  }
  labels <- vapply(candidates, function(x) x$candidate_label, character(1L))
  if (anyDuplicated(labels)) stop("Structural candidate labels must be unique.", call. = FALSE)
  candidates
}

app_glofas_median_structural_space <- function(campaign, anchor = NULL) {
  if (is.character(campaign) && length(campaign) == 1L) {
    campaign <- app_read_yaml(app_resolve_path(campaign, must_work = TRUE))
  }
  campaign <- app_glofas_median_screen_normalize_yaml_keys(campaign)
  if (is.null(anchor)) anchor <- app_glofas_median_campaign_verify_anchor(campaign)
  inference <- campaign$fixed$inference %||% list()
  if (as.integer(inference$max_iter %||% NA_integer_) != 150L ||
      as.integer(inference$max_iter_hard_cap %||% NA_integer_) != 150L) {
    stop("The authorized structural campaign requires max_iter=max_iter_hard_cap=150.", call. = FALSE)
  }
  scheduler <- campaign$scheduler %||% list()
  cores <- as.integer(unlist(scheduler$cores %||% integer(), use.names = FALSE))
  if (as.integer(scheduler$max_parallel %||% NA_integer_) != 20L ||
      length(cores) != 20L || anyDuplicated(cores)) {
    stop("The authorized structural campaign requires 20 unique one-worker cores.", call. = FALSE)
  }
  if (app_as_bool((campaign$contracts %||% list())$require_same_desn_by_default %||% TRUE)) {
    stop("Structural block-asymmetry screening requires require_same_desn_by_default=false.", call. = FALSE)
  }
  space <- campaign
  space$version <- "2.1"
  space$campaign <- NULL
  space$explicit_candidates <- app_glofas_median_structural_candidates(campaign, anchor)
  space$candidate_sets <- list()
  space$linked_factorial <- NULL
  manifest <- app_glofas_median_screen_candidate_manifest(space)
  expected <- as.integer((space$execution %||% list())$expected_candidates %||% NA_integer_)
  if (!is.finite(expected) || nrow(manifest) != expected) {
    stop(sprintf("Structural campaign cardinality is %d, not the declared %s.", nrow(manifest), expected), call. = FALSE)
  }
  space
}
