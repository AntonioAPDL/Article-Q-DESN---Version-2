/* Opt-in batched adaptation of R 4.6.0 src/library/stats/src/isoreg.c.
 * Numerical cumulative-minorant loop adapted from:
 * Copyright (C) 1995 Brian Ripley
 * Copyright (C) 2003-2024 The R Core Team
 * Copyright (C) 2003-2023 The R Foundation
 * Batch/registration modifications: 2026 repository contributors.
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 * See ../licenses/mq_isoreg_GPL-2.txt and https://www.R-project.org/Licenses/.
 *
 * Preserve the native sequential double sums, strict '<' earliest-tie
 * minimum-slope scan and final slope recomputation. This is not sorting,
 * probability-weighted projection, or a block-mean reassociation.
 */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

static SEXP mqi_project(SEXP x)
{
    SEXP dim = Rf_getAttrib(x, R_DimSymbol);
    if (TYPEOF(x) != REALSXP || TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2)
        Rf_error("MQ isoreg candidate requires a real matrix");
    int rows = INTEGER(dim)[0], cols = INTEGER(dim)[1];
    if (rows < 1 || rows > 1000000 || cols < 2 || cols > 64 ||
        XLENGTH(x) != (R_xlen_t) rows * cols)
        Rf_error("MQ isoreg candidate requires 1-1000000 rows and 2-64 levels");
    SEXP out = PROTECT(Rf_allocMatrix(REALSXP, rows, cols));
    Rf_setAttrib(out, R_DimNamesSymbol, Rf_getAttrib(x, R_DimNamesSymbol));
    double *cum = (double *) R_alloc((size_t) cols + 1, sizeof(double));
    const double *input = REAL(x);
    double *output = REAL(out);
    for (int row = 0; row < rows; row++) {
        int crossed = 0;
        for (int col = 0; col < cols; col++) {
            R_xlen_t at = row + (R_xlen_t) rows * col;
            if (!R_FINITE(input[at])) Rf_error("MQ isoreg candidate requires finite entries");
            output[at] = input[at];
            if (col && input[at] < input[at - rows]) crossed = 1;
        }
        /* Canonical app_iqf_grid does not call isoreg on an ordered row.
         * Preserve its bits before computing any possibly overflowing sum. */
        if (!crossed) continue;
        cum[0] = 0.;
        double tmp = 0.;
        for (int col = 0; col < cols; col++) {
            tmp += input[row + (R_xlen_t) rows * col];
            cum[col + 1] = tmp;
        }
        if (!R_FINITE(cum[cols]))
            Rf_error("MQ isoreg candidate: non-finite sum(y) is not allowed");
        int known = 0, endpoint = 0;
        do {
            double slope = R_PosInf;
            for (int col = known + 1; col <= cols; col++) {
                tmp = (cum[col] - cum[known]) / (col - known);
                if (tmp < slope) { slope = tmp; endpoint = col; }
            }
            if (endpoint <= known)
                Rf_error("MQ isoreg candidate: unresolved cumulative-minorant segment");
            for (int col = known; col < endpoint; col++)
                output[row + (R_xlen_t) rows * col] =
                    (cum[endpoint] - cum[known]) / (endpoint - known);
        } while ((known = endpoint) < cols);
        if ((row & 1023) == 0) R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return out;
}

static const R_CallMethodDef calls[] = {
    {"mqi_project", (DL_FUNC) &mqi_project, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_mq_isoreg_batch(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
