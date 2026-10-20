# Item Assistant on CrossOver — diagnostic

A small script that reports how **Grim Dawn Item Assistant** is set up inside a
CrossOver bottle on macOS, so a problem can be identified from the output
instead of from a conversation.

It is for one symptom in particular: **Item Assistant runs, but you cannot see
your items.** There are two quite different causes, and the report separates
them:

- **The renderer draws nothing.** Usually a WebView2 runtime later than
  `109.0.1518.140`. Later builds fail by rendering nothing rather than by
  reporting an error, so the application looks like it is working.
- **There is nothing to draw.** Item Assistant has to read Grim Dawn's own item
  database before it can show anything, and it cannot find the game by itself
  under CrossOver — its search looks inside its own bottle. If Item Assistant
  and the game are in *different* bottles, the folder has to be set by hand, and
  until it is the grid is simply empty.

## Running it

Download `gdia-diagnose.sh` from the [latest release][rel], then in Terminal:

```sh
zsh ~/Downloads/gdia-diagnose.sh
```

Use `zsh ~/…` rather than `./gdia-diagnose.sh` — it saves having to make the
file executable, and avoids macOS asking about a downloaded script.

To save the report to your Desktop **and** copy it to the clipboard ready to
paste into a forum reply:

```sh
zsh ~/Downloads/gdia-diagnose.sh | tee ~/Desktop/gdia-report.txt | pbcopy
```

If you saved the file somewhere else, change the path — `zsh ~/Desktop/gdia-diagnose.sh`
works the same way.

[rel]: https://github.com/GrimDawn-max/gdia-crossover-diagnostic/releases/latest

## What it checks

| | |
|---|---|
| Machine | macOS version, processor, architecture |
| CrossOver | which copies are installed, and their versions |
| Bottles | every bottle found, and which one holds Item Assistant |
| WebView2 | the installed runtime version, against the one that works |
| Install rules | whether the registry rules that select that runtime are set |
| Environment | all four settings a bottle needs to render, against a bottle that does |
| .NET | that the Desktop Runtime 10.x is present, not just the plain runtime |
| Items | how many of the game's items it knows, and how many of yours it holds |
| Game folder | whether Grim Dawn is in the same bottle, and which folder is set |
| Its own report | Item Assistant's built-in diagnostics, and how far it got last run |

It finishes with a summary naming what is wrong and what to do about each one,
and if the environment is what is out of place, the exact lines to add and the
file to add them to.

## What it does not do

It **reads files only**. It installs nothing, changes nothing, and starts no
Windows programs — so it is safe to run on a working setup, and running it
cannot make a broken one worse.

Home folder paths are shortened to `~` in the output, and the machine name is
removed from Item Assistant's own report, so it can be posted publicly without
revealing your user name, machine name or folder layout. It is worth reading the
output before posting it, as you would with any diagnostic.

The script is short and plain text. You are welcome to read it first; that is a
sensible habit with any script a stranger hands you.

## If it reports nothing wrong

Then the cause is something this script does not yet know to look for. Say so,
and include the report anyway — knowing what has been ruled out is most of the
work.

## The setup guide

This script checks an installation against one particular procedure:

**[Grim Dawn Item Assistant on macOS (CrossOver)][guide]** — on the Crate
Entertainment forum.

Follow that first. This is for working out what went wrong afterwards.

[guide]: https://forums.crateentertainment.com/t/grim-dawn-item-assistant-on-macos-crossover/160408/3

## Related

Item Assistant itself is by EvilSoft and is not connected to this repository.
This is a diagnostic for people installing it under CrossOver, nothing more.
