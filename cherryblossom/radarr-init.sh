#!/bin/sh
# Runs via LinuxServer custom-cont-init.d AFTER filesystem setup but BEFORE
# the main process. Forks the configure script in background so it can wait
# for Radarr's API to come up, then applies idempotent config.
/configure/arr-configure.sh radarr 7878 "${RADARR_API_KEY}" movies /media/movies &
