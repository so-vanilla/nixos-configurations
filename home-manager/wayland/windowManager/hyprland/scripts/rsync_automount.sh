#!/usr/bin/env bash

ORG_DIR="$HOME/org"

if ! mountpoint -q "$ORG_DIR"; then
    rclone mount org: "$ORG_DIR" --daemon
fi
