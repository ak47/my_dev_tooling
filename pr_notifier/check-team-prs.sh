#!/bin/bash

# check-team-prs.sh
# Checks for team PRs across multiple repos by branch pattern or team member

# Get script directory and source configuration
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

# Create logs folder
LOGS_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOGS_DIR}"
PROCESSED_PRS_FILE="${LOGS_DIR}/processed_team_prs.txt"  # Tracks which PRs we've already notified about

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set up GitHub CLI path
if [ -n "$GITHUB_CLI_PATH" ]; then
    export PATH="${GITHUB_CLI_PATH}:${PATH}"
fi

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com/"
    echo "Or set GITHUB_CLI_PATH in config.sh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub CLI${NC}"
    echo "Run: gh auth login"
    exit 1
fi

# Check if Slack webhook is configured
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo -e "${RED}Error: SLACK_WEBHOOK_URL is not set${NC}"
    echo "Set it as an environment variable or update config.sh"
    exit 1
fi

# Check if at least one filter is configured
if [ ${#BRANCH_PREFIXES[@]} -eq 0 ] && [ ${#TEAM_MEMBERS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No branch prefixes or team members configured${NC}"
    echo "Configure at least one BRANCH_PREFIXES or TEAM_MEMBERS in config.sh"
    exit 1
fi

# Create processed PRs file if it doesn't exist
touch "$PROCESSED_PRS_FILE"

# Function to check if branch matches any prefix pattern
matches_branch_pattern() {
    local branch="$1"
    
    # If no branch prefixes configured, return false
    if [ ${#BRANCH_PREFIXES[@]} -eq 0 ]; then
        return 1
    fi
    
    for prefix in "${BRANCH_PREFIXES[@]}"; do
        # Case-insensitive match with minimum digit requirement
        if [[ "$branch" =~ ^${prefix}[0-9]{${MIN_DIGITS},} ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if author is a team member
is_team_member() {
    local author="$1"
    
    # If no team members configured, return false
    if [ ${#TEAM_MEMBERS[@]} -eq 0 ]; then
        return 1
    fi
    
    for member in "${TEAM_MEMBERS[@]}"; do
        if [ "$author" = "$member" ]; then
            return 0
        fi
    done
    return 1
}

# Function to send Slack notification
send_slack_notification() {
    local pr_title="$1"
    local pr_author="$2"
    local pr_branch="$3"
    local pr_url="$4"
    local pr_number="$5"
    local repo_name="$6"
    local match_reason="$7"
    local is_draft="$8"
    
    # Escape special characters for JSON
    pr_title=$(echo "$pr_title" | sed 's/"/\\"/g')
    
    # Create match reason emoji and text
    local match_emoji=""
    local match_text=""
    if [ "$match_reason" = "branch" ]; then
        match_emoji="🌿"
        match_text="Branch Pattern Match"
    elif [ "$match_reason" = "member" ]; then
        match_emoji="👤"
        match_text="Team Member PR"
    else
        match_emoji="🔍"
        match_text="Team PR"
    fi
    
    # Add draft status to text
    if [ "$is_draft" = "true" ]; then
        match_text="${match_text} (Draft)"
    fi
    
    # Set header text based on draft status
    local header_text=""
    if [ "$is_draft" = "true" ]; then
        header_text="${match_emoji} Draft PR Created"
    else
        header_text="${match_emoji} PR Ready for Review"
    fi
    
    local payload=$(cat <<EOF
{
    "text": "Team PR ready for review",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "${header_text}",
                "emoji": true
            }
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "${match_text} | *${repo_name}*"
                }
            ]
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*PR:* #${pr_number}"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Author:* ${pr_author}"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Branch:* \`${pr_branch}\`"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Title:* ${pr_title}"
                }
            ]
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "View PR",
                        "emoji": true
                    },
                    "url": "${pr_url}",
                    "style": "primary"
                }
            ]
        }
    ]
}
EOF
    )
    
    # Send to Slack
    response=$(curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$payload")
    
    if [ "$response" = "ok" ]; then
        echo -e "${GREEN}✓ Notification sent for PR #${pr_number}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to send notification for PR #${pr_number}: ${response}${NC}"
        return 1
    fi
}

# Function to check if user has already approved the PR
user_has_approved() {
    local pr_reviews="$1"
    local user_handle="$2"
    
    # If no user handle configured, don't filter by approval
    if [ -z "$user_handle" ]; then
        return 1
    fi
    
    # Check if user has approved (state: "APPROVED")
    echo "$pr_reviews" | jq -r --arg user "$user_handle" '.[] | select(.author.login == $user and .state == "APPROVED")' | grep -q "."
    return $?
}

# Function to check if PR has failed automated checks
pr_has_failed_checks() {
    local repo="$1"
    local pr_number="$2"
    
    # If CI filtering is disabled, don't check
    if [ "$FILTER_FAILED_CHECKS" != "true" ]; then
        return 1
    fi
    
    # Get the head commit SHA for this PR (more efficient than getting all commits)
    local head_sha=$(gh pr view "$pr_number" --repo "$repo" --json headRefOid -q '.headRefOid' 2>/dev/null)
    
    # If we can't get the head SHA, assume checks are passing (don't filter out)
    if [ $? -ne 0 ] || [ -z "$head_sha" ]; then
        return 1
    fi
    
    # Get check runs for this specific commit (more targeted API call)
    local check_runs=$(gh api "repos/${repo}/commits/${head_sha}/check-runs?per_page=50&status=completed" 2>/dev/null)
    
    # If we can't get check runs, assume checks are passing (don't filter out)
    if [ $? -ne 0 ] || [ -z "$check_runs" ]; then
        return 1
    fi
    
    # Check if any completed check runs have failed
    local failed_checks=$(echo "$check_runs" | jq -r '.check_runs[] | select(.conclusion == "failure") | .name' 2>/dev/null)
    
    if [ -n "$failed_checks" ]; then
        return 0  # Has failed checks
    fi
    
    return 1  # No failed checks
}

# Main execution
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Checking for team PRs...${NC}"
echo -e "${BLUE}Repos: ${#REPOS[@]} configured${NC}"
if [ ${#BRANCH_PREFIXES[@]} -gt 0 ]; then
    echo -e "${BLUE}Branch prefixes: ${BRANCH_PREFIXES[*]}${NC}"
fi
if [ ${#TEAM_MEMBERS[@]} -gt 0 ]; then
    echo -e "${BLUE}Team members: ${#TEAM_MEMBERS[@]} configured${NC}"
fi
if [ -n "$GITHUB_USER_HANDLE" ]; then
    echo -e "${BLUE}Approval filtering: Enabled (${GITHUB_USER_HANDLE})${NC}"
else
    echo -e "${BLUE}Approval filtering: Disabled${NC}"
fi
if [ "$ALWAYS_NOTIFY" = "true" ]; then
    echo -e "${BLUE}Always notify: Enabled (will notify about all matching PRs)${NC}"
else
    echo -e "${BLUE}Always notify: Disabled (only new PRs)${NC}"
fi
if [ "$FILTER_FAILED_CHECKS" = "true" ]; then
    echo -e "${BLUE}CI filtering: Enabled (exclude PRs with failed checks)${NC}"
else
    echo -e "${BLUE}CI filtering: Disabled (include all PRs)${NC}"
fi
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Clear processed PRs file if ALWAYS_NOTIFY is enabled
if [ "$ALWAYS_NOTIFY" = "true" ]; then
    > "$PROCESSED_PRS_FILE"
    echo -e "${BLUE}Cleared processed PRs history (ALWAYS_NOTIFY enabled)${NC}"
fi

# Counters
total_prs=0
new_notifications=0

# Process each repository
for repo in "${REPOS[@]}"; do
    echo -e "\n${BLUE}Checking ${repo}...${NC}"
    
    # Check if repo exists and we have access
    if ! gh repo view "$repo" &> /dev/null; then
        echo -e "${RED}  ✗ Cannot access repo ${repo} (check permissions or repo name)${NC}"
        continue
    fi
    
    # Get all open PRs (with optional draft filtering)
    if [ "$INCLUDE_DRAFTS" = "true" ]; then
        # Include all PRs (drafts and non-drafts)
        gh pr list \
            --repo "$repo" \
            --state open \
            --limit 100 \
            --json number,title,author,headRefName,url,isDraft,reviews | \
        jq -r '.[] | @json'
    else
        # Exclude draft PRs (default behavior)
        gh pr list \
            --repo "$repo" \
            --state open \
            --limit 100 \
            --json number,title,author,headRefName,url,isDraft,reviews | \
        jq -r '.[] | select(.isDraft == false) | @json'
    fi | \
    while IFS= read -r pr_json; do
        # Parse PR data
        pr_number=$(echo "$pr_json" | jq -r '.number')
        pr_title=$(echo "$pr_json" | jq -r '.title')
        pr_author=$(echo "$pr_json" | jq -r '.author.login')
        pr_branch=$(echo "$pr_json" | jq -r '.headRefName')
        pr_url=$(echo "$pr_json" | jq -r '.url')
        pr_is_draft=$(echo "$pr_json" | jq -r '.isDraft')
        pr_reviews=$(echo "$pr_json" | jq -r '.reviews')
        
        # Create unique ID for this PR (repo + number)
        pr_id="${repo}#${pr_number}"
        
        # Check if PR matches our criteria
        match_reason=""
        
        # Check branch pattern
        if matches_branch_pattern "$pr_branch"; then
            match_reason="branch"
        fi
        
        # Check if author is team member
        if is_team_member "$pr_author"; then
            if [ -z "$match_reason" ]; then
                match_reason="member"
            else
                match_reason="both"
            fi
        fi
        
        # Skip if no match
        if [ -z "$match_reason" ]; then
            continue
        fi
        
        # Check if user has already approved this PR
        if user_has_approved "$pr_reviews" "$GITHUB_USER_HANDLE"; then
            echo "  • PR #${pr_number} already approved by ${GITHUB_USER_HANDLE} (${pr_author} - ${pr_branch})"
            continue
        fi
        
        # Check if PR has failed automated checks
        if pr_has_failed_checks "$repo" "$pr_number"; then
            echo "  • PR #${pr_number} has failed checks (${pr_author} - ${pr_branch})"
            continue
        fi
        
        total_prs=$((total_prs + 1))
        
        # Check if we've already processed this PR (unless ALWAYS_NOTIFY is enabled)
        if [ "$ALWAYS_NOTIFY" != "true" ] && grep -q "^${pr_id}$" "$PROCESSED_PRS_FILE"; then
            echo "  • PR #${pr_number} already notified (${pr_author} - ${pr_branch})"
            continue
        fi
        
        # Display match information
        draft_indicator=""
        if [ "$pr_is_draft" = "true" ]; then
            draft_indicator=" (Draft)"
        fi
        
        if [ "$match_reason" = "branch" ]; then
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (branch pattern: ${pr_branch})${draft_indicator}${NC}"
        elif [ "$match_reason" = "member" ]; then
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (team member: ${pr_author})${draft_indicator}${NC}"
        else
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (team member: ${pr_author}, branch: ${pr_branch})${draft_indicator}${NC}"
        fi
        echo "    Title: ${pr_title}"
        
        # Send notification
        if send_slack_notification "$pr_title" "$pr_author" "$pr_branch" "$pr_url" "$pr_number" "$repo" "$match_reason" "$pr_is_draft"; then
            # Mark PR as processed only if notification was successful
            echo "$pr_id" >> "$PROCESSED_PRS_FILE"
            new_notifications=$((new_notifications + 1))
        fi
    done
done

# Clean up old processed PRs (keep only last MAX_PROCESSED_PRS entries)
if [ $(wc -l < "$PROCESSED_PRS_FILE") -gt $MAX_PROCESSED_PRS ]; then
    tail -$MAX_PROCESSED_PRS "$PROCESSED_PRS_FILE" > "$PROCESSED_PRS_FILE.tmp" && mv "$PROCESSED_PRS_FILE.tmp" "$PROCESSED_PRS_FILE"
fi

# Summary
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $new_notifications -gt 0 ]; then
    echo -e "${GREEN}✓ Sent ${new_notifications} new notification(s)${NC}"
else
    echo "No new team PRs to notify about"
fi
echo -e "Total team PRs open: ${total_prs}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Log summary with timestamp
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checked ${#REPOS[@]} repos, found ${total_prs} team PRs, sent ${new_notifications} notifications" >> "${LOGS_DIR}/check_summary.log"