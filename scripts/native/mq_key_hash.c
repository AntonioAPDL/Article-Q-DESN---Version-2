/* SPDX-License-Identifier: MIT
 * Original candidate implementation, 2026 Q-DESN contributors.
 * Uses public R serialization APIs and the system OpenSSL SHA256 API.
 * No R, digest or OpenSSL implementation source is copied here.
 * See ../../docs/implementation_notes/mq_native_key_hash_candidate_20261102.md.
 */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>
#include <openssl/sha.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>

struct mqk_buffer {
    unsigned char *bytes;
    size_t used;
    size_t capacity;
};

static void mqk_out_bytes(R_outpstream_t stream, void *source, int length)
{
    struct mqk_buffer *b = (struct mqk_buffer *) stream->data;
    if (length < 0 || (size_t) length > b->capacity - b->used)
        Rf_error("MQ native key: serialized key exceeds bounded buffer");
    memcpy(b->bytes + b->used, source, (size_t) length);
    b->used += (size_t) length;
}

static void mqk_out_char(R_outpstream_t stream, int value)
{
    unsigned char ch = (unsigned char) value;
    mqk_out_bytes(stream, &ch, 1);
}

static void mqk_serialize(SEXP key, struct mqk_buffer *buffer)
{
    struct R_outpstream_st output;
    buffer->used = 0;
    R_InitOutPStream(&output, (R_pstream_data_t) buffer,
                    R_pstream_xdr_format, 2, mqk_out_char, mqk_out_bytes,
                    NULL, R_NilValue);
    R_Serialize(key, &output);
    /* digest 0.6.39 set_skip(raw, ascii=FALSE) skips these 14 bytes.
       Check the format/version rather than silently assuming a new format. */
    if (buffer->used < 14 || buffer->bytes[0] != 'X' || buffer->bytes[1] != '\n' ||
        buffer->bytes[2] != 0 || buffer->bytes[3] != 0 ||
        buffer->bytes[4] != 0 || buffer->bytes[5] != 2)
        Rf_error("MQ native key: unexpected R version-2 XDR header");
}

static double mqk_first_uniform(const uint32_t seed[6])
{
    const int64_t m1 = INT64_C(4294967087), m2 = INT64_C(4294944443);
    int64_t p1 = (INT64_C(1403580) * seed[1] - INT64_C(810728) * seed[0]) % m1;
    int64_t p2 = (INT64_C(527612) * seed[5] - INT64_C(1370589) * seed[3]) % m2;
    if (p1 < 0) p1 += m1;
    if (p2 < 0) p2 += m2;
    /* Same positive integer difference and final binary64 multiplication
       as the existing source's first-step-only CMRG specialization. */
    return (double) (p1 > p2 ? p1 - p2 : p1 - p2 + m1) *
           2.328306549295727688e-10;
}

static void mqk_check_strings(SEXP x, const char *label)
{
    if (TYPEOF(x) != STRSXP || XLENGTH(x) < 1 || Rf_isObject(x) ||
        R_getAttribCount(x) != 0 || ALTREP(x))
        Rf_error("MQ native key: plain materialized %s strings required", label);
    for (R_xlen_t i = 0; i < XLENGTH(x); ++i) {
        SEXP ch = STRING_ELT(x, i);
        if (ch == NA_STRING || LENGTH(ch) < 1 || LENGTH(ch) > 1048576)
            Rf_error("MQ native key: invalid or overlarge %s string", label);
    }
}

SEXP mq_key_hash_batch(SEXP template, SEXP inner, SEXP horizons, SEXP audit)
{
    static const char *fields[7] = {"version", "scientific_identity", "draw",
                                  "origin", "inner", "horizon", "purpose"};
    if (TYPEOF(template) != VECSXP || XLENGTH(template) != 7 || Rf_isObject(template))
        Rf_error("MQ native key: exact seven-field template required");
    SEXP names = Rf_getAttrib(template, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != 7)
        Rf_error("MQ native key: exact ordered names required");
    if (R_getAttribCount(template) != 1 || !R_hasAttrib(template,R_NamesSymbol))
        Rf_error("MQ native key: unexpected template attributes");
    for (int j = 0; j < 7; ++j)
        if (STRING_ELT(names,j) == NA_STRING || strcmp(CHAR(STRING_ELT(names,j)),fields[j]))
            Rf_error("MQ native key: template names/order changed");
    SEXP version = VECTOR_ELT(template,0);
    if (TYPEOF(version) != INTSXP || XLENGTH(version) != 1 || INTEGER(version)[0] != 1 ||
        R_getAttribCount(version) != 0)
        Rf_error("MQ native key: original integer version required");
    size_t capacity = 4096;
    for (int j = 1; j < 7; ++j) {
        SEXP value = VECTOR_ELT(template,j);
        if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 || Rf_isObject(value) ||
            R_getAttribCount(value) != 0 || ALTREP(value) || STRING_ELT(value,0) == NA_STRING ||
            LENGTH(STRING_ELT(value,0)) > 1048576)
            Rf_error("MQ native key: exact unclassed scalar strings required");
        capacity += (size_t) LENGTH(STRING_ELT(value,0));
    }
    if (strcmp(CHAR(STRING_ELT(VECTOR_ELT(template,6),0)),"response"))
        Rf_error("MQ native key: original response purpose required");
    mqk_check_strings(inner,"inner"); mqk_check_strings(horizons,"horizon");
    if (TYPEOF(audit) != LGLSXP || XLENGTH(audit) != 1 || LOGICAL(audit)[0] == NA_LOGICAL)
        Rf_error("MQ native key: explicit audit flag required");
    const R_xlen_t N = XLENGTH(inner), H = XLENGTH(horizons);
    if (N > INT_MAX || H > INT_MAX || N > INT_MAX / H)
        Rf_error("MQ native key: matrix dimensions overflow");
    const R_xlen_t count = N * H;
    const int capture = LOGICAL(audit)[0];
    if (capture && count > 1024)
        Rf_error("MQ native key: audit is bounded to 1024 tuples");
    size_t maximum_inner = 0, maximum_horizon = 0;
    for (R_xlen_t i=0;i<N;++i) if ((size_t)LENGTH(STRING_ELT(inner,i)) > maximum_inner)
        maximum_inner = (size_t)LENGTH(STRING_ELT(inner,i));
    for (R_xlen_t h=0;h<H;++h) if ((size_t)LENGTH(STRING_ELT(horizons,h)) > maximum_horizon)
        maximum_horizon = (size_t)LENGTH(STRING_ELT(horizons,h));
    capacity += maximum_inner + maximum_horizon;
    if (capture && capacity > ((size_t)67108864) / (size_t)count)
        Rf_error("MQ native key: complete raw audit would exceed64MiB");
    struct mqk_buffer buffer;
    buffer.bytes = (unsigned char *) R_alloc(capacity,1);
    buffer.capacity = capacity; buffer.used = 0;
    SEXP key = PROTECT(Rf_duplicate(template));
    SEXP uniform = PROTECT(Rf_allocMatrix(REALSXP,(int)N,(int)H));
    SEXP seeds = PROTECT(capture ? Rf_allocMatrix(INTSXP,(int)count,6) : R_NilValue);
    SEXP hashes = PROTECT(capture ? Rf_allocMatrix(STRSXP,(int)N,(int)H) : R_NilValue);
    SEXP bytes = PROTECT(capture ? Rf_allocVector(VECSXP,count) : R_NilValue);
    static const char hexchars[] = "0123456789abcdef";
    for (R_xlen_t h=0;h<H;++h) {
        SET_VECTOR_ELT(key,5,Rf_ScalarString(STRING_ELT(horizons,h)));
        for (R_xlen_t i=0;i<N;++i) {
            if ((i & 127) == 0) R_CheckUserInterrupt();
            SET_VECTOR_ELT(key,4,Rf_ScalarString(STRING_ELT(inner,i)));
            mqk_serialize(key,&buffer);
            unsigned char digest[SHA256_DIGEST_LENGTH];
            if (SHA256(buffer.bytes+14,buffer.used-14,digest) == NULL)
                Rf_error("MQ native key: SHA256 failed");
            uint32_t words[6];
            const R_xlen_t at = h*N+i;
            for (int j=0;j<6;++j) {
                uint32_t word=0;
                for (int k=0;k<7;++k) {
                    const int nibble=j*7+k;
                    word=(word<<4) | ((digest[nibble/2] >> ((nibble%2) ? 0 : 4)) & 15);
                }
                words[j]=word+1;
                if (capture) INTEGER(seeds)[at+count*j]=(int)words[j];
            }
            REAL(uniform)[at]=mqk_first_uniform(words);
            if (capture) {
                char text[2*SHA256_DIGEST_LENGTH+1];
                for (int j=0;j<SHA256_DIGEST_LENGTH;++j) {
                    text[2*j]=hexchars[digest[j]>>4]; text[2*j+1]=hexchars[digest[j]&15];
                }
                text[2*SHA256_DIGEST_LENGTH]='\0';
                SET_STRING_ELT(hashes,at,Rf_mkChar(text));
                SEXP raw=PROTECT(Rf_allocVector(RAWSXP,(R_xlen_t)buffer.used));
                memcpy(RAW(raw),buffer.bytes,buffer.used);
                SET_VECTOR_ELT(bytes,at,raw); UNPROTECT(1);
            }
        }
    }
    SEXP result=PROTECT(Rf_allocVector(VECSXP,4));
    SEXP result_names=PROTECT(Rf_allocVector(STRSXP,4));
    const char *labels[4]={"uniforms","seed_words","digests","serialized"};
    for (int j=0;j<4;++j) SET_STRING_ELT(result_names,j,Rf_mkChar(labels[j]));
    SET_VECTOR_ELT(result,0,uniform); SET_VECTOR_ELT(result,1,seeds);
    SET_VECTOR_ELT(result,2,hashes); SET_VECTOR_ELT(result,3,bytes);
    Rf_setAttrib(result,R_NamesSymbol,result_names);
    UNPROTECT(7);
    return result;
}

static const R_CallMethodDef mqk_calls[] = {
    {"mq_key_hash_batch",(DL_FUNC)&mq_key_hash_batch,4},
    {NULL,NULL,0}
};
void attribute_visible R_init_mq_key_hash(DllInfo *dll)
{
    R_registerRoutines(dll,NULL,mqk_calls,NULL,NULL);
    R_useDynamicSymbols(dll,FALSE);
    R_forceSymbols(dll,TRUE);
}
