# Article-Q-DESN authoritative repository sync note

Date: 2026-07-09

## Authoritative repository

The active Article-Q-DESN manuscript repository is now:

```text
GitHub: https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git
Local:  /data/jaguir26/local/src/Article-Q-DESN---Version-2
Branch: main
```

This is the repository linked to the working Overleaf project:

```text
AntonioAPDL/Article-Q-DESN---Version-2
```

The previous repository,

```text
https://github.com/AntonioAPDL/Article-Q-DESN.git
```

is now an archive/probe repository for historical context only. The accidentally
created single-hyphen v2 repository,

```text
https://github.com/AntonioAPDL/Article-Q-DESN-Version-2.git
```

is not the Overleaf-linked repository and should not receive new manuscript
work.

## Snapshot verification

The new authoritative repository was initialized from the repaired old article
state. The tracked file tree matches the repaired old `main` exactly:

```text
old repaired main commit: 7df763c34571a2b6f78a8e601a650ac8839febe0
old repaired main tree:   baac757cb9dfdcd0187bb676c724cb3e26627f99
new repository baseline:  3eb663264bdfca520223425752d9e3ea8e204e7d
new repository tree:      baac757cb9dfdcd0187bb676c724cb3e26627f99
tracked files:            1456
```

The histories differ intentionally; the tracked content is the same clean
snapshot. This avoids carrying forward the broken Overleaf/GitHub browser-sync
state.

## Old-checkout audit decision

A file-by-file audit compared the new authoritative repository against the old
repository, old worktrees, and the dirty old application branch. The audit found
no tracked article changes that should be imported into the new repository.

Key decision:

```text
No application scripts, validation scripts, QDESN, joint-QDESN, PriceFM, or
GloFAS implementation files were imported.
No stale GloFAS/PriceFM artifact sets were imported.
No old article-core files replaced the authoritative current versions.
```

The old active branch contains application and validation-script work tied to
`application-ensemble-likelihood-redesign`. It is intentionally not part of this
Overleaf manuscript sync.

## Local-only audit material

Detailed raw diff inventories, classified per-file decisions, and a few
old-branch documentation candidates are preserved locally under ignored
`.codex_work/` directories. They are not part of the Overleaf/GitHub tracked
manuscript state.

## Overleaf workflow

Future article work should be committed only to:

```text
https://github.com/AntonioAPDL/Article-Q-DESN---Version-2.git
```

After a pushed article commit, the Overleaf project linked to
`AntonioAPDL/Article-Q-DESN---Version-2` should use **Pull GitHub changes into
Overleaf**.
