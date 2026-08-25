#!/usr/bin/env python3
"""Download and pin the canonical PriceFM raw artifacts."""

from __future__ import print_function

from pathlib import Path

from pricefm_common import (
    load_config, now_utc, parser, pricefm_block, raw_csv_path, repo_path,
    require_modules, run_command, sha256_file, summarize, write_json,
)


def main():
    p = parser(__doc__)
    args = p.parse_args()
    cfg = load_config(args.config)
    require_modules(["huggingface_hub"])

    from huggingface_hub import HfApi, hf_hub_download

    spec = pricefm_block(cfg)
    raw_dir = repo_path(spec["raw_dir"])
    raw_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = raw_dir / "download_manifest.json"
    if raw_csv_path(cfg).exists() and manifest_path.exists() and not args.force:
        raise FileExistsError(
            "{} and {} already exist. Re-run with --force true to refresh.".format(
                raw_csv_path(cfg), manifest_path
            )
        )

    api = HfApi()
    info = api.dataset_info(spec["repo_id"])
    revision = info.sha

    csv_path = Path(
        hf_hub_download(
            repo_id=spec["repo_id"],
            filename=spec["filename"],
            repo_type="dataset",
            revision=revision,
            local_dir=str(raw_dir),
        )
    )

    github_commit = None
    external_dir = repo_path(spec.get("external_repo_dir", "application/data_local/pricefm/external/PriceFM"))
    github_repo = spec.get("source", {}).get("github_repo")
    if github_repo:
        external_dir.parent.mkdir(parents=True, exist_ok=True)
        if not external_dir.exists():
            run_command(["git", "clone", github_repo, str(external_dir)])
        github_commit = run_command(["git", "rev-parse", "HEAD"], cwd=external_dir)
        with open(raw_dir / "pricefm_git_commit.txt", "w") as f:
            f.write(github_commit + "\n")

    sha = sha256_file(csv_path)
    expected_sha = spec.get("source", {}).get("hf_sha256_expected")
    if expected_sha and sha != expected_sha:
        raise RuntimeError(
            "Downloaded SHA256 {} does not match expected {}.".format(sha, expected_sha)
        )

    manifest = {
        "created_at_utc": now_utc(),
        "dataset_repo_id": spec["repo_id"],
        "dataset_revision": revision,
        "filename": spec["filename"],
        "local_path": str(csv_path),
        "file_size_bytes": csv_path.stat().st_size,
        "sha256_local": sha,
        "sha256_expected_from_hf_ui": expected_sha,
        "xet_hash_from_hf_ui": spec.get("source", {}).get("hf_xet_hash_expected"),
        "license": spec.get("source", {}).get("license"),
        "github_repo": github_repo,
        "github_commit": github_commit,
    }
    write_json(manifest_path, manifest)
    summarize(csv_path, {"sha256": sha, "dataset_revision": revision, "github_commit": github_commit})


if __name__ == "__main__":
    main()
