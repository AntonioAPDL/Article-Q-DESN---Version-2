#!/usr/bin/env Rscript
# Purpose: build a broad, reproducible reservoir-screening grid for the GloFAS
# latent-path application. This script writes screening-only candidate tables;
# it does not launch VB/MCMC application fits.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(repo_root)

fmt_num <- function(x) {
  out <- format(x, scientific = FALSE, trim = TRUE)
  out <- sub("^0\\.", "0p", out)
  out <- gsub("\\.", "p", out, fixed = TRUE)
  out <- gsub("-", "m", out, fixed = TRUE)
  out
}

vec_label <- function(x) {
  paste(as.integer(x), collapse = "x")
}

no_reduction_n_tilde <- function(n_vec) {
  n_vec <- as.integer(n_vec)
  if (length(n_vec) <= 1L) return("")
  paste(n_vec[-length(n_vec)], collapse = ";")
}

add_block <- function(
  out,
  family,
  base_case,
  D,
  n_vector,
  m_values,
  alpha_values,
  rho_values,
  scale_values,
  input_bounds = "none",
  seed = 20260512L,
  rationale = ""
) {
  n_vector <- as.integer(n_vector)
  stopifnot(length(n_vector) == as.integer(D))
  grid <- expand.grid(
    m = as.integer(m_values),
    alpha = as.numeric(alpha_values),
    rho = as.numeric(rho_values),
    win_scale_global = as.numeric(scale_values),
    input_bound = as.character(input_bounds),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  grid$win_scale_bias <- grid$win_scale_global
  grid$spec_id <- sprintf(
    "%s_m%03d_a%s_r%s_w%s_bound%s",
    base_case,
    grid$m,
    fmt_num(grid$alpha),
    fmt_num(grid$rho),
    fmt_num(grid$win_scale_global),
    grid$input_bound
  )
  rows <- data.frame(
    spec_id = grid$spec_id,
    family = family,
    base_case = base_case,
    D = as.integer(D),
    n_vector = paste(n_vector, collapse = ";"),
    n_tilde = no_reduction_n_tilde(n_vector),
    m = grid$m,
    alpha = grid$alpha,
    rho = grid$rho,
    pi_w = 0.03,
    pi_in = 1.00,
    win_scale_global = grid$win_scale_global,
    win_scale_bias = grid$win_scale_bias,
    input_bound = grid$input_bound,
    launch_seed = as.integer(seed),
    rationale = rationale,
    stringsAsFactors = FALSE
  )
  c(out, list(rows))
}

blocks <- list()

# A. Known-good D1 n=300 neighborhood. This is the positive-control region
# around the current promoted reference run.
blocks <- add_block(
  blocks,
  family = "positive_control_d1n300",
  base_case = "d1n300_refine",
  D = 1,
  n_vector = 300,
  m_values = c(80, 90, 100, 110, 120),
  alpha_values = c(0.84, 0.86, 0.88, 0.90, 0.92, 0.94),
  rho_values = c(0.91, 0.93, 0.95, 0.97),
  scale_values = c(0.15, 0.20, 0.25),
  rationale = "Positive-control D1 n300 neighborhood around the promoted m100 alpha0.92 rho0.97 run."
)

# B. Shallow capacity ladder. Keep D=1 and increase width before adding depth.
for (n in c(400, 500, 700, 1000)) {
  blocks <- add_block(
    blocks,
    family = "shallow_capacity_ladder",
    base_case = sprintf("d1n%d_ladder", n),
    D = 1,
    n_vector = n,
    m_values = c(80, 100, 120),
    alpha_values = c(0.65, 0.80, 0.92),
    rho_values = c(0.90, 0.93, 0.95, 0.97),
    scale_values = c(0.05, 0.10, 0.15, 0.20),
    rationale = "D1 capacity ladder with reduced input scale to test whether wider shallow reservoirs stay healthy."
  )
}

# C. Two-layer ladder. Previous capacity-1000 results had the closest
# near-misses in D2, so this block explores moderate D2 capacity carefully.
d2_cases <- list(
  d2n250x250_ladder = c(250, 250),
  d2n350x350_ladder = c(350, 350),
  d2n400x300_ladder = c(400, 300),
  d2n500x500_ladder = c(500, 500),
  d2n600x400_ladder = c(600, 400)
)
for (nm in names(d2_cases)) {
  blocks <- add_block(
    blocks,
    family = "two_layer_ladder",
    base_case = nm,
    D = 2,
    n_vector = d2_cases[[nm]],
    m_values = c(80, 100, 120),
    alpha_values = c(0.65, 0.80, 0.92),
    rho_values = c(0.90, 0.93, 0.95),
    scale_values = c(0.025, 0.05, 0.10),
    rationale = "D2 no-reduction ladder, emphasizing the D2 region that produced the closest capacity-1000 near-misses."
  )
}

# D. Three-layer ladder. Keep a controlled D3 search over total capacities below
# and at 1000, with no inter-layer reduction.
d3_cases <- list(
  d3n200x200x200_ladder = c(200, 200, 200),
  d3n300x300x300_ladder = c(300, 300, 300),
  d3n400x300x300_ladder = c(400, 300, 300),
  d3n333x334x333_ladder = c(333, 334, 333),
  d3n300x300x400_ladder = c(300, 300, 400)
)
for (nm in names(d3_cases)) {
  blocks <- add_block(
    blocks,
    family = "three_layer_ladder",
    base_case = nm,
    D = 3,
    n_vector = d3_cases[[nm]],
    m_values = c(80, 100, 120),
    alpha_values = c(0.50, 0.65, 0.80),
    rho_values = c(0.85, 0.90, 0.93),
    scale_values = c(0.025, 0.05, 0.10),
    rationale = "Controlled D3 no-reduction ladder to separate useful depth from saturation."
  )
}

# E. Focused deep stress tests. These are deliberately smaller than the D1-D3
# blocks because prior capacity-1000 screens showed depth mainly saturated.
deep_cases <- list(
  d4n250eq_stress = rep(250, 4),
  d5n200eq_stress = rep(200, 5),
  d6n200x200x150x150x150x150_stress = c(200, 200, 150, 150, 150, 150),
  d8n125eq_stress = rep(125, 8),
  d10n100eq_stress = rep(100, 10)
)
for (nm in names(deep_cases)) {
  blocks <- add_block(
    blocks,
    family = "deep_stress",
    base_case = nm,
    D = length(deep_cases[[nm]]),
    n_vector = deep_cases[[nm]],
    m_values = c(80, 100),
    alpha_values = c(0.50, 0.65, 0.80),
    rho_values = c(0.75, 0.85, 0.90),
    scale_values = c(0.025, 0.05, 0.10),
    rationale = "Focused deep no-reduction stress test; learning screen only unless diagnostics are unexpectedly strong."
  )
}

grid <- do.call(rbind, blocks)
if (anyDuplicated(grid$spec_id)) {
  dup <- unique(grid$spec_id[duplicated(grid$spec_id)])
  stop(sprintf("Duplicated spec_id values: %s", paste(utils::head(dup, 10), collapse = ", ")), call. = FALSE)
}

grid <- grid[order(grid$family, grid$base_case, grid$m, grid$alpha, grid$rho, grid$win_scale_global), , drop = FALSE]
row.names(grid) <- NULL

summary <- aggregate(
  spec_id ~ family + base_case + D + n_vector + n_tilde,
  data = grid,
  FUN = length
)
names(summary)[names(summary) == "spec_id"] <- "n_candidates"
summary$total_units <- vapply(strsplit(summary$n_vector, ";", fixed = TRUE), function(x) sum(as.integer(x)), integer(1L))
summary <- summary[order(summary$family, summary$total_units, summary$base_case), , drop = FALSE]
row.names(summary) <- NULL

grid_path <- file.path("application", "config", "reservoir_candidate_grid_latent_path_overnight_ladder_20260525.csv")
summary_path <- file.path("application", "config", "glofas_overnight_ladder_screen_20260525.csv")
utils::write.csv(grid, grid_path, row.names = FALSE, na = "")
utils::write.csv(summary, summary_path, row.names = FALSE, na = "")

cat(sprintf("wrote %s (%d rows)\n", grid_path, nrow(grid)))
cat(sprintf("wrote %s (%d rows)\n", summary_path, nrow(summary)))
