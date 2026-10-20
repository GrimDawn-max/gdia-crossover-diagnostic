# Item Assistant on CrossOver — diagnostic

A small script that reports how **Grim Dawn Item Assistant** is set up inside a
CrossOver bottle on macOS, so a problem can be identified from the output
instead of from a conversation.

It is for one symptom in particular: **Item Assistant runs and collects items,
but its window is black or its item grid is blank.** That is almost always the
WebView2 runtime being a version later than `109.0.1518.140`. Later builds fail
by rendering nothing rather than by reporting an error, so the application looks
like it is working.

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
| Renderer | the browser arguments and version overrides in effect |
| .NET | that the Desktop Runtime 10.x is present, not just the plain runtime |
| Item Assistant | where it is installed, and anything in its logs |

It finishes with a summary naming what is wrong and what to do about each one.

## What it does not do

It **reads files only**. It installs nothing, changes nothing, and starts no
Windows programs — so it is safe to run on a working setup, and running it
cannot make a broken one worse.

Home folder paths are shortened to `~` in the output, so the report can be
posted publicly without revealing your user name or folder layout. It is worth
reading the output before posting it, as you would with any diagnostic.

The script is short and plain text. You are welcome to read it first; that is a
sensible habit with any script a stranger hands you.

## If it reports nothing wrong

Then the cause is something this script does not yet know to look for. Say so,
and include the report anyway — knowing what has been ruled out is most of the
work.

## Related

The full installation procedure this checks against is the Item Assistant on
macOS / CrossOver setup guide on the Crate Entertainment forum.

Item Assistant itself is by EvilSoft and is not connected to this repository.
This is a diagnostic for people installing it under CrossOver, nothing more.
