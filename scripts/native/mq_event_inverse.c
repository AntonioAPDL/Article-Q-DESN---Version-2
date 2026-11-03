/* SPDX-License-Identifier: MIT
 * Original generated-only event/search and pointwise-CDF candidate.
 * No private R entry point or copied R implementation is used.
 * R retains event construction/sorting/grouping, cumsum and mean arithmetic.
 */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

static SEXP mqe_first_indices(SEXP right, SEXP probability)
{
    if (TYPEOF(right) != REALSXP || TYPEOF(probability) != REALSXP ||
        XLENGTH(right) < 1 || XLENGTH(right) > 4000000 ||
        XLENGTH(probability) < 1 || XLENGTH(probability) > 64)
        Rf_error("MQ event candidate: bounded real CDF/probability vectors required");
    R_xlen_t n = XLENGTH(right), m = XLENGTH(probability);
    for (R_xlen_t j=0;j<n;j++)
        if (!R_FINITE(REAL(right)[j])) Rf_error("MQ event candidate: nonfinite CDF");
    SEXP out=PROTECT(Rf_allocVector(INTSXP,m));
    for (R_xlen_t k=0;k<m;k++) {
        double p=REAL(probability)[k];
        if (!R_FINITE(p) || p <= 0 || p >= 1)
            Rf_error("MQ event candidate: interior finite probabilities required");
        INTEGER(out)[k]=NA_INTEGER;
        /* Independent first-index scans preserve the exact which(right>=p)[1]
         * interpretation even for repeated/unsorted query probabilities. */
        for (R_xlen_t j=0;j<n;j++) if (REAL(right)[j] >= p) {
            INTEGER(out)[k]=(int)j+1;break;
        }
        R_CheckUserInterrupt();
    }
    UNPROTECT(1);return out;
}

static SEXP mqe_cdf_values(SEXP matrix, SEXP tau, SEXP queries)
{
    SEXP d=Rf_getAttrib(matrix,R_DimSymbol);
    if (TYPEOF(matrix)!=REALSXP || TYPEOF(d)!=INTSXP || XLENGTH(d)!=2 ||
        TYPEOF(tau)!=REALSXP || TYPEOF(queries)!=REALSXP)
        Rf_error("MQ event candidate: real ordered matrix/grid/queries required");
    int n=INTEGER(d)[0],K=INTEGER(d)[1];R_xlen_t M=XLENGTH(queries);
    if(n<1 || n>262144 || K<2 || K>64 || XLENGTH(tau)!=K || M<1 || M>128 ||
       XLENGTH(matrix)!=(R_xlen_t)n*K || (double)n*M>8388608)
        Rf_error("MQ event candidate: pointwise matrix exceeds declared bounds");
    const double *q=REAL(matrix),*p=REAL(tau),*y=REAL(queries);
    for(int k=0;k<K;k++) {
        if(!R_FINITE(p[k]) || p[k]<=0 || p[k]>=1 || (k && p[k]<=p[k-1]))
            Rf_error("MQ event candidate: ordered interior levels required");
        for(int i=0;i<n;i++) {
            R_xlen_t at=i+(R_xlen_t)n*k;
            if(!R_FINITE(q[at]) || (k && q[at]<q[at-n]))
                Rf_error("MQ event candidate: finite already ordered rows required");
        }
    }
    SEXP out=PROTECT(Rf_allocMatrix(REALSXP,n,(int)M));
    for(R_xlen_t j=0;j<M;j++) {
        if(!R_FINITE(y[j]))Rf_error("MQ event candidate: finite query required");
        for(int i=0;i<n;i++) {
            int k=0;while(k<K && q[i+(R_xlen_t)n*k]<=y[j])k++;
            double value=0.;
            if(k==K)value=1.;
            else if(k>0) {
                double low=q[i+(R_xlen_t)n*(k-1)],high=q[i+(R_xlen_t)n*k];
                /* Same binary64 operation order as the canonical R expression.
                 * Do not reassociate or contract multiplication/addition. */
                value=p[k-1]+(p[k]-p[k-1])*(y[j]-low)/(high-low);
            }
            REAL(out)[i+(R_xlen_t)n*j]=value;
        }
        R_CheckUserInterrupt();
    }
    UNPROTECT(1);return out;
}

static const R_CallMethodDef entries[]={
    {"mqe_first_indices",(DL_FUNC)&mqe_first_indices,2},
    {"mqe_cdf_values",(DL_FUNC)&mqe_cdf_values,3},
    {NULL,NULL,0}
};
void attribute_visible R_init_mq_event_inverse(DllInfo *dll)
{
    R_registerRoutines(dll,NULL,entries,NULL,NULL);
    R_useDynamicSymbols(dll,FALSE);R_forceSymbols(dll,TRUE);
}
