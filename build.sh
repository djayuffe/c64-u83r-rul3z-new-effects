#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 tools/static_audit.py
mkdir -p build
acme -f cbm -o build/megademo.prg src/megademo.s
cp build/megademo.prg ./megademo.prg
echo "Built build/megademo.prg and ./megademo.prg"
