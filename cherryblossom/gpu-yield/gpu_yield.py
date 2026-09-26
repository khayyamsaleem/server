#!/usr/bin/env python3
"""Arbitrate the 3090 (and host RAM) between Ollama, Forge and ComfyUI.

Forge images (called synchronously by envoy forge_filter around txt2img/img2img):
  POST /evict    unload whatever Ollama has loaded, wait until it is gone.
                 423 while a ComfyUI lease is active (GPU busy with video).
  POST /restore  reload the evicted model at the same context length, making
                 sure it lands fully on the GPU (Forge may still be releasing
                 VRAM, in which case Ollama would split layers onto the CPU).
                 No-op while a ComfyUI lease is active.

ComfyUI video (called by envoy comfy_filter on every prompt submission):
  POST /lease    unload Ollama, restart Forge's worker to release its ~10G of
                 offloaded checkpoints (unload-checkpoint does not free RAM),
                 then require enough host RAM for ComfyUI to reach its measured
                 peak from what it already holds. 507 if RAM stays short,
                 so a job never starts where it could cause a host-wide OOM.
                 A watcher reloads Ollama once ComfyUI's queue has drained.

  GET  /health

The KV cache is not preserved: llama-server slot save/restore does not
survive Ollama's runner for hybrid (Qwen3.5+/DeltaNet) or mmproj models, so
the next chat turn re-prefills. Stdlib only.
"""
import json, os, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = os.environ.get("OLLAMA", "http://ollama-3090:11434")
FORGE = os.environ.get("FORGE", "http://forge:17860")
COMFY = os.environ.get("COMFY", "http://comfyui:8188")
PORT = int(os.environ.get("PORT", "11500"))
LOAD_RETRIES = int(os.environ.get("LOAD_RETRIES", "4"))
# Fallback when ComfyUI cannot report its headroom (17G cap, ~3.3G idle).
MIN_FREE_MIB = int(os.environ.get("MIN_FREE_MIB", "14500"))
# Peak ComfyUI RSS measured for one LTX-2.3 job (12.2-15.4G across i2v/t2v/LoRA runs).
COMFY_PEAK_MIB = int(os.environ.get("COMFY_PEAK_MIB", "15872"))
LEASE_IDLE_SECS = int(os.environ.get("LEASE_IDLE_SECS", "15"))

lock = threading.Lock()
state = {}  # model + ctx of the last eviction awaiting restore
lease = {"active": False, "last": 0.0}


def log(msg, **kw):
    print(json.dumps({"ts": time.strftime("%H:%M:%S"), "msg": msg, **kw}), flush=True)


def call(url, body=None, timeout=300):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


def loaded():
    return call(OLLAMA + "/api/ps").get("models", [])


def mem_available_mib():
    # Containers see the host's /proc/meminfo.
    with open("/proc/meminfo") as f:
        return next(int(l.split()[1]) for l in f if l.startswith("MemAvailable")) // 1024


def _evict():
    t = time.time()
    models = loaded()
    if not models:
        # Nothing on the GPU; keep any pending restore from an earlier eviction.
        return {"evicted": None, "pending": state.get("model")}
    m = models[0]
    for x in models:
        call(OLLAMA + "/api/generate", {"model": x["name"], "keep_alive": 0})
    deadline = time.time() + 60
    while loaded() and time.time() < deadline:
        time.sleep(0.25)
    state.clear()
    state.update(model=m["name"], ctx=m.get("context_length"))
    return {"evicted": m["name"], "ctx": state["ctx"], "ms": round((time.time() - t) * 1000)}


def _restore():
    if not state.get("model"):
        return {"restored": None}
    model, ctx = state["model"], state["ctx"]
    t = time.time()
    opts = {"num_ctx": ctx} if ctx else {}
    vram_pct = None
    for attempt in range(1, LOAD_RETRIES + 1):
        call(OLLAMA + "/api/generate", {"model": model, "prompt": "", "options": opts})
        p = next((x for x in loaded() if x["name"] == model), {})
        vram_pct = round(100 * p.get("size_vram", 0) / max(p.get("size", 1), 1), 1)
        if vram_pct >= 99.9 or attempt == LOAD_RETRIES:
            break
        log("partial GPU load, retrying", model=model, vram_pct=vram_pct, attempt=attempt)
        call(OLLAMA + "/api/generate", {"model": model, "keep_alive": 0})
        time.sleep(3)
    state.clear()
    return {"restored": model, "ctx": ctx, "vram_pct": vram_pct, "ms": round((time.time() - t) * 1000)}


def evict():
    with lock:
        if lease["active"]:
            return 423, {"error": "GPU busy: video generation in progress"}
        out = _evict()
        if out.get("evicted"):
            log("evict", **out)
        return 200, out


def restore():
    with lock:
        if lease["active"]:
            return 200, {"restored": None, "deferred": "video lease active"}
        out = _restore()
        log("restore", **out)
        return 200, out


def required_free_mib():
    """Host RAM a video job still needs: its measured peak minus what ComfyUI
    already holds (system_stats is cgroup-aware), plus a margin. A job that runs
    past its expected peak is stopped by the container cap, and oom_score_adj
    makes ComfyUI the kernel's first choice if the host does run out."""
    try:
        s = call(COMFY + "/system_stats", timeout=10)["system"]
        held = (s["ram_total"] - s["ram_free"]) // 2**20
        return max(COMFY_PEAK_MIB - held, 0) + 512
    except Exception:
        return MIN_FREE_MIB


def _free_forge_ram():
    """Kill Forge's worker; supervisord restarts it empty in ~15s (checkpoints load lazily)."""
    try:
        urllib.request.urlopen(urllib.request.Request(FORGE + "/sdapi/v1/server-kill", b"", method="POST"), timeout=10)
    except Exception:
        pass  # the connection drops when the process exits


def take_lease():
    with lock:
        lease["last"] = time.time()
        if lease["active"]:
            return 200, {"lease": "renewed"}
        t = time.time()
        evicted = _evict()
        _free_forge_ram()
        need = required_free_mib()
        avail = mem_available_mib()
        deadline = time.time() + 30
        while avail < need and time.time() < deadline:
            time.sleep(1)
            avail = mem_available_mib()
        if avail < need:
            restored = _restore()
            log("lease refused", avail_mib=avail, need_mib=need, restored=restored.get("restored"))
            return 507, {"error": f"not enough free RAM for a video job ({avail} MiB < {need} MiB)"}
        lease["active"] = True
        out = {"lease": "granted", "evicted": evicted.get("evicted"), "avail_mib": avail, "ms": round((time.time() - t) * 1000)}
        log("lease", **out)
        threading.Thread(target=watch_comfy, daemon=True).start()
        return 200, out


def watch_comfy():
    """Release the lease once ComfyUI's queue has been empty for LEASE_IDLE_SECS."""
    idle_since = None
    while True:
        time.sleep(5)
        try:
            q = call(COMFY + "/queue", timeout=10)
            busy = bool(q.get("queue_running") or q.get("queue_pending"))
        except Exception:
            busy = False  # ComfyUI gone: nothing is using the GPU
        now = time.time()
        if busy or now - lease["last"] < LEASE_IDLE_SECS:
            idle_since = None
            continue
        idle_since = idle_since or now
        if now - idle_since >= LEASE_IDLE_SECS:
            with lock:
                lease["active"] = False
                out = _restore()
            log("lease released", **out)
            return


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
            return self._send(200, {"ok": True, "pending": state.get("model"), "video_lease": lease["active"]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        fn = {"/evict": evict, "/restore": restore, "/lease": take_lease}.get(self.path)
        if not fn:
            return self._send(404, {"error": "not found"})
        try:
            self._send(*fn())
        except Exception as e:
            log("error", path=self.path, error=str(e)[:300])
            self._send(500, {"error": str(e)[:300]})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    log("gpu-yield listening", port=PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
