#!/usr/bin/env python3
"""
Fireworks benchmark — code, math, writing, tool calls
Reuses scoring from benchmark.py; uses OpenAI-compatible Fireworks endpoint.
"""

import json, os, re, sys, time
from dataclasses import dataclass
from typing import Optional

import requests

API_BASE = "https://api.fireworks.ai/inference/v1"
API_KEY  = os.environ["FIREWORKS_API_KEY"]

MODELS = [
    "accounts/fireworks/models/deepseek-v4-pro",
    "accounts/fireworks/models/kimi-k2p5",
    "accounts/fireworks/models/kimi-k2p6",
    "accounts/fireworks/models/gpt-oss-120b",   # same as current Groq model — baseline
]

# ── Benchmarks ──────────────────────────────────────────────────────────────

BENCHMARKS = {
    "code": {
        "prompt": (
            "Write a Python function `sieve(n: int) -> list[int]` that returns all "
            "prime numbers up to n using the Sieve of Eratosthenes. Include a one-line "
            "docstring. Return ONLY the code block, no explanation outside it."
        ),
    },
    "math": {
        "prompt": (
            "A train travels from city A to city B at 60 mph, then returns at 40 mph. "
            "What is the average speed for the entire round trip? "
            "Show your reasoning step by step and state the final numeric answer clearly."
        ),
    },
    "writing": {
        "prompt": (
            "In exactly 2-3 paragraphs, explain how the Linux kernel's Completely Fair "
            "Scheduler (CFS) uses a red-black tree and virtual runtime (vruntime) to "
            "allocate CPU time. Write for a senior software engineer who knows data "
            "structures but has never studied OS scheduling."
        ),
    },
    "tools": {
        "prompt": "What is the current weather in Tokyo? Use the get_weather tool.",
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get current weather for a city",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "city":  {"type": "string"},
                            "units": {"type": "string", "enum": ["celsius", "fahrenheit"]},
                        },
                        "required": ["city"],
                    },
                },
            }
        ],
    },
}

# ── Scoring (identical to benchmark.py) ────────────────────────────────────

def score_code(response: str):
    code = response
    m = re.search(r"```(?:python)?\n(.*?)```", response, re.DOTALL)
    if m:
        code = m.group(1)
    if "def sieve" not in code:
        return 0, "no sieve function"
    try:
        ns: dict = {}
        exec(compile(code, "<bench>", "exec"), ns)
        fn = ns.get("sieve")
        if not callable(fn):
            return 10, "not callable"
        for got, want, lbl in [(fn(10),[2,3,5,7],"sieve(10)"),(fn(2),[2],"sieve(2)"),(fn(1),[],"sieve(1)")]:
            if got != want:
                return 40, f"wrong {lbl}={got!r}"
        if len(fn(100)) != 25:
            return 60, f"sieve(100) len={len(fn(100))}"
        return 100, "all checks passed"
    except SyntaxError as e:
        return 5, f"syntax: {e}"
    except Exception as e:
        return 20, f"exec: {e}"

def score_math(response: str):
    text = response.lower()
    if re.search(r"\b48\b", text):
        if any(k in text for k in ["48 mph","= 48","is 48","answer is 48","average speed is 48"]):
            return 100, "correct: 48 mph"
        return 80, "48 present; likely correct"
    if re.search(r"\b50\b", text) and "average" in text:
        return 0, "wrong: 50 mph (arithmetic mean mistake)"
    return 0, "48 mph not found"

def score_writing(response: str):
    text = response.lower()
    concepts = {
        "red-black tree":  ["red-black","rbtree","rb tree","red black"],
        "vruntime":        ["vruntime","virtual runtime","virtual run time"],
        "fairness":        ["fair","fairness"],
        "scheduling":      ["schedul"],
        "weight/priority": ["weight","priority","nice value","nice level"],
        "time slice":      ["time slice","timeslice","quantum","cpu time"],
    }
    found = [c for c,terms in concepts.items() if any(t in text for t in terms)]
    missed = [c for c in concepts if c not in found]
    score = int(len(found)/len(concepts)*100)
    detail = f"hit {len(found)}/{len(concepts)}: {found}"
    if missed:
        detail += f" | missed: {missed}"
    return score, detail

def score_tools(message: dict):
    tool_calls = message.get("tool_calls") or []
    if not tool_calls:
        content = (message.get("content") or "").lower()
        if "get_weather" in content or "tokyo" in content:
            return 30, "mentioned but didn't invoke"
        return 0, "no tool call"
    fn   = tool_calls[0].get("function", {})
    name = fn.get("name","")
    args = fn.get("arguments",{})
    if isinstance(args, str):
        try: args = json.loads(args)
        except: args = {}
    if name != "get_weather":
        return 20, f"wrong tool: {name!r}"
    city = str(args.get("city","")).lower()
    if "tokyo" in city:
        return 100, f"correct: get_weather(city={args.get('city')!r})"
    return 50, f"get_weather but city={args.get('city')!r}"

# ── Runner ──────────────────────────────────────────────────────────────────

@dataclass
class Result:
    model: str
    category: str
    score: int
    detail: str
    elapsed: float
    tokens: int
    error: Optional[str] = None

def run_one(model: str, category: str, bench: dict) -> Result:
    payload = {
        "model": model,
        "temperature": 0,
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": bench["prompt"]}],
    }
    if "tools" in bench:
        payload["tools"] = bench["tools"]
        payload["max_tokens"] = 512

    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    }

    t0 = time.time()
    try:
        r = requests.post(f"{API_BASE}/chat/completions", json=payload, headers=headers, timeout=120)
        elapsed = time.time() - t0
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        return Result(model, category, 0, "", time.time()-t0, 0, error=str(e))

    choice  = data["choices"][0]
    message = choice["message"]
    content = message.get("content") or ""
    tokens  = data.get("usage",{}).get("completion_tokens", 0)

    if category == "code":
        score, detail = score_code(content)
    elif category == "math":
        score, detail = score_math(content)
    elif category == "writing":
        score, detail = score_writing(content)
    elif category == "tools":
        score, detail = score_tools(message)
    else:
        score, detail = 0, "unknown"

    return Result(model, category, score, detail, elapsed, tokens)

# ── Main ────────────────────────────────────────────────────────────────────

def short(model: str, w: int = 30) -> str:
    name = model.split("/")[-1]
    return (name[:w-1]+"…") if len(name) > w else name

def main():
    cats = ["code", "math", "writing", "tools"]
    results: list[Result] = []

    print(f"Benchmarking {len(MODELS)} models on Fireworks × {len(cats)} tasks\n")

    for model in MODELS:
        print(f"{'─'*60}")
        print(f"  {short(model)}")
        print(f"{'─'*60}")
        for cat in cats:
            print(f"  [{cat:<7}] ", end="", flush=True)
            res = run_one(model, cat, BENCHMARKS[cat])
            results.append(res)
            if res.error:
                print(f"ERROR — {res.error}")
            else:
                tps = res.tokens / res.elapsed if res.elapsed else 0
                print(f"score={res.score:3d}  {tps:5.1f} t/s  ({res.elapsed:.1f}s)")
                print(f"           {res.detail}")
        print()

    # Summary
    W = 20
    print(f"\n{'═'*72}")
    print("  RESULTS")
    print(f"{'═'*72}")
    print(f"  {'Model':<{W}} {'Code':>5} {'Math':>5} {'Write':>6} {'Tools':>6} {'Avg':>5}  {'TPS':>7}")
    print(f"  {'─'*70}")

    ranked = []
    for model in MODELS:
        mres = [r for r in results if r.model == model and not r.error]
        if not mres: continue
        sc     = {r.category: r.score for r in mres}
        tps    = sum(r.tokens/r.elapsed for r in mres if r.elapsed) / max(1, len(mres))
        avg    = sum(sc.values()) / len(sc)
        ranked.append((model, avg, tps, sc))
        print(
            f"  {short(model,W):<{W}} "
            f"{sc.get('code',0):>5} {sc.get('math',0):>5} "
            f"{sc.get('writing',0):>6} {sc.get('tools',0):>6} "
            f"{avg:>5.0f}  {tps:>6.1f}t/s"
        )

    ranked.sort(key=lambda x: x[1], reverse=True)
    print(f"\n{'═'*72}")
    print("  RANKING")
    print(f"{'═'*72}")
    for i,(model,avg,tps,_) in enumerate(ranked,1):
        tag = "✓ BEST" if i==1 else ("✓ GOOD" if avg>=70 else ("~ OK" if avg>=50 else "✗ WEAK"))
        print(f"  {i}. {short(model,W):<{W}}  avg={avg:>5.0f}  {tps:>5.1f}t/s  {tag}")
    print()

if __name__ == "__main__":
    main()
