#!/bin/bash
# Persist GitHub credentials for subprocess use.
# Hermes strips GH_TOKEN from all child processes (CVE guard), so we store
# credentials in files that git and gh can read without the env var.
if [ -n "$GH_TOKEN" ]; then
    # git credential store — lets git push/clone without GH_TOKEN in env
    printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > "$HOME/.git-credentials"
    chmod 600 "$HOME/.git-credentials"

    # gh CLI config — lets gh pr create / gh api work without GH_TOKEN in env
    _gh_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gh"
    mkdir -p "$_gh_cfg"
    printf 'github.com:\n    oauth_token: %s\n    git_protocol: https\n    user: khayyamsaleem\n' \
        "$GH_TOKEN" > "$_gh_cfg/hosts.yml"
    chmod 600 "$_gh_cfg/hosts.yml"
fi
exec hermes gateway run
