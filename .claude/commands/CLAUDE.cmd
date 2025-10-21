# Code Quality Standards

When writing or modifying code in this project:

## Code Cleanliness Rules

1. **NO Unnecessary Comments**
   - Remove inline comments that just repeat what the code does
   - Only add comments for:
     - Complex business logic that isn't obvious
     - Why a non-obvious decision was made
     - TODO or FIXME for future work
   - NEVER add comments like `// Store the value` or `// Return result`

2. **NO Dead Code**
   - Remove unused functions, variables, and imports immediately
   - Don't leave commented-out code "just in case"
   - If code isn't called anywhere, DELETE it

3. **NO Code Bloat**
   - Keep files focused and concise
   - Extract repeated logic into helper functions
   - Don't duplicate code - reuse existing functions
   - Remove deprecated code paths

4. **NO Spaghetti Code**
   - One responsibility per function
   - Clear function names that describe what they do
   - Avoid deeply nested conditionals (max 3 levels)
   - Use early returns to reduce nesting

5. **Code Organization**
   - Group related functionality together
   - Separate concerns (UI, business logic, data)
   - Remove duplicate implementations
   - Consolidate similar functions

## When Refactoring

1. **Before adding new code:**
   - Check if similar functionality already exists
   - Remove deprecated alternatives first
   - Clean up the area you're working in

2. **After making changes:**
   - Remove any code that became obsolete
   - Delete unused imports
   - Simplify conditional logic where possible
   - Remove debug logs that are no longer needed

3. **File length limits:**
   - If a file exceeds 500 lines, consider splitting it
   - Extract helper functions to separate files
   - Create focused, single-purpose modules

## Examples of What to Remove

### ❌ Bad (unnecessary comments):
```dart
// Set the name
final name = 'John';

// Check if connected
if (isConnected) {
  // Send the message
  sendMessage(msg);
}
```

### ✅ Good (clean, self-documenting):
```dart
final name = 'John';

if (isConnected) {
  sendMessage(msg);
}
```

### ❌ Bad (dead code):
```dart
// Old approach (not used anymore)
// void oldFunction() {
//   // ... 100 lines of code
// }

void newFunction() {
  // Implementation
}
```

### ✅ Good (removed):
```dart
void newFunction() {
  // Implementation
}
```

### ❌ Bad (spaghetti):
```dart
void processData(data) {
  if (data != null) {
    if (data.isValid) {
      if (data.hasItems) {
        for (var item in data.items) {
          if (item.active) {
            // Deep nesting...
          }
        }
      }
    }
  }
}
```

### ✅ Good (early returns):
```dart
void processData(data) {
  if (data == null || !data.isValid || !data.hasItems) return;

  for (var item in data.items.where((i) => i.active)) {
    processItem(item);
  }
}

void processItem(item) {
  // Extracted logic
}
```

## Code Review Checklist

Before completing a task, verify:
- [ ] No commented-out code blocks
- [ ] No unused functions or variables
- [ ] No unnecessary inline comments
- [ ] No duplicate implementations
- [ ] Files are reasonably sized (<500 lines preferred)
- [ ] Functions have single, clear responsibilities
- [ ] Code is self-documenting with good naming
- [ ] Imports are cleaned up (no unused imports)

## Priority Actions for This Codebase

Current issues to fix:
1. Remove unused socket functions in MainActivity.kt (lines 374-650+)
2. Remove MAC address validation code that's no longer used
3. Clean up duplicate handshake implementations
4. Remove legacy identifier code paths
5. Consolidate message routing logic

**Remember:** Less code = less bugs = easier maintenance = faster development
