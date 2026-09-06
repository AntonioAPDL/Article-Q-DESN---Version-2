// [[Rcpp::plugins(cpp14)]]
// [[Rcpp::depends(RcppArmadillo)]]

#include <RcppArmadillo.h>

using namespace Rcpp;
using namespace arma;

namespace {

arma::vec process_input(
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
      Rcpp::stop("Part 3 input scaling dimensions do not match.");
    }
    for (arma::uword j = 0; j < m; ++j) {
      if (!std::isfinite(scale[j]) || scale[j] <= 0.0) {
        Rcpp::stop("Part 3 input scale must be finite and positive.");
      }
      row[j] = (row[j] - center[j]) / scale[j];
    }
  }
  if (input_bound == "tanh") {
    row = arma::tanh(row);
  } else if (!(input_bound.empty() || input_bound == "none")) {
    Rcpp::stop("Unsupported Part 3 input bound.");
  }
  arma::vec out(m + 1L, arma::fill::ones);
  out[0] = win_scale_bias;
  if (m > 0L) out.subvec(1L, m) = win_scale_global * row;
  return out;
}

arma::vec activate(const arma::vec& x, const std::string& activation) {
  if (activation == "tanh") return arma::tanh(x);
  if (activation == "identity") return x;
  Rcpp::stop("Unsupported Part 3 reservoir activation.");
  return x;
}

void validate_component(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state0,
    const arma::mat& static_values,
    const arma::imat& future_index,
    const arma::vec& center,
    const arma::vec& scale,
    const double alpha,
    const std::string& label) {
  const arma::uword n = state0.n_elem;
  const arma::uword H = static_values.n_rows;
  const arma::uword m = static_values.n_cols;
  if (n == 0L || H == 0L || W.n_rows != n || W.n_cols != n ||
      Win.n_rows != n || Win.n_cols != m + 1L ||
      future_index.n_rows != H || future_index.n_cols != m ||
      center.n_elem != m || scale.n_elem != m) {
    Rcpp::stop("Part 3 " + label + " component dimensions are inconsistent.");
  }
  if (!std::isfinite(alpha) || alpha <= 0.0 || alpha > 1.0) {
    Rcpp::stop("Part 3 " + label + " alpha must lie in (0, 1].");
  }
}

void replace_recursive_lags(
    arma::vec& row,
    const arma::irowvec& future_index,
    const arma::vec& future_path,
    const arma::uword h,
    const std::string& label) {
  for (arma::uword j = 0; j < row.n_elem; ++j) {
    const int idx = future_index[j];
    if (idx > 0) {
      if (idx > static_cast<int>(h)) {
        Rcpp::stop("Part 3 " + label + " future index is non-causal.");
      }
      row[j] = future_path[static_cast<arma::uword>(idx - 1)];
    }
  }
}

arma::vec advance(
    const arma::mat& W,
    const arma::mat& Win,
    const arma::vec& state,
    const arma::vec& row,
    const arma::vec& center,
    const arma::vec& scale,
    const bool standardize,
    const std::string& input_bound,
    const double win_scale_global,
    const double win_scale_bias,
    const double alpha,
    const std::string& activation) {
  const arma::vec input = process_input(
    row, center, scale, standardize, input_bound,
    win_scale_global, win_scale_bias
  );
  const arma::vec proposal = activate(W * state + Win * input, activation);
  return (1.0 - alpha) * state + alpha * proposal;
}

double readout(const arma::rowvec& beta, const arma::vec& state) {
  double out = beta[0];
  for (arma::uword j = 0; j < state.n_elem; ++j) out += beta[j + 1L] * state[j];
  return out;
}

}  // namespace

// [[Rcpp::export]]
Rcpp::List glofas_part3_d1_quantile_recursive_cpp(
    const arma::mat& W_reference,
    const arma::mat& Win_reference,
    const arma::vec& state0_reference,
    const arma::mat& static_reference,
    const arma::imat& future_index_reference,
    const arma::vec& center_reference,
    const arma::vec& scale_reference,
    const bool standardize_reference,
    const std::string input_bound_reference,
    const double win_scale_global_reference,
    const double win_scale_bias_reference,
    const double alpha_reference,
    const std::string activation_reference,
    const arma::mat& beta_reference,
    const arma::mat& W_discrepancy,
    const arma::mat& Win_discrepancy,
    const arma::vec& state0_discrepancy,
    const arma::mat& static_discrepancy,
    const arma::imat& future_index_discrepancy,
    const arma::vec& center_discrepancy,
    const arma::vec& scale_discrepancy,
    const bool standardize_discrepancy,
    const std::string input_bound_discrepancy,
    const double win_scale_global_discrepancy,
    const double win_scale_bias_discrepancy,
    const double alpha_discrepancy,
    const std::string activation_discrepancy,
    const arma::mat& beta_discrepancy) {
  validate_component(
    W_reference, Win_reference, state0_reference, static_reference,
    future_index_reference, center_reference, scale_reference,
    alpha_reference, "reference"
  );
  validate_component(
    W_discrepancy, Win_discrepancy, state0_discrepancy, static_discrepancy,
    future_index_discrepancy, center_discrepancy, scale_discrepancy,
    alpha_discrepancy, "discrepancy"
  );
  const arma::uword H = static_reference.n_rows;
  const arma::uword K = beta_reference.n_rows;
  if (static_discrepancy.n_rows != H || K == 0L || beta_discrepancy.n_rows != K ||
      beta_reference.n_cols != state0_reference.n_elem + 1L ||
      beta_discrepancy.n_cols != state0_discrepancy.n_elem + 1L) {
    Rcpp::stop("Part 3 quantile forecast dimensions are inconsistent.");
  }

  arma::mat reference(H, K, arma::fill::zeros);
  arma::mat discrepancy(H, K, arma::fill::zeros);
  arma::mat glofas(H, K, arma::fill::zeros);

  for (arma::uword k = 0; k < K; ++k) {
    arma::vec state_reference = state0_reference;
    arma::vec state_discrepancy = state0_discrepancy;
    arma::vec future_reference(H, arma::fill::zeros);
    arma::vec future_discrepancy(H, arma::fill::zeros);
    for (arma::uword h = 0; h < H; ++h) {
      arma::vec input_reference = static_reference.row(h).t();
      arma::vec input_discrepancy = static_discrepancy.row(h).t();
      replace_recursive_lags(
        input_reference, future_index_reference.row(h), future_reference, h, "reference"
      );
      replace_recursive_lags(
        input_discrepancy, future_index_discrepancy.row(h), future_discrepancy, h, "discrepancy"
      );
      state_reference = advance(
        W_reference, Win_reference, state_reference, input_reference,
        center_reference, scale_reference, standardize_reference,
        input_bound_reference, win_scale_global_reference,
        win_scale_bias_reference, alpha_reference, activation_reference
      );
      state_discrepancy = advance(
        W_discrepancy, Win_discrepancy, state_discrepancy, input_discrepancy,
        center_discrepancy, scale_discrepancy, standardize_discrepancy,
        input_bound_discrepancy, win_scale_global_discrepancy,
        win_scale_bias_discrepancy, alpha_discrepancy, activation_discrepancy
      );
      const double q = readout(beta_reference.row(k), state_reference);
      const double d = readout(beta_discrepancy.row(k), state_discrepancy);
      reference(h, k) = q;
      discrepancy(h, k) = d;
      glofas(h, k) = q + d;
      future_reference[h] = q;
      future_discrepancy[h] = d;
    }
  }
  return Rcpp::List::create(
    Rcpp::_["reference"] = reference,
    Rcpp::_["discrepancy"] = discrepancy,
    Rcpp::_["glofas"] = glofas,
    Rcpp::_["backend"] = "cpp_d1_part3_quantile_recursive"
  );
}

// [[Rcpp::export]]
Rcpp::List glofas_part3_d1_normal_draw_recursive_cpp(
    const arma::mat& W_reference,
    const arma::mat& Win_reference,
    const arma::vec& state0_reference,
    const arma::mat& static_reference,
    const arma::imat& future_index_reference,
    const arma::vec& center_reference,
    const arma::vec& scale_reference,
    const bool standardize_reference,
    const std::string input_bound_reference,
    const double win_scale_global_reference,
    const double win_scale_bias_reference,
    const double alpha_reference,
    const std::string activation_reference,
    const arma::mat& beta_reference_draws,
    const arma::mat& W_discrepancy,
    const arma::mat& Win_discrepancy,
    const arma::vec& state0_discrepancy,
    const arma::mat& static_discrepancy,
    const arma::imat& future_index_discrepancy,
    const arma::vec& center_discrepancy,
    const arma::vec& scale_discrepancy,
    const bool standardize_discrepancy,
    const std::string input_bound_discrepancy,
    const double win_scale_global_discrepancy,
    const double win_scale_bias_discrepancy,
    const double alpha_discrepancy,
    const std::string activation_discrepancy,
    const arma::mat& beta_discrepancy_draws,
    const arma::vec& sigma_draws,
    const arma::mat& z_reference,
    const arma::mat& z_glofas) {
  validate_component(
    W_reference, Win_reference, state0_reference, static_reference,
    future_index_reference, center_reference, scale_reference,
    alpha_reference, "reference"
  );
  validate_component(
    W_discrepancy, Win_discrepancy, state0_discrepancy, static_discrepancy,
    future_index_discrepancy, center_discrepancy, scale_discrepancy,
    alpha_discrepancy, "discrepancy"
  );
  const arma::uword H = static_reference.n_rows;
  const arma::uword S = beta_reference_draws.n_rows;
  if (static_discrepancy.n_rows != H || S == 0L || beta_discrepancy_draws.n_rows != S ||
      beta_reference_draws.n_cols != state0_reference.n_elem + 1L ||
      beta_discrepancy_draws.n_cols != state0_discrepancy.n_elem + 1L ||
      sigma_draws.n_elem != S || z_reference.n_rows != H || z_reference.n_cols != S ||
      z_glofas.n_rows != H || z_glofas.n_cols != S) {
    Rcpp::stop("Part 3 Normal forecast dimensions are inconsistent.");
  }

  arma::mat reference_mean(H, S, arma::fill::zeros);
  arma::mat discrepancy_mean(H, S, arma::fill::zeros);
  arma::mat glofas_mean(H, S, arma::fill::zeros);
  arma::mat reference_draws(H, S, arma::fill::zeros);
  arma::mat discrepancy_draws(H, S, arma::fill::zeros);
  arma::mat glofas_draws(H, S, arma::fill::zeros);

  for (arma::uword s = 0; s < S; ++s) {
    if (!std::isfinite(sigma_draws[s]) || sigma_draws[s] <= 0.0) {
      Rcpp::stop("Part 3 Normal sigma draws must be finite and positive.");
    }
    arma::vec state_reference = state0_reference;
    arma::vec state_discrepancy = state0_discrepancy;
    arma::vec future_reference(H, arma::fill::zeros);
    arma::vec future_discrepancy(H, arma::fill::zeros);
    for (arma::uword h = 0; h < H; ++h) {
      arma::vec input_reference = static_reference.row(h).t();
      arma::vec input_discrepancy = static_discrepancy.row(h).t();
      replace_recursive_lags(
        input_reference, future_index_reference.row(h), future_reference, h, "reference"
      );
      replace_recursive_lags(
        input_discrepancy, future_index_discrepancy.row(h), future_discrepancy, h, "discrepancy"
      );
      state_reference = advance(
        W_reference, Win_reference, state_reference, input_reference,
        center_reference, scale_reference, standardize_reference,
        input_bound_reference, win_scale_global_reference,
        win_scale_bias_reference, alpha_reference, activation_reference
      );
      state_discrepancy = advance(
        W_discrepancy, Win_discrepancy, state_discrepancy, input_discrepancy,
        center_discrepancy, scale_discrepancy, standardize_discrepancy,
        input_bound_discrepancy, win_scale_global_discrepancy,
        win_scale_bias_discrepancy, alpha_discrepancy, activation_discrepancy
      );
      const double q = readout(beta_reference_draws.row(s), state_reference);
      const double d = readout(beta_discrepancy_draws.row(s), state_discrepancy);
      const double y = q + sigma_draws[s] * z_reference(h, s);
      const double g = q + d + sigma_draws[s] * z_glofas(h, s);
      const double observed_discrepancy = g - y;
      reference_mean(h, s) = q;
      discrepancy_mean(h, s) = d;
      glofas_mean(h, s) = q + d;
      reference_draws(h, s) = y;
      discrepancy_draws(h, s) = observed_discrepancy;
      glofas_draws(h, s) = g;
      future_reference[h] = y;
      future_discrepancy[h] = observed_discrepancy;
    }
  }
  return Rcpp::List::create(
    Rcpp::_["reference_mean_draws"] = reference_mean,
    Rcpp::_["discrepancy_mean_draws"] = discrepancy_mean,
    Rcpp::_["glofas_mean_draws"] = glofas_mean,
    Rcpp::_["reference_draws"] = reference_draws,
    Rcpp::_["discrepancy_draws"] = discrepancy_draws,
    Rcpp::_["glofas_draws"] = glofas_draws,
    Rcpp::_["backend"] = "cpp_d1_part3_normal_draw_recursive"
  );
}
