#!/bin/bash
# Verify L1 benchmark task completion
set -e

TASK_DIR="$1"
cd "$TASK_DIR"

RESULTS_FILE="${2:-verify-results.json}"
PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

run_check() {
    local type="$1"
    local name="$2"
    local command="$3"

    echo -n "  [$type] $name... "

    if eval "$command" > /dev/null 2>&1; then
        echo "PASS"
        RESULTS+=("{\"type\":\"$type\",\"name\":\"$name\",\"passed\":true}")
        ((PASS_COUNT++))
    else
        echo "FAIL"
        RESULTS+=("{\"type\":\"$type\",\"name\":\"$name\",\"passed\":false}")
        ((FAIL_COUNT++))
    fi
}

echo "Running verifications..."

# Start server in background for API tests
npm run build > /dev/null 2>&1
node dist/index.js &
SERVER_PID=$!
sleep 2

# TEST: Unit tests pass
run_check "TEST" "unit-tests-pass" "npm test"

# API: Health endpoint exists and responds
run_check "API" "health-endpoint-responds" "curl -sf http://localhost:3000/health | jq -e '.status'"

# API: Returns required fields
run_check "API" "health-returns-required-fields" "curl -sf http://localhost:3000/health | jq -e '.uptime and .memory and .database and .version'"

# API: Status is valid enum
run_check "API" "health-status-valid" "curl -sf http://localhost:3000/health | jq -e '.status | . == \"healthy\" or . == \"degraded\" or . == \"unhealthy\"'"

# CLI: No TypeScript errors
run_check "CLI" "no-typescript-errors" "npx tsc --noEmit"

# Cleanup
kill $SERVER_PID 2>/dev/null || true

# Calculate passed rate
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $TOTAL -gt 0 ]; then
    PASSED_RATE=$(echo "scale=2; $PASS_COUNT / $TOTAL" | bc)
else
    PASSED_RATE="0"
fi

# Write results
cat > "$RESULTS_FILE" << EOF
{
  "passed": $PASS_COUNT,
  "failed": $FAIL_COUNT,
  "total": $TOTAL,
  "passed_rate": $PASSED_RATE,
  "resolved": $([ $FAIL_COUNT -eq 0 ] && echo "true" || echo "false"),
  "verifications": [$(IFS=,; echo "${RESULTS[*]}")]
}
EOF

echo ""
echo "Results: $PASS_COUNT/$TOTAL passed ($(echo "$PASSED_RATE * 100" | bc)%)"
echo "Resolved: $([ $FAIL_COUNT -eq 0 ] && echo "YES" || echo "NO")"

exit $FAIL_COUNT
