"""Nine independent analytical Gaussian fixtures. NOT executed by admin tests.

Expected values use diagonal identities, Sherman-Morrison, and a closed 2x2
inverse, independently of the Cholesky/linear solver. These are compute tests,
not a claim of qualified synthetic execution, target parity or scientific success.
"""
FIXTURE_PLAN = {"schema": "r200_analytic_reference_fixture_request_v1",
                "sizes": [8, 16, 32],
                "families": ["diagonal", "rank_one", "paired_ill_conditioned"],
                "optimizer_updates": 0, "new_posterior_fits": 0}
EXPECTED_IDENTITIES = {
    "diagonal": "P_ii=2^(-2i); b=P*1; beta_i=1; inverse_ii=2^(2i)",
    "rank_one": "P=I+11'/8; beta_i=(-1)^i (even p); inverse=I-11'/(8+p)",
    "paired_ill_conditioned": "Pblock=[[1,1-e],[1-e,1]], e=2^-40; beta=[1,-1]; inverse=(1/(2e-e^2))*[[1,-(1-e)],[-(1-e),1]]"
}

def _run_compute_only(kernel):
    # No module-level numeric constants, matrices or generated targets.
    from fractions import Fraction as F
    from decimal import Decimal as D, localcontext
    rows = []
    for p in FIXTURE_PLAN["sizes"]:
        for family in FIXTURE_PLAN["families"]:
            P = [[F(0) for _ in range(p)] for _ in range(p)]
            expected_V = [[F(0) for _ in range(p)] for _ in range(p)]
            if family == "diagonal":
                expected_beta = [F(1)] * p
                for i in range(p):
                    P[i][i] = F(1, 2 ** (2 * i))
                    expected_V[i][i] = F(2 ** (2 * i))
            elif family == "rank_one":
                expected_beta = [F(1 if i % 2 == 0 else -1) for i in range(p)]
                for i in range(p):
                    for j in range(p):
                        P[i][j] = F(int(i == j)) + F(1, 8)
                        expected_V[i][j] = F(int(i == j)) - F(1, 8 + p)
            else:
                expected_beta = [F(1 if i % 2 == 0 else -1) for i in range(p)]
                e = F(1, 2**40)
                divisor = 2 * e - e * e
                for i in range(0, p, 2):
                    P[i][i] = P[i+1][i+1] = F(1)
                    P[i][i+1] = P[i+1][i] = 1-e
                    expected_V[i][i] = expected_V[i+1][i+1] = 1/divisor
                    expected_V[i][i+1] = expected_V[i+1][i] = -(1-e)/divisor
            b = [sum((P[i][j]*expected_beta[j] for j in range(p)), F(0)) for i in range(p)]
            with localcontext() as ctx:
                ctx.prec = 200
                convert = lambda x: D(x.numerator) / D(x.denominator)
                PP = [[convert(x) for x in row] for row in P]
                bb = [convert(x) for x in b]
                expected_m = [convert(x) for x in expected_beta]
                expected_cov = [[convert(x) for x in row] for row in expected_V]
                for digits in (80, 120, 160):
                    beta, V = kernel._gaussian(PP, bb, digits)
                    beta_error = max((a-z).copy_abs() for a,z in zip(beta, expected_m))
                    covariance_error = max(sum(((a-z).copy_abs() for a,z in zip(aa,zz)), D(0))
                                           for aa,zz in zip(V, expected_cov))
                    tolerance = D(10) ** (-(digits // 2))
                    if beta_error > tolerance or covariance_error > tolerance:
                        raise ValueError("analytical oracle mismatch")
                    bounds = kernel._outward_forward_bounds(PP, bb, beta, V, digits+24)
                    if bounds["status"] != "RIGOROUS_COMPONENT_BOUND_FOR_EXACT_STORED_P_RHS":
                        raise ValueError("analytic forward bound unearned")
                    rows.append({"size":p, "family":family, "precision":digits,
                                 "beta_error":str(beta_error),
                                 "covariance_error":str(covariance_error),
                                 "component_bounds":bounds})
    return {"schema":"r200_analytic_reference_result_v1",
            "status":"COMPUTE_ANALYTIC_COMPONENT_FIXTURES_PASSED_NOT_TARGET_ACCEPTANCE",
            "cases":9, "precision_evaluations":27, "rows":rows,
            "target_parity":False, "native_bootstrap_qualification_transferred":False,
            "full_prior_objective_rounding_budget_qualified":False,
            "optimizer_updates":0, "new_posterior_fits":0}
