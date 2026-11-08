#!/bin/sh
# Keep the application bundle together so the executable's $ORIGIN/lib
# RUNPATH and its data/ directory both resolve correctly.
exec /usr/lib/secrandom-lite/secrandom_lite "$@"
