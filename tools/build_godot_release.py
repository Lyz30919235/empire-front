"""Build the standalone Godot Windows release without touching legacy packages."""
from __future__ import annotations
import argparse
from pathlib import Path
import subprocess
import zipfile
import sys
import re
from download_godot_templates import download

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot"
RELEASE = ROOT / "release"

def release_version():
    """Use the project's major/minor version for both release archive names."""
    project_text = (PROJECT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="(\d+)\.(\d+)\.\d+"$', project_text, re.MULTILINE)
    if not match:
        raise RuntimeError("Project version is missing or invalid")
    return f"{match.group(1)}.{match.group(2)}"

def run(command):
    result = subprocess.run([str(part) for part in command], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        output = result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        output = result.stdout.decode("gb18030", errors="replace")
    RELEASE.mkdir(exist_ok=True)
    with (RELEASE / "godot-build.log").open("a", encoding="utf-8") as log:
        log.write(output + "\n")
    if result.returncode or "SCRIPT ERROR:" in output or "Parse Error:" in output:
        print(output, flush=True)
        raise RuntimeError(f"Godot command failed ({result.returncode})")
    print("Godot command completed; details: release/godot-build.log", flush=True)

def build(godot):
    templates = ROOT / "tools/godot-runtime/templates"
    download(templates)
    RELEASE.mkdir(exist_ok=True)
    run([godot, "--headless", "--path", PROJECT, "--editor", "--import"])
    executable = RELEASE / "EmpireFrontGodot.exe"
    run([godot, "--headless", "--path", PROJECT, "--export-release", "Windows Desktop", executable])
    if not executable.exists() or executable.stat().st_size < 1024 * 1024:
        raise RuntimeError("Export executable missing or empty")
    print(f"Exported {executable} ({executable.stat().st_size:,} bytes)", flush=True)
    return executable

def package(executable):
    executable = Path(executable).resolve()
    if not executable.is_file() or executable.stat().st_size < 1024 * 1024:
        raise RuntimeError("A previously verified Windows executable is required")
    required = [PROJECT / "README.md", PROJECT / "THIRD_PARTY.md", PROJECT / "licenses/GODOT-LICENSE.txt", PROJECT / "licenses/GODOT-COPYRIGHT.txt"]
    for path in required:
        if not path.is_file():
            raise RuntimeError(f"Release documentation missing: {path}")
    RELEASE.mkdir(exist_ok=True)
    version = release_version()
    windows_archive = RELEASE / f"EmpireFrontGodot-Windows-v{version}.zip"
    source_archive = RELEASE / f"EmpireFrontGodot-Source-v{version}.zip"
    with zipfile.ZipFile(windows_archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        bundle.write(executable, executable.name)
        for path in required:
            bundle.write(path, path.relative_to(PROJECT).as_posix())
        for preview in sorted(RELEASE.glob("Godot*.png")):
            bundle.write(preview, "预览/" + preview.name)
    with zipfile.ZipFile(source_archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        bundle.write(PROJECT / "README.md", "README.md")
        for path in PROJECT.rglob("*"):
            relative = path.relative_to(PROJECT)
            if path.is_file() and not any(part in (".godot", ".git", "__pycache__") for part in relative.parts) and path.suffix not in (".import", ".pyc"):
                bundle.write(path, "godot/" + relative.as_posix())
        for filename in ("build_godot_release.py", "download_godot_templates.py"):
            bundle.write(ROOT / "tools" / filename, "tools/" + filename)
        references = ROOT / "tools/skill-references"
        if references.exists():
            for path in references.rglob("*"):
                if path.is_file() and path.suffix.lower() in (".md", ".txt"):
                    bundle.write(path, "tools/skill-references/" + path.relative_to(references).as_posix())
    print(f"Packaged {windows_archive}", flush=True)
    print(f"Packaged {source_archive}", flush=True)

if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / "tools/godot-runtime/Godot_v4.7.2-stable_win64_console.exe")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--build-only", action="store_true")
    selection.add_argument("--package", action="store_true", help="Build and package (default)")
    selection.add_argument("--package-only", action="store_true", help="Package an already verified executable; do not import or export")
    parser.add_argument("--exe", type=Path, default=RELEASE / "EmpireFrontGodot.exe", help="Existing verified executable for --package-only")
    args = parser.parse_args()
    exe = args.exe if args.package_only else build(args.godot)
    if not args.build_only:
        package(exe)
