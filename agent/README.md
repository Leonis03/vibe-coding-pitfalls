# AI 工具链

| 路径 | 内容 | 部署到 |
| :--- | :--- | :--- |
| [`claude-code/`](claude-code/) | `settings.json`、全局约定原件 `claude-global.md`、状态栏脚本 | `~/.claude/`（`cp`） |
| [`antigravity/`](antigravity/) | 全局约定原件 `agents-brave-uv.md`，`agy` CLI 用法与读图记录 | `~/.gemini/config/AGENTS.md`（`cp`） |
| [`brave-search/`](brave-search/) | `bx` CLI 与 Brave Search MCP 的接入说明 | — |
| [`skills/`](skills/) | 全部 skill，两边共用 | `~/.claude/skills/`、`~/.gemini/config/skills/`（**只能**用 `tools/sync-skills.sh`，不能 `cp`） |

- 同一个工具可能出现在两处：`antigravity/` 是配置原件与使用记录，`skills/antigravity-cli/` 是给 agent 调用的 skill；
  `brave-search/` 与 `skills/bx/` 同理。改行为改 skill，改部署配置改前者。
- 全局约定原件故意不叫 `CLAUDE.md` / `AGENTS.md`：harness 会把子目录里这两个名字的文件当作指令自动加载。
