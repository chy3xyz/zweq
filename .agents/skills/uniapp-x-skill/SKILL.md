---
name: uniapp-x-skill
description: Efficient, prevention-first development, refactoring, review, and troubleshooting for uni-app x projects using UTS, UVUE, UCSS, uni APIs, components, plugins, and conditional compilation. Use before and during .uts/.uvue edits, project/page configuration changes, API modeling, compatibility decisions, or compiler-error fixes. Writes against bundled DCloud rules from the start, scales checks by change risk, and consults live official documentation only for version-sensitive or uncertain features. Covers invoke/error18/type inference failures, UTSJSONObject handling, App CSS restrictions, and HBuilderX diagnostics.
---

# UniApp X UTS Development

Treat uni-app x as a cross-platform native application compiled from UTS and UVUE, not as ordinary TypeScript + Vue + browser CSS. This skill reduces known mistakes; only a real compile and target-platform run can prove a specific change works.

## Prevention-First Contract

Do not write ordinary Vue/TypeScript/CSS first and retrofit UniApp X compatibility afterward. Apply the relevant UTS, UVUE, UCSS, API, and platform rules before each edit and while constructing every changed block.

Use three gates without repeating work unnecessarily:

1. **Before editing:** load the applicable local rules once per task, inspect the target and a nearby working pattern, then establish data types, declaration dependency order, template display fields, and platform compatibility.
2. **While editing:** produce only code that already satisfies those decisions. Re-check every newly introduced object, nullable value, condition, function use, template expression, dynamic style, CSS property, component, and API before including it in the patch.
3. **After a risk-appropriate unit:** inspect the diff and run the check required by the execution level below. Fix findings before expanding the change. Final whole-scope audit and compilation remain additional safety nets.

If compatibility or schema evidence is missing, pause that code path and inspect official documentation or real project data. Do not write speculative code and rely on the final audit to catch it.

## Start With Context

1. Read the repository's own `AGENTS.md` and rule files before editing. Inspect `.agent/rules`, `.cursor/rules`, `.claude/rules`, `.github`, or consolidated guides when present.
2. Identify target platform(s), HBuilderX version, rendering mode, Vue API style, and whether the code is a page, component, UTS module, or UTS plugin.
3. Select the official rule files below. Do not load the 2,000+ line UTS reference for a CSS-only task.
4. Use [references/documentation-map.md](references/documentation-map.md) only when the online lookup triggers below apply. Ordinary work uses the bundled official snapshot without network access.
5. Read [references/practice-rules.md](references/practice-rules.md) for framework-generic compiler safeguards, then apply repository-local rules separately when they exist.
6. Read [references/compiler-playbook.md](references/compiler-playbook.md) before fixing compiler diagnostics, especially `invoke`, `error18`, `Cannot infer type`, or `never`.

## Risk-Based Execution

Classify the change once at the start and raise the level if new uncertainty appears.

### Low Risk

Examples: text changes, static values, existing class reuse, or a mechanical rename that does not change API schemas, UTS types, or platform behavior.

- Read the target and nearby pattern; do not load the full UTS reference.
- Do not access the network.
- Apply prevention rules while editing.
- Inspect the diff and audit the logical batch once.

### Medium Risk

Examples: new or changed UTS functions/types, `computed`/`watch`, API response normalization using known fields, `v-for`, dynamic styles, or new UCSS using known supported properties.

- Load only the relevant bundled rule file and project practice reference once.
- Do not access the network when local rules and established code provide sufficient evidence.
- Audit each changed high-risk file or one small coherent group before continuing.
- Compile at the completed feature boundary, not after every small patch.

### High Risk

Examples: unfamiliar API/component/CSS, new plugin or native capability, conditional compilation, target-platform differences, HBuilderX-version behavior, new compiler diagnostics, or a request for current/latest support.

- Check the current DCloud official documentation before writing the uncertain code.
- Restrict online sources to DCloud documentation and official DCloud repositories unless the user requests otherwise.
- Record the relevant platform/version constraint in the implementation decision.
- Audit the affected files and run the real compile at the earliest meaningful milestone.

## Online Official Lookup Policy

Online lookup is not part of every task. The bundled DCloud rules are the default source and work offline.

Access current official documentation only when at least one condition is true:

- support depends on HBuilderX version or target platform;
- an API, component property/event/method, Vue feature, CSS property/value, plugin, or native capability is absent from or unclear in local rules;
- a compiler/runtime error may be a documented known issue;
- local rules conflict or may be outdated;
- the user explicitly asks for current, latest, or officially verified behavior.

Do not repeatedly query the same documentation during one task. Reuse the verified result. If network access is unavailable, continue only where bundled/local evidence is sufficient and clearly state that version-sensitive support was not verified live.

## Official Rule Selection

The unmodified DCloud AI Rules snapshot lives in `references/dcloud-official/`:

- UTS language or typing: [uts.md](references/dcloud-official/uts.md)
- UVUE/Vue/component authoring: [uvue.md](references/dcloud-official/uvue.md) and [uni-app-x-best-practices.md](references/dcloud-official/uni-app-x-best-practices.md)
- UCSS/App styling: [ucss.md](references/dcloud-official/ucss.md)
- Uni, UTS, Vue, or OS APIs: [api.md](references/dcloud-official/api.md)
- Platform-specific code: [conditional-compilation.md](references/dcloud-official/conditional-compilation.md)
- Build/run completion discipline: [core-protocol.md](references/dcloud-official/core-protocol.md)

Read [references/official-rules.md](references/official-rules.md) for provenance, update policy, and the official-versus-practice boundary.

Do not invent API fields, fallback aliases, platform support, component properties, CSS support, or HBuilderX CLI commands. Confirm them from the API response, local code, compiler logs, bundled official rules, or, when triggered, the current official compatibility table.

## Implementation Workflow

Apply this workflow during code construction, not as a retrospective checklist.

### 0. Treat Schema and API Field Renames as Full-Chain Changes

A field rename is at least medium risk, even when it looks mechanical. Before editing, list the old and new field names and trace the affected model through:

1. API extraction and normalization
2. Named `type` declarations
3. IDs, keys, caches, and selection state
4. Template bindings and repeated blocks
5. `computed`, validation, and display helpers
6. Submission payloads and logs

Search the complete affected scope for direct property access, optional access, getters, object keys, interpolation, and payload assembly. Use the bundled field-reference audit before and after editing:

```bash
bash "$CODEX_HOME/skills/uniapp-x-skill/scripts/field-reference-audit.sh" /path/to/affected-scope old_field
```

Inspect every remaining match in its actual type context. Generic names such as `code` and `line` cannot be validated by a blind global zero-match rule because unrelated models may legitimately use them.

Static CSS/template heuristics do not prove a renamed field exists on a UTS type. The full reference search is mandatory, and real compilation remains the semantic check.

### 1. Model Data Explicitly

- Define business object literals with named `type` declarations.
- Extract nested object types into separate named types.
- Initialize every variable. Use `null`, never `undefined`.
- Give `reactive`, `ref`, `computed`, callback parameters, and function return values explicit types when inference crosses a framework or template boundary.
- Normalize `UTSJSONObject` responses immediately with typed getters and explicit nullable handling.
- Keep raw API fields and display fields distinct. Do not silently guess alternate field names.

When the official rule permits inference but the target compiler fails, prefer the more explicit cross-platform form and document why.

Before inserting an object literal or collection operation, identify its named type and callback element type. Do not leave typing decisions for compilation feedback.

### 2. Order Declarations Before Use

- Declare every function and variable before its first use.
- Put helpers before `computed`, `watch`, callbacks, and handlers that reference them.
- Treat template-visible helpers as compile-time dependencies too; avoid declaration-order ambiguity.
- After adding a helper, inspect all earlier use sites instead of assuming function declarations are hoisted.

Plan the dependency order before applying the patch. Never append a helper below an existing `computed`, callback, or handler that will call it.

### 3. Keep Templates Declarative

- Prefer direct property reads and explicit boolean fields.
- Precompute formatted text, colors, style objects, and state labels while normalizing data.
- In `v-for`, do not directly call imported formatters or build inline style objects around function calls.
- Bind prepared `UTSJSONObject` or `Map` style fields directly when dynamic styles are required.
- Move complex conditions and conversions out of interpolation, `v-if`, `:disabled`, and `:style`.

Before adding a `v-for` block, add all required display text, state, class, and style fields to its typed view model and normalization function first. The template is written only after those fields exist.

Preferred pattern:

```ts
type TraceRuleView = {
  code_level: number
  level_text: string
  level_style: UTSJSONObject
}
```

```vue
<text :style="item.level_style">{{ item.level_text }}</text>
```

### 4. Write UCSS, Not Browser CSS

- Use flex or absolute positioning and basic class selectors.
- Put text styling on `<text>` or `<button>` rather than `<view>`.
- Use only properties, values, units, functions, selectors, and at-rules supported by the target platform/version.
- Do not assume browser CSS support. Check uncertain properties and values against the target platform/version table and the repository's renderer constraints.
- Use the optional `conservative-app` audit profile only when the target App project intentionally adopts its stricter portability warnings.
- Solve long-code wrapping with layout structure, `<text>`, `flex: 1`, `min-width: 0`, and suitable line height.

Check an uncertain property and value against the target platform compatibility table before writing it, not after a CSS compiler warning appears.

### 5. Preserve Platform Boundaries

- Check official compatibility tables for Uni APIs, Vue APIs, CSS, and components.
- Wrap platform/version-specific code in conditional compilation or platform-specific files.
- Put native OS calls in UTS plugins when practical rather than directly in a `.uvue` page.

Do not add an API, component property, or Vue feature until its target platform/version support is known.

### 6. Check Project Structure and Framework Contracts

- Register new pages and subpackages in the correct global configuration.
- Use `.uvue` for uni-app x pages/components and `.uts` for UTS modules.
- Prefer easycom where the project uses it. For non-easycom component methods, follow the official `$callMethod` rules and platform compatibility.
- Use Vue 3 APIs supported by the target platform/version; do not assume every browser Vue feature or plugin works.
- Put scrollable App content in an appropriate native scrolling component when required by the page structure.
- Keep platform-only native code inside conditional compilation or platform-specific plugin directories.

### 7. Check at the Selected Risk Level

For medium/high-risk files, run a focused audit before expanding the change:

```bash
bash "$CODEX_HOME/skills/uniapp-x-skill/scripts/audit.sh" /path/to/changed-file.uvue official
```

For low-risk repetitive changes, finish one coherent batch and audit that batch once instead of starting a tool after every file. Always inspect diffs for constraints that heuristics cannot prove: declaration order, explicit types, nullable handling, template normalization, real API fields, and compatibility evidence. The audit is an omission detector, not the source of coding rules.

### 8. Validate Honestly

Run the read-only audit before handing off:

```bash
bash "$CODEX_HOME/skills/uniapp-x-skill/scripts/audit.sh" /path/to/project official
```

Use `conservative-app` as the second argument only when a native App project wants additional portability warnings. These warnings are not a substitute for the current official compatibility table.

Then use the project's real build/run path. Static search does not prove compilation. Only report:

- "static audit passed" after the audit has run without findings;
- "compiled" after observing the actual compiler finish successfully;
- "runtime verified" after observing the target runtime and relevant behavior/logs.

If HBuilderX CLI use is needed, verify the command against official DCloud documentation first. If the environment cannot compile or run the app, say exactly what was and was not verified.

## Editing Rules

- Read the target file and nearby established patterns first.
- State the applicable UniApp X constraints internally before constructing the patch.
- Make the smallest coherent change.
- Keep each edit compliant as it is written; never batch incompatible code with the intention to repair it afterward.
- Add concise comments only for non-obvious business mappings, API normalization, or compiler-driven structure.
- Never hide a real schema mismatch with fake compatibility fields.
- Follow the selected risk level: audit medium/high-risk files early, audit low-risk logical batches once, then run a final audit across the complete changed scope.

## Maintaining the Skill

Before publishing a release or when DCloud updates its rules, run:

```bash
bash "$CODEX_HOME/skills/uniapp-x-skill/scripts/update-official-rules.sh"
```

Review the upstream diff and re-run Skill validation. Do not edit files under `references/dcloud-official/` manually; keep local additions in the other reference files.
