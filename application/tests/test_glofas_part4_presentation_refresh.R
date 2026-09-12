if (!exists("app_set_repo_root", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
}
source(app_path("application/scripts/394_check_glofas_part4_presentation_refresh.R"))

cat("GloFAS Part 4 presentation refresh checks passed.\n")
