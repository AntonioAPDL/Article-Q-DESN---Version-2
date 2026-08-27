source(file.path(repo_root, "application/R/glofas_richer_discrepancy_campaign.R"))

pi <- app_glofas_median_screen_fan_in_pi(16, 4, c(100, 100, 100), 720, 720)
stopifnot(length(pi) == 4L)
stopifnot(isTRUE(all.equal(pi[[1L]], 16 / 2162)))
stopifnot(all(pi[-1L] == 0.16))

geometries <- app_glofas_richer_initial_geometries()
stopifnot(length(geometries) == 15L)
stopifnot(identical(vapply(geometries, `[[`, integer(1L), "D"),
  c(2L, 2L, 3L, 3L, 4L, 4L, 4L, 4L, 8L, 8L, 8L, 16L, 16L, 32L, 32L)))

space <- app_glofas_richer_screen_space("test_richer", tempfile("richer_"), 0:19)
stopifnot(length(space$explicit_candidates) == 21L)
stopifnot(space$fixed$inference$max_iter == 150L)
stopifnot(space$scheduler$max_parallel == 20L)
manifest <- app_glofas_median_screen_candidate_manifest(space)
stopifnot(nrow(manifest) == 21L)
stopifnot(sum(manifest$candidate_role == "low_alpha_health_canary") == 4L)
