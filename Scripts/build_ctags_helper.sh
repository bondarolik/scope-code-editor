#!/bin/sh
# Rebuild Scope/Resources/Tools/ctags from the pinned Universal Ctags 6.2.1 and
# Jansson 2.14 source trees. Build one static slice per architecture, then lipo
# them together. JSON is mandatory; YAML, PCRE2, and iconv are disabled to keep
# the helper self-contained. The app build signs the copied resource.
set -eu
echo "Use the documented pinned third-party sources to produce arm64 and x86_64 slices, then lipo them into Scope/Resources/Tools/ctags."
