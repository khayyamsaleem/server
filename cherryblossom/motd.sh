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

printf "  \033[1;38;5;218m%-30s %s\033[0m\n" "CONTAINER" "STATUS"
printf "  \033[38;5;240m%-30s %s\033[0m\n" "─────────────────────────────" "──────────"

docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.State}}' 2>/dev/null | sort | while IFS=$'\t' read -r name cstatus state; do
    short_name="${name#cherryblossom-}"
    short_name="${short_name%-1}"
    if [ "$state" = "running" ]; then
        case "$cstatus" in
            *healthy*)   icon="\033[38;5;34m✔ healthy\033[0m" ;;
            *unhealthy*) icon="\033[38;5;196m✘ unhealthy\033[0m" ;;
            *starting*)  icon="\033[38;5;214m⟳ starting\033[0m" ;;
            *)           icon="\033[38;5;34m✔ running\033[0m" ;;
        esac
    else
        icon="\033[38;5;196m✘ ${state}\033[0m"
    fi
    printf "  %-30s %b\n" "$short_name" "$icon"
done

echo ""
