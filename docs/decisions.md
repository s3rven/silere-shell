# Decisions

[All docs](README.md) · [Contributing](../CONTRIBUTING.md) · [Architecture](architecture.md)

Short records of the big noes and the choices behind them, so the why is written down next to the code. If you
think one is wrong, say so in [Discussions](https://github.com/s3rven/silere-shell/discussions).

## No launcher in the shell

Silere draws the bar, notifications, the OSD and its menus, and stops there. A launcher is a large program of
its own (desktop entries, search, ranking, its own keyboard handling), and good ones already exist. Building one
would grow the shell's memory, start-up and test matrix for something anyone can bind in one line. The same
reasoning keeps out a dock, a clipboard manager, a lock screen and a wallpaper picker; [Companions](companions.md)
shows how each connects instead.

If many people ask for a launcher in Silere itself, I'll reconsider. It would load only when opened and cost
nothing while closed.

## Scripts, not plugins

Silere loads no outside code. A script extends it through the `silere` command and its IPC calls: hooks run on
events, `silere indicator` puts a mark in the bar, `silere osd` shows a message, and `silere set` changes any
setting ([scripting](scripting.md)).

A plugin runs inside the shell's process, so a slow or crashing one freezes the bar and loses your
notifications with it, and every internal name it touches becomes an interface that can no longer change. A
script runs in its own process, within limits the shell sets (hooks: 20 runs a second, 4 at a time, 30 seconds
each), and talks to a surface small enough to promise: from 2.0, no 2.x release removes or renames a command,
call or hook the scripting guide lists, and ci-lint fails a change that drops one.

## One theming path: Matugen

Colours come from two places: the built-in neutral theme, with an accent you pick or take from a picture
(`silere theme`), or the palette Matugen writes from your wallpaper. There is no second import for other palette
tools or theme files.

Matugen already themes GTK, Qt, terminals and much of a desktop from the same wallpaper, so joining it keeps one
palette across everything. A second path would mean a second set of templates to keep working and a second way
for colours to disagree. Silere reads one file, recolours when it changes, and keeps the last good palette if a
write breaks it.

## The updater's scope

`silere update` moves a git checkout from one signed release tag to the next, and that is all. It checks the
tag's signature against `security/update-signers`, starts the new release in a sandbox before switching, keeps
a journal so an interrupted update recovers, and `silere update --rollback` goes back. It never installs on its
own: the optional timer only checks, and installing waits for you. It doesn't touch Quickshell, Qt, your
compositor or other packages, and a package install is left to its package manager. There is no beta channel;
it follows `vX.Y.Z` tags only.

Code that can replace your desktop shell is the riskiest code in the project. Keeping its job this narrow keeps
it testable: `dev/test-update.sh` runs interrupted updates, broken releases, dirty checkouts and restarts against
fixture repositories. See [updates and recovery](updates.md).

## The compositor facade

Widgets never talk to Hyprland or niri themselves. `services/Compositor.qml` picks a backend from the session's
socket variable and loads one file, `CompositorHyprland.qml` or `CompositorNiri.qml`, and both publish
workspaces, windows and actions in the same shape.

The two compositors share almost nothing: Hyprland's IPC socket and Quickshell module against niri's JSON event
stream. Behind one boundary, a widget is written once, a backend that lacks a feature simply leaves it out, the
unused backend costs nothing at start, and a new compositor is one file plus two lines
([backend contract](forking.md#another-compositor)). ci-lint fails a file outside the Hyprland backend that
imports Quickshell's Hyprland module, and a backend missing a member the facade reads.
