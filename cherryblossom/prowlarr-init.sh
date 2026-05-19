#!/bin/sh
# Runs via LinuxServer custom-cont-init.d. Forks configure script in background
# so it can wait for Prowlarr's API, then wires Radarr + Sonarr as applications.
/configure/prowlarr-configure.sh &
