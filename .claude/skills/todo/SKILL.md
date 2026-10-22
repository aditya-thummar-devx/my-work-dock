---
name: todo
description: Add a todo to MyWorkDock's TODO list through the myworkdock MCP server. Use when the user runs /todo, or asks to add, note or remember a todo or task in MyWorkDock.
argument-hint: <todo text, may include #tag>
allowed-tools: mcp__myworkdock__add_todo
---

Add the todo with the `add_todo` tool of the `myworkdock` MCP server (`mcp__myworkdock__add_todo`).

- Todo text: $ARGUMENTS. If it is empty, use what the user asked for in the conversation; if that is unclear too, ask for the text.
- Pass the text as `title` exactly as written, keeping any `#tag` in it (the app files the todo under the first tag). Several todos: one call each.
- Reply with the tool's text in one line.
- If the tool says MyWorkDock isn't running, tell the user to open MyWorkDock (with Notes › TODO switched on) and try again.
- If the `myworkdock` tool isn't available at all, tell the user to click **Connect** in MyWorkDock's Notes › TODO tab, then start a new Claude Code session.
