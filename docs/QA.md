# Manual QA checklist

These checks cover what the unit tests can't: the window, focus, displays, and the real Muxy and Claude Code. Run them on a release build (`scripts/build-app.sh release`). Use a notch display (MacBook), and a non-notch display (for example an external ultrawide) where a check says so.

## Before you start

- [ ] Muxy 2.x is running, and Muxy Eye's hooks are installed (Settings → Claude hooks → Install). Restart any Claude sessions that were already open.
- [ ] To test without touching your own Claude settings, add the hooks to a throwaway project instead. Put them in its `.claude/settings.local.json`, with each command pointing at `"<path>/Muxy Eye.app/Contents/Helpers/muxy-eye-hook" <EventName>`.
- [ ] Start a test session in a Muxy terminal with `claude --permission-mode default`, so that Claude asks for approvals. Accept the folder trust dialog first. Project-local hooks apply only after that.
- [ ] Prompts that are handy for testing:
  - an approval: "Use the Bash tool to run exactly: touch qa-1.txt";
  - a question: "Use the AskUserQuestion tool to ask me one single-select question with three options";
  - a multi-select question: the same, with "multi-select";
  - a finished turn: any short request.

## The collapsed eye

- [ ] There is no Dock icon.
- [ ] The eye sits at the top center of the display of the app you are working in.
- [ ] **Idle** (no agent working or waiting):
  - [ ] a flat, dim line that doesn't move;
  - [ ] about 0% CPU in Activity Monitor.
- [ ] **Working:** while a Claude session works, a white wave scrolls across, with a fainter cyan wave behind it.
- [ ] **Waiting:**
  - [ ] the line becomes the pulsing orange ring within about 1 s of an approval appearing;
  - [ ] the pulse doesn't jump when the ring has finished forming, and the ring turns back into the wave smoothly;
  - [ ] about 0% CPU in Activity Monitor while the ring pulses, once it has formed;
  - [ ] clicking the pulsing ring opens the panel;
  - [ ] after you answer it in the terminal, the wave returns within about 2 s;
  - [ ] after a turn finishes, the ring comes back for the finished turn. It clears once you look at that pane in Muxy.
- [ ] **Notch display (MacBook):**
  - [ ] with nothing waiting, there is one wing, on the left, holding the eye;
  - [ ] with one or more waiting, there are two wings, and the right wing shows the count;
  - [ ] the eye stays on the left wing when the right wing appears or retracts.
- [ ] **Non-notch display (ultrawide):**
  - [ ] the eye is a circle at the top center of the menu bar, slightly smaller than the menu bar;
  - [ ] with one waiting there is no badge;
  - [ ] with two or more waiting, a count badge appears beside the circle.
- [ ] Clicks reach the menu bar everywhere outside the visible shape: next to the eye, and in the gap between the eye and the badge.
- [ ] **Full screen and Spaces:** the eye stays visible over a full-screen app, and after switching Spaces.
- [ ] **Several displays:**
  - [ ] the eye moves to the display of the app you activate;
  - [ ] with a display pinned in Settings, it stays on that display;
  - [ ] it moves to the right place again after connecting or disconnecting a display, or changing the resolution.
- [ ] **A new session:** open a new Muxy terminal, start Claude, and make it raise a prompt straight away. The ring shows at once, and the row shows the project name.
- [ ] **Muxy's server stopped** (only with no terminals running):
  - [ ] after `muxy server stop`, the eye goes idle within a few seconds;
  - [ ] `muxy server status` stays stopped, even a minute later. The eye never starts the server again.
- [ ] **Quitting:** right-click → Quit Muxy Eye removes `~/Library/Application Support/Muxy Eye/eye.sock`.

## Moving and resizing the eye

Start each group from the default spot and size: use **Reset Position and Size** in the eye's menu if it is offered.

- [ ] **Click or drag:**
  - [ ] a press released without moving opens the panel, on release, and gives it the keyboard;
  - [ ] a press that moves a little (about 2 points) and comes back still opens the panel;
  - [ ] a press that moves more than about 4 points drags the eye: it follows the pointer live, without lag or flicker, and stays where you let go;
  - [ ] after a drag the panel stays closed, nothing is typed into any terminal, and the keyboard stays in the app you were in;
  - [ ] a drag that starts on the count badge moves the eye too, and the circle comes to the pointer as the drag starts;
  - [ ] on a notch display, a drag that starts on either wing (also the right wing's count) brings the circle to the pointer instead of trailing far from it;
  - [ ] a drag that goes back to where it started is still a drag: the panel doesn't open;
  - [ ] right-click and control-click on the eye still open its menu;
  - [ ] the open panel can't be dragged, and dragging inside it (selecting text, for example) doesn't move anything;
  - [ ] while the panel pulls back into the eye, a click on it still opens it again.
- [ ] **Auto-expand during a drag:** with auto-expand on, start dragging the eye and make a prompt arrive. The panel opens without taking the keyboard, and the eye stays where it was dragged to.
- [ ] **Shape:**
  - [ ] at the default spot and size, the eye looks exactly as before: the notch's wings on a notch display, the menu-bar circle and its badge elsewhere;
  - [ ] the first move or resize turns it into a free circle, also on a notch display (no wings);
  - [ ] a moved eye shows no count with one session waiting, and the count beside it with two or more, on every display;
  - [ ] at the right edge of the screen, and just left of the notch, the count sits on the eye's left instead;
  - [ ] the eye stops at the screen's edges: it can't be dragged off the screen;
  - [ ] drag the eye along the top of a notch display, across the notch: it never disappears behind the notch, and dropped there it sits just beside or below it.
- [ ] **Resize:**
  - [ ] on a trackpad, two fingers up over the eye grow it and down shrink it, smoothly, without jumps;
  - [ ] at the default spot on a notch display, scroll over the right wing: the circle appears under the pointer and keeps resizing as you keep scrolling; the same beside the menu-bar eye, over its count;
  - [ ] scroll over the middle of the notch itself: the eye resizes once and appears beside or below the notch (it can't sit behind it), so further scrolling there goes to what's below — expected;
  - [ ] with a mouse wheel, each step grows or shrinks it by about a tenth;
  - [ ] the same finger or wheel direction grows it with natural scrolling on and off (System Settings → Trackpad / Mouse);
  - [ ] lifting the fingers stops the resizing at once (momentum doesn't keep it going);
  - [ ] it stops at about half and about three times its usual size;
  - [ ] the count badge and its digits grow and shrink with it;
  - [ ] scrolling over the open panel scrolls its content and doesn't resize the eye;
  - [ ] scrolling elsewhere in the menu bar or in other apps is unaffected.
- [ ] **Clicks around the eye:** at the largest size, clicks next to the circle (at the corners of its square) and in the gap between the eye and its count reach the menu bar or the app below; so does a scroll there. 
  - [ ] with Settings open in front (Muxy Eye active), move the pointer off a large eye and back onto it, then click it: the click still opens the panel (the eye takes clicks again as soon as the pointer is back on it).A click on the circle or the count still opens the panel. At the usual size the few points at the eye's corners stay the eye's, as before.
- [ ] **Relaunch:** quit and start the app again. The eye is where you left it, at the same size.
- [ ] **Several displays:**
  - [ ] move the eye, for example to the left third of the screen, half way down; activate an app on another display. The eye is at the same relative place there, at the same size relative to that display's usual eye;
  - [ ] with a display pinned in Settings, the moved eye stays on that display;
  - [ ] after connecting or disconnecting a display, or changing the resolution, the moved eye is at the same relative place again;
  - [ ] a moved eye on a notch display sits clear of the notch, also when it got there by following the active display.
- [ ] **Reset:**
  - [ ] at the default spot and size, the eye's menu has no Reset Position and Size, from the right-click and from the ⋯ button;
  - [ ] after a move, and after a resize alone, both menus have it;
  - [ ] it puts the eye back at the top centre at its usual size, with the notch's wings again on a notch display, and the item disappears;
  - [ ] from the ⋯ button in the open panel, the panel moves back to the top centre with the eye.
- [ ] **CPU:** with a moved and resized eye at rest, idle and waiting, Muxy Eye uses about 0% CPU, as at the default spot.

## The panel's side

Settings → **Panel opens**. Check each side with the eye moved to the middle of the screen, then near the screen's edges. Check on a notch display and a non-notch one.

- [ ] **Each side** (below, above, left, right):
  - [ ] the panel opens beside the eye on that side, a few points from it (and from where its count goes), grows out of the eye with the same spring as before, and pulls back into the eye when it closes;
  - [ ] the eye stays visible the whole time, with its line and count: while the panel opens, while it is open, and while it closes. Check this over a dark window too (a Muxy terminal): there is no moment without the eye at the end of closing;
  - [ ] a click on the eye while the panel is open closes it;
  - [ ] when a count appears or goes while the panel is open, the panel doesn't move;
  - [ ] the panel has its usual size, with all four corners rounded;
  - [ ] the content isn't cut off, and nothing sits under the notch or the menu bar;
  - [ ] when the content grows (a longer prompt), the panel stays on the side it opened on.
- [ ] **No room on that side:** with the eye near the bottom edge and "below", the panel opens above; near the top and "above", below; near the left edge and "left", to the right; near the right edge and "right", to the left.
- [ ] **No room on either side for the whole panel** (eye half way down the 14" display, a tall prompt, "below" or "above"): the panel opens on the side with more room, beside the eye, only as tall as that room; its content scrolls, and the eye stays visible.
- [ ] **No room even for a short panel** (only on a very small screen or window area): the panel opens on the chosen side, moved over the eye just enough to stay on the screen.
- [ ] **Always on the screen:** in every case the panel is fully inside the screen and clear of the Dock; unless it hangs from the top of the screen (below an eye in the menu bar), it is clear of the menu bar and the notch too.
- [ ] **Eye in the menu bar** (resize it at the default spot, or drag it to the top), also a large one reaching below the menu bar:
  - [ ] with "below" or "above", the panel hangs from the top of the screen as before, centred on the eye (kept on the screen at its edges), square on top, content below the notch on a notch display, covering the eye;
  - [ ] when that panel closes, the eye's line and count are back while its shape pulls back into the eye: there is no moment with only black shapes, also over a dark window;
  - [ ] with "left" or "right", the panel opens under the menu bar beside the eye; an eye fully in the menu bar stays visible above it, keeps animating, and a click on it closes the panel.
- [ ] **Clicks beside the open panel:** with the panel open beside the eye (a moved eye mid-screen with any side, an eye in the menu bar with "left" or "right", or an eye over the Dock):
  - [ ] clicks in the empty space between the eye and the panel, and next to them, reach the menu bar, the Dock or the app below, and close the panel;
  - [ ] a scroll there scrolls what is below, and a file dragged from Finder across that space can be dropped on what is below;
  - [ ] clicks on the panel and on the eye still work as above, also right after moving the pointer quickly from the space onto them;
  - [ ] a press in the panel (selecting text, for example) dragged out into that space and released there ends normally;
  - [ ] while the panel opens or closes, clicks beside it are still taken as before (no click lands in another app mid-animation);
  - [ ] Muxy Eye uses no CPU while the mouse doesn't move, and next to none while it moves.
- [ ] **Default spot:** with "below", the panel is exactly as before: flush with the top edge, square on top, content below the notch on a notch display. With "above", it opens the same way.
- [ ] **With a moved eye, as at the default spot:**
  - [ ] a click outside the panel closes it, and typing goes back to the app you were in;
  - [ ] Esc, ↑/↓, the digits and Return work after clicking the eye or the panel;
  - [ ] auto-expand opens the panel without taking the keyboard;
  - [ ] clicking the eye again while the panel closes, or closing it while it opens, turns the animation around smoothly;
  - [ ] with Reduce Motion on, the panel fades in and out on its side instead of growing.

## The expanded panel

- [ ] Click the eye. The panel opens and gets the keyboard, but no text field is focused, so digit keys pick options.
- [ ] The frontmost app (its menu bar) stays the same while the panel is open, because the panel doesn't activate the app.
- [ ] After a click outside, the panel closes, and typing goes back to the window you were in.
- [ ] Esc closes the panel, and ↑/↓ move through the rail.
- [ ] **Rail:**
  - [ ] rows are ordered waiting (oldest first), then working, then idle;
  - [ ] ages tick (`approval · 12s`);
  - [ ] non-Claude agents show `<provider> · <state>`.
- [ ] **Layout:**
  - [ ] on a notch display, the content starts below the notch, and the area behind the notch is black;
  - [ ] on a non-notch display, the panel drops from the menu bar, with no top inset.
- [ ] **Approval:**
  - [ ] the panel shows the tool label (`BASH COMMAND`), the command and Claude's description;
  - [ ] it shows the options exactly as in the terminal, with option 1 in orange;
  - [ ] `1` approves, and the terminal continues;
  - [ ] Return also approves (option 1);
  - [ ] on a Write prompt, the file path is shown, and the "No" number rejects it.
- [ ] **No, with feedback:**
  - [ ] type in "Tell Claude what to do instead…" and press Return;
  - [ ] the terminal shows `Interrupted · What should Claude do instead?`, followed by your text as the next prompt, and Claude answers it;
  - [ ] this works with Claude's prompt suggestions on (the default).
- [ ] **Single-select question:**
  - [ ] the panel shows `QUESTION · <HEADER>`, the options with descriptions, and "Type something else…";
  - [ ] "Chat about this" is not offered;
  - [ ] clicking an option answers it;
  - [ ] free text plus Return answers it too.
- [ ] **Multi-select question:**
  - [ ] the panel shows checkboxes, and Submit stays disabled until something is ticked;
  - [ ] ticking with `1` and with a click types nothing into the terminal (it still shows `[ ]`);
  - [ ] Submit answers with both picks.
- [ ] **Two questions in one request:**
  - [ ] after question 1 is answered in the panel, question 2 appears and can be answered there;
  - [ ] after question 2, Claude's review screen shows read-only, with Open in Muxy (known limitation).
- [ ] **Multi-select inside a request with several questions** (known limitation): Submit in the panel. Note what you see:
  - [ ] whether the boxes get ticked in the terminal;
  - [ ] whether the terminal moves to the next question or to the review screen;
  - [ ] which banner the eye shows (expected: "Couldn't confirm — Open in Muxy");
  - [ ] that you can still finish the request in the terminal.
- [ ] **Finished turn:**
  - [ ] the panel shows Claude's last message, Reply and Dismiss;
  - [ ] Reply sends the text as the next prompt, with Claude's prompt suggestions on (the default);
  - [ ] Dismiss clears the item and marks the Muxy event read.
- [ ] **Stale prompt:**
  - [ ] while the panel shows an approval, answer it in the terminal (`muxy session send <id> -- 1`), then click an option in the eye. The banner reads "Prompt changed — Open in Muxy", and nothing extra is typed;
  - [ ] do the same with a question;
  - [ ] the banner keeps the panel open until you close it;
  - [ ] the next time the panel opens, there is no old banner.
- [ ] **Refresh on click:** clicking a rail row, or clicking into an auto-expanded panel, reads that row's terminal again. The options match the terminal.
- [ ] **No prompt details:**
  - [ ] relaunch the app while an approval is already open;
  - [ ] the row says `needs input`;
  - [ ] the panel shows `NEEDS INPUT`, the last terminal lines as read-only text, and only Open in Muxy.
- [ ] **Working or idle row:** the panel shows the state, and Claude's last message once one is known.
- [ ] **Closing by itself:**
  - [ ] about 1 s after the last waiting item is answered, dismissed or cleared, the panel closes;
  - [ ] if a new item arrives within that second, it stays open on the new item.
- [ ] **Open in Muxy:**
  - [ ] Muxy comes to the front and switches to the session's project. It can't focus the exact pane (known limitation);
  - [ ] the session's alerts are marked read;
  - [ ] the panel closes.

## Auto-expand

- [ ] It is off by default: a new approval only changes the eye.
- [ ] **On, with Muxy not frontmost:**
  - [ ] a new approval, question or finished turn opens the panel;
  - [ ] keep typing in another app (for example TextEdit) while it opens. Every keystroke stays in that app, and none reaches the eye;
  - [ ] clicking the auto-expanded panel gives it the keyboard.
- [ ] **On, with Muxy frontmost:** the eye changes, but the panel doesn't open. Check with Muxy Beta too, if you have it.
- [ ] **Hide for 1 Hour:**
  - [ ] the eye disappears, and auto-expand doesn't bring it back in that time;
  - [ ] after the hour, the eye comes back. If auto-expand opened the panel in the meantime, a click outside still closes it.

## Setup, Settings and the menu

- [ ] **First launch:** run `defaults delete io.github.vybo.muxy-eye` first. The setup window shows:
  - [ ] the Muxy path and version;
  - [ ] the Claude settings file and the hooks status;
  - [ ] Install, the restart hint, Launch at login, and Done.
- [ ] Closing the setup window, with Done or with the red button, means it doesn't come back on the next launch.
- [ ] **Install:**
  - [ ] the hooks are merged into Claude's settings, and every other entry and value is kept (the keys may be re-sorted);
  - [ ] a `settings.json.muxy-eye-backup-<date>` copy is written next to the file;
  - [ ] Muxy 1.x hooks (`muxy-claude-hook.sh`) are left as they were;
  - [ ] the file has exactly 8 entries containing `muxy-eye-hook` (`grep -c muxy-eye-hook ~/.claude/settings.json` prints 8);
  - [ ] the helper is in place: `test -x ~/"Library/Application Support/Muxy Eye/bin/muxy-eye-hook" && echo ok` prints ok;
  - [ ] the status says Installed.
- [ ] **Update:** after an older install, the status says Needs update, and Update fixes it.
- [ ] **Remove:** only entries containing `muxy-eye-hook` are removed.
- [ ] **⋯ menu button** (top-right of the open panel) shows the same items as the right-click menu and works with a menu-bar tool like Barbee running.
- [ ] **Open in Muxy with Muxy on another Space:** you're taken to Muxy's Space.
- [ ] **Right-click menu:** (a menu-bar tool such as Barbee may take the right click; then use ⋯)
  - [ ] Settings… opens Settings in front;
  - [ ] Hide for 1 Hour hides the eye;
  - [ ] Quit Muxy Eye quits.
- [ ] `open "Muxy Eye.app" --args --settings` opens Settings at launch.
- [ ] **Settings:**
  - [ ] the auto-expand toggle takes effect immediately;
  - [ ] Display can be pinned to each connected display, and set back to "Follow focused app";
  - [ ] **Panel opens** offers below (the default), above, left and right, and takes effect at once, also while the panel is open;
  - [ ] the hooks status matches the settings file;
  - [ ] **Launch at login:** toggling it works, or shows macOS's reason when it refuses (an ad hoc signed build may be refused);
  - [ ] **Muxy CLI path:** a path to another `muxy` binary is used at once ("Muxy found: <path>"), a path that doesn't exist falls back to automatic detection, and clearing it goes back to automatic detection;
  - [ ] **Muxy profile folder:** another profile, such as `~/Library/Application Support/Muxy Beta`, switches the eye to that profile's sessions, without a restart.
- [ ] A Muxy that speaks another CLI protocol shows the "unsupported protocol" warning.

## Claude Code is never slowed down

- [ ] With Muxy Eye quit, Claude sessions with the hooks installed show no delay, and their prompts look unchanged.
- [ ] A Claude session outside Muxy (in another terminal app) is unaffected and doesn't appear in the eye.
- [ ] While a session is working, Muxy Eye uses about 8% CPU or less (release build).
