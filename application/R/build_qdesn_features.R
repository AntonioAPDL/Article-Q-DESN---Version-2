# Q-DESN feature adapter for the GloFAS application.

app_reservoir_args <- function(cfg, seed = NULL, force_no_readout_bias = FALSE) {
  r <- cfg$reservoir
  if (is.null(r$n) && "FALSE" %in% names(r)) {
    r$n <- r[["FALSE"]]
    r[["FALSE"]] <- NULL
  }
  r$seed <- as.integer(seed %||% r$seed %||% 20260511L)
  if (isTRUE(force_no_readout_bias)) {
    r$add_bias <- FALSE
  }
  r
}

app_build_qdesn_design <- function(y, cfg, seed = NULL, drop = NULL) {
  build_fun <- app_qdesn_engine_function(cfg, "qdesn_build_design")
  build_fun(
    y = y,
    desn_args = app_reservoir_args(cfg, seed = seed, force_no_readout_bias = TRUE),
    drop = drop
  )
}

app_build_qdesn_design_full <- function(y, cfg, seed = NULL, drop = NULL) {
  fit_fun <- app_qdesn_engine_function(cfg, "qdesn_fit_vb")
  args <- app_reservoir_args(cfg, seed = seed, force_no_readout_bias = TRUE)
  if (!is.null(drop)) {
    args$washout <- max(as.integer(drop), as.integer(args$m %||% 0L))
  }
  do.call(
    fit_fun,
    c(
      list(
        y = y,
        p0 = 0.50,
        fit_readout = FALSE,
        vb_args = list()
      ),
      args
    )
  )
}
