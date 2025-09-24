# GitHub Team PR Checker

![GitHub](https://img.shields.io/badge/GitHub-CLI-blue?logo=github)
![Slack](https://img.shields.io/badge/Slack-Notifications-4A154B?logo=slack)
![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash)

Automated Slack notifications for team pull requests across multiple GitHub repositories. Get notified when PRs matching your team's branch patterns or created by team members are ready for review.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration Examples](#configuration-examples)
- [Monitoring & Troubleshooting](#monitoring--troubleshooting)
- [File Structure](#file-structure)
- [Slack Notification Format](#slack-notification-format)
- [Configuration File (config.sh)](#configuration-file-configsh)
- [Customization](#customization)
- [Security Notes](#security-notes)
- [Support](#support)
- [License](#license)

## Features

- 🔍 **Multiple filtering options**: Branch patterns, team members, or both
- 📦 **Multi-repository support**: Monitor PRs across all your team's repos
- 🚫 **Configurable draft PR filtering**: Choose to include or exclude draft PRs
- 🔔 **Smart notifications**: Only notifies once per PR (no spam)
- 🌅 **Daily morning review summary**: Get a comprehensive list of all PRs pending your review each morning
- 📊 **Detailed Slack messages**: Shows PR details with direct links and draft status
- 📝 **Comprehensive logging**: Tracks all processed PRs and notifications

## Prerequisites

- Linux/macOS/WSL environment
- GitHub CLI (`gh`) installed
- GitHub personal access token with `repo` and `read:org` scopes
- Slack workspace with incoming webhook configured
- Access to the GitHub repositories you want to monitor

## Installation

### Step 1: Install GitHub CLI

#### macOS
```bash
brew install gh
```

#### Other platforms

Visit: [GitHub CLI Installation Guide](https://cli.github.com/manual/installation)

### Step 2: Authenticate GitHub CLI

```bash
gh auth login
```
Follow the interactive prompts to authenticate with your GitHub account.

Verify authentication:
```bash
gh auth status
```

### Step 3: Set Up Slack Webhook

1. Go to [Slack API Apps](https://api.slack.com/apps)
2. Click **"Create New App"** > **"From scratch"**
3. Name your app (e.g., "GitHub PR Notifier") and select your workspace
4. In the app settings, go to **"Incoming Webhooks"**
5. Toggle **"Activate Incoming Webhooks"** to ON
6. Click **"Add New Webhook to Workspace"**
7. Select the channel where you want notifications
8. Copy the webhook URL (looks like: `https://hooks.slack.com/services/T.../B.../...`)

### Step 4: Download and Configure the Script

```bash
# Create scripts directory
mkdir -p ~/scripts
cd ~/scripts

# Download the scripts (or create them manually)
# Copy the script contents from this repository:
# - check-team-prs.sh
# - check-prs-wrapper.sh  
# - config.sh

# Make scripts executable
chmod +x check-team-prs.sh check-prs-wrapper.sh config.sh
```

### Step 5: Configure the Script

Edit `config.sh` and update the configuration settings:

```bash
# List of repositories to check
REPOS=(
    "organization/repo-name"
    "organization/another-repo"
)

# Team member GitHub handles (optional)
TEAM_MEMBERS=(
    "john-doe"
    "jane-smith"
)

# Requested reviewers to monitor (optional)
# Include PRs where these users or teams are requested as reviewers
# Supports individual users (e.g., "username") and teams (e.g., "org/team-name")
REQUESTED_REVIEWERS=(
    # "your-username"              # Individual user
    # "team-name"                  # Team name
    # "organization/team-name"     # Full team path
)

# Branch prefixes to match (optional)
BRANCH_PREFIXES=(
    "CRX-"
    "crx-"
    "FEATURE-"
)

# Minimum digits after prefix (for branch validation)
MIN_DIGITS=4

# Include draft pull requests (true/false)
# Set to true to include draft PRs in notifications, false to exclude them
INCLUDE_DRAFTS=false

# Filter out PRs already approved by this user (optional)
# Set to your GitHub username to exclude PRs you've already approved
# Leave empty to include all matching PRs regardless of approval status
GITHUB_USER_HANDLE=""

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

# GitHub CLI path (optional - will use system PATH if not set)
GITHUB_CLI_PATH="/usr/local/bin"

# GitHub token for authentication (required for cron jobs)
# Get your token from: https://github.com/settings/tokens
GITHUB_TOKEN="your-github-token-here"

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
MAX_PROCESSED_PRS=500  # Maximum number of processed PRs to keep in history
```

### Step 6: Set Up Slack Webhook URL

Add your webhook URL to `config.sh`:
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

Alternatively, set it as an environment variable:
```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Step 7: Test the Script

```bash
# Run manually
~/scripts/check-prs-wrapper.sh

# Check the logs
ls ~/scripts/logs/
cat ~/scripts/logs/processed_team_prs.txt
```

### Step 8: Set Up Automated Checking (Cron)

```bash
# Edit crontab
crontab -e

# Add one of these schedules:
```

#### Every 15 minutes:
```bash
*/15 * * * * /home/your-user/scripts/check-prs-wrapper.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

#### Every 30 minutes during work hours (9am-6pm, Mon-Fri):
```bash
*/30 9-18 * * 1-5 /home/your-user/scripts/check-prs-wrapper.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

#### Every hour:
```bash
0 * * * * /home/your-user/scripts/check-prs-wrapper.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

### Alternative: Create a Custom Wrapper Script

For cleaner crontab management:

```bash
cat > ~/scripts/my-pr-checker.sh << 'EOF'
#!/bin/bash
export SLACK_WEBHOOK_URL="your-webhook-url-here"
export PATH="/usr/local/bin:$PATH"  # Ensure gh is in PATH
/home/your-user/scripts/check-prs-wrapper.sh
EOF

chmod +x ~/scripts/my-pr-checker.sh

# Then in crontab:
*/15 * * * * /home/your-user/scripts/my-pr-checker.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

## GitHub Authentication

### Required GitHub Token Scopes

⚠️ **IMPORTANT**: Your GitHub personal access token must have the correct scopes to function properly. The script requires specific permissions to access organization data and review requests.

**Required Scopes:**
- `repo` - Access to private repositories
- `read:org` - **REQUIRED** for organization access and review requests

**Common Error:**
If you see this error:
```
GraphQL: Your token has not been granted the required scopes to execute this query. The 'login' field requires one of the following scopes: ['read:org'], but your token has only been granted the: ['admin:repo_hook', 'codespace', 'copilot', 'delete:packages', 'gist', 'notifications', 'project', 'repo', 'workflow', 'write:discussion', 'write:packages'] scopes.
```

**Solution:** Update your token scopes at [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens) to include `read:org`.

### For Cron Jobs

Cron jobs run in a minimal environment without access to your interactive GitHub CLI authentication. You need to provide a GitHub personal access token:

1. **Create a GitHub Personal Access Token**:
   - Go to [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens)
   - Click "Generate new token (classic)"
   - **Select these scopes:**
     - ✅ `repo` (for private repos)
     - ✅ `read:org` (for organization access and review requests)
   - Copy the generated token

2. **Add Token to config.sh**:
   ```bash
   GITHUB_TOKEN="ghp_your-token-here"
   ```

3. **The script will automatically authenticate** using this token when running

### For Interactive Use

The script will automatically use the token from `config.sh` if available, or fall back to your existing GitHub CLI authentication.

## Configuration Examples

### Example 1: Branch Pattern Only
Monitor PRs with specific branch prefixes:
```bash
REPOS=("mudflapapp/mudflap-api")
TEAM_MEMBERS=()  # Empty - only check branch patterns
BRANCH_PREFIXES=("CRX-" "crx-" "HOTFIX-")
MIN_DIGITS=4  # Require at least 4 digits after prefix
```

### Example 2: Team Members Only
Monitor all PRs from specific team members:
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=()  # Empty - only check team members
```

### Example 3: Combined Filtering with Advanced Options
Monitor PRs that match branch patterns OR are from team members, with additional filtering options:
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=("CRX-" "FEATURE-")

# Optional advanced settings (uncomment as needed):
# INCLUDE_DRAFTS=true                    # Include draft PRs in notifications
# GITHUB_USER_HANDLE="your-username"    # Filter out PRs you've approved
# ALWAYS_NOTIFY=true                    # Notify about all matching PRs every time
# FILTER_FAILED_CHECKS=false            # Include PRs with failed checks
# MORNING_REVIEW_LISTING=true           # Daily morning summary of pending reviews
```

### Example 4: Monitor Requested Reviewers
Get notified about PRs where you or your team are requested as reviewers:
```bash
REPOS=("org/repo1" "org/repo2")
REQUESTED_REVIEWERS=("your-username" "team-name" "org/backend-team")
# This will notify about PRs where any of these are requested as reviewers
```

**Note**: The requested reviewers feature requires a GitHub token with `read:org` scope. If the scope is not available, the feature will be disabled gracefully.

## Monitoring & Troubleshooting

### Check if cron is running:
```bash
# View cron logs
tail -f ~/scripts/logs/cron.log

# Check summary log
tail -f ~/scripts/logs/check_summary.log
```

### View processed PRs:
```bash
cat ~/scripts/logs/processed_team_prs.txt
```

### View PR check logs with timestamps:
```bash
# View recent log entries
tail -f ~/scripts/logs/pr-check.log

# View all log entries
cat ~/scripts/logs/pr-check.log
```

**Log Format**: Each session starts with a timestamp header:
```
=== PR Check Session Started: 2025-09-19 12:44:33 ===
```

### Test Slack webhook:
```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"text":"Test message from PR checker"}' \
  YOUR_SLACK_WEBHOOK_URL
```

### Common Issues

#### "gh: command not found" in cron
Add PATH to your crontab or wrapper script:
```bash
PATH=/usr/local/bin:/usr/bin:/bin
```

#### "Cannot access repo" error
- Verify you have read access to the repository
- Check that your GitHub token has the correct scopes (`repo` for private repos, `read:org` for review requests)
- Ensure `GITHUB_TOKEN` is set in your `config.sh`

#### "GraphQL: Your token has not been granted the required scopes" error
This error occurs when your GitHub token is missing the `read:org` scope:

```
GraphQL: Your token has not been granted the required scopes to execute this query. The 'login' field requires one of the following scopes: ['read:org'], but your token has only been granted the: ['admin:repo_hook', 'codespace', 'copilot', 'delete:packages', 'gist', 'notifications', 'project', 'repo', 'workflow', 'write:discussion', 'write:packages'] scopes.
```

**Solution:**
1. Go to [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens)
2. Find your current token and click "Edit"
3. Add the `read:org` scope to your token
4. Save the changes
5. Update your `config.sh` with the new token if needed

#### "GitHub authentication failed" in cron
- Make sure `GITHUB_TOKEN` is properly set in `config.sh`
- Verify the token is valid and not expired
- Check that the token has the required scopes (`repo`, `read:org`)
- Enable debug mode by setting `LOG_LEVEL="DEBUG"` in `config.sh` for more information
- Ensure the cron job has access to the GitHub CLI: `which gh` in your cron environment
- Check repository name spelling (format: `owner/repo`)
- Re-authenticate: `gh auth refresh`

#### No notifications received
1. Check Slack webhook is valid
2. Verify PRs match your filters
3. Check `processed_team_prs.txt` - PRs are only notified once
4. Run script manually to see detailed output

#### Duplicate notifications
Clear the processed PRs file to reset:
```bash
> ~/scripts/logs/processed_team_prs.txt
```

## File Structure

After setup, you'll have:

```text
~/scripts/
├── check-team-prs.sh           # Main script
├── check-prs-wrapper.sh        # Wrapper script for cron
├── config.sh                   # Configuration file
└── logs/
    ├── processed_team_prs.txt  # Tracks notified PRs
    ├── morning_listing_sent.txt # Tracks daily morning listing
    ├── pr-check.log           # Main execution log with timestamps
    ├── check_summary.log       # Summary of each run
    └── cron.log               # Cron execution logs
```

## Slack Notification Format

### Regular Notifications
Consolidated notifications include:
- **Header**: Shows total count of PRs
- **Legend**: Explains emoji meanings (🌿 Branch Pattern, 👤 Team Member, 👥 Requested Reviewer)
- **PR List**: Each PR with:
  - PR number and title (clickable link)
  - Author, branch, and repository information
  - Visual indicators for match type
  - Draft status indicators when applicable

### Morning Review Summary
Daily morning notifications show:
- **Header**: "🌅 Morning Review Summary (X PRs pending your review)"
- **Legend**: "📋 All PRs where you are requested as a reviewer"
- **PR List**: All PRs pending your review with same details as regular notifications

## Configuration File (config.sh)

The `config.sh` file centralizes all configuration settings, making it easy to manage without editing the main scripts.

### Configuration Options

- **REPOS**: Array of repositories to monitor (format: `owner/repo`)
- **TEAM_MEMBERS**: Array of GitHub usernames to monitor
- **REQUESTED_REVIEWERS**: Array of users/teams to monitor as requested reviewers
- **BRANCH_PREFIXES**: Array of branch name prefixes to match
- **MIN_DIGITS**: Minimum digits required after branch prefix
- **INCLUDE_DRAFTS**: Whether to include draft PRs (`true`/`false`)
- **GITHUB_USER_HANDLE**: Your GitHub username to filter out already approved PRs
- **ALWAYS_NOTIFY**: Whether to notify about all matching PRs on every run (`true`/`false`)
- **FILTER_FAILED_CHECKS**: Whether to exclude PRs with failed CI/CD checks (`true`/`false`)
- **MORNING_REVIEW_LISTING**: Whether to send daily morning summary of PRs pending your review (`true`/`false`)
- **SLACK_WEBHOOK_URL**: Slack webhook URL for notifications
- **GITHUB_CLI_PATH**: Custom path to GitHub CLI (optional)
- **GITHUB_TOKEN**: GitHub personal access token for authentication (required for cron)
- **LOG_LEVEL**: Logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`)
- **MAX_PROCESSED_PRS**: Maximum processed PRs to keep in history

### Benefits of config.sh

- ✅ **Easy configuration**: Edit one file instead of multiple scripts
- ✅ **Version control friendly**: Keep sensitive data out of main scripts
- ✅ **Environment flexibility**: Override settings via environment variables
- ✅ **Clean separation**: Configuration separate from logic

## Customization

### Adjust notification format
Edit the `send_consolidated_slack_notification` function to customize the Slack message format.

### Configure draft PR handling
Control whether draft PRs are included in notifications:
- `INCLUDE_DRAFTS=false` (default): Only notify for PRs ready for review
- `INCLUDE_DRAFTS=true`: Include draft PRs for early feedback and visibility

When drafts are included, notifications will show:
- "(Draft)" indicator in the context text
- "Draft PR Created" header instead of "PR Ready for Review"

### Configure approval filtering
Filter out PRs you've already approved to reduce notification noise:
- `GITHUB_USER_HANDLE=""` (default): Include all matching PRs regardless of approval status
- `GITHUB_USER_HANDLE="your-username"`: Exclude PRs you've already approved

When approval filtering is enabled:
- PRs you've approved will be skipped with a console message
- Only PRs requiring your review will trigger notifications
- Useful for reducing notification fatigue when you're an active reviewer

### Configure always notify behavior
Control whether to notify about all matching PRs on every run:
- `ALWAYS_NOTIFY=false` (default): Only notify about new PRs (avoid spam)
- `ALWAYS_NOTIFY=true`: Notify about all matching PRs every time the script runs

When always notify is enabled:
- Processed PRs history is cleared at the start of each run
- You'll get notifications about all matching PRs, even if previously notified
- Useful for monitoring dashboards or when you want to see all current PRs
- Console will show "Cleared processed PRs history (ALWAYS_NOTIFY enabled)"

### Configure CI/CD check filtering
Control whether to exclude PRs with failed automated checks:
- `FILTER_FAILED_CHECKS=true` (default): Only notify about PRs with passing checks
- `FILTER_FAILED_CHECKS=false`: Include all PRs regardless of check status

When CI filtering is enabled:
- PRs with failed CI/CD checks will be skipped with a console message
- Only PRs with passing checks (or no checks) will trigger notifications
- Useful for ensuring you only review PRs that are actually ready
- Console will show "PR #123 has failed checks" for filtered PRs

### Add more filters
Extend the script to filter by:
- PR labels
- File changes
- PR size
- Custom patterns

### Change notification channel
Use multiple webhooks for different channels:
```bash
if [[ "$pr_branch" =~ HOTFIX ]]; then
    WEBHOOK=$EMERGENCY_WEBHOOK
else
    WEBHOOK=$REGULAR_WEBHOOK
fi
```

## Security Notes

- Never commit your Slack webhook URL to version control
- Use environment variables or secure secret management for sensitive data
- Regularly rotate your Slack webhook URLs
- Limit GitHub token permissions to minimum required (read-only for public repos)

## Support

For issues with:

- **GitHub CLI**: [GitHub CLI Manual](https://cli.github.com/manual/)
- **Slack Webhooks**: [Slack Webhooks Documentation](https://api.slack.com/messaging/webhooks)
- **Cron syntax**: [Crontab Guru](https://crontab.guru/)

## License

This script is provided as-is for team use. Modify as needed for your workflow.