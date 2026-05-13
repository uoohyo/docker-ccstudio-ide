#!/bin/bash
# Verify CCS v20.0.x patches were applied correctly

set -e

echo "🧪 Verifying CCS v20.0.x patches..."

# Only test if this is a v20.0.x version
if [ "$CCS_VERSION" != "20.0.0.00012" ] && \
   [ "$CCS_VERSION" != "20.0.1.00004" ] && \
   [ "$CCS_VERSION" != "20.0.2.00005" ]; then
    echo "✅ Not a v20.0.x version, skipping patch verification"
    exit 0
fi

SCRIPT="/opt/ti/ccs/eclipse/ccs-server-cli.sh"

# 1. Check shell syntax fixed
if ! grep -q ' == ' "$SCRIPT"; then
    echo "✅ Shell syntax fixed (no == operators found)"
else
    echo "❌ Still contains == operators"
    exit 1
fi

# 2. Check plugins symlink
if [ -L "/home/plugins" ] && [ -d "/opt/ti/ccs/eclipse/plugins" ]; then
    echo "✅ Plugins path fallback exists"
else
    echo "⚠️  Plugins symlink missing (may still work)"
fi

# 3. Check Node.js in PATH
if command -v node >/dev/null 2>&1; then
    echo "✅ Node.js available: $(node --version)"
else
    echo "❌ Node.js not found in PATH"
    exit 1
fi

# 4. Check backup exists
if [ -f "$SCRIPT.orig" ]; then
    echo "✅ Original script backed up"
else
    echo "⚠️  No backup found"
fi

echo "🎉 All v20.0.x patches verified successfully!"
