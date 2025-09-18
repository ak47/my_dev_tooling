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
- 📊 **Detailed Slack messages**: Shows PR details with direct links and draft status
- 📝 **Comprehensive logging**: Tracks all processed PRs and notifications

## Prerequisites

- Linux/macOS/WSL environment
- GitHub CLI (`gh`) installed
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

# GitHub CLI path (optional - will use system PATH if not set)
GITHUB_CLI_PATH="/usr/local/bin"

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
MAX_PROCESSED_PRS=500  # Maximum number of processed PRs to keep in history
```

### Step 6: Set Up Slack Webhook URL

#### Option A: Environment Variable
```bash
# Add to ~/.bashrc or ~/.zshrc
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
source ~/.bashrc  # or source ~/.zshrc
```

#### Option B: Directly in config.sh
Set the webhook URL directly in `config.sh`:
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
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
*/15 * * * * SLACK_WEBHOOK_URL="your-webhook-url" /home/your-user/scripts/check-team-prs.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

#### Every 30 minutes during work hours (9am-6pm, Mon-Fri):
```bash
*/30 9-18 * * 1-5 SLACK_WEBHOOK_URL="your-webhook-url" /home/your-user/scripts/check-team-prs.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

#### Every hour:
```bash
0 * * * * SLACK_WEBHOOK_URL="your-webhook-url" /home/your-user/scripts/check-team-prs.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

### Alternative: Create a Wrapper Script

For cleaner crontab management:

```bash
cat > ~/scripts/pr-checker-wrapper.sh << 'EOF'
#!/bin/bash
export SLACK_WEBHOOK_URL="your-webhook-url-here"
export PATH="/usr/local/bin:$PATH"  # Ensure gh is in PATH
/home/your-user/scripts/check-team-prs.sh
EOF

chmod +x ~/scripts/pr-checker-wrapper.sh

# Then in crontab:
*/15 * * * * /home/your-user/scripts/pr-checker-wrapper.sh >> /home/your-user/scripts/logs/cron.log 2>&1
```

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

### Example 3: Combined Filtering
Monitor PRs that match branch patterns OR are from team members:
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=("CRX-" "FEATURE-")
```

### Example 4: Include Draft PRs
Monitor all PRs including drafts (useful for early feedback):
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=("CRX-" "FEATURE-")
INCLUDE_DRAFTS=true  # Include draft PRs in notifications
```

### Example 5: Filter Out Already Approved PRs
Only notify about PRs you haven't approved yet:
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=("CRX-" "FEATURE-")
GITHUB_USER_HANDLE="your-username"  # Filter out PRs you've approved
```

### Example 6: Always Notify About All Matching PRs
Get notified about all matching PRs on every run (useful for monitoring):
```bash
REPOS=("org/repo1" "org/repo2")
TEAM_MEMBERS=("alice" "bob" "charlie")
BRANCH_PREFIXES=("CRX-" "FEATURE-")
ALWAYS_NOTIFY=true  # Notify about all matching PRs every time
```

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
    ├── check_summary.log       # Summary of each run
    └── cron.log               # Cron execution logs
```

## Slack Notification Format

Notifications include:
- PR number and title
- Author username
- Branch name
- Repository name
- Direct link button to view PR
- Visual indicators for match type (🌿 branch pattern, 👤 team member)
- Draft status indicator when `INCLUDE_DRAFTS=true`

## Configuration File (config.sh)

The `config.sh` file centralizes all configuration settings, making it easy to manage without editing the main scripts.

### Configuration Options

- **REPOS**: Array of repositories to monitor (format: `owner/repo`)
- **TEAM_MEMBERS**: Array of GitHub usernames to monitor
- **BRANCH_PREFIXES**: Array of branch name prefixes to match
- **MIN_DIGITS**: Minimum digits required after branch prefix
- **INCLUDE_DRAFTS**: Whether to include draft PRs (`true`/`false`)
- **GITHUB_USER_HANDLE**: Your GitHub username to filter out already approved PRs
- **ALWAYS_NOTIFY**: Whether to notify about all matching PRs on every run (`true`/`false`)
- **SLACK_WEBHOOK_URL**: Slack webhook URL for notifications
- **GITHUB_CLI_PATH**: Custom path to GitHub CLI (optional)
- **LOG_LEVEL**: Logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`)
- **MAX_PROCESSED_PRS**: Maximum processed PRs to keep in history

### Benefits of config.sh

- ✅ **Easy configuration**: Edit one file instead of multiple scripts
- ✅ **Version control friendly**: Keep sensitive data out of main scripts
- ✅ **Environment flexibility**: Override settings via environment variables
- ✅ **Clean separation**: Configuration separate from logic

## Customization

### Adjust notification format
Edit the `send_slack_notification` function to customize the Slack message format.

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