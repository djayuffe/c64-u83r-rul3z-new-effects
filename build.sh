#!/usr/bin/env bash
# Copyright (C) 2026 Ulf Bertilsson
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
cd "$(dirname "$0")"
exec make "$@"
