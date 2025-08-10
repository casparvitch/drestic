#!/bin/bash
set -euo pipefail

ENV_FILE="$1"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file not found: $ENV_FILE"
    exit 1
fi

echo "Current Gotify configuration:"
grep -E "^GOTIFY_(URL|TOKEN)=" "$ENV_FILE" || echo "No Gotify configuration found"
echo

read -rp "Enter new Gotify URL (no trailing slash, e.g. https://gotify.example.com): " GOTIFY_URL
if [ -n "$GOTIFY_URL" ]; then
    # Validate URL format
    if [[ ! "$GOTIFY_URL" =~ ^https?:// ]]; then
        echo "Error: Invalid URL format (must start with http:// or https://)"
        exit 1
    fi
    
    # Test URL reachability
    echo "Testing Gotify server connectivity..."
    if ! curl -s --connect-timeout 10 "$GOTIFY_URL/health" >/dev/null 2>&1; then
        echo "Warning: Cannot reach Gotify server at $GOTIFY_URL"
        echo "This might be due to network issues or incorrect URL."
        read -rp "Continue anyway? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    else
        echo "✓ Gotify server is reachable"
    fi
    
    read -rp "Enter new Gotify token: " GOTIFY_TOKEN
    
    # Test token if both URL and token are provided
    if [ -n "$GOTIFY_TOKEN" ]; then
        echo "Testing Gotify token..."
        if curl -sS "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
            -F "title=DRestic Config Test" \
            -F "message=Testing Gotify configuration - you can ignore this message" \
            -F "priority=1" >/dev/null 2>&1; then
            echo "✓ Test notification sent successfully!"
        else
            echo "Warning: Failed to send test notification. Please verify your token."
            read -rp "Continue anyway? [y/N]: " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 1
            fi
        fi
    fi
else
    GOTIFY_TOKEN=""
fi

# Update or add Gotify settings
sed -i '/^GOTIFY_URL=/d' "$ENV_FILE"
sed -i '/^GOTIFY_TOKEN=/d' "$ENV_FILE"
echo "GOTIFY_URL=\"$GOTIFY_URL\"" >> "$ENV_FILE"
echo "GOTIFY_TOKEN=\"$GOTIFY_TOKEN\"" >> "$ENV_FILE"

echo "✓ Gotify configuration updated!"
if [ -n "$GOTIFY_URL" ]; then
    echo "Test with: make test-remote-gotify"
else
    echo "Gotify notifications disabled"
fi
