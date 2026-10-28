#!/bin/bash

sleep 30 &
worker_pid=$!
trap 'kill "$worker_pid" 2>/dev/null || true; exit 0' TERM
wait "$worker_pid"
