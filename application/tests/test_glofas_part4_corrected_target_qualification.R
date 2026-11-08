source(app_path("application/R/glofas_part4_corrected_target_qualification.R"))

stopifnot(
  identical(gptq_normalize_family(c("Joint AL", "Joint exAL", "Normal RHS")),
    c("MQ AL", "MQ exAL", "Normal RHS/VB")),
  identical(gptq_expected$design_sha256,
    "55edbd490c622bdc55ebf373d792dbbb4f1be71fffc8df115e44f089548c4b33")
)

s3 <- data.frame(family = c("Independent AL", "Raw GloFAS"),
  crps_grid_log1p = c(.7, 1.4), crossing_pairs = c(0L, 0L))
oct <- data.frame(family = c("Independent AL", "Raw GloFAS"),
  crps_grid_log1p = c(.9, 1.4), crossing_pairs = c(1L, 0L))
nov <- data.frame(family = c("Independent AL", "Raw GloFAS"),
  grid_acrps_log1p = c(1.5, 1.4), raw_crossing_pairs = c(39L, 0L))
cmp <- gptq_comparison(s3, oct, nov)
stopifnot(nrow(cmp) == 6L,
  cmp$crps_grid_log1p[cmp$scenario == "October coherent later design" &
    cmp$family == "Independent AL"] == .9,
  cmp$crossing_pairs[cmp$scenario == "November rejected same-family" &
    cmp$family == "Independent AL"] == 39L)

td <- tempfile("gptq-", tmpdir = getwd()); dir.create(td, recursive = TRUE)
writeLines("qualification", file.path(td, "evidence.txt"))
m <- data.frame(relative_path = "evidence.txt", size_bytes = file.info(file.path(td, "evidence.txt"))$size,
  sha256 = gptq_sha256(file.path(td, "evidence.txt")))
dir.create(file.path(td, "manifests")); gptq_write_csv(m, file.path(td, "manifests/artifact_manifest.csv"))
stopifnot(file.exists(file.path(td, "manifests/artifact_manifest.csv")))
stopifnot(nchar(system2("git", c("rev-parse", "HEAD"), stdout = TRUE)) == 40L,
  !length(system2("git", c("status", "--porcelain", "--untracked-files=no"), stdout = TRUE)))
unlink(td, recursive = TRUE, force = TRUE)
cat("GLOFAS_PART4_CORRECTED_TARGET_QUALIFICATION_TEST_PASS\n")
