"""Analytic diagnostic tests, independent of any forecast engine."""
import importlib.util
import json
from pathlib import Path
import tarfile

import numpy as np
import pytest

PATH=Path(__file__).parents[1]/'scripts/pricefm/pricefm_r150_diagnostics.py'
spec=importlib.util.spec_from_file_location('diagnostics',PATH)
d=importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


def test_pinball_asymmetry_zero_ties_and_units():
    truth=np.array([[2.,0.,1.]])
    prediction=np.ones((1,3,7))
    loss=d.pinball(truth,prediction)
    np.testing.assert_allclose(loss[0,0],d.LEVELS)
    np.testing.assert_allclose(loss[0,1],1-np.array(d.LEVELS))
    np.testing.assert_array_equal(loss[0,2],np.zeros(7))
    np.testing.assert_allclose(d.pinball(d.euros(truth,100,3),d.euros(prediction,100,3)),3*loss)


def test_reliability_ties_are_bracketed_coverage_inclusive():
    truth=np.array([[0.,1.,2.]])
    p=np.ones((1,3,7))
    m=d.summarize(truth,p)
    np.testing.assert_allclose(m['below_strict'],[1/3]*7)
    np.testing.assert_allclose(m['below_inclusive'],[2/3]*7)
    np.testing.assert_allclose(m['tie_frequency'],[1/3]*7)
    assert m['lower_tail_miss']==1/3 and m['upper_tail_miss']==1/3
    assert m['coverage_80']==1/3 and m['width_80']==0


def test_nominal_intervals_and_median_error():
    p=np.array(d.LEVELS)[None,None,:]
    truth=np.array([[.5]])
    m=d.summarize(truth,p)
    assert m['coverage_80']==m['coverage_50']==m['coverage_10']==1
    assert m['width_80']==pytest.approx(.8)
    assert m['width_50']==pytest.approx(.5)
    assert m['width_10']==pytest.approx(.1)
    assert m['median_MAE']==0


def test_market_clock_fixed_hour_across_dst_boundaries():
    # Official 2025 dates straddle both European DST changes; each remains 23:00Z.
    anchors=np.array(['2025-03-29','2025-03-30','2025-03-31','2025-10-26'],dtype='datetime64[ns]').astype('int64')
    physical=d.market_to_physical_ns(anchors)
    np.testing.assert_array_equal(physical,anchors-3600*10**9)
    assert all(str(v).endswith('23:00:00.000000000') for v in physical.astype('datetime64[ns]'))


def test_fold_weights_group_contributions_preserve_primary():
    # Unequal folds make an accidentally pooled target detectably wrong.
    values=np.array([3.,6.,6.,6.])
    weights=np.array([.5,1/6,1/6,1/6])
    groups=np.array(['A','B','A','B'])
    c=d.contribution(values,groups,weights)
    assert sum(c.values())==pytest.approx(4.5)
    assert c['A']==pytest.approx(2.5)
    assert np.mean(values)!=pytest.approx(sum(c.values()))


@pytest.mark.parametrize('truth,prediction',[(np.zeros((2,96)),np.zeros((2,96,6))),
                                          (np.array([[np.nan]]),np.zeros((1,1,7)))])
def test_invalid_arrays_rejected(truth,prediction):
    with pytest.raises(d.EvidenceError):d.pinball(truth,prediction)


def test_changed_seal_rejected(tmp_path):
    p=tmp_path/'predictions.npz';p.write_bytes(b'original')
    seal={'artifacts':{'predictions.npz':d.digest(p)},'metadata':{}}
    (tmp_path/'completed_evidence.json').write_text(json.dumps(seal))
    d.verify_seal(tmp_path)
    p.write_bytes(b'changed')
    with pytest.raises(d.EvidenceError,match='sealed artifact changed'):d.verify_seal(tmp_path)


def test_traversal_seal_rejected(tmp_path):
    (tmp_path/'completed_evidence.json').write_text(json.dumps({'artifacts':{'../foreign':'unused'}}))
    with pytest.raises(d.EvidenceError,match='unsafe'):d.verify_seal(tmp_path)


def test_archive_symlink_and_unexpected_namespace_rejected(tmp_path):
    for filename,info in [('symlink.tar',tarfile.TarInfo('DK_1/link')),
                          ('foreign.tar',tarfile.TarInfo('unapproved/file'))]:
        if filename=='symlink.tar':info.type=tarfile.SYMTYPE;info.linkname='/etc/passwd'
        archive=tmp_path/filename
        with tarfile.open(archive,'w') as handle:handle.addfile(info)
        with pytest.raises(d.EvidenceError):d.extract_safe(archive,tmp_path/'out')
