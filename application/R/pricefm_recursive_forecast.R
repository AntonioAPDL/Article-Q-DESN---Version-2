app_pricefm_with_seed <- function(seed, code) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))
  force(code)
}

app_pricefm_recursive_path_ids <- function(n_paths, prefix = "pricefm_path") {
  n_paths <- as.integer(n_paths)
  if (!is.finite(n_paths) || n_paths < 1L) stop("n_paths must be positive.", call. = FALSE)
  sprintf("%s_%06d", as.character(prefix), seq_len(n_paths))
}

app_pricefm_recursive_resume_plan <- function(requested_path_ids, completed_path_ids = character()) {
  requested <- as.character(requested_path_ids)
  completed <- as.character(completed_path_ids)
  if (anyNA(requested) || any(!nzchar(requested)) || anyDuplicated(requested)) {
    stop("requested path IDs must be non-empty and unique.", call. = FALSE)
  }
  if (anyNA(completed) || any(!nzchar(completed)) || anyDuplicated(completed)) {
    stop("completed path IDs must be non-empty and unique.", call. = FALSE)
  }
  unknown <- setdiff(completed, requested)
  if (length(unknown)) stop("completed path IDs are outside the requested contract.", call. = FALSE)
  list(
    requested_path_ids = requested,
    completed_path_ids = completed,
    pending_path_ids = requested[!requested %in% completed]
  )
}

app_pricefm_recursive_seed <- function(base_seed, path_index, horizon, region_index, stream = 0L) {
  values <- as.double(c(base_seed, path_index, horizon, region_index, stream))
  if (any(!is.finite(values)) || any(values < 0)) stop("seed coordinates must be finite and non-negative.", call. = FALSE)
  modulus <- 2147483646
  seed <- (values[[1L]] +
    1000003 * values[[2L]] +
    9176 * values[[3L]] +
    131 * values[[4L]] +
    7919 * values[[5L]]) %% modulus
  as.integer(seed + 1)
}

app_pricefm_recursive_validate <- function(initial_histories, initial_states, regions, horizon, n_paths) {
  regions <- as.character(regions)
  if (!length(regions) || anyNA(regions) || any(!nzchar(regions)) || anyDuplicated(regions)) {
    stop("regions must be non-empty and unique.", call. = FALSE)
  }
  if (!setequal(names(initial_histories), regions)) {
    stop("initial_histories must be named for exactly the declared regions.", call. = FALSE)
  }
  if (!setequal(names(initial_states), regions)) {
    stop("initial_states must be named for exactly the declared regions.", call. = FALSE)
  }
  history_lengths <- vapply(initial_histories[regions], length, integer(1L))
  if (any(history_lengths < 1L)) stop("initial histories must be non-empty.", call. = FALSE)
  if (any(vapply(initial_histories[regions], function(x) any(!is.finite(as.numeric(x))), logical(1L)))) {
    stop("initial histories must be finite.", call. = FALSE)
  }
  horizon <- as.integer(horizon)
  n_paths <- as.integer(n_paths)
  if (!is.finite(horizon) || horizon < 1L || !is.finite(n_paths) || n_paths < 1L) {
    stop("horizon and n_paths must be positive.", call. = FALSE)
  }
  invisible(TRUE)
}

app_pricefm_causal_teacher_forcing <- function(
  observed_prices,
  start_index,
  build_input,
  exogenous = NULL,
  regions = names(observed_prices),
  calculation_order = regions
) {
  regions <- as.character(regions)
  calculation_order <- as.character(calculation_order)
  if (!setequal(names(observed_prices), regions) || !setequal(calculation_order, regions)) {
    stop("observed prices and calculation order must match regions.", call. = FALSE)
  }
  lengths <- vapply(observed_prices[regions], length, integer(1L))
  if (length(unique(lengths)) != 1L || any(lengths < 2L)) {
    stop("observed regional price histories must be aligned.", call. = FALSE)
  }
  start_index <- as.integer(start_index)
  if (!is.function(build_input) || start_index < 2L || start_index > lengths[[1L]]) {
    stop("invalid causal teacher-forcing contract.", call. = FALSE)
  }
  inputs <- vector("list", (lengths[[1L]] - start_index + 1L) * length(regions))
  audit <- vector("list", length(inputs))
  pos <- 0L
  for (time_index in seq.int(start_index, lengths[[1L]])) {
    histories <- lapply(observed_prices[regions], function(x) as.numeric(x[seq_len(time_index - 1L)]))
    pending <- setNames(vector("list", length(regions)), regions)
    for (region in calculation_order) {
      pending[[region]] <- build_input(
        region = region,
        time_index = time_index,
        histories = histories,
        exogenous = exogenous
      )
    }
    for (region in calculation_order) {
      pos <- pos + 1L
      inputs[[pos]] <- pending[[region]]
      audit[[pos]] <- data.frame(
        region = region,
        time_index = time_index,
        information_end_index = time_index - 1L,
        response = as.numeric(observed_prices[[region]][[time_index]]),
        update_order = "predict_then_observe_y_t",
        stringsAsFactors = FALSE
      )
    }
  }
  list(inputs = inputs, audit = do.call(rbind, audit))
}

app_pricefm_recursive_panel <- function(
  initial_histories,
  initial_states,
  horizon,
  n_paths = 500L,
  parameter_draws,
  exogenous,
  build_input,
  transition_state,
  predict_location,
  draw_response,
  regions = names(initial_histories),
  calculation_order = regions,
  seed = 2026091601L,
  path_prefix = "pricefm_path",
  history_limits = setNames(vapply(initial_histories, length, integer(1L)), names(initial_histories))
) {
  regions <- as.character(regions)
  calculation_order <- as.character(calculation_order)
  app_pricefm_recursive_validate(initial_histories, initial_states, regions, horizon, n_paths)
  if (!setequal(calculation_order, regions) || anyDuplicated(calculation_order)) {
    stop("calculation_order must be a permutation of regions.", call. = FALSE)
  }
  if (!setequal(names(parameter_draws), regions)) {
    stop("parameter_draws must be named for exactly the declared regions.", call. = FALSE)
  }
  if (!setequal(names(history_limits), regions)) {
    stop("history_limits must be named for exactly the declared regions.", call. = FALSE)
  }
  history_limits <- as.integer(history_limits[regions])
  names(history_limits) <- regions
  if (any(!is.finite(history_limits)) || any(history_limits < 1L)) {
    stop("history limits must be positive.", call. = FALSE)
  }
  if (any(vapply(parameter_draws[regions], length, integer(1L)) != n_paths)) {
    stop("each region must provide one parameter draw per path.", call. = FALSE)
  }
  for (callback in list(build_input, transition_state, predict_location, draw_response)) {
    if (!is.function(callback)) stop("all recursive callbacks must be functions.", call. = FALSE)
  }

  horizon <- as.integer(horizon)
  n_paths <- as.integer(n_paths)
  path_ids <- app_pricefm_recursive_path_ids(n_paths, path_prefix)
  region_index <- setNames(seq_along(regions), regions)
  response <- array(
    NA_real_, dim = c(n_paths, horizon, length(regions)),
    dimnames = list(path_id = path_ids, horizon = as.character(seq_len(horizon)), region = regions)
  )
  location <- response
  histories <- lapply(regions, function(region) {
    x <- utils::tail(as.numeric(initial_histories[[region]]), history_limits[[region]])
    matrix(rep(as.numeric(x), each = n_paths), nrow = n_paths, byrow = FALSE)
  })
  names(histories) <- regions
  states <- lapply(initial_states[regions], function(x) rep(list(x), n_paths))
  input_audit <- vector("list", n_paths * horizon * length(regions))
  seed_rows <- vector("list", n_paths * horizon * length(regions))
  audit_pos <- 0L

  for (h in seq_len(horizon)) {
    for (s in seq_len(n_paths)) {
      snapshot <- lapply(histories, function(x) as.numeric(x[s, , drop = TRUE]))
      names(snapshot) <- regions
      pending <- setNames(vector("list", length(regions)), regions)

      # Every region is evaluated from the same h-1 panel snapshot.  No draw is
      # appended until all locations and states have been computed.
      for (region in calculation_order) {
        parameter <- parameter_draws[[region]][[s]]
        input <- build_input(
          region = region,
          horizon = h,
          path_id = path_ids[[s]],
          histories = snapshot,
          exogenous = exogenous,
          parameter = parameter
        )
        next_state <- transition_state(
          region = region,
          state = states[[region]][[s]],
          input = input,
          horizon = h,
          path_id = path_ids[[s]],
          parameter = parameter
        )
        mu <- as.numeric(predict_location(
          region = region,
          state = next_state,
          input = input,
          horizon = h,
          path_id = path_ids[[s]],
          parameter = parameter
        ))
        if (length(mu) != 1L || !is.finite(mu)) stop("non-finite recursive location.", call. = FALSE)
        pending[[region]] <- list(input = input, state = next_state, location = mu, parameter = parameter)
      }

      for (region in calculation_order) {
        item <- pending[[region]]
        innovation_seed <- app_pricefm_recursive_seed(
          seed, s, h, region_index[[region]], stream = 1L
        )
        y <- app_pricefm_with_seed(innovation_seed, as.numeric(draw_response(
          region = region,
          location = item$location,
          state = item$state,
          input = item$input,
          horizon = h,
          path_id = path_ids[[s]],
          parameter = item$parameter
        )))
        if (length(y) != 1L || !is.finite(y)) stop("non-finite recursive response draw.", call. = FALSE)
        response[s, h, region] <- y
        location[s, h, region] <- item$location
        states[[region]][[s]] <- item$state
        audit_pos <- audit_pos + 1L
        input_audit[[audit_pos]] <- data.frame(
          path_id = path_ids[[s]], horizon = h, region = region,
          history_length_before_update = length(snapshot[[region]]),
          panel_snapshot = "all_regions_h_minus_1", stringsAsFactors = FALSE
        )
        seed_rows[[audit_pos]] <- data.frame(
          path_id = path_ids[[s]], horizon = h, region = region,
          innovation_seed = innovation_seed, stringsAsFactors = FALSE
        )
      }
    }
    for (region in regions) {
      histories[[region]] <- cbind(histories[[region]], response[, h, region])
      if (ncol(histories[[region]]) > history_limits[[region]]) {
        histories[[region]] <- histories[[region]][, seq.int(ncol(histories[[region]]) - history_limits[[region]] + 1L, ncol(histories[[region]])), drop = FALSE]
      }
    }
  }

  seed_ledger <- do.call(rbind, seed_rows)
  input_audit <- do.call(rbind, input_audit)
  seed_ledger <- seed_ledger[order(seed_ledger$path_id, seed_ledger$horizon, match(seed_ledger$region, regions)), , drop = FALSE]
  input_audit <- input_audit[order(input_audit$path_id, input_audit$horizon, match(input_audit$region, regions)), , drop = FALSE]
  rownames(seed_ledger) <- NULL
  rownames(input_audit) <- NULL

  list(
    response_draws = response,
    location_draws = location,
    final_histories = histories,
    final_states = states,
    path_ids = path_ids,
    seed_ledger = seed_ledger,
    input_audit = input_audit,
    contract = list(
      engine = "pricefm_synchronous_panel_recursive_v1",
      regions = regions,
      calculation_order = calculation_order,
      horizon = horizon,
      n_paths = n_paths,
      base_seed = as.integer(seed),
      history_limits = history_limits,
      update_order = "build_all_predict_all_draw_all_then_update_all"
    )
  )
}

app_pricefm_quantile_on_common_driver <- function(
  common_driver,
  tau,
  evaluate_quantile,
  parameter_draws,
  regions = dimnames(common_driver$response_draws)$region
) {
  if (!is.function(evaluate_quantile)) stop("evaluate_quantile must be a function.", call. = FALSE)
  tau <- as.numeric(tau)
  if (!length(tau) || any(!is.finite(tau)) || any(tau <= 0 | tau >= 1)) {
    stop("tau must lie strictly between zero and one.", call. = FALSE)
  }
  driver <- common_driver$response_draws
  if (length(dim(driver)) != 3L) stop("common driver must be a path-by-horizon-by-region array.", call. = FALSE)
  regions <- as.character(regions)
  if (!setequal(regions, dimnames(driver)$region)) stop("common-driver regions disagree.", call. = FALSE)
  out <- array(
    NA_real_,
    dim = c(dim(driver)[1L], dim(driver)[2L], length(regions), length(tau)),
    dimnames = list(
      path_id = dimnames(driver)$path_id,
      horizon = dimnames(driver)$horizon,
      region = regions,
      tau = format(tau, trim = TRUE)
    )
  )
  frozen_driver <- driver
  for (region in regions) for (s in seq_len(dim(driver)[1L])) for (h in seq_len(dim(driver)[2L])) {
    for (k in seq_along(tau)) {
      value <- evaluate_quantile(
        region = region,
        horizon = h,
        path_id = dimnames(driver)$path_id[[s]],
        tau = tau[[k]],
        common_driver = driver,
        parameter = parameter_draws[[region]][[s]]
      )
      out[s, h, region, k] <- as.numeric(value)
    }
  }
  if (!identical(driver, frozen_driver)) stop("quantile evaluation mutated the common driver.", call. = FALSE)
  list(
    conditional_quantile_draws = out,
    common_driver_path_ids = dimnames(driver)$path_id,
    contract = "quantile_outputs_do_not_feed_primary_endogenous_path"
  )
}

app_pricefm_mixture_quantile <- function(cdf_functions, tau, lower, upper, tol = 1e-8) {
  if (!length(cdf_functions) || any(!vapply(cdf_functions, is.function, logical(1L)))) {
    stop("cdf_functions must be a non-empty list of functions.", call. = FALSE)
  }
  tau <- as.numeric(tau)
  mixture_cdf <- function(x) mean(vapply(cdf_functions, function(fun) fun(x), numeric(1L))) - tau
  stats::uniroot(mixture_cdf, lower = lower, upper = upper, tol = tol)$root
}
