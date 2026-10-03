# FrameworkToolbox

A description of this package.

## Dynamic interposition

`DyldToolbox` provides `@DyldDynamicInterpose` and `DyldDynamicInterpose.applyAll()` / `revertAll()` for replacing imported function pointer slots at runtime. A matching slot must be writable under the operating system's memory protection rules. Trusted Path Read-Only (TPRO) pages can reject the change even when their maximum protection includes WRITE. Those slots remain unchanged and appear in `skippedSlots` with `memoryProtectionChangeFailed(errorNumber:)`; callers should inspect the report to determine which slots were replaced.

The default tests verify both successful interposition and explicit refusal on confirmed TPRO pages:

```sh
set -o pipefail
swift test 2>&1 | xcsift
```

To exercise the complete `getppid` apply/observe/revert cycle when the test executable's GOT is protected by TPRO, link the test build without moving sections into `__DATA_CONST`:

```sh
set -o pipefail
FRAMEWORK_TOOLBOX_REQUIRE_INTERPOSE_WRITES=1 swift test --filter DyldDynamicInterposeTests -Xlinker -no_data_const 2>&1 | xcsift
```

The environment variable requires successful writes, so this run fails if the slots remain protected. The linker option changes the test build's section layout. It does not change system security settings or make already protected images writable. The ordinary build retains the linker's default protections.

## Claude Code Plugin

This repository also ships as a [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin marketplace, providing skills that teach Claude Code how to use the macros in this package (currently `@Loggable` and `#log`).

### Install via Claude Code marketplace

Inside Claude Code, run:

```text
/plugin marketplace add Mx-Iris/FrameworkToolbox
/plugin install framework-toolbox@framework-toolbox
```

The first command registers this repository as a marketplace by reading `.claude-plugin/marketplace.json`. The second command installs the `framework-toolbox` plugin from the `framework-toolbox` marketplace, which mounts every skill under `plugins/framework-toolbox/skills/`.

To update the marketplace listing later:

```text
/plugin marketplace update framework-toolbox
```

### Available skills

| Skill | Triggers on |
|-------|-------------|
| `loggable-and-log` | Working with `@Loggable` / `#log`, configuring `subsystem`/`category`/access level, choosing privacy levels, or debugging the pre-macOS 11 `os_log` fallback. |

### Repository layout

```
.claude-plugin/marketplace.json         # marketplace manifest
plugins/framework-toolbox/              # plugin root
  .claude-plugin/plugin.json            # plugin manifest
  skills/                               # auto-discovered skills
    loggable-and-log/SKILL.md
```
