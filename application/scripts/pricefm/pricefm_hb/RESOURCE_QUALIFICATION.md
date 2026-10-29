# Finite opaque resource and I/O qualification

This is a separate nonnumerical research experiment. It does not rerun a
regional COST panel, deserialize scientific arrays, change scientific prices,
admit a full screen, or amend the scientific worker policy.

`resource_io_worker.py` reads the complete retained FI/DK2 input allowlists as
opaque bytes, copies them into a new owned scratch directory, verifies the
copy, and removes only that new directory. It preserves original file bytes,
modes and metadata. Cache state is reported as unknown. Filesystem devices,
per-phase CPU/wall and process-I/O counters are recorded; this is not a claim
of a cold-cache or numerical memory measurement.

The controller supports separately admitted arrays of two or four tasks. Each
task requests one CPU,4096MiB and120 seconds, with no requeue. It submits held,
writes exact job-bound authority, then explicitly releases. The worker checks
the actual node/array/task/resources and single CPU affinity before I/O.
Rendezvous is bounded; distinct physical cores and real source-hash overlap
are reconciled after collection. An array submission alone is not a successful
parallel qualification. Four tasks require a pinned, canonically accepted
two-task parallel proof with identical source and retained input identities.

Both stages use a new canonical namespace and one-use stage claims. No old
synthetic or COST ledger is reused. Each scope prepays90 administrative CPU
seconds: at most thirteen metadata commands at3CPU, two transfers at11CPU,
and three8CPU parent lifetimes (85CPU maximum grid). Every intent precedes I/O;
failed and interrupted charges are retained. Actual compute allocations are
separate, at most240CPU for two tasks or480CPU for four.

The three explicit controller commands are:

```
python -B resource_qualification.py --authority ROOT.json --authority-sha256 SHA --stage stage
python -B resource_qualification.py --authority ROOT.json --authority-sha256 SHA --stage submit
python -B resource_qualification.py --authority ROOT.json --authority-sha256 SHA --stage finish
```

Use the exact administrative Python on CPU31. ROOT.json must bind the published
controller/worker source, exact compact release, contract, strict dedicated-key
site/host-trust pins, fresh read-only census, aggregate allocation, new output
paths and finite calendar. The original outer endpoint cannot be renewed.
The release contains only the worker, the exact `RUN_SCRIPT` shell entry and
contract.json; credentials and input bank payloads are never uploaded.

`finish` uses one finite parent lifetime and at most two terminal checks, at
least300 seconds apart. It retrieves evidence immediately while accounting
is fresh, validates Slurm JobIDRaw and every array task/batch/srun step,
checks complete source/input/result seals, revalidates the publication copy,
and creates a new atomic publication. Held or ambiguous-release failures
retain their claim. Only exact owned wholly pending metadata jobs can be
cancelled; running jobs with known job authority are tracked without signals.
There is no automatic task resubmission or third poll.

The private tests use tiny opaque fixtures and mocked scheduler/transport
responses. They do not access retained inputs or execute a cluster task.
Actual qualification additionally requires source review/publication,
prospective grants, fresh capacity and successful terminal collection.

Even a successful parallel I/O qualification does not prove worst-case
scientific geometry memory, new numerical service share, complete optional
seed calendars, or the joint1800CPU full-screening controller certificate.
