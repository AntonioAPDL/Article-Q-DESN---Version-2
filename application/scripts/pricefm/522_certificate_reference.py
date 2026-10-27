#!/usr/bin/env python3
"""R154 fixed-state numerical references. No optimizer, certificate, or registry API.

Coordinates are the original design/response coordinates. Diagonal equilibration
is internal to a Gaussian linear solve and maps both moments back before return.
The objective keeps the r129 prior contribution and all normalization constants.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import sys
from pathlib import Path

import numpy as np
from scipy.linalg import cho_solve
from scipy.special import digamma, gammaln, kve

LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              predictor_rms=1e-6, sigma_relative=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, elbo_relative=1e-8)
PINNED_PYTHON = '/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
STATE_KIND = 'source_equivalent_fixed_state_not_optimizer_resume'
UNITS = 'original_design_and_response'
PRIOR = dict(family='rhs_ns', center='zero', shrink_intercept=False,
             sigma_a=1.0, sigma_b=1.0, freeze_tau_iters=0, freeze_tau_warmup_iters=0)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                    allow_nan=False).encode()).hexdigest()


def validate_scope(scope):
    """Fail closed before any target arithmetic. This does not grant execution."""
    if scope['units'] != UNITS or scope['prior'] != PRIOR:
        raise ValueError('changed units or prior')
    if scope['state_kind'] != STATE_KIND or scope.get('exact_optimizer_resume') is not False:
        raise ValueError('unsupported optimizer state/resume')
    if scope['limits'] != LIMITS or scope['caps'] != {'Normal': 2000, 'AL': 300}:
        raise ValueError('changed acceptance gates or caps')
    if scope['acceptance'] != 'finite AND (formal OR independent)':
        raise ValueError('changed acceptance logic')


def verify_files(bindings):
    """No ignored permission/missing-file errors and no path-only validation."""
    for item in bindings:
        if sha256(item['path']) != item['sha256']:
            raise ValueError('artifact hash mismatch: ' + item['path'])


def verify_target(manifest, name):
    """Read-only strict source/design/state validation on the owning host.

    Hashing a design is not numerical diagnosis. Parent resource admission is
    still needed before any reconstruction or target matrix arithmetic.
    """
    validate_scope(manifest['scope'])
    targets=manifest['targets']
    if len(targets)!=7 or len({t['name'] for t in targets})!=7:
        raise ValueError('not the sealed seven-target set')
    target=next(t for t in targets if t['name']==name)
    if platform.node().split('.')[0]!=target['host'].split('.')[0]:
        raise ValueError('target must be inspected on its original host')
    verify_files(target['bindings'])
    verify_files([manifest['runtime']['CRAN_source']])
    c=target['contract']
    actual=json.loads(Path(target['bindings'][0]['path']).read_text())
    if actual!=c or c['certificate_limits']!=LIMITS or c['max_iter']!=300:
        raise ValueError('contract mismatch or changed gate/cap')
    if c['prior_center_from_initializer'] is not False or c['test_opened'] is not False:
        raise ValueError('changed prior or exposed test state')
    for key in ('tau','tau0','seed','posterior_target_sha256'):
        if c[key]!=target[key]: raise ValueError('target identity mismatch: '+key)
    terminal=json.loads((Path(c['output_dir'])/'terminal.json').read_text())
    if terminal!=target['stored_terminal'] or terminal['computationally_certified'] is not False:
        raise ValueError('failed target state changed')
    for key in ('n','p','tau','tau0','posterior_target_sha256'):
        if terminal[key]!=target[key]: raise ValueError('terminal identity mismatch: '+key)
    design=Path(c['design_dir'])
    dt=json.loads((design/'terminal.json').read_text())
    if dt['status']!='completed_r137_quantile_design' or dt['test_opened'] is not False:
        raise ValueError('invalid design terminal')
    verify_files([dict(path=str(design/key),sha256=value) for key,value in dt['files'].items()])
    d=json.loads((design/'design.json').read_text())
    if d['n']!=target['n'] or d['p']!=target['p'] or d['feature_names'][0]!='intercept':
        raise ValueError('design dimensions or intercept mismatch')
    for filename,size in [('X.bin',target['n']*target['p']*8),('y.bin',target['n']*8)]:
        if (design/filename).stat().st_size!=size: raise ValueError('design byte dimension mismatch')
    return target


def environment_binding():
    """Observe the actual process, not a presumed executable on PATH."""
    executable = os.path.realpath('/proc/self/exe')
    if executable != os.path.realpath(PINNED_PYTHON):
        raise ValueError('actual process is not the pinned Python')
    import scipy
    shared=set()
    for row in Path('/proc/self/maps').read_text().splitlines():
        parts=row.split(maxsplit=5)
        if len(parts)==6 and parts[5].startswith('/') and '.so' in parts[5]:
            shared.add(parts[5])
    return dict(host=platform.node(), executable=executable,
                executable_sha256=sha256(executable), python=sys.version,
                numpy=np.__version__, scipy=scipy.__version__,
                numpy_file=str(Path(np.__file__).resolve()),
                scipy_file=str(Path(scipy.__file__).resolve()),
                numpy_file_sha256=sha256(np.__file__),
                scipy_file_sha256=sha256(scipy.__file__),
                loaded_shared_object_sha256={p:sha256(p) for p in sorted(shared)},
                affinity=sorted(os.sched_getaffinity(0)),
                thread_environment={k: os.environ.get(k) for k in
                    ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
                     'BLIS_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS')})


def immutable_json(path, payload):
    """Exclusive creation only: diagnostics cannot overwrite any prior record."""
    payload = dict(payload)
    payload['record_kind'] = 'diagnostic_only_no_production_acceptance_authority'
    encoded=json.dumps(payload, indent=2, sort_keys=True, allow_nan=False)+'\n'
    with open(path, 'x', encoding='utf-8') as f:
        f.write(encoded)


def gaussian_reference(P, b):
    """Factor the same SPD P; no jitter, altered prior, or silent fallback.

    P*=D P D, b*=D b, beta=D theta, V=D Vtheta D. Componentwise
    backward error is max |P beta-b|/(|P||beta|+|b|). Both original-unit
    covariance and inverse residuals are returned; a small residual does not
    establish a small forward error in an ill-conditioned matrix.
    """
    P = np.asarray(P, dtype=float)
    b = np.asarray(b, dtype=float)
    p = len(b)
    if P.shape != (p, p) or p == 0 or not np.isfinite(P).all() or not np.isfinite(b).all():
        raise ValueError('invalid Gaussian dimensions/nonfinite state')
    if not np.array_equal(P, P.T) or np.any(np.diag(P) <= 0):
        raise ValueError('precision must be symmetric with positive diagonal')
    D = 1.0 / np.sqrt(np.diag(P))
    scaled = (D[:, None] * P) * D[None, :]
    # Roundoff from evaluating symmetric products in a different order is avoided.
    scaled = np.tril(scaled) + np.tril(scaled, -1).T
    L = np.linalg.cholesky(scaled)  # Raises on non-SPD. Never adds jitter.
    theta = cho_solve((L, True), D * b)
    beta = D * theta
    V = (D[:, None] * cho_solve((L, True), np.eye(p))) * D[None, :]
    residual = P @ beta - b
    denominator = np.abs(P) @ np.abs(beta) + np.abs(b)
    component = np.divide(np.abs(residual), denominator, out=np.zeros(p), where=denominator > 0)
    U = np.linalg.cholesky(P).T  # Original-unit metric, no changed criterion.
    inverse_residual = P @ V - np.eye(p)
    return dict(beta=beta, covariance=V, diagonal_scale=D,
                original_cholesky_upper=U,
                componentwise_backward_error=float(np.max(component)),
                normwise_backward_error=float(np.linalg.norm(residual, np.inf) /
                    max(np.finfo(float).tiny, np.linalg.norm(P, np.inf) *
                        np.linalg.norm(beta, np.inf) + np.linalg.norm(b, np.inf))),
                inverse_residual_inf=float(np.linalg.norm(inverse_residual, np.inf)),
                precision_condition=float(np.linalg.cond(P)),
                equilibration_condition=float(np.linalg.cond(scaled)), jitter_added=0.0)


def objective_reference(residual, second, sigma, tau, p, logdetV, prior_elbo):
    """Half-order AL objective in original r129 units with floor correction.

    `prior_elbo` must be evaluated by the pinned original RHS prior on the same
    m,V and RHS state. This boundary is recorded; this function never substitutes
    a changed prior or drops its constants. It returns no certificate flag.
    """
    residual = np.asarray(residual, dtype=float)
    second = np.asarray(second, dtype=float)
    if residual.ndim != 1 or residual.shape != second.shape or len(residual) == 0:
        raise ValueError('invalid fixed-state dimensions')
    if not np.isfinite(residual).all() or not np.isfinite(second).all() or np.any(second < 0):
        raise ValueError('invalid fixed-state moments')
    if not all(map(math.isfinite, (sigma, tau, logdetV, prior_elbo))) or sigma <= 0 or not 0 < tau < 1:
        raise ValueError('invalid objective scalars')
    n = len(residual)
    A = (1 - 2 * tau) / (tau * (1 - tau))
    B = 2 / (tau * (1 - tau))
    a = 1 + 1.5 * n
    b = sigma * (a - 1)
    kappa = a / b
    chi_raw = (kappa / B) * second
    psi_raw = kappa * (2 + A * A / B)
    chi = np.maximum(chi_raw, 1e-12)
    psi = max(psi_raw, 1e-12)
    ell = np.sqrt(psi / chi)
    nu = np.sqrt(chi / psi) * (1 + 1 / np.sqrt(chi * psi))
    logc = .5 * math.log(psi / (2 * math.pi)) + np.sqrt(chi * psi)
    corrections = .5 * ((chi - chi_raw) * ell + (psi - psi_raw) * nu)
    elogs = math.log(b) - digamma(a)
    terms = dict(prior=float(prior_elbo), sigma_prior=-2 * elogs - kappa,
                 latent_scale=-n * elogs,
                 likelihood_constant=-(n / 2) * (math.log(2 * math.pi) + math.log(B) + elogs),
                 beta_entropy=.5 * (p * (1 + math.log(2 * math.pi)) + logdetV),
                 sigma_entropy=a + math.log(b) + gammaln(a) - (a + 1) * digamma(a),
                 latent_cross=(kappa * A / B) * math.fsum(residual),
                 latent_normalizer=-math.fsum(logc),
                 floor_correction=math.fsum(corrections))
    return dict(objective=math.fsum(terms.values()), terms=terms,
                absolute_term_sum=math.fsum(abs(x) for x in terms.values()),
                ell=ell, nu=nu, chi_floor_count=int(np.sum(chi_raw < 1e-12)),
                psi_floor_active=bool(psi_raw < 1e-12),
                prior_boundary='pinned_original_RHS_elbo_same_state_required')


def objective_expanded_reference(residual, second, sigma, tau, p, logdetV, prior_elbo):
    """Independent expanded half-GIG formula, retaining explicit Elogv terms.

    SciPy finite differences here are a test comparison only; they do not replace
    CRAN R's Bessel implementation or establish the cause of any old failure.
    """
    r = np.asarray(residual, dtype=float); q = np.asarray(second, dtype=float)
    n = len(r); A = (1 - 2*tau)/(tau*(1-tau)); B = 2/(tau*(1-tau))
    a = 1 + 1.5*n; b = sigma*(a-1); k = a/b
    chi = np.maximum(k/B*q, 1e-12); psi = max(k*(2+A*A/B), 1e-12)
    z = np.sqrt(chi*psi); ell = np.sqrt(psi/chi)
    nu = np.sqrt(chi/psi)*(1+1/z)
    logK = np.log(np.maximum(kve(.5, z), 1e-300))-z
    Elog = .5*(np.log(chi)-math.log(psi)) + (
        np.log(np.maximum(kve(.500001,z),1e-300))-
        np.log(np.maximum(kve(.499999,z),1e-300)))/(2e-6)
    logc = .25*(math.log(psi)-np.log(chi))-math.log(2)-logK
    entropy = np.sum(-logc + .5*Elog+.5*(chi*ell+psi*nu))
    elogs = math.log(b)-digamma(a)
    return float(prior_elbo-2*elogs-k-n*elogs-k*np.sum(nu)
        -(n/2)*(math.log(2*math.pi)+math.log(B)+elogs)-.5*np.sum(Elog)
        -(k/(2*B))*np.sum(ell*q-2*A*r+A*A*nu)
        +.5*(p*(1+math.log(2*math.pi))+logdetV)
        +a+math.log(b)+gammaln(a)-(a+1)*digamma(a)+entropy)
