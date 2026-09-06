#!/usr/bin/env python3
"""Build a hash-pinned diagnostic derivative of the R75 exdqlm runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R75_MANIFEST = DATA / "runtime_libraries/exdqlm_pricefm_r75_large_n_gig_repair/pricefm_stage_r75_large_n_gig_repair_manifest.json"
SOURCE_ROOT = DATA / "runtime_sources/exdqlm_pricefm_r80_failure_diagnostics"
LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r80_failure_diagnostics"
MANIFEST_NAME = "pricefm_stage_r80_failure_diagnostics_manifest.json"
SOURCE_HASH = "50d69262c22fef169a0d608783b60ffb8b1bd9f4a0b0b1818d6f6c7137d01091"
BASE_SHA = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
VERSION = "1.1.1.9003"


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    if value.lower() in {"1", "true", "yes"}:
        return True
    if value.lower() in {"0", "false", "no"}:
        return False
    raise argparse.ArgumentTypeError(value)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r75-manifest", type=Path, default=R75_MANIFEST)
    p.add_argument("--source-root", type=Path, default=SOURCE_ROOT)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--install", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"Expected one instrumentation anchor, observed {text.count(old)}: {old[:60]}")
    return text.replace(old, new)


def instrument(source: Path) -> None:
    description = source / "DESCRIPTION"
    text = description.read_text()
    text = replace_once(text, "Version: 1.1.1.9002", f"Version: {VERSION}")
    text = replace_once(
        text, "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG",
        "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics",
    )
    description.write_text(text)

    structured = source / "R/exal_sigmagam_structured.R"
    text = structured.read_text()
    helper = '''.pricefm_emit_structured_failure <- function(kind, payload = list()) {
  callback <- getOption("exdqlm.pricefm_failure_callback", NULL)
  if (is.function(callback)) {
    event <- c(list(
      kind = as.character(kind),
      iter = getOption("exdqlm.pricefm_current_iter", NA_integer_)
    ), payload)
    try(callback(event), silent = TRUE)
  }
  invisible(NULL)
}

'''
    text = replace_once(text, "# Shared exAL scale-skewness helpers used by dynamic and static inference.\n\n",
                        "# Shared exAL scale-skewness helpers used by dynamic and static inference.\n\n" + helper)
    old = '  if (!length(logw)) stop("Structured exAL scale-skewness update has no finite gamma grid.", call. = FALSE)'
    new = '''  if (!length(logw)) {
    .pricefm_emit_structured_failure("no_finite_gamma_grid", list(
      stats = stats, p0 = p0, bounds = c(L, U), eta_start = eta_start,
      eta_mode = eta_mode, coarse_eta = coarse, coarse_logw = coarse_vals,
      adaptive_eta = seq(lo, hi, length.out = grid_size), adaptive_logw = logw
    ))
    stop("Structured exAL scale-skewness update has no finite gamma grid.", call. = FALSE)
  }'''
    text = replace_once(text, old, new)
    structured.write_text(text)

    static = source / "R/exalStaticLDVB.R"
    text = static.read_text()
    text = replace_once(
        text,
        "    if (isTRUE(do_ld_update) && isTRUE(structured_sigmagam)) {\n      ld <- find_mode_structured(eta_hat)",
        "    if (isTRUE(do_ld_update) && isTRUE(structured_sigmagam)) {\n      options(exdqlm.pricefm_current_iter = as.integer(iter))\n      ld <- find_mode_structured(eta_hat)",
    )
    static.write_text(text)


def probe(library: Path) -> dict[str, Any]:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
desc <- utils::packageDescription("exdqlm", lib.loc = lib)
ns <- loadNamespace("exdqlm", lib.loc = lib)
emit <- get(".pricefm_emit_structured_failure", envir = ns, inherits = FALSE)
seen <- NULL
old <- options(exdqlm.pricefm_failure_callback = function(event) seen <<- event,
               exdqlm.pricefm_current_iter = 17L)
on.exit(options(old), add = TRUE)
emit("probe", list(value = 3))
cat(jsonlite::toJSON(list(
  version = as.character(desc$Version),
  repair = as.character(desc[["Config/PriceFM/repair"]]),
  callback_kind = seen$kind, callback_iter = seen$iter, callback_value = seen$value
), auto_unbox = TRUE))
'''
    result = json.loads(subprocess.check_output(["Rscript", "-e", code, str(library)], text=True))
    if result != {"version": VERSION,
                  "repair": "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics",
                  "callback_kind": "probe", "callback_iter": 17, "callback_value": 3}:
        raise RuntimeError(f"R80 diagnostic runtime probe failed: {result}")
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    prior = json.loads(args.r75_manifest.read_text())
    if prior.get("base_tarball_sha256") != BASE_SHA:
        raise RuntimeError("R75 runtime does not derive from exact CRAN exdqlm 1.1.1")
    old_source = Path(prior["patched_source"])
    if sha256(old_source / "R/exal_sigmagam_structured.R") != SOURCE_HASH:
        raise RuntimeError("R75 structured source hash changed")
    source_root, library = args.source_root.resolve(), args.library.resolve()
    manifest_path = library / MANIFEST_NAME
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        result = json.loads(manifest_path.read_text())
        result["probe"] = probe(library)
        return result
    if source_root.exists():
        if not args.force:
            raise FileExistsError(source_root)
        shutil.rmtree(source_root)
    if library.exists():
        if not args.force:
            raise FileExistsError(library)
        shutil.rmtree(library)
    source_root.mkdir(parents=True)
    source = source_root / "exdqlm"
    shutil.copytree(old_source, source)
    instrument(source)
    payload: dict[str, Any] = {
        "status": "materialized_not_installed", "version": VERSION,
        "scientific_role": "diagnostic_only_no_scientific_repair",
        "base_tarball_sha256": BASE_SHA, "r75_manifest": str(args.r75_manifest.resolve()),
        "r75_manifest_sha256": sha256(args.r75_manifest), "source": str(source),
        "source_hashes": {str(p.relative_to(source)): sha256(p) for p in (
            source / "DESCRIPTION", source / "R/exal_sigmagam_structured.R", source / "R/exalStaticLDVB.R")},
        "library": str(library), "launch_authorized": False, "test_access_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    if args.install:
        library.mkdir(parents=True)
        log = library / "install.log"
        with log.open("w") as handle:
            subprocess.run(["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(source)],
                           check=True, stdout=handle, stderr=subprocess.STDOUT, text=True)
        payload.update(status="installed_diagnostic_runtime", install_log=str(log),
                       install_log_sha256=sha256(log), probe=probe(library))
        manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    else:
        (source_root / MANIFEST_NAME).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return payload


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
