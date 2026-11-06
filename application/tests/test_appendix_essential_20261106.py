#!/usr/bin/env python3.11
"""Bounded reader-layout and mathematical mutation checks; no model runtime."""
from __future__ import annotations

import copy
import importlib.util
import math
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("essential_guard", ROOT / "scripts/appendix_compression_validation_20261106.py")
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


class EssentialMathematicalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = (ROOT / "main.tex").read_text()
        cls.supplement = (ROOT / "qdesn-supplement.tex").read_text()
        cls.bibliography = (ROOT / "refs.bib").read_text()

    def check(self, supplement=None):
        return C.essential_semantic_checks(self.main, self.supplement if supplement is None else supplement, self.bibliography)

    def test_retained_short_account_has_complete_math(self):
        self.assertTrue(all(self.check().values()))

    def test_wrong_normalizers_and_global_slab_shapes_are_rejected(self):
        mutations = (
            (r"\Normal(0;0,a+b)", "1"),
            (r"C_\beta(\Theta_\beta)\prod", "\\prod"),
            (r"\frac{r+1}{2}", r"\frac r2"),
            (r"a_\zeta+\frac r2", r"a_\zeta+\frac{r+1}{2}"),
            (r"\tau_0^{-2}", "1"),
        )
        for before,after in mutations:
            self.assertIn(before,self.supplement)
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(self.supplement.replace(before,after))

    def test_covariance_canonical_parameters_and_tn_actual_moments_are_required(self):
        mutations = (
            (r"\bar e_t^2+\vect x_t^\top\mat\Sigma_\beta\vect x_t", r"\bar e_t^2"),
            (r"(\mat\Sigma_\beta)_{jj}", "0"),
            (r"\E_q\{(\sigma B_\gamma)^{-1}\}", r"\E_q(\sigma^{-1})\E_q(B_\gamma^{-1})"),
            (r"\TN(h_t^s/K_t^s,1/K_t^s)", r"\TN(\E_q(h_t^s/K_t^s),\E_q(1/K_t^s))"),
            (r"m^2+V+m\sqrt V", r"m^2+V"),
        )
        for before,after in mutations:
            self.assertIn(before,self.supplement)
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(self.supplement.replace(before,after))

    def test_gig_conditions_mq_and_response_design_covariance_are_required(self):
        mutations = (
            (r"a<-\nu", r"a>\nu"),
            (r"\nu<0",r"\nu>0"),
            (r"\Gamma(-\nu-a)", r"\Gamma(-\nu+a)"),
            (r"\diag(\mat H\mat\Sigma\mat H^\top)", r"\diag(\mat\Sigma)"),
            (r"\mat J_i\mat V\vect e_h", "0"),
            (r"\frac{D_\gamma^2}{B_\gamma}", r"D_\gamma^2"),
            (r"\prod_{h=1}^{28}\prod_{e=1}^{51}", r"\prod_{h=1}^{28}\prod_{e=1}^{51}{}^{1/51}"),
            (r"a_c+n_c/2", r"a_c+3n_c/2"),
        )
        for before,after in mutations:
            self.assertIn(before,self.supplement)
            with self.subTest(before=before), self.assertRaises(C.CompressionError):
                self.check(self.supplement.replace(before,after))

    def test_width_exceptions_cannot_be_removed_or_generalized(self):
        for before,after in (("persistent-heavy-tail","another"),("0.736433","1.0")):
            self.assertIn(before,self.supplement)
            with self.subTest(before=before),self.assertRaises(C.CompressionError):
                self.check(self.supplement.replace(before,after))
        with self.assertRaises(C.CompressionError):
            self.check(self.supplement + "\nEvery interval becomes wider.\n")

    def test_truncated_normal_zero_location_is_not_zero_mean(self):
        location,variance=0.,1.
        phi=math.exp(-.5*location**2/variance)/math.sqrt(2*math.pi)
        Phi=.5*(1+math.erf(location/math.sqrt(2*variance)))
        mean=location+math.sqrt(variance)*phi/Phi
        second=location**2+variance+location*math.sqrt(variance)*phi/Phi
        self.assertAlmostEqual(mean,math.sqrt(2/math.pi))
        self.assertEqual(second,1.)

    def test_correct_hidden_equation_is_not_current_mathematics(self):
        at=self.supplement.index(r"\label{eq:supp_rhs_mcmc}")
        begin=self.supplement.rfind(r"\begin{equation}",0,at)
        end=self.supplement.index(r"\end{equation}",at)+len(r"\end{equation}")
        changed=self.supplement[:begin]+"\\iffalse\n"+self.supplement[begin:end]+"\n\\fi"+self.supplement[end:]
        with self.assertRaisesRegex(C.CompressionError,"defining equation is hidden"):
            self.check(changed)

    def test_consolidated_dependence_explanation_cannot_disappear(self):
        before="one coefficient draw across targets"
        self.assertIn(before,self.supplement)
        with self.assertRaisesRegex(C.CompressionError,"cross_target_dependence"):
            self.check(self.supplement.replace(before,"separate coefficient draws at every target"))


class EssentialAdmissionTests(unittest.TestCase):
    def test_fixed_contract_and_default_role_boundary(self):
        contract=C.essential_contract(ROOT)
        self.assertEqual(contract["visible_counts"],dict(figures=3,tables=7,algorithms=2))
        roles={r["role"]:r for r in contract["roles"]}
        self.assertEqual(roles["mq_fit_rmse"]["disposition"],"archived")
        self.assertEqual(roles["mq_sensitivity"]["disposition"],"retained")
        self.assertEqual(roles["augmented_model"]["destination"],"main.tex#eq:qdesn-aug")
        self.assertEqual(C.selected_manifest_path(ROOT),C.ESSENTIAL_MANIFEST)

    def test_unknown_partial_marker_fails_closed_without_v1_fallback(self):
        for relative in (C.ESSENTIAL_CONTRACT,C.ESSENTIAL_MANIFEST,C.LEGACY_RECEIPT):
            with tempfile.TemporaryDirectory(prefix="essential_partial_") as temporary:
                root=Path(temporary)
                target=root/relative; target.parent.mkdir(parents=True)
                target.write_text('{"'+C.ESSENTIAL_FIELD+'":{"schema":"unknown"}}\n')
                with self.subTest(relative=relative), mock.patch.object(C,"_v1_refresh",side_effect=AssertionError("no v1 fallback")):
                    with self.assertRaises(C.CompressionError): C.refresh(root)

    def test_refresh_cannot_approve_different_contract_or_variant(self):
        raw=(ROOT/C.ESSENTIAL_CONTRACT).read_text()
        with tempfile.TemporaryDirectory(prefix="essential_contract_") as temporary:
            root=Path(temporary); target=root/C.ESSENTIAL_CONTRACT; target.parent.mkdir(parents=True)
            target.write_text(raw.replace('"figures": 3','"figures": 2'))
            with self.assertRaisesRegex(C.CompressionError,"approved essential-layout contract changed"):
                C.refresh(root,write=True)
            self.assertFalse((root/C.ESSENTIAL_MANIFEST).exists())

    def test_historical_namespaces_and_scientific_counters_cannot_be_rehashed(self):
        baseline={"sources":{"main.tex":"old","R/tiny.R":"frozen"},"outputs":{"qdesn-supplement.tex":"old"},
                  "appendix_compression_20261106":{"schema":"historical"},"fits_launched":0}
        current=C.essential_legacy(baseline,baseline,{"main.tex":"new","qdesn-supplement.tex":"new","overleaf/article_files.txt":"new"})
        C.essential_legacy(current,baseline)
        for field in ("appendix_compression_20261106","fits_launched"):
            forged=copy.deepcopy(current); forged[field]="forged"
            with self.subTest(field=field),self.assertRaises(C.CompressionError): C.essential_legacy(forged,baseline)

    def test_no_missing_git_fallback(self):
        with mock.patch.object(C,"git",side_effect=C.CompressionError("Git ancestry missing")),mock.patch.object(C,"essential_portable_checks",side_effect=AssertionError("not automatic")):
            with self.assertRaisesRegex(C.CompressionError,"Git ancestry missing"): C.refresh(ROOT)

    def test_actual_visible_roles_and_exact_derivatives(self):
        C.essential_route_checks(ROOT)
        self.assertEqual(C.essential_derivative_checks(ROOT)["essential_derivatives"],2)

    def test_archived_input_or_hidden_retained_input_is_rejected(self):
        visible=C.visible_routes(ROOT)
        archived="figures/independent_simulation/independent_train500_eval500_mcmc_forecast_mae_v1.pdf"
        with mock.patch.object(C,"visible_routes",return_value=dict(visible,**{archived:["qdesn-supplement.tex"]})):
            with self.assertRaisesRegex(C.CompressionError,"archived figure accidentally reintroduced"): C.essential_route_checks(ROOT)
        hidden=dict(visible); hidden.pop("tables/appendix_essential_20261106_mq_crossings.tex")
        with mock.patch.object(C,"visible_routes",return_value=hidden):
            with self.assertRaisesRegex(C.CompressionError,"actual role consumer absent"): C.essential_route_checks(ROOT)

    def test_inline_algorithm_and_literal_table_must_be_visible(self):
        original=C.regular
        supp=(ROOT/"qdesn-supplement.tex").read_text()
        for label in ("alg:qdesn_mcmc","tab:simulation-dgp"):
            at=supp.index("\\label{"+label+"}")
            before=supp.rfind(r"\begin{",0,at)
            # Hide the role-defining label even though the original bytes and
            # raw begin count remain in the input graph.
            changed=supp[:before]+"\\iffalse\n"+supp[before:at]+"\\label{"+label+"}\\fi"+supp[at+len("\\label{"+label+"}"):]
            def read(root,path,*args):
                return changed.encode() if path=="qdesn-supplement.tex" else original(root,path,*args)
            with self.subTest(label=label),mock.patch.object(C,"regular",side_effect=read),self.assertRaisesRegex(C.CompressionError,"missing or hidden"):
                C.essential_route_checks(ROOT)

    def test_wrong_archive_line_destination_is_rejected(self):
        original=C.regular
        archive=(ROOT/C.ESSENTIAL_ARCHIVE).read_text()
        wrong=archive.replace("qdesn-supplement.tex#L1053-L1092","qdesn-supplement.tex#L1054-L1092")
        self.assertNotEqual(archive,wrong)
        def read(root,path,*args):
            return wrong.encode() if path==C.ESSENTIAL_ARCHIVE else original(root,path,*args)
        with mock.patch.object(C,"regular",side_effect=read),self.assertRaisesRegex(C.CompressionError,"archive role destination missing"):
            C.essential_archive_checks(ROOT,C.essential_contract(ROOT))


if __name__ == "__main__":
    unittest.main()
