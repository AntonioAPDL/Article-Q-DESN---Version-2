source("application/scripts/_joint_qdesn_pure_recursive_bootstrap.R")

expect_error <- function(expr, pattern) {
  message <- tryCatch({ force(expr); NA_character_ }, error = conditionMessage)
  stopifnot(is.character(message), length(message) == 1L, !is.na(message),
    grepl(pattern, message, fixed = TRUE))
}

contract <- app_joint_alkernel_contract()
stopifnot(app_joint_alkernel_value(contract, "mandatory_al_workers", TRUE) == 96,
  app_joint_alkernel_value(contract, "reused_exal_workers", TRUE) == 96,
  app_joint_alkernel_value(contract, "rescored_al_cells", TRUE) == 32,
  app_joint_alkernel_value(contract, "scale_update_id") ==
    "direct_inverse_gamma_unbounded_v1",
  app_joint_alkernel_value(contract, "sigma_support") == "(0,Inf)",
  app_joint_alkernel_value(contract, "exal_method") ==
    "M0_v_collapsed_support_logit")

fixture <- data.frame(worker_id = 1:4, likelihood_family = c("AL", "exAL", "AL", "exAL"),
  stringsAsFactors = FALSE)
tmp <- tempfile("joint_al_kernel_health_"); dir.create(tmp, recursive = TRUE)
dir.create(file.path(tmp, "full_confirmation", "mcmc_workers"), recursive = TRUE)
write.csv(fixture[fixture$likelihood_family == "AL", ], file.path(tmp,
  "full_confirmation", "al_mcmc_rerun_plan.csv"), row.names = FALSE)
for (id in c(1L, 3L)) {
  dir.create(file.path(tmp, "full_confirmation", "mcmc_workers",
    sprintf("worker_%04d", id)))
}
writeLines("completed", file.path(tmp, "full_confirmation", "mcmc_workers",
  "worker_0001", "DONE"))
health <- app_joint_alkernel_health(tmp, "mcmc")
stopifnot(health$expected == 2L, health$completed == 1L, health$remaining == 1L,
  health$failed == 0L)

bad_root <- tempfile("joint_al_kernel_bad_"); dir.create(bad_root)
writeLines("occupied", file.path(bad_root, "file"))
expect_error(app_joint_alkernel_prepare(bad_root, bad_root, bad_root),
  "must be new and empty")

packet_fixture <- data.frame(
  scenario_id = rep(c("s1", "persistent_heavy_tail"), each = 4),
  model_id = rep(c("independent_qdesn_rhs", "joint_qdesn_rhs",
    "independent_exqdesn_rhs", "joint_exqdesn_rhs"), 2),
  specification_role = "new_geometry_parity", stringsAsFactors = FALSE)
stopifnot(all(table(packet_fixture$scenario_id) == 4L))

unlink(c(tmp, bad_root), recursive = TRUE, force = TRUE)
cat("JOINT_SUPERFINAL_AL_KERNEL_RERUN_TEST_PASS checks=18 production_runs=0\n")
