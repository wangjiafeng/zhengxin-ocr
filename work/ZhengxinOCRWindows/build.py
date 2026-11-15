"""Cross-publish the Windows application and single setup EXE with .NET 8 SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import ssl
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
CA_FILE = os.environ.get("SSL_CERT_FILE")
if not CA_FILE and Path("/etc/ssl/cert.pem").exists():
    CA_FILE = "/etc/ssl/cert.pem"
TLS = ssl.create_default_context(cafile=CA_FILE)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download(url, target):
    print("Download:", url, flush=True)
    with urllib.request.urlopen(url, timeout=90, context=TLS) as source, target.open("wb") as dest:
        shutil.copyfileobj(source, dest)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--skip-download", action="store_true", help="Reuse verified vendored uv")
    args = parser.parse_args()
    DIST.mkdir(exist_ok=True)
    core = ROOT.parent / "ZhengxinOCRUniversal/Resources/backend/localocr_backend.py"
    shutil.copy2(core, ROOT / "backend/core.py")
    (ROOT / "backend/core-source.json").write_text(json.dumps({"source": str(core.relative_to(ROOT.parent)), "sha256": digest(core)}, indent=2), encoding="utf-8")
    app = DIST / "app"
    subprocess.run([args.dotnet, "publish", str(ROOT / "App/ZhengxinOCR.csproj"), "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", str(app)], check=True)
    resources = app / "resources"
    resources.mkdir(exist_ok=True)
    shutil.copytree(ROOT / "backend", resources / "backend", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("prepare.ps1", "cli.ps1", "帮助.md"):
        shutil.copy2(ROOT / name, resources / name)
    for name in ("localocr.cmd", "localocr-mcp.cmd"):
        shutil.copy2(ROOT / name, app / name)
    tools = resources / "tools"
    tools.mkdir(exist_ok=True)
    archive = DIST / "uv.zip"
    version = "0.9.7"
    url = f"https://github.com/astral-sh/uv/releases/download/{version}/uv-x86_64-pc-windows-msvc.zip"
    if not args.skip_download:
        download(url, archive)
        with urllib.request.urlopen(url + ".sha256", timeout=90, context=TLS) as response:
            expected = response.read().decode().split()[0].lower()
        if len(expected) != 64 or digest(archive) != expected:
            raise RuntimeError("uv archive checksum mismatch")
        with zipfile.ZipFile(archive) as package:
            entry = next(n for n in package.namelist() if n.endswith("uv.exe"))
            (tools / "uv.exe").write_bytes(package.read(entry))
        download(f"https://raw.githubusercontent.com/astral-sh/uv/{version}/LICENSE-MIT", tools / "uv-LICENSE-MIT.txt")
        (tools / "uv-source.json").write_text(json.dumps({"version": version, "source": url, "archive_sha256": expected, "binary_sha256": digest(tools / "uv.exe")}, indent=2), encoding="utf-8")
    else:
        report = json.loads((tools / "uv-source.json").read_text())
        if digest(tools / "uv.exe") != report["binary_sha256"]:
            raise RuntimeError("Vendored uv verification failed")
    # Include a manifest to make future field diagnostics reproducible.
    manifest = {str(p.relative_to(app)): digest(p) for p in sorted(app.rglob("*")) if p.is_file() and p != resources / "build-manifest.json"}
    (resources / "build-manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    with zipfile.ZipFile(DIST / "payload.zip", "w", zipfile.ZIP_DEFLATED) as payload:
        for path in sorted(app.rglob("*")):
            if path.is_file():
                payload.write(path, path.relative_to(app).as_posix())
    setup = DIST / "setup"
    subprocess.run([args.dotnet, "publish", str(ROOT / "Installer/Installer.csproj"), "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", str(setup)], check=True)
    result = ROOT.parents[1] / "outputs/ZhengxinOCR-Windows-Setup-1.0-test.exe"
    shutil.copy2(setup / "ZhengxinOCR-Windows-Setup.exe", result)
    result.with_suffix(".exe.sha256").write_text(digest(result) + "  " + result.name + "\n")
    print("Candidate installer:", result, flush=True)


if __name__ == "__main__":
    main()
