"""Contained execution of untrusted, model-generated Python.

Two Ralph tracks execute code that a model wrote — `ralph-ml-coding` runs each
solution against its own self-test, `ralph-data-drills` runs each Monte Carlo
simulation against its analytic answer. That is the one place in this repo where
running untrusted code is the *point*, so it has to be the most contained part
of it, not the least. Containment lives here, once, so the two tracks cannot
drift apart.

`cwd=<tempdir>` is not containment. A plain `subprocess.run(..., timeout=)`
leaves the code free to write anywhere the user can write, open sockets, read
the parent's environment (API keys, messaging tokens), exhaust memory, and leave
a detached grandchild running after the validator has exited and reported OK.
Each layer below closes one of those.

Layers, outermost first:

1. Process      — its own session (`start_new_session`), so the whole tree can be
                  killed by process *group*; stdin is /dev/null; cwd is a fresh
                  temp dir; the interpreter runs isolated (`-I`: no PYTHON* env
                  vars, no user site-packages, script dir off sys.path).
2. Environment  — rebuilt from an allowlist. The child never sees the parent's
                  environment, so a secret in it cannot be read or exfiltrated.
3. Kernel limits— RLIMIT_NPROC blocks fork bombs and detached grandchildren at
                  the kernel level; RLIMIT_FSIZE caps bytes written; RLIMIT_CORE=0
                  suppresses core dumps of whatever the code was holding.
                  RLIMIT_AS is set where the kernel honours it — Darwin does not
                  (setrlimit(RLIMIT_AS) returns EINVAL there), which is why
                  layer 3b exists rather than being assumed away.
3b. RSS watchdog— the parent samples the child's resident memory and SIGKILLs the
                  group past a cap. Resident, not virtual, is the number that
                  matters: an untouched lazy mapping harms nothing, while touched
                  pages are what push a machine into swap.
4. OS sandbox   — macOS seatbelt via `sandbox-exec`: no network at all, and no
                  filesystem writes outside the run's temp dir. Kernel-enforced,
                  so ctypes cannot talk its way around it.
5. Audit hook   — CPython-level backstop for platforms with no OS sandbox. Vetoes
                  socket creation, process spawning and out-of-sandbox writes.
                  Weaker than layer 4 (ctypes can bypass an audit hook), which is
                  why it is the fallback and not the plan.
6. Timeout      — on expiry the entire process GROUP is SIGKILLed. `subprocess`'s
                  own timeout kills only the direct child.

Public API:

    result = ralph_sandbox.run(python_bin, source, timeout)
    result.returncode        int, or None if it never started / timed out
    result.stdout            str
    result.stderr            str
    result.timed_out         bool
    result.start_error       str or None
    result.layers            list[str]  — containment actually applied, for logs
"""

import os
import platform
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

__all__ = ["run", "Result", "describe"]

DEFAULT_MEMORY_MB = int(os.environ.get("RALPH_SANDBOX_MEM_MB", "2048"))
DEFAULT_MAX_PROCS = int(os.environ.get("RALPH_SANDBOX_MAX_PROCS", "0"))  # 0 = no fork
DEFAULT_FSIZE_MB = int(os.environ.get("RALPH_SANDBOX_FSIZE_MB", "64"))

# Environment variables worth passing through. Everything else — including every
# credential the parent holds — is dropped. PATH is rewritten, not inherited.
ENV_ALLOWLIST = ("LANG", "LC_ALL", "LC_CTYPE", "TZ")
SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

SANDBOX_EXEC = "/usr/bin/sandbox-exec"


class Result(object):
    def __init__(self):
        self.returncode = None
        self.stdout = ""
        self.stderr = ""
        self.timed_out = False
        self.memory_exceeded = False
        self.peak_rss_mb = 0.0
        self.start_error = None
        self.layers = []

    @property
    def ok(self):
        return (self.returncode == 0 and not self.timed_out
                and not self.memory_exceeded and not self.start_error)

    def tail(self, n=6):
        """Last n lines of combined output — what a FAIL line should quote."""
        lines = (self.stdout + self.stderr).strip().splitlines()
        return " | ".join(lines[-n:])


def _build_env(sandbox_dir):
    env = {k: os.environ[k] for k in ENV_ALLOWLIST if k in os.environ}
    env["PATH"] = SAFE_PATH
    env["HOME"] = sandbox_dir
    env["TMPDIR"] = sandbox_dir
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONNOUSERSITE"] = "1"
    # joblib/loky counts physical cores by shelling out to sysctl, and process
    # spawning is blocked in here. Telling it the count up front keeps a
    # scikit-learn cross-check from printing a containment traceback that has
    # nothing to do with the solution being validated. Multiprocessing is off
    # for the same reason: it cannot fork, so let it not try.
    env["LOKY_MAX_CPU_COUNT"] = str(os.cpu_count() or 1)
    env["JOBLIB_MULTIPROCESSING"] = "0"
    return env


def _limit_setter(memory_mb, max_procs, fsize_mb):
    """preexec_fn: applied in the forked child, before exec."""
    def apply_limits():
        def _set(what, value):
            try:
                soft, hard = resource.getrlimit(what)
                if hard != resource.RLIM_INFINITY:
                    value = min(value, hard)
                resource.setrlimit(what, (value, value))
            except (ValueError, OSError, AttributeError):
                pass  # limit unsupported here; other layers still apply

        _set(resource.RLIMIT_CORE, 0)
        if memory_mb:
            _set(resource.RLIMIT_AS, memory_mb * 1024 * 1024)
        if fsize_mb:
            _set(resource.RLIMIT_FSIZE, fsize_mb * 1024 * 1024)
        if hasattr(resource, "RLIMIT_NPROC"):
            # NPROC is counted per real UID, so the value is a ceiling on *new*
            # processes this user can create: fork() from the child fails, while
            # processes that already exist are untouched.
            _set(resource.RLIMIT_NPROC, max_procs)
    return apply_limits


def _seatbelt_profile(sandbox_dir):
    """macOS seatbelt: allow-by-default, then take away network and writes."""
    return (
        "(version 1)\n"
        "(allow default)\n"
        "(deny network*)\n"
        "(deny file-write*)\n"
        '(allow file-write* (subpath "%s"))\n'
        '(allow file-write-data\n'
        '  (literal "/dev/null")\n'
        '  (literal "/dev/zero")\n'
        '  (literal "/dev/random")\n'
        '  (literal "/dev/urandom")\n'
        '  (literal "/dev/dtracehelper")\n'
        '  (literal "/dev/tty"))\n' % sandbox_dir
    )


# The audit-hook runner. Written beside the script and given the script path, so
# tracebacks keep the real filename and line numbers of the code under test.
RUNNER_SOURCE = r'''
import os, runpy, sys, traceback

_ROOTS = tuple(sys.argv[1].split(os.pathsep))
_TARGET = sys.argv[2]
_DEV_OK = ("/dev/null", "/dev/zero", "/dev/random", "/dev/urandom",
           "/dev/tty", "/dev/stdout", "/dev/stderr")

_BLOCK = {
    "socket.socket", "socket.bind", "socket.connect", "socket.getaddrinfo",
    "socket.gethostbyname", "socket.sendto",
    "subprocess.Popen", "os.system", "os.posix_spawn", "os.exec", "os.fork",
    "os.forkpty", "pty.spawn",
}
# Deliberately NOT blocked: ctypes.dlopen/dlsym. numpy imports ctypes during
# `import numpy`, so blocking it would break every legitimate solution in the
# ml-coding track — and it would buy nothing, because ctypes is exactly how an
# audit hook gets bypassed in the first place. The kernel sandbox (layer 4) is
# the boundary that holds against ctypes; this hook is the portable fallback for
# machines that have no kernel sandbox, and it is honest about being weaker.

_WRITE_FLAGS = os.O_WRONLY | os.O_RDWR | os.O_APPEND | os.O_CREAT | os.O_TRUNC


def _is_write(mode, flags):
    if isinstance(mode, str):
        return any(ch in mode for ch in "wax+")
    if isinstance(flags, int):
        return bool(flags & _WRITE_FLAGS)
    return False


def _permitted(path):
    try:
        real = os.path.realpath(path)
    except Exception:
        return False
    if real in _DEV_OK:
        return True
    return any(real == r or real.startswith(r + os.sep) for r in _ROOTS)


def _hook(event, args):
    if event in _BLOCK:
        raise PermissionError(
            "ralph-sandbox: %s is not permitted inside the validator sandbox"
            % event)
    if event == "open":
        path = args[0] if args else None
        mode = args[1] if len(args) > 1 else None
        flags = args[2] if len(args) > 2 else None
        if path is None or isinstance(path, int):
            return
        if _is_write(mode, flags) and not _permitted(path):
            raise PermissionError(
                "ralph-sandbox: write outside the sandbox directory is not "
                "permitted: %s" % (path,))


sys.addaudithook(_hook)
sys.argv = [_TARGET]

try:
    runpy.run_path(_TARGET, run_name="__main__")
except SystemExit:
    raise
except BaseException:
    exc_type, exc, tb = sys.exc_info()
    frames = [f for f in traceback.extract_tb(tb) if f.filename != __file__]
    sys.stderr.write("Traceback (most recent call last):\n")
    sys.stderr.write("".join(traceback.format_list(frames)))
    sys.stderr.write("".join(traceback.format_exception_only(exc_type, exc)))
    sys.exit(1)
'''


def describe():
    """One line naming the containment available on this machine."""
    layers = ["isolated interpreter", "scrubbed environment",
              "rlimits (NPROC/FSIZE/CORE)", "RSS watchdog",
              "audit hook", "process-group kill"]
    if _seatbelt_available():
        layers.insert(3, "macOS seatbelt (no network, no outside writes)")
    else:
        layers.append("NO OS SANDBOX on %s — audit hook is the only network/FS "
                      "boundary" % platform.system())
    return "sandbox: " + ", ".join(layers)


def _seatbelt_available():
    return sys.platform == "darwin" and os.path.exists(SANDBOX_EXEC)


def run(python_bin, source, timeout, filename="script.py",
        memory_mb=DEFAULT_MEMORY_MB, max_procs=DEFAULT_MAX_PROCS,
        fsize_mb=DEFAULT_FSIZE_MB, grace=5):
    """Execute `source` with `python_bin` under every containment layer above.

    Never raises for anything the code under test does; failures come back on
    the Result so the caller can turn them into FAIL lines.
    """
    result = Result()
    tmp = tempfile.mkdtemp(prefix="ralph-sbx-")
    # macOS hands out /var/folders paths that are symlinks to /private/var;
    # seatbelt subpaths and the audit hook both compare resolved paths.
    sandbox_dir = os.path.realpath(tmp)
    try:
        script = os.path.join(sandbox_dir, filename)
        with open(script, "w") as fh:
            fh.write(source if source.endswith("\n") else source + "\n")
        runner = os.path.join(sandbox_dir, "_ralph_runner.py")
        with open(runner, "w") as fh:
            fh.write(RUNNER_SOURCE)

        argv = [python_bin, "-I", "-B", runner, sandbox_dir, script]
        result.layers = ["-I isolated", "env allowlist",
                         "rlimits(NPROC=%d, FSIZE=%dMB)" % (max_procs, fsize_mb),
                         "rss watchdog(%dMB)" % memory_mb,
                         "audit hook", "setsid + killpg"]

        if _seatbelt_available():
            profile = os.path.join(sandbox_dir, "_ralph.sb")
            with open(profile, "w") as fh:
                fh.write(_seatbelt_profile(sandbox_dir))
            argv = [SANDBOX_EXEC, "-f", profile] + argv
            result.layers.insert(0, "seatbelt")

        try:
            proc = subprocess.Popen(
                argv,
                cwd=sandbox_dir,
                env=_build_env(sandbox_dir),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
                preexec_fn=_limit_setter(memory_mb, max_procs, fsize_mb),
            )
        except OSError as exc:
            result.start_error = "could not start the sandboxed interpreter: %s" % exc
            return result

        watchdog = _RssWatchdog(proc.pid, memory_mb) if memory_mb else None
        if watchdog is not None:
            watchdog.start()
        try:
            try:
                out, err = proc.communicate(timeout=timeout)
                result.returncode = proc.returncode
            except subprocess.TimeoutExpired:
                _kill_group(proc)
                try:
                    out, err = proc.communicate(timeout=grace)
                except Exception:
                    out, err = b"", b""
                result.timed_out = True
        finally:
            if watchdog is not None:
                watchdog.stop()
                watchdog.join(timeout=2)
                result.peak_rss_mb = round(watchdog.peak_kb / 1024.0, 1)
                # A kill by the watchdog surfaces as a SIGKILLed child, so the
                # watchdog's own flag is what distinguishes it from a timeout.
                if watchdog.tripped:
                    result.memory_exceeded = True
                    result.timed_out = False

        result.stdout = _text(out)
        result.stderr = _text(err)
        return result
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


class _RssWatchdog(threading.Thread):
    """SIGKILL the sandboxed process group once its resident memory passes a cap.

    Darwin ignores setrlimit(RLIMIT_AS) — it returns EINVAL — so on macOS this is
    the only thing standing between a `bytearray(64 * 2**30)` in a generated
    solution and the machine going to swap. It samples with ps(1) so it works
    against a stock interpreter with nothing installed.

    Resident, not virtual, is the number that matters: an untouched lazy mapping
    costs nothing, while touched pages are what cause swapping.

    The guarantee is "killed within one poll interval of crossing the cap", not
    "never exceeds the cap". memset runs at roughly 10 GB/s, so a deliberate bomb
    can overshoot by a few hundred MB inside one 20 ms window before the kill
    lands. Sampling the child directly costs ~2 ms; a full process-group scan
    costs ~19 ms, so the group scan runs every GROUP_EVERY samples to catch a
    process that somehow forked despite RLIMIT_NPROC.
    """

    PS = "/bin/ps"
    INTERVAL = 0.02
    GROUP_EVERY = 25

    def __init__(self, pid, cap_mb):
        threading.Thread.__init__(self)
        self.daemon = True
        self.pid = pid
        self.cap_kb = cap_mb * 1024
        self.tripped = False
        self.peak_kb = 0
        self._halt = threading.Event()

    def _ps(self, args):
        try:
            return subprocess.check_output(
                [self.PS] + args, stderr=subprocess.DEVNULL
            ).decode("ascii", "replace")
        except Exception:
            return None

    def _self_rss_kb(self):
        out = self._ps(["-o", "rss=", "-p", str(self.pid)])
        if not out:
            return None
        try:
            return int(out.split()[0])
        except (IndexError, ValueError):
            return None

    def _group_rss_kb(self):
        try:
            pgid = os.getpgid(self.pid)
        except OSError:
            return None
        out = self._ps(["-A", "-o", "pgid=,rss="])
        if out is None:
            return None
        total, seen = 0, False
        for line in out.splitlines():
            parts = line.split()
            if len(parts) != 2:
                continue
            try:
                if int(parts[0]) == pgid:
                    total += int(parts[1])
                    seen = True
            except ValueError:
                continue
        return total if seen else None

    def run(self):
        n = 0
        while not self._halt.wait(self.INTERVAL):
            n += 1
            rss = (self._group_rss_kb() if n % self.GROUP_EVERY == 0
                   else self._self_rss_kb())
            if rss is None:
                continue
            self.peak_kb = max(self.peak_kb, rss)
            if rss > self.cap_kb:
                self.tripped = True
                try:
                    os.killpg(os.getpgid(self.pid), signal.SIGKILL)
                except Exception:
                    pass
                return

    def stop(self):
        self._halt.set()


def _kill_group(proc):
    """SIGKILL the whole session, so a detached grandchild dies with it."""
    for attempt in (
        lambda: os.killpg(os.getpgid(proc.pid), signal.SIGKILL),
        lambda: proc.kill(),
    ):
        try:
            attempt()
            return
        except Exception:
            continue


def _text(blob):
    if blob is None:
        return ""
    if isinstance(blob, bytes):
        return blob.decode("utf-8", "replace")
    return blob
