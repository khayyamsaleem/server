#!/usr/bin/env python3
"""Yield the 3090 from Ollama to Forge for the duration of an image generation.

Called synchronously by the envoy forge_filter around every txt2img/img2img:
  POST /evict    unload whatever Ollama has loaded, wait until it is gone
  POST /restore  reload the evicted model at the same context length, making
                 sure it lands fully on the GPU (Forge may still be releasing
                 VRAM, in which case Ollama would split layers onto the CPU)
  GET  /health

The KV cache is not preserved: llama-server slot save/restore does not
survive Ollama's runner for hybrid (Qwen3.5+/DeltaNet) or mmproj models, so
the next chat turn re-prefills. Stdlib only.
"""
import json, os, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = os.environ.get("OLLAMA", "http://ollama-3090:11434")
PORT = int(os.environ.get("PORT", "11500"))
LOAD_RETRIES = int(os.environ.get("LOAD_RETRIES", "4"))

lock = threading.Lock()
state = {}  # model + ctx of the last eviction awaiting restore


def log(msg, **kw):
    print(json.dumps({"ts": time.strftime("%H:%M:%S"), "msg": msg, **kw}), flush=True)


def call(path, body=None, timeout=300):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(OLLAMA + path, data, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


def loaded():
    return call("/api/ps").get("models", [])


def evict():
    with lock:
        t = time.time()
        models = loaded()
        if not models:
            # Nothing on the GPU; keep any pending restore from an earlier eviction.
            return {"evicted": None, "pending": state.get("model")}
        m = models[0]
        for x in models:
            call("/api/generate", {"model": x["name"], "keep_alive": 0})
        deadline = time.time() + 60
        while loaded() and time.time() < deadline:
            time.sleep(0.25)
        state.clear()
        state.update(model=m["name"], ctx=m.get("context_length"))
        out = {"evicted": m["name"], "ctx": state["ctx"], "ms": round((time.time() - t) * 1000)}
        log("evict", **out)
        return out


def restore():
    with lock:
        if not state.get("model"):
            return {"restored": None}
        model, ctx = state["model"], state["ctx"]
        t = time.time()
        opts = {"num_ctx": ctx} if ctx else {}
        vram_pct = None
        for attempt in range(1, LOAD_RETRIES + 1):
            call("/api/generate", {"model": model, "prompt": "", "options": opts})
            p = next((x for x in loaded() if x["name"] == model), {})
            vram_pct = round(100 * p.get("size_vram", 0) / max(p.get("size", 1), 1), 1)
            if vram_pct >= 99.9 or attempt == LOAD_RETRIES:
                break
            log("partial GPU load, retrying", model=model, vram_pct=vram_pct, attempt=attempt)
            call("/api/generate", {"model": model, "keep_alive": 0})
            time.sleep(3)
        state.clear()
        out = {"restored": model, "ctx": ctx, "vram_pct": vram_pct, "ms": round((time.time() - t) * 1000)}
        log("restore", **out)
        return out


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True, "pending": state.get("model")})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        fn = {"/evict": evict, "/restore": restore}.get(self.path)
        if not fn:
            return self._send(404, {"error": "not found"})
        try:
            self._send(200, fn())
        except Exception as e:
            log("error", path=self.path, error=str(e)[:300])
            self._send(500, {"error": str(e)[:300]})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    log("gpu-yield listening", port=PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
