# Open WebUI with two patches to its image-generation path (see the .patch):
# - middleware: forward model/negative_prompt/size/steps chosen by the task
#   model (via IMAGE_PROMPT_GENERATION_PROMPT_TEMPLATE) on to Forge, instead of
#   only the prompt.
# - builtin generate_image (native function calling): run the chat model's
#   free-text prompt through that same template on the task model, so it also
#   picks the checkpoint, Pony tags and negative prompt. Falls back to the
#   plain prompt on any error.
# Pinned: bumping the tag re-applies the patch, and the build fails loudly if
# upstream moved the code instead of silently shipping unpatched.
FROM ghcr.io/open-webui/open-webui:v0.11.4
COPY image-prompt-template.patch /tmp/
RUN patch -p1 --forward < /tmp/image-prompt-template.patch && rm /tmp/image-prompt-template.patch
