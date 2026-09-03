// [[Rcpp::plugins(cpp14)]]
// [[Rcpp::depends(RcppArmadillo)]]

#include <RcppArmadillo.h>

using namespace Rcpp;
using namespace arma;

namespace {

struct GlofasDlmStabStats {
  int calls = 0;
  int cov_projected = 0;
  int cov_floor_clipped = 0;
  int cov_cap_clipped = 0;
  int cov_nonfinite_inputs = 0;
  int inv_sympd_failed = 0;
  int inv_svd_used = 0;
};

inline arma::mat symmetrize_mat(const arma::mat& x) {
  return 0.5 * (x + x.t());
}

inline arma::mat regularize_mat(const arma::mat& x, const double eps) {
  return x + std::max(eps, 0.0) * arma::eye<arma::mat>(x.n_rows, x.n_cols);
}

inline arma::mat stabilize_covariance_cpp(
    const arma::mat& x,
    const double eig_floor,
    const double eig_cap,
    const double diag_jitter,
    GlofasDlmStabStats* stats) {
  if (stats != nullptr) stats->calls += 1;

  arma::mat sx = symmetrize_mat(x);
  if (!sx.is_finite()) {
    sx.transform([](double v) { return std::isfinite(v) ? v : 0.0; });
    if (stats != nullptr) stats->cov_nonfinite_inputs += 1;
  }

  if (sx.n_rows != sx.n_cols || sx.n_rows == 0) {
    return arma::eye<arma::mat>(sx.n_rows, sx.n_cols) * eig_floor;
  }

  arma::vec eig_vals;
  arma::mat eig_vecs;
  bool eig_ok = arma::eig_sym(eig_vals, eig_vecs, sx);
  bool needs_projection = !eig_ok || !eig_vals.is_finite() || !eig_vecs.is_finite();
  bool floor_hit = needs_projection;
  bool cap_hit = needs_projection;

  if (eig_ok && eig_vals.is_finite()) {
    const double min_eval = eig_vals.min();
    const double max_eval = eig_vals.max();
    floor_hit = (!std::isfinite(min_eval) || min_eval < eig_floor);
    cap_hit = (!std::isfinite(max_eval) || max_eval > eig_cap);
    needs_projection = floor_hit || cap_hit;
  }

  arma::mat out = sx;
  if (needs_projection) {
    if (stats != nullptr) {
      stats->cov_projected += 1;
      if (floor_hit) stats->cov_floor_clipped += 1;
      if (cap_hit) stats->cov_cap_clipped += 1;
    }
    if (eig_ok && eig_vals.is_finite() && eig_vecs.is_finite()) {
      eig_vals.transform([eig_floor, eig_cap](double v) {
        if (!std::isfinite(v)) return eig_floor;
        if (v < eig_floor) return eig_floor;
        if (v > eig_cap) return eig_cap;
        return v;
      });
      out = eig_vecs * arma::diagmat(eig_vals) * eig_vecs.t();
    } else {
      out = arma::eye<arma::mat>(sx.n_rows, sx.n_cols) * eig_floor;
    }
  }

  arma::mat stabilized = regularize_mat(symmetrize_mat(out), diag_jitter);
  for (int iter = 0; iter < 3; ++iter) {
    arma::vec vals;
    bool ok = arma::eig_sym(vals, stabilized);
    const double min_eval = (ok && vals.is_finite()) ? vals.min() : arma::datum::nan;
    if (std::isfinite(min_eval) && min_eval >= eig_floor) break;
    double shift = eig_floor;
    if (std::isfinite(min_eval)) shift = eig_floor - min_eval;
    if (!std::isfinite(shift) || shift < 0.0) shift = eig_floor;
    stabilized += (shift + std::max(diag_jitter, 0.0)) *
      arma::eye<arma::mat>(stabilized.n_rows, stabilized.n_cols);
    if (stats != nullptr) {
      if (stats->cov_projected == 0) stats->cov_projected += 1;
      if (stats->cov_floor_clipped == 0) stats->cov_floor_clipped += 1;
    }
  }
  return symmetrize_mat(stabilized);
}

inline arma::mat robust_svd_inv_cpp(const arma::mat& x, const double tolerance) {
  arma::mat U, V;
  arma::vec s;
  if (!arma::svd(U, s, V, x)) {
    Rcpp::stop("glofas structural DLM backend: SVD failed during robust inverse");
  }
  arma::vec s_inv = s;
  const double tol = std::max(tolerance, 1e-14);
  for (arma::uword i = 0; i < s.n_elem; ++i) {
    double si = std::abs(s[i]);
    if (!std::isfinite(si) || si < tol) si = tol;
    s_inv[i] = 1.0 / si;
  }
  return V * arma::diagmat(s_inv) * U.t();
}

inline arma::mat safe_inv_cpp(
    const arma::mat& x,
    const double diag_jitter,
    GlofasDlmStabStats* stats) {
  arma::mat sx = symmetrize_mat(x);
  arma::mat inv_try;
  bool ok = arma::inv_sympd(inv_try, sx);
  if (ok && inv_try.is_finite()) return inv_try;

  if (stats != nullptr) stats->inv_sympd_failed += 1;
  arma::mat reg = regularize_mat(sx, std::max(diag_jitter, 1e-8));
  ok = arma::inv_sympd(inv_try, reg);
  if (ok && inv_try.is_finite()) return inv_try;

  if (stats != nullptr) stats->inv_svd_used += 1;
  arma::mat inv_svd = robust_svd_inv_cpp(reg, 1e-12);
  if (!inv_svd.is_finite()) {
    Rcpp::stop("glofas structural DLM backend: robust SVD inverse produced non-finite output");
  }
  return inv_svd;
}

inline Rcpp::List stats_as_list(const GlofasDlmStabStats& stats) {
  return Rcpp::List::create(
    Rcpp::_["calls"] = stats.calls,
    Rcpp::_["cov_projected"] = stats.cov_projected,
    Rcpp::_["cov_floor_clipped"] = stats.cov_floor_clipped,
    Rcpp::_["cov_cap_clipped"] = stats.cov_cap_clipped,
    Rcpp::_["cov_nonfinite_inputs"] = stats.cov_nonfinite_inputs,
    Rcpp::_["inv_sympd_failed"] = stats.inv_sympd_failed,
    Rcpp::_["inv_svd_used"] = stats.inv_svd_used
  );
}

}  // namespace

// [[Rcpp::export]]
Rcpp::List glofas_structural_dlm_safe_inv_cpp(
    const arma::mat& x,
    const double cov_eig_floor = 1e-8,
    const double cov_eig_cap = 1e8,
    const double cov_diag_jitter = 1e-10) {
  GlofasDlmStabStats stats;
  arma::mat sx = stabilize_covariance_cpp(
    x,
    cov_eig_floor,
    cov_eig_cap,
    cov_diag_jitter,
    &stats
  );
  arma::mat inv_x = safe_inv_cpp(sx, cov_diag_jitter, &stats);
  return Rcpp::List::create(
    Rcpp::_["inverse"] = inv_x,
    Rcpp::_["stabilization"] = stats_as_list(stats)
  );
}

// [[Rcpp::export]]
Rcpp::List glofas_structural_dlm_filter_forward_cpp(
    const arma::vec& y,
    const arma::mat& F_mat,
    const arma::cube& G_array,
    const arma::mat& discount_scale_mat,
    const arma::vec& m0,
    const arma::mat& C0_star_in,
    const double n0,
    const double S0,
    const double cov_eig_floor = 1e-8,
    const double cov_eig_cap = 1e8,
    const double cov_diag_jitter = 1e-10) {
  const int Tn = static_cast<int>(y.n_elem);
  const int p = static_cast<int>(m0.n_elem);
  if (Tn <= 0) Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: y must be nonempty");
  if (p <= 0) Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: state dimension must be positive");
  if (F_mat.n_rows != static_cast<arma::uword>(Tn) ||
      F_mat.n_cols != static_cast<arma::uword>(p)) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: F_mat must be T x p");
  }
  if (G_array.n_rows != static_cast<arma::uword>(p) ||
      G_array.n_cols != static_cast<arma::uword>(p) ||
      G_array.n_slices != static_cast<arma::uword>(Tn)) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: G_array must be p x p x T");
  }
  if (discount_scale_mat.n_rows != static_cast<arma::uword>(p) ||
      discount_scale_mat.n_cols != static_cast<arma::uword>(p)) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: discount_scale_mat must be p x p");
  }
  if (C0_star_in.n_rows != static_cast<arma::uword>(p) ||
      C0_star_in.n_cols != static_cast<arma::uword>(p)) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: C0_star must be p x p");
  }
  if (!std::isfinite(n0) || n0 <= 0.0) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: n0 must be finite and positive");
  }
  if (!std::isfinite(S0) || S0 <= 0.0) {
    Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: S0 must be finite and positive");
  }

  GlofasDlmStabStats stats;
  arma::mat a(p, Tn, fill::zeros);
  arma::mat m(p, Tn, fill::zeros);
  arma::cube P_star(p, p, Tn, fill::zeros);
  arma::cube R_star(p, p, Tn, fill::zeros);
  arma::cube C_star(p, p, Tn, fill::zeros);
  arma::vec f(Tn, fill::zeros);
  arma::vec Q_star(Tn, fill::zeros);
  arma::vec e(Tn, fill::zeros);
  arma::vec n_prev_seq(Tn, fill::zeros);
  arma::vec S_prev_seq(Tn, fill::zeros);
  arma::vec n_seq(Tn, fill::zeros);
  arma::vec S_seq(Tn, fill::zeros);
  arma::vec Q_scale(Tn, fill::zeros);
  arma::vec pred_var_actual(Tn, fill::zeros);
  arma::vec fitted_mean(Tn, fill::zeros);
  arma::vec fitted_var_actual(Tn, fill::zeros);

  arma::vec m_prev = m0;
  arma::mat C_prev = stabilize_covariance_cpp(
    C0_star_in,
    cov_eig_floor,
    cov_eig_cap,
    cov_diag_jitter,
    &stats
  );
  double n_prev = n0;
  double S_prev = S0;

  for (int tt = 0; tt < Tn; ++tt) {
    if (!std::isfinite(y[tt])) {
      Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: y contains non-finite values");
    }
    arma::vec F_t = F_mat.row(tt).t();
    arma::mat G_t = G_array.slice(tt);
    if (!F_t.is_finite() || !G_t.is_finite()) {
      Rcpp::stop("glofas_structural_dlm_filter_forward_cpp: F/G contains non-finite values");
    }

    arma::vec a_t = G_t * m_prev;
    arma::mat P_t = stabilize_covariance_cpp(
      G_t * C_prev * G_t.t(),
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );
    arma::mat W_t = discount_scale_mat % P_t;
    arma::mat R_t = stabilize_covariance_cpp(
      P_t + W_t,
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );

    double f_t = arma::dot(F_t, a_t);
    double Q_t = 1.0 + arma::as_scalar(F_t.t() * R_t * F_t);
    if (!std::isfinite(Q_t) || Q_t < 1e-10) Q_t = 1e-10;
    double e_t = y[tt] - f_t;
    arma::vec A_t = (R_t * F_t) / Q_t;
    arma::vec m_t = a_t + A_t * e_t;
    arma::mat C_t = stabilize_covariance_cpp(
      R_t - (A_t * A_t.t()) * Q_t,
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );

    double n_t = n_prev + 1.0;
    double S_t = (n_prev * S_prev + (e_t * e_t) / Q_t) / n_t;
    if (!std::isfinite(S_t) || S_t <= 0.0) S_t = S_prev;

    a.col(tt) = a_t;
    m.col(tt) = m_t;
    P_star.slice(tt) = P_t;
    R_star.slice(tt) = R_t;
    C_star.slice(tt) = C_t;
    f[tt] = f_t;
    Q_star[tt] = Q_t;
    e[tt] = e_t;
    n_prev_seq[tt] = n_prev;
    S_prev_seq[tt] = S_prev;
    n_seq[tt] = n_t;
    S_seq[tt] = S_t;
    Q_scale[tt] = S_prev * Q_t;
    pred_var_actual[tt] = (n_prev > 2.0) ? (n_prev / (n_prev - 2.0)) * Q_scale[tt] : NA_REAL;

    double post_scale = S_t * arma::as_scalar(F_t.t() * C_t * F_t);
    fitted_mean[tt] = arma::dot(F_t, m_t);
    fitted_var_actual[tt] = (n_t > 2.0) ? (n_t / (n_t - 2.0)) * post_scale : NA_REAL;

    m_prev = m_t;
    C_prev = C_t;
    n_prev = n_t;
    S_prev = S_t;
  }

  return Rcpp::List::create(
    Rcpp::_["a"] = a,
    Rcpp::_["m"] = m,
    Rcpp::_["P_star"] = P_star,
    Rcpp::_["R_star"] = R_star,
    Rcpp::_["C_star"] = C_star,
    Rcpp::_["f"] = f,
    Rcpp::_["Q_star"] = Q_star,
    Rcpp::_["e"] = e,
    Rcpp::_["n_prev"] = n_prev_seq,
    Rcpp::_["S_prev"] = S_prev_seq,
    Rcpp::_["n"] = n_seq,
    Rcpp::_["S"] = S_seq,
    Rcpp::_["Q_scale"] = Q_scale,
    Rcpp::_["pred_var_actual"] = pred_var_actual,
    Rcpp::_["fitted_mean"] = fitted_mean,
    Rcpp::_["fitted_var_actual"] = fitted_var_actual,
    Rcpp::_["stabilization"] = stats_as_list(stats)
  );
}

// [[Rcpp::export]]
Rcpp::List glofas_structural_dlm_smooth_backward_cpp(
    const arma::mat& F_mat,
    const arma::cube& G_array,
    const arma::mat& a,
    const arma::mat& m,
    const arma::cube& R_star,
    const arma::cube& C_star,
    const arma::vec& n,
    const arma::vec& S,
    const double cov_eig_floor = 1e-8,
    const double cov_eig_cap = 1e8,
    const double cov_diag_jitter = 1e-10) {
  const int Tn = static_cast<int>(m.n_cols);
  const int p = static_cast<int>(m.n_rows);
  if (Tn <= 0) Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: filter output must be nonempty");
  if (p <= 0) Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: state dimension must be positive");
  if (a.n_rows != static_cast<arma::uword>(p) ||
      a.n_cols != static_cast<arma::uword>(Tn)) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: a must match m dimensions");
  }
  if (F_mat.n_rows != static_cast<arma::uword>(Tn) ||
      F_mat.n_cols != static_cast<arma::uword>(p)) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: F_mat must be T x p");
  }
  if (G_array.n_rows != static_cast<arma::uword>(p) ||
      G_array.n_cols != static_cast<arma::uword>(p) ||
      G_array.n_slices != static_cast<arma::uword>(Tn)) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: G_array must be p x p x T");
  }
  if (R_star.n_rows != static_cast<arma::uword>(p) ||
      R_star.n_cols != static_cast<arma::uword>(p) ||
      R_star.n_slices != static_cast<arma::uword>(Tn) ||
      C_star.n_rows != static_cast<arma::uword>(p) ||
      C_star.n_cols != static_cast<arma::uword>(p) ||
      C_star.n_slices != static_cast<arma::uword>(Tn)) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: R_star/C_star must be p x p x T");
  }
  if (n.n_elem != static_cast<arma::uword>(Tn) ||
      S.n_elem != static_cast<arma::uword>(Tn)) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: n and S must have length T");
  }
  if (!m.is_finite() || !a.is_finite() || !F_mat.is_finite() || !G_array.is_finite()) {
    Rcpp::stop("glofas_structural_dlm_smooth_backward_cpp: inputs contain non-finite values");
  }

  GlofasDlmStabStats stats;
  arma::mat s(p, Tn, fill::zeros);
  arma::cube D_star(p, p, Tn, fill::zeros);
  arma::cube B_star(p, p, Tn, fill::zeros);
  arma::vec smoothed_mean(Tn, fill::zeros);
  arma::vec smoothed_var_actual(Tn, fill::zeros);

  s.col(Tn - 1) = m.col(Tn - 1);
  D_star.slice(Tn - 1) = stabilize_covariance_cpp(
    C_star.slice(Tn - 1),
    cov_eig_floor,
    cov_eig_cap,
    cov_diag_jitter,
    &stats
  );

  for (int tt = Tn - 2; tt >= 0; --tt) {
    arma::mat C_t = stabilize_covariance_cpp(
      C_star.slice(tt),
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );
    arma::mat R_next = stabilize_covariance_cpp(
      R_star.slice(tt + 1),
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );
    arma::mat G_next = G_array.slice(tt + 1);
    arma::mat inv_R_next = safe_inv_cpp(R_next, cov_diag_jitter, &stats);
    arma::mat B_t = C_t * G_next.t() * inv_R_next;
    arma::vec s_t = m.col(tt) + B_t * (s.col(tt + 1) - a.col(tt + 1));
    arma::mat D_t = C_t + B_t * (D_star.slice(tt + 1) - R_next) * B_t.t();

    s.col(tt) = s_t;
    D_star.slice(tt) = stabilize_covariance_cpp(
      D_t,
      cov_eig_floor,
      cov_eig_cap,
      cov_diag_jitter,
      &stats
    );
    B_star.slice(tt) = B_t;
  }

  const double final_n = n[Tn - 1];
  const double final_S = S[Tn - 1];
  for (int tt = 0; tt < Tn; ++tt) {
    arma::vec F_t = F_mat.row(tt).t();
    smoothed_mean[tt] = arma::dot(F_t, s.col(tt));
    double mean_var_scale = final_S * arma::as_scalar(F_t.t() * D_star.slice(tt) * F_t);
    if (std::isfinite(final_n) && final_n > 2.0 &&
        std::isfinite(final_S) && final_S > 0.0 &&
        std::isfinite(mean_var_scale) && mean_var_scale >= 0.0) {
      smoothed_var_actual[tt] = (final_n / (final_n - 2.0)) * mean_var_scale;
    } else {
      smoothed_var_actual[tt] = NA_REAL;
    }
  }

  return Rcpp::List::create(
    Rcpp::_["s"] = s,
    Rcpp::_["D_star"] = D_star,
    Rcpp::_["B_star"] = B_star,
    Rcpp::_["smoothed_mean"] = smoothed_mean,
    Rcpp::_["smoothed_var_actual"] = smoothed_var_actual,
    Rcpp::_["final_n"] = final_n,
    Rcpp::_["final_S"] = final_S,
    Rcpp::_["stabilization"] = stats_as_list(stats)
  );
}
