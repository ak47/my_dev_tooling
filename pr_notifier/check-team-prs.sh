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
MORNING_LISTING_FILE="${LOGS_DIR}/morning_listing_sent.txt"  # Tracks when morning listing was last sent
LOG_FILE="${LOGS_DIR}/pr-check.log"  # Main log file

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

# Function to log session start timestamp
log_session_start() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "" >> "$LOG_FILE"
    echo "=== PR Check Session Started: $timestamp ===" >> "$LOG_FILE"
}

# Function to authenticate with GitHub CLI
authenticate_github() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo -e "${BLUE}Authenticating with GitHub using token...${NC}"
        # Set the token as an environment variable for GitHub CLI
        export GITHUB_TOKEN
        
        # Test if the token works by making a simple API call
        if gh api user 2>/dev/null >/dev/null; then
            echo -e "${GREEN}✓ GitHub authentication successful${NC}"
        else
            echo -e "${YELLOW}⚠ GitHub token authentication failed, trying to login...${NC}"
            # Try to authenticate with the token using a more direct approach
            # Create a temporary file with the token for non-interactive login
            local temp_token_file=$(mktemp)
            echo "$GITHUB_TOKEN" > "$temp_token_file"
            
            # Try to login with the token file
            if gh auth login --with-token < "$temp_token_file" 2>/dev/null; then
                echo -e "${GREEN}✓ GitHub authentication successful${NC}"
            else
                echo -e "${YELLOW}⚠ GitHub authentication failed, trying alternative method...${NC}"
                # Alternative: try to set the token directly in GitHub CLI config
                gh config set token "$GITHUB_TOKEN" 2>/dev/null
                if gh api user 2>/dev/null >/dev/null; then
                    echo -e "${GREEN}✓ GitHub authentication successful (via config)${NC}"
                else
                    echo -e "${YELLOW}⚠ GitHub authentication failed, continuing with existing auth${NC}"
                fi
            fi
            
            # Clean up temp file
            rm -f "$temp_token_file"
        fi
    else
        echo -e "${BLUE}No GitHub token provided, using existing authentication${NC}"
    fi
}

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

# Function to send consolidated Slack notification
send_consolidated_slack_notification() {
    local prs_data="$1"
    local total_count="$2"
    
    # Create header text
    local header_text="🔔 Team PRs Ready for Review"
    local pr_text="PRs"
    if [ "$total_count" -eq 1 ]; then
        header_text="🔔 Team PR Ready for Review"
        pr_text="PR"
    fi
    
    # Start building the JSON payload
    local payload='{
    "text": "Team PRs ready for review",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'"${header_text}"' ('"${total_count}"' '"${pr_text}"')",
                "emoji": true
            }
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "🌿 Branch Pattern | 👤 Team Member | 👥 Requested Reviewer"
                }
            ]
        }'
    
    # Process each PR and add to payload
    local temp_file=$(mktemp)
    printf '%b' "$prs_data" > "$temp_file"
    
    while IFS='|' read -r pr_number pr_title pr_author pr_branch pr_url repo_name match_reason is_draft; do
        # Skip empty lines
        if [ -z "$pr_number" ]; then
            continue
        fi
        
        # Escape special characters for JSON
        pr_title=$(echo "$pr_title" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
        pr_branch=$(echo "$pr_branch" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
        
        # Create match reason emoji
        local match_emoji=""
        if [ "$match_reason" = "branch" ]; then
            match_emoji="🌿"
        elif [ "$match_reason" = "member" ]; then
            match_emoji="👤"
        elif [ "$match_reason" = "reviewer" ]; then
            match_emoji="👥"
        else
            match_emoji="🔍"
        fi
        
        # Add draft indicator
        local draft_indicator=""
        if [ "$is_draft" = "true" ]; then
            draft_indicator=" *(Draft)*"
        fi
        
        # Add section to payload
        payload="${payload},
        {
            \"type\": \"section\",
            \"fields\": [
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*${match_emoji} PR #${pr_number}*${draft_indicator}\\n<${pr_url}|${pr_title}>\"
                },
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*Author:* ${pr_author}\\n*Branch:* \`${pr_branch}\`\\n*Repo:* ${repo_name}\"
                }
            ]
        }"
    done < "$temp_file"
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Close the JSON structure
    payload="${payload}
    ]
}"
    
    # Debug: Show payload if LOG_LEVEL is DEBUG
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        echo "Debug: Slack payload (first 20 lines):"
        echo "$payload" | head -20
        echo "..."
    fi
    
    # Send to Slack
    response=$(curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$payload")
    
    if [ "$response" = "ok" ]; then
        echo -e "${GREEN}✓ Consolidated notification sent for ${total_count} PR(s)${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to send consolidated notification: ${response}${NC}"
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

# Function to check if PR should be filtered due to failed automated checks
should_filter_pr_for_failed_checks() {
    local repo="$1"
    local pr_number="$2"
    
    # If CI filtering is disabled, don't filter
    if [ "$FILTER_FAILED_CHECKS" != "true" ]; then
        return 1  # Don't filter
    fi
    
    # Get the head commit SHA for this PR (more efficient than getting all commits)
    local head_sha=$(gh pr view "$pr_number" --repo "$repo" --json headRefOid -q '.headRefOid' 2>/dev/null)
    
    # If we can't get the head SHA, assume checks are passing (don't filter out)
    if [ $? -ne 0 ] || [ -z "$head_sha" ]; then
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            echo "    Debug: Could not get head SHA for PR #${pr_number}, assuming checks pass"
        fi
        return 1  # Don't filter
    fi
    
    # Get check runs for this specific commit (more targeted API call)
    local check_runs=$(gh api "repos/${repo}/commits/${head_sha}/check-runs?per_page=50&status=completed" 2>/dev/null)
    
    # If we can't get check runs, assume checks are passing (don't filter out)
    if [ $? -ne 0 ] || [ -z "$check_runs" ]; then
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            echo "    Debug: Could not get check runs for PR #${pr_number}, assuming checks pass"
        fi
        return 1  # Don't filter
    fi
    
    # Check if any completed check runs have failed
    local failed_checks=$(echo "$check_runs" | jq -r '.check_runs[] | select(.conclusion == "failure") | .name' 2>/dev/null)
    
    if [ -n "$failed_checks" ]; then
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            echo "    Debug: PR #${pr_number} has failed checks: $(echo "$failed_checks" | tr '\n' ', ' | sed 's/,$//')"
        fi
        return 0  # Filter this PR out
    fi
    
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        echo "    Debug: PR #${pr_number} has no failed checks"
    fi
    return 1  # Don't filter this PR
}

# Function to check if morning listing was already sent today
morning_listing_sent_today() {
    if [ ! -f "$MORNING_LISTING_FILE" ]; then
        return 1  # File doesn't exist, so not sent today
    fi
    
    local today=$(date '+%Y-%m-%d')
    local last_sent=$(cat "$MORNING_LISTING_FILE" 2>/dev/null)
    
    if [ "$last_sent" = "$today" ]; then
        return 0  # Already sent today
    else
        return 1  # Not sent today
    fi
}

# Function to mark morning listing as sent today
mark_morning_listing_sent() {
    local today=$(date '+%Y-%m-%d')
    echo "$today" > "$MORNING_LISTING_FILE"
}

# Function to get PRs pending review for morning listing
get_morning_review_prs() {
    local morning_prs=""
    local morning_count=0
    
    echo -e "${BLUE}🌅 Collecting PRs pending your review...${NC}"
    
    # Process each repository
    for repo in "${REPOS[@]}"; do
        echo -e "${BLUE}  Checking ${repo}...${NC}"
        
        # Check if repo exists and we have access
        if ! gh repo view "$repo" &> /dev/null; then
            echo -e "${RED}    ✗ Cannot access repo ${repo}${NC}"
            continue
        fi
        
        # Get all open PRs with reviews data
        local json_fields="number,title,author,headRefName,url,isDraft,reviews"
        
        # Store PRs in temporary file to avoid subshell issues
        local temp_file=$(mktemp)
        if [ "$INCLUDE_DRAFTS" = "true" ]; then
            gh pr list \
                --repo "$repo" \
                --state open \
                --limit 100 \
                --json "$json_fields" | \
            jq -r '.[] | @json' > "$temp_file"
        else
            gh pr list \
                --repo "$repo" \
                --state open \
                --limit 100 \
                --json "$json_fields" | \
            jq -r '.[] | select(.isDraft == false) | @json' > "$temp_file"
        fi
        
        while IFS= read -r pr_json; do
            # Parse PR data
            local pr_number=$(echo "$pr_json" | jq -r '.number')
            local pr_title=$(echo "$pr_json" | jq -r '.title')
            local pr_author=$(echo "$pr_json" | jq -r '.author.login')
            local pr_branch=$(echo "$pr_json" | jq -r '.headRefName')
            local pr_url=$(echo "$pr_json" | jq -r '.url')
            local pr_is_draft=$(echo "$pr_json" | jq -r '.isDraft')
            local pr_reviews=$(echo "$pr_json" | jq -r '.reviews')
            
            # Skip if user is the author of this PR
            if [ -n "$GITHUB_USER_HANDLE" ] && [ "$pr_author" = "$GITHUB_USER_HANDLE" ]; then
                continue
            fi
            
            # Check if user has already approved this PR
            if user_has_approved "$pr_reviews" "$GITHUB_USER_HANDLE"; then
                continue
            fi
            
            # Check if PR has failed automated checks
            if should_filter_pr_for_failed_checks "$repo" "$pr_number"; then
                continue
            fi
            
            # For morning listing, we'll include PRs from team members or matching branch patterns
            # This is simpler than trying to get review requests which require special permissions
            local include_pr=false
            
            # Include if author is team member
            if is_team_member "$pr_author"; then
                include_pr=true
            fi
            
            # Include if branch matches pattern
            if matches_branch_pattern "$pr_branch"; then
                include_pr=true
            fi
            
            # Include if it's in our requested reviewers list (simplified approach)
            # We'll assume if it's a team member or matches branch pattern, it might need review
            if [ "$include_pr" = "true" ]; then
                morning_prs="${morning_prs}${pr_number}|${pr_title}|${pr_author}|${pr_branch}|${pr_url}|${repo}|morning|${pr_is_draft}\n"
                morning_count=$((morning_count + 1))
                echo -e "${GREEN}    ✓ Found PR #${pr_number} for morning review (${pr_author} - ${pr_branch})${NC}"
            fi
        done < "$temp_file"
        
        # Clean up temporary file
        rm -f "$temp_file"
    done
    
    echo "$morning_prs|$morning_count"
}

# Function to check if PR has requested reviewers we're monitoring
has_requested_reviewers() {
    local pr_review_requests="$1"
    
    # If no requested reviewers configured, return false
    if [ ${#REQUESTED_REVIEWERS[@]} -eq 0 ]; then
        return 1
    fi
    
    # If review requests data is not available (no read:org scope), return false
    if [ -z "$pr_review_requests" ] || [ "$pr_review_requests" = "null" ]; then
        return 1
    fi
    
    # Check if any of the requested reviewers match our configured reviewers
    for reviewer in "${REQUESTED_REVIEWERS[@]}"; do
        # Check for exact match in requested reviewers
        if echo "$pr_review_requests" | jq -r --arg reviewer "$reviewer" '.[] | select(.login == $reviewer or .name == $reviewer) | .login' 2>/dev/null | grep -q "."; then
            return 0  # Found matching reviewer
        fi
    done
    
    return 1  # No matching reviewers
}

# Main execution
log_session_start
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Checking for team PRs...${NC}"
echo -e "${BLUE}Repos: ${#REPOS[@]} configured${NC}"
if [ ${#BRANCH_PREFIXES[@]} -gt 0 ]; then
    echo -e "${BLUE}Branch prefixes: ${BRANCH_PREFIXES[*]}${NC}"
fi
if [ ${#TEAM_MEMBERS[@]} -gt 0 ]; then
    echo -e "${BLUE}Team members: ${#TEAM_MEMBERS[@]} configured${NC}"
fi
if [ ${#REQUESTED_REVIEWERS[@]} -gt 0 ]; then
    echo -e "${BLUE}Requested reviewers: ${#REQUESTED_REVIEWERS[@]} configured${NC}"
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
if [ "$MORNING_REVIEW_LISTING" = "true" ]; then
    echo -e "${BLUE}Morning review listing: Enabled${NC}"
else
    echo -e "${BLUE}Morning review listing: Disabled${NC}"
fi
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Authenticate with GitHub
authenticate_github

# Verify authentication worked
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub CLI${NC}"
    echo "Run: gh auth login or check your GITHUB_TOKEN in config.sh"
    
    # Debug information
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        echo -e "${YELLOW}Debug information:${NC}"
        echo "GITHUB_TOKEN is set: $([ -n "$GITHUB_TOKEN" ] && echo "Yes" || echo "No")"
        echo "GitHub CLI version: $(gh --version 2>/dev/null || echo "Not available")"
        echo "Current user: $(whoami)"
        echo "Current directory: $(pwd)"
    fi
    
    exit 1
fi

# Clear processed PRs file if ALWAYS_NOTIFY is enabled
if [ "$ALWAYS_NOTIFY" = "true" ]; then
    > "$PROCESSED_PRS_FILE"
    echo -e "${BLUE}Cleared processed PRs history (ALWAYS_NOTIFY enabled)${NC}"
fi

# Check for morning review listing
if [ "$MORNING_REVIEW_LISTING" = "true" ] && [ -n "$GITHUB_USER_HANDLE" ]; then
    if ! morning_listing_sent_today; then
        echo -e "\n${BLUE}🌅 Checking for morning review listing...${NC}"
        
        # Get morning review PRs using the simplified function
        morning_data=$(get_morning_review_prs)
        morning_review_prs=$(echo "$morning_data" | cut -d'|' -f1)
        morning_review_count=$(echo "$morning_data" | cut -d'|' -f2)
        
        # Send morning review listing if there are PRs
        if [ "$morning_review_count" -gt 0 ]; then
            echo -e "\n${BLUE}🌅 Sending morning review listing for ${morning_review_count} PR(s)...${NC}"
            
            # Create morning-specific notification
            header_text="🌅 Morning Review Summary"
            pr_text="PRs"
            if [ "$morning_review_count" -eq 1 ]; then
                header_text="🌅 Morning Review Summary"
                pr_text="PR"
            fi
            
            # Start building the JSON payload for morning listing
            morning_payload='{
    "text": "Morning review summary",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'"${header_text}"' ('"${morning_review_count}"' '"${pr_text}"' pending your review)",
                "emoji": true
            }
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "📋 Team PRs that may need your review"
                }
            ]
        }'
            
            # Process each PR and add to morning payload
            temp_file=$(mktemp)
            printf '%b' "$morning_review_prs" > "$temp_file"
            
            while IFS='|' read -r pr_number pr_title pr_author pr_branch pr_url repo_name match_reason is_draft; do
                # Skip empty lines
                if [ -z "$pr_number" ]; then
                    continue
                fi
                
                # Escape special characters for JSON
                pr_title=$(echo "$pr_title" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
                pr_branch=$(echo "$pr_branch" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
                
                # Add draft indicator
                draft_indicator=""
                if [ "$is_draft" = "true" ]; then
                    draft_indicator=" *(Draft)*"
                fi
                
                # Add section to morning payload
                morning_payload="${morning_payload},
        {
            \"type\": \"section\",
            \"fields\": [
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*📋 PR #${pr_number}*${draft_indicator}\\n<${pr_url}|${pr_title}>\"
                },
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*Author:* ${pr_author}\\n*Branch:* \`${pr_branch}\`\\n*Repo:* ${repo_name}\"
                }
            ]
        }"
            done < "$temp_file"
            
            # Clean up temp file
            rm -f "$temp_file"
            
            # Close the JSON structure
            morning_payload="${morning_payload}
    ]
}"
            
            # Send morning listing to Slack
            response=$(curl -s -X POST "$SLACK_WEBHOOK_URL" \
                -H 'Content-Type: application/json' \
                -d "$morning_payload")
            
            if [ "$response" = "ok" ]; then
                echo -e "${GREEN}✓ Morning review listing sent successfully${NC}"
                mark_morning_listing_sent
            else
                echo -e "${RED}✗ Failed to send morning review listing: ${response}${NC}"
            fi
        else
            echo -e "${BLUE}No PRs pending your review this morning${NC}"
            mark_morning_listing_sent  # Mark as sent even if no PRs to avoid repeated checks
        fi
    else
        echo -e "${BLUE}Morning review listing already sent today${NC}"
    fi
fi

# Counters and data collection
total_prs=0
new_notifications=0
prs_to_notify=""

# Process each repository
for repo in "${REPOS[@]}"; do
    echo -e "\n${BLUE}Checking ${repo}...${NC}"
    
    # Check if repo exists and we have access
    if ! gh repo view "$repo" &> /dev/null; then
        echo -e "${RED}  ✗ Cannot access repo ${repo} (check permissions or repo name)${NC}"
        continue
    fi
    
    # Determine JSON fields based on configuration
    json_fields="number,title,author,headRefName,url,isDraft,reviews"
    if [ ${#REQUESTED_REVIEWERS[@]} -gt 0 ]; then
        json_fields="${json_fields},reviewRequests"
    fi
    
    # Get all open PRs (with optional draft filtering) and store in temporary file
    temp_prs_file=$(mktemp)
    if [ "$INCLUDE_DRAFTS" = "true" ]; then
        # Include all PRs (drafts and non-drafts)
        gh pr list \
            --repo "$repo" \
            --state open \
            --limit 100 \
            --json "$json_fields" | \
        jq -r '.[] | @json' > "$temp_prs_file"
    else
        # Exclude draft PRs (default behavior)
        gh pr list \
            --repo "$repo" \
            --state open \
            --limit 100 \
            --json "$json_fields" | \
        jq -r '.[] | select(.isDraft == false) | @json' > "$temp_prs_file"
    fi
    
    # Process each PR from the temporary file
    while IFS= read -r pr_json; do
        # Parse PR data
        pr_number=$(echo "$pr_json" | jq -r '.number')
        pr_title=$(echo "$pr_json" | jq -r '.title')
        pr_author=$(echo "$pr_json" | jq -r '.author.login')
        pr_branch=$(echo "$pr_json" | jq -r '.headRefName')
        pr_url=$(echo "$pr_json" | jq -r '.url')
        pr_is_draft=$(echo "$pr_json" | jq -r '.isDraft')
        pr_reviews=$(echo "$pr_json" | jq -r '.reviews')
        pr_review_requests=$(echo "$pr_json" | jq -r '.reviewRequests // empty')
        
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
        
        # Check if PR has requested reviewers we're monitoring
        if has_requested_reviewers "$pr_review_requests"; then
            if [ -z "$match_reason" ]; then
                match_reason="reviewer"
            else
                match_reason="multiple"
            fi
        fi
        
        # Skip if no match
        if [ -z "$match_reason" ]; then
            continue
        fi
        
        # Skip if user is the author of this PR
        if [ -n "$GITHUB_USER_HANDLE" ] && [ "$pr_author" = "$GITHUB_USER_HANDLE" ]; then
            echo "  • PR #${pr_number} is authored by ${GITHUB_USER_HANDLE} - skipping (${pr_branch})"
            continue
        fi
        
        # Check if user has already approved this PR
        if user_has_approved "$pr_reviews" "$GITHUB_USER_HANDLE"; then
            echo "  • PR #${pr_number} already approved by ${GITHUB_USER_HANDLE} (${pr_author} - ${pr_branch})"
            continue
        fi
        
        # Check if PR has failed automated checks
        if should_filter_pr_for_failed_checks "$repo" "$pr_number"; then
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
        elif [ "$match_reason" = "reviewer" ]; then
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (requested reviewer)${draft_indicator}${NC}"
        elif [ "$match_reason" = "both" ]; then
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (team member: ${pr_author}, branch: ${pr_branch})${draft_indicator}${NC}"
        elif [ "$match_reason" = "multiple" ]; then
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (multiple criteria)${draft_indicator}${NC}"
        else
            echo -e "${GREEN}  ✓ Found new PR #${pr_number} (team member: ${pr_author}, branch: ${pr_branch})${draft_indicator}${NC}"
        fi
        echo "    Title: ${pr_title}"
        
        # Add PR to notification list (pipe-separated format)
        prs_to_notify="${prs_to_notify}${pr_number}|${pr_title}|${pr_author}|${pr_branch}|${pr_url}|${repo}|${match_reason}|${pr_is_draft}\n"
        
        # Mark PR as processed (only if not in ALWAYS_NOTIFY mode)
        if [ "$ALWAYS_NOTIFY" != "true" ]; then
            echo "$pr_id" >> "$PROCESSED_PRS_FILE"
        fi
        new_notifications=$((new_notifications + 1))
    done < "$temp_prs_file"
    
    # Clean up temporary file
    rm -f "$temp_prs_file"
done

# Send consolidated notification if there are PRs to notify about
if [ $new_notifications -gt 0 ]; then
    if [ "$ALWAYS_NOTIFY" = "true" ]; then
        echo -e "\n${BLUE}Sending consolidated notification for ALL ${new_notifications} matching PR(s) (ALWAYS_NOTIFY enabled)...${NC}"
    else
        echo -e "\n${BLUE}Sending consolidated notification for ${new_notifications} new PR(s)...${NC}"
    fi
    
    if send_consolidated_slack_notification "$prs_to_notify" "$new_notifications"; then
        echo -e "${GREEN}✓ Consolidated notification sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send consolidated notification${NC}"
    fi
fi

# Clean up old processed PRs (keep only last MAX_PROCESSED_PRS entries)
if [ $(wc -l < "$PROCESSED_PRS_FILE") -gt $MAX_PROCESSED_PRS ]; then
    tail -$MAX_PROCESSED_PRS "$PROCESSED_PRS_FILE" > "$PROCESSED_PRS_FILE.tmp" && mv "$PROCESSED_PRS_FILE.tmp" "$PROCESSED_PRS_FILE"
fi

# Summary
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $new_notifications -gt 0 ]; then
    if [ "$ALWAYS_NOTIFY" = "true" ]; then
        echo -e "${GREEN}✓ Found ${new_notifications} matching PR(s) for notification (ALWAYS_NOTIFY enabled)${NC}"
    else
        echo -e "${GREEN}✓ Found ${new_notifications} new PR(s) for notification${NC}"
    fi
else
    echo "No team PRs to notify about"
fi
echo -e "Total team PRs open: ${total_prs}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Log summary with timestamp
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checked ${#REPOS[@]} repos, found ${total_prs} team PRs, sent ${new_notifications} notifications" >> "${LOGS_DIR}/check_summary.log"