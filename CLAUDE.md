# ToolHUD

Drive the app with `toolhud` (the app binary; `toolhud help`). See `.claude/skills/toolhud/SKILL.md`. Commands live in
`Sources/ToolHUD/Agent/AgentCommands.swift`; test them on a Debug build with `APP_STORE=/tmp/<name>`, which starts a
test copy on its own settings (suite `com.smanke.ToolHUD.agenttest`) with nothing else running: no sync, triggers,
key tap, menu hub or updater (Release builds ignore it). Never run `buttons run`, `hud show` or `hud repeat` in tests.
