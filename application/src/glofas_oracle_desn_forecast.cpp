// [[Rcpp::plugins(cpp14)]]
// [[Rcpp::depends(RcppArmadillo)]]

#include <RcppArmadillo.h>

using namespace Rcpp;
using namespace arma;

namespace {

inline arma::vec process_input_row(
    arma::vec row,
    const arma::vec& center,
    const arma::vec& scale,
    const bool standardize,
    const std::string& input_bound,
    const double win_scale_global,
    const double win_scale_bias) {
  const arma::uword m = row.n_elem;
  if (standardize) {
    if (center.n_elem != m || scale.n_elem != m) {
      Rcpp::stop("glofas_oracle_d1_forecast_cpp: input scaling dimensions mismatch");
    }
    for (arma::uword j = 0; j < m; ++j) {
      const double sj = scale[j];
      if (!std::isfinite(sj) || sj <= 0.0) {
        Rcpp::stop("glofas_oracle_d1_forecast_cpp: non-positive input scale");
      }
      row[j] = (row[j] - center[j]) / sj;
    }
  }
  if (input_bound == "tanh") {
    row = arma::tanh(row);
  } else if (!(input_bound.empty() || input_bound == "none")) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: unsupported input_bound");
  }
  arma::vec u(m + 1L, arma::fill::ones);
  u[0] = win_scale_bias;
  if (m > 0L) {
    u.subvec(1L, m) = row * win_scale_global;
  }
  return u;
}

inline arma::vec activate(const arma::vec& x, const std::string& act_f) {
  if (act_f == "tanh") return arma::tanh(x);
  if (act_f == "identity") return x;
  Rcpp::stop("glofas_oracle_d1_forecast_cpp: unsupported activation");
  return x;
}

inline void validate_common(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state0,
    const arma::mat& static_values,
    const arma::imat& future_index,
    const arma::vec& center,
    const arma::vec& scale,
    const double alpha) {
  const arma::uword n = state0.n_elem;
  const arma::uword H = static_values.n_rows;
  const arma::uword m = static_values.n_cols;
  if (n == 0L || H == 0L) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: state and horizon must be non-empty");
  }
  if (W.n_rows != n || W.n_cols != n) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: W must be n x n");
  }
  if (Win.n_rows != n || Win.n_cols != m + 1L) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: Win must be n x (m + 1)");
  }
  if (future_index.n_rows != H || future_index.n_cols != m) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: future_index must match static_values");
  }
  if (center.n_elem != m || scale.n_elem != m) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: center/scale length must equal m");
  }
  if (!std::isfinite(alpha) || alpha <= 0.0 || alpha >= 1.0) {
    Rcpp::stop("glofas_oracle_d1_forecast_cpp: alpha must lie in (0, 1)");
  }
}

}  // namespace

// [[Rcpp::export]]
Rcpp::List glofas_oracle_d1_draw_recursive_cpp(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state0,
    const arma::mat& static_values,
    const arma::imat& future_index,
    const arma::vec& lag_center,
    const arma::vec& lag_scale,
    const bool standardize_inputs,
    const std::string input_bound,
    const double win_scale_global,
    const double win_scale_bias,
    const double alpha,
    const arma::mat& beta_draws,
    const arma::vec& sigma_draws,
    const arma::mat& z_obs,
    const std::string act_f = "tanh") {
  validate_common(W, Win, state0, static_values, future_index, lag_center, lag_scale, alpha);
  const arma::uword H = static_values.n_rows;
  const arma::uword m = static_values.n_cols;
  const arma::uword n = state0.n_elem;
  const arma::uword S = beta_draws.n_rows;
  if (S == 0L || beta_draws.n_cols != n + 1L) {
    Rcpp::stop("glofas_oracle_d1_draw_recursive_cpp: beta_draws must be S x (n + 1)");
  }
  if (sigma_draws.n_elem != S || z_obs.n_rows != H || z_obs.n_cols != S) {
    Rcpp::stop("glofas_oracle_d1_draw_recursive_cpp: sigma/z dimensions mismatch");
  }

  arma::mat y_draws(H, S, arma::fill::zeros);
  arma::mat mu_draws(H, S, arma::fill::zeros);
  arma::mat input_sum(H, m, arma::fill::zeros);

  for (arma::uword s = 0; s < S; ++s) {
    arma::vec state = state0;
    arma::vec y_future(H, arma::fill::zeros);
    const arma::rowvec beta_s = beta_draws.row(s);
    const double sigma_s = sigma_draws[s];
    if (!std::isfinite(sigma_s) || sigma_s <= 0.0) {
      Rcpp::stop("glofas_oracle_d1_draw_recursive_cpp: sigma draws must be positive");
    }

    for (arma::uword h = 0; h < H; ++h) {
      arma::vec row = static_values.row(h).t();
      for (arma::uword j = 0; j < m; ++j) {
        const int idx = future_index(h, j);
        if (idx > 0) {
          if (idx > static_cast<int>(h)) {
            Rcpp::stop("glofas_oracle_d1_draw_recursive_cpp: non-causal future index");
          }
          row[j] = y_future[static_cast<arma::uword>(idx - 1)];
        }
      }
      input_sum.row(h) += row.t();
      arma::vec u = process_input_row(
        row,
        lag_center,
        lag_scale,
        standardize_inputs,
        input_bound,
        win_scale_global,
        win_scale_bias
      );
      arma::vec pre = W * state + Win * u;
      arma::vec omega = activate(pre, act_f);
      state = (1.0 - alpha) * state + alpha * omega;

      double mu = beta_s[0];
      for (arma::uword j = 0; j < n; ++j) {
        mu += state[j] * beta_s[j + 1L];
      }
      const double y = mu + sigma_s * z_obs(h, s);
      mu_draws(h, s) = mu;
      y_draws(h, s) = y;
      y_future[h] = y;
    }
  }

  return Rcpp::List::create(
    Rcpp::_["forecast_draws"] = y_draws,
    Rcpp::_["conditional_mean_draws"] = mu_draws,
    Rcpp::_["input_mean"] = input_sum / static_cast<double>(S),
    Rcpp::_["backend"] = "cpp_d1_draw_recursive"
  );
}

// [[Rcpp::export]]
Rcpp::List glofas_oracle_d1_plugin_recursive_cpp(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state0,
    const arma::mat& static_values,
    const arma::imat& future_index,
    const arma::vec& lag_center,
    const arma::vec& lag_scale,
    const bool standardize_inputs,
    const std::string input_bound,
    const double win_scale_global,
    const double win_scale_bias,
    const double alpha,
    const arma::vec& beta_mean,
    const std::string act_f = "tanh") {
  validate_common(W, Win, state0, static_values, future_index, lag_center, lag_scale, alpha);
  const arma::uword H = static_values.n_rows;
  const arma::uword m = static_values.n_cols;
  const arma::uword n = state0.n_elem;
  if (beta_mean.n_elem != n + 1L) {
    Rcpp::stop("glofas_oracle_d1_plugin_recursive_cpp: beta_mean must have length n + 1");
  }

  arma::mat X_future(H, n + 1L, arma::fill::ones);
  arma::mat input_rows(H, m, arma::fill::zeros);
  arma::vec pred_mean(H, arma::fill::zeros);
  arma::vec y_future(H, arma::fill::zeros);
  arma::vec state = state0;

  for (arma::uword h = 0; h < H; ++h) {
    arma::vec row = static_values.row(h).t();
    for (arma::uword j = 0; j < m; ++j) {
      const int idx = future_index(h, j);
      if (idx > 0) {
        if (idx > static_cast<int>(h)) {
          Rcpp::stop("glofas_oracle_d1_plugin_recursive_cpp: non-causal future index");
        }
        row[j] = y_future[static_cast<arma::uword>(idx - 1)];
      }
    }
    input_rows.row(h) = row.t();
    arma::vec u = process_input_row(
      row,
      lag_center,
      lag_scale,
      standardize_inputs,
      input_bound,
      win_scale_global,
      win_scale_bias
    );
    arma::vec pre = W * state + Win * u;
    arma::vec omega = activate(pre, act_f);
    state = (1.0 - alpha) * state + alpha * omega;
    X_future(h, 0) = 1.0;
    for (arma::uword j = 0; j < n; ++j) X_future(h, j + 1L) = state[j];
    const double mu = arma::dot(X_future.row(h), beta_mean.t());
    pred_mean[h] = mu;
    y_future[h] = mu;
  }

  return Rcpp::List::create(
    Rcpp::_["pred_mean"] = pred_mean,
    Rcpp::_["X_future"] = X_future,
    Rcpp::_["input_rows"] = input_rows,
    Rcpp::_["backend"] = "cpp_d1_plugin_recursive"
  );
}
