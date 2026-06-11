#!/bin/bash
# Read the JSON input from Claude Code
input=$(cat)

# Extract basic fields
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Extract token counts
IN_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Context usage bar calculation
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
BAR_SIZE=10
FILLED=$(awk -v p="$PCT" -v b="$BAR_SIZE" 'BEGIN {print int(p * b / 100)}')
EMPTY=$((BAR_SIZE - FILLED))

# Build the progress bar string with a check for 0
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "█%.0s" $(seq 1 $FILLED))
[ "$EMPTY" -gt 0 ] && BAR+=$(printf "░%.0s" $(seq 1 $EMPTY))

# Define colors using \e for printf compatibility
CYAN='\e[36m'; GREEN='\e[32m'; YELLOW='\e[33m'; RED='\e[31m'; RESET='\e[0m'

if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

    # Use %b inside the variable string or build it here
    [ "$STAGED" -gt 0 ] && STAGED_DISPLAY=" +${STAGED}"
    [ "$MODIFIED" -gt 0 ] && MODIFIED_DISPLAY=" ~${MODIFIED}"

    BRANCH_DISPLAY=" 🌿 $BRANCH $GIT_STATUS"
else
    BRANCH_DISPLAY=""
    STAGED_DISPLAY=""
    MODIFIED_DISPLAY=""
fi

# Use %b to interpret the color escape codes
printf " %b%s%b | 📁 %s%s%b%s%b%b%s%b\n%s %d%% | 💰 \$%.2f | ⬆ %s ⬇ %s\n" \
    "$CYAN" "$MODEL" "$RESET" \
    "${DIR##*/}" \
    "$BRANCH_DISPLAY" \
    "$GREEN" "$STAGED_DISPLAY" "$RESET" \
    "$YELLOW" "$MODIFIED_DISPLAY" "$RESET" \
    "$BAR" "$PCT" "$COST" "$IN_TOKENS" "$OUT_TOKENS"
