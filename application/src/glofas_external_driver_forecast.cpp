// [[Rcpp::plugins(cpp14)]]
// [[Rcpp::depends(RcppArmadillo)]]

#include <RcppArmadillo.h>

namespace {

arma::vec external_driver_input(
    arma::vec row,
    const arma::vec& center,
    const arma::vec& scale,
    const bool standardize,
    const std::string& input_bound,
    const double global_scale,
    const double bias_scale) {
  const arma::uword m = row.n_elem;
  if (standardize) {
    if (center.n_elem != m || scale.n_elem != m) {
      Rcpp::stop("external-driver input scaling dimensions do not match");
    }
    for (arma::uword j = 0; j < m; ++j) {
      if (!std::isfinite(scale[j]) || scale[j] <= 0.0) {
        Rcpp::stop("external-driver input scale must be finite and positive");
      }
      row[j] = (row[j] - center[j]) / scale[j];
    }
  }
  if (input_bound == "tanh") {
    row = arma::tanh(row);
  } else if (!(input_bound.empty() || input_bound == "none")) {
    Rcpp::stop("unsupported external-driver input bound");
  }
  arma::vec out(m + 1L, arma::fill::ones);
  out[0] = bias_scale;
  if (m) out.subvec(1L, m) = global_scale * row;
  return out;
}

arma::vec external_driver_activation(const arma::vec& x, const std::string& activation) {
  if (activation == "tanh") return arma::tanh(x);
  if (activation == "identity") return x;
  Rcpp::stop("unsupported external-driver reservoir activation");
  return x;
}

}  // namespace

// Evaluate one D=1 DESN readout along externally supplied recursive response
// paths. Each column is one aligned driver/parameter trajectory.
// [[Rcpp::export]]
Rcpp::List glofas_d1_external_driver_forecast_cpp(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state0,
    const arma::mat& static_values,
    const arma::imat& future_index,
    const arma::mat& driver_paths,
    const arma::mat& beta_draws,
    const arma::vec& lag_center,
    const arma::vec& lag_scale,
    const bool standardize_inputs,
    const std::string input_bound,
    const double win_scale_global,
    const double win_scale_bias,
    const double alpha,
    const std::string activation = "tanh") {
  const arma::uword H = static_values.n_rows;
  const arma::uword m = static_values.n_cols;
  const arma::uword n = state0.n_elem;
  const arma::uword S = driver_paths.n_cols;
  if (!H || !n || !S || driver_paths.n_rows != H) {
    Rcpp::stop("external-driver horizon, state, and path count must be positive and aligned");
  }
  if (W.n_rows != n || W.n_cols != n || Win.n_rows != n || Win.n_cols != m + 1L) {
    Rcpp::stop("external-driver reservoir dimensions do not match");
  }
  if (future_index.n_rows != H || future_index.n_cols != m) {
    Rcpp::stop("external-driver future-index dimensions do not match static inputs");
  }
  if (beta_draws.n_rows != S || beta_draws.n_cols != n + 1L) {
    Rcpp::stop("external-driver beta draws must be S x (n + 1)");
  }
  if (lag_center.n_elem != m || lag_scale.n_elem != m) {
    Rcpp::stop("external-driver center/scale dimensions do not match inputs");
  }
  if (!std::isfinite(alpha) || alpha <= 0.0 || alpha > 1.0) {
    Rcpp::stop("external-driver leaking rate must lie in (0, 1]");
  }

  arma::mat quantile_paths(H, S, arma::fill::zeros);
  arma::mat input_sum(H, m, arma::fill::zeros);
  for (arma::uword s = 0; s < S; ++s) {
    arma::vec state = state0;
    for (arma::uword h = 0; h < H; ++h) {
      arma::vec row = static_values.row(h).t();
      for (arma::uword j = 0; j < m; ++j) {
        const int idx = future_index(h, j);
        if (idx > 0) {
          if (idx > static_cast<int>(h)) {
            Rcpp::stop("external-driver future index is non-causal");
          }
          row[j] = driver_paths(static_cast<arma::uword>(idx - 1), s);
        }
      }
      input_sum.row(h) += row.t();
      const arma::vec input = external_driver_input(
        row, lag_center, lag_scale, standardize_inputs, input_bound,
        win_scale_global, win_scale_bias
      );
      const arma::vec proposal = external_driver_activation(W * state + Win * input, activation);
      state = (1.0 - alpha) * state + alpha * proposal;
      double value = beta_draws(s, 0);
      for (arma::uword j = 0; j < n; ++j) value += state[j] * beta_draws(s, j + 1L);
      quantile_paths(h, s) = value;
    }
  }
  return Rcpp::List::create(
    Rcpp::_ ["quantile_paths"] = quantile_paths,
    Rcpp::_ ["input_mean"] = input_sum / static_cast<double>(S),
    Rcpp::_ ["backend"] = "cpp_d1_external_normal_driver"
  );
}
