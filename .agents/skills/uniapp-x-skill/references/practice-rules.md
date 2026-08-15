# Cross-Project Compiler-Safe Practices

These practices are framework-generic lessons from real UniApp X compiler failures. They supplement DCloud rules without introducing application-specific business behavior or visual design requirements.

## Source Inspection

- Read repository instructions and the nearest working implementation before editing.
- Treat duplicated AI-rule directories as possible copies; identify one canonical local source before loading all of them.
- Inspect real API responses and contracts before defining models or payload fields. Do not add guessed aliases or fake fallback fields.

## API Schema Changes

- Treat field additions, removals, and renames as full-chain changes.
- Trace normalization, explicit types, IDs/keys, state, templates, computed values, validation, payloads, logs, and tests.
- Run `scripts/field-reference-audit.sh` before and after a rename, then inspect each result in its type context.
- Do not claim a schema rename is complete based only on text replacement or CSS/template heuristic audits.

## UTS Conventions

- Initialize variables and represent absence with `null`.
- Prefer explicit named `type` declarations for API models, view models, forms, and payloads.
- Extract nested object types into separately named types.
- Add explicit types to reactive values, computed returns, callback parameters, collections, and normalization helpers when data crosses API/template boundaries.
- Use explicit boolean comparisons rather than truthy/falsy expressions.
- Normalize `UTSJSONObject` near the API boundary and handle nullable getters explicitly.

## Declaration Order

Composition API code should be ordered by dependency because local-scope helpers can fail when used before declaration on some targets.

1. Types and constants
2. Pure conversion and formatting helpers
3. API normalization helpers
4. Reactive state
5. Derived helpers
6. `computed` and `watch` values
7. Event handlers and lifecycle functions

After moving one helper, inspect its dependencies and reorder the chain rather than hiding the error with wrappers or broad casts.

## Template Boundary

- Prefer normalized display fields over data conversion in templates.
- Avoid imported formatter calls in repeated template blocks when a typed display field can be prepared during normalization.
- Precompute dynamic text, state, classes, colors, and style objects when template inference becomes fragile.
- Bind a typed `UTSJSONObject` or `Map` style value instead of combining an inline object with function calls.
- Keep conditions explicitly boolean and template property chains shallow.

## UCSS Portability

- Check CSS properties, values, selectors, units, functions, and at-rules against the actual target platform/version.
- Prefer the target renderer's documented layout model instead of translating browser CSS mechanically.
- Put text styling on the text-bearing component when required by the App renderer.
- Treat `conservative-app` audit findings as portability review items, not universal DCloud errors.

## Verification

- Static audits find known patterns; they do not type-check templates or prove platform compatibility.
- Compilation proves only that the selected build target accepted the code.
- Runtime claims require observation on the relevant target platform.
- Never invent HBuilderX CLI commands; verify current syntax from DCloud documentation.
