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
}


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


def retain_sources(runtime):
    generator = runtime / "generator"
    generator.mkdir(exist_ok=True)
    for name in sorted({name for names in DEPENDENCIES.values() for name in names}):
        shutil.copyfile(source_directory() / (name + ".bend"),generator / (name + ".bend"))


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
    sources = {name: (source_directory() / (name + ".bend")).read_bytes() for name in names}
    fingerprint = hashlib.sha256(version.encode())
    for name, content in sources.items():
        fingerprint.update(name.encode() + b"\0" + content + b"\0")
    cache_root = ROOT / "build" if SCRIPT_DIR.name == "scripts" else Path.home() / ".cache" / "bend-voxel"
    cache = cache_root / "megascene-bend"
    cache.mkdir(parents=True, exist_ok=True)
    key = fingerprint.hexdigest()
    worker = cache / key
    with (cache / (key + ".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not worker.is_file():
            with tempfile.TemporaryDirectory(dir=cache) as directory:
                stage = Path(directory)
                for name, content in sources.items():
                    (stage / (name + ".bend")).write_bytes(content)
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
