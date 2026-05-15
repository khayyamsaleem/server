#!/usr/bin/env python3
"""
LLM Benchmark Suite — code, math, writing, tool calls
Runs against all loaded models via the Ollama Envoy gateway.
"""

import json
import re
import sys
import time
from dataclasses import dataclass
from typing import Optional

import requests

GATEWAY = "http://localhost:11435"

MODELS = [
    "qwen3.5:27b-q4_K_M",
    "qwen2.5-coder-8k:latest",
    "devstral-small-2:24b",
    "mdq100/Gemma3-Instruct-Abliterated:12b",
    "qwen3-coder:30b-a3b-q4_K_M",
    "igorls/gemma-4-E4B-it-heretic-GGUF:latest",
    "qwen3:30b-a3b",
    "gemma4:26b",
    "laguna-xs.2:q4_K_M",
]

# ── Benchmarks ─────────────────────────────────────────────────────────────

BENCHMARKS = {
    "code": {
        "prompt": (
            "Write a Python function `sieve(n: int) -> list[int]` that returns all "
            "prime numbers up to n using the Sieve of Eratosthenes. Include a one-line "
            "docstring. Return ONLY the code block, no explanation outside it."
        ),
        "options": {"num_predict": 2048, "num_ctx": 15000, "temperature": 0, "think": False},
    },
    "math": {
        "prompt": (
            "A train travels from city A to city B at 60 mph, then returns at 40 mph. "
            "What is the average speed for the entire round trip? "
            "Show your reasoning step by step and state the final numeric answer clearly."
        ),
        "options": {"num_predict": 2048, "num_ctx": 15000, "temperature": 0, "think": False},
    },
    "writing": {
        "prompt": (
            "In exactly 2-3 paragraphs, explain how the Linux kernel's Completely Fair "
            "Scheduler (CFS) uses a red-black tree and virtual runtime (vruntime) to "
            "allocate CPU time. Write for a senior software engineer who knows data "
            "structures but has never studied OS scheduling."
        ),
        "options": {"num_predict": 2048, "num_ctx": 15000, "temperature": 0, "think": False},
    },
    "tools": {
        "prompt": "What is the current weather in Tokyo? Use the get_weather tool.",
        "options": {"num_predict": 512, "num_ctx": 15000, "temperature": 0, "think": False},
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get current weather for a city",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "city": {
                                "type": "string",
                                "description": "City name",
                            },
                            "units": {
                                "type": "string",
                                "enum": ["celsius", "fahrenheit"],
                                "description": "Temperature units",
                            },
                        },
                        "required": ["city"],
                    },
                },
            }
        ],
    },
}

# ── Scoring ─────────────────────────────────────────────────────────────────

def score_code(response: str) -> tuple[int, str]:
    """Extract and execute sieve. Score 0-100."""
    code = response
    m = re.search(r"```(?:python)?\n(.*?)```", response, re.DOTALL)
    if m:
        code = m.group(1)

    if "def sieve" not in code:
        return 0, "no sieve function defined"

    try:
        ns: dict = {}
        exec(compile(code, "<bench>", "exec"), ns)
        fn = ns.get("sieve")
        if not callable(fn):
            return 10, "sieve defined but not callable"

        checks = [
            (fn(10), [2, 3, 5, 7], "sieve(10)"),
            (fn(2),  [2],           "sieve(2)"),
            (fn(1),  [],            "sieve(1)"),
        ]
        for got, want, label in checks:
            if got != want:
                return 40, f"wrong: {label}={got!r} want {want!r}"

        if len(fn(100)) != 25:
            return 60, f"sieve(100) len={len(fn(100))} want 25"

        return 100, "all correctness checks passed"
    except AssertionError as e:
        return 40, f"assertion: {e}"
    except SyntaxError as e:
        return 5, f"syntax error: {e}"
    except Exception as e:
        return 20, f"exec error: {e}"


def score_math(response: str) -> tuple[int, str]:
    """Correct answer: 48 mph (harmonic mean). Score 0-100."""
    text = response.lower()

    if re.search(r"\b48\b", text):
        if any(k in text for k in ["48 mph", "= 48", "is 48", "answer is 48", "average speed is 48"]):
            return 100, "correct: 48 mph"
        return 80, "48 present; likely correct but not explicit"

    if re.search(r"\b50\b", text) and "average" in text:
        return 0, "wrong: arithmetic mean 50 mph (common mistake)"

    return 0, "correct answer (48 mph) not found"


def score_writing(response: str) -> tuple[int, str]:
    """Score CFS explanation by concept coverage. Score 0-100."""
    text = response.lower()
    concepts = {
        "red-black tree":   ["red-black", "rbtree", "rb tree", "red black"],
        "vruntime":         ["vruntime", "virtual runtime", "virtual run time"],
        "fairness":         ["fair", "fairness"],
        "scheduling":       ["schedul"],
        "weight/priority":  ["weight", "priority", "nice value", "nice level"],
        "time slice":       ["time slice", "timeslice", "quantum", "cpu time"],
    }
    found, missing = [], []
    for concept, terms in concepts.items():
        if any(t in text for t in terms):
            found.append(concept)
        else:
            missing.append(concept)

    score = int(len(found) / len(concepts) * 100)
    detail = f"hit {len(found)}/{len(concepts)}: {found}"
    if missing:
        detail += f" | missed: {missing}"
    return score, detail


def score_tools(data: dict) -> tuple[int, str]:
    """Check get_weather tool call with Tokyo. Score 0-100."""
    msg = data.get("message", {})
    tool_calls = msg.get("tool_calls") or []

    if not tool_calls:
        content = (msg.get("content") or "").lower()
        if "get_weather" in content or "tokyo" in content:
            return 30, "mentioned tool/Tokyo in text but did not invoke"
        return 0, "no tool call, no mention of Tokyo"

    call = tool_calls[0]
    fn = call.get("function", {})
    name = fn.get("name", "")
    args = fn.get("arguments", {})
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            args = {}

    if name != "get_weather":
        return 20, f"called wrong tool: {name!r}"

    city = str(args.get("city", "")).lower()
    if "tokyo" in city:
        return 100, f"correct: get_weather(city={args.get('city')!r})"
    return 50, f"called get_weather but city={args.get('city')!r}"


# ── Runner ──────────────────────────────────────────────────────────────────

@dataclass
class Result:
    model: str
    category: str
    score: int
    detail: str
    tps: float
    elapsed: float
    error: Optional[str] = None


def run_one(model: str, category: str, bench: dict) -> Result:
    payload: dict = {
        "model": model,
        "stream": False,
        "options": bench.get("options", {}),
        "messages": [{"role": "user", "content": bench["prompt"]}],
    }
    if "tools" in bench:
        payload["tools"] = bench["tools"]

    t0 = time.time()
    try:
        resp = requests.post(f"{GATEWAY}/api/chat", json=payload, timeout=300)
        elapsed = time.time() - t0
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        return Result(model, category, 0, "", 0.0, time.time() - t0, error=str(e))

    eval_count = data.get("eval_count", 0)
    eval_ns    = data.get("eval_duration", 0)
    tps = eval_count / (eval_ns / 1e9) if eval_ns > 0 else 0.0

    content = (data.get("message") or {}).get("content") or ""

    if category == "code":
        score, detail = score_code(content)
    elif category == "math":
        score, detail = score_math(content)
    elif category == "writing":
        score, detail = score_writing(content)
    elif category == "tools":
        score, detail = score_tools(data)
    else:
        score, detail = 0, "unknown category"

    return Result(model, category, score, detail, tps, elapsed)


# ── Main ────────────────────────────────────────────────────────────────────

def short(model: str, width: int = 30) -> str:
    name = model.split("/")[-1]
    return name[:width] if len(name) <= width else name[:width - 1] + "…"


def main() -> None:
    cats = ["code", "math", "writing", "tools"]

    try:
        r = requests.get(f"{GATEWAY}/api/tags", timeout=10)
        available = {m["name"] for m in r.json().get("models", [])}
    except Exception as e:
        print(f"[warn] could not fetch model list: {e}; running all")
        available = set(MODELS)

    active  = [m for m in MODELS if m in available]
    skipped = [m for m in MODELS if m not in available]

    if skipped:
        print(f"Skipping (not yet pulled): {skipped}\n")

    print(f"Benchmarking {len(active)} models × {len(cats)} categories\n")

    results: list[Result] = []

    for model in active:
        print(f"{'─'*62}")
        print(f"  {model}")
        print(f"{'─'*62}")
        for cat in cats:
            print(f"  [{cat:<7}] ", end="", flush=True)
            res = run_one(model, cat, BENCHMARKS[cat])
            results.append(res)
            if res.error:
                print(f"ERROR — {res.error}")
            else:
                print(f"score={res.score:3d}  {res.tps:5.1f} t/s  ({res.elapsed:.0f}s)")
                print(f"           {res.detail}")
        print()

    # ── Summary table ─────────────────────────────────────────────────────
    W = 32
    print(f"\n{'═'*80}")
    print("  RESULTS")
    print(f"{'═'*80}")
    hdr = f"  {'Model':<{W}} {'Code':>5} {'Math':>5} {'Write':>6} {'Tools':>6} {'Avg':>5}  {'TPS':>7}"
    print(hdr)
    print(f"  {'─'*78}")

    model_avgs: dict[str, float] = {}
    for model in active:
        mres = [r for r in results if r.model == model and not r.error]
        if not mres:
            continue
        sc = {r.category: r.score for r in mres}
        avg_tps   = sum(r.tps for r in mres if r.tps) / max(1, sum(1 for r in mres if r.tps))
        avg_score = sum(sc.values()) / len(sc)
        model_avgs[model] = avg_score

        print(
            f"  {short(model, W):<{W}} "
            f"{sc.get('code',   0):>5} "
            f"{sc.get('math',   0):>5} "
            f"{sc.get('writing',0):>6} "
            f"{sc.get('tools',  0):>6} "
            f"{avg_score:>5.0f}  "
            f"{avg_tps:>6.1f}t/s"
        )

    # ── Recommendations ───────────────────────────────────────────────────
    print(f"\n{'═'*80}")
    print("  RECOMMENDATIONS")
    print(f"{'═'*80}")

    ranked = sorted(model_avgs.items(), key=lambda x: x[1], reverse=True)
    for rank, (model, avg) in enumerate(ranked, 1):
        mres    = [r for r in results if r.model == model and not r.error]
        avg_tps = sum(r.tps for r in mres if r.tps) / max(1, sum(1 for r in mres if r.tps))
        tag     = "✓ KEEP" if avg >= 60 else ("~ MARGINAL" if avg >= 35 else "✗ DROP")
        print(f"  {rank}. {short(model, W):<{W}}  avg={avg:>5.0f}  {avg_tps:>5.1f}t/s  {tag}")

    print()


if __name__ == "__main__":
    main()
