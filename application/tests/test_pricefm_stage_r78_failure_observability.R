args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
test_path <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
runner <- file.path(dirname(dirname(test_path)), "scripts", "pricefm",
                    "259_run_pricefm_stage_r76_repaired_exal_component.R")
text <- readLines(runner, warn = FALSE)
start <- grep("^finite_check <-", text)
stop_line <- grep("^task_path <-", text)[1L]
eval(parse(text = text[start:(stop_line - 1L)]), envir = environment())

trace <- data.frame(sigma = c(1, 2), gamma = c(0, 0.1), delta_state = c(1, 0.1))
ok <- validate_fit_contract(1:2, diag(2), 1, 0, 1:3, trace,
                            names(trace), 40L, 35L)
stopifnot(ok$passed, length(ok$failed_fields) == 0L)

bad <- validate_fit_contract(c(1, NA_real_), diag(2), 1, Inf, 1:3, trace,
                             names(trace), 20L, 35L)
stopifnot(!bad$passed)
stopifnot(identical(bad$failed_fields, c("beta", "gamma", "structured_updates")))
cat("R78 failure-observability checks passed.\n")
