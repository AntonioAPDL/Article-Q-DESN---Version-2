# Pure, in-memory fitted-quantile functionals. No file reads or saved callbacks.
# Authentication/admission of real design and model reads belongs to the caller.
gfh_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS fitted history: ", why), call. = FALSE)
  invisible(TRUE)
}
gfh_tau <- function() c(.05, .20, .35, .50, .65, .80, .95)

gfh_reference_history <- function(design, days = 30L) {
  q <- gfh_require; origin <- as.Date("2022-12-25")
  q(is.numeric(days) && length(days) == 1L && is.finite(days) &&
    days == as.integer(days) && days >= 1L && days <= 30L, "one to thirty history dates required")
  q(is.list(design) && identical(design$future_truth_policy,
    "physically_excluded_from_fit_objects_scoring_sidecar_only") &&
    identical(design$ensemble_member_weight_policy, "unit_member_likelihood_v1") &&
    isTRUE(design$two_block_design), "truth-free unit-member two-block design required")
  X <- design$H_fixed; r <- design$row_info_fixed; b <- design$base_panel
  q(is.matrix(X) && is.numeric(X) && nrow(X) > 0L && ncol(X) > 1L &&
    is.character(colnames(X)) && !anyNA(colnames(X)) &&
    all(nzchar(colnames(X))) && !anyDuplicated(colnames(X)), "named historical design matrix required")
  columns <- colnames(X); source <- as.character(design$source_fixed)
  q(length(source) == nrow(X) && !anyNA(source) && setequal(unique(source), c("Y", "G")) &&
    is.data.frame(r) && nrow(r) == nrow(X) &&
    all(c("source", "row_role", "feature_row", "target_date", "is_future") %in% names(r)) &&
    identical(as.character(r$source), source) &&
    is.logical(r$is_future) && !anyNA(r$is_future) && !any(r$is_future), "historical source rows differ")
  rd <- as.Date(r$target_date)
  q(!anyNA(rd) && all(rd <= origin), "historical design contains a future or invalid date")
  q(is.data.frame(b) && "target_date" %in% names(b) && nrow(b) > 0L,
    "historical base-panel dates required")
  bd <- as.Date(b$target_date)
  q(!anyNA(bd) && !anyDuplicated(bd) && all(bd <= origin), "base-panel dates must be unique and pre-origin")
  yi <- which(source == "Y"); gi <- which(source == "G")
  f <- r$feature_row
  q(is.numeric(f) && !anyNA(f) && all(is.finite(f)) && all(f == as.integer(f)) &&
    length(yi) == nrow(b) && length(gi) == nrow(b) &&
    identical(sort(as.integer(f[yi])), seq_len(nrow(b))) &&
    identical(sort(as.integer(f[gi])), seq_len(nrow(b))) &&
    all(rd == bd[f]) && all(r$row_role[yi] == "historical_usgs") &&
    all(r$row_role[gi] == "historical_glofas_retrospective"), "feature-row/date/source alignment differs")
  beta <- design$beta_index; alpha <- design$alpha_index
  valid_index <- function(v) is.numeric(v) && length(v) > 0L && !anyNA(v) &&
    all(is.finite(v)) && all(v == as.integer(v)) && !anyDuplicated(v)
  q(valid_index(beta) && valid_index(alpha) && !length(intersect(beta, alpha)) &&
    setequal(c(beta, alpha), seq_len(ncol(X))), "reference/discrepancy coefficient partition differs")
  dates <- seq(origin - as.integer(days) + 1L, origin, by = "day")
  at <- match(dates, rd[yi]); q(!anyNA(at), "consecutive requested history dates are absent")
  at <- yi[at]; H <- X[at, , drop = FALSE]
  q(all(is.finite(H)) && all(H[, alpha, drop = FALSE] == 0),
    "historical USGS rows must have zero discrepancy columns")
  xb <- design$X_beta
  q(is.matrix(xb) && is.numeric(xb) && nrow(xb) == nrow(b) && ncol(xb) == length(beta) &&
    isTRUE(all.equal(unname(H[, beta, drop = FALSE]),
      unname(xb[as.integer(f[at]), , drop = FALSE]), tolerance = 0, check.attributes = FALSE)),
    "stored reference features disagree with historical USGS design")
  structure(list(H = H, dates = dates, columns = columns, days = as.integer(days),
    beta_index = as.integer(beta), alpha_index = as.integer(alpha)), class = "gfh_reference_history_v1")
}

# The Normal core's sigma is an inverse-gamma VARIANCE, not a standard deviation.
gfh_normal_sd_mean <- function(sigma) {
  q <- gfh_require
  q(is.list(sigma) && is.numeric(sigma$shape) && is.numeric(sigma$rate) &&
    identical(names(sigma$shape), c("Y", "G")) && identical(names(sigma$rate), c("Y", "G")) &&
    all(is.finite(c(sigma$shape, sigma$rate))) && all(sigma$shape > .5) && all(sigma$rate > 0),
    "named Normal inverse-gamma variance shape > 1/2 and positive rate required")
  a <- sigma$shape[["Y"]]; b <- sigma$rate[["Y"]]
  value <- exp(.5 * log(b) + lgamma(a - .5) - lgamma(a))
  q(length(value) == 1L && is.finite(value) && value > 0, "nonfinite Normal variance half-moment")
  value
}

gfh_core_rows <- function(core, history, family, probabilities, conditional_joint_rhs = FALSE) {
  q <- gfh_require
  q(inherits(history, "gfh_reference_history_v1"), "validated historical reference rows required")
  q(is.list(core) && identical(core$method, "vb") &&
    is.character(core$likelihood_family) && length(core$likelihood_family) == 1L &&
    core$likelihood_family %in% c("normal", "al", "exal") &&
    is.character(core$prior) && length(core$prior) == 1L &&
    core$prior %in% c("ridge", "rhs_ns"), "known VB likelihood/prior required")
  p <- probabilities
  q(is.numeric(p) && length(p) > 0L && all(is.finite(p)) && !anyDuplicated(p) &&
    all(p %in% gfh_tau()) && identical(p, sort(p)), "ordered frozen probability levels required")
  m <- core$summary$theta_mean
  q(is.numeric(m) && length(m) == ncol(history$H) && all(is.finite(m)) &&
    is.matrix(core$draws$theta) && identical(colnames(core$draws$theta), history$columns),
    "coefficient dimension or retained feature order differs")
  location <- as.numeric(history$H %*% m)
  normal <- identical(core$likelihood_family, "normal")
  q(is.character(family) && length(family) == 1L && !is.na(family), "one family label required")
  q(if (normal) family %in% c("Normal Ridge", "Normal RHS") else
    family %in% if (core$likelihood_family == "al") c("Independent AL", "MQ AL") else
      c("Independent exAL", "MQ exAL"), "family label disagrees with likelihood")
  if (normal) q(identical(core$prior, if (family == "Normal Ridge") "ridge" else "rhs_ns"),
    "Normal family label disagrees with prior")
  q(normal || (length(p) == 1L && (identical(core$prior, "rhs_ns") ||
    (isTRUE(conditional_joint_rhs) && family %in% c("MQ AL", "MQ exAL") && identical(core$prior,"ridge")))),
    "one matching fixed-p AL/exAL core required")
  sd_mean <- if (normal) gfh_normal_sd_mean(core$variational_state$sigma) else 0
  out <- do.call(rbind, lapply(p, function(tau) {
    offset <- if (normal) sd_mean * stats::qnorm(tau) else 0
    z <- location + offset
    q(all(is.finite(c(z, expm1(z)))), "nonfinite fitted conditional quantile")
    data.frame(family = family, target_date = as.character(history$dates), tau = tau,
      quantile_transformed = z, quantile = expm1(z),
      location_mean_transformed = location, quantile_offset_transformed = offset,
      time_role = "historical_fitted_conditional_quantile",
      estimand = "VB_mean_conditional_quantile_on_log1p_scale",
      inverse_transform = "expm1_of_transformed_scale_VB_mean_not_original_scale_mean",
      future_path_factor_used = FALSE, posterior_predictive_quantile = FALSE,
      quantile_functional_credible_interval = FALSE, extra_response_noise_added = FALSE,
      isotonic_adjustment = FALSE, stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL; out
}

gfh_transition_rows <- function(result, design, days = 30L) {
  q <- gfh_require; id <- result$task_id
  ids <- c(paste0("gft-al-p", c("005", "020", "035", "050", "065", "080", "095")),
    paste0("gft-exal-p", c("005", "020", "035", "050", "065", "080", "095")),
    "gft-mq-al", "gft-mq-exal")
  q(is.list(result) && identical(result$schema_version, "glofas_family_transition_fit_v1") &&
    is.character(id) && length(id) == 1L && id %in% ids &&
    isTRUE(result$converged) && identical(result$status, "converged") &&
    identical(result$target_contract$schema_version, "glofas_family_transition_v1") &&
    identical(result$target_contract$future_truth_used_in_fit, FALSE) &&
    identical(result$target_contract$replacement_gaussian_path_prior, FALSE),
    "completed same-family transition result required")
  history <- gfh_reference_history(design, days)
  mq <- startsWith(id, "gft-mq-")
  likelihood <- if (grepl("exal", id, fixed = TRUE)) "exal" else "al"
  family <- paste(if (mq) "MQ" else "Independent", if (likelihood == "al") "AL" else "exAL")
  if (mq) {
    joint <- result$fit
    q(identical(joint$schema_version, "glofas_part4_joint_latent_v1") &&
      identical(joint$fit_structure, "joint_adjacent_rhs") && identical(joint$likelihood_family, likelihood) &&
      isTRUE(joint$converged) && identical(as.numeric(joint$tau), gfh_tau()) && length(joint$fits) == 7L,
      "matching complete multiquantile blocks required")
    cores <- joint$fits; p <- gfh_tau()
    # The joint engine updates RHS moments outside the seven conditional
    # Gaussian coefficient fits (which are therefore tagged ridge internally).
    # Accept that representation only with the retained outer RHS certificate.
    conditional_rhs <- any(vapply(cores,function(x)identical(x$prior,"ridge"),logical(1L)))
    if (conditional_rhs) {
      cert <- joint$rhs_partition_certificate
      precision_ok <- function(states,n) is.list(states)&&length(states)==7L&&
        all(vapply(states,function(x)is.numeric(x$prior_precision)&&length(x$prior_precision)==n&&
          all(is.finite(x$prior_precision)&x$prior_precision>0),logical(1L)))
      q(isTRUE(joint$converged_rhs)&&is.data.frame(cert)&&nrow(cert)==1L&&
        identical(cert$schema_version,"glofas_part3_rhs_partition_v1")&&
        cert$p_reference==length(history$beta_index)&&cert$p_discrepancy==length(history$alpha_index)&&
        cert$n_quantiles==7L&&cert$overlap_count==0L&&isTRUE(cert$all_precision_finite)&&
        precision_ok(joint$rhs_state_reference,length(history$beta_index))&&
        precision_ok(joint$rhs_state_discrepancy,length(history$alpha_index)),
        "conditional Gaussian cores require the converged outer RHS certificate")
    }
  } else {
    cores <- list(result$fit); p <- as.numeric(sub(".*-p", "", id)) / 100; conditional_rhs <- FALSE
  }
  rows <- lapply(seq_along(cores), function(k) {
    core <- cores[[k]]
    q(identical(core$likelihood_family, likelihood) &&
      isTRUE(core$vb_diagnostics$converged) &&
      isTRUE(core$vb_diagnostics$future_y_working_likelihood_used) &&
      identical(core$vb_diagnostics$future_gaussian_prior_used, FALSE), "core likelihood or fitted state differs")
    # The task identity / joint tau order identifies p; old optional metadata
    # cannot silently conflict with that association.
    stated <- core$warm_start_contract$quantile_level
    if (!is.null(stated)) q(identical(as.numeric(stated), p[k]), "retained core probability level differs")
    gfh_core_rows(core, history, family, p[k],conditional_joint_rhs=conditional_rhs)
  })
  out <- do.call(rbind, rows); rownames(out) <- NULL; out
}

gfh_normal_rows <- function(result, design, model, days = 30L) {
  q <- gfh_require
  q(is.character(model) && length(model) == 1L && model %in% c("normal_ridge", "normal_rhs"),
    "known enrolled Normal model required")
  prior <- if (model == "normal_ridge") "ridge" else "rhs_ns"
  q(is.list(result) && identical(result$status, "completed") &&
    identical(result$likelihood_family, "normal") && identical(result$coefficient_prior, prior) &&
    identical(result$fit$likelihood_family, "normal") && identical(result$fit$prior, prior) &&
    isTRUE(result$fit$vb_diagnostics$converged), "completed enrolled Normal state required")
  gfh_core_rows(result$fit, gfh_reference_history(design, days),
    if (model == "normal_ridge") "Normal Ridge" else "Normal RHS", gfh_tau())
}
