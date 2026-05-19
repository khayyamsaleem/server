#!/bin/sh
# Runs via LinuxServer custom-cont-init.d AFTER filesystem setup but BEFORE
# the main process. Forks the configure script in background so it can wait
# for Sonarr's API to come up, then applies idempotent config.
/configure/arr-configure.sh sonarr 8989 "${SONARR_API_KEY}" shows /media/shows &
