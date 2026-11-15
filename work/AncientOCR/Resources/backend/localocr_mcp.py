#!/usr/bin/env python3
"""Minimal local STDIO MCP bridge for AncientOCR.

Tool responses intentionally contain job metadata and paths, never OCR text.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


CLI = Path(__file__).resolve().parents[1] / "bin" / "localocr"


TOOLS = [
    {
        "name": "ocr_health",
        "description": "Check whether the local AncientOCR runtime and models are ready.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "ocr_submit",
        "description": "Submit a local PDF or image OCR job. Returns metadata only, never OCR text.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "input_path": {"type": "string"},
                "output_path": {"type": "string"},
                "profile": {"type": "string", "enum": ["modern", "complex", "ancient"]},
            },
            "required": ["input_path", "output_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ocr_status",
        "description": "Read progress, failures and output path for a local OCR job.",
        "inputSchema": {
            "type": "object",
            "properties": {"job_id": {"type": "string"}},
            "required": ["job_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ocr_cancel",
        "description": "Cancel a running local OCR job without deleting its saved progress.",
        "inputSchema": {
            "type": "object",
            "properties": {"job_id": {"type": "string"}},
            "required": ["job_id"],
            "additionalProperties": False,
        },
    },
]


def invoke(arguments: list[str]) -> tuple[int, str]:
    process = subprocess.run(
        [str(CLI), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return process.returncode, process.stdout.strip()


def tool_call(name: str, args: dict[str, Any]) -> tuple[bool, str]:
    if name == "ocr_health":
        code, output = invoke(["doctor", "--json"])
    elif name == "ocr_submit":
        code, output = invoke([
            "submit", args["input_path"],
            "--output", args["output_path"],
            "--profile", args.get("profile", "ancient"),
            "--start", "--json",
        ])
    elif name == "ocr_status":
        code, output = invoke(["status", args["job_id"], "--json"])
    elif name == "ocr_cancel":
        code, output = invoke(["cancel", args["job_id"], "--json"])
    else:
        return False, json.dumps({"error": f"Unknown tool: {name}"})
    return code == 0, output


def response(request_id: Any, result: Any = None, error: Any = None) -> None:
    payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id}
    if error is not None:
        payload["error"] = error
    else:
        payload["result"] = result
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def handle(message: dict[str, Any]) -> None:
    method = message.get("method")
    request_id = message.get("id")
    if method == "initialize":
        response(request_id, {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "ancientocr-local", "version": "1.0"},
        })
    elif method == "ping":
        response(request_id, {})
    elif method == "tools/list":
        response(request_id, {"tools": TOOLS})
    elif method == "tools/call":
        params = message.get("params") or {}
        ok, output = tool_call(params.get("name", ""), params.get("arguments") or {})
        response(request_id, {
            "content": [{"type": "text", "text": output}],
            "isError": not ok,
        })
    elif request_id is not None:
        response(request_id, error={"code": -32601, "message": f"Method not found: {method}"})


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            handle(json.loads(line))
        except Exception as exc:
            response(None, error={"code": -32603, "message": str(exc)})


if __name__ == "__main__":
    main()
