"""Synthetic JSON regression tests for training-boundary and lineage failures."""
import copy
from datetime import datetime,timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

P=Path(__file__).with_name('training_provenance.py')
spec=importlib.util.spec_from_file_location('tested_training_provenance',P)
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.counter=0
        self.config={'schema':p.SCHEMA,'sources':{},'designs':[]}
        source_sha={}
        for role in ('r120','r122','r123','r141','core','replay','r127'):
            path=self.root/(role+'.py');path.write_text('# synthetic source identity\n')
            sha=hashlib.sha256(path.read_bytes()).hexdigest();original='/historical/'+role+'.py'
            self.config['sources'][role]={'path':str(path),'sha256':sha,'original_path':original};source_sha[original]=sha
        self.config['preparation']=self.doc({'source_sha256':source_sha,'official_protocol':{'new_model_first_train_origin_market':'2022-02-04T00:00:00+00:00'}})
        for split in (1,2,3):
            for tau in p.TAUS:
                count=p.BOUNDARIES[split-1][0]
                task={'split':split,'tau0':tau,'kind':'internal_design','region':'SI','candidate_id':'r134_996c377eeda607f0',
                      'specification_sha256':'a'*64,'spec':{'region':'SI','feature_policy':'target_only','units':[192,192],'calendar':'none'}}
                design={'region':'SI','split':split,'selection_stage':'inner_training_only','test_opened':False,
                        'source_specification_sha256':'a'*64,'n':count*96,'p':385,
                        'response_end_exclusive':(datetime.fromisoformat('2022-02-04T00:00:00+00:00')+timedelta(days=count)).isoformat()}
                scaler={'training_origin_count':count,'price_mean':1.0,'price_scale':2.0,'exog_mean':[0.,1.,0.],'exog_scale':[1.,2.,1.]}
                row={key:self.doc(value) for key,value in [('task',task),('design',design),('scaler',scaler)]}
                row['seal']=self.doc({'metadata':{'task_sha256':row['task']['sha256']},'artifacts':{'design/design.json':row['design']['sha256'],'design/scaler.json':row['scaler']['sha256']}})
                self.config['designs'].append(row)
    def tearDown(self):self.tmp.cleanup()
    def doc(self,value):
        self.counter+=1;path=self.root/(str(self.counter)+'.json');path.write_text(json.dumps(value)+'\n')
        return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    def alter(self,row,key,field,value,reseal=True):
        obj=p.read(row[key]);obj[field]=value;row[key]=self.doc(obj)
        if reseal:
            seal=p.read(row['seal'])
            if key=='task':seal['metadata']['task_sha256']=row[key]['sha256']
            else:seal['artifacts']['design/'+key+'.json']=row[key]['sha256']
            row['seal']=self.doc(seal)
    def validate(self):
        # Isolate metadata validation from the separately verified source-AST
        # contract; synthetic tests never open an executed scientific source.
        with patch.object(p,'source_contract',return_value={'synthetic_source_contract':True}):
            return p.validate_si(self.config)
    def test_complete_lineage_has_no_array_or_source_execution_claim(self):
        result=self.validate();self.assertEqual(len(result['designs']),6)
        self.assertFalse(result['array_values_or_binary_bank_integrity_recomputed'])
        self.assertFalse(result['source_imported_or_executed'])
    def test_wrong_scaler_training_count_rejected(self):
        self.alter(self.config['designs'][0],'scaler','training_origin_count',507)
        with self.assertRaises(ValueError):self.validate()
    def test_training_response_overlap_rejected(self):
        row=self.config['designs'][0]
        self.alter(row,'design','response_end_exclusive','2023-06-26T00:00:00+00:00')
        with self.assertRaises(ValueError):self.validate()
    def test_teacher_forced_row_count_mismatch_rejected(self):
        self.alter(self.config['designs'][0],'design','n',506*96+1)
        with self.assertRaises(ValueError):self.validate()
    def test_unsealed_scaler_cannot_support_boundary(self):
        self.alter(self.config['designs'][0],'scaler','price_mean',3.,reseal=False)
        with self.assertRaises(ValueError):self.validate()
    def test_feature_policy_cannot_silently_change(self):
        row=self.config['designs'][0];task=p.read(row['task']);task['spec']['feature_policy']='graph_summary_mean_std'
        row['task']=self.doc(task);seal=p.read(row['seal']);seal['metadata']['task_sha256']=row['task']['sha256'];row['seal']=self.doc(seal)
        with self.assertRaises(ValueError):self.validate()
    def test_duplicate_or_missing_finalist_split_rejected(self):
        self.config['designs'][-1]=self.config['designs'][0]
        with self.assertRaises(ValueError):self.validate()
    def test_unbound_source_alias_rejected(self):
        self.config['sources']['r120']['original_path']='/unbound/other.py'
        with self.assertRaises(ValueError):self.validate()
    def test_source_bytes_drift_rejected(self):
        Path(self.config['sources']['r120']['path']).write_text('# changed\n')
        with self.assertRaises(ValueError):self.validate()
    def test_paired_tau_scaler_difference_rejected(self):
        self.alter(self.config['designs'][1],'scaler','price_mean',4.)
        with self.assertRaises(ValueError):self.validate()
    def test_AST_matching_preserves_generated_history_expression(self):
        good=p.ast.parse('u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, generated[:, :h])')
        bad=p.ast.parse('u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, arrays.response)')
        expression='engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, generated[:, :h])'
        self.assertTrue(p.contains(good,expression));self.assertFalse(p.contains(bad,expression))

if __name__=='__main__':unittest.main(verbosity=2)
