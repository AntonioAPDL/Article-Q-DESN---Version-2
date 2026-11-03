"""Compute-only independent references; no arithmetic executes at import.

Only reference_compute's actual owned entrypoint calls _compute or _synthetic.
No optimizer, certificate acceptance, production replacement or grant API exists.
Input binary64 values are imported exactly with Decimal.from_float, never str.
"""

def _imports():
    from decimal import Decimal, localcontext, ROUND_FLOOR, ROUND_CEILING
    from fractions import Fraction
    import math
    import struct
    return Decimal, localcontext, ROUND_FLOOR, ROUND_CEILING, Fraction, math, struct

def _require(ok, why):
    if not ok:
        raise ValueError(why)

def _decode(raw, count):
    D, _, _, _, _, math, struct = _imports()
    _require(type(raw) is bytes and len(raw) == count * 8, "exact binary64 byte count")
    values = []
    for (value,) in struct.iter_unpack("<d", raw):
        _require(math.isfinite(value), "nonfinite stored binary64")
        values.append(D.from_float(value))
    return values

def _hex(value):
    D, _, _, _, _, math, _ = _imports()
    _require(type(value) is str and value.startswith(("0x", "-0x")), "binary64 hex required")
    number = float.fromhex(value)
    _require(math.isfinite(number), "nonfinite binary64 hex")
    return D.from_float(number)

def _matrix(flat, rows, cols):
    _require(len(flat) == rows * cols, "column-major matrix length")
    return [[flat[i + j * rows] for j in range(cols)] for i in range(rows)]

def _cholesky(A):
    D, _, _, _, _, _, _ = _imports()
    p = len(A)
    _require(1 <= p <= 1024 and all(len(row) == p for row in A), "bounded full matrix")
    _require(all(A[i][j] == A[j][i] for i in range(p) for j in range(p)),
             "exact binary64 symmetry; no averaging or jitter")
    L = [[D(0) for _ in range(p)] for _ in range(p)]
    for i in range(p):
        for j in range(i + 1):
            term = A[i][j] - sum((L[i][k] * L[j][k] for k in range(j)), D(0))
            if i == j:
                _require(term > 0, "nonpositive pivot; no fallback")
                L[i][j] = term.sqrt()
            else:
                L[i][j] = term / L[j][j]
    return L

def _solve_from_cholesky(L, b):
    D, _, _, _, _, _, _ = _imports()
    p = len(b)
    y = []
    for i in range(p):
        y.append((b[i] - sum((L[i][j] * y[j] for j in range(i)), D(0))) / L[i][i])
    x = [D(0)] * p
    for i in range(p - 1, -1, -1):
        x[i] = (y[i] - sum((L[j][i] * x[j] for j in range(i + 1, p)), D(0))) / L[i][i]
    return x

def _gaussian(P, b, digits):
    D, localcontext, _, _, _, _, _ = _imports()
    with localcontext() as ctx:
        ctx.prec = digits
        L = _cholesky(P)
        beta = _solve_from_cholesky(L, b)
        columns = [_solve_from_cholesky(L, [D(int(i == j)) for i in range(len(b))])
                   for j in range(len(b))]
        V = [[columns[j][i] for j in range(len(b))] for i in range(len(b))]
        # Retain both evaluated triangles: never silently symmetrize results.
        return beta, V

def _outward_forward_bounds(P, b, beta, V, digits):
    """Component forward bounds from a full approximate inverse.

    Outward-rounded arithmetic encloses r=||I-PV||inf and e=||P beta-b||inf.
    If r<1, ||P^-1||inf <= ||V||inf/(1-r). No stability or backward residual
    alone is promoted to a forward-error claim. Bounds concern this exact P/b
    and the supplied returned beta/V, not target construction or seven gates.
    """
    D, localcontext, DOWN, UP, _, _, _ = _imports()
    p = len(b)
    def product_sum(xs, ys, rounding):
        with localcontext() as ctx:
            ctx.prec = digits
            ctx.rounding = rounding
            total = D(0)
            for x, y in zip(xs, ys):
                total += x * y
            return total
    def subtract(a, bvalue, rounding):
        with localcontext() as ctx:
            ctx.prec = digits
            ctx.rounding = rounding
            return a - bvalue
    def upper_sum(xs):
        with localcontext() as ctx:
            ctx.prec = digits
            ctx.rounding = UP
            total = D(0)
            for value in xs:
                total += value
            return total
    rho_rows = []
    for i in range(p):
        absolute = []
        for j in range(p):
            column = [V[k][j] for k in range(p)]
            low = subtract(product_sum(P[i], column, DOWN), D(int(i == j)), DOWN)
            high = subtract(product_sum(P[i], column, UP), D(int(i == j)), UP)
            absolute.append(max(low.copy_abs(), high.copy_abs()))
        rho_rows.append(upper_sum(absolute))
    rho = max(rho_rows)
    residual = []
    for i in range(p):
        low = subtract(product_sum(P[i], beta, DOWN), b[i], DOWN)
        high = subtract(product_sum(P[i], beta, UP), b[i], UP)
        residual.append(max(low.copy_abs(), high.copy_abs()))
    e = max(residual)
    vnorm = max(upper_sum([x.copy_abs() for x in row]) for row in V)
    result = {"inverse_residual_inf_upper": str(rho),
              "mean_residual_inf_upper": str(e), "covariance_inf_upper": str(vnorm),
              "exact_input_binary64": True, "outward_precision": digits,
              "target_construction_bound": None, "all_seven_measures_certified": False}
    if rho >= 1:
        result.update(status="FORWARD_BOUND_UNEARNED_RHO_NOT_BELOW_ONE",
                      inverse_norm_inf_upper=None, beta_forward_error_inf_upper=None,
                      covariance_forward_error_inf_upper=None)
        return result
    denominator = subtract(D(1), rho, DOWN)
    with localcontext() as ctx:
        ctx.prec = digits
        ctx.rounding = UP
        invnorm = vnorm / denominator
        beta_error = invnorm * e
        covariance_error = vnorm * rho / denominator
    result.update(status="RIGOROUS_COMPONENT_BOUND_FOR_EXACT_STORED_P_RHS",
                  inverse_norm_inf_upper=str(invnorm),
                  beta_forward_error_inf_upper=str(beta_error),
                  covariance_forward_error_inf_upper=str(covariance_error))
    return result

def _bernoulli_even(max_order):
    _, _, _, _, F, _, _ = _imports()
    A = [F(0)] * (max_order + 1)
    result = {}
    for m in range(max_order + 1):
        A[m] = F(1, m + 1)
        for j in range(m, 0, -1):
            A[j - 1] = j * (A[j - 1] - A[j])
        if m > 0 and m % 2 == 0:
            result[m] = A[0]
    return result

def _constants(digits):
    """Machin pi and Euler-Maclaurin gamma; no finite hardcoded constant ceiling.

    Analytic next-term bounds are retained. Decimal rounding propagation for
    special-function/objective terms remains an explicitly unearned budget.
    """
    D, localcontext, _, _, _, _, _ = _imports()
    with localcontext() as ctx:
        ctx.prec = digits + 32
        threshold = D(10) ** (-(digits + 16))
        def atan_reciprocal(q):
            x = D(1) / D(q)
            square = x * x
            term = x
            total = D(0)
            k = 0
            while True:
                part = term / D(2 * k + 1)
                if part.copy_abs() < threshold:
                    return total, part.copy_abs()
                total += part if k % 2 == 0 else -part
                term *= square
                k += 1
        a, ea = atan_reciprocal(5)
        b, eb = atan_reciprocal(239)
        pi = 16 * a - 4 * b
        N = max(64, 2 * digits)
        harmonic = sum((D(1) / D(k) for k in range(1, N + 1)), D(0))
        gamma = harmonic - D(N).ln() - D(1) / (2 * D(N))
        bernoulli = _bernoulli_even(2 * digits)
        tail = None
        previous = None
        for k in range(1, digits + 1):
            frac = bernoulli[2 * k]
            term = D(frac.numerator) / D(frac.denominator) / (D(2 * k) * D(N) ** (2 * k))
            _require(previous is None or term.copy_abs() <= previous,
                     "Euler-Maclaurin terms stopped decreasing")
            if term.copy_abs() < threshold:
                tail = term.copy_abs()
                break
            gamma += term
            previous = term.copy_abs()
        _require(tail is not None, "Euler constant analytic remainder not earned")
        return {"pi": pi, "euler": gamma,
                "pi_analytic_tail": 16 * ea + 4 * eb, "euler_analytic_tail": tail,
                "rounding_error_bound": None}

def _gamma_pair(x, constants, cache):
    """Exact integer/half-integer recurrence; full n90240 sigma shape supported."""
    D, _, _, _, _, _, _ = _imports()
    _require(x > 0 and x <= 200000 and 2 * x == (2 * x).to_integral_value(),
             "only original integer/half-integer gamma shapes are supported")
    if x in cache:
        return cache[x]
    if x == x.to_integral_value():
        z, lg, psi = D(1), D(0), -constants["euler"]
    else:
        z = D("0.5")
        lg = constants["pi"].ln() / 2
        psi = -constants["euler"] - 2 * D(2).ln()
    while z < x:
        lg += z.ln()
        psi += 1 / z
        z += 1
    cache[x] = (lg, psi)
    return lg, psi

def _ig(a, b, constants, cache):
    lg, psi = _gamma_pair(a, constants, cache)
    return {"elog": b.ln() - psi, "einv": a / b,
            "entropy": a + b.ln() + lg - (a + 1) * psi}

def _rhs_prior(m, V, state, controls, constants, cache):
    """Independent original rhs_ns prior, never a supplied production scalar.

    Formula source: exact CRAN1.1.1 static_beta_prior.R, member SHA
    6f89caf7b25513be16159f6f044ee7d5b268ce06daa4043131f007827e9c0d68.
    No beta entropy is included here; it is accounted once in the AL objective.
    """
    D, _, _, _, _, _, _ = _imports()
    p = len(m)
    _require(state["p"] == p and state["prior_type"] == "rhs_ns" and
             state["shrink_intercept"] is False and state["zeta2_is_fixed"] is False,
             "unchanged full rhs_ns state required")
    _require(set(controls) == {"tau0", "a_zeta", "b_zeta", "var_floor",
                               "shrink_intercept"} and controls["shrink_intercept"] is False,
             "closed RHS prior controls")
    floor = max(_hex(controls["var_floor"]), D.from_float(1e-16))
    beta2 = [m[i] * m[i] + V[i][i] for i in range(p)]
    arrays = {}
    for key in ("a_lambda", "b_lambda", "a_nu", "b_nu"):
        _require(len(state[key]) == p, "complete RHS vector shape")
        arrays[key] = [max(_hex(x), floor) for x in state[key]]
    scalars = {key: max(_hex(state[key]), floor)
               for key in ("a_tau", "b_tau", "a_xi", "b_xi", "a_zeta", "b_zeta")}
    local = [_ig(arrays["a_lambda"][i], arrays["b_lambda"][i], constants, cache)
             for i in range(p)]
    nu = [_ig(arrays["a_nu"][i], arrays["b_nu"][i], constants, cache)
          for i in range(p)]
    tau = _ig(scalars["a_tau"], scalars["b_tau"], constants, cache)
    xi = _ig(scalars["a_xi"], scalars["b_xi"], constants, cache)
    zeta = _ig(scalars["a_zeta"], scalars["b_zeta"], constants, cache)
    az, bz, tau0 = _hex(controls["a_zeta"]), _hex(controls["b_zeta"]), _hex(controls["tau0"])
    _require(az > 0 and bz > 0 and tau0 > 0, "positive original prior controls")
    log2pi = (2 * constants["pi"]).ln()
    loggamma_half, _ = _gamma_pair(D("0.5"), constants, cache)
    loggamma_az, _ = _gamma_pair(az, constants, cache)
    active = range(1, p)
    half = D("0.5")
    terms = {
        "beta_horseshoe": sum((-half * log2pi - half * tau["elog"] -
             half * local[i]["elog"] - half * beta2[i] * tau["einv"] *
             local[i]["einv"] for i in active), D(0)),
        "beta_slab": sum((-half * log2pi - half * zeta["elog"] -
             half * beta2[i] * zeta["einv"] for i in active), D(0)),
        "lambda_given_nu": sum((-half * nu[i]["elog"] - loggamma_half -
             (half + 1) * local[i]["elog"] - nu[i]["einv"] * local[i]["einv"]
             for i in active), D(0)),
        "nu_prior": sum((-loggamma_half - (half + 1) * nu[i]["elog"] -
             nu[i]["einv"] for i in active), D(0)),
        "tau_given_xi": -half * xi["elog"] - loggamma_half -
             (half + 1) * tau["elog"] - xi["einv"] * tau["einv"],
        "xi_prior": half * (1 / (tau0 * tau0)).ln() - loggamma_half -
             (half + 1) * xi["elog"] - (1 / (tau0 * tau0)) * xi["einv"],
        "zeta_prior": az * bz.ln() - loggamma_az -
             (az + 1) * zeta["elog"] - bz * zeta["einv"],
        "hyperparameter_entropy": sum((local[i]["entropy"] + nu[i]["entropy"]
             for i in active), D(0)) + tau["entropy"] + xi["entropy"] + zeta["entropy"],
    }
    prec0 = _hex(state["intercept_prec"])
    _require(prec0 > 0, "invalid intercept precision; no silent prior fallback")
    terms["intercept_prior"] = half * (prec0.ln() - log2pi) - half * prec0 * beta2[0]
    return sum(terms.values(), D(0)), terms

def _full_target_moments(Xraw, yraw, m, V, n, p):
    """Original-unit moments from unchanged ROW-MAJOR original X.bin.

    The old R179 reader uses matrix(..., byrow=TRUE). Precision and covariance
    exports have a separate column-major contract and are not reinterpreted here.
    """
    D, _, _, _, _, math, struct = _imports()
    _require(len(Xraw) == n * p * 8 and len(yraw) == n * 8, "exact full target bytes")
    residual, second = [], []
    for i in range(n):
        row = []
        for j in range(p):
            f = struct.unpack_from("<d", Xraw, (i * p + j) * 8)[0]
            _require(math.isfinite(f), "nonfinite design")
            row.append(D.from_float(f))
        f = struct.unpack_from("<d", yraw, i * 8)[0]
        _require(math.isfinite(f), "nonfinite response")
        r = D.from_float(f) - sum((row[j] * m[j] for j in range(p)), D(0))
        q = sum((row[j] * V[j][k] * row[k] for j in range(p) for k in range(p)), D(0))
        _require(q >= 0, "negative full-covariance quadratic; no clipping")
        residual.append(r)
        second.append(q + r * r)
    return residual, second

def _explicit_objective(request, payloads, m, V, digits):
    """Full original imported-factor AL terms, without reconditioning q(v)."""
    D, _, _, _, _, _, _ = _imports()
    import json
    import hashlib
    def pairs(items):
        out = {}
        for key, value in items:
            _require(key not in out, "duplicate factor snapshot key")
            out[key] = value
        return out
    snapshot = json.loads(payloads["factor_snapshot"], object_pairs_hook=pairs,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite factor JSON")))
    _require(type(snapshot) is dict and set(snapshot) == {"schema", "state_semantics",
        "no_factor_or_prior_rewrite", "target", "n", "p", "rhs_state", "prior_controls",
        "qsig", "qv", "source_provenance"}, "closed owned factor snapshot")
    _require(snapshot["schema"] == "r200_owned_explicit_factor_snapshot_v1" and
             snapshot["state_semantics"] == "explicit_imported_factors_not_reconditioned" and
             snapshot["no_factor_or_prior_rewrite"] is True and
             all(snapshot[k] == request[k] for k in ("target", "n", "p")),
             "owned exact target fixed-factor snapshot")
    provenance = snapshot["source_provenance"]
    _require(type(provenance) is dict and set(provenance) == {"kind",
        "source_recipe_sha256", "original_failed_bindings", "named_input_sha256",
        "optimizer_updates", "native_owned_export_receipt_sha256"},
        "closed owned factor-export provenance")
    _require(provenance["kind"] in {"owned_export_of_preserved_factors",
        "owned_exact_original_recipe_reconstruction"} and
        type(provenance["optimizer_updates"]) is int and provenance["optimizer_updates"] == 0,
        "fixed-state owned export without optimizer updates")
    _require(provenance["source_recipe_sha256"] ==
        request["target_construction"]["source_recipe_sha256"], "same source recipe")
    _require(type(provenance["original_failed_bindings"]) is list and
        len(provenance["original_failed_bindings"]) > 0, "original failed provenance retained")
    for binding in provenance["original_failed_bindings"]:
        _require(type(binding) is dict and set(binding) == {"path", "sha256"} and
            type(binding["path"]) is str and binding["path"].startswith("/") and
            type(binding["sha256"]) is str and len(binding["sha256"]) == 64,
            "complete original failed binding descriptor")
    expected_names = set(payloads) - {"factor_snapshot"}
    _require(set(provenance["named_input_sha256"]) == expected_names,
        "factor export binds all numerical input byte identities")
    for name in expected_names:
        _require(provenance["named_input_sha256"][name] ==
            hashlib.sha256(payloads[name]).hexdigest(), "exact exported numerical snapshot bytes")
    _require(type(provenance["native_owned_export_receipt_sha256"]) is str and
        len(provenance["native_owned_export_receipt_sha256"]) == 64,
        "owned export receipt descriptor is not an independent execution grant")
    constants = _constants(digits)
    cache = {}
    prior, prior_terms = _rhs_prior(m, V, snapshot["rhs_state"], snapshot["prior_controls"],
                                    constants, cache)
    _require(snapshot["prior_controls"]["tau0"] == float(request["tau0"]).hex(),
             "exact original binary64 tau0")
    n, p = request["n"], request["p"]
    r, q = _full_target_moments(payloads["design"], payloads["response"], m, V, n, p)
    sigma = snapshot["qsig"]
    a, b = _hex(sigma["a"]), _hex(sigma["b"])
    _require(a == 1 + D("1.5") * n and b >= D.from_float(1e-12), "original sigma factors")
    sig = _ig(a, b, constants, cache)
    t = D.from_float(float(request["tau"]))
    A, B = (1 - 2 * t) / (t * (1 - t)), 2 / (t * (1 - t))
    v = snapshot["qv"]
    _require(set(v) == {"chi", "psi", "E_v", "E_inv_v", "E_log_v"} and
             all(len(v[k]) == n for k in ("chi", "E_v", "E_inv_v", "E_log_v")),
             "complete imported qv factors")
    chi = [_hex(x) for x in v["chi"]]
    psi = _hex(v["psi"])
    Ev, Einv, Elog = ([_hex(x) for x in v[k]] for k in ("E_v", "E_inv_v", "E_log_v"))
    qv_floor = D.from_float(1e-12)
    _require(psi >= qv_floor and all(x >= qv_floor for x in chi) and
             all(x > 0 for x in Ev + Einv), "original floored imported qv factors")
    Hlatent = D(0)
    for x, ev, ei, el in zip(chi, Ev, Einv, Elog):
        z = (x * psi).sqrt()
        logK = (constants["pi"] / (2 * z)).ln() / 2 - z
        logc = (psi.ln() - x.ln()) / 4 - D(2).ln() - logK
        Hlatent += -logc + el / 2 + (x * ei + psi * ev) / 2
    Lv = _cholesky(V)
    logdetV = 2 * sum((Lv[i][i].ln() for i in range(p)), D(0))
    terms = {
        "prior": prior,
        "sigma_prior": -2 * sig["elog"] - sig["einv"],
        "latent_prior": -D(n) * sig["elog"] - sig["einv"] * sum(Ev, D(0)),
        "likelihood": -D(n) / 2 * ((2 * constants["pi"]).ln() + B.ln() + sig["elog"])
           -sum(Elog, D(0)) / 2 - sig["einv"] / (2 * B) *
            sum((ei * second - 2 * A * rr + A * A * ev
                 for ei, second, rr, ev in zip(Einv, q, r, Ev)), D(0)),
        "Hbeta": (D(p) * (1 + (2 * constants["pi"]).ln()) + logdetV) / 2,
        "Hsigma": sig["entropy"], "Hlatent": Hlatent}
    return {"objective": str(sum(terms.values(), D(0))),
            "terms": {k: str(x) for k, x in terms.items()},
            "independent_rhs_prior_terms": {k: str(x) for k, x in prior_terms.items()},
            "state_semantics": "explicit_imported_factors_not_reconditioned",
            "constant_analytic_tails": {k: str(constants[k]) for k in
                ("pi_analytic_tail", "euler_analytic_tail")},
            "special_function_rounding_bound": None,
            "full_target_objective_error_bound": None,
            "total_error_budget_closed": False}

def _binary64_view(beta, covariance):
    D, _, _, _, _, math, _ = _imports()
    def one(x):
        f = float(x)
        _require(math.isfinite(f), "reference cannot be returned as finite binary64")
        return f.hex(), D.from_float(f)
    bview = [one(x) for x in beta]
    vview = [[one(x) for x in row] for row in covariance]
    encoded = {"beta_binary64_hex": [x[0] for x in bview],
               "covariance_row_blocks": [
                   {"first_row": first, "rows": [[x[0] for x in row]
                       for row in vview[first:first + 32]]}
                   for first in range(0, len(beta), 32)],
               "output_semantics": "full_original_unit_covariance_binary64_view_not_production_replacement"}
    return encoded, [x[1] for x in bview], [[x[1] for x in row] for row in vview]

def _compute(request, payloads):
    D, localcontext, _, _, _, _, _ = _imports()
    p = request["p"]
    P = _matrix(_decode(payloads["precision"], p * p), p, p)
    b = _decode(payloads["rhs"], p)
    candidate_beta = _decode(payloads["candidate_beta"], p)
    candidate_covariance = _matrix(_decode(payloads["candidate_covariance"], p * p), p, p)
    answers, objectives, changes = [], [], []
    for digits in request["precision_schedule"]:
        with localcontext() as ctx:
            ctx.prec = digits
            answer = _gaussian(P, b, digits)
            if answers:
                prior = answers[-1]
                changes.append({"from_precision": request["precision_schedule"][len(answers)-1],
                   "to_precision": digits,
                   "beta_change_inf": str(max((a - z).copy_abs() for a, z in zip(answer[0], prior[0]))),
                   "covariance_change_inf": str(max(sum(((a-z).copy_abs()
                       for a, z in zip(arow, zrow)), D(0))
                       for arow, zrow in zip(answer[1], prior[1])))})
            answers.append(answer)
            if request["objective_mode"] == "EXPLICIT_IMPORTED_FULL_FACTORS":
                objectives.append({"precision": digits,
                   **_explicit_objective(request, payloads, candidate_beta, candidate_covariance, digits)})
    with localcontext() as ctx:
        ctx.prec = request["precision_schedule"][-1] + 24
        encoded, returned_beta, returned_V = _binary64_view(*answers[-1])
        forward = _outward_forward_bounds(P, b, returned_beta, returned_V, ctx.prec)
    return {"schema": "r200_regional_reference_result_v2",
       "status": "REFERENCE_COMPONENTS_COMPUTED_FULL_SCIENTIFIC_ACCEPTANCE_HELD",
       "target": request["target"], "precision_schedule": request["precision_schedule"],
       "exact_binary64_P_RHS_import": True, "higher_precision_target_reconstruction": False,
       "input_binary_layout": request["binary_layout"],
       "full_covariance": encoded, "forward_error_for_returned_view": forward,
       "precision_changes": changes, "stability_is_not_total_error_bound": True,
       "explicit_factor_objective": objectives,
       "candidate_state_not_replaced": True, "optimizer_updates": 0,
       "target_construction_error_bound": None,
       "all_seven_measures_and_both_RHS_starts_certified": False,
       "numerical_or_production_acceptance": False,
       "automatic_stage_release": False,
       "remaining_budget_gaps": ["owned target reconstruction/input error",
          "special function and full objective rounding propagation",
          "seven original measures and both original RHS starts",
          "native bootstrap, analytic fixture execution and whole-purpose measured cost"]}
