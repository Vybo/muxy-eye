# Spike findings: Claude Code prompts through Muxy

Date: 2026-10-23. Claude Code 2.1.309, Muxy 2.1.0 (protocol V2), macOS 26.2.

Method: a throwaway Muxy session ran `claude --permission-mode default` in a temporary folder. Project-local hooks logged every event's stdin and environment. Answers were typed with `muxy session send` / `send-keys`. Sanitized captures are in `Tests/MuxyEyeCoreTests/Fixtures/`.

## S1 — Keystrokes

| Prompt | Keystrokes that worked | Notes |
| --- | --- | --- |
| Permission approval (Bash, Write) | `send "N"` | Answers immediately, with no Enter. State went from `blocked` to `working` in under 0.5 s. |
| Permission "No" | `send "<No number>"` | Interrupts the tool. The screen shows `Interrupted · What should Claude do instead?` and Claude goes `idle` at the prompt. Feedback is then a normal prompt: `send "<text>"`, then `send-keys Enter`. |
| Question, single-select | `send "N"` | Answers immediately. |
| Question, free text | `send "<Type something number>"`, then `send "<text>"`, then `send-keys Enter` | The number moves focus into the inline text option; the typed text replaces the label. |
| Question, multi-select | `send "N"` for each option to toggle, then `send "\e[C"` (→), then `send "1"` | Numbers toggle `[ ]` ↔ `[✔]`. → opens the "Review your answers / Ready to submit your answers?" view, with `1. Submit answers`, `2. Cancel`. |
| Reply after a finished turn | `send "<text>"`, then `send-keys Enter` | |

The option numbering changes between prompts. For example, Bash showed 4 options ending in `No`, and Write showed 3. Always take numbers from the screen.

## S2 — Raw input

`muxy session send <id> $'\e[B'` passes escape sequences through as raw input: the cursor moved in the trust dialog. Arrow keys therefore work through the CLI, so multi-select can be answered.

## S3 — Hooks

- Command hooks see `MUXY_SESSION_ID` and `MUXY_SERVER_ID`. `MUXY_SESSION_ID` equals the `session` field in `muxy activity list --json`.
- With exit 0 and no stdout, `PermissionRequest` and `PreToolUse(AskUserQuestion)` leave Claude's dialog unchanged.
- `AskUserQuestion` fires **both** `PreToolUse` (with `tool_input.questions`) **and** `PermissionRequest` (`tool_name: "AskUserQuestion"`). Ignore the latter.
- After an approval: `PostToolUse` fires once the tool finishes, then `Stop` (with `last_assistant_message`).
- After a denial with "No": neither `PostToolUse` nor `Stop` fires. Clearing must come from Muxy's state (`blocked` → `idle`).
- `Notification` (`notification_type: "permission_prompt"`) arrives about 6 s after the prompt. It is not needed for showing prompts.
- `SessionEnd` fires when the session ends.
- Project-local hooks only applied after the folder trust dialog was accepted.

## S4 — Screens

- `muxy session read-screen <id> --lines N` returns the visible rows, with trailing blank rows. Content can sit at the top, so read the whole screen (`--lines` at least the terminal's row count; use 200).
- Prompt blocks sit below a `─` rule, and end with a footer starting with `Esc to cancel` (permissions) or `Enter to select` (questions).
- The cursor marker is `❯`. Options are `N. label`.
  - Long permission labels wrap onto continuation lines, indented under the label, sometimes mid-word at the terminal width.
  - Question options are followed by indented description lines.
  - Multi-select options carry `[ ]` / `[✔]`.
- Question header: `☐ <header>`, or `☒ <header>` once answered. Multi-select shows a tab bar: `←  ☐ Platforms  ✔ Submit  →`.
- After the question options, a `─` rule separates a `N. Chat about this` option.
- The trust dialog has unnumbered options (`❯ No, exit` / `Yes, I trust this folder`). It is not a prompt the eye answers.

## S5 — Muxy

- `muxy activity list --json` takes about 40 ms wall time and about 2 ms CPU per call, so 1 s polling is cheap.
- Event JSON: `kind` is capitalized (`"Completed"`, `"Attention"`), `provider` is `"Claude"`, `state` is lowercase. Ids are strings.
- `muxy server status --json` prints `{"build":{...},"instance":<n>}` with exit 0 while running. A failing connection prints `muxy: …` to stderr with exit 1. Treat anything other than exit 0 with an `instance` field as "not running".
- Worktrees are projects: `project list --json` items have `kind` (`"project"` or `"worktree"`) and `parent_id`.
- Muxy Beta: bundle id `com.muxy-beta.app`, profile `~/Library/Application Support/Muxy Beta`. Stable: `com.muxy.app`, `~/Library/Application Support/Muxy 2`.
- `MUXY_DIR` paths must stay short. A Unix socket path over `SUN_LEN` (104 bytes) fails with `path must be shorter than SUN_LEN`.
