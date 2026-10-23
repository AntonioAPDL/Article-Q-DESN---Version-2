"""Finite workflow transitions never reinterpret failure as successful completion."""
import importlib.util
from pathlib import Path
import hashlib
import json
import time
import types
import pytest

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/499_execute_pricefm_stage_r150_finite_workflow.py'
spec=importlib.util.spec_from_file_location('r150_workflow_test',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def test_only_three_remaining_prospectively_approved_admissions():
    done=[]
    while True:
        nxt=m.next_step(done,False)
        if nxt is None:break
        done.append(nxt)
    assert done==['1','2','3']
    assert m.next_step(done,False) is None
    assert m.next_step([],True) is None


@pytest.mark.parametrize('done',[['benchmark'],['1','1'],['3'],['1','2','3','4']])
def test_reordering_duplicate_or_added_admission_refused(done):
    with pytest.raises(RuntimeError):m.next_step(done,False)


def terminal(**values):
    out=dict(wave='1',status='R150_WAVE_COMPLETE',cleanup_verified=True,original_stop_reason='all scientific tasks strictly complete')
    out.update(values);return out


@pytest.mark.parametrize('values',[dict(cleanup_verified=False),dict(status='R150_GUARD_STOPPED'),
    dict(original_stop_reason='idle CPU share below.10 for300s; checkpoint and defer without requeue'),
    dict(original_stop_reason='cooperative controller stop requested')])
def test_failures_and_starvation_end_automatic_progression(values):
    with pytest.raises(RuntimeError):m.acceptable_terminal(terminal(**values),numerical_progress=True)


def test_zero_progress_wave_cannot_consume_next_lease():
    with pytest.raises(RuntimeError):m.acceptable_terminal(terminal(status='R150_WAVE_DEFERRED'),numerical_progress=False)
    m.acceptable_terminal(terminal(status='R150_WAVE_DEFERRED'),numerical_progress=True)
    with pytest.raises(RuntimeError,match='benchmark'):
        m.acceptable_terminal(terminal(wave='benchmark'),numerical_progress=False)


class FakeResources:
    """Owned fake units exercise execute+wait_wave without service mutations."""
    def __init__(self, tmp_path, states, overrides=None, missing_terminal=None, stop_failures=()):
        self.runtime = tmp_path/'runtime'
        self.states = states
        self.overrides = overrides or {}
        self.missing_terminal = missing_terminal
        self.stop_failures = set(stop_failures)
        self.launched = []
        self.unit_reads = {}
        self.drained = []
        self.finalized = False
        self.source = {'head':'frozen-head', 'remote_head':'frozen-head'}
        self.OUT = tmp_path/'campaign'

    @staticmethod
    def read(path):
        return json.loads(Path(path).read_text())

    @staticmethod
    def atomic(path, value):
        path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(value))

    @staticmethod
    def digest(path):
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()

    def assert_parent_policy(self, c):
        assert c['runtime']==str(self.runtime)

    def source_release(self):
        return self.source

    def verify_benchmark_import(self,c,system):
        return {'original_science_source':{'head':'original-benchmark-producer'},'original_available_cpu_seconds':21786.141934839827}

    def System(self):
        return self

    def unit(self, name):
        count=self.unit_reads.get(name,0);self.unit_reads[name]=count+1
        return dict(Id=name,ActiveState='active' if count==0 else 'inactive')

    @staticmethod
    def verify_owned(saved, props):
        assert saved['unit']==props['Id']

    def stop_and_drain(self, system, saved):
        assert system is self
        self.drained.append(saved['unit'])
        if saved['unit'] in self.stop_failures:
            raise RuntimeError('owned cleanup refused: '+saved['unit'])
        return dict(unit=saved['unit'],drained=True)

    @staticmethod
    def discover_workers(folder):
        return [dict(unit='worker-'+Path(folder).name)]

    def launch(self,c,wave):
        assert wave not in self.launched
        self.launched.append(wave)
        lease=dict(wave=wave,source_head='frozen-head',lease_id='lease-'+wave,expires_epoch=time.time()+100)
        folder=self.runtime/('wave_'+wave)
        self.atomic(folder/'controller_launch.json',dict(unit='controller-'+wave,
            argv=['fake-owned-controller',wave],lease=lease,
            description='R150 finite controller lease '+lease['lease_id'],
            expected_cgroup='/user.slice/fake/controller-'+wave+'.service'))
        receipt=terminal(wave=wave,source=dict(head='frozen-head'),lease=lease)
        receipt.update(self.overrides.get(wave,{}))
        if wave!=self.missing_terminal:
            self.atomic(folder/'terminal.json',receipt)
        return dict(unit='controller-'+wave,lease=lease)

    def advance(self):
        return self.queue_state()

    def read_preparation(self):
        return {}

    def queue_state(self):
        state=dict(self.states[len(self.launched)])
        state['scientific_complete']=self.finalized
        return state

    def finalize(self):
        for wave in self.launched:
            assert 'controller-'+wave in self.drained
            assert 'worker-wave_'+wave in self.drained
        self.finalized=True
        self.atomic(self.OUT/'assessment.json',dict(complete=True))
        return dict(complete=True)


def state(complete=(), ready=('work',), terminal_state=False):
    return dict(phase='READY_FOR_ASSESSMENT' if terminal_state else 'WORK',
                ready=[dict(name=n) for n in ready],complete=list(complete),total=12,terminal=terminal_state)


def run_fake(tmp_path, monkeypatch, states, **kwargs):
    resources=FakeResources(tmp_path,states,**kwargs)
    release=tmp_path/'release.json'
    resources.atomic(release,dict(status='PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE',
                                  source=resources.source))
    monkeypatch.setattr(m,'module',lambda *args:resources)
    monkeypatch.setattr(m.time,'sleep',lambda _:None)
    result=m.execute(resources,dict(runtime=str(resources.runtime),benchmark_import={'path':str(release)}),release)
    assert resources.read(resources.runtime/'workflow_terminal.json')==result
    return resources,result


def test_execute_real_coordinator_waits_for_owned_drain_before_final_assessment(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state(['D1'],(),True)])
    assert r.launched==['1']
    assert r.finalized
    assert result['status']=='R150_FINITE_WORKFLOW_SCIENTIFICALLY_COMPLETE'
    assert result['error'] is None
    assert (r.runtime/'wave_1/workflow_independent_drain.json').is_file()


def test_execute_never_admits_fourth_wave_when_science_remains_incomplete(tmp_path,monkeypatch):
    states=[state([str(i) for i in range(n)]) for n in range(4)]
    r,result=run_fake(tmp_path,monkeypatch,states)
    assert r.launched==['1','2','3']
    assert result['status']=='R150_FINITE_WORKFLOW_BUDGET_EXHAUSTED'
    assert not r.finalized


def test_execute_benchmark_budget_deferral_opens_no_numerical_lease(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state((),())])
    assert r.launched==[]
    assert result['status']=='R150_FINITE_WORKFLOW_BUDGET_DEFERRED_BEFORE_NEXT_ADMISSION'
    assert not r.finalized


@pytest.mark.parametrize('changes',[dict(status='R150_GUARD_STOPPED'),dict(cleanup_verified=False),
    dict(original_stop_reason='idle CPU share below.10 for300s'),dict(original_stop_reason='cooperative controller stop requested')])
def test_execute_guard_failure_stop_and_starvation_preserve_terminal_without_next_admission(tmp_path,monkeypatch,changes):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state(['D1'])],
                       overrides={'1':changes})
    assert r.launched==['1']
    assert result['status']=='R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
    assert result['error']
    assert not r.finalized


def test_execute_zero_progress_ends_after_one_numerical_wave(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state()])
    assert r.launched==['1']
    assert result['status']=='R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
    assert 'zero-progress' in result['error']


def test_execute_missing_terminal_is_failure_and_still_independently_drains_owned_units(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state(['D1'])],missing_terminal='1')
    assert r.launched==['1']
    assert result['status']=='R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
    assert 'durable terminal' in result['error']
    assert 'controller-1' in r.drained
    assert 'worker-wave_1' in r.drained
    assert not r.finalized


def test_execute_rejects_source_release_mismatch_before_any_admission(tmp_path,monkeypatch):
    r=FakeResources(tmp_path,[state()])
    release=tmp_path/'release.json'
    r.atomic(release,dict(status='PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE',
                         source=dict(head='other',remote_head='other')))
    with pytest.raises(RuntimeError,match='HEAD differs'):
        m.execute(r,dict(runtime=str(r.runtime),benchmark_import={'path':str(release)}),release)
    assert r.launched==[]


def test_execute_preserves_original_missing_terminal_error_separately_from_cleanup_failure(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state(['D1'])],
        missing_terminal='1',stop_failures=['worker-wave_1'])
    assert r.launched==['1']
    assert 'durable terminal' in result['error']
    assert result['cleanup_failures'][0]['unit']=='worker-wave_1'
    assert 'owned cleanup refused' in result['cleanup_failures'][0]['error']
    proof=r.read(r.runtime/'wave_1/workflow_independent_drain.json')
    assert not proof['cleanup_verified']
    assert 'controller-1' in r.drained
    assert not r.finalized


def test_execute_rejects_wrong_wave_terminal_source_after_drain(tmp_path,monkeypatch):
    r,result=run_fake(tmp_path,monkeypatch,[state(),state(['D1'])],
        overrides={'1':dict(source=dict(head='foreign-source'))})
    assert r.launched==['1']
    assert 'terminal source/lease differs' in result['error']
    assert 'controller-1' in r.drained and 'worker-wave_1' in r.drained
    assert not r.finalized


def test_same_name_replacement_controller_never_receives_original_lifetime_stop(tmp_path,monkeypatch):
    class ReplacedController(FakeResources):
        def unit(self,name):
            props=super().unit(name)
            props['InvocationID']='original-'+name
            if name=='controller-1' and self.unit_reads[name]>1:
                props['InvocationID']='replacement-same-name-and-command'
            return props

        @staticmethod
        def verify_owned(saved,props):
            FakeResources.verify_owned(saved,props)
            if saved.get('attested') and saved['attested']['InvocationID']!=props['InvocationID']:
                raise RuntimeError('refusing replacement controller InvocationID')

        def stop_and_drain(self,system,saved):
            # Match the production resource boundary: every attempted stop must
            # prove the persisted lifetime, not merely command/name intent.
            self.verify_owned(saved,self.unit(saved['unit']))
            return super().stop_and_drain(system,saved)

    r=ReplacedController(tmp_path,[state(),state(['D1'])])
    release=tmp_path/'release.json'
    r.atomic(release,dict(status='PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE',source=r.source))
    monkeypatch.setattr(m,'module',lambda *args:r)
    monkeypatch.setattr(m.time,'sleep',lambda _:None)
    result=m.execute(r,dict(runtime=str(r.runtime),benchmark_import={'path':str(release)}),release)
    assert result['status']=='R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
    assert 'replacement controller InvocationID' in result['error']
    assert result['cleanup_failures'][0]['unit']=='controller-1'
    assert 'replacement controller InvocationID' in result['cleanup_failures'][0]['error']
    assert 'controller-1' not in r.drained
    assert 'worker-wave_1' in r.drained
    original=r.read(r.runtime/'wave_1/workflow_controller_attestation.json')
    assert original['attested']['InvocationID']=='original-controller-1'
    assert r.launched==['1']
    assert not r.finalized


def test_rapid_fatal_startup_checks_expected_cgroup_even_without_active_attestation(tmp_path,monkeypatch):
    class RapidFatalController(FakeResources):
        def unit(self,name):
            props=super().unit(name)
            if name=='controller-1':
                props.update(ActiveState='failed',ControlGroup='',MainPID='0')
            return props

        def stop_and_drain(self,system,saved):
            if saved['unit']=='controller-1':
                assert not saved.get('attested')
                # Membership survives under its original private path even
                # after manager readback clears ControlGroup on rapid failure.
                assert saved['expected_cgroup']=='/user.slice/fake/controller-1.service'
                raise RuntimeError('owned expected cgroup still contains descendant')
            return super().stop_and_drain(system,saved)

    r=RapidFatalController(tmp_path,[state(),state(['D1'])])
    release=tmp_path/'release.json'
    r.atomic(release,dict(status='PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE',source=r.source))
    monkeypatch.setattr(m,'module',lambda *args:r)
    monkeypatch.setattr(m.time,'sleep',lambda _:None)
    result=m.execute(r,dict(runtime=str(r.runtime),benchmark_import={'path':str(release)}),release)
    assert result['status']=='R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
    assert 'independent owned cleanup failed' in result['error']
    assert 'owned expected cgroup still contains descendant' in result['cleanup_failures'][0]['error']
    assert 'controller-1' not in r.drained
    assert 'worker-wave_1' in r.drained
    assert not (r.runtime/'wave_1/workflow_controller_attestation.json').exists()
    assert r.launched==['1']
    assert not r.finalized
