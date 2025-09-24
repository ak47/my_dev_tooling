#!/bin/bash

# GitHub Team PR Checker Configuration
# Edit this file to configure the PR checker settings

# List of repositories to check (format: owner/repo)
REPOS=(
    # "owner/another-repo"
    # "organization/third-repo"
)

# Team member GitHub handles (optional - leave empty to only use branch pattern)
TEAM_MEMBERS=(
    # "username1"
    # "username2"
    # "username3"
)

# Requested reviewers to monitor (optional)
# Include PRs where these users or teams are requested as reviewers
# Supports individual users (e.g., "username") and teams (e.g., "org/team-name")
REQUESTED_REVIEWERS=(
    # "ak47"                    # Individual user
    # "some-team"              # Team name
    # "organization/backend-team" # Full team path
)

# Branch prefix pattern (optional - leave empty to only use team members)
# Supports multiple prefixes
BRANCH_PREFIXES=(
    # "FEATURE-"
    # "feature-"
)

# Minimum digits after prefix (for branch pattern matching)
MIN_DIGITS=4

# Include draft pull requests (true/false)
# Set to true to include draft PRs in notifications, false to exclude them
INCLUDE_DRAFTS=false

# Filter out PRs already approved by this user (optional)
# Set to your GitHub username to exclude PRs you've already approved
# Leave empty to include all matching PRs regardless of approval status
GITHUB_USER_HANDLE="your-username"

# Always notify about all matching PRs (true/false)
# Set to true to notify about all matching PRs on every run, even if previously notified
# Set to false to only notify about new PRs (default behavior)
ALWAYS_NOTIFY=false

# Filter out PRs with failed automated checks (true/false)
# Set to true to exclude PRs that have failed CI/CD checks (default behavior)
# Set to false to include all PRs regardless of check status
FILTER_FAILED_CHECKS=true

# Morning listing of all PRs pending review (true/false)
# Set to true to send a daily morning summary of all PRs pending your review
# This runs once per day and shows all PRs where you are requested as a reviewer
# Honors INCLUDE_DRAFTS and FILTER_FAILED_CHECKS settings
MORNING_REVIEW_LISTING=true

# Slack webhook URL
# Set as environment variable or replace with actual URL
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL}"

# GitHub CLI path (optional - will use system PATH if not set)
GITHUB_CLI_PATH="/opt/homebrew/bin"
GITHUB_TOKEN="your-github-token-here"

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
MAX_PROCESSED_PRS=500  # Maximum number of processed PRs to keep in history
