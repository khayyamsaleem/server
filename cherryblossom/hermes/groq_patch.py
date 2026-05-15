"""Patch hermes-agent to work with Groq's strict OpenAI-compatible endpoint.

Upstream issues: #11089 (reasoning_content rejected), #11237 (think=False bug),
#20577 (reasoning_content cross-provider leak). This patch:

1. Bails out of _copy_reasoning_content_for_api when base_url is Groq.
2. Strips _empty_recovery_synthetic from outgoing API messages (two locations).
3. Wraps _build_api_kwargs so tool schemas served to Groq mark all non-required
   string/number properties as nullable, preventing "expected string, got null"
   validation errors when models pass null for omitted optional params.
"""
import pathlib
import sys

p = pathlib.Path('/opt/hermes/run_agent.py')
src = p.read_text()

old1 = (
    '    def _copy_reasoning_content_for_api(self, source_msg: dict, api_msg: dict) -> None:\n'
    '        """Copy provider-facing reasoning fields onto an API replay message."""\n'
    '        if source_msg.get("role") != "assistant":\n'
    '            return\n'
)
new1 = (
    '    def _copy_reasoning_content_for_api(self, source_msg: dict, api_msg: dict) -> None:\n'
    '        """Copy provider-facing reasoning fields onto an API replay message."""\n'
    '        if source_msg.get("role") != "assistant":\n'
    '            return\n'
    '        _bu = getattr(self, "base_url", None) or ""\n'
    '        if "api.groq.com" in _bu.lower():\n'
    '            api_msg.pop("reasoning_content", None)\n'
    '            return\n'
)
assert old1 in src, "patch1 target not found"
src = src.replace(old1, new1, 1)

old2a = (
    '                for internal_field in ("reasoning", "finish_reason", "_thinking_prefill"):\n'
    '                    api_msg.pop(internal_field, None)\n'
)
new2a = (
    '                for internal_field in ("reasoning", "finish_reason", "_thinking_prefill", "_empty_recovery_synthetic"):\n'
    '                    api_msg.pop(internal_field, None)\n'
)
assert old2a in src, "patch2a target not found"
src = src.replace(old2a, new2a, 1)

old2b = (
    '                # Strip internal thinking-prefill marker\n'
    '                api_msg.pop("_thinking_prefill", None)\n'
)
new2b = (
    '                # Strip internal thinking-prefill marker\n'
    '                api_msg.pop("_thinking_prefill", None)\n'
    '                # Strip empty-response recovery marker (rejected by strict providers like Groq)\n'
    '                api_msg.pop("_empty_recovery_synthetic", None)\n'
)
assert old2b in src, "patch2b target not found"
src = src.replace(old2b, new2b, 1)

old3 = (
    '    def _build_api_kwargs(self, api_messages: list) -> dict:\n'
    '        """Build the keyword arguments dict for the active API mode."""\n'
    '        tools_for_api = self.tools\n'
)
new3 = (
    '    def _build_api_kwargs(self, api_messages: list) -> dict:\n'
    '        """Build the keyword arguments dict for the active API mode."""\n'
    '        tools_for_api = self.tools\n'
    '        # Groq compat: mark non-required scalar properties as nullable so models\n'
    '        # that pass {"foo": null} for omitted optional params dont fail validation.\n'
    '        _bu_lower = (getattr(self, "base_url", None) or "").lower()\n'
    '        if "api.groq.com" in _bu_lower and tools_for_api:\n'
    '            import copy as _copy\n'
    '            def _allow_null(schema):\n'
    '                if not isinstance(schema, dict):\n'
    '                    return\n'
    '                params = schema.get("parameters") if "parameters" in schema else schema\n'
    '                if isinstance(params, dict) and isinstance(params.get("function"), dict):\n'
    '                    _allow_null(params["function"])\n'
    '                    return\n'
    '                if isinstance(params, dict):\n'
    '                    props = params.get("properties") or {}\n'
    '                    required = set(params.get("required") or [])\n'
    '                    for pname, pspec in props.items():\n'
    '                        if pname in required or not isinstance(pspec, dict):\n'
    '                            continue\n'
    '                        t = pspec.get("type")\n'
    '                        if isinstance(t, str) and t != "null":\n'
    '                            pspec["type"] = [t, "null"]\n'
    '            tools_for_api = _copy.deepcopy(tools_for_api)\n'
    '            for _t in tools_for_api:\n'
    '                _allow_null(_t)\n'
    '                if isinstance(_t, dict) and isinstance(_t.get("function"), dict):\n'
    '                    _allow_null(_t["function"])\n'
)
assert old3 in src, "patch3 target not found"
src = src.replace(old3, new3, 1)

p.write_text(src)
print("groq-compat patch applied")
