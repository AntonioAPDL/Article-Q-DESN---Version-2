#!/usr/bin/env python3.11
"""Tiny generated editorial fixtures only: no model objects or scientific jobs."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("appendix_compression", ROOT / "scripts/appendix_compression_validation_20261106.py")
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)

MAIN = r"""
\Normal(0\mid\beta_j,\zeta^2) \Normal(\beta_j\mid0,\tau^2\lambda_j^2)
\sigma\sim\IG(a_\sigma,b_\sigma) \xi\sim\IG(1/2,1/\tau_0^2)
Use a proper shape-prior density supported on the stated interval; AL fixes shape at zero.
Readouts use features averaged over its simulated trajectories.
\section{Electricity prices}\label{sec:pricefm-application}
Direct horizon analysis; covariate vintages are not independently verified.
[PriceFM findings to be updated.]
\section{Streamflow}\label{sec:data}
Both use realized values during the forecast window;
future USGS measurements are reserved for scoring.
The raw ensemble comparison has 2 of 28 covered dates, 23.2--27.4 percent
crossing, inversions, negative flow and calibration problems: a physical-support limitation.
All four AL and exAL regressions score above the raw ensemble.
BracherEtAl2021WIS docs/reproducibility/appendix_compression_archive_20261106.md
"""
SUPPLEMENT = r"""
\section{A}\label{sec:dist_conventions}
\begin{equation}
\Normal(\beta_j\mid0,a)\Normal(0\mid\beta_j,b)
=\Normal(0\mid0,a+b)\Normal(\beta_j\mid0,ab/(a+b)).
\label{eq:supp_ns_product_factor}\end{equation}
\begin{equation}
\phi_1(\beta_0;b_0,V_0)p(\tau^2\mid\xi)p(\xi)p(\zeta^2)
\prod_j\phi_1(\beta_j;0,\tau^2\lambda_j^2)\phi_1(0;\beta_j,\zeta^2)
p(\lambda_j^2\mid\nu_j)p(\nu_j)
\label{eq:supp_ns_full_prior}\end{equation}
\begin{align}
\tau^2\mid\cdot&\sim\IG\left(\frac{r+1}{2},b\right),\\
\zeta^2\mid\cdot&\sim\IG\left(a_\zeta+\frac{r}{2},d\right),
\xi\mid\cdot&\sim\IG(1,\frac{1}{\tau_0^2}+\tau^{-2}).
\label{eq:supp_rhs_mcmc}\end{align}
NS CAVI uses \(m_{\beta,j}^2+(\mat\Sigma_\beta)_{jj}\),
\((r+1)/2\), \(a_\zeta+r/2\).
\label{eq:supp_generic_vb_rhs}
Jacobian, negative Hessian, quadrature and mixed moments define the approximation.
\label{eq:supp_structured_scale_integral}
\label{eq:supp_generic_elbo}\label{eq:supp_elbo_transformed_coordinates}
\section{B}\label{sec:joint_qdesn_supp}
\(C_\Delta(\Theta_\Delta)p(\Theta_\Delta)\), \(\vect\Delta_1=\vect\beta_1\).
\begin{equation}
\E_q(\Delta^2)=(\mat Hm)^2+\operatorname{diag}(\mat H\mat\Sigma\mat H^\top).
\label{eq:supp_joint_increment_moments}\end{equation}
The point intercept approximation omits intercept uncertainty.
\section{C}\label{sec:forecast_synthesis}
The parameter draw remains fixed for a trajectory. Use linear interpolation
and retain the outermost ordinate. Count crossings before ordering, not sorting.
\(w_k=1\).
\begin{equation}
\bar{\vect x}_{o+h}=\frac1M\sum_{j=1}^M\tilde{\vect x}_{o+h}^{[j]},\qquad
q_{o,h,k}^{(b)}=\beta_{0k}^{(b)}+\bar{\vect x}_{o+h}^{\top}\vect\beta_k^{(b)}.
\label{eq:supp-forecast-mean-design}\end{equation}
Intervals condition on this averaged design. The trajectory-specific sensitivity
adds trajectory variation. Neither is a quantile of the mixture over future histories.
Weights \((0.025,0.10,0.20,0.25,0.20,0.10,0.025)\) sum to 0.90.
95 percent intervals and posterior-mean grid scores are distinct;
model contrasts are descriptive.
\section{D}
Imperfect scale--shape mixing remains: score stability does not establish mixing.
The shorter period was selected after inspecting forecasts.
\section{E}\label{sec:glofas_discrepancy}
Each level retains its own path. No additional observation error is added
and no post-hoc crossing correction is applied.
\begin{equation}
\prod_{h=1}^{28}\prod_{e=1}^{51} f_{p_k}(g_{he})\prod_{h=1}^{28}f_{p_k}(y_h).
\label{eq:supp_glofas_unit_member_target}\end{equation}
\begin{equation}
\psi_c&=\frac{D_\gamma^2}{B_\gamma}\sum_i s_i^2/v_i.
\label{eq:supp_glofas_unit_exal_updates}\end{equation}
Discrepancy-only paths are unscored: no future retrospective GloFAS is available.
"""
BIBLIOGRAPHY = "doi={10.1371/journal.pcbi.1008618}"


class SemanticTests(unittest.TestCase):
    def check(self, main=MAIN, supplement=SUPPLEMENT):
        return C.semantic_checks(main, supplement, BIBLIOGRAPHY)

    def test_tiny_complete_semantics_and_harmless_line_wrapping(self):
        self.check()
        self.check(main=MAIN.replace("raw ensemble", "raw\nensemble"),
                   supplement=SUPPLEMENT.replace("averaged design", "averaged\n design"))

    def test_core_math_negative_mutations(self):
        for before, after in (
            (r"\Normal(0\mid0,a+b)", "1"),
            (r"\phi_1(0;\beta_j,\zeta^2)", "1"),
            (r"\frac{r+1}{2}", r"\frac{r}{2}"),
            (r"a_\zeta+\frac{r}{2}", r"a_\zeta+\frac{r+1}{2}"),
            (r"\frac{D_\gamma^2}{B_\gamma}", r"D_\gamma^2"),
            (r"\operatorname{diag}(\mat H\mat\Sigma\mat H^\top)", r"\operatorname{diag}(\mat\Sigma)"),
            (r"\bar{\vect x}_{o+h}^{\top}\vect\beta_k^{(b)}", r"\tilde{\vect x}_{o+h}^{(b)\top}\vect\beta_k^{(b)}"),
            (r"\prod_{h=1}^{28}\prod_{e=1}^{51}", r"\{\prod_{h=1}^{28}\prod_{e=1}^{51}\}^{1/51}"),
        ):
            self.assertIn(before, SUPPLEMENT)
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(supplement=SUPPLEMENT.replace(before, after))

    def test_unfavorable_findings_and_diagnostic_scope_are_obligations(self):
        for before, after in (
            ("negative flow", "positive flow"), ("physical-support", "computational"),
            ("2 of 28", "28 of 28"), ("23.2--27.4", "0.0"),
        ):
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(main=MAIN.replace(before, after))
        for before, after in (
            ("Imperfect scale--shape mixing remains", "All parameter chains converged"),
            ("Neither is a quantile of the mixture over future histories", "This is the integrated predictive quantile"),
            ("Discrepancy-only paths are unscored", "Discrepancy-only paths score zero"),
        ):
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(supplement=SUPPLEMENT.replace(before, after))
        with self.assertRaises(C.CompressionError):
            self.check(main=MAIN.replace(C.ARCHIVE, "missing-source-pointer"))


class AdmissionTests(unittest.TestCase):
    def test_public_archive_target_is_determined_by_frozen_role_identity(self):
        row = dict(id="synthetic-role", source="qdesn-supplement.tex;tables/tiny.tex",
                   baseline_lines="8-12;20-24", actual_destination=C.PUBLIC_BASE + "qdesn-supplement.tex#L8-L12")
        self.assertEqual(C.validate_archive_destination(row), row["actual_destination"])
        for target in (
            C.PUBLIC_BASE + "missing.tex#L8-L12",
            C.PUBLIC_BASE + "qdesn-supplement.tex#L99999-L100000",
            C.PUBLIC_BASE + "qdesn-supplement.tex#L8-L13",
            C.PUBLIC_BASE + "tables/tiny.tex#L20-L24",
            row["actual_destination"].replace(C.BASELINE, "main"),
        ):
            forged = dict(row, actual_destination=target)
            with self.subTest(target=target), self.assertRaisesRegex(C.CompressionError, "frozen role source"):
                C.validate_archive_destination(forged)

    def test_missing_git_never_falls_back_to_fixture_api_or_writes(self):
        with tempfile.TemporaryDirectory(prefix="compression_no_git_") as directory:
            root = Path(directory)
            with mock.patch.object(C, "portable_checks", side_effect=AssertionError("must not run")):
                for write in (False, True):
                    with self.subTest(write=write), self.assertRaisesRegex(C.CompressionError, "Git ancestry"):
                        C.refresh(root, write=write)
            self.assertEqual(list(root.iterdir()), [])

    def test_original_numeric_and_inference_bytes_cannot_be_refreshed(self):
        fixtures = ("tables/tiny.csv", "figures/tiny.pdf", "application/R/tiny.R", "application/config/tiny.json")
        with tempfile.TemporaryDirectory(prefix="compression_original_bytes_") as directory:
            root = Path(directory)
            entries = []
            for path in fixtures:
                raw = b"original synthetic fixture\n"
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
                blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
                entries.append(b"100644 blob " + blob.encode() + b"\t" + path.encode())
            with mock.patch.object(C, "git", return_value=b"\0".join(entries) + b"\0"):
                self.assertEqual(len(C.protected_inventory(root)), 4)
                for path in fixtures:
                    (root / path).write_bytes(b"changed synthetic fixture\n")
                    with self.subTest(path=path), self.assertRaisesRegex(C.CompressionError, "frozen original"):
                        C.protected_inventory(root)
                    (root / path).write_bytes(b"original synthetic fixture\n")

    def test_historical_fields_preserved_only_outer_document_hashes_refresh(self):
        baseline = dict(sources={"main.tex": "old", "application/R/tiny.R": "frozen"},
            outputs={"tables/tiny.csv": "science"}, reader_appendix_20261106={"old": "unchanged"}, fits_launched=0)
        result = C.expected_legacy(baseline, {p: "current" for p in C.OUTER_MUTABLE})
        C.verify_legacy(result, baseline)
        self.assertEqual(result["reader_appendix_20261106"], baseline["reader_appendix_20261106"])
        self.assertEqual(result["sources"]["main.tex"], "current")
        for mutate in (
            lambda x: x["reader_appendix_20261106"].update(old="forged"),
            lambda x: x["outputs"].update({"tables/tiny.csv": "forged"}),
            lambda x: x.update(fits_launched=1),
            lambda x: x[C.FIELD].update(manifest="different.json"),
        ):
            value = copy.deepcopy(result); mutate(value)
            with self.assertRaises(C.CompressionError):
                C.verify_legacy(value, baseline)

    def test_explicit_fixture_api_does_not_claim_publication_admission(self):
        with tempfile.TemporaryDirectory(prefix="compression_fixture_only_") as directory:
            root = Path(directory); (root / "tables").mkdir()
            baseline = {"sources": {}, "outputs": {}, "reader_appendix_20261106": {"tiny": "synthetic"}}
            manifest = dict(schema=C.SCHEMA, baseline_commit=C.BASELINE,
                original_legacy_receipt_sha256=C.LEGACY_SHA, original_legacy_receipt=baseline,
                source_ancestry_authenticated=True, scientific_values_changed=False,
                scientific_outputs_regenerated=False, fits_launched=0, forecasts_launched=0, scores_recomputed=0,
                current_source_sha256={p: C.sha(raw.encode()) for p, raw in
                    (("main.tex", MAIN), ("qdesn-supplement.tex", SUPPLEMENT), ("refs.bib", BIBLIOGRAPHY))},
                actual_input_routes={})
            for path, raw in (("main.tex", MAIN), ("qdesn-supplement.tex", SUPPLEMENT), ("refs.bib", BIBLIOGRAPHY)):
                (root / path).write_text(raw)
            (root / C.MANIFEST).write_bytes(C.canonical(manifest))
            (root / C.LEGACY_RECEIPT).write_bytes(C.canonical(C.expected_legacy(baseline, manifest["current_source_sha256"])))
            # Only replace the identity of this wholly synthetic baseline;
            # normal public admission is separately proven fail-closed above.
            with mock.patch.object(C, "LEGACY_SHA", C.sha(C.canonical(baseline))), \
                 mock.patch.object(C, "current_route_checks", return_value={}), \
                 mock.patch.object(C, "disposition_checks"), mock.patch.object(C, "derivative_checks"):
                manifest["original_legacy_receipt_sha256"] = C.LEGACY_SHA
                (root / C.MANIFEST).write_bytes(C.canonical(manifest))
                result = C.portable_checks(root)
            self.assertFalse(result["source_ancestry_authenticated"])
            self.assertFalse(result["full_scientific_inventory_authenticated"])
            self.assertFalse(result["metadata_written"])


class RoutingTests(unittest.TestCase):
    def test_each_eight_figures_and_new_table_must_really_be_selected(self):
        routes = {p: ["qdesn-supplement.tex"] for p in C.REQUIRED_DISPLAYS + C.REQUIRED_FIGURES + C.REQUIRED_EXTRA_EVIDENCE}
        text = r"\label{tab:joint-qdesn-pure-desn-v2-score}\label{tab:joint-qdesn-pure-desn-v2-recursive-policy}"
        with mock.patch.object(C, "regular", return_value=text.encode()), \
             mock.patch.object(C, "visible_routes", return_value=routes):
            with mock.patch.object(C, "route_inventory", return_value=routes):
                C.current_route_checks(Path("synthetic"))
            for path in C.REQUIRED_FIGURES + C.REQUIRED_DISPLAYS + C.REQUIRED_EXTRA_EVIDENCE:
                omitted = copy.deepcopy(routes); omitted[path] = []
                with self.subTest(path=path), mock.patch.object(C, "route_inventory", return_value=omitted), \
                     self.assertRaisesRegex(C.CompressionError, "not selected"):
                    C.current_route_checks(Path("synthetic"))
            hidden = copy.deepcopy(routes)
            hidden[C.REQUIRED_DISPLAYS[0]] = []
            with mock.patch.object(C, "visible_routes", return_value=hidden), \
                 mock.patch.object(C, "route_inventory", return_value=routes), \
                 self.assertRaisesRegex(C.CompressionError, "not selected"):
                C.current_route_checks(Path("synthetic"))
            for path in C.STALE_DISPLAYS:
                stale = copy.deepcopy(routes); stale[path] = ["qdesn-supplement.tex"]
                with self.subTest(path=path), mock.patch.object(C, "route_inventory", return_value=stale), \
                     self.assertRaisesRegex(C.CompressionError, "stale duplicate"):
                    C.current_route_checks(Path("synthetic"))


if __name__ == "__main__":
    unittest.main()
