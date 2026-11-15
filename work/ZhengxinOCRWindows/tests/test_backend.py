"""Integration tests for data safety and native-text fast path; no model downloads."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
TEMP = tempfile.TemporaryDirectory()
os.environ["ZHENGXIN_OCR_SUPPORT"] = TEMP.name
sys.path.insert(0, str(PROJECT / "backend"))
import windows_backend as backend
import core


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        backend.ROOT = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"ZHENGXIN_OCR_SUPPORT": self.temp.name})
        self.env.start(); self.addCleanup(self.env.stop)
        core.APP_SUPPORT = backend.ROOT
        core.JOBS_DIR = backend.ROOT / "jobs"
        core.LOGS_DIR = backend.ROOT / "logs"
        core.MODELS_DIR = backend.ROOT / "models"
        core.ensure_dirs()

    def ready(self, mode="modern"):
        model = backend.ROOT / "models" / "paddlex" / "weight.bin"
        model.parent.mkdir(parents=True, exist_ok=True)
        model.write_bytes(b"test model")
        core.atomic_json(backend.ROOT / "models" / f"{mode}.json", {
            "ready": True, "config_hash": backend.config_hash(),
            "files": [{"path": "paddlex/weight.bin", "size": model.stat().st_size, "sha256": core.sha256(model)}]})
        return model

    def test_model_corruption_and_missing(self):
        model = self.ready()
        report = backend.capabilities()["modern"]
        self.assertTrue(report["ready"])
        model.write_bytes(b"bad! model")  # same size: full hash check must catch corruption
        self.assertFalse(backend.inventory_valid(report, full=True))
        model.unlink()
        self.assertFalse(backend.capabilities()["modern"]["ready"])

    def test_invalid_model_manifest_path(self):
        self.assertFalse(backend.inventory_valid({"files": [{"path": "../../escape", "size": 1}]}))

    def test_damaged_model_is_removed_before_repair(self):
        model = self.ready()
        model.write_bytes(b"damaged")
        class Result:
            def save_to_json(self, directory):
                Path(directory, "result.json").write_text('{"rec_texts":["TEST"]}')
        class Pipeline:
            def predict(self, sample):
                self.assert_removed()
                model.write_bytes(b"repaired model")
                return [Result()]
            def assert_removed(self):
                if model.exists():
                    raise AssertionError("damaged model must be removed before pipeline loads")
        with patch.object(backend, "create_pipeline", return_value=(Pipeline(), False, None)):
            backend.prepare_mode("modern")
        self.assertTrue(backend.capabilities()["modern"]["ready"])
        self.assertEqual(model.read_bytes(), b"repaired model")

    def test_mode_not_ready_rejects_submit(self):
        with self.assertRaisesRegex(RuntimeError, "自检"):
            backend.submit("test.pdf", "ancient", str(backend.ROOT / "out"), False)

    def test_job_id_cannot_escape_directory(self):
        with self.assertRaises(ValueError):
            backend.load_state("../../runtime")

    def test_pid_reuse_never_matches(self):
        self.assertIsNone(backend.process_matches({"pid": os.getpid(), "process_created": 1, "job_id": "fake"}))

    def test_separate_output_directories(self):
        self.ready()
        source = backend.ROOT / "book.pdf"
        source.write_bytes(b"placeholder")
        first = backend.submit(str(source), "modern", str(backend.ROOT / "out"), False)
        first["status"] = "completed"; core.save_state(first)
        second = backend.submit(str(source), "modern", str(backend.ROOT / "out"), False)
        self.assertNotEqual(first["output"], second["output"])

    def test_cancellation_flag_is_not_lost(self):
        job = {"job_id": "ocr_20261030_123456_abcdef", "status": "recognizing"}
        core.save_state(job)
        old = dict(job)
        job.update(cancel_requested=True, status="cancelled"); core.save_state(job)
        core.save_state(old)
        self.assertEqual(core.load_state(job["job_id"])["status"], "cancelled")

    def test_native_pdf_without_models(self):
        import pymupdf
        document = pymupdf.open()
        page = document.new_page()
        page.insert_textbox((40, 40, 550, 700), "Visible text is extracted without loading OCR models. " * 10)
        self.assertIsNotNone(core.native_text_result(page))
        hidden = document.new_page()
        hidden.insert_textbox((40, 40, 550, 700), "Hidden text must never take the native path. " * 10, render_mode=3)
        self.assertIsNone(core.native_text_result(hidden))
        source = backend.ROOT / "native.pdf"
        document.select([0]); document.save(source); document.close()
        self.ready()
        state = backend.submit(str(source), "modern", str(backend.ROOT / "out"), False)
        previous = Path.cwd()
        try:
            with patch.object(core, "create_pipeline", side_effect=AssertionError("OCR must remain unloaded")):
                core.run_job(state["job_id"])
        finally:
            os.chdir(previous)
        result = core.load_state(state["job_id"])
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["rendered_pages"], 0)
        self.assertEqual(result["recognized_pages"], 1)
        performance = json.loads((Path(result["output"]) / "performance.json").read_text())
        self.assertEqual(performance["native_text_pages"], 1)
        self.assertTrue((Path(result["output"]) / "document.txt").exists())

    def test_cancel_only_owned_process(self):
        import psutil
        job_id = "ocr_20261030_123456_123abc"
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", "windows_backend.py", "run", job_id])
        try:
            state = {"job_id": job_id, "status": "recognizing", "pid": process.pid,
                     "process_created": psutil.Process(process.pid).create_time()}
            core.save_state(state)
            result = backend.cancel(job_id)
            self.assertEqual(result["status"], "cancelled")
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill(); process.wait()

    def test_windows_pipelines_never_take_intel_mac_or_mlx_path(self):
        calls = []
        def factory(**kwargs):
            calls.append(kwargs); return object()
        fake = types.SimpleNamespace(PaddleOCR=factory, PPStructureV3=factory, PaddleOCRVL=factory)
        with patch.dict(sys.modules, {"paddleocr": fake}):
            for mode in backend.MODES:
                backend.create_pipeline(mode)
        self.assertEqual(calls[0]["ocr_version"], "PP-OCRv6")
        self.assertEqual(calls[0]["text_det_limit_side_len"], 1920)
        self.assertFalse(calls[0]["use_doc_unwarping"])
        self.assertEqual(calls[2]["vl_rec_backend"], "native")

    def test_detached_worker_start_and_state_reconciliation(self):
        import pymupdf
        document = pymupdf.open(); page = document.new_page()
        page.insert_textbox((40, 40, 550, 700), "Native text survives independent worker execution. " * 10)
        source = backend.ROOT / "worker.pdf"; document.save(source); document.close()
        self.ready()
        state = backend.submit(str(source), "modern", str(backend.ROOT / "out"), True)
        for _ in range(100):
            state = core.load_state(state["job_id"])
            if state["status"] in backend.TERMINAL:
                break
            time.sleep(0.1)
        self.assertEqual(state["status"], "completed")
        self.assertEqual(state["recognized_pages"], 1)

    def test_mcp_stdout_is_jsonrpc(self):
        request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
        result = subprocess.run([sys.executable, str(PROJECT / "backend/mcp.py")], input=json.dumps(request) + "\n",
                                capture_output=True, text=True, check=True)
        response = json.loads(result.stdout)
        self.assertEqual(response["id"], 1)
        self.assertIn("serverInfo", response["result"])


if __name__ == "__main__":
    unittest.main()
