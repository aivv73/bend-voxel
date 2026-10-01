#!/usr/bin/env bash
exec bash "$(dirname "$(readlink -f -- "$0")")/benchmark_tool.sh" parallel "$@"
