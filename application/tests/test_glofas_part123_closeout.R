repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/glofas_part123_closeout.R"))

dates <- seq.Date(as.Date("2022-12-26"), by = "day", length.out = 30L)
truth <- data.frame(date = dates, observed_usgs = seq(0.1, 3, length.out = 30L))
origin <- list(origin_date = as.Date("2022-12-25"), future_dates = dates)
normal <- list(origin = origin, reference_draws = cbind(truth$observed_usgs - 0.1, truth$observed_usgs + 0.1))
score_n <- app_glofas_closeout_score_normal(normal, truth, "normal")
stopifnot(nrow(score_n) == 1L, score_n$mae < 1e-12, is.finite(score_n$mean_crps))

tau <- c(0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.95)
qhat <- outer(truth$observed_usgs, stats::qnorm(tau), function(y, z) y + z * 0.1)
quantile <- list(origin = origin, reference = qhat, tau = tau)
score_q <- app_glofas_closeout_score_quantile(quantile, truth, "quantile")
stopifnot(nrow(score_q) == 7L, all(is.finite(score_q$mean_crps_grid)))

bad <- normal
bad$origin$future_dates[1] <- as.Date("2022-12-25")
rejected <- tryCatch({ app_glofas_closeout_score_normal(bad, truth, "bad"); FALSE }, error = function(e) TRUE)
stopifnot(rejected)
cat("test_glofas_part123_closeout: OK\n")
