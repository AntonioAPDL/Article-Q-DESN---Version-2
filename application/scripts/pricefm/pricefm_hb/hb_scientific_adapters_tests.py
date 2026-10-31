import hashlib
from pathlib import Path
import unittest

from . import hb_scientific_adapters as m

NATIVE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r157_native_bootstrap_20261028')


class ScientificPortTests(unittest.TestCase):
    def test_toy_scientific_suffix_remains_byte_identical(self):
        old=(NATIVE/'application/tests/525_project_projection_toy_validation.R').read_text()
        new=m.generate_toy(old)
        self.assertEqual(m.suffix(old,m.TOY_MARKER),m.suffix(new,m.TOY_MARKER))
        self.assertNotIn('muscat_cpu30',new)
        for fragment in ['maximum_optimizer_invocations == 8L','maximum_total_optimizer_iterations == 30L',
                         'maximum_n == 128L','maximum_p == 32L','maximum_CPU_seconds <= 300']:
            self.assertIn(fragment,new)

    def test_bridge_pilot_scientific_suffix_and_original_contract_remain(self):
        old=(NATIVE/'application/scripts/pricefm/525_project_bridge_or_pilot.R').read_text()
        new=m.generate_bridge(old)
        self.assertEqual(m.suffix(old,m.BRIDGE_MARKER),m.suffix(new,m.BRIDGE_MARKER))
        self.assertNotIn('muscat_cpu30',new)
        self.assertIn("'fixedpoint_helper','cran_library'",new)
        self.assertIn("grant$max_iter == if (mode == 'bridge') 0L else 300L",new)

    def test_missing_or_duplicate_source_boundaries_fail(self):
        for text in ['',m.TOY_MARKER+m.TOY_MARKER]:
            with self.assertRaises(ValueError):m.generate_toy(text)
        with self.assertRaises(ValueError):m.generate_bridge(m.BRIDGE_MARKER)

    def test_new_host_prefix_demands_actual_boundary_owner_and_review(self):
        for fragment in ['SLURM_JOB_ID','SLURMD_NODENAME','source_review','scientific_boundary_qualification',
                         'r157_traced_bootstrap_guard_receipt_v1','postbootstrap_TSYNC_scientific_fork_denial',
                         'scientific_target_access_handshake','remaining_owned_lifetimes','FLOCK.*WRITE']:
            self.assertIn(fragment,m.COMMON)
        self.assertIn('old_claims_reused, FALSE',m.COMMON)


if __name__=='__main__':unittest.main()
