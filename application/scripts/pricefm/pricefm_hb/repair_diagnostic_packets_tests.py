"""Pure metadata negative tests for original scientific-contract retention."""
import copy
import unittest
from . import repair_diagnostic_packets as m


def fixture():
    return {"schema":m.SCHEMA,"purpose":"MECHANISM_PREPARATION_ONLY","caps":{"Normal":2000,"AL":300},
            "limits":dict(m.LIMITS),"both_RHS_starts":True,"production_acceptance":False,"posterior_fits":0,
            "old_balance_reused":False,"evidence":{"LT_scalar_analysis":{},"LT_findings":{},"NO4_saved_diagnosis":{}}}


class PacketContractTests(unittest.TestCase):
    def test_preserved_preparation_contract(self):
        m.validate(fixture())

    def test_no_optimizer_expansion_acceptance_or_old_balance(self):
        for key,value in [("caps",{"Normal":2000,"AL":600}),("both_RHS_starts",False),
                          ("production_acceptance",True),("posterior_fits",1),("old_balance_reused",True),
                          ("purpose","PRODUCTION_FIT")]:
            x=fixture();x[key]=value
            with self.subTest(key=key),self.assertRaises(m.ReadinessError):m.validate(x)

    def test_every_original_gate_limit_is_mandatory(self):
        for key in m.LIMITS:
            x=fixture();x["limits"][key]*=2
            with self.subTest(key=key),self.assertRaises(m.ReadinessError):m.validate(x)

    def test_no_missing_or_additional_evidence_surface(self):
        x=fixture();del x["evidence"]["LT_findings"]
        with self.assertRaises(m.ReadinessError):m.validate(x)

    def test_missing_or_wrong_target_evidence_is_not_classification(self):
        for lt in ({},{"schema":"r154_LT_fixed_state_scalar_analysis_v1","target":"other"}):
            with self.assertRaises(m.ReadinessError):m.validate_original_evidence(lt,{})

    def test_incomplete_or_relaxed_original_limits_fail(self):
        lt={"schema":"r154_LT_fixed_state_scalar_analysis_v1","target":"LT_fold1_al0.90",
            "gates":[{"measure":k,"limit":v,"component_gate_pass":k!="elbo_relative"} for k,v in m.LIMITS.items()]}
        no4={"FR_SI_NO4_prior_training_diagnosis":{"NO4_failed_targets":8,"NO4_AL_iterations":[300],
            "NO4_failure_gate_counts":{"beta_posterior_sd_rms":8,"covariance_whitened_rms":6,"elbo_relative":4,"predictor_rms":6,"sigma_relative":2},
            "NO4_paired_tau_gate_sets_identical":True,"NO4_RHS_precision_exclusions_separate":144}}
        m.validate_original_evidence(lt,no4)
        lt["gates"][0]["limit"]*=2
        with self.assertRaises(m.ReadinessError):m.validate_original_evidence(lt,no4)

    def test_missing_no4_evidence_does_not_create_eight_failures(self):
        lt={"schema":"r154_LT_fixed_state_scalar_analysis_v1","target":"LT_fold1_al0.90",
            "gates":[{"measure":k,"limit":v,"component_gate_pass":k!="elbo_relative"} for k,v in m.LIMITS.items()]}
        with self.assertRaises(m.ReadinessError):m.validate_original_evidence(lt,{})
        x=fixture();x["evidence"]["official_test_selection"]={}
        with self.assertRaises(m.ReadinessError):m.validate(x)


if __name__=="__main__":unittest.main()
