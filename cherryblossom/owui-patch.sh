#!/bin/bash
# Patches Open WebUI on container start. Idempotent.

MIDDLEWARE="/app/backend/open_webui/utils/middleware.py"
TASKS="/app/backend/open_webui/routers/tasks.py"

# --- Patch 1: Forward model/negative_prompt from task model to Forge ---
MARKER1="# PATCHED: forward model+negative_prompt from task model"
if ! grep -q "$MARKER1" "$MIDDLEWARE" 2>/dev/null; then
python3 -c "
with open('$MIDDLEWARE', 'r') as f: content = f.read()
old = \"CreateImageForm(**{'prompt': prompt})\"
new = '''CreateImageForm(  $MARKER1
                        **({k: v for k, v in response.items() if k in ('prompt', 'model', 'negative_prompt', 'size', 'steps')}
                           if isinstance(response, dict) else {'prompt': prompt})
                    )'''
if old in content:
    content = content.replace(old, new)
    with open('$MIDDLEWARE', 'w') as f: f.write(content)
    print('[patch] middleware: model+negative_prompt forwarding enabled')
else:
    print('[patch] middleware: target not found, skipping')
"
else
    echo "[patch] middleware: already patched"
fi

# --- Patch 2: Set max_tokens for image prompt generation ---
MARKER2="max_tokens"
if ! grep -q "$MARKER2" <(sed -n '/generate_image_prompt/,/^async def/p' "$TASKS") 2>/dev/null; then
python3 -c "
with open('$TASKS', 'r') as f: content = f.read()
idx = content.index('generate_image_prompt')
before = content[:idx]
after = content[idx:]
old = \"            'stream': False,\"
new = \"            'stream': False,\n            'max_tokens': 500,\"
after = after.replace(old, new, 1)
content = before + after
with open('$TASKS', 'w') as f: f.write(content)
print('[patch] tasks: max_tokens=500 for image prompt generation')
"
else
    echo "[patch] tasks: already patched"
fi
