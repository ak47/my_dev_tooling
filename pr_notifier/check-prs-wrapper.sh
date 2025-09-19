#!/bin/bash

# check-prs-wrapper.sh
# Wrapper script for GitHub Team PR Checker
# This script sources the config and runs the main checker

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please create config.sh with your settings"
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"

# Set up environment variables from config
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    export SLACK_WEBHOOK_URL
fi

if [ -n "$GITHUB_CLI_PATH" ]; then
    export PATH="${GITHUB_CLI_PATH}:${PATH}"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    export GITHUB_TOKEN
    echo "GitHub token set"
fi

# Run the main script
"${SCRIPT_DIR}/check-team-prs.sh"
