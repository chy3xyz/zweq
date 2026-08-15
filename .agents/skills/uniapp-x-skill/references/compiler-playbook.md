# UniApp X Compiler Playbook

Follow the diagnostic order instead of treating UTS as ordinary TypeScript.

## `找不到名称 ... error18`

1. Find the first use and declaration of the missing name.
2. Move the complete declaration before every use, including `computed`, callbacks, and template-facing helpers.
3. Check whether a moved helper now references another later declaration; reorder the dependency chain, not just one function.
4. Ensure the symbol is in the same `<script setup>` scope and not hidden by conditional compilation.
5. Compile again before attempting type casts or fallback wrappers.

Do not assume a `function` declaration is hoisted.

## `invoke`, `Function invocation expected`, or Template Generic Inference Errors

Typical risky shape:

```vue
<view v-for="item in items">
  <text :style="{ color: importedFilter(item.level) }">
    {{ formatItem(item) }}
  </text>
</view>
```

Fix by moving both formatting and style construction into typed normalization:

```ts
type ItemView = {
  label: string
  label_style: UTSJSONObject
}
```

```vue
<text :style="item.label_style">{{ item.label }}</text>
```

Then verify:

- callback parameter types are explicit;
- arrays have concrete element types rather than `Array<UTSJSONObject>` where a domain type is known;
- helper return types are explicit;
- no imported function is called directly from the repeated template block;
- no inline object literal forces the template compiler to infer a generic style value.

## `Cannot infer type`, `Not enough information to infer type argument`

1. Add a named type for the object/array element.
2. Type callback parameters explicitly: `(item : ItemType) => { ... }`.
3. Type local collections explicitly before `find`, `filter`, `map`, or `forEach`.
4. Replace clever chained expressions with typed local variables and explicit branches.
5. Move dynamic display calculation out of the template.

Avoid fixing inference by broadly casting to `any`; it usually moves the failure to another platform boundary.

## `Property ... does not exist on type never`

This commonly follows callback-based assignment where the compiler cannot prove a nullable variable was set.

Prefer an index or direct typed lookup:

```ts
let matchedIndex = -1
for (let i = 0; i < lines.length; i++) {
  if (lines[i].code == targetCode) {
    matchedIndex = i
    break
  }
}
if (matchedIndex >= 0) {
  const targetLine : ScanLine = lines[matchedIndex]
  targetLine.scan_count = targetLine.scan_count + count
}
```

Keep the concrete element type visible at the mutation site.

## Nullable `UTSJSONObject` Values

- Store getter output in a typed local variable.
- Check `!= null` before conversion or access.
- Supply a real domain default only when the API contract defines one.
- Do not add guessed aliases or fake values solely to silence the compiler.

## UCSS Compiler Errors

For `property value ... is not supported` or `not a standard property name`:

1. Remove or replace the unsupported property/value according to the official compatibility table.
2. Search the whole changed module for the same pattern.
3. Confirm text styles are attached to `<text>`/`<button>`.
4. Prefer a simpler flex layout instead of reproducing browser CSS exactly.

Native App compiler failures have been observed for values or properties such as `font-weight: 800/900`, `word-break`, and `overflow-wrap` in some project/version combinations. Verify the current compatibility table before treating them as universal restrictions.

## Verification Ladder

1. Run `scripts/audit.sh` for known static risks.
2. Inspect the exact changed lines and declaration order.
3. Run the real uni-app x compile path.
4. Test the target page on the relevant platform/device.
5. Verify API payload, response status, UI state, and console output.
6. Remove temporary diagnostics.

Never describe steps 3-5 as complete unless their output was actually observed.
