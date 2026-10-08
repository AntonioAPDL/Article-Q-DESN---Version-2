local({
tmp <- tempfile("search3_runtime_contract_")
dir.create(tmp, recursive = TRUE)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

legacy <- file.path(tmp, "legacy.csv")
writeLines('""', legacy)
legacy_rows <- app_glofas_search3_read_reuse_registry(legacy)
stopifnot(nrow(legacy_rows) == 0L)
stopifnot(identical(names(legacy_rows), app_glofas_search3_reuse_registry_columns()))

typed <- file.path(tmp, "typed.csv")
app_write_csv(app_glofas_search3_empty_reuse_registry(), typed)
typed_rows <- app_glofas_search3_read_reuse_registry(typed)
stopifnot(nrow(typed_rows) == 0L)
stopifnot(identical(names(typed_rows), app_glofas_search3_reuse_registry_columns()))

valid <- app_glofas_search3_empty_reuse_registry()
valid[1L, ] <- as.list(rep("x", ncol(valid)))
valid_path <- file.path(tmp, "valid.csv")
app_write_csv(valid, valid_path)
valid_rows <- app_glofas_search3_read_reuse_registry(valid_path)
stopifnot(nrow(valid_rows) == 1L, identical(names(valid_rows), names(valid)))

malformed <- file.path(tmp, "malformed.csv")
writeLines('"destination_job_id"\n"x"', malformed)
malformed_failed <- inherits(try(app_glofas_search3_read_reuse_registry(malformed), silent = TRUE), "try-error")
stopifnot(malformed_failed)
})

cat("test_glofas_search3_runtime_contract: OK\n")
