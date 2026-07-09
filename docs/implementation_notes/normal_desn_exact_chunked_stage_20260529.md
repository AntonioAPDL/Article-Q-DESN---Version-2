# Normal DESN Exact Chunked Scaled-Ridge Stage

Date: 2026-05-29

## Scope

This stage implements exact row chunking for the Normal DESN scaled-ridge
readout in the shared validation package worktree:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
```

No Overleaf/main files were edited.

The stage is deliberately narrow:

- scaled-ridge Normal DESN only;
- deterministic sequential row chunks only;
- full-data target preserved exactly;
- RHS/RHS_NS Normal DESN chunking remains forbidden;
- stochastic/hybrid Normal DESN batching remains future work.

## Mathematical Target

The model remains the exact Normal-inverse-gamma readout:

```text
y | beta, omega2, X ~ N(X beta, omega2 I)
beta | omega2       ~ N(b, omega2 P^{-1})
omega2              ~ IG(a, b)
```

Chunking only changes how the row-additive sufficient statistics are
accumulated:

```text
X'X = sum_b X_b' X_b
X'y = sum_b X_b' y_b
y'y = sum_b y_b' y_b
```

After accumulation, the posterior equations are unchanged:

```text
P_n = P + X'X
h_n = P b + X'y
m_n = P_n^{-1} h_n
a_n = a + T / 2
B_n = b + 0.5 (y'y + b'P b - m_n'P_n m_n)
```

Thus exact chunking is a memory/workflow feature, not a new approximation.

## API

The package now accepts exact chunking through `normal_desn_fit()`:

```r
normal_desn_fit(
  X,
  y,
  beta_prior_type = "scaled_ridge",
  control = list(
    chunking = list(
      enabled = TRUE,
      mode = "exact",
      chunk_size = 512L,
      order = "sequential",
      trace = FALSE
    )
  )
)
```

The same control passes through `qdesn_fit_normal()` via
`normal_args$control$chunking`.

Unsupported settings fail early:

- non-`exact` chunking modes;
- non-sequential chunk order;
- missing or non-positive `chunk_size`;
- RHS/RHS_NS chunking.

## Validation

Focused package tests were run with R 4.6.0:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
git diff --check
```

Results:

```text
test-qdesn-normal.R: 133 pass, 0 fail
test-qdesn-vb-likelihood-family.R: 12 pass, 0 fail
test-qdesn-vb-batching-modes.R: 42 pass, 0 fail
test-static-beta-prior-rhs.R: 110 pass, 0 fail
git diff --check: passed
```

The Normal DESN test suite verifies:

- one chunk equals the unchunked scaled-ridge posterior;
- several chunks equal the unchunked scaled-ridge posterior;
- chunk size one equals the unchunked scaled-ridge posterior;
- `qdesn_fit_normal()` forwards chunking to the readout;
- beta means, beta covariance, scale covariance, omega2 shape/rate, fitted
  means, sufficient statistics, and log marginal likelihood match the
  unchunked reference;
- unsupported chunking controls fail early;
- RHS/RHS_NS chunking fails early.

## Current Interpretation

Normal DESN exact chunking is now ready to use as the full-data-preserving
scaled-ridge baseline and as a memory-safe source of AL/exAL initialization
moments.

RHS/RHS_NS Normal DESN remains an approximate global VB readout. It is not
chunked in this stage because the global shrinkage state should not be
row-updated without a separate derivation and validation gate.

## Next Stage

The next roadmap stage is the economical source-median comparison harness:

```text
scripts/run_normal_desn_source_median_comparison_20260529.R
docs/implementation_notes/normal_desn_source_median_comparison_20260529.md
```

That stage should compare Normal scaled ridge, Normal exact chunked scaled
ridge, Normal RHS/RHS_NS VB, and the currently implemented Q-DESN AL/exAL
methods on the frozen Gaussian median validation source subset.
