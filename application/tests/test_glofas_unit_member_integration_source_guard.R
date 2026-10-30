#!/usr/bin/env Rscript

# No model code is sourced and no fits are run. All mutations, index changes,
# and merge-state simulations occur in one disposable local Git fixture whose
# object store only reads the real repository through Git alternates.
local({
  run_guard_tests <- function() {
    if (exists("app_repo_root", mode = "function")) {
      root <- app_repo_root()
    } else {
      file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
      stopifnot(length(file_arg) == 1L)
      root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)),
        "..", ".."), mustWork = TRUE)
    }
    guard_env <- new.env(parent = baseenv())
    sys.source(file.path(root, "scripts/glofas_unit_member_integration_source_guard.R"),
      envir = guard_env)
    guard <- guard_env$app_check_glofas_unit_member_integration_sources
    baseline <- "a96e661613ec7e733196a0b994f45350a3078332"
    source_commit <- "60daab261d52eec0ae24060babe186d618303e2b"
    source_parent <- "483e6edbec72ec76e48f2259e943e674b76e5041"
    pin <- "176c0340fbcc7c2efdda7fe01d9e13c44906ffafa311bc48a16a645156905dd6"
    relative_manifest <- paste0("docs/reproducibility/",
      "glofas_unit_member_integration_source_contract_20261029.csv")
    manifest <- read.csv(file.path(root, relative_manifest), colClasses = "character")
    worker <- "application/scripts/386_run_glofas_part4_latent_family_job.R"
    checks <- 0L
    mutations <- 0L
    check <- function(value, message) {
      if (!isTRUE(value)) stop(message, call. = FALSE)
      checks <<- checks + 1L
    }
    git_at <- function(directory, arguments) {
      output <- suppressWarnings(system2("git",
        c("--no-replace-objects", "-C", shQuote(directory), arguments),
        stdout = TRUE, stderr = TRUE))
      status <- attr(output, "status")
      if (!is.null(status) && status != 0L) {
        stop(paste("Fixture Git failed:", paste(output, collapse = "\n")), call. = FALSE)
      }
      unname(as.character(output))
    }
    check(any(grepl(pin, readLines(file.path(root,
      "scripts/check_qdesn_statistical_language_revision.R")), fixed = TRUE)),
      "The production statistical-language checker must contain the manifest SHA256 pin.")
    check(length(guard(root, pin)) > 0L,
      "The actual integration source surface must pass before fixture mutations.")
    fixture <- tempfile("glofas unit source guard ")
    dir.create(fixture)
    on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
    git <- function(arguments) git_at(fixture, arguments)
    git(c("init", "--quiet"))
    objects <- git_at(root, c("rev-parse", "--path-format=absolute", "--git-path", "objects"))
    check(length(objects) == 1L && dir.exists(objects),
      "The disposable fixture must read the existing object store without modifying it.")
    writeLines(objects, file.path(fixture, ".git/objects/info/alternates"))
    git(c("config", "core.sparseCheckout", "true"))
    git(c("config", "core.sparseCheckoutCone", "false"))
    scopes <- c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
    writeLines(paste0("/", scopes, "/"), file.path(fixture, ".git/info/sparse-checkout"))
    git(c("update-ref", "HEAD", source_commit))
    git(c("read-tree", "-mu", source_commit))
    path <- function(relative) file.path(fixture, relative)
    manifest_path <- path(relative_manifest)
    dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
    check(file.copy(file.path(root, relative_manifest), manifest_path),
      "The fixture authorization manifest must copy exactly.")
    check(file.copy(file.path(root, worker), path(worker), overwrite = TRUE),
      "Only the approved worker correction is added to the fixture science source.")
    accept <- function(label, required = NULL) {
      result <- guard(fixture, pin)
      check(length(result) > 0L &&
        (is.null(required) || any(grepl(required, result, fixed = TRUE))),
        paste("Expected source-guard acceptance:", label))
    }
    reject <- function(label, expected = NULL, expected_pin = pin) {
      result <- tryCatch(guard(fixture, expected_pin), error = identity)
      check(inherits(result, "error") &&
        (is.null(expected) || grepl(expected, conditionMessage(result), fixed = TRUE)),
        paste("Expected source-guard rejection:", label,
          if (inherits(result, "error")) conditionMessage(result) else "unexpected acceptance"))
      mutations <<- mutations + 1L
    }
    raw_file <- function(filename) readBin(filename, "raw", n = file.info(filename)$size)
    restore_manifest <- function() {
      check(file.copy(file.path(root, relative_manifest), manifest_path, overwrite = TRUE),
        "Fixture manifest restoration must succeed.")
    }
    accept("frozen science source already in HEAD", "Integrated source authorization")
    git(c("update-ref", "HEAD", source_parent))
    writeLines(source_commit, path(".git/MERGE_HEAD"))
    accept("exact frozen pending merge", "Integrated source authorization")
    writeLines(source_parent, path(".git/MERGE_HEAD"))
    reject("wrong pending merge source", "sole pending MERGE_HEAD")
    writeLines(c(source_commit, source_parent), path(".git/MERGE_HEAD"))
    reject("multiple pending merge sources", "sole pending MERGE_HEAD")
    unlink(path(".git/MERGE_HEAD"))
    reject("source object exists but is not integrated", "sole pending MERGE_HEAD")
    git(c("update-ref", "HEAD", baseline))
    writeLines(source_commit, path(".git/MERGE_HEAD"))
    reject("pending merge without frozen-parent ancestry", "sole pending MERGE_HEAD")
    git(c("update-ref", "HEAD", source_parent))
    writeLines(source_commit, path(".git/MERGE_HEAD"))

    for (relative in manifest$path) {
      original <- raw_file(path(relative))
      writeBin(c(original, charToRaw("\n# unauthorized source mutation\n")), path(relative))
      reject(paste("one-byte-or-more source mutation:", relative), "Scientific source bytes")
      writeBin(original, path(relative))
    }
    # This additional tracked source is outside the exact frozen twelve-path set.
    extra_tracked <- path("application/R/00_packages.R")
    original <- raw_file(extra_tracked)
    writeBin(c(original, charToRaw("\n# extra tracked scientific edit\n")), extra_tracked)
    reject("additional tracked source", "exactly the twelve authorized paths")
    git(c("add", "--", "application/R/00_packages.R"))
    writeBin(original, extra_tracked)
    reject("additional staged source hidden by restored worktree",
      "exactly the twelve authorized paths")
    git(c("reset", "--quiet", source_commit, "--", "application/R/00_packages.R"))
    for (scope in scopes) {
      added <- path(paste0(scope, "/guard_untracked_source.R"))
      dir.create(dirname(added), recursive = TRUE, showWarnings = FALSE)
      writeLines("# additional untracked implementation", added)
      reject(paste("untracked source in", scope), "No untracked scientific source")
      unlink(added)
    }
    added <- path("application/R/guard_ignored_source.R")
    writeLines("guard_ignored_source.R", path(".git/info/exclude"))
    writeLines("# ignored files must not bypass source authorization", added)
    reject("ignored untracked source", "No untracked scientific source")
    unlink(added)
    writeLines(character(), path(".git/info/exclude"))
    added_relative <- "application/R/guard_staged_source.R"
    writeLines("# staged extra source", path(added_relative))
    git(c("add", "--", shQuote(added_relative)))
    reject("additional staged source", "exactly the twelve authorized paths")
    git(c("update-index", "--force-remove", "--", shQuote(added_relative)))
    unlink(path(added_relative))

    # Deletion and renaming never change the real integration files.
    victim <- path(manifest$path[[1L]])
    backup <- path("saved_source_bytes")
    check(file.rename(victim, backup), "Fixture source deletion setup must succeed.")
    reject("deleted authorized source")
    check(file.rename(backup, victim), "Fixture deleted source restoration must succeed.")
    renamed <- paste0(victim, ".renamed")
    check(file.rename(victim, renamed), "Fixture rename setup must succeed.")
    reject("renamed authorized source", "No untracked scientific source")
    check(file.rename(renamed, victim), "Fixture rename restoration must succeed.")
    check(file.rename(victim, backup), "Fixture symlink setup must preserve original bytes.")
    check(file.symlink(backup, victim), "Fixture symlink creation must succeed.")
    reject("symlink with otherwise authorized bytes", "a symlink")
    unlink(victim)
    check(file.rename(backup, victim), "Fixture symlink restoration must succeed.")
    Sys.chmod(victim, "0755")
    git(c("config", "core.filemode", "false"))
    reject("executable bit even when Git ignores mode", "executable modes")
    Sys.chmod(victim, "0644")
    git(c("config", "core.filemode", "true"))
    git(c("update-index", "--chmod=+x", "--", shQuote(manifest$path[[1L]])))
    reject("staged executable mode", "index entries")
    git(c("update-index", "--chmod=-x", "--", shQuote(manifest$path[[1L]])))

    # A bad staged blob must not be hidden behind correct working-tree bytes.
    original <- raw_file(victim)
    writeBin(c(original, charToRaw("\n# staged-only unauthorized mutation\n")), victim)
    git(c("add", "--", shQuote(manifest$path[[1L]])))
    writeBin(original, victim)
    reject("staged bad bytes concealed by restored worktree", "Staged source bytes")
    git(c("update-index", "--cacheinfo", paste0("100644,",
      manifest$source_blob[[1L]], ",", manifest$path[[1L]])))

    saved_worker <- raw_file(path(worker))
    # checkout-index reads the frozen original worker from this fixture's index.
    git(c("checkout-index", "--force", "--", shQuote(worker)))
    reject("uncorrected original worker", "Scientific source bytes")
    writeBin(saved_worker, path(worker))
    original_manifest <- raw_file(manifest_path)
    writeBin(c(original_manifest, charToRaw("\n")), manifest_path)
    reject("manifest byte mutation", "manifest SHA256")
    writeBin(original_manifest, manifest_path)
    check(file.rename(manifest_path, path("saved_manifest")),
      "Fixture manifest deletion setup must succeed.")
    reject("science changes cannot fall back when manifest removed", "editorial revision")
    check(file.rename(path("saved_manifest"), manifest_path),
      "Fixture manifest restoration after deletion must succeed.")
    mutate_manifest <- function(changed, label, expected) {
      write.csv(changed, manifest_path, row.names = FALSE, quote = FALSE)
      reject(label, expected, unname(tools::sha256sum(manifest_path)[[1L]]))
      restore_manifest()
    }
    changed <- manifest
    changed$source_blob[[1L]] <- strrep("0", 40L)
    mutate_manifest(changed, "false original blob even with matching test pin",
      "Only the operational worker")
    changed <- manifest
    changed$source_blob[[1L]] <- changed$authorized_blob[[1L]] <- strrep("0", 40L)
    mutate_manifest(changed, "false source blob and final blob", "Original scientific source blobs")
    changed <- manifest[-1L, , drop = FALSE]
    mutate_manifest(changed, "missing manifest path", "exactly the twelve frozen paths")
    changed <- rbind(manifest, manifest[1L, , drop = FALSE])
    mutate_manifest(changed, "extra duplicate manifest path", "exactly the twelve frozen paths")
    changed <- manifest
    changed$path[[1L]] <- changed$path[[2L]]
    mutate_manifest(changed, "duplicate replacing authorized manifest path", "exactly the twelve frozen paths")
    changed <- manifest
    changed$authorized_mode[[1L]] <- "100755"
    mutate_manifest(changed, "changed authorization mode", "modes and hashes")
    accept("all integration mutations restored")

    # Restore this fixture alone to the editorial baseline. The absence of the
    # authorization manifest must retain precisely the original no-source-edit rule.
    unlink(manifest_path)
    unlink(path(".git/MERGE_HEAD"))
    # Discard only this disposable fixture's pinned operational worker patch.
    git(c("read-tree", "--reset", "-u", baseline))
    git(c("update-ref", "HEAD", baseline))
    accept("zero-delta editorial mode without manifest", "Editorial source authorization")
    writeLines("# unauthorized editorial source addition", path("application/R/editorial_extra.R"))
    reject("editorial untracked source", "No untracked scientific source")
    unlink(path("application/R/editorial_extra.R"))
    original <- raw_file(path("application/R/00_packages.R"))
    writeBin(c(original, charToRaw("\n# unauthorized editorial edit\n")),
      path("application/R/00_packages.R"))
    reject("editorial tracked source mutation", "editorial revision")
    writeBin(original, path("application/R/00_packages.R"))
    restore_manifest()
    reject("manifest cannot authorize an incomplete scientific merge",
      "sole pending MERGE_HEAD")
    cat(sprintf(paste0("GLOFAS_UNIT_MEMBER_INTEGRATION_SOURCE_GUARD_TEST_PASS ",
      "checks=%d expected_mutation_rejections=%d scientific_runs=0\n"), checks, mutations))
  }
  run_guard_tests()
})
