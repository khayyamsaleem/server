#!/bin/bash
# Dynamic MOTD for cherryblossom — shows ASCII art + Docker container health
[[ -z "$SSH_CONNECTION" ]] && return 2>/dev/null || true

E=$'\033'

cat << ART

${E}[38;5;95m                  │${E}[0m
${E}[38;5;95m                ╲ │${E}[0m
${E}[38;5;95m                 ╲│${E}[0m
${E}[38;5;95m              ────┤${E}[0m
${E}[38;5;95m             ╱    │╲${E}[0m
${E}[38;5;175m          ▄▀▀▄${E}[38;5;95m ╱ │ ${E}[38;5;175m▄▀▀▄${E}[0m
${E}[38;5;218m         █${E}[38;5;224m▓▓▓▓${E}[38;5;218m█${E}[38;5;95m  │${E}[38;5;218m█${E}[38;5;224m▓▓▓▓${E}[38;5;218m█${E}[0m        ${E}[1;38;5;218m      ╱╲${E}[0m
${E}[38;5;218m         █${E}[38;5;224m▓▓${E}[38;5;214m██${E}[38;5;218m█${E}[38;5;95m  │${E}[38;5;218m█${E}[38;5;224m▓▓${E}[38;5;214m██${E}[38;5;218m█${E}[0m       ${E}[1;38;5;218m  ╱──╱  ╲──╲${E}[0m
${E}[38;5;218m          ▀██▀ ${E}[38;5;95m │${E}[38;5;218m ▀██▀${E}[0m        ${E}[1;38;5;175mcherryblossom${E}[0m
${E}[38;5;95m              ╲  │${E}[0m
${E}[38;5;95m          ─────┬─┘${E}[0m
${E}[38;5;95m          ╱    │${E}[0m              ${E}[38;5;245mArch Linux (Manjaro)${E}[0m
${E}[38;5;175m       ▄▀▀▄${E}[38;5;95m ╱ │${E}[0m
${E}[38;5;218m      █${E}[38;5;224m▓▓▓▓${E}[38;5;218m█${E}[38;5;95m  │${E}[0m
${E}[38;5;218m      █${E}[38;5;224m▓▓${E}[38;5;214m██${E}[38;5;218m█${E}[38;5;95m  │${E}[0m
${E}[38;5;218m       ▀██▀ ${E}[38;5;95m │${E}[0m
${E}[38;5;95m             │${E}[0m

ART

docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.State}}' 2>/dev/null | sort | while IFS=$'\t' read -r name cstatus state; do
    n="${name#cherryblossom-}"; n="${n%-1}"
    if [ "$state" = "running" ]; then
        case "$cstatus" in
            *unhealthy*) dot="\033[38;5;196m●\033[0m" ;;
            *starting*)  dot="\033[38;5;214m●\033[0m" ;;
            *)           dot="\033[38;5;34m●\033[0m" ;;
        esac
    else
        dot="\033[38;5;196m○\033[0m"
    fi
    printf "  %b %s" "$dot" "$n"
done
echo ""
echo ""
