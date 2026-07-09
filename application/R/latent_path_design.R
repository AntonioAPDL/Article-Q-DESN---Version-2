# Latent-path continuation helpers for the GloFAS ensemble-likelihood model.

app_qdesn_activation <- function(name) {
  if (is.function(name)) return(name)
  name <- tolower(as.character(name %||% "tanh")[[1L]])
  switch(name,
    tanh = base::tanh,
    relu = function(x) pmax(0, x),
    identity = function(x) x,
    stop(sprintf("Unsupported Q-DESN activation '%s'.", name), call. = FALSE)
  )
}

app_qdesn_activation_derivative <- function(name) {
  if (is.function(name)) {
    stop("Custom activation functions need an explicit derivative before latent-path sensitivities can be used.", call. = FALSE)
  }
  name <- tolower(as.character(name %||% "tanh")[[1L]])
  switch(name,
    tanh = function(x) {
      z <- tanh(x)
      1 - z^2
    },
    relu = function(x) as.numeric(x > 0),
    identity = function(x) rep(1, length(x)),
    stop(sprintf("Unsupported Q-DESN activation '%s'.", name), call. = FALSE)
  )
}

app_qdesn_last_states <- function(qfit) {
  states <- qfit$states$H_all %||% NULL
  if (is.null(states) || !is.list(states) || !length(states)) {
    stop("Q-DESN object is missing states$H_all for latent-path continuation.", call. = FALSE)
  }
  lapply(states, function(H) {
    H <- as.matrix(H)
    if (!nrow(H)) stop("Q-DESN state matrix has zero rows.", call. = FALSE)
    as.numeric(H[nrow(H), ])
  })
}

app_qdesn_lag_buffer <- function(y_history, m_input) {
  m_input <- as.integer(m_input)
  if (!is.finite(m_input) || m_input < 0L) stop("m_input must be nonnegative.", call. = FALSE)
  if (!m_input) return(numeric(0))
  y_history <- as.numeric(y_history)
  if (length(y_history) < m_input) {
    stop("Historical response is too short to initialize the reservoir lag buffer.", call. = FALSE)
  }
  out <- rev(utils::tail(y_history, m_input))
  if (any(!is.finite(out))) stop("Historical reservoir lag buffer contains non-finite values.", call. = FALSE)
  out
}

# Covariate-aware reservoir input construction. These helpers are used only by
# latent-path configs that put ppt and soil lags inside the reservoir input.
# Response-only configs keep using the package-side Q-DESN design builder.

app_qdesn_reservoir_input_spec <- function(cfg) {
  contract <- app_feature_contract(cfg)
  output_lags <- as.integer(contract$reservoir_input$output_lags %||% integer(0))
  covariate_lags <- contract$reservoir_input$covariate_lags %||% list()
  covariate_lags <- covariate_lags[vapply(covariate_lags, length, integer(1L)) > 0L]

  columns <- character(0)
  info <- list()
  k <- 1L
  if (length(output_lags)) {
    columns <- c(columns, sprintf("y_lag_%d", output_lags))
    info[[k]] <- data.frame(
      column_name = sprintf("y_lag_%d", output_lags),
      input_block = "output_lag",
      variable = "y",
      lag = output_lags,
      stringsAsFactors = FALSE
    )
    k <- k + 1L
  }
  if (length(covariate_lags)) {
    for (v in names(covariate_lags)) {
      lags <- as.integer(covariate_lags[[v]])
      columns <- c(columns, sprintf("%s_lag_%d", v, lags))
      info[[k]] <- data.frame(
        column_name = sprintf("%s_lag_%d", v, lags),
        input_block = "covariate_lag",
        variable = v,
        lag = lags,
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }
  if (!length(columns)) {
    stop("Reservoir input contract produced zero non-bias input columns.", call. = FALSE)
  }
  info <- app_bind_rows_fill(info)
  rownames(info) <- NULL
  info$column_index <- seq_len(nrow(info))
  info <- info[, c("column_index", setdiff(names(info), "column_index")), drop = FALSE]
  if (anyDuplicated(columns)) {
    stop("Reservoir input contract produced duplicated input columns.", call. = FALSE)
  }

  list(
    columns = columns,
    info = info,
    output_lags = output_lags,
    covariate_lags = covariate_lags,
    uses_covariates = length(covariate_lags) > 0L,
    standardize = isTRUE(contract$reservoir_input$standardize),
    internal_bias = isTRUE(contract$reservoir_input$internal_bias),
    m_input = length(columns)
  )
}

app_qdesn_reservoir_uses_covariates <- function(cfg) {
  length(app_qdesn_reservoir_input_spec(cfg)$covariate_lags) > 0L
}

app_qdesn_covariate_lookup <- function(timeline, variable, date) {
  if (is.null(timeline) || !nrow(timeline)) {
    stop("Covariate-aware reservoir inputs require a model covariate timeline.", call. = FALSE)
  }
  if (!"date" %in% names(timeline)) {
    stop("Model covariate timeline is missing a date column.", call. = FALSE)
  }
  date <- as.Date(date)
  timeline$date <- as.Date(timeline$date)
  value_col <- as.character(variable)
  role_col <- paste0(value_col, "_role")
  if (!value_col %in% names(timeline)) {
    stop(sprintf("Model covariate timeline is missing '%s'.", value_col), call. = FALSE)
  }
  idx <- match(date, timeline$date)
  if (is.na(idx)) {
    if (date < min(timeline$date, na.rm = TRUE)) {
      return(list(value = 0, role = "initial_zero_padding", source = "padding"))
    }
    stop(sprintf("Missing %s covariate value for %s.", value_col, as.character(date)), call. = FALSE)
  }
  value <- as.numeric(timeline[[value_col]][[idx]])
  if (!is.finite(value)) {
    stop(sprintf("Non-finite %s covariate value for %s.", value_col, as.character(date)), call. = FALSE)
  }
  role <- if (role_col %in% names(timeline)) as.character(timeline[[role_col]][[idx]]) else "covariate"
  list(value = value, role = role, source = "covariate_timeline")
}

app_qdesn_response_lookup <- function(history_dates, y_history, date, future_dates = NULL, y_future = NULL, h_current = NULL) {
  history_dates <- as.Date(history_dates)
  y_history <- as.numeric(y_history)
  date <- as.Date(date)
  n_future <- length(y_future %||% numeric(0))
  deriv <- rep(0, n_future)
  idx_hist <- match(date, history_dates)
  if (!is.na(idx_hist)) {
    value <- y_history[[idx_hist]]
    if (!is.finite(value)) stop(sprintf("Non-finite historical response lag for %s.", as.character(date)), call. = FALSE)
    return(list(value = value, derivative = deriv, role = "historical_usgs", source = "history"))
  }
  if (!is.null(future_dates) && length(future_dates)) {
    future_dates <- as.Date(future_dates)
    idx_future <- match(date, future_dates)
    if (!is.na(idx_future)) {
      if (is.null(h_current) || idx_future >= as.integer(h_current)) {
        stop(
          sprintf(
            "Reservoir input for %s would require an unavailable current or future USGS lag at %s.",
            as.character(future_dates[[as.integer(h_current)]] %||% date),
            as.character(date)
          ),
          call. = FALSE
        )
      }
      value <- as.numeric(y_future[[idx_future]])
      if (!is.finite(value)) stop(sprintf("Non-finite latent future response lag for %s.", as.character(date)), call. = FALSE)
      deriv[[idx_future]] <- 1
      return(list(value = value, derivative = deriv, role = "latent_future_usgs", source = "latent_path"))
    }
  }
  if (date < min(history_dates, na.rm = TRUE)) {
    return(list(value = 0, derivative = deriv, role = "initial_zero_padding", source = "padding"))
  }
  stop(sprintf("Missing response lag value for %s.", as.character(date)), call. = FALSE)
}

app_qdesn_reservoir_input_row <- function(
  spec,
  history_dates,
  y_history,
  target_date,
  covariate_timeline = NULL,
  future_dates = NULL,
  y_future = NULL,
  h_current = NULL
) {
  n_future <- length(y_future %||% numeric(0))
  values <- numeric(spec$m_input)
  J <- matrix(0, nrow = spec$m_input, ncol = n_future)
  audit <- vector("list", spec$m_input)
  info <- spec$info
  target_date <- as.Date(target_date)
  for (j in seq_len(nrow(info))) {
    variable <- as.character(info$variable[[j]])
    lag <- as.integer(info$lag[[j]])
    lookup_date <- target_date - lag
    if (identical(variable, "y")) {
      looked <- app_qdesn_response_lookup(
        history_dates = history_dates,
        y_history = y_history,
        date = lookup_date,
        future_dates = future_dates,
        y_future = y_future,
        h_current = h_current
      )
      values[[j]] <- looked$value
      if (n_future) J[j, ] <- looked$derivative
      role <- looked$role
      source <- looked$source
    } else {
      looked <- app_qdesn_covariate_lookup(covariate_timeline, variable, lookup_date)
      values[[j]] <- looked$value
      role <- looked$role
      source <- looked$source
    }
    audit[[j]] <- data.frame(
      target_date = target_date,
      input_date = lookup_date,
      column_name = as.character(info$column_name[[j]]),
      input_block = as.character(info$input_block[[j]]),
      variable = variable,
      lag = lag,
      role = role,
      source = source,
      stringsAsFactors = FALSE
    )
  }
  names(values) <- spec$columns
  rownames(J) <- spec$columns
  list(value = values, jacobian = J, audit = app_bind_rows_fill(audit))
}

app_qdesn_reservoir_input_matrix <- function(panel, cfg, spec = NULL) {
  spec <- spec %||% app_qdesn_reservoir_input_spec(cfg)
  panel$target_date <- as.Date(panel$target_date)
  history_dates <- as.Date(panel$target_date)
  y_history <- as.numeric(panel$y_transformed)
  if (any(!is.finite(y_history))) stop("Reservoir input history contains non-finite response values.", call. = FALSE)
  covariate_timeline <- if (isTRUE(spec$uses_covariates)) app_panel_covariate_timeline(panel, required = TRUE) else NULL

  n <- nrow(panel)
  X <- matrix(NA_real_, nrow = n, ncol = spec$m_input)
  colnames(X) <- spec$columns
  storage.mode(X) <- "double"
  summaries <- vector("list", nrow(spec$info))
  for (j in seq_len(nrow(spec$info))) {
    variable <- as.character(spec$info$variable[[j]])
    lag <- as.integer(spec$info$lag[[j]])
    lookup_dates <- panel$target_date - lag
    if (identical(variable, "y")) {
      idx <- match(lookup_dates, history_dates)
      initial <- is.na(idx) & lookup_dates < min(history_dates, na.rm = TRUE)
      missing <- is.na(idx) & !initial
      if (any(missing)) {
        missing_dates <- sort(unique(lookup_dates[missing]))
        stop(
          sprintf(
            "Missing response history for reservoir input %s at %s.",
            as.character(spec$info$column_name[[j]]),
            paste(utils::head(as.character(missing_dates), 10L), collapse = ", ")
          ),
          call. = FALSE
        )
      }
      vals <- numeric(n)
      vals[!initial] <- y_history[idx[!initial]]
      if (any(!is.finite(vals))) {
        stop(sprintf("Non-finite values in reservoir input %s.", as.character(spec$info$column_name[[j]])), call. = FALSE)
      }
      X[, j] <- vals
      summaries[[j]] <- data.frame(
        column_name = as.character(spec$info$column_name[[j]]),
        input_block = "output_lag",
        variable = "y",
        lag = lag,
        n_rows = n,
        n_initial_zero_padding = sum(initial),
        n_history = sum(!initial),
        n_covariate = 0L,
        roles = "historical_usgs;initial_zero_padding",
        stringsAsFactors = FALSE
      )
    } else {
      if (is.null(covariate_timeline) || !nrow(covariate_timeline)) {
        stop("Covariate-aware reservoir input matrix requires a covariate timeline.", call. = FALSE)
      }
      covariate_timeline$date <- as.Date(covariate_timeline$date)
      if (!variable %in% names(covariate_timeline)) {
        stop(sprintf("Covariate timeline is missing '%s'.", variable), call. = FALSE)
      }
      idx <- match(lookup_dates, covariate_timeline$date)
      initial <- is.na(idx) & lookup_dates < min(covariate_timeline$date, na.rm = TRUE)
      missing <- is.na(idx) & !initial
      if (any(missing)) {
        missing_dates <- sort(unique(lookup_dates[missing]))
        stop(
          sprintf(
            "Missing covariate history for reservoir input %s at %s.",
            as.character(spec$info$column_name[[j]]),
            paste(utils::head(as.character(missing_dates), 10L), collapse = ", ")
          ),
          call. = FALSE
        )
      }
      vals <- numeric(n)
      vals[!initial] <- as.numeric(covariate_timeline[[variable]][idx[!initial]])
      if (any(!is.finite(vals))) {
        stop(sprintf("Non-finite values in reservoir input %s.", as.character(spec$info$column_name[[j]])), call. = FALSE)
      }
      X[, j] <- vals
      role_col <- paste0(variable, "_role")
      roles <- rep("initial_zero_padding", n)
      if (role_col %in% names(covariate_timeline)) {
        roles[!initial] <- as.character(covariate_timeline[[role_col]][idx[!initial]])
      } else {
        roles[!initial] <- "covariate"
      }
      summaries[[j]] <- data.frame(
        column_name = as.character(spec$info$column_name[[j]]),
        input_block = "covariate_lag",
        variable = variable,
        lag = lag,
        n_rows = n,
        n_initial_zero_padding = sum(initial),
        n_history = 0L,
        n_covariate = sum(!initial),
        roles = paste(sort(unique(roles)), collapse = ";"),
        stringsAsFactors = FALSE
      )
    }
  }
  list(X = X, audit = app_bind_rows_fill(summaries), covariate_timeline = covariate_timeline)
}

# Article-side reservoir generation mirrors the package-side fixed-DESN
# construction closely enough for the application contract, while allowing an
# arbitrary input matrix instead of scalar response lags only.

app_qdesn_reservoir_scale_inputs <- function(X_raw, standardize = TRUE, scale_params = NULL) {
  X_raw <- as.matrix(X_raw)
  storage.mode(X_raw) <- "double"
  cols <- colnames(X_raw)
  if (is.null(cols) || any(!nzchar(cols))) cols <- paste0("input_", seq_len(ncol(X_raw)))
  if (is.null(scale_params)) {
    if (isTRUE(standardize)) {
      center <- colMeans(X_raw)
      scale <- apply(X_raw, 2L, stats::sd)
      scale[!is.finite(scale) | scale <= 1.0e-12] <- 1
    } else {
      center <- rep(0, ncol(X_raw))
      scale <- rep(1, ncol(X_raw))
    }
    names(center) <- cols
    names(scale) <- cols
    scale_params <- list(columns = cols, center = center, scale = scale, standardize = isTRUE(standardize))
  }
  center <- as.numeric(scale_params$center[cols])
  scale <- as.numeric(scale_params$scale[cols])
  if (any(!is.finite(center)) || any(!is.finite(scale)) || any(scale <= 0)) {
    stop("Invalid reservoir input scaling parameters.", call. = FALSE)
  }
  list(
    X = sweep(sweep(X_raw, 2L, center, "-"), 2L, scale, "/"),
    scale_params = scale_params
  )
}

app_qdesn_sparse_weights <- function(nr, nc, prob, dist = "normal") {
  prob <- as.numeric(prob)
  if (!is.finite(prob) || prob <= 0 || prob > 1) stop("Sparse-weight probability must lie in (0, 1].", call. = FALSE)
  mask <- matrix(stats::runif(nr * nc) < prob, nr, nc)
  dist <- tolower(as.character(dist %||% "normal")[[1L]])
  z <- switch(
    dist,
    normal = matrix(stats::rnorm(nr * nc), nr, nc),
    gaussian = matrix(stats::rnorm(nr * nc), nr, nc),
    uniform = matrix(stats::runif(nr * nc, -1, 1), nr, nc),
    stop(sprintf("Unsupported reservoir weight distribution '%s'.", dist), call. = FALSE)
  )
  storage.mode(mask) <- "double"
  mask * z
}

app_qdesn_spectral_radius <- function(A) {
  A <- as.matrix(A)
  if (nrow(A) != ncol(A)) stop("Spectral radius requires a square matrix.", call. = FALSE)
  if (nrow(A) >= 256L && requireNamespace("RSpectra", quietly = TRUE)) {
    ev <- tryCatch(RSpectra::eigs(A, k = 1L, which = "LM")$values, error = function(e) NULL)
    if (!is.null(ev) && length(ev)) return(max(Mod(ev)))
  }
  exact_max_n <- getOption("app_qdesn_spectral_radius_exact_max_n", Inf)
  if (is.finite(exact_max_n) && nrow(A) > exact_max_n) {
    v <- rep(1 / sqrt(nrow(A)), nrow(A))
    radius <- NA_real_
    for (iter in seq_len(as.integer(getOption("app_qdesn_spectral_radius_power_iter", 120L)))) {
      z <- drop(A %*% v)
      nz <- sqrt(sum(z^2))
      if (!is.finite(nz) || nz <= 0) return(0)
      v_next <- z / nz
      radius_next <- nz
      if (is.finite(radius) && abs(radius_next - radius) <= 1.0e-6 * max(1, abs(radius))) {
        radius <- radius_next
        break
      }
      v <- v_next
      radius <- radius_next
    }
    return(as.numeric(radius))
  }
  max(Mod(eigen(A, only.values = TRUE)$values))
}

app_qdesn_enforce_leaky_radius <- function(Wd, alpha) {
  alpha <- as.numeric(alpha)
  nr <- nrow(Wd)
  J <- (1 - alpha) * diag(nr) + alpha * Wd
  rJ <- app_qdesn_spectral_radius(J)
  if (!is.finite(rJ) || rJ <= 0 || rJ < 1 - 1.0e-6) return(Wd)
  s <- 0.99 / rJ
  (1 / alpha) * (s * J - (1 - alpha) * diag(nr))
}

app_qdesn_make_reducer <- function(n_from, n_to) {
  n_from <- as.integer(n_from)
  n_to <- as.integer(n_to)
  if (n_to <= 0L) return(matrix(0, 0, n_from))
  Q <- matrix(stats::rnorm(n_to * n_from), n_to, n_from)
  rs <- sqrt(rowSums(Q^2))
  rs[!is.finite(rs) | rs < 1.0e-8] <- 1
  Q / rs
}

app_qdesn_generate_article_reservoir <- function(cfg, seed, m_input) {
  r <- cfg$reservoir %||% list()
  D <- as.integer(r$D %||% 1L)
  n <- as.integer(unlist(r$n %||% r[["FALSE"]] %||% 50L, use.names = FALSE))
  if (length(n) == 1L) n <- rep(n, D)
  if (length(n) != D || any(!is.finite(n)) || any(n <= 0L)) stop("Invalid reservoir n specification.", call. = FALSE)
  n_tilde <- as.integer(unlist(r$n_tilde %||% if (D > 1L) n[-D] else integer(0), use.names = FALSE))
  if (D == 1L) n_tilde <- integer(0)
  if (D > 1L && length(n_tilde) == 1L) n_tilde <- rep(n_tilde, D - 1L)
  if (D > 1L && (length(n_tilde) != D - 1L || any(!is.finite(n_tilde)) || any(n_tilde <= 0L))) {
    stop("Invalid reservoir n_tilde specification.", call. = FALSE)
  }
  alpha <- as.numeric(unlist(r$alpha %||% 0.3, use.names = FALSE))
  rho <- as.numeric(unlist(r$rho %||% 0.9, use.names = FALSE))
  pi_w <- as.numeric(unlist(r$pi_w %||% 0.1, use.names = FALSE))
  pi_in <- as.numeric(unlist(r$pi_in %||% 1, use.names = FALSE))
  if (length(alpha) == 1L) alpha <- rep(alpha, D)
  if (length(rho) == 1L) rho <- rep(rho, D)
  if (length(pi_w) == 1L) pi_w <- rep(pi_w, D)
  if (length(pi_in) == 1L) pi_in <- rep(pi_in, D)
  if (length(alpha) != D || any(alpha <= 0 | alpha >= 1)) stop("Invalid reservoir alpha.", call. = FALSE)
  if (length(rho) != D || any(rho <= 0 | rho >= 1)) stop("Invalid reservoir rho.", call. = FALSE)
  if (length(pi_w) != D || any(pi_w <= 0 | pi_w > 1)) stop("Invalid reservoir pi_w.", call. = FALSE)
  if (length(pi_in) != D || any(pi_in <= 0 | pi_in > 1)) stop("Invalid reservoir pi_in.", call. = FALSE)

  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))

  w_dist <- as.character(r$w_dist %||% "normal")
  in_dist <- as.character(r$in_dist %||% "normal")
  Win <- vector("list", D)
  W <- vector("list", D)
  Qred <- vector("list", max(0L, D - 1L))
  Q_is_identity <- logical(max(0L, D - 1L))
  Win[[1L]] <- app_qdesn_sparse_weights(n[[1L]], as.integer(m_input) + 1L, pi_in[[1L]], in_dist)
  W[[1L]] <- app_qdesn_sparse_weights(n[[1L]], n[[1L]], pi_w[[1L]], w_dist)
  if (D >= 2L) {
    for (d in 2:D) {
      Win[[d]] <- app_qdesn_sparse_weights(n[[d]], n_tilde[[d - 1L]], pi_in[[d]], in_dist)
      W[[d]] <- app_qdesn_sparse_weights(n[[d]], n[[d]], pi_w[[d]], w_dist)
      if (n_tilde[[d - 1L]] == n[[d - 1L]]) {
        Qred[[d - 1L]] <- diag(1, n[[d - 1L]])
        Q_is_identity[[d - 1L]] <- TRUE
      } else {
        Qred[[d - 1L]] <- app_qdesn_make_reducer(n[[d - 1L]], n_tilde[[d - 1L]])
        Q_is_identity[[d - 1L]] <- FALSE
      }
    }
  }
  for (d in seq_len(D)) {
    sr <- suppressWarnings(try(app_qdesn_spectral_radius(W[[d]]), silent = TRUE))
    if (inherits(sr, "try-error") || !is.finite(sr) || sr <= 0) sr <- 1
    W[[d]] <- (rho[[d]] / sr) * W[[d]]
    W[[d]] <- app_qdesn_enforce_leaky_radius(W[[d]], alpha[[d]])
  }
  list(
    D = D,
    n = n,
    n_tilde = n_tilde,
    m = as.integer(r$m %||% m_input),
    m_input = as.integer(m_input),
    alpha = alpha,
    rho = rho,
    W = W,
    Win = Win,
    Q = Qred,
    Q_is_identity = Q_is_identity,
    act_f = r$act_f %||% "tanh",
    act_k = r$act_k %||% "identity",
    pi_w = pi_w,
    pi_in = pi_in,
    w_dist = w_dist,
    in_dist = in_dist,
    seed = as.integer(seed)
  )
}

app_qdesn_roll_article_reservoir <- function(input_matrix, reservoir, meta) {
  input_matrix <- as.matrix(input_matrix)
  storage.mode(input_matrix) <- "double"
  D <- as.integer(reservoir$D)
  states <- lapply(seq_len(D), function(d) rep(0, reservoir$n[[d]]))
  H <- lapply(seq_len(D), function(d) matrix(0, nrow = nrow(input_matrix), ncol = reservoir$n[[d]]))
  X_all <- matrix(NA_real_, nrow = nrow(input_matrix), ncol = length(app_qdesn_readout_row_from_states(states, reservoir)))
  for (i in seq_len(nrow(input_matrix))) {
    states <- app_qdesn_continue_one_step(states, input_matrix[i, ], reservoir, meta)
    for (d in seq_len(D)) H[[d]][i, ] <- states[[d]]
    X_all[i, ] <- app_qdesn_readout_row_from_states(states, reservoir)
  }
  colnames(X_all) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(X_all))))
  list(X_all = X_all, H_all = H)
}

app_qdesn_build_article_design_full <- function(panel, cfg, seed = NULL, drop = NULL) {
  spec <- app_qdesn_reservoir_input_spec(cfg)
  if (!isTRUE(spec$uses_covariates)) {
    stop("Article-side reservoir design is reserved for covariate-aware reservoir input contracts.", call. = FALSE)
  }
  seed <- suppressWarnings(as.integer(seed %||% (cfg$reservoir %||% list())$seed %||% 20260513L))
  if (!is.finite(seed)) seed <- 20260513L
  input <- app_qdesn_reservoir_input_matrix(panel, cfg, spec = spec)
  standardize <- isTRUE(spec$standardize)
  scaled <- app_qdesn_reservoir_scale_inputs(input$X, standardize = standardize)
  meta <- list(
    keep_idx = integer(0),
    drop = NA_integer_,
    T = nrow(panel),
    p0 = 0.50,
    D = as.integer((cfg$reservoir %||% list())$D %||% 1L),
    m = as.integer((cfg$reservoir %||% list())$m %||% spec$m_input),
    m_input = spec$m_input,
    input_components = spec$columns,
    input_lag_warmup = max(c(spec$output_lags, unlist(spec$covariate_lags, use.names = FALSE), 0L)),
    add_bias = FALSE,
    inference_method = "design_only",
    input_mode_requested = "article_covariate_lags",
    input_mode_effective = "article_covariate_lags",
    input_mode = "article_covariate_lags",
    standardize_inputs = standardize,
    input_bound = as.character((cfg$reservoir %||% list())$input_bound %||% "none"),
    win_scale_global = as.numeric((cfg$reservoir %||% list())$win_scale_global %||% 1),
    win_scale_bias = as.numeric((cfg$reservoir %||% list())$win_scale_bias %||% 1),
    win_scale_lags = NULL,
    lag_center = as.numeric(scaled$scale_params$center[spec$columns]),
    lag_scale = as.numeric(scaled$scale_params$scale[spec$columns]),
    reservoir_input_spec = spec,
    reservoir_input_columns = spec$columns,
    reservoir_input_info = spec$info,
    reservoir_covariates_enabled = TRUE,
    reservoir_covariate_columns = spec$info$column_name[spec$info$input_block == "covariate_lag"],
    reservoir_input_scale_params = scaled$scale_params,
    reservoir_input_audit_summary = input$audit,
    covariate_timeline = input$covariate_timeline,
    history_dates = as.Date(panel$target_date),
    y_history = as.numeric(panel$y_transformed)
  )
  reservoir <- app_qdesn_generate_article_reservoir(cfg, seed = seed, m_input = spec$m_input)
  rolled <- app_qdesn_roll_article_reservoir(input$X, reservoir, meta)
  requested_drop <- as.integer(drop %||% (cfg$reservoir %||% list())$washout %||% 0L)
  if (!is.finite(requested_drop)) requested_drop <- 0L
  drop_final <- max(requested_drop, meta$input_lag_warmup, 0L)
  if (nrow(panel) <= drop_final) {
    stop(
      sprintf("Not enough historical rows (%d) for reservoir drop/washout of %d.", nrow(panel), drop_final),
      call. = FALSE
    )
  }
  keep_idx <- seq.int(drop_final + 1L, nrow(panel))
  meta$keep_idx <- keep_idx
  meta$drop <- drop_final
  meta$alpha <- reservoir$alpha
  meta$rho <- reservoir$rho
  out <- list(
    fit = NULL,
    X = rolled$X_all[keep_idx, , drop = FALSE],
    y_fit = as.numeric(panel$y_transformed[keep_idx]),
    mu_hat = rep(NA_real_, length(keep_idx)),
    reservoir = reservoir,
    states = list(H_all = rolled$H_all, H_tilde = list(), decomposition = NULL),
    meta = meta
  )
  class(out) <- "qdesn_fit"
  out
}

app_qdesn_process_lag_buffer <- function(lag_buf, meta) {
  lag_buf <- as.numeric(lag_buf)
  if (!length(lag_buf)) return(numeric(0))
  standardize_inputs <- isTRUE(meta$standardize_inputs %||% FALSE)
  lag_center <- as.numeric(meta$lag_center %||% rep(0, length(lag_buf)))
  lag_scale <- as.numeric(meta$lag_scale %||% rep(1, length(lag_buf)))
  if (length(lag_center) == 1L) lag_center <- rep(lag_center, length(lag_buf))
  if (length(lag_scale) == 1L) lag_scale <- rep(lag_scale, length(lag_buf))
  if (length(lag_center) != length(lag_buf) || length(lag_scale) != length(lag_buf)) {
    stop("Lag scaling parameters do not match the reservoir lag buffer.", call. = FALSE)
  }
  if (any(!is.finite(lag_center)) || any(!is.finite(lag_scale)) || any(lag_scale <= 0)) {
    stop("Invalid lag scaling parameters for reservoir continuation.", call. = FALSE)
  }
  z <- lag_buf
  if (standardize_inputs) z <- (z - lag_center) / lag_scale
  win_scale_lags <- meta$win_scale_lags %||% NULL
  if (!is.null(win_scale_lags)) {
    win_scale_lags <- as.numeric(win_scale_lags)
    if (length(win_scale_lags) != length(z)) {
      stop("win_scale_lags does not match the reservoir lag buffer.", call. = FALSE)
    }
    z <- z * win_scale_lags
  }
  if (identical(as.character(meta$input_bound %||% "none")[[1L]], "tanh")) z <- tanh(z)
  z
}

app_qdesn_process_lag_buffer_with_jacobian <- function(lag_buf, d_lag_buf, meta) {
  lag_buf <- as.numeric(lag_buf)
  d_lag_buf <- as.matrix(d_lag_buf)
  storage.mode(d_lag_buf) <- "double"
  if (!length(lag_buf)) {
    return(list(value = numeric(0), jacobian = matrix(numeric(0), nrow = 0L, ncol = ncol(d_lag_buf))))
  }
  if (nrow(d_lag_buf) != length(lag_buf)) {
    stop("Lag-buffer derivative row count does not match the lag buffer.", call. = FALSE)
  }

  standardize_inputs <- isTRUE(meta$standardize_inputs %||% FALSE)
  lag_center <- as.numeric(meta$lag_center %||% rep(0, length(lag_buf)))
  lag_scale <- as.numeric(meta$lag_scale %||% rep(1, length(lag_buf)))
  if (length(lag_center) == 1L) lag_center <- rep(lag_center, length(lag_buf))
  if (length(lag_scale) == 1L) lag_scale <- rep(lag_scale, length(lag_buf))
  if (length(lag_center) != length(lag_buf) || length(lag_scale) != length(lag_buf)) {
    stop("Lag scaling parameters do not match the reservoir lag buffer.", call. = FALSE)
  }
  if (any(!is.finite(lag_center)) || any(!is.finite(lag_scale)) || any(lag_scale <= 0)) {
    stop("Invalid lag scaling parameters for reservoir continuation.", call. = FALSE)
  }

  z <- lag_buf
  J <- d_lag_buf
  if (standardize_inputs) {
    z <- (z - lag_center) / lag_scale
    J <- J / lag_scale
  }
  win_scale_lags <- meta$win_scale_lags %||% NULL
  if (!is.null(win_scale_lags)) {
    win_scale_lags <- as.numeric(win_scale_lags)
    if (length(win_scale_lags) != length(z)) {
      stop("win_scale_lags does not match the reservoir lag buffer.", call. = FALSE)
    }
    z <- z * win_scale_lags
    J <- J * win_scale_lags
  }
  if (identical(as.character(meta$input_bound %||% "none")[[1L]], "tanh")) {
    dz <- 1 - tanh(z)^2
    z <- tanh(z)
    J <- J * dz
  }
  list(value = z, jacobian = J)
}

app_qdesn_make_input_vector <- function(lag_buf, meta) {
  u <- c(1, app_qdesn_process_lag_buffer(lag_buf, meta))
  u[[1L]] <- u[[1L]] * as.numeric(meta$win_scale_bias %||% 1)
  if (length(u) > 1L) u[-1L] <- u[-1L] * as.numeric(meta$win_scale_global %||% 1)
  u
}

app_qdesn_make_input_vector_with_jacobian <- function(lag_buf, d_lag_buf, meta) {
  processed <- app_qdesn_process_lag_buffer_with_jacobian(lag_buf, d_lag_buf, meta)
  n_future <- ncol(processed$jacobian)
  u <- c(1, processed$value)
  J <- rbind(matrix(0, nrow = 1L, ncol = n_future), processed$jacobian)
  u[[1L]] <- u[[1L]] * as.numeric(meta$win_scale_bias %||% 1)
  if (length(u) > 1L) {
    scale_global <- as.numeric(meta$win_scale_global %||% 1)
    u[-1L] <- u[-1L] * scale_global
    J[-1L, ] <- J[-1L, , drop = FALSE] * scale_global
  }
  list(value = u, jacobian = J)
}

app_qdesn_readout_row_from_states <- function(states, reservoir) {
  D <- as.integer(reservoir$D)
  if (length(states) != D) stop("State list length does not match reservoir depth.", call. = FALSE)
  k_act <- app_qdesn_activation(reservoir$act_k %||% "identity")
  if (D == 1L) return(as.numeric(states[[1L]]))
  lower <- do.call(c, lapply(seq_len(D - 1L), function(d) {
    htilde <- if (isTRUE(reservoir$Q_is_identity[[d]])) {
      as.numeric(states[[d]])
    } else {
      as.numeric(reservoir$Q[[d]] %*% states[[d]])
    }
    k_act(htilde)
  }))
  c(as.numeric(states[[D]]), lower)
}

app_qdesn_readout_row_from_states_with_jacobian <- function(states, d_states, reservoir) {
  D <- as.integer(reservoir$D)
  if (length(states) != D || length(d_states) != D) {
    stop("State and derivative lists must match reservoir depth.", call. = FALSE)
  }
  k_act <- app_qdesn_activation(reservoir$act_k %||% "identity")
  k_deriv <- app_qdesn_activation_derivative(reservoir$act_k %||% "identity")

  if (D == 1L) {
    return(list(
      value = as.numeric(states[[1L]]),
      jacobian = as.matrix(d_states[[1L]])
    ))
  }

  values <- list(as.numeric(states[[D]]))
  jac <- list(as.matrix(d_states[[D]]))
  for (d in seq_len(D - 1L)) {
    htilde <- if (isTRUE(reservoir$Q_is_identity[[d]])) {
      as.numeric(states[[d]])
    } else {
      as.numeric(reservoir$Q[[d]] %*% states[[d]])
    }
    d_htilde <- if (isTRUE(reservoir$Q_is_identity[[d]])) {
      as.matrix(d_states[[d]])
    } else {
      reservoir$Q[[d]] %*% as.matrix(d_states[[d]])
    }
    values[[length(values) + 1L]] <- as.numeric(k_act(htilde))
    jac[[length(jac) + 1L]] <- d_htilde * as.numeric(k_deriv(htilde))
  }

  list(
    value = do.call(c, values),
    jacobian = do.call(rbind, jac)
  )
}

app_qdesn_validate_latent_continuation_contract <- function(qfit) {
  meta <- qfit$meta %||% list()
  if (!is.null(meta$reservoir_input_spec)) {
    spec <- meta$reservoir_input_spec
    if (!is.list(spec) || !length(spec$columns) || !is.finite(spec$m_input)) {
      stop("Covariate-aware reservoir continuation has an invalid reservoir_input_spec.", call. = FALSE)
    }
    return(invisible(TRUE))
  }
  cov_fields <- c(
    "reservoir_covariate_columns",
    "input_covariate_columns",
    "input_covariates",
    "covariate_columns"
  )
  has_covariates <- any(vapply(cov_fields, function(nm) {
    val <- meta[[nm]] %||% NULL
    !is.null(val) && length(val) > 0L
  }, logical(1L)))
  has_covariate_flag <- isTRUE(meta$reservoir_covariates_enabled %||% FALSE) ||
    isTRUE(meta$input_covariates_enabled %||% FALSE)
  if (isTRUE(has_covariates || has_covariate_flag)) {
    stop(
      paste(
        "Latent-path reservoir continuation currently supports output-lag",
        "reservoir inputs only. Add a covariate-aware continuation kernel",
        "before using covariates inside the reservoir recursion."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_qdesn_continue_latent_path_covariate <- function(
  qfit,
  y_history,
  y_future,
  initial_states = NULL,
  return_jacobian = FALSE,
  future_dates = NULL,
  covariate_timeline = NULL
) {
  reservoir <- qfit$reservoir %||% NULL
  meta <- qfit$meta %||% list()
  spec <- meta$reservoir_input_spec %||% NULL
  if (is.null(reservoir) || is.null(spec)) {
    stop("Covariate-aware continuation requires reservoir parameters and reservoir_input_spec.", call. = FALSE)
  }
  y_future <- as.numeric(y_future)
  if (any(!is.finite(y_future))) stop("Latent future path must be finite for state continuation.", call. = FALSE)
  n_future <- length(y_future)
  future_dates <- as.Date(future_dates %||% meta$future_dates %||% character(0))
  if (length(future_dates) != n_future || any(is.na(future_dates))) {
    stop("Covariate-aware continuation requires one future target date per latent future value.", call. = FALSE)
  }
  history_dates <- as.Date(meta$history_dates %||% character(0))
  y_history <- as.numeric(y_history)
  if (length(history_dates) != length(y_history)) {
    stop("Covariate-aware continuation requires qfit$meta$history_dates aligned with y_history.", call. = FALSE)
  }
  if (length(history_dates) != length(y_history) || any(is.na(history_dates))) {
    stop("Covariate-aware continuation requires historical target dates aligned with y_history.", call. = FALSE)
  }
  covariate_timeline <- covariate_timeline %||% meta$covariate_timeline %||% NULL
  if (isTRUE(spec$uses_covariates) && (is.null(covariate_timeline) || !nrow(covariate_timeline))) {
    stop("Covariate-aware continuation requires a covariate timeline.", call. = FALSE)
  }

  states <- initial_states %||% app_qdesn_last_states(qfit)
  d_states <- lapply(states, function(x) matrix(0, nrow = length(x), ncol = n_future))
  X <- matrix(NA_real_, nrow = n_future, ncol = length(app_qdesn_readout_row_from_states(states, reservoir)))
  input_rows <- matrix(NA_real_, nrow = n_future, ncol = spec$m_input)
  colnames(input_rows) <- spec$columns
  state_rows <- vector("list", n_future)
  J_rows <- vector("list", n_future)
  audit_rows <- vector("list", n_future)

  for (h in seq_len(n_future)) {
    row <- app_qdesn_reservoir_input_row(
      spec = spec,
      history_dates = history_dates,
      y_history = y_history,
      target_date = future_dates[[h]],
      covariate_timeline = covariate_timeline,
      future_dates = future_dates,
      y_future = y_future,
      h_current = h
    )
    input_rows[h, ] <- row$value
    audit_rows[[h]] <- row$audit
    if (isTRUE(return_jacobian)) {
      step <- app_qdesn_continue_one_step_with_jacobian(states, d_states, row$value, row$jacobian, reservoir, meta)
      states <- step$states
      d_states <- step$d_states
      readout <- app_qdesn_readout_row_from_states_with_jacobian(states, d_states, reservoir)
      X[h, ] <- readout$value
      J_rows[[h]] <- readout$jacobian
    } else {
      states <- app_qdesn_continue_one_step(states, row$value, reservoir, meta)
      X[h, ] <- app_qdesn_readout_row_from_states(states, reservoir)
    }
    state_rows[[h]] <- states
  }

  colnames(X) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(X))))
  audit <- app_bind_rows_fill(audit_rows)
  app_latent_path_validate_no_usgs_leakage(
    data.frame(date = audit$input_date, role = audit$role, stringsAsFactors = FALSE),
    cutoff_date = max(history_dates)
  )
  out <- list(
    X_future_core = X,
    states_future = state_rows,
    input_lag_matrix = input_rows,
    future_input_audit = audit,
    y_future = y_future,
    m_input = spec$m_input,
    n_future = n_future
  )
  if (isTRUE(return_jacobian)) {
    out$J_future_core <- J_rows
    out$strict_lag_jacobian <- TRUE
    out$covariate_jacobian_zero <- TRUE
  }
  class(out) <- "qdesn_latent_path_continuation"
  out
}

app_qdesn_continue_one_step <- function(states, lag_buf, reservoir, meta) {
  D <- as.integer(reservoir$D)
  alpha <- as.numeric(reservoir$alpha)
  f_act <- app_qdesn_activation(reservoir$act_f %||% "tanh")
  u_t <- app_qdesn_make_input_vector(lag_buf, meta)

  next_states <- states
  pre1 <- reservoir$W[[1L]] %*% states[[1L]] + reservoir$Win[[1L]] %*% u_t
  omega1 <- as.numeric(f_act(pre1))
  next_states[[1L]] <- (1 - alpha[[1L]]) * states[[1L]] + alpha[[1L]] * omega1

  if (D >= 2L) {
    for (d in 2:D) {
      htilde <- if (isTRUE(reservoir$Q_is_identity[[d - 1L]])) {
        as.numeric(next_states[[d - 1L]])
      } else {
        as.numeric(reservoir$Q[[d - 1L]] %*% next_states[[d - 1L]])
      }
      pred <- reservoir$W[[d]] %*% states[[d]] + reservoir$Win[[d]] %*% htilde
      omega <- as.numeric(f_act(pred))
      next_states[[d]] <- (1 - alpha[[d]]) * states[[d]] + alpha[[d]] * omega
    }
  }
  next_states
}

app_qdesn_continue_one_step_with_jacobian <- function(states, d_states, lag_buf, d_lag_buf, reservoir, meta) {
  D <- as.integer(reservoir$D)
  alpha <- as.numeric(reservoir$alpha)
  f_act <- app_qdesn_activation(reservoir$act_f %||% "tanh")
  f_deriv <- app_qdesn_activation_derivative(reservoir$act_f %||% "tanh")
  u <- app_qdesn_make_input_vector_with_jacobian(lag_buf, d_lag_buf, meta)

  next_states <- states
  next_d_states <- d_states

  pre1 <- as.numeric(reservoir$W[[1L]] %*% states[[1L]] + reservoir$Win[[1L]] %*% u$value)
  d_pre1 <- reservoir$W[[1L]] %*% as.matrix(d_states[[1L]]) +
    reservoir$Win[[1L]] %*% u$jacobian
  omega1 <- as.numeric(f_act(pre1))
  d_omega1 <- d_pre1 * as.numeric(f_deriv(pre1))
  next_states[[1L]] <- (1 - alpha[[1L]]) * states[[1L]] + alpha[[1L]] * omega1
  next_d_states[[1L]] <- (1 - alpha[[1L]]) * as.matrix(d_states[[1L]]) + alpha[[1L]] * d_omega1

  if (D >= 2L) {
    for (d in 2:D) {
      htilde <- if (isTRUE(reservoir$Q_is_identity[[d - 1L]])) {
        as.numeric(next_states[[d - 1L]])
      } else {
        as.numeric(reservoir$Q[[d - 1L]] %*% next_states[[d - 1L]])
      }
      d_htilde <- if (isTRUE(reservoir$Q_is_identity[[d - 1L]])) {
        as.matrix(next_d_states[[d - 1L]])
      } else {
        reservoir$Q[[d - 1L]] %*% as.matrix(next_d_states[[d - 1L]])
      }
      pred <- as.numeric(reservoir$W[[d]] %*% states[[d]] + reservoir$Win[[d]] %*% htilde)
      d_pred <- reservoir$W[[d]] %*% as.matrix(d_states[[d]]) +
        reservoir$Win[[d]] %*% d_htilde
      omega <- as.numeric(f_act(pred))
      d_omega <- d_pred * as.numeric(f_deriv(pred))
      next_states[[d]] <- (1 - alpha[[d]]) * states[[d]] + alpha[[d]] * omega
      next_d_states[[d]] <- (1 - alpha[[d]]) * as.matrix(d_states[[d]]) + alpha[[d]] * d_omega
    }
  }

  list(states = next_states, d_states = next_d_states)
}

app_qdesn_continue_latent_path <- function(
  qfit,
  y_history,
  y_future,
  initial_states = NULL,
  return_jacobian = FALSE,
  future_dates = NULL,
  covariate_timeline = NULL
) {
  app_qdesn_validate_latent_continuation_contract(qfit)
  if (!is.null((qfit$meta %||% list())$reservoir_input_spec)) {
    return(app_qdesn_continue_latent_path_covariate(
      qfit = qfit,
      y_history = y_history,
      y_future = y_future,
      initial_states = initial_states,
      return_jacobian = return_jacobian,
      future_dates = future_dates,
      covariate_timeline = covariate_timeline
    ))
  }
  reservoir <- qfit$reservoir %||% NULL
  meta <- qfit$meta %||% list()
  if (is.null(reservoir)) stop("Q-DESN object is missing reservoir parameters.", call. = FALSE)
  y_future <- as.numeric(y_future)
  if (any(!is.finite(y_future))) stop("Latent future path must be finite for state continuation.", call. = FALSE)
  m_input <- as.integer(meta$m_input %||% reservoir$m_input %||% reservoir$m %||% 0L)
  states <- initial_states %||% app_qdesn_last_states(qfit)
  lag_buf <- app_qdesn_lag_buffer(y_history, m_input)
  n_future <- length(y_future)
  d_states <- lapply(states, function(x) matrix(0, nrow = length(x), ncol = n_future))
  d_lag_buf <- if (m_input) matrix(0, nrow = m_input, ncol = n_future) else matrix(numeric(0), nrow = 0L, ncol = n_future)

  X <- matrix(NA_real_, nrow = n_future, ncol = length(app_qdesn_readout_row_from_states(states, reservoir)))
  state_rows <- vector("list", n_future)
  J_rows <- vector("list", n_future)
  input_rows <- if (m_input) matrix(NA_real_, nrow = n_future, ncol = m_input) else matrix(numeric(0), nrow = n_future, ncol = 0L)

  for (h in seq_along(y_future)) {
    if (m_input) input_rows[h, ] <- lag_buf
    if (isTRUE(return_jacobian)) {
      step <- app_qdesn_continue_one_step_with_jacobian(states, d_states, lag_buf, d_lag_buf, reservoir, meta)
      states <- step$states
      d_states <- step$d_states
      readout <- app_qdesn_readout_row_from_states_with_jacobian(states, d_states, reservoir)
      X[h, ] <- readout$value
      J_rows[[h]] <- readout$jacobian
    } else {
      states <- app_qdesn_continue_one_step(states, lag_buf, reservoir, meta)
      X[h, ] <- app_qdesn_readout_row_from_states(states, reservoir)
    }
    state_rows[[h]] <- states
    if (m_input) {
      keep <- seq_len(max(0L, m_input - 1L))
      lag_buf <- c(y_future[[h]], lag_buf[keep])
      e_h <- rep(0, n_future)
      e_h[[h]] <- 1
      d_lag_buf <- rbind(e_h, d_lag_buf[keep, , drop = FALSE])
    }
  }

  colnames(X) <- paste0("reservoir_", sprintf("%04d", seq_len(ncol(X))))
  if (m_input) colnames(input_rows) <- paste0("y_lag_", seq_len(m_input))
  out <- list(
    X_future_core = X,
    states_future = state_rows,
    input_lag_matrix = input_rows,
    y_future = y_future,
    m_input = m_input,
    n_future = length(y_future)
  )
  if (isTRUE(return_jacobian)) {
    out$J_future_core <- J_rows
    out$strict_lag_jacobian <- TRUE
  }
  class(out) <- "qdesn_latent_path_continuation"
  out
}

app_latent_path_validate_no_usgs_leakage <- function(future_inputs, cutoff_date) {
  if (is.null(future_inputs) || !nrow(future_inputs)) return(invisible(TRUE))
  if (!all(c("date", "role") %in% names(future_inputs))) {
    stop("Future input audit requires date and role columns.", call. = FALSE)
  }
  dates <- as.Date(future_inputs$date)
  roles <- as.character(future_inputs$role)
  bad <- dates > as.Date(cutoff_date) & roles %in% c("observed_usgs", "heldout_usgs", "future_observed_usgs")
  if (any(bad, na.rm = TRUE)) {
    stop("Future input audit found post-cutoff observed USGS values in model inputs.", call. = FALSE)
  }
  invisible(TRUE)
}
