"""Verify the exact serialized observer's controller whitelist, not workers."""
import ast
import inspect
import unittest
from . import readiness as rd


class ControllerClassificationTests(unittest.TestCase):
    def setUp(self):
        tree=ast.parse(inspect.getsource(rd.metadata_snapshot))
        node=next(v for v in tree.body[0].body if isinstance(v,ast.FunctionDef) and v.name=='control_only')
        namespace={};exec(compile(ast.Module(body=[node],type_ignores=[]),'<exact-observer>','exec'),namespace)
        self.classify=namespace['control_only']

    def test_exact_new_metadata_controllers_are_excluded(self):
        for module,action in (('pricefm_hb.admission','--plan'),('pricefm_hb.lifecycle','release-and-activate'),
                ('pricefm_hb.lifecycle','submit-held'),('pricefm_hb.prefix_control','calendar-observation'),
                ('pricefm_hb.prefix_control','prepare-release')):
            self.assertTrue(self.classify(module,['python','-B','-m',module,action,'/FI/fixed-plan.json']))

    def test_worker_payload_unknown_actions_and_disguised_worker_stay_visible(self):
        for module,action in (('pricefm_hb.lifecycle','worker'),('pricefm_hb.lifecycle','payload'),
                ('pricefm_hb.lifecycle','unknown'),('pricefm_hb.prefix_control','run-assessment'),
                ('pricefm_hb.prefix','run-component')):
            self.assertFalse(self.classify(module,['python','-B','-m',module,action,'--status','FI']))
        self.assertFalse(self.classify('pricefm_hb.lifecycle',['python','-m','pricefm_hb.lifecycle','worker','status']))


if __name__=='__main__':unittest.main()
