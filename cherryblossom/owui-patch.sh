#!/bin/bash
# Patches Open WebUI on container start. Idempotent.

MIDDLEWARE="/app/backend/open_webui/utils/middleware.py"

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

# --- Patch 2: Run native generate_image through the image prompt template ---
# With native function calling the builtin generate_image tool sends only the
# chat model's free-text prompt, skipping IMAGE_PROMPT_GENERATION_PROMPT_TEMPLATE:
# no checkpoint choice, no Pony tags, no negative prompt. Route the tool prompt
# through the template on the task model (thinking off, ~2s) and forward
# prompt/model/negative_prompt. Falls back to the plain prompt on any error.
BUILTIN="/app/backend/open_webui/tools/builtin.py"
MARKER2="# PATCHED: image prompt template for native generate_image"
if ! grep -q "$MARKER2" "$BUILTIN" 2>/dev/null; then
python3 -c "
with open('$BUILTIN', 'r') as f: content = f.read()
old = 'form_data=CreateImageForm(prompt=prompt),'
new = 'form_data=CreateImageForm(**(await _templated_image_form(user, prompt, __chat_id__))),'
if content.count(old) != 1:
    print('[patch] builtin: target not found, skipping')
    raise SystemExit
content = content.replace(old, new)
content += '''

async def _templated_image_form(user, prompt, chat_id):  $MARKER2
    form = {'prompt': prompt}
    try:
        if not await Config.get('image_generation.prompt.enable'):
            return form
        # Import locally: upstream reshuffles module-level imports between
        # releases (0.11.4 dropped the module-level json import from builtin.py).
        import json
        import os
        import aiohttp
        from open_webui.utils.task import image_prompt_generation_template

        template = await Config.get('task.image.prompt_template')
        model = await Config.get('task.model.default')
        if not template or not model:
            return form

        # The user's own words plus the chat model's rendering of them.
        messages = []
        if is_saved_chat_id(chat_id):
            chat = await Chats.get_chat_by_id(chat_id)
            history = ((chat.chat or {}).get('history') or {}) if chat else {}
            user_msgs = [m for m in (history.get('messages') or {}).values() if m.get('role') == 'user']
            if user_msgs:
                last = max(user_msgs, key=lambda m: m.get('timestamp') or 0)
                messages.append({'role': 'user', 'content': last.get('content') or ''})
        messages.append({'role': 'user', 'content': f'Image to generate: {prompt}'})
        content = await image_prompt_generation_template(template, messages, user)

        url = os.environ.get('OLLAMA_BASE_URL', 'http://localhost:11434').rstrip('/') + '/api/chat'
        body = {
            'model': model,
            'messages': [{'role': 'user', 'content': content}],
            'stream': False,
            'think': False,
            'options': {'num_predict': 1024},
        }
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=180)) as session:
            async with session.post(url, json=body) as r:
                r.raise_for_status()
                text = (await r.json())['message']['content']

        parsed = json.loads(text[text.find('{'):text.rfind('}') + 1])
        for key in ('prompt', 'model', 'negative_prompt'):
            if isinstance(parsed.get(key), str) and parsed[key].strip():
                form[key] = parsed[key].strip()
        log.info(f'generate_image: template chose model={form.get(\"model\")}')
    except Exception as e:
        log.warning(f'generate_image: prompt template failed, using tool prompt: {e}')
    return form
'''
with open('$BUILTIN', 'w') as f: f.write(content)
print('[patch] builtin: generate_image uses image prompt template')
"
else
    echo "[patch] builtin: already patched"
fi
