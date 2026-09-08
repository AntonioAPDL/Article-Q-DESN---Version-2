rhs_gaussian <- app_rhs_reference_tau0(
  m0 = 5,
  r = 100,
  n_fit = 400,
  sigma_ref = 2
)
stopifnot(abs(rhs_gaussian - (5 / 95) * (2 / 20)) < 1e-15)

rhs_unit_scale <- app_rhs_reference_tau0(
  m0 = 5,
  r = 100,
  n_fit = 400
)
stopifnot(abs(rhs_unit_scale - rhs_gaussian / 2) < 1e-15)

rhs_al <- app_rhs_reference_tau0_al(
  m0 = 5,
  r = 100,
  n_fit = 400,
  p0 = 0.25,
  sigma_ref = 2
)
rhs_al_generic <- app_rhs_reference_tau0(
  m0 = 5,
  r = 100,
  n_fit = 400,
  sigma_ref = 2,
  information_factor = 0.25 * 0.75
)
stopifnot(abs(rhs_al - rhs_al_generic) < 1e-15)

rhs_exal_at_al <- app_rhs_reference_tau0_exal(
  m0 = 5,
  r = 100,
  n_fit = 400,
  j_ref = 0.25 * 0.75,
  sigma_ref = 2
)
stopifnot(abs(rhs_exal_at_al - rhs_al) < 1e-15)

expect_reference_error <- function(expression) {
  result <- tryCatch({
    force(expression)
    NULL
  }, error = function(e) e)
  stopifnot(inherits(result, "error"))
}

expect_reference_error(app_rhs_reference_tau0(0, 100, 400))
expect_reference_error(app_rhs_reference_tau0(100, 100, 400))
expect_reference_error(app_rhs_reference_tau0(5, 1.5, 400))
expect_reference_error(app_rhs_reference_tau0(5, 100, 0))
expect_reference_error(app_rhs_reference_tau0(5, 100, 400, sigma_ref = 0))
expect_reference_error(app_rhs_reference_tau0(
  5, 100, 400, information_factor = 0
))
expect_reference_error(app_rhs_reference_tau0_al(5, 100, 400, p0 = 1))
expect_reference_error(app_rhs_reference_tau0_exal(
  5, 100, 400, j_ref = NA_real_
))

main_text <- paste(readLines(app_path("main.tex"), warn = FALSE), collapse = "\n")
supplement_text <- paste(
  readLines(app_path("qdesn-supplement.tex"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("Reference calibration of the global scale", main_text, fixed = TRUE))
stopifnot(grepl("eq:rhs-global-reference-main", main_text, fixed = TRUE))
stopifnot(!grepl(
  "tau_{0,\\mathrm{ref}}=\\GlofasApplicationCurrentSharedRhsTau",
  main_text,
  fixed = TRUE
))
stopifnot(grepl(
  "Reference Calibration of the Global Shrinkage Scale",
  supplement_text,
  fixed = TRUE
))
stopifnot(grepl("eq:supp-rhs-tau0-al-reference", supplement_text, fixed = TRUE))
stopifnot(grepl("eq:supp-rhs-tau0-exal-reference", supplement_text, fixed = TRUE))
