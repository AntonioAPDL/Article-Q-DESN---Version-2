"""Prospective mutex-protected control CPU reservations and operation limits.

This is an accounting/admission ledger, not a kernel CPU controller. Its caps
must be applied by the caller to the corresponding commands. Unknown accounting
or a measured overrun permanently blocks further I/O for that claim. Reserved
CPU is never refunded, including failed, cancelled and interrupted operations.
"""
from __future__ import annotations
import math
import os
from pathlib import Path
import re
import socket
import time
import uuid
from . import registry as r

SCHEMA = "r157_prospective_control_cpu_budget_v1"
OWNER = "muscat.be.ucsc.edu"
INITIAL_CEILING = 720
INITIAL_CLAIM_RESERVATION = 230
PUBLICATION_RESERVATION = 30
UNITS = {"metadata": {"local_CPU_cap": 1, "remote_CPU_cap": 2},
         "transfer": {"local_CPU_cap": 5, "remote_CPU_cap": 6},
         "ready_watch": {"local_CPU_cap": 1, "remote_CPU_cap": 10},
         "admission_refresh": {"local_CPU_cap": 10, "remote_CPU_cap": 10}}
INITIAL_LIMITS = {"metadata": 20, "transfer": 6, "ready_watch": 1, "admission_refresh": 1}
KINDS = {'INITIAL':720,'PREFIX':1800,'INITIAL_SUPPLEMENT':230}
REPLACEMENT_PROTOCOL = 'r161_cost_replacement_v1'


class BudgetError(ValueError):
    pass


def owner():
    if socket.getfqdn() != OWNER or os.sched_getaffinity(0) != {31}:
        raise BudgetError("canonical Muscat administrative31 required")


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def safe_key(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:|-]{1,180}", value)


def priced_maximum(limits, parent_cap):
    if (set(limits) != set(UNITS) or any(type(v) is not int or v < 0 for v in limits.values())
            or not number(parent_cap)):
        raise BudgetError("explicit nonnegative operation counts and parent CPU cap required")
    return parent_cap + sum(limits[k] * sum(UNITS[k].values()) for k in UNITS)


def replacement_metadata(value):
    """Read one explicitly named bounded JSON proof, never an opaque asset."""
    if (not isinstance(value,dict) or set(value)!={'path','sha256'}
            or not isinstance(value['path'],str) or not re.fullmatch(r'[a-f0-9]{64}',str(value['sha256']))):
        raise BudgetError('exact replacement metadata pin required')
    path=r.no_links(value['path'])
    if (not Path(value['path']).is_absolute() or path.suffix!='.json' or not path.is_file()
            or path.stat().st_size>16*1024**2 or r.digest(path)!=value['sha256']):
        raise BudgetError('bounded immutable replacement JSON proof required')
    return r.read(path)


def _terminal_time(claim,target):
    epochs=[claim.get(key) for key in ('completed_epoch','completed','terminal_epoch')]
    epochs += [value.get('epoch') for value in claim.get('events',[]) if value.get('to',value.get('to_state'))==target]
    epochs=[value for value in epochs if number(value)]
    if not epochs:raise BudgetError('retained terminal history clock required')
    return max(epochs)


def validate_replacement_lineage(authorization):
    """Bind new04 funding to both terminal paid03 COST predecessors."""
    if authorization.get('protocol_version')!=REPLACEMENT_PROTOCOL:return None
    from . import policy
    mapping=authorization.get('cost_replacement_lineage')
    if (authorization.get('kind')!='INITIAL' or authorization.get('CPU_ceiling')!=720
            or authorization.get('old_scope_renewed') is not False
            or authorization.get('old_charges_refunded') is not False
            or not isinstance(mapping,dict) or set(mapping)!={'FI','DK2'}):
        raise BudgetError('new04 funding requires both exact conserved COST lineages')
    qualification=replacement_metadata(authorization.get('qualification_lineage'))
    if (qualification.get('protocol_version')!=REPLACEMENT_PROTOCOL
            or qualification.get('schema')!='r161_control_qualification_lineage_v1'
            or qualification.get('status')!='ROOT_ADMITTED_TEST04_PRESERVING_OLD_ACCEPTED_TEST'
            or qualification.get('controller')!=OWNER
            or type(qualification.get('max_new_attempts')) is not int or qualification.get('max_new_attempts')!=1
            or qualification.get('old_charges_refunded') is not False or qualification.get('old_clocks_mutated') is not False
            or not number(qualification.get('created_epoch')) or not number(qualification.get('expires_epoch'))):
        raise BudgetError('new04 qualification lineage protocol differs')
    created=authorization.get('created_epoch');expires=authorization.get('expires_epoch')
    if not number(created) or not number(expires):raise BudgetError('finite new04 authorization clock required')
    packet=replacement_metadata(authorization.get('resource_policy'))
    # Structural history is evaluated at admission, while create/_read and
    # COST validation independently require a currently active scope.
    policy.validate_policy(packet,now=created,check_files=False)
    if (not number(created) or not number(expires) or not packet['created_epoch']<=created<expires<=packet['expires_epoch']
            or not 0<expires-created<=7200
            or not qualification['created_epoch']<=created<qualification['expires_epoch']):
        raise BudgetError('new04 control clock must be separately prospective within its resource policy')
    results={};paid_pin=None;old_keys=set()
    for study,reference in mapping.items():
        if (not isinstance(reference,dict) or reference.get('old_charges_retained') is not True
                or not safe_key(reference.get('prior_legacy_claim_key'))
                or not safe_key(reference.get('prior_operational_claim_key'))):
            raise BudgetError('exact old paid COST identities required')
        legacy_state=replacement_metadata(reference.get('prior_legacy_snapshot'))
        operational_state=replacement_metadata(reference.get('prior_operational_snapshot'))
        release=replacement_metadata(reference.get('prior_release'))
        paid=replacement_metadata(reference.get('paid_control_snapshot'))
        old_authority=replacement_metadata(reference.get('paid_control_authorization'))
        legacy_key=reference['prior_legacy_claim_key'];operational_key=reference['prior_operational_claim_key']
        legacy=legacy_state.get('claims',{}).get(legacy_key,{})
        operational=operational_state.get('claims',{}).get(operational_key,{})
        control_claim=paid.get('claims',{}).get(operational_key,{})
        old_spec=release.get('control_cpu_scope',{})
        old_roles=old_authority.get('recovery_claims',{})
        if (legacy_state.get('schema')!='r156_hb_cost_control_v1' or legacy_state.get('owner')!=OWNER
                or operational_state.get('schema')!='r157_hb_lifecycle_v1' or operational_state.get('owner')!=OWNER
                or legacy_state.get('spent_regions',{}).get(study)!=legacy_key
                or legacy.get('task_key')!=legacy_key or operational.get('task_key')!=operational_key
                or legacy.get('state')!='FAILED_RECONCILED' or operational.get('state')!='FAILED_RECONCILED'
                or legacy.get('application_accepted') is not False or operational.get('application_accepted') is not False
                or legacy.get('task',{}).get('study')!=study or operational.get('task',{}).get('study')!=study
                or operational.get('task',{}).get('purpose')!='COST_ONLY'
                or legacy.get('reserved_CPU_seconds')!=1200 or legacy.get('wall_seconds')!=1200
                or release.get('task_key')!=operational_key or release.get('purpose')!='COST_ONLY' or release.get('study')!=study
                or reference['prior_release']['sha256']!=legacy.get('release_sha256')
                or reference['prior_release']['sha256']!=operational.get('release_sha256')
                or legacy.get('release_path')!=operational.get('release_path')
                or reference['prior_release']['path']!=str(Path(operational.get('release_path',''))/'release.json')
                or release.get('plan_sha256')!=legacy.get('task',{}).get('plan_sha256')
                or release.get('plan_sha256')!=operational.get('task',{}).get('plan_sha256')
                or old_spec.get('authorization_pin')!=reference['paid_control_authorization']
                or paid.get('schema')!=SCHEMA or paid.get('owner')!=OWNER or paid.get('kind')!='INITIAL'
                or paid.get('CPU_ceiling')!=720 or paid.get('no_refund') is not True
                or paid.get('authorization')!=reference['paid_control_authorization']
                or paid.get('scope_id')!=old_spec.get('scope_id') or paid.get('scope_id')==authorization.get('scope_id')
                or old_authority.get('status')!='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE'
                or old_authority.get('controller')!=OWNER or old_authority.get('kind')!='INITIAL'
                or old_authority.get('CPU_ceiling')!=720 or old_authority.get('nonrenewing') is not True
                or paid.get('expires_epoch')!=old_authority.get('expires_epoch')
                or not any(v.get('purpose')=='CONTROL_TEST' and v.get('scope_id')=='r157_control_placement_03' for v in old_roles.values())
                or old_roles.get(operational_key)!={'purpose':'COST_ONLY','study':study,'scope_id':release.get('scope_id')}
                or control_claim.get('reserved_CPU')!=230 or control_claim.get('no_refund') is not True
                or not number(paid.get('claim_reserved_CPU'))
                or paid['claim_reserved_CPU']!=sum(v['reserved_CPU'] for v in paid['claims'].values())):
            raise BudgetError('old03 paid terminal COST history or exact authorization differs')
        # Verify the retained snapshot against its original journal bytes; no
        # clock admission, lock creation, recursive pin traversal or mutation.
        if replacement_metadata(dict(path=old_spec.get('path'),sha256=reference['paid_control_snapshot']['sha256']))!=paid:
            raise BudgetError('old03 control bytes changed')
        if paid_pin is not None and paid_pin!=reference['paid_control_snapshot']:
            raise BudgetError('both replacement roles must retain the same paid03 snapshot')
        paid_pin=reference['paid_control_snapshot']
        accepted_reference=qualification.get('prior_accepted_test',{})
        accepted=operational_state.get('claims',{}).get(accepted_reference.get('claim_key'),{})
        accepted_release=replacement_metadata(accepted_reference.get('release'))
        accepted_collection=replacement_metadata(accepted_reference.get('publication'))
        failures=qualification.get('prior_failed_tests')
        if (qualification.get('paid_control_snapshot')!=reference['paid_control_snapshot']
                or qualification.get('paid_control_authorization')!=reference['paid_control_authorization']
                or accepted.get('state')!='COLLECTED' or accepted.get('application_accepted') is not True
                or accepted.get('scope_id')!='r157_control_placement_03'
                or accepted.get('job_id')!=accepted_reference.get('job_id')
                or accepted.get('release_sha256')!=accepted_reference['release']['sha256']
                or accepted_release.get('task_key')!=accepted_reference.get('claim_key')
                or accepted_release.get('purpose')!='CONTROL_TEST'
                or accepted_release.get('scope_id')!='r157_control_placement_03'
                or accepted_release.get('source_hashes')!=accepted_reference.get('source_hashes')
                or accepted_release.get('control_cpu_scope')!=old_spec
                or accepted_collection.get('task_key')!=accepted_reference.get('claim_key')
                or accepted_collection.get('application_accepted') is not True or accepted_collection.get('no_refund') is not True
                or accepted_reference['publication']['path']!=str(Path(accepted.get('publication',''))/'collection.json')
                or not isinstance(failures,list) or len(failures)!=2
                or [operational_state.get('claims',{}).get(item.get('prior_failed_claim_key'),{}).get('scope_id')
                    for item in failures]!=['r157_control_placement_01','r157_control_placement_02']
                or any(operational_state['claims'][item['prior_failed_claim_key']].get('state')!='FAILED_RECONCILED'
                    for item in failures)
                or created<max(_terminal_time(legacy,'FAILED_RECONCILED'),_terminal_time(operational,'FAILED_RECONCILED'),
                               _terminal_time(accepted,'COLLECTED'))):
            raise BudgetError('new04 funding requires exact admitted prior TEST03/failed01-02 and nonbackdated terminal history')
        if study=='FI' and not any(v.get('reason')=='PARENT_CPU_CAP_EXCEEDED' for v in control_claim.get('violations',[])):
            raise BudgetError('real FI parent CPU overrun must remain retained')
        old_keys.update((legacy_key,operational_key))
        results[study]=dict(reference=reference,legacy_state=legacy_state,operational_state=operational_state,
            legacy=legacy,operational=operational,release=release,paid=paid,control_claim=control_claim)
    restrictions=authorization.get('recovery_claims',{})
    if old_keys & set(restrictions):raise BudgetError('new04 funding cannot reuse any old COST key')
    return results


def recovery_claims(authorization):
    """An optional new INITIAL is restricted to three exact reviewed roles."""
    protocol=authorization.get('protocol_version')
    if protocol not in (None,REPLACEMENT_PROTOCOL):raise BudgetError('unknown control recovery protocol')
    claims=authorization.get('recovery_claims')
    if claims is None:
        if protocol==REPLACEMENT_PROTOCOL:raise BudgetError('new04 funding cannot omit its exact reviewed role restrictions')
        return None
    roles={('CONTROL_TEST','TEST'),('COST_ONLY','FI'),('COST_ONLY','DK2')}
    permitted_scopes={'r161_control_placement_04'} if protocol==REPLACEMENT_PROTOCOL else {
        'r157_control_placement_02','r157_control_placement_03'}
    if (protocol not in (None,REPLACEMENT_PROTOCOL) or authorization.get('kind')!='INITIAL' or authorization.get('max_new_claims')!=3
            or type(authorization.get('max_new_claims')) is not int or not isinstance(claims,dict)
            or len(claims)!=3 or any(not safe_key(key) for key in claims)
            or any(not isinstance(v,dict) or set(v)!={'purpose','study','scope_id'}
                   or not isinstance(v['purpose'],str) or not isinstance(v['study'],str)
                   or not safe_key(v['scope_id']) for v in claims.values())
            or {(v['purpose'],v['study']) for v in claims.values()}!=roles
            or next(v['scope_id'] for v in claims.values() if v['purpose']=='CONTROL_TEST') not in permitted_scopes):
        raise BudgetError('new recovery INITIAL requires its exact separately reviewed TEST/FI/DK2 roles')
    if protocol==REPLACEMENT_PROTOCOL:validate_replacement_lineage(authorization)
    return claims


class OperationBudget:
    def __init__(self, path):
        owner()
        self.path = r.no_links(path)
        if not self.path.is_absolute(): raise BudgetError("absolute canonical budget path required")
        self.lock = self.path.with_name(self.path.name + ".lock")

    @classmethod
    def create(cls, path, *, scope_id, authorization_pin, expires_epoch,
               kind="INITIAL", now=None):
        store = cls(path)
        now = time.time() if now is None else now
        if (not safe_key(scope_id) or kind not in KINDS
                or not number(now) or not number(expires_epoch) or not now < expires_epoch <= now + 86400):
            raise BudgetError("explicit finite prospective control scope required")
        from . import policy
        authorization = policy.pinned(authorization_pin)
        ceiling = KINDS[kind]
        if (authorization.get("status") != "ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE"
                or authorization.get("controller") != OWNER or authorization.get("scope_id") != scope_id
                or authorization.get("kind") != kind or authorization.get("CPU_ceiling") != ceiling
                or authorization.get("nonrenewing") is not True
                or authorization.get("expires_epoch") != expires_epoch):
            raise BudgetError("exact prospective root control CPU authorization required")
        restrictions=recovery_claims(authorization)
        supplement=None
        if kind=='INITIAL_SUPPLEMENT':
            from . import lifecycle
            original=policy.pinned(authorization.get('old_initial_authorization_pin'))
            state=lifecycle.Ledger().snapshot()
            prior,release=lifecycle.validate_failed_test(authorization,state)
            old=cls(release['control_cpu_scope']['path']).snapshot(now)
            if (original.get('status')!='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE' or original.get('controller')!=OWNER
                    or original.get('kind')!='INITIAL' or original.get('CPU_ceiling')!=720
                    or original.get('nonrenewing') is not True or old['kind']!='INITIAL'
                    or authorization['old_initial_authorization_pin']!=old['authorization']
                    or old['authorization']!=release['control_cpu_scope']['authorization_pin']
                    or expires_epoch!=original.get('expires_epoch') or expires_epoch!=old['expires_epoch']
                    or authorization.get('permitted_claim_purpose')!='COST_ONLY'
                    or authorization.get('permitted_claim_study')!='DK2'
                    or not safe_key(authorization.get('permitted_claim_key'))
                    or type(authorization.get('max_new_claims')) is not int or authorization.get('max_new_claims')!=1
                    or authorization.get('old_charges_refunded') is not False):
                raise BudgetError('one explicit DK2 supplement must preserve the original paid720CPU scope and clock')
            supplement=dict(old_initial_authorization_pin=authorization['old_initial_authorization_pin'],
                prior_failed_claim_key=prior['task_key'],permitted_claim_key=authorization['permitted_claim_key'])
        store.path.parent.mkdir(parents=True, exist_ok=True)
        with r.lock(store.lock):
            if store.path.exists(): raise FileExistsError("control scope already exists")
            r.write(store.path, dict(schema=SCHEMA, owner=OWNER, scope_id=scope_id, kind=kind,
                created_epoch=now, expires_epoch=expires_epoch, authorization=authorization_pin,
                CPU_ceiling=ceiling, claim_reserved_CPU=0, publication_reserved_CPU=0,
                no_refund=True, claims={}, publication=None,supplement=supplement,recovery_claims=restrictions))
        return store

    def _read(self, now=None):
        state = r.read(self.path)
        now = time.time() if now is None else now
        if (state.get("schema") != SCHEMA or state.get("owner") != OWNER or state.get("no_refund") is not True
                or state.get("kind") not in KINDS
                or state.get("CPU_ceiling") != KINDS[state['kind']]
                or not state["created_epoch"] <= now < state["expires_epoch"]):
            raise BudgetError("active exact control CPU scope required")
        from . import policy
        if state.get('recovery_claims')!=recovery_claims(policy.pinned(state['authorization'])):
            raise BudgetError('immutable control authorization claim restrictions differ')
        return state

    def snapshot(self, now=None):
        with r.lock(self.lock): return self._read(now)

    def historical_snapshot(self, snapshot_pin, authorization_pin):
        """Validate retained immutable bytes without admitting expired operations.

        No lock file or journal is written. This helper cannot reserve or spend.
        """
        from . import policy
        state=policy.pinned(snapshot_pin);authorization=policy.pinned(authorization_pin)
        if (r.digest(self.path)!=snapshot_pin['sha256'] or state.get('schema')!=SCHEMA
                or state.get('owner')!=OWNER or state.get('no_refund') is not True
                or state.get('kind')!='INITIAL' or state.get('CPU_ceiling')!=720
                or state.get('authorization')!=authorization_pin
                or authorization.get('status')!='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE'
                or authorization.get('controller')!=OWNER or authorization.get('kind')!='INITIAL'
                or authorization.get('CPU_ceiling')!=720 or authorization.get('nonrenewing') is not True
                or state.get('scope_id')!=authorization.get('scope_id')
                or state.get('expires_epoch')!=authorization.get('expires_epoch')
                or not number(state.get('created_epoch')) or not number(state.get('expires_epoch'))
                or state['created_epoch']>=state['expires_epoch']
                or not isinstance(state.get('claims'),dict)
                or any(v.get('no_refund') is not True or not number(v.get('reserved_CPU')) for v in state['claims'].values())
                or state.get('claim_reserved_CPU')!=sum(v['reserved_CPU'] for v in state['claims'].values())
                or state.get('publication_reserved_CPU') not in (0,30)
                or state['claim_reserved_CPU']+state['publication_reserved_CPU']>720):
            raise BudgetError('exact immutable historical INITIAL authorization and retained charges required')
        return state

    def reserve_claim(self, key, *, reservation=None, limits=None, parent_CPU_cap=None, price_pin=None,
                      purpose=None, study=None, scope_id=None, now=None):
        if not safe_key(key): raise BudgetError("canonical claim key required")
        with r.lock(self.lock):
            state = self._read(now)
            if key in state["claims"]: raise BudgetError("control claim already reserved/spent")
            restrictions=state.get('recovery_claims')
            if restrictions is not None:
                from . import policy
                if (restrictions!=recovery_claims(policy.pinned(state['authorization']))
                        or restrictions.get(key)!={'purpose':purpose,'study':study,'scope_id':scope_id}):
                    raise BudgetError('recovery scope permits only its exact root-bound claim role and scope')
            if state["kind"] in {"INITIAL",'INITIAL_SUPPLEMENT'}:
                maximum_claims=3 if state['kind']=='INITIAL' else 1
                if len(state["claims"]) >= maximum_claims: raise BudgetError("initial control claim allowance is spent")
                if state['kind']=='INITIAL_SUPPLEMENT' and key!=state['supplement']['permitted_claim_key']:
                    raise BudgetError('supplement is restricted to its one exact root-bound DK2 claim')
                if (reservation not in (None,230) or limits not in (None,INITIAL_LIMITS)
                        or parent_CPU_cap not in (None,60)):
                    raise BudgetError("initial 230CPU command/parent price cannot change")
                reservation,limits,parent_CPU_cap=230,dict(INITIAL_LIMITS),60
            else:
                from . import policy
                price = policy.pinned(price_pin)
                if (price.get("status") != "ROOT_ADMITTED_EXACT_PREFIX_CONTROL_PRICE"
                        or price.get("controller") != OWNER or price.get("scope_id") != state["scope_id"]
                        or price.get("claim_key") != key or price.get("reservation_CPU") != reservation
                        or price.get("operation_limits") != limits or price.get("parent_CPU_cap") != parent_CPU_cap):
                    raise BudgetError("prefix needs an explicit exact preclaim control price")
            maximum = priced_maximum(limits,parent_CPU_cap)
            if not number(reservation) or not maximum <= reservation or reservation <= 0:
                raise BudgetError("claim reservation does not cover every declared command and parent CPU cap")
            # Initial scope always preserves its separately priced publication30.
            publication = 30 if state["kind"] == "INITIAL" else state["publication_reserved_CPU"]
            if state["claim_reserved_CPU"] + reservation + publication > state["CPU_ceiling"]:
                raise BudgetError("control pool cannot fit the complete next priced claim")
            claim=dict(reserved_CPU=reservation,operation_limits=limits,parent_CPU_cap=parent_CPU_cap,
                priced_command_and_parent_maximum_CPU=maximum,price_pin=price_pin,
                operation_reserved_CPU=0,parent_measured_CPU=0,parent_processes={},
                parent_reserved_CPU=0,parent_slices={},
                counts={k:0 for k in UNITS},operations={},violations=[],no_refund=True)
            state["claims"][key]=claim;state["claim_reserved_CPU"]+=reservation;r.write(self.path,state)
            return claim

    def _claim(self,state,key):
        claim=state["claims"][key]
        if claim["violations"]:raise BudgetError("unreconciled or exceeded control accounting blocks further I/O")
        if any(v["status"]=="CHARGED_BEFORE_IO" for v in claim["operations"].values()):
            raise BudgetError("previous charged I/O lacks reconciled CPU accounting")
        return claim

    def start_operation(self,key,kind,*,now=None):
        """Charge the whole declared slot before invoking SSH/rsync/watcher."""
        if kind not in UNITS:raise BudgetError("unknown control operation")
        with r.lock(self.lock):
            state=self._read(now);claim=self._claim(state,key)
            if claim["counts"][kind]>=claim["operation_limits"][kind]:raise BudgetError("prepriced operation count exhausted")
            cap=sum(UNITS[kind].values())
            if claim["operation_reserved_CPU"]+cap+claim["parent_CPU_cap"]>claim["reserved_CPU"]:
                raise BudgetError("whole operation no longer fits reserved claim")
            token=uuid.uuid4().hex
            claim["counts"][kind]+=1;claim["operation_reserved_CPU"]+=cap
            claim["operations"][token]=dict(kind=kind,status="CHARGED_BEFORE_IO",issued_epoch=time.time() if now is None else now,
                reserved_CPU=cap,**UNITS[kind])
            r.write(self.path,state);return token

    def finish_operation(self,key,token,*,local_CPU,remote_CPU,outcome="COMPLETE",now=None):
        """Persist observed costs; an unknown remote cost is never assumed zero."""
        with r.lock(self.lock):
            state=self._read(now);claim=state["claims"][key];operation=claim["operations"][token]
            if operation["status"]!="CHARGED_BEFORE_IO":raise BudgetError("operation completion is one-use")
            errors=[]
            for label,value in (("local",local_CPU),("remote",remote_CPU)):
                if not number(value):errors.append(label+"_CPU_UNKNOWN")
                elif value>operation[label+"_CPU_cap"]:errors.append(label+"_CPU_CAP_EXCEEDED")
            operation.update(status="MEASURED" if not errors else "BLOCKED_ACCOUNTING",outcome=outcome,
                local_CPU=local_CPU if number(local_CPU) else None,remote_CPU=remote_CPU if number(remote_CPU) else None,
                completed_epoch=time.time() if now is None else now)
            claim["violations"].extend(dict(operation=token,reason=v) for v in errors)
            r.write(self.path,state)
        if errors:raise BudgetError("measured control cost exceeded or lacks declared accounting: "+",".join(errors))
        return operation

    def checkpoint_parent(self,key,identity,cumulative_SELF_and_children_CPU,*,now=None):
        """Charge kernel rusage totals monotonically; counts child CPU twice safely.

        The identity must include PID/start/boot from the caller. The first total
        is charged in full, so replacing or restarting the controller cannot
        erase already consumed CPU. This reports a budget; it supplies no cgroup.
        """
        if (not isinstance(identity,dict) or set(identity)!={"pid","start_ticks","boot_id"}
                or type(identity["pid"]) is not int or identity["pid"]<=0
                or type(identity["start_ticks"]) is not int or identity["start_ticks"]<=0
                or not isinstance(identity["boot_id"],str) or not number(cumulative_SELF_and_children_CPU)):
            raise BudgetError("exact parent lifetime and measured cumulative CPU required")
        lifetime=r.identity(identity)
        with r.lock(self.lock):
            state=self._read(now);claim=state["claims"][key]
            slices=claim.get("parent_slices",{})
            if slices and lifetime not in slices:
                raise BudgetError("this controller lifetime lacks its pre-I/O parent CPU slice")
            previous=claim["parent_processes"].get(lifetime,{}).get("CPU",0)
            if cumulative_SELF_and_children_CPU<previous:raise BudgetError("parent CPU cannot move backward")
            claim["parent_measured_CPU"]+=cumulative_SELF_and_children_CPU-previous
            claim["parent_processes"][lifetime]=dict(identity=identity,CPU=cumulative_SELF_and_children_CPU)
            exceeded=(claim["parent_measured_CPU"]>claim["parent_CPU_cap"]
                      or bool(slices) and cumulative_SELF_and_children_CPU>slices[lifetime]["reserved_CPU"])
            if exceeded:claim["violations"].append(dict(reason="PARENT_CPU_CAP_EXCEEDED",lifetime=lifetime))
            r.write(self.path,state)
        if exceeded:raise BudgetError("cumulative parent control CPU cap exceeded")
        return claim["parent_measured_CPU"]

    def reserve_parent_slice(self,key,identity,CPU_cap,*,now=None):
        """Reserve a finite process lifetime before I/O; process death gives no refund.

        The CLI must apply its corresponding CPU limit before using the slice.
        Unknown final usage conservatively retains the complete reserved slice;
        a later controller may proceed only within the original cumulative cap.
        """
        if (not isinstance(identity,dict) or set(identity)!={"pid","start_ticks","boot_id"}
                or type(identity["pid"]) is not int or identity["pid"]<=0
                or type(identity["start_ticks"]) is not int or identity["start_ticks"]<=0
                or not isinstance(identity["boot_id"],str) or not number(CPU_cap) or CPU_cap<=0):
            raise BudgetError("exact parent lifetime and positive finite CPU slice required")
        cap=math.ceil(CPU_cap);lifetime=r.identity(identity)
        with r.lock(self.lock):
            state=self._read(now);claim=self._claim(state,key)
            slices=claim.setdefault("parent_slices",{})
            if lifetime in slices:raise BudgetError("this process lifetime's parent CPU slice is spent")
            reserved=claim.get("parent_reserved_CPU",0)
            if reserved+cap>claim["parent_CPU_cap"]:raise BudgetError("complete next parent slice cannot fit original cap")
            if claim["parent_processes"] and not slices:
                raise BudgetError("parent slice enforcement cannot discard earlier unreserved accounting")
            slices[lifetime]=dict(identity=identity,reserved_CPU=cap,status="RESERVED_BEFORE_IO",no_refund=True)
            claim["parent_reserved_CPU"]=reserved+cap;r.write(self.path,state);return slices[lifetime]

    def close_parent_slice(self,key,identity,cumulative_SELF_and_children_CPU,*,now=None):
        self.checkpoint_parent(key,identity,cumulative_SELF_and_children_CPU,now=now)
        lifetime=r.identity(identity)
        with r.lock(self.lock):
            state=self._read(now);slice=state["claims"][key]["parent_slices"][lifetime]
            if slice["status"]!="RESERVED_BEFORE_IO":raise BudgetError("parent slice completion is one-use")
            slice.update(status="MEASURED_RESERVED_CPU_RETAINED",measured_SELF_and_children_CPU=cumulative_SELF_and_children_CPU)
            r.write(self.path,state);return slice

    def reserve_publication(self,*,now=None):
        with r.lock(self.lock):
            state=self._read(now)
            if state['kind']=='INITIAL_SUPPLEMENT':raise BudgetError('supplement230 funds exactly one claim; publication30 remains in original pool')
            if state["publication"] is not None:raise BudgetError("publication reservation already spent")
            if state["claim_reserved_CPU"]+30>state["CPU_ceiling"]:raise BudgetError("publication30 does not fit scope")
            state["publication_reserved_CPU"]=30
            state["publication"]=dict(status="CHARGED_BEFORE_IO",reserved_CPU=30,no_refund=True)
            r.write(self.path,state);return state["publication"]
