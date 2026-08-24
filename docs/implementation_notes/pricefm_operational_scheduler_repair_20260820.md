# PriceFM operational scheduler repair

## Failure classification

The first operational full-shot attempt failed in the preparation control stage
before any model fit. The configured executable was the PriceFM TensorFlow venv
entrypoint, but `Campaign.__init__` called `Path.resolve()` on that path. Because
the venv executable is a symlink, the scheduler replaced it with
`/usr/bin/python3.11`; that system interpreter does not contain NumPy. The
observed `ModuleNotFoundError` is therefore a launcher environment defect, not
a data, architecture, optimization, or model result.

No Phase-I, Phase-II, stability, test, or closeout model artifact was produced
by the failed attempt. The restart contract remains a clean full campaign.

## Repair

The scheduler now:

1. converts the requested Python path to an absolute path without dereferencing
   its venv symlink;
2. runs a mandatory preflight through that exact executable;
3. imports and records Python, NumPy, Pandas, and TensorFlow versions;
4. verifies that `sys.executable` is the requested entrypoint and that
   `sys.prefix != sys.base_prefix`;
5. freezes the preflight result in `python_environment_preflight.json` before
   preparation or fitting;
6. acquires the global PriceFM campaign lock shared with the R56 confirmation,
   in addition to its campaign-local scheduler lock.

The existing resource contract is unchanged: 20 idle physical cores, one model
per physical core, one numerical thread per model, load no greater than 36,
at least 128 GiB available memory, and at least 150 GiB free disk. The scheduler
continues to wait rather than oversubscribe the host.

## Scientific and publication guards

The repair does not alter the operational model, hyperparameter surface,
validation selection, test scoring, registry, or article. It only ensures that
the already preregistered campaign executes in the environment named in its
launch contract. Registry and article mutation remain blocked through closeout.
