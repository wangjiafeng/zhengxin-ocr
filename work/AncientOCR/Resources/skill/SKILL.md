---
name: local-ocr
description: Use the local AncientOCR macOS app to OCR scanned PDFs, complex layouts, or Chinese ancient books. Submit and monitor local jobs without returning full OCR text to chat.
---

# Local AncientOCR

Use the `local_ocr` MCP tools for local OCR work.

1. Call `ocr_health` before submitting a job.
2. Choose `modern` for regular modern scans, `complex` for tables/formulas/multi-column documents, and `ancient` for vertical Chinese, annotations, rare characters, seals, or damaged pages.
3. `ocr_submit` is asynchronous. Return the job id, then use `ocr_status` when the user asks for progress.
4. Keep OCR text local by default. Report metadata, failed page numbers, and output paths only. Never paste an entire recognized document into chat unless the user explicitly requests that disclosure.
5. Never overwrite the source PDF or manually reviewed output.
6. Cancelling preserves completed pages and logs.
