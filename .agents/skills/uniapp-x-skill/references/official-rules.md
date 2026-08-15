# Official Rules and Provenance

## Sources and Priority

Use this order when rules appear to conflict:

1. The current DCloud documentation and its platform/version compatibility table
2. The bundled DCloud `uni-app-x-ai-rules` snapshot
3. Repository-local rules and established code patterns
4. General TypeScript, Vue, CSS, Kotlin, Swift, or Web knowledge

Repository rules may intentionally be stricter than DCloud's minimum, but they cannot make an unsupported feature valid.

This priority order does not require network access for every task. Use the bundled snapshot by default. Consult the current documentation only for version-sensitive, uncertain, conflicting, or explicitly current/latest questions.

## Bundled DCloud Snapshot

`references/dcloud-official/` is copied without modification from DCloud's official [uni-app-x-ai-rules](https://gitcode.com/dcloud/uni-app-x-ai-rules) repository.

- Imported files: `.agent/rules/*.md` and `LICENSE`
- License: Apache License 2.0

Read [dcloud-official/SOURCE.md](dcloud-official/SOURCE.md) for the exact bundled revision and [dcloud-official/LICENSE](dcloud-official/LICENSE) before redistribution.

The snapshot is the offline development baseline, not a frozen replacement for live documentation. Uni-app x support varies by HBuilderX version and target platform, so use [documentation-map.md](documentation-map.md) only to verify uncertain or recently changed behavior rather than browsing during ordinary edits.

## Core Official Model

- UTS is a strongly and nominally typed cross-platform language compiled to target languages.
- Variables must be initialized; absence is represented with `null`, not `undefined`.
- Conditions require a real `boolean` rather than JavaScript truthiness.
- Uncontextualized object literals can become `UTSJSONObject`; use named `type` models at business boundaries.
- UTS language behavior and inference capabilities vary by HBuilderX version. Explicit types are the safer cross-version form.
- UVUE, Vue APIs, components, uni APIs, CSS, and plugins each have separate platform/version compatibility tables.
- App native rendering supports a CSS subset rather than all browser CSS.
- Platform-specific behavior belongs behind conditional compilation or in platform-specific source directories.

## Official AI Rules and MCP

DCloud's [AI Rules and MCP guide](https://doc.dcloud.net.cn/uni-app-x/tutorial/rules_mcp.html) documents official configurations for Codex and other AI tools. It points Codex projects to an `AGENTS.md` ruleset and configures `@dcloudio/uni-app-x-mcp` to inspect available project components.

If the UniApp X MCP is configured and available, use it for project component/plugin discovery. If it is unavailable, inspect the repository directly; never claim MCP-derived compatibility or component information without a real tool result.
