# Diagnostic-only metadata reconciliation of selected and executed GloFAS DESNs.
# These functions never read files, generate weights, build features, fit models,
# inspect forecast losses, or grant permission to change a frozen model.

app_gsr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS specification reconciliation: ", why), call. = FALSE)
  invisible(TRUE)
}

app_gsr_number <- function(x, name, integer = FALSE, lower = 0, strict = FALSE) {
  out <- suppressWarnings(as.numeric(as.character(x)))
  app_gsr_require(length(out) == 1L && is.finite(out) &&
    (if (strict) out > lower else out >= lower) && (!integer || out == floor(out)),
    paste0("one finite admissible ", name, " required"))
  out
}

app_gsr_boolean <- function(x, name) {
  text <- tolower(as.character(x))
  app_gsr_require(length(text) == 1L && !is.na(text) && text %in% c("true", "false"),
    paste0("explicit Boolean ", name, " required"))
  text == "true"
}

app_gsr_decision <- function(record, policy) {
  q <- app_gsr_require
  keys <- c("schema_version", "decision_id", "authority", "instruction_reference", "policy", "scope",
    "allow_model_runs", "allow_scoring", "allow_article_changes")
  q(is.character(policy) && length(policy) == 1L && !is.na(policy) &&
    policy %in% c("preserve_executed", "restore_screened"), "explicit unambiguous specification policy required")
  q(is.list(record) && length(record) == length(keys) && !anyDuplicated(names(record)) &&
    setequal(names(record), keys) && identical(record$schema_version, "glofas_specification_decision_v1") &&
    identical(record$authority, "explicit_author_instruction") && identical(record$policy, policy) &&
    identical(record$scope, "specification_reconciliation_and_preflight_only") &&
    all(vapply(record[c("decision_id", "instruction_reference")], function(x)
      is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)), logical(1L))) &&
    all(vapply(record[c("allow_model_runs", "allow_scoring", "allow_article_changes")], identical,
      logical(1L), FALSE)), "exact explicit author decision and no-run scope required")
  record
}

app_gsr_components <- function(x) {
  q <- app_gsr_require
  q(is.data.frame(x) && nrow(x) == 2L && !anyDuplicated(names(x)), "exact two-row unique-field specification required")
  available <- intersect(c("component", "target", "role"), names(x))
  q(length(available) > 0L, "explicit component labels required")
  normalize <- function(value) {
    value <- as.character(value)
    value[value == "reference_anchor"] <- "reference"
    value[value == "discrepancy_anchor"] <- "discrepancy"
    q(all(!is.na(value) & value %in% c("reference", "discrepancy")), "unknown or ambiguous component labels")
    value
  }
  comp <- normalize(x[[available[1L]]])
  for (field in available[-1L]) q(identical(comp, normalize(x[[field]])), "conflicting component aliases")
  q(!anyDuplicated(comp) && setequal(comp, c("reference", "discrepancy")), "duplicate or missing component")
  x$component <- comp
  x[match(c("reference", "discrepancy"), comp), , drop = FALSE]
}

app_gsr_specification <- function(x, screened) {
  q <- app_gsr_require; x <- app_gsr_components(x)
  required <- c("candidate_id", "n_vector", "m", "output_lag_max", "covariate_lag_max", "washout",
    "alpha", "rho", "pi_w", "pi_in", "win_scale_global", "win_scale_bias", "standardize_inputs",
    "state_scaling", "input_bound", "act_f", "act_k")
  if (screened) required <- c(required, "canonical_seed", "D", "input_dimension", "effective_input_gain")
  else required <- c(required, "seed")
  q(all(required %in% names(x)), paste0("missing ", if (screened) "screened" else "executed", " specification field"))
  rows <- lapply(seq_len(nrow(x)), function(i) {
    r <- x[i, , drop = FALSE]
    widths <- as.character(r$n_vector)
    q(length(widths) == 1L && !is.na(widths) && grepl("^[1-9][0-9]*(;[1-9][0-9]*)*$", widths),
      "unambiguous positive layer widths required")
    n <- as.numeric(strsplit(widths, ";", fixed = TRUE)[[1L]])
    # Both frozen Search III components are one layer. General multilayer
    # reconciliation additionally needs a reducer specification, not a guess.
    q(length(n) == 1L, "this frozen reconciliation requires explicit one-layer DESNs")
    if ("D" %in% names(r)) q(app_gsr_number(r$D, "depth", TRUE, 0, TRUE) == length(n), "depth and layer widths disagree")
    if ("n_state_features" %in% names(r)) q(app_gsr_number(r$n_state_features,
      "state dimension", TRUE, 0, TRUE) == sum(n), "state dimension and widths disagree")
    seed <- if (screened) r$canonical_seed else r$seed
    if (all(c("seed", "canonical_seed") %in% names(r)))
      q(app_gsr_number(r$seed, "seed", TRUE, 0, TRUE) ==
        app_gsr_number(r$canonical_seed, "canonical seed", TRUE, 0, TRUE), "conflicting seed aliases")
    m <- app_gsr_number(r$m, "response lag count", TRUE, 0, TRUE)
    ylag <- app_gsr_number(r$output_lag_max, "response lag maximum", TRUE, 0, TRUE)
    zlag <- app_gsr_number(r$covariate_lag_max, "covariate lag maximum", TRUE)
    dimension <- ylag + 2 * (zlag + 1)
    q(m == ylag, "response lag count differs from frozen contiguous-lag convention")
    if ("input_dimension" %in% names(r)) q(app_gsr_number(r$input_dimension,
      "input dimension", TRUE, 0, TRUE) == dimension, "input dimension disagrees with lag specification")
    alpha <- app_gsr_number(r$alpha, "leak", lower = 0, strict = TRUE)
    rho <- app_gsr_number(r$rho, "spectral target", lower = 0, strict = TRUE)
    pi_w <- app_gsr_number(r$pi_w, "recurrent sparsity", lower = 0, strict = TRUE)
    pi_in <- app_gsr_number(r$pi_in, "input sparsity", lower = 0, strict = TRUE)
    q(alpha < 1 && rho < 1 && pi_w <= 1 && pi_in <= 1, "invalid dynamic/sparsity parameter")
    candidate <- as.character(r$candidate_id)
    state_scaling <- as.character(r$state_scaling); input_bound <- as.character(r$input_bound)
    act_f <- as.character(r$act_f); act_k <- as.character(r$act_k)
    q(length(candidate) == 1L && !is.na(candidate) && nzchar(candidate) &&
      state_scaling %in% c("none", "train_zscore") && input_bound %in% c("none", "tanh") &&
      act_f %in% c("tanh", "relu", "identity") && act_k %in% c("tanh", "relu", "identity"),
      "explicit supported feature transformations required")
    data.frame(component = r$component, candidate_id = candidate, D = length(n), n_vector = widths,
      n_state_features = sum(n), m = m, output_lag_max = ylag, covariate_lag_max = zlag,
      input_dimension = dimension, washout = app_gsr_number(r$washout, "washout", TRUE),
      alpha = alpha, rho = rho, seed = app_gsr_number(seed, "seed", TRUE, 0, TRUE),
      pi_w = pi_w, pi_in = pi_in, standardize_inputs = app_gsr_boolean(r$standardize_inputs, "input standardization"),
      state_scaling = state_scaling, input_bound = input_bound, act_f = act_f, act_k = act_k,
      win_scale_global = app_gsr_number(r$win_scale_global, "input multiplier", lower = 0, strict = TRUE),
      win_scale_bias = app_gsr_number(r$win_scale_bias, "bias multiplier", lower = 0, strict = TRUE),
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows); rownames(out) <- NULL; out
}

app_gsr_compare_fields <- function(a, b, fields) {
  do.call(rbind, lapply(seq_len(nrow(a)), function(i) do.call(rbind, lapply(fields, function(field) {
    x <- a[[field]][i]; y <- b[[field]][i]
    pass <- if (is.numeric(x) && is.numeric(y)) abs(x - y) <= 1e-12 * max(1, abs(x), abs(y)) else identical(x, y)
    data.frame(component = a$component[i], field = field, screened_value = as.character(x),
      executed_value = as.character(y), pass = pass, stringsAsFactors = FALSE)
  }))))
}

app_glofas_reconcile_specification <- function(selected, executed, policy, decision_record) {
  q <- app_gsr_require
  decision <- app_gsr_decision(decision_record, policy)
  raw_selected <- app_gsr_components(selected)
  screened <- app_gsr_specification(raw_selected, TRUE)
  applied <- app_gsr_specification(executed, FALSE)
  shared <- setdiff(names(screened), c("win_scale_global", "win_scale_bias"))
  checks <- app_gsr_compare_fields(screened, applied, shared)
  q(all(checks$pass), "screened/executed shared feature specifications disagree")
  gain <- vapply(seq_len(2L), function(i) app_gsr_number(raw_selected$effective_input_gain[i],
    "selected effective input gain", lower = 0, strict = TRUE), numeric(1L))
  expected <- gain / sqrt(screened$pi_in * screened$input_dimension)
  q(all(abs(screened$win_scale_global - expected) <= 1e-12) &&
    all(abs(screened$win_scale_bias - expected) <= 1e-12), "selected gain normalization does not reproduce")
  q(all(abs(applied$win_scale_global - gain) <= 1e-12) && all(applied$win_scale_bias == 1),
    "executed declaration does not match frozen raw-gain/bias-one convention")
  gains <- data.frame(component = screened$component, candidate_id = screened$candidate_id,
    input_dimension = screened$input_dimension, pi_in = screened$pi_in, effective_input_gain = gain,
    expected_screened_scale = expected, screened_global = screened$win_scale_global,
    screened_bias = screened$win_scale_bias, executed_global = applied$win_scale_global,
    executed_bias = applied$win_scale_bias, global_multiplier_ratio = applied$win_scale_global / screened$win_scale_global,
    bias_multiplier_ratio = applied$win_scale_bias / screened$win_scale_bias, stringsAsFactors = FALSE)
  basis <- if (policy == "preserve_executed") "executed_frozen_v1" else "screened_normalized_v1"
  list(schema_version = "glofas_specification_reconciliation_v1", status = "RECONCILED_NOT_A_MODEL_CHANGE",
    policy = policy, specification_basis = basis, decision = decision,
    screened_specification = screened, executed_specification = applied,
    authorized_specification = if (policy == "preserve_executed") applied else screened,
    shared_feature_checks = checks, gain_comparison = gains,
    screened_and_executed_feature_maps_identical = FALSE,
    can_reuse_executed_numeric_design = policy == "preserve_executed",
    selected_registry_is_execution_identity = FALSE, original_RDS_reads = 0L,
    model_runs = 0L, weights_generated = 0L, parameters_changed = 0L,
    forecast_losses_used_for_decision = FALSE, future_USGS_accessed = FALSE,
    allow_model_runs = FALSE, allow_scoring = FALSE, allow_article_changes = FALSE)
}

app_glofas_bind_executed_replay <- function(reconciliation, replay) {
  q <- app_gsr_require
  q(is.list(reconciliation) && identical(reconciliation$schema_version, "glofas_specification_reconciliation_v1") &&
    is.list(replay) && identical(replay$status, "PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY") &&
    isTRUE(replay$context_unchanged) && isTRUE(replay$RNG_unchanged) && replay$forbidden_calls == 0 &&
    replay$saved_callback_calls == 0 && replay$applied_updates == 0 &&
    identical(replay$future_truth_read, FALSE), "passed truth-free unchanged numeric replay required")
  identity <- replay$actual_context_identity
  q(is.list(identity) && is.list(identity$blocks) && setequal(names(identity$blocks), c("beta", "alpha")),
    "exact two-block numeric identity required")
  hash <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9a-f]{64}$", x)
  q(all(vapply(identity[c("context_sha256", "covariate_timeline_sha256", "issued_member_rows_sha256")],
    hash, logical(1L))), "complete context/covariate/member fingerprints required")
  rows <- list(); fingerprints <- list()
  hash_fields <- c("W_sha256", "Win_sha256", "reducers_sha256", "last_states_sha256", "input_spec_sha256",
    "feature_metadata_sha256", "config_sha256", "scaler_sha256", "historical_values_sha256")
  for (i in seq_len(2L)) {
    block <- c("beta", "alpha")[i]; b <- identity$blocks[[block]]
    r <- reconciliation$executed_specification[i, , drop = FALSE]; meta <- b$actual_meta
    q(is.list(b) && all(hash_fields %in% names(b)) && all(vapply(b[hash_fields], hash, logical(1L))) &&
      b$depth == 1 && identical(as.numeric(unlist(b$layer_widths)), as.numeric(r$n_state_features)) &&
      b$input_dimension == r$input_dimension && identical(b$history_last_date, "2022-12-25") &&
      b$history_length == 12995, "numeric replay dimensions/date/fingerprints disagree")
    values <- list(win_scale_global = r$win_scale_global, win_scale_bias = r$win_scale_bias,
      standardize_inputs = r$standardize_inputs, input_bound = r$input_bound,
      alpha = r$alpha, act_f = r$act_f, act_k = r$act_k)
    for (field in names(values)) {
      a <- meta[[field]]; expected <- values[[field]]
      pass <- if (is.numeric(a) && is.numeric(expected)) length(a) == 1L &&
        is.finite(a) && abs(a - expected) <= 1e-12 else identical(a, expected)
      q(pass, paste0("numeric replay actual ", field, " differs from executed declaration"))
      rows[[length(rows) + 1L]] <- data.frame(component = r$component, field = field,
        expected = as.character(expected), actual = as.character(a), pass = TRUE, stringsAsFactors = FALSE)
    }
    fingerprints[[block]] <- b[c("history_last_date", "history_length", hash_fields)]
  }
  reconciliation$replay_checks <- do.call(rbind, rows)
  reconciliation$frozen_numeric_identity <- c(identity[c("context_sha256", "covariate_timeline_sha256",
    "issued_member_rows_sha256")], list(blocks = fingerprints))
  reconciliation$executed_numeric_replay_bound <- TRUE
  reconciliation
}

app_glofas_assert_specification_basis <- function(proposed, reconciliation, policy, basis, frozen_identity) {
  q <- app_gsr_require
  q(is.list(reconciliation) && identical(reconciliation$schema_version, "glofas_specification_reconciliation_v1") &&
    identical(policy, reconciliation$policy) && identical(basis, reconciliation$specification_basis),
    "explicit preparation policy/basis must match author decision")
  canonical <- app_gsr_specification(proposed, FALSE)
  expected <- reconciliation$authorized_specification
  checks <- app_gsr_compare_fields(expected, canonical, names(expected))
  q(all(checks$pass), "proposed preparation changes the explicitly authorized specification")
  if (policy == "preserve_executed") {
    q(isTRUE(reconciliation$executed_numeric_replay_bound) &&
      identical(frozen_identity, reconciliation$frozen_numeric_identity),
      "preserve-executed preparation requires the exact frozen numeric identity")
  } else q(is.null(frozen_identity), "restored-screened design cannot claim executed numeric identity or fit reuse")
  invisible(list(status = "SPECIFICATION_PREFLIGHT_PASS_NOT_RUN_AUTHORIZATION", policy = policy, basis = basis,
    allow_model_runs = FALSE, allow_scoring = FALSE, allow_article_changes = FALSE))
}
