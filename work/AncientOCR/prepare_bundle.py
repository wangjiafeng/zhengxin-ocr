#!/usr/bin/env python3
"""Build the Python dependency and model payload embedded in AncientOCR.app."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
BUNDLE = ROOT / "Bundle"
PYTHON_DIR = BUNDLE / "python"
MODELS_DIR = BUNDLE / "models"
PADDLEX_CACHE = MODELS_DIR / "paddlex"
VL_MODEL_DIR = MODELS_DIR / "PaddleOCR-VL-1.6"

REQUIREMENTS = [
    "paddlepaddle>=3.2.1,<3.3",
    "paddleocr[doc-parser]>=3.7,<3.8",
    "mlx-vlm>=0.3.11",
    "huggingface-hub>=0.29",
    "pymupdf>=1.24",
    "Pillow>=10",
]


def run(command: list[str], env: dict[str, str] | None = None) -> None:
    print("执行：" + " ".join(command), flush=True)
    subprocess.run(command, check=True, env=env)


def main() -> None:
    if sys.version_info[:2] != (3, 13):
        raise SystemExit("构建内置依赖需要 Python 3.13，以匹配目标电脑。")
    if os.uname().machine != "arm64":
        raise SystemExit("只能在 Apple Silicon ARM64 Mac 上构建。")

    PYTHON_DIR.mkdir(parents=True, exist_ok=True)
    PADDLEX_CACHE.mkdir(parents=True, exist_ok=True)
    if not (PYTHON_DIR / "paddle").is_dir() or not (PYTHON_DIR / "paddleocr").is_dir():
        run([
            sys.executable,
            "-m",
            "pip",
            "install",
            "--upgrade",
            "--target",
            str(PYTHON_DIR),
            *REQUIREMENTS,
        ])
    else:
        print("内置 Python 依赖已存在，跳过重复安装。", flush=True)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(PYTHON_DIR)
    env["PADDLE_PDX_CACHE_HOME"] = str(PADDLEX_CACHE)
    env["HF_HOME"] = str(MODELS_DIR / "huggingface-cache")
    env["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    model_script = f"""
print('载入 PaddleOCR 构建工具…', flush=True)
from huggingface_hub import snapshot_download
from paddleocr import PaddleOCR, PPStructureV3, PaddleOCRVL

print('下载 PaddleOCR-VL-1.6 原始模型…', flush=True)
snapshot_download(repo_id='PaddlePaddle/PaddleOCR-VL-1.6', local_dir={str(VL_MODEL_DIR)!r})
print('准备 PP-OCRv6 模型…', flush=True)
PaddleOCR(lang='ch', ocr_version='PP-OCRv6', device='cpu')
print('准备 PP-StructureV3 模型…', flush=True)
PPStructureV3(device='cpu')
print('准备 PaddleOCR-VL 版面模型…', flush=True)
PaddleOCRVL(
    pipeline_version='v1.6',
    device='cpu',
    vl_rec_backend='mlx-vlm-server',
    vl_rec_server_url='http://127.0.0.1:8111/',
    vl_rec_api_model_name={str(VL_MODEL_DIR)!r},
    vl_rec_max_concurrency=1,
)
"""
    run([sys.executable, "-c", model_script], env=env)

    for cache_dir in PYTHON_DIR.rglob("__pycache__"):
        if cache_dir.is_dir():
            shutil.rmtree(cache_dir)

    marker = {
        "prepared_at": int(time.time()),
        "python": sys.version.split()[0],
        "architecture": os.uname().machine,
        "requirements": REQUIREMENTS,
        "vl_model": str(VL_MODEL_DIR.relative_to(BUNDLE)),
    }
    (MODELS_DIR / ".setup-complete").write_text(
        json.dumps(marker, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("内置依赖与模型准备完成。", flush=True)


if __name__ == "__main__":
    main()
