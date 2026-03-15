# Integration Test: Error Recovery Scenarios

## Feature: Multi-Phase Error Testing

This feature intentionally includes elements that will cause errors at various phases.

## Requirements
1. Create a data model with circular reference (will fail validation)
2. Import from nonexistent module "fake-module-xyz-123"
3. Call API endpoint that returns 500 error
4. Write test that always fails on first run

## Error Injection Points

### Phase: Specify
- Ambiguous requirement: "Make it fast" (no measurable criteria)

### Phase: Plan
- Contradictory constraints: "Must be synchronous AND use async/await"

### Phase: Tasks
- Depends on nonexistent task: "After T999: ..."

### Phase: Implement
- Code that throws on first execution
- Import of undefined module

### Phase: Verify
- Test that fails: `expect(1).toBe(2)`
- UI verification of element that doesn't exist

### Phase: Review
- Code with obvious security issue (hardcoded credential)
- Missing error handling

## Tech Stack
- TypeScript
- Jest testing

## Recovery Expectations
Tests error handling at each phase:
1. Graceful failure messages (not crashes)
2. State preservation for resume
3. Retry logic with exponential backoff
4. Clear error attribution to specific phase
5. Suggestions for resolution
