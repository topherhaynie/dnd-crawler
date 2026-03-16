# General Coding Instructions

This file provides recommended coding practices for this repository. Place project-specific or language-specific conventions in separate instruction files and keep them concise.

1. Typing and Return Types
- Prefer explicit type annotations for functions, parameters, and variables where helpful for clarity and static analysis. Example in GDScript:
  - Use `func compute(value: int) -> float:` rather than untyped signatures.
- When returning complex structures (Dictionary, Array, Image, PackedByteArray), annotate return types when practical or document the shape in the docstring.
- Use `as` casts when receiving generic or untyped values from registries, singletons, or external sources to satisfy the analyzer and make intent explicit.

2. Indentation and Formatting
- Use 4 spaces per indent level for GDScript and most repository files. Do not mix tabs and spaces within a file.
- Keep line length reasonable (≈120 chars). Prefer breaking complex expressions across lines.
- Keep whitespace consistent: single space after commas and around binary operators.

3. Function Structure and Small Helpers
- Keep functions focused. If a function grows beyond ~80–120 lines, consider extracting helper methods.
- Name helper functions clearly and keep them private (leading underscore) if they're internal to a module.

4. Error Handling and Early Returns
- Validate inputs early and return quickly for invalid or no-op cases. This keeps the main flow clearer.

5. Backwards-Compatibility and Migration Edits
- When refactoring or migrating APIs (e.g., moving functionality into services), prefer adding delegating shims in the old location that forward to new services while retaining a fallback implementation.
- Ensure new behavior preserves legacy return types unless you update all consumers simultaneously.

6. Static Analysis and Tests
- Run the project's static analyzer and unit/smoke tests after edits. Fix analyzer warnings before committing, especially those flagged as errors in CI.

7. Commit Hygiene and PRs
- Make small, reviewable commits focused on a single intent. Describe the motivation and test/verification steps in the PR description.

8. Requirement: Resolve Workspace Problems Caused by Edits
- Whenever you modify files, run the analyzer and test suite, and resolve any reported problems before finalizing the change. If your edit introduces new warnings or errors, address them in the same branch/PR rather than leaving them for later.

9. Language-Specific Notes (GDScript)
- Avoid using parameter/local name `visible` in Node2D/CanvasItem scripts to prevent shadowing base-class names.
- Annotate temporaries created from `Dictionary.get()` calls with `var tmp: Variant = dict.get("key")` where needed to avoid inferred-Variant warnings when `warnings-as-errors` is enabled.
- Use `get_node_or_null()` to safely acquire nodes and check for null before calling methods.

If you need to document additional conventions (C#, project-specific CI quirks, etc.), add separate files under `.github/instructions/` and reference them from here.
