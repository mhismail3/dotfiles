#!/bin/bash
# Claude Code status line - shows token usage, cost, and context info
# Receives JSON via stdin with session metrics

input=$(cat)

# Parse key values once
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Current context usage
CURRENT_IN=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# Calculate context percentage (current context window usage)
CURRENT_CONTEXT=$((CURRENT_IN + CACHE_CREATE + CACHE_READ))
if [ "$CONTEXT_SIZE" -gt 0 ]; then
    CONTEXT_PCT=$((CURRENT_CONTEXT * 100 / CONTEXT_SIZE))
else
    CONTEXT_PCT=0
fi

# Format tokens as K for readability
format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $tokens / 1000000" | bc)"
    elif [ "$tokens" -ge 1000 ]; then
        printf "%.1fK" "$(echo "scale=1; $tokens / 1000" | bc)"
    else
        echo "$tokens"
    fi
}

# Format cost
if [ "$(echo "$COST > 0" | bc -l)" -eq 1 ]; then
    COST_FMT=$(printf "\$%.2f" "$COST")
else
    COST_FMT="\$0.00"
fi

# Format token counts
TOTAL_IN_FMT=$(format_tokens "$TOTAL_IN")
TOTAL_OUT_FMT=$(format_tokens "$TOTAL_OUT")

# Context bar indicator (visual representation)
if [ "$CONTEXT_PCT" -lt 25 ]; then
    CTX_INDICATOR="$CONTEXT_PCT%"
elif [ "$CONTEXT_PCT" -lt 50 ]; then
    CTX_INDICATOR="$CONTEXT_PCT%"
elif [ "$CONTEXT_PCT" -lt 75 ]; then
    CTX_INDICATOR="$CONTEXT_PCT%"
else
    CTX_INDICATOR="$CONTEXT_PCT%!"
fi

# Output: Model | Cost | Tokens (in/out) | Context %
echo "$MODEL | $COST_FMT | ${TOTAL_IN_FMT}/${TOTAL_OUT_FMT} | ctx:$CTX_INDICATOR"
