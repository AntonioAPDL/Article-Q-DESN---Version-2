# Immutable numerical runtime and observational identity-service state

The first ancestor-first IND preflight at source `45e3e01b2c1342bb2a538e4cafaaa6e6558a5bae`
stopped before reading the training RDS or running a filter. It correctly found
that the declared runtime-byte inventory no longer matched the process.
Inspection isolated the difference to SSSD identity caches: `passwd` changed
bytes and a `group` mapping appeared. The failed purpose, source, manifest and
terminal accounting remain historical evidence; they are not repaired in place.
This was an admission failure, not a numerical filter result.

`scripts/runtime_identity_cache_observations.R` introduces an explicit boundary
between immutable numerical runtime inputs and unrelated OS identity-service
state. Only these exact Muscat paths qualify as observational:

```
/var/lib/sss/mc/passwd
/var/lib/sss/mc/group
/var/lib/sss/mc/initgroups
```

Each observed file must be regular, canonical and nonsymlink; belong to the
native SSSD service UID/GID 981; have mode 0664, no executable file bits, and
no executable process mapping. Every mapping of a file is checked, not just
its first segment. Sizes must be positive and at most 64 MiB per cache.
Unknown `/var/lib/sss/` mappings, deleted mappings and ownership/type/mode
masquerades are rejected. This is not a `/var/lib`, nonexecutable-data-file,
basename or mutable-file exemption. Unrelated mapped files remain strict.

The helper returns paths, numeric ownership, mode, size, mapping permissions
and an observed SHA-256 for the allowed live caches. These are non-atomic
observations of OS state, not immutable software pins; consumers retain them
separately before and after execution without demanding byte equality or a
constant set of identity-cache mappings. The helper does not change mappings,
clear caches, call privileged operations or modify environment-based NSS
behavior. It never reads a model or scientific input.

All numerical inputs, source files, installed package files, mapped software,
`libnss*.so`, R/BLAS and other required executable/library files remain subject
to their unchanged exact-byte requirements. A changed scientific or software
hash remains an admission failure. The new helper itself must join every
consumer's exact transitive source inventory.

APIs:

- `runtime_ic_mappings(lines)` parses native file-backed mappings and rejects
  deleted or malformed entries.
- `runtime_ic_classify(mappings, metadata)` is a pure classifier used by the
  generated negative tests. It returns `strict_mapped_paths`,
  `observational_paths`, and classified metadata.
- `runtime_ic_snapshot()` reads process/cache metadata and returns the strict
  mapped paths and `observational_os_state`, plus its explicit observation role.

The new source requires fresh review, runtime preparation, source publication
and a new finite purpose before another authentic attempt. Neither passing
the classifier tests nor recording cache state grants numerical admission.
