"""Windows adapter for the current macOS OCR core. No MLX or Intel-Mac fallback."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import threading
import time

ROOT = Path(os.environ.get("ZHENGXIN_OCR_SUPPORT", Path(os.environ.get("LOCALAPPDATA", Path.home())) / "ZhengxinOCR"))
os.environ["ZHENGXIN_OCR_SUPPORT"] = str(ROOT)
os.environ.setdefault("PADDLE_PDX_CACHE_HOME", str(ROOT / "models" / "paddlex"))
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "huggingface"))
os.environ.setdefault("PYTHONUTF8", "1")
import core

TERMINAL = {"completed", "completed_with_errors", "cancelled", "failed"}
MODES = ("modern", "complex", "ancient")
CONFIG = Path(__file__).with_name("requirements-cpu.lock")


@contextlib.contextmanager
def file_lock(path, wait=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        deadline = time.monotonic() + (10 if wait else 0)
        while True:
            try:
                if os.name == "nt":
                    import msvcrt
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("另一个操作正在修改任务或准备环境，请稍后重试")
                time.sleep(0.02)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == "nt":
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle, fcntl.LOCK_UN)


_save = core.save_state
def save_state(state):
    with file_lock(core.JOBS_DIR / state["job_id"] / "state.lock", wait=True):
        path = core.state_path(state["job_id"])
        if path.exists():
            previous = core.read_json(path)
            if previous.get("cancel_requested"):
                state["cancel_requested"] = True
                if previous.get("status") == "cancelled":
                    state["status"] = "cancelled"
        _save(state)


def config_hash():
    return hashlib.sha256(CONFIG.read_bytes()).hexdigest()


def validate_job(job_id):
    if not re.fullmatch(r"ocr_\d{8}_\d{6}_[0-9a-f]{6}", job_id):
        raise ValueError("无效任务编号")


_load = core.load_state
def load_state(job_id):
    validate_job(job_id)
    return _load(job_id)


def capabilities():
    result = {}
    for mode in MODES:
        path = ROOT / "models" / f"{mode}.json"
        try:
            report = core.read_json(path)
            report["ready"] = bool(report.get("ready") and report.get("config_hash") == config_hash() and inventory_valid(report))
            result[mode] = report
        except (OSError, ValueError):
            result[mode] = {"ready": False, "error": "模型尚未通过识别自检"}
    return result


def inventory_valid(report, full=False):
    files = report.get("files")
    if not files:
        return False
    for entry in files:
        path = (ROOT / "models" / entry["path"]).resolve()
        if not path.is_relative_to((ROOT / "models").resolve()):
            return False
        try:
            if path.stat().st_size != entry["size"] or (full and core.sha256(path) != entry["sha256"]):
                return False
        except OSError:
            return False
    return True


def doctor():
    core.ensure_dirs()
    modules = {name: core.module_available(name) for name in ("paddle", "paddleocr", "pymupdf", "PIL", "psutil")}
    runtime = all(modules.values())
    modes = capabilities()
    return {"platform": platform.system(), "architecture": platform.machine(),
            "python": sys.executable, "runtime_ready": runtime, "modules": modules,
            "models_ready": any(m["ready"] for m in modes.values()),
            "ancient_supported": modes["ancient"]["ready"], "modes": modes,
            "summary": "可用模式已就绪" if runtime and any(m["ready"] for m in modes.values()) else "正在准备运行环境或模型"}


def create_pipeline(profile):
    if profile == "modern":
        from paddleocr import PaddleOCR
        return PaddleOCR(lang="ch", ocr_version="PP-OCRv6", device="cpu",
                         use_doc_orientation_classify=True, use_doc_unwarping=False,
                         use_textline_orientation=True, text_det_limit_side_len=1920,
                         text_det_limit_type="max", cpu_threads=4), False, None
    if profile == "complex":
        from paddleocr import PPStructureV3
        return PPStructureV3(device="cpu"), True, None
    if profile != "ancient":
        raise ValueError("未知识别模式")
    from paddleocr import PaddleOCRVL
    return PaddleOCRVL(pipeline_version="v1.6", device="cpu", vl_rec_backend="native",
                       vl_rec_max_concurrency=1), True, None


def prepare_mode(mode):
    """Constructor downloads models; actual prediction is mandatory before enabling."""
    from PIL import Image, ImageDraw
    core.ensure_dirs()
    target = ROOT / "models" / f"{mode}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    # Remove only files known to differ from the previous successful local inventory.
    # Otherwise downloaders may repeatedly reuse a damaged cache entry.
    if target.exists():
        with contextlib.suppress(OSError, ValueError, KeyError):
            previous = core.read_json(target)
            for entry in previous.get("files", []):
                path = (ROOT / "models" / entry["path"]).resolve()
                if path.is_relative_to((ROOT / "models").resolve()) and path.is_file():
                    if path.stat().st_size != entry["size"] or core.sha256(path) != entry["sha256"]:
                        path.unlink()
    report = {"ready": False, "mode": mode, "config_hash": config_hash(), "checked_at": int(time.time())}
    core.atomic_json(target, report)
    sample = ROOT / "models" / f"smoke-{mode}.png"
    image = Image.new("RGB", (900, 400), "white")
    ImageDraw.Draw(image).text((60, 100), "ZHENGXIN OCR TEST 1234567890", fill="black", font_size=32)
    image.save(sample)
    try:
        pipeline, markdown, _ = create_pipeline(mode)
        results = list(pipeline.predict(str(sample)))
        if not results:
            raise RuntimeError("模型未返回识别结果")
        smoke_dir = ROOT / "models" / "selftest" / mode
        smoke_dir.mkdir(parents=True, exist_ok=True)
        for result in results:
            core.save_result(result, smoke_dir, "smoke", markdown)
        files = []
        for base in (ROOT / "models" / "paddlex", ROOT / "models" / "huggingface"):
            for path in base.rglob("*"):
                if path.is_file() and ".locks" not in path.parts and ".cache" not in path.parts:
                    files.append({"path": str(path.relative_to(ROOT / "models")), "size": path.stat().st_size, "sha256": core.sha256(path)})
        if not files:
            raise RuntimeError("未找到模型缓存，无法确认离线可用性")
        report["files"] = files
        report.update(ready=True, error=None)
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
        raise
    finally:
        core.atomic_json(target, report)
        sample.unlink(missing_ok=True)


def process_matches(state):
    import psutil
    try:
        process = psutil.Process(state["pid"])
        if abs(process.create_time() - state["process_created"]) > 0.1:
            return None
        args = process.cmdline()
        if state["job_id"] not in args or "run" not in args or not any(Path(a).name == "windows_backend.py" for a in args):
            return None
        return process
    except (KeyError, TypeError, psutil.Error):
        return None


def list_jobs():
    core.ensure_dirs()
    jobs = []
    for path in core.JOBS_DIR.glob("*/state.json"):
        with contextlib.suppress(OSError, ValueError):
            state = load_state(path.parent.name)
            if state["status"] not in TERMINAL and not process_matches(state):
                state.update(status="failed", stage_message="工作进程已退出，已完成结果保留")
                core.save_state(state)
            jobs.append(state)
    return sorted(jobs, key=lambda job: job.get("created_at", 0), reverse=True)


def launch_job(job_id):
    import psutil
    state = load_state(job_id)
    with (core.JOBS_DIR / job_id / "worker.log").open("ab", buffering=0) as log:
        # A detached process survives UI exit. Cancel explicitly targets its verified tree.
        flags = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP) if os.name == "nt" else 0
        process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "run", job_id],
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=flags, close_fds=True)
    # Worker waits for this identity record before touching state, avoiding startup races.
    state.update(pid=process.pid, process_created=psutil.Process(process.pid).create_time(), status="starting")
    core.save_state(state)
    threading.Thread(target=process.wait, daemon=True).start()


def cancel(job_id):
    import psutil
    state = load_state(job_id)
    if state["status"] in TERMINAL:
        return state
    state["cancel_requested"] = True
    core.save_state(state)
    process = process_matches(state)
    if process:
        children = process.children(recursive=True)
        # Suspend root before collecting a final descendant list, preventing new children.
        try:
            process.suspend()
            children = process.children(recursive=True)
            for item in [*reversed(children), process]:
                with contextlib.suppress(psutil.NoSuchProcess):
                    item.kill()
            _, alive = psutil.wait_procs([*children, process], timeout=10)
            if alive:
                raise RuntimeError("部分任务进程尚未退出，请重试取消")
        finally:
            with contextlib.suppress(psutil.Error):
                process.resume()
    state = load_state(job_id)
    state.update(status="cancelled", cancel_requested=True, stage_message="任务已取消，已完成结果保留")
    core.save_state(state)
    return state


_submit = core.submit
def _submit_locked(input_path, profile, output, start):
    if any(job["status"] not in TERMINAL for job in list_jobs()):
        raise RuntimeError("已有任务运行，请完成或取消后重试")
    if not capabilities().get(profile, {}).get("ready"):
        raise RuntimeError("此模式尚未通过模型识别自检，请修复环境")
    if Path(input_path).suffix.lower() not in {".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff"}:
        raise ValueError("请选择 PDF、PNG、JPEG 或 TIFF 文件")
    state = _submit(input_path, profile, output, False)
    # Isolate results; existing .complete markers must never reuse a different book.
    state["output"] = str(Path(output).resolve() / state["job_id"])
    Path(state["output"]).mkdir(parents=True, exist_ok=True)
    core.save_state(state)
    if start:
        launch_job(state["job_id"])
        state = load_state(state["job_id"])
    return state


def submit(input_path, profile, output, start):
    with file_lock(ROOT / "submit.lock"), file_lock(ROOT / "prepare.lock"):
        return _submit_locked(input_path, profile, output, start)


core.doctor = doctor
core.create_pipeline = create_pipeline
core.launch_job = launch_job
core.cancel = cancel
core.submit = submit
core.load_state = load_state
core.save_state = save_state


def main():
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "prepare-mode":
            if len(sys.argv) != 3 or sys.argv[2] not in MODES:
                raise ValueError("无效模式")
            prepare_mode(sys.argv[2])
            return 0
        if len(sys.argv) > 1 and sys.argv[1] == "setup-models":
            with file_lock(ROOT / "prepare.lock"):
                for mode in MODES:
                    try:
                        prepare_mode(mode)
                    except Exception as exc:
                        print(f"{mode}: {exc}", file=sys.stderr)
            return 0 if any(m["ready"] for m in capabilities().values()) else 1
        if len(sys.argv) > 1 and sys.argv[1] == "submit" and "--profile" not in sys.argv:
            sys.argv.extend(["--profile", "modern"])
        if len(sys.argv) > 1 and sys.argv[1] == "list":
            core.emit(list_jobs(), True)
            return 0
        if len(sys.argv) == 3 and sys.argv[1] == "check-mode":
            report = capabilities().get(sys.argv[2], {})
            return 0 if report.get("ready") and inventory_valid(report, full=True) else 1
        if len(sys.argv) > 2 and sys.argv[1] == "run":
            for _ in range(100):
                state = load_state(sys.argv[2])
                if state.get("pid") == os.getpid() and state.get("process_created"):
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("启动任务身份记录超时")
        return core.main()
    except Exception as exc:
        core.emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
