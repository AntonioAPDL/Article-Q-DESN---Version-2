# Reference-only Q-DESN fit adapter.

app_fit_qdesn_reference <- function(panel, cfg, model_row) {
  fit_fun <- app_qdesn_engine_function(cfg, "qdesn_fit")

  hist <- panel[panel$is_retrospective & is.finite(panel$y_transformed), , drop = FALSE]
  hist <- hist[order(hist$target_date), , drop = FALSE]
  if (nrow(hist) < 50L) stop("Reference-only Q-DESN requires at least 50 historical rows.", call. = FALSE)

  p0 <- as.numeric(model_row$quantile_level[[1L]])
  method <- if (tolower(model_row$inference_method[[1L]]) == "mcmc") "mcmc" else "vb"
  prior <- tolower(model_row$coefficient_prior[[1L]])
  if (identical(prior, "none")) prior <- cfg$inference$coefficient_prior_default
  prior_engine <- app_map_qdesn_prior(prior)

  args <- c(
    list(
      y = hist$y_transformed,
      p0 = p0,
      method = method
    ),
    app_reservoir_args(cfg, seed = as.integer(model_row$reservoir_seed[[1L]] %||% cfg$reservoir$seed))
  )

  args$vb_args <- list(beta_prior_type = prior_engine)
  args$mcmc_args <- list(beta_prior_type = prior_engine)

  fit <- do.call(fit_fun, args)
  list(
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]],
    model_family = model_row$model_family[[1L]],
    quantile_level = p0,
    fit = fit,
    status = "completed"
  )
}
