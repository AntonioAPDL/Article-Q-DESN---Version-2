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
        if (not safe_key(scope_id) or kind not in {"INITIAL", "PREFIX"}
                or not number(now) or not number(expires_epoch) or not now < expires_epoch <= now + 86400):
            raise BudgetError("explicit finite prospective control scope required")
        from . import policy
        authorization = policy.pinned(authorization_pin)
        ceiling = INITIAL_CEILING if kind == "INITIAL" else 1800
        if (authorization.get("status") != "ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE"
                or authorization.get("controller") != OWNER or authorization.get("scope_id") != scope_id
                or authorization.get("kind") != kind or authorization.get("CPU_ceiling") != ceiling
                or authorization.get("nonrenewing") is not True
                or authorization.get("expires_epoch") != expires_epoch):
            raise BudgetError("exact prospective root control CPU authorization required")
        store.path.parent.mkdir(parents=True, exist_ok=True)
        with r.lock(store.lock):
            if store.path.exists(): raise FileExistsError("control scope already exists")
            r.write(store.path, dict(schema=SCHEMA, owner=OWNER, scope_id=scope_id, kind=kind,
                created_epoch=now, expires_epoch=expires_epoch, authorization=authorization_pin,
                CPU_ceiling=ceiling, claim_reserved_CPU=0, publication_reserved_CPU=0,
                no_refund=True, claims={}, publication=None))
        return store

    def _read(self, now=None):
        state = r.read(self.path)
        now = time.time() if now is None else now
        if (state.get("schema") != SCHEMA or state.get("owner") != OWNER or state.get("no_refund") is not True
                or state.get("kind") not in {"INITIAL", "PREFIX"}
                or state.get("CPU_ceiling") != (INITIAL_CEILING if state["kind"] == "INITIAL" else 1800)
                or not state["created_epoch"] <= now < state["expires_epoch"]):
            raise BudgetError("active exact control CPU scope required")
        return state

    def snapshot(self, now=None):
        with r.lock(self.lock): return self._read(now)

    def reserve_claim(self, key, *, reservation=None, limits=None, parent_CPU_cap=None, price_pin=None, now=None):
        if not safe_key(key): raise BudgetError("canonical claim key required")
        with r.lock(self.lock):
            state = self._read(now)
            if key in state["claims"]: raise BudgetError("control claim already reserved/spent")
            if state["kind"] == "INITIAL":
                if len(state["claims"]) >= 3: raise BudgetError("three initial control claims are spent")
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
            if state["publication"] is not None:raise BudgetError("publication reservation already spent")
            if state["claim_reserved_CPU"]+30>state["CPU_ceiling"]:raise BudgetError("publication30 does not fit scope")
            state["publication_reserved_CPU"]=30
            state["publication"]=dict(status="CHARGED_BEFORE_IO",reserved_CPU=30,no_refund=True)
            r.write(self.path,state);return state["publication"]
