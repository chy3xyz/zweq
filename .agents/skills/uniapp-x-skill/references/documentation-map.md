# DCloud Documentation Map

Use this index only when a live-lookup trigger in `SKILL.md` applies. Ordinary development uses the bundled official rules without network access. When lookup is required, open only the pages relevant to the task; compatibility tables on the target page are authoritative for platform and HBuilderX version support.

## Project and Runtime Model

- [Uni-app x overview](https://doc.dcloud.net.cn/uni-app-x/)
- [Project structure](https://doc.dcloud.net.cn/uni-app-x/project.html)
- [Pages](https://doc.dcloud.net.cn/uni-app-x/page.html)
- [App Vapor rendering mode](https://doc.dcloud.net.cn/uni-app-x/app-vapor.html)
- [Compiler](https://doc.dcloud.net.cn/uni-app-x/compiler/)
- [Performance](https://doc.dcloud.net.cn/uni-app-x/performance.html)
- [Compatibility table guide](https://doc.dcloud.net.cn/uni-app-x/tutorial/compatibility.html)
- [Official examples](https://doc.dcloud.net.cn/uni-app-x/sample.html)

## UTS Language

Read this entire section when implementing unfamiliar UTS syntax or porting TypeScript/JavaScript code.

- [UTS introduction, declaration, inference, and platform compilation](https://doc.dcloud.net.cn/uni-app-x/uts/)
- [Data types and nullability](https://doc.dcloud.net.cn/uni-app-x/uts/data-type.html)
- [Literals](https://doc.dcloud.net.cn/uni-app-x/uts/literal.html)
- [Operators](https://doc.dcloud.net.cn/uni-app-x/uts/operator.html)
- [Functions](https://doc.dcloud.net.cn/uni-app-x/uts/function.html)
- [Classes](https://doc.dcloud.net.cn/uni-app-x/uts/class.html)
- [Interfaces](https://doc.dcloud.net.cn/uni-app-x/uts/interface.html)
- [Object types](https://doc.dcloud.net.cn/uni-app-x/uts/object.html)
- [Type aliases](https://doc.dcloud.net.cn/uni-app-x/uts/type-aliases.html)
- [Type compatibility](https://doc.dcloud.net.cn/uni-app-x/uts/type-compatibility.html)
- [Generics](https://doc.dcloud.net.cn/uni-app-x/uts/generics.html)
- [Modules](https://doc.dcloud.net.cn/uni-app-x/uts/module.html)
- [Keywords](https://doc.dcloud.net.cn/uni-app-x/uts/keywords.html)
- [UTS global and built-in APIs](https://doc.dcloud.net.cn/uni-app-x/uts/buildin-object-api/global.html)
- [UTSJSONObject](https://doc.dcloud.net.cn/uni-app-x/uts/buildin-object-api/utsjsonobject.html)
- [UTS versus TypeScript restrictions](https://doc.dcloud.net.cn/uni-app-x/uts/uts_diff_ts.html)

## UVUE and Vue

- [UVUE overview, template/script/style, class and style binding](https://doc.dcloud.net.cn/uni-app-x/vue/)
- [Composition API](https://doc.dcloud.net.cn/uni-app-x/vue/composition-api.html)
- [Options API](https://doc.dcloud.net.cn/uni-app-x/vue/options-api.html)
- [Components and easycom](https://doc.dcloud.net.cn/uni-app-x/vue/component.html)
- [Data binding](https://doc.dcloud.net.cn/uni-app-x/vue/data-bind.html)
- [Modifiers](https://doc.dcloud.net.cn/uni-app-x/vue/modifier.html)
- [Built-in Vue features](https://doc.dcloud.net.cn/uni-app-x/vue/built-in.html)
- [Global Vue APIs](https://doc.dcloud.net.cn/uni-app-x/vue/global-api.html)
- [Advanced Vue APIs](https://doc.dcloud.net.cn/uni-app-x/vue/advanced-api.html)
- [Other Vue compatibility](https://doc.dcloud.net.cn/uni-app-x/vue/others.html)

## Global Configuration

- [pages.json](https://doc.dcloud.net.cn/uni-app-x/collocation/pagesjson.html)
- [manifest.json](https://doc.dcloud.net.cn/uni-app-x/collocation/manifest.html)

Verify the actual filename and property support from the global-files navigation before adding configuration that is absent from the current project.

## Components

- [Component overview and custom components](https://doc.dcloud.net.cn/uni-app-x/component/)
- [Common component attributes](https://doc.dcloud.net.cn/uni-app-x/component/common.html)
- [Uni UI X](https://doc.dcloud.net.cn/uni-app-x/component/uni-ui-x/)
- [Scroll view](https://doc.dcloud.net.cn/uni-app-x/component/scroll-view.html)
- [List view](https://doc.dcloud.net.cn/uni-app-x/component/list-view.html)
- [Waterflow](https://doc.dcloud.net.cn/uni-app-x/component/waterflow.html)

For every component, open its own page and verify properties, events, methods, slots, and platform/version columns. Do not infer support from a similarly named Web component.

## APIs

- [Uni API overview](https://doc.dcloud.net.cn/uni-app-x/api/)
- [DOM APIs](https://doc.dcloud.net.cn/uni-app-x/api/dom/)
- [Ext APIs](https://doc.dcloud.net.cn/uni-app-x/api/ext.html)
- [UniCloud APIs](https://doc.dcloud.net.cn/uni-app-x/api/unicloud/)
- [UTS global and built-in APIs](https://doc.dcloud.net.cn/uni-app-x/uts/buildin-object-api/global.html)

For each API, verify callback/Promise support, parameter types, return types, error codes, permissions, and platform/version compatibility. OS-native APIs should normally be isolated in a UTS plugin.

## UCSS

- [CSS overview and supported property list](https://doc.dcloud.net.cn/uni-app-x/css/)
- [Differences from Web CSS](https://doc.dcloud.net.cn/uni-app-x/css/css_diff_web.html)
- [Selectors](https://doc.dcloud.net.cn/uni-app-x/css/common/selector.html)
- [Lengths and units](https://doc.dcloud.net.cn/uni-app-x/css/common/length.html)
- [Colors](https://doc.dcloud.net.cn/uni-app-x/css/common/color.html)
- [Functions](https://doc.dcloud.net.cn/uni-app-x/css/common/function.html)
- [At-rules](https://doc.dcloud.net.cn/uni-app-x/css/common/at-rules.html)
- [Style isolation](https://doc.dcloud.net.cn/uni-app-x/css/common/style-isolation.html)

Open the individual property page for every uncertain property or value. Support on Web does not imply support on App native rendering.

## Plugins and Native APIs

- [Plugin overview](https://doc.dcloud.net.cn/uni-app-x/plugin/)
- [UTS plugin development](https://doc.dcloud.net.cn/uni-app-x/plugin/uts-plugin.html)
- [Native development](https://doc.dcloud.net.cn/uni-app-x/native/)

For platform-specific source and conditional compilation, read the bundled official `conditional-compilation.md`, then verify every API or component on its own compatibility table.

## Errors, Testing, and AI Tooling

- [Compiler known issues](https://doc.dcloud.net.cn/uni-app-x/uts/compiler-known-issues.html)
- [Runtime known issues](https://doc.dcloud.net.cn/uni-app-x/uts/runtime-known-issues.html)
- [Uni error specification](https://doc.dcloud.net.cn/uni-app-x/err-spec.html)
- [AI Rules and MCP](https://doc.dcloud.net.cn/uni-app-x/tutorial/rules_mcp.html)
- [Language service plugin](https://doc.dcloud.net.cn/uni-app-x/tutorial/ls-plugin.html)
- [Engineering and automation](https://doc.dcloud.net.cn/uni-app-x/worktile/)

Search the exact compiler message and check the documented applicable version before applying a workaround.
