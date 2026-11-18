#!/bin/bash
set -euo pipefail
binary="$(mktemp /tmp/vectorpaddle-smoke.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc Sources/PaddleEngine.swift Sources/TableTennisEngine.swift Tests/EngineSmoke.swift -o "$binary"
"$binary"
