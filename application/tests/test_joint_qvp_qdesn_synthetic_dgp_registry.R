registry <- app_joint_qvp_load_synthetic_dgp_registry()

stopifnot(nrow(registry) >= 9L)
stopifnot(all(app_joint_qvp_synthetic_dgp_registry_columns() %in% names(registry)))
stopifnot(any(registry$scenario_class == "bridge"))
stopifnot(any(registry$scenario_class == "stress"))
stopifnot(!anyDuplicated(registry$scenario_id))
stopifnot(all(registry$distribution_family %in% app_joint_qvp_allowed_synthetic_dgp_distributions()))
stopifnot(all(registry$dynamics_class %in% app_joint_qvp_allowed_synthetic_dgp_dynamics()))

required_scenarios <- c(
  "normal_bridge",
  "laplace_bridge",
  "gaussian_mixture_bridge",
  "student_t_location_scale",
  "asymmetric_laplace_tail",
  "heteroskedastic_seasonal",
  "persistent_heavy_tail",
  "regime_shift",
  "nonlinear_reservoir_friendly"
)
stopifnot(all(required_scenarios %in% registry$scenario_id))

smoke_registry <- registry
smoke_registry$simulated_length <- 60L
smoke_registry$washout_length <- 12L
smoke_registry$train_length <- 28L
smoke_registry$test_length <- 20L
app_joint_qvp_validate_synthetic_dgp_registry(smoke_registry)

normal_row <- smoke_registry[smoke_registry$scenario_id == "normal_bridge", , drop = FALSE]
normal_fixture <- app_joint_qvp_fixture_from_synthetic_dgp_registry_row(normal_row)
normal_repeat <- app_joint_qvp_fixture_from_synthetic_dgp_registry_row(normal_row)
stopifnot(identical(round(normal_fixture$y, 12), round(normal_repeat$y, 12)))
stopifnot(identical(round(normal_fixture$true_q, 12), round(normal_repeat$true_q, 12)))
stopifnot(all(is.finite(normal_fixture$y)))
stopifnot(all(is.finite(normal_fixture$Z)))
stopifnot(all(is.finite(normal_fixture$true_q)))
stopifnot(all(normal_fixture$sigma > 0))
stopifnot(all(apply(normal_fixture$true_q, 1L, function(x) all(diff(x) >= -1.0e-10))))
stopifnot(sum(normal_fixture$crossing_diagnostics$n_crossing_pairs) == 0L)
stopifnot(sum(normal_fixture$split$split == "washout") == 12L)
stopifnot(sum(normal_fixture$split$split == "train") == 28L)
stopifnot(sum(normal_fixture$split$split == "test") == 20L)

mix_row <- smoke_registry[smoke_registry$scenario_id == "gaussian_mixture_bridge", , drop = FALSE]
mix <- app_joint_qvp_registry_mixture_params(mix_row)
mix_probs <- c(0.05, 0.10, 0.50, 0.90, 0.95)
mix_q <- app_joint_qvp_gaussian_mixture_quantile(
  mix_probs,
  weight = mix$weight,
  mean1 = mix$mean1,
  sd1 = mix$sd1,
  mean2 = mix$mean2,
  sd2 = mix$sd2
)
mix_cdf <- app_joint_qvp_gaussian_mixture_cdf(
  mix_q,
  weight = mix$weight,
  mean1 = mix$mean1,
  sd1 = mix$sd1,
  mean2 = mix$mean2,
  sd2 = mix$sd2
)
stopifnot(max(abs(mix_cdf - mix_probs)) < 1.0e-8)

registry_dir <- tempfile("joint_qvp_synthetic_dgp_registry_")
registry_result <- app_joint_qvp_materialize_synthetic_dgp_registry(
  out_dir = registry_dir,
  registry = smoke_registry
)

registry_manifest <- utils::read.csv(
  file.path(registry_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_registry_labels <- c(
  "frozen_registry",
  "registry_validation",
  "scenario_summary",
  "observed_series",
  "design_matrix",
  "true_quantile_wide",
  "true_quantile_long",
  "split_metadata",
  "dgp_parameters",
  "crossing_summary",
  "provenance",
  "readme"
)
stopifnot(identical(registry_manifest$label, expected_registry_labels))
stopifnot(all(nchar(registry_manifest$sha256) == 64L))
for (ii in seq_len(nrow(registry_manifest))) {
  artifact_path <- file.path(registry_result$out_dir, registry_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), registry_manifest$sha256[[ii]]))
}

scenario_summary <- utils::read.csv(file.path(registry_result$out_dir, "scenario_summary.csv"), stringsAsFactors = FALSE)
observed <- utils::read.csv(file.path(registry_result$out_dir, "observed_series.csv"), stringsAsFactors = FALSE)
design <- utils::read.csv(file.path(registry_result$out_dir, "design_matrix.csv"), stringsAsFactors = FALSE)
true_wide <- utils::read.csv(file.path(registry_result$out_dir, "true_quantile_wide.csv"), stringsAsFactors = FALSE)
true_long <- utils::read.csv(file.path(registry_result$out_dir, "true_quantile_long.csv"), stringsAsFactors = FALSE)
split_metadata <- utils::read.csv(file.path(registry_result$out_dir, "split_metadata.csv"), stringsAsFactors = FALSE)
validation <- utils::read.csv(file.path(registry_result$out_dir, "registry_validation.csv"), stringsAsFactors = FALSE)

stopifnot(nrow(scenario_summary) == nrow(smoke_registry))
stopifnot(nrow(observed) == nrow(smoke_registry) * 60L)
stopifnot(nrow(design) == nrow(smoke_registry) * 60L)
stopifnot(nrow(true_wide) == nrow(smoke_registry) * 60L)
stopifnot(nrow(true_long) == nrow(smoke_registry) * 60L * 7L)
stopifnot(nrow(split_metadata) == nrow(smoke_registry))
stopifnot(all(validation$status == "pass"))
stopifnot(all(observed$sigma > 0))
stopifnot(all(is.finite(observed$y)))
stopifnot(all(is.finite(design$lag_y)))
stopifnot(all(is.finite(true_long$true_quantile)))
stopifnot(all(split_metadata$washout_length == 12L))
stopifnot(all(split_metadata$train_length == 28L))
stopifnot(all(split_metadata$test_length == 20L))

for (scenario_id in unique(true_long$scenario_id)) {
  block <- true_long[true_long$scenario_id == scenario_id, , drop = FALSE]
  for (tt in unique(block$time_index)) {
    row <- block[block$time_index == tt, , drop = FALSE]
    row <- row[order(row$tau), , drop = FALSE]
    stopifnot(all(diff(row$true_quantile) >= -1.0e-10))
  }
}

repeat_dir <- tempfile("joint_qvp_synthetic_dgp_registry_repeat_")
repeat_result <- app_joint_qvp_materialize_synthetic_dgp_registry(
  out_dir = repeat_dir,
  registry = smoke_registry
)
repeat_manifest <- utils::read.csv(file.path(repeat_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(registry_manifest$label, repeat_manifest$label))
stopifnot(identical(registry_manifest$relative_path, repeat_manifest$relative_path))
stopifnot(identical(registry_manifest$sha256, repeat_manifest$sha256))
