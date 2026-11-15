#!/usr/bin/env python3
"""Local OCR job runner for the universal ZhengxinOCR installer edition."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import os
import platform
import shutil
import signal
import socket
import subprocess
import sys
import time
import traceback
import uuid
import unicodedata
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


APP_SUPPORT = Path(os.environ.get(
    "ZHENGXIN_OCR_SUPPORT",
    Path.home() / "Library" / "Application Support" / "ZhengxinOCRUniversal",
))
RESOURCE_DIR = Path(__file__).resolve().parents[1]
RUNTIME_DIR = APP_SUPPORT / "runtime"
MODELS_DIR = APP_SUPPORT / "models"
JOBS_DIR = APP_SUPPORT / "jobs"
LOGS_DIR = APP_SUPPORT / "logs"
VL_MODEL_DIR = MODELS_DIR / "PaddleOCR-VL-1.6"
MODELS_MARKER = MODELS_DIR / ".setup-complete"
MLX_PORT = 8111


def ensure_dirs() -> None:
    for path in (APP_SUPPORT, JOBS_DIR, LOGS_DIR):
        path.mkdir(parents=True, exist_ok=True)


def emit(value: Any, json_mode: bool = False) -> None:
    if json_mode or isinstance(value, (dict, list)):
        print(json.dumps(value, ensure_ascii=False, indent=None if json_mode else 2))
    else:
        print(value)


def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(path)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def state_path(job_id: str) -> Path:
    return JOBS_DIR / job_id / "state.json"


def load_state(job_id: str) -> dict[str, Any]:
    path = state_path(job_id)
    if not path.exists():
        raise FileNotFoundError(f"任务不存在：{job_id}")
    return read_json(path)


def save_state(state: dict[str, Any]) -> None:
    state["updated_at"] = int(time.time())
    atomic_json(state_path(state["job_id"]), state)


def stage(state: dict[str, Any], status: str, message: str) -> None:
    state["status"] = status
    state["stage_message"] = message
    save_state(state)
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def doctor() -> dict[str, Any]:
    ensure_dirs()
    active_python = Path(sys.executable)
    checks = {
        "architecture": platform.machine(),
        "macos": platform.mac_ver()[0],
        "bootstrap_python": str(active_python),
        "runtime_marker": (RUNTIME_DIR / "runtime.json").is_file(),
        "paddle": module_available("paddle"),
        "paddleocr": module_available("paddleocr"),
        "mlx": module_available("mlx"),
        "mlx_vlm": module_available("mlx_vlm"),
        "pymupdf": module_available("pymupdf"),
        "vl_model_local": VL_MODEL_DIR.exists(),
        "free_gb": round(shutil.disk_usage(APP_SUPPORT).free / (1024**3), 1),
    }
    required = ["runtime_marker", "paddle", "paddleocr", "pymupdf"]
    if platform.machine() == "arm64":
        required.extend(["mlx", "mlx_vlm"])
    ready = all(checks[key] for key in required)
    checks["ready"] = ready
    checks["runtime_ready"] = ready
    checks["models_ready"] = MODELS_MARKER.exists()
    checks["feature_level"] = "full" if platform.machine() == "arm64" else "intel_legacy"
    checks["ancient_supported"] = platform.machine() == "arm64"
    checks["python"] = str(active_python)
    if ready and checks["models_ready"]:
        checks["summary"] = "运行环境与模型均已就绪，可以开始识别。"
    elif ready:
        checks["summary"] = "运行环境已就绪，请继续安装模型。"
    else:
        checks["summary"] = "运行环境不完整，请重新执行首次安装。"
    return checks


def setup_runtime() -> None:
    report = doctor()
    if not report["runtime_ready"]:
        raise RuntimeError("运行环境尚未安装完整，请重新执行首次安装。")
    print("运行环境验证通过。", flush=True)


def setup_models() -> None:
    ensure_dirs()
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    architecture = platform.machine()
    print(f"检测到 {architecture}，开始下载并初始化所需模型…", flush=True)
    if architecture == "arm64":
        from huggingface_hub import snapshot_download
        from paddleocr import PaddleOCR, PaddleOCRVL, PPStructureV3

        snapshot_download(repo_id="PaddlePaddle/PaddleOCR-VL-1.6", local_dir=VL_MODEL_DIR)
        PaddleOCR(lang="ch", ocr_version="PP-OCRv6", device="cpu")
        PPStructureV3(device="cpu")
        PaddleOCRVL(
            pipeline_version="v1.6",
            device="cpu",
            vl_rec_backend="mlx-vlm-server",
            vl_rec_server_url="http://127.0.0.1:8111/",
            vl_rec_api_model_name=str(VL_MODEL_DIR),
            vl_rec_max_concurrency=1,
        )
        modes = ["modern", "complex", "ancient"]
    else:
        from paddleocr import PaddleOCR, PPStructure

        PaddleOCR(use_angle_cls=True, lang="ch", show_log=True)
        PPStructure(show_log=True)
        modes = ["modern", "complex"]
    atomic_json(MODELS_MARKER, {
        "prepared_at": int(time.time()),
        "architecture": architecture,
        "modes": modes,
    })
    print("模型安装完成；后续识别可以离线运行。", flush=True)


def submit(input_path: str, profile: str, output: str, start: bool) -> dict[str, Any]:
    ensure_dirs()
    source = Path(input_path).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(f"输入文件不存在：{source}")
    output_dir = Path(output).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    job_id = time.strftime("ocr_%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6]
    job_dir = JOBS_DIR / job_id
    job_dir.mkdir(parents=True)
    state = {
        "job_id": job_id,
        "status": "queued",
        "profile": profile,
        "input": str(source),
        "input_sha256": sha256(source),
        "output": str(output_dir),
        "completed_pages": 0,
        "rendered_pages": 0,
        "recognized_pages": 0,
        "processed_pages": 0,
        "current_page": 0,
        "total_pages": 0,
        "failed_pages": 0,
        "failed_page_numbers": [],
        "cancel_requested": False,
        "created_at": int(time.time()),
        "updated_at": int(time.time()),
        "pid": None,
        "error": None,
        "stage_message": "任务已进入队列",
    }
    save_state(state)
    if start:
        launch_job(job_id)
    return state


def launch_job(job_id: str) -> None:
    if not doctor()["runtime_ready"]:
        raise RuntimeError("应用包中的运行依赖不完整。")
    log_path = JOBS_DIR / job_id / "worker.log"
    log_handle = log_path.open("ab", buffering=0)
    process = subprocess.Popen(
        [sys.executable, __file__, "run", job_id],
        stdin=subprocess.DEVNULL,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )
    state = load_state(job_id)
    state["pid"] = process.pid
    state["status"] = "starting"
    save_state(state)


def port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.4)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def ensure_mlx_server(job_dir: Path) -> subprocess.Popen[bytes] | None:
    if port_open(MLX_PORT):
        return None
    log = (job_dir / "mlx-vlm.log").open("ab", buffering=0)
    process = subprocess.Popen(
        [sys.executable, "-m", "mlx_vlm.server", "--port", str(MLX_PORT)],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )
    deadline = time.time() + 90
    while time.time() < deadline:
        if process.poll() is not None:
            raise RuntimeError("MLX-VLM服务启动失败，请查看任务日志。")
        if port_open(MLX_PORT):
            return process
        time.sleep(1)
    process.terminate()
    raise TimeoutError("MLX-VLM服务启动超时。")


def source_page_count(source: Path) -> int:
    if source.suffix.lower() != ".pdf":
        return 1
    import pymupdf

    with pymupdf.open(source) as document:
        return document.page_count


def render_page(
    source: Path,
    pages_dir: Path,
    page_number: int,
    dpi: int,
    document: Any = None,
) -> Path:
    if source.suffix.lower() != ".pdf":
        return source
    if document is None:
        raise RuntimeError("PDF 文档尚未打开。")
    import pymupdf

    pages_dir.mkdir(parents=True, exist_ok=True)
    target = pages_dir / f"page-{page_number:04d}.png"
    if target.exists() and target.stat().st_size > 0:
        return target
    partial = pages_dir / f"page-{page_number:04d}.partial.png"
    with contextlib.suppress(FileNotFoundError):
        partial.unlink()
    scale = dpi / 72.0
    pixmap = document[page_number - 1].get_pixmap(
        matrix=pymupdf.Matrix(scale, scale), alpha=False
    )
    pixmap.save(partial)
    partial.replace(target)
    return target


def save_result(result: Any, target_dir: Path, stem: str, markdown: bool) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    saved = False
    if hasattr(result, "save_to_json"):
        result.save_to_json(str(target_dir))
        saved = True
    if markdown and hasattr(result, "save_to_markdown"):
        result.save_to_markdown(str(target_dir))
        saved = True
    if hasattr(result, "save_to_img"):
        with contextlib.suppress(Exception):
            result.save_to_img(str(target_dir / "visualized"))
    if not saved:
        (target_dir / f"{stem}.txt").write_text(str(result), encoding="utf-8")


def native_text_result(page: Any) -> dict[str, Any] | None:
    """Use visible PDF text only on text-only pages with usable Unicode.

    Raster pages (including scans with an invisible OCR layer), mixed pages,
    sparse pages and broken character maps stay on the OCR path.
    """
    if page.get_image_info():
        return None
    traces = page.get_texttrace()
    if not traces or any(span.get("type") == 3 or span.get("opacity", 1) < 0.1 for span in traces):
        return None
    lines = []
    boxes = []
    for block in page.get_text("dict", sort=True)["blocks"]:
        if block.get("type") != 0:
            return None
        for line in block.get("lines", []):
            text = "".join(span["text"] for span in line["spans"]).strip()
            if text:
                lines.append(text)
                boxes.append(list(line["bbox"]))
    content = "".join(lines)
    chars = [char for char in content if not char.isspace()]
    if len(chars) < 80 or sum(char.isalnum() for char in chars) / len(chars) < 0.5:
        return None
    if any(char == "\ufffd" or unicodedata.category(char) in {"Co", "Cs", "Cc", "Cn"} for char in chars):
        return None
    return {
        "extraction_method": "pdf_visible_text",
        "coordinate_unit": "pdf_points",
        "rec_texts": lines,
        "rec_boxes": boxes,
    }


def merge_document(result_root: Path, output: Path) -> None:
    markdown_files = sorted(result_root.glob("page-*/*.md"))
    if markdown_files:
        parts = []
        for index, path in enumerate(markdown_files, start=1):
            parts.append(f"\n\n<!-- page {index}: {path.name} -->\n\n")
            parts.append(path.read_text(encoding="utf-8", errors="replace"))
        (output / "document.md").write_text("".join(parts).lstrip(), encoding="utf-8")

    json_files = sorted(result_root.glob("page-*/*.json"))
    text_pages: list[str] = []
    for path in json_files:
        with contextlib.suppress(Exception):
            payload = read_json(path)
            texts: list[str] = []

            def walk(value: Any) -> None:
                if isinstance(value, dict):
                    for key, item in value.items():
                        if key in {"rec_texts", "texts"} and isinstance(item, list):
                            texts.extend(str(entry) for entry in item if str(entry).strip())
                        else:
                            walk(item)
                elif isinstance(value, list):
                    for item in value:
                        walk(item)

            walk(payload)
            if texts:
                text_pages.append("\n".join(texts))
    if text_pages:
        (output / "document.txt").write_text("\n\n\f\n\n".join(text_pages), encoding="utf-8")


class LegacyResult:
    """Adapts PaddleOCR 2.x results to the version 3 save interface."""

    def __init__(self, stem: str, payload: Any, markdown: bool) -> None:
        self.stem = stem
        self.payload = payload
        self.markdown = markdown

    def texts(self) -> list[str]:
        found: list[str] = []

        def walk(value: Any) -> None:
            if isinstance(value, dict):
                if isinstance(value.get("text"), str):
                    found.append(value["text"])
                for item in value.values():
                    walk(item)
            elif isinstance(value, (list, tuple)):
                if len(value) >= 2 and isinstance(value[0], str) and isinstance(value[1], (int, float)):
                    found.append(value[0])
                else:
                    for item in value:
                        walk(item)

        walk(self.payload)
        return [text for text in found if text.strip()]

    def save_to_json(self, directory: str) -> None:
        target = Path(directory)
        target.mkdir(parents=True, exist_ok=True)

        def json_safe(value: Any) -> Any:
            if isinstance(value, dict):
                return {
                    str(key): json_safe(item)
                    for key, item in value.items()
                    if key != "img"
                }
            if isinstance(value, (list, tuple)):
                return [json_safe(item) for item in value]
            if isinstance(value, (str, int, float, bool)) or value is None:
                return value
            if hasattr(value, "tolist"):
                return value.tolist()
            return str(value)

        atomic_json(target / f"{self.stem}_res.json", {
            "texts": self.texts(),
            "legacy_result": json_safe(self.payload),
        })

    def save_to_markdown(self, directory: str) -> None:
        if not self.markdown:
            return
        target = Path(directory)
        target.mkdir(parents=True, exist_ok=True)
        (target / f"{self.stem}.md").write_text(
            "\n\n".join(self.texts()), encoding="utf-8"
        )


class LegacyPipeline:
    def __init__(self, mode: str) -> None:
        self.mode = mode
        if mode == "modern":
            from paddleocr import PaddleOCR

            self.engine = PaddleOCR(use_angle_cls=True, lang="ch", show_log=True)
        else:
            from paddleocr import PPStructure

            self.engine = PPStructure(show_log=True)

    def predict(self, input_path: str) -> list[LegacyResult]:
        if self.mode == "modern":
            payload = self.engine.ocr(input_path, cls=True)
            markdown = False
        else:
            payload = self.engine(input_path)
            markdown = True
        return [LegacyResult(Path(input_path).stem, payload, markdown)]


def create_pipeline(profile: str) -> tuple[Any, bool, subprocess.Popen[bytes] | None]:
    if platform.machine() == "x86_64":
        if profile == "ancient":
            raise RuntimeError(
                "Intel Mac 不支持 PaddleOCR-VL/MLX 古籍模式，请选择复杂排版或普通扫描。"
            )
        return LegacyPipeline(profile), profile == "complex", None
    if profile == "modern":
        from paddleocr import PaddleOCR

        return (
            PaddleOCR(
                lang="ch",
                ocr_version="PP-OCRv6",
                device="cpu",
                use_doc_orientation_classify=True,
                use_doc_unwarping=False,
                use_textline_orientation=True,
                text_det_limit_side_len=1920,
                text_det_limit_type="max",
                cpu_threads=4,
            ),
            False,
            None,
        )
    if profile == "complex":
        from paddleocr import PPStructureV3

        return PPStructureV3(device="cpu"), True, None
    from paddleocr import PaddleOCRVL

    job_dir = Path.cwd()
    server = ensure_mlx_server(job_dir)
    model_ref = str(VL_MODEL_DIR) if VL_MODEL_DIR.exists() else "PaddlePaddle/PaddleOCR-VL-1.6"
    pipeline = PaddleOCRVL(
        pipeline_version="v1.6",
        device="cpu",
        vl_rec_backend="mlx-vlm-server",
        vl_rec_server_url=f"http://127.0.0.1:{MLX_PORT}/",
        vl_rec_api_model_name=model_ref,
        vl_rec_max_concurrency=1,
    )
    return pipeline, True, server


def run_job(job_id: str) -> None:
    ensure_dirs()
    state = load_state(job_id)
    job_dir = JOBS_DIR / job_id
    os.chdir(job_dir)
    server: subprocess.Popen[bytes] | None = None
    document: Any = None
    started = time.perf_counter()
    page_timings: list[dict[str, Any]] = []
    reused_pages = 0
    try:
        state["pid"] = os.getpid()
        stage(state, "preparing", "正在读取文档信息…")
        source = Path(state["input"])
        output = Path(state["output"])
        total_pages = source_page_count(source)
        state["total_pages"] = total_pages
        state["rendered_pages"] = 0
        state["recognized_pages"] = 0
        state["processed_pages"] = 0
        state["completed_pages"] = 0
        stage(state, "preparing", f"文档共 {total_pages} 页，正在检查页面…")
        pipeline = None
        markdown = state["profile"] != "modern"
        state["server_pid"] = None
        state["native_text_pages"] = 0
        result_root = output / "raw"
        failures: list[int] = list(state.get("failed_page_numbers") or [])
        recognized = 0
        processed = 0
        rendered = 0
        if source.suffix.lower() == ".pdf":
            import pymupdf

            document = pymupdf.open(source)
        dpi = 450 if state["profile"] == "ancient" else 350
        for index in range(1, total_pages + 1):
            latest = load_state(job_id)
            if latest.get("cancel_requested"):
                state.update(latest)
                stage(state, "cancelled", "任务已取消，已完成结果予以保留。")
                return
            page_dir = result_root / f"page-{index:04d}"
            marker = page_dir / ".complete"
            if marker.exists():
                reused_pages += 1
                recognized += 1
                processed += 1
                native = (page_dir / "native-text.json").exists()
                if native:
                    state["native_text_pages"] += 1
                else:
                    rendered += 1
                state["rendered_pages"] = rendered
                state["recognized_pages"] = recognized
                state["processed_pages"] = processed
                state["completed_pages"] = processed
                save_state(state)
                continue

            state["current_page"] = index
            page_started = time.perf_counter()
            method = "ocr"
            try:
                native = None
                if state["profile"] == "modern" and document is not None:
                    with contextlib.suppress(Exception):
                        native = native_text_result(document[index - 1])
                if native is not None:
                    method = "pdf_visible_text"
                    stage(state, "recognizing", f"正在提取第 {index}/{total_pages} 页原生文字…")
                    atomic_json(page_dir / "native-text.json", native)
                    state["native_text_pages"] += 1
                else:
                    if pipeline is None:
                        stage(state, "loading_model", f"正在为第 {index}/{total_pages} 页加载识别模型…")
                        pipeline, markdown, server = create_pipeline(state["profile"])
                        state["server_pid"] = server.pid if server is not None else None
                    stage(state, "rendering", f"正在渲染第 {index}/{total_pages} 页…")
                    page = render_page(source, job_dir / "pages", index, dpi, document)
                    rendered += 1
                    state["rendered_pages"] = rendered
                    stage(state, "recognizing", f"正在识别第 {index}/{total_pages} 页…")
                    results = pipeline.predict(str(page))
                    for result in results:
                        save_result(result, page_dir, page.stem, markdown)
                    if page != source:
                        with contextlib.suppress(FileNotFoundError):
                            page.unlink()
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.write_text("ok\n", encoding="utf-8")
                recognized += 1
            except Exception:
                if index not in failures:
                    failures.append(index)
                page_dir.mkdir(parents=True, exist_ok=True)
                (page_dir / "error.txt").write_text(traceback.format_exc(), encoding="utf-8")
                print(f"[{time.strftime('%H:%M:%S')}] 第 {index} 页识别失败。", flush=True)
            page_timings.append({"page": index, "method": method, "seconds": round(time.perf_counter() - page_started, 4)})
            processed += 1
            state["processed_pages"] = processed
            state["completed_pages"] = processed
            state["recognized_pages"] = recognized
            state["failed_page_numbers"] = failures
            state["failed_pages"] = len(failures)
            save_state(state)
        state["current_page"] = total_pages
        merge_document(result_root, output)
        atomic_json(output / "performance.json", {
            "profile": state["profile"], "native_text_pages": state["native_text_pages"],
            "reused_pages": reused_pages,
            "elapsed_seconds": round(time.perf_counter() - started, 4),
            "pages": page_timings,
        })
        final_status = "completed" if not failures else "completed_with_errors"
        final_message = (
            f"识别完成，共 {recognized} 页。"
            if not failures
            else f"处理完成，成功 {recognized} 页，失败 {len(failures)} 页。"
        )
        stage(state, final_status, final_message)
    except Exception as exc:
        state["status"] = "failed"
        state["error"] = f"{type(exc).__name__}: {exc}"
        state["stage_message"] = f"任务失败：{type(exc).__name__}: {exc}"
        save_state(state)
        traceback.print_exc()
        raise
    finally:
        if document is not None:
            document.close()
        if server is not None and server.poll() is None:
            server.terminate()


def cancel(job_id: str) -> dict[str, Any]:
    state = load_state(job_id)
    state["cancel_requested"] = True
    state["stage_message"] = "任务已取消，已完成结果予以保留。"
    save_state(state)
    pid = state.get("pid")
    server_pid = state.get("server_pid")
    for candidate in (pid, server_pid):
        if not isinstance(candidate, int):
            continue
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(candidate, signal.SIGTERM)
    state["status"] = "cancelled"
    save_state(state)
    return state


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="localocr", description="本地古籍识别任务工具")
    sub = root.add_subparsers(dest="command", required=True)
    doctor_cmd = sub.add_parser("doctor")
    doctor_cmd.add_argument("--json", action="store_true")
    sub.add_parser("setup-runtime")
    sub.add_parser("setup-models")
    submit_cmd = sub.add_parser("submit")
    submit_cmd.add_argument("input")
    submit_cmd.add_argument("--profile", choices=("modern", "complex", "ancient"), default="ancient")
    submit_cmd.add_argument("--output", required=True)
    submit_cmd.add_argument("--start", action="store_true")
    submit_cmd.add_argument("--json", action="store_true")
    status_cmd = sub.add_parser("status")
    status_cmd.add_argument("job_id")
    status_cmd.add_argument("--json", action="store_true")
    cancel_cmd = sub.add_parser("cancel")
    cancel_cmd.add_argument("job_id")
    cancel_cmd.add_argument("--json", action="store_true")
    run_cmd = sub.add_parser("run")
    run_cmd.add_argument("job_id")
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "doctor":
            report = doctor()
            emit(report if args.json else report["summary"], args.json)
        elif args.command == "setup-runtime":
            setup_runtime()
        elif args.command == "setup-models":
            setup_models()
        elif args.command == "submit":
            emit(submit(args.input, args.profile, args.output, args.start), args.json)
        elif args.command == "status":
            emit(load_state(args.job_id), args.json)
        elif args.command == "cancel":
            emit(cancel(args.job_id), args.json)
        elif args.command == "run":
            run_job(args.job_id)
        return 0
    except Exception as exc:
        emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
