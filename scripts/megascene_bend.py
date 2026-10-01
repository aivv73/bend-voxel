import fcntl
import hashlib
from functools import lru_cache
import os
from pathlib import Path
import subprocess
import shutil
import tempfile

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent if SCRIPT_DIR.name == "scripts" else SCRIPT_DIR
DEPENDENCIES = {
    "megascene_source": ("megascene_source", "megascene_recipe", "math"),
    "megascene_policy": ("megascene_policy", "megascene_scale"),
    "megascene_admit": ("megascene_admit", "megascene_admission", "megascene_scale", "megascene_recipe", "math"),
    "megascene_schedule": ("megascene_schedule", "schedule_route", "schedule_history", "schedule_cut", "schedule_policy", "schedule_proxy", "schedule_float", "schedule_json", "schedule_points", "megascene_scale"),
    "schedule_points": ("schedule_points",),
    "schedule_binary": ("schedule_binary", "schedule_points", "schedule_file"),
    "megascene_inputs": ("megascene_inputs", "megascene_source", "megascene_recipe", "math", "schedule_points", "schedule_json"),
    "megascene_admission_inputs": ("megascene_admission_inputs", "megascene_inputs", "megascene_source", "megascene_recipe", "math", "schedule_points", "schedule_json"),
}


def dependency_files(names):
    return tuple(name + extension for name in names for extension in
                 ((".bend", ".c", ".js") if name == "schedule_float" else (".bend",)))


@lru_cache(maxsize=1)
def compiler_version():
    version = subprocess.run(["bend", "version"], capture_output=True, text=True,
                             check=True, timeout=10).stdout.strip()
    if version != "bend 2.0.34":
        raise RuntimeError("Megascene is pinned to Bend 2.0.34")
    return version


def source_directory():
    generator = ROOT / "generator"
    return generator if generator.is_dir() else ROOT / "src"


def cache_root():
    explicit = os.environ.get("MEGASCENE_CACHE_ROOT")
    if explicit:
        root = Path(explicit)
        if not root.is_absolute():
            raise ValueError("MEGASCENE_CACHE_ROOT must be an absolute path")
        return root
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg and Path(xdg).is_absolute():
        return Path(xdg) / "bend-voxel"
    return ROOT / "build" if SCRIPT_DIR.name == "scripts" else Path.home() / ".cache" / "bend-voxel"


def retain_sources(runtime):
    generator = runtime / "generator"
    generator.mkdir(exist_ok=True)
    for name in sorted({name for names in DEPENDENCIES.values() for name in dependency_files(names)}):
        shutil.copyfile(source_directory() / name, generator / name)


@lru_cache(maxsize=2048)
def invoke(worker, arguments):
    result = subprocess.run([str(worker), "--threads", "1", "--", *arguments],
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Bend worker rejected input")
    return result.stdout


def worker(module):
    names = DEPENDENCIES[module]
    version = compiler_version()
    sources = {name: (source_directory() / name).read_bytes() for name in dependency_files(names)}
    fingerprint = hashlib.sha256(version.encode())
    for name, content in sources.items():
        fingerprint.update(name.encode() + b"\0" + content + b"\0")
    cache = cache_root() / "megascene-bend"
    cache.mkdir(parents=True, exist_ok=True)
    key = fingerprint.hexdigest()
    worker = cache / key
    with (cache / (key + ".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not worker.is_file():
            with tempfile.TemporaryDirectory(dir=cache) as directory:
                stage = Path(directory)
                for name, content in sources.items():
                    (stage / name).write_bytes(content)
                result = subprocess.run(["bend", str(stage / (module + ".bend")),
                                         "-o", str(stage / "worker")],
                                        capture_output=True, text=True, timeout=120)
                if result.returncode:
                    raise RuntimeError("Bend worker build failed\n" + result.stdout + result.stderr)
                os.replace(stage / "worker", worker)
    return worker


def run(module, *arguments):
    return invoke(worker(module), tuple(str(argument) for argument in arguments))


def run_input(module, text):
    executable = worker(module)
    with tempfile.NamedTemporaryFile(mode="w", encoding="ascii") as request:
        request.write(text)
        request.flush()
        result = subprocess.run([str(executable), "--threads", "1", "--", request.name],
                                capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Bend worker rejected input")
    return result.stdout


def run_binary(module, text):
    executable = worker(module)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        request, output = root / "request", root / "output"
        request.write_text(text, encoding="ascii")
        result = subprocess.run([str(executable), "--threads", "1", "--", str(request), str(output)],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise ValueError(result.stderr.strip() or "Bend worker rejected input")
        return output.read_bytes()
