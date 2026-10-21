#!/bin/zsh
#
# gdia-diagnose.sh — report how Item Assistant is set up under CrossOver on macOS.
#
# Run it, paste the output. It reads files only: it installs nothing, changes
# nothing, and starts no Windows programs. Home paths are shortened to ~ so the
# output is safe to post publicly.
#
#   zsh ~/Downloads/gdia-diagnose.sh
#
# The usual cause of a black Item Assistant window is the WebView2 runtime
# being a version later than 109.0.1518.140. Later builds require Windows 10
# APIs that do not work here, and they fail by rendering nothing rather than by
# reporting an error — so the application looks like it is running correctly.

emulate -L zsh
setopt null_glob

GOOD_WEBVIEW="109.0.1518.140"

# The environment of a bottle that is known to render the item grid. All four
# matter: the browser arguments force software rendering, and the other three
# were each needed to get this far on Apple silicon.
typeset -A GOOD_ENV=(
  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS "--no-sandbox --disable-gpu --disable-gpu-compositing --disable-gpu-sandbox --disable-accelerated-2d-canvas --disable-accelerated-video-decode --use-gl=swiftshader --in-process-gpu"
  DOTNET_SYSTEM_GLOBALIZATION_USENLS    "1"
  WINEMSYNC                             "0"
  CX_GRAPHICS_BACKEND                   ""
)

problems=()
notes=()
env_wrong=()
rule_missing=0

say()  { print -r -- "$@" }
head2(){ print -r -- ""; print -r -- "── $1"; }
tidy() { print -r -- "${1//$HOME/~}" }

ok()   { say "   [ ok ]   $1" }
bad()  { say "   [FAIL]   $1"; problems+=("$1${2:+ -- $2}") }
warn() { say "   [warn]   $1"; notes+=("$1${2:+ -- $2}") }
info() { say "            $1" }

# value of "name" inside [section] of a wine .reg file
reg_value() {
  local file=$1 section=$2 name=$3
  [[ -r $file ]] || return 1
  # the section and name go through the environment, not -v: awk expands
  # escape sequences in -v assignments, which turns the doubled backslashes a
  # wine .reg file uses into single ones, and nothing ever matches
  RV_SECTION="[$section]" RV_NAME="\"$name\"=" awk '
    index($0, ENVIRON["RV_SECTION"])==1 {f=1; next}
    f && /^\[/ {exit}
    f && index($0, ENVIRON["RV_NAME"])==1 {
      v=substr($0, length(ENVIRON["RV_NAME"])+1); gsub(/^"|"$/,"",v); print v; exit
    }' "$file"
}

# A windows path as Item Assistant stores it, turned back into a real one.
# The drive letters are symlinks in the bottle's dosdevices folder, so this is
# the only way to tell whether a configured folder exists -- and whether it
# points outside the bottle, which is how a separate-bottle setup has to work.
win_to_real() {
  local bottle=$1 win=$2 letter target rest full
  [[ $win == ?:* ]] || return 1
  letter=${(L)win[1]}
  target=$(readlink "$bottle/dosdevices/$letter:" 2>/dev/null) || return 1
  [[ $target == /* ]] || target="$bottle/dosdevices/$target"
  rest=${win[3,-1]//\\//}
  # :A normalises -- the c: mapping is relative (../drive_c), and an
  # unnormalised path fails every later comparison against the bottle
  local full="${target%/}$rest"
  print -r -- "${full:A}"
}

say "Item Assistant / CrossOver diagnostic"
say "generated $(date '+%Y-%m-%d %H:%M %Z')"

# ---------------------------------------------------------------- the machine
head2 "Machine"
info "macOS      $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
info "chip       $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
info "arch       $(uname -m)"

# ------------------------------------------------------------------ CrossOver
head2 "CrossOver"
cx_apps=()
for p in /Applications/CrossOver.app "/Applications/CrossOver Preview.app" \
         /Volumes/*/CrossOver.app "/Volumes/*/CrossOver Preview.app" \
         ~/Applications/CrossOver.app; do
  [[ -d $p ]] && cx_apps+=("$p")
done
if (( ${#cx_apps} == 0 )); then
  bad "No CrossOver application found" "install CrossOver, then re-run this"
else
  for a in $cx_apps; do
    v=$(defaults read "$a/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    info "$(tidy $a)  version ${v:-unknown}"
  done
fi

# -------------------------------------------------------------------- bottles
bottle_dirs=()
d=$(defaults read com.codeweavers.CrossOver BottleDir 2>/dev/null) && bottle_dirs+=("$d")
d=$(defaults read com.codeweavers.CrossOverPreview BottleDir 2>/dev/null) && bottle_dirs+=("$d")
bottle_dirs+=("$HOME/Library/Application Support/CrossOver/Bottles")
typeset -U bottle_dirs

head2 "Bottles"
bottles=()
for bd in $bottle_dirs; do
  [[ -d $bd ]] || continue
  info "in $(tidy $bd):"
  for b in "$bd"/*/; do
    [[ -d "$b/drive_c" ]] || continue
    bottles+=("${b%/}")
    info "   $(basename "${b%/}")"
  done
done
(( ${#bottles} == 0 )) && bad "No bottles found" "nothing is installed yet"

# Every bottle holding Item Assistant, not the first one found. Installing it
# twice is easy to do and the two copies keep separate settings and separate
# item databases, so a report describing the wrong copy explains nothing.
iagd_bottles=()
for b in $bottles; do
  [[ -d "$b/drive_c/Program Files/IAGD" || -d "$b/drive_c/Program Files (x86)/IAGD" ]] \
    && iagd_bottles+=("$b")
done

# Examine the one actually being run: the most recently written log wins. A
# copy that has never been started has no log, and loses to one that has.
iagd_bottle=""
newest=0
for b in $iagd_bottles; do
  when=0
  for l in "$b/drive_c/users"/*/"AppData/Local/EvilSoft/IAGD/log.txt"; do
    [[ -f $l ]] && when=$(stat -f %m "$l" 2>/dev/null)
  done
  (( when >= newest )) && { newest=$when; iagd_bottle=$b }
done

if (( ${#iagd_bottles} > 1 )); then
  warn "Item Assistant is installed in ${#iagd_bottles} bottles: ${${iagd_bottles[@]:t}}" \
       "each keeps its own settings and its own item database -- the one examined below is $(basename $iagd_bottle), the one used most recently"
fi

if [[ -z $iagd_bottle ]]; then
  bad "Item Assistant is not installed in any bottle" \
      "step 5 of the setup guide has not been done, or it went into a bottle this script cannot see"
else
  head2 "The bottle holding Item Assistant"
  info "$(basename "$iagd_bottle")   at $(tidy $iagd_bottle)"
  tmpl=$(grep -E '^"Template"' "$iagd_bottle/cxbottle.conf" 2>/dev/null | head -1 | cut -d'"' -f4)
  info "template   ${tmpl:-unknown}"
  # ProductName and CurrentBuild, not CurrentVersion: wine leaves CurrentVersion
  # at 6.3 even on a win10 template, so reporting it sends people chasing a
  # Windows 8.1 that is not there.
  prod=$(reg_value "$iagd_bottle/system.reg" 'Software\\Microsoft\\Windows NT\\CurrentVersion' ProductName)
  bld=$(reg_value  "$iagd_bottle/system.reg" 'Software\\Microsoft\\Windows NT\\CurrentVersion' CurrentBuild)
  info "windows    ${prod:-unknown}${bld:+ build $bld}"
  winver=$(grep -E '^"WindowsVersion"' "$iagd_bottle/cxbottle.conf" 2>/dev/null | head -1 | cut -d'"' -f4)
  [[ -n $winver && $winver != win10 ]] && \
    warn "the bottle is set to $winver, and a working one is win10" \
         "change it in the bottle's Settings"

  # Which CrossOver owns this bottle. The "Preview" key does not say -- it is
  # absent from most bottles and set on some made by the ordinary build. The
  # Version field is the one that matches an installed application's version.
  cxv=$(grep -E '^"Version"' "$iagd_bottle/cxbottle.conf" 2>/dev/null | head -1 | cut -d'"' -f4)
  info "made by    CrossOver ${cxv:-unknown}"
  (( ${#cx_apps} > 1 )) && warn "more than one CrossOver is installed, and a bottle behaves differently under each" \
      "the version above says which one made it -- run Item Assistant from that one"

  # ------------------------------------------------------------- WebView2
  head2 "WebView2 runtime  (the usual cause of a black window)"
  app_dir="$iagd_bottle/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
  found=()
  for v in "$app_dir"/*/; do
    vb=$(basename "${v%/}")
    [[ $vb == <->.<->.<->.<-> ]] && found+=("$vb")
  done

  if (( ${#found} == 0 )); then
    bad "WebView2 is not installed in this bottle" "do step 3 of the setup guide"
  else
    for v in $found; do
      if [[ $v == $GOOD_WEBVIEW ]]; then
        ok "WebView2 $v"
      else
        bad "WebView2 $v is installed, and only $GOOD_WEBVIEW works" \
            "uninstall it, make sure the step 2 registry rules are set, then install again"
      fi
    done
    (( ${#found} > 1 )) && warn "more than one WebView2 version is present: ${found[*]}" \
        "the newest usually wins, so remove the others"
    [[ -x "$app_dir/${found[1]}/msedgewebview2.exe" ]] || \
      warn "msedgewebview2.exe is missing from $app_dir/${found[1]}" "the install is incomplete"
  fi

  pv=$(grep -i '"pv"=' "$iagd_bottle/system.reg" 2>/dev/null | head -1 | cut -d'"' -f4)
  [[ -n $pv ]] && info "registry reports pv = $pv"

  # --------------------------------------------- step 2: the win7 spoof rules
  head2 "Step 2 rules  (which WebView2 build Microsoft offers)"
  for exe in MicrosoftEdgeWebview2Setup.exe MicrosoftEdgeUpdate.exe; do
    v=$(reg_value "$iagd_bottle/user.reg" "Software\\\\Wine\\\\AppDefaults\\\\$exe" Version)
    if [[ $v == win7 ]]; then
      ok "$exe -> win7"
    elif [[ -n $v ]]; then
      warn "$exe -> $v, expected win7" "a reinstall would fetch a WebView2 that cannot work"
    else
      warn "$exe has no Version rule" "set it before reinstalling WebView2, or you will get a build that cannot work"
    fi
  done

  # ------------------------------------------- renderer flags and overrides
  head2 "Environment  (why a window can be black with the right runtime)"
  for name in WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS DOTNET_SYSTEM_GLOBALIZATION_USENLS \
              WINEMSYNC CX_GRAPHICS_BACKEND; do
    want=${GOOD_ENV[$name]}
    line=$(grep -E "^\"$name\"" "$iagd_bottle/cxbottle.conf" 2>/dev/null | head -1)
    if [[ -z $line ]]; then
      warn "$name is not set" "a bottle that renders sets it to \"$want\""
      env_wrong+=("$name")
      continue
    fi
    have=$(print -r -- "$line" | cut -d'"' -f4)
    if [[ $have == $want ]]; then
      ok "$name"
    else
      warn "$name is \"$have\"" "a bottle that renders sets it to \"$want\""
      env_wrong+=("$name")
    fi
  done

  v=$(reg_value "$iagd_bottle/user.reg" 'Software\\Wine\\AppDefaults\\msedgewebview2.exe' Version)
  case $v in
    win7) ok "msedgewebview2.exe -> win7" ;;
    "")   warn "msedgewebview2.exe has no Version rule" \
               "a bottle that renders sets it to win7 -- the renderer takes a different drawing path depending on what Windows it thinks it is on"
          rule_missing=1 ;;
    *)    warn "msedgewebview2.exe -> $v, and a bottle that renders uses win7" \
               "the renderer takes a different drawing path depending on what Windows it thinks it is on"
          rule_missing=1 ;;
  esac

  # ---------------------------------------------------------------- .NET
  head2 ".NET 10 Desktop Runtime"
  shared="$iagd_bottle/drive_c/Program Files/dotnet/shared"
  for pack in Microsoft.WindowsDesktop.App Microsoft.NETCore.App; do
    vers=()
    for v in "$shared/$pack"/*/; do vers+=("$(basename "${v%/}")") done
    if (( ${#vers} == 0 )); then
      bad "$pack is not installed" "do step 4 -- it must be the Desktop Runtime, not the plain .NET Runtime"
    else
      case ${vers[1]} in
        10.*) ok "$pack ${vers[*]}" ;;
        *)    bad "$pack is ${vers[*]}, version 10.x is required" "do step 4" ;;
      esac
    fi
  done

  # --------------------------------------------------------------- IAGD
  head2 "Item Assistant"
  for d in "$iagd_bottle/drive_c/Program Files/IAGD" "$iagd_bottle/drive_c/Program Files (x86)/IAGD"; do
    [[ -d $d ]] || continue
    info "installed at $(tidy $d)"
    main=""
    for e in "$d"/*.exe; do
      case ${e:t:l} in
        *grim*|*iagd*|*assistant*) main=$e ;;
      esac
    done
    [[ -n $main ]] && info "main program $(basename "$main")"
    # a raw file count is not comparable between versions; what matters is
    # whether the pieces that draw the item grid are present
    missing=()
    for f in WebView2Loader.dll Microsoft.Web.WebView2.Core.dll \
             Microsoft.Web.WebView2.WinForms.dll IAGrim.dll; do
      [[ -f "$d/$f" ]] || missing+=("$f")
    done
    if (( ${#missing} )); then
      bad "Item Assistant is missing ${missing[*]}" "reinstall it -- step 5"
    else
      ok "the WebView2 pieces it draws the grid with are all present"
    fi
  done

  # ------------------------------------------- does it know any items at all
  # The grid can be empty for a reason that has nothing to do with rendering:
  # Item Assistant has to parse Grim Dawn's own item database before it can
  # show anything, and it cannot find the game by itself here. Its automatic
  # search looks at the Windows registry and the usual install folders inside
  # its own bottle, so a bottle that holds Item Assistant and not the game
  # finds nothing -- the location has to be set by hand, to a path that bottle
  # can actually reach.
  head2 "Does it know any items"

  gd_here=""
  for g in "$iagd_bottle/drive_c"/*/"Grim Dawn" "$iagd_bottle/drive_c"/*/*/"Grim Dawn"; do
    [[ -f "$g/Grim Dawn.exe" || -f "$g/x64/Grim Dawn.exe" ]] && { gd_here=$g; break }
  done
  if [[ -n $gd_here ]]; then
    info "Grim Dawn is in this bottle too, at $(tidy ${gd_here#$iagd_bottle/drive_c})"
  else
    info "Grim Dawn is NOT in this bottle -- Item Assistant cannot find it by itself"
  fi

  iagd_data=""
  for d in "$iagd_bottle/drive_c/users"/*/"AppData/Local/EvilSoft/IAGD"; do
    [[ -d $d ]] && { iagd_data=$d; break }
  done

  if [[ -z $iagd_data ]]; then
    warn "Item Assistant has never been run in this bottle" \
         "it writes its settings and log the first time it starts"
  else
    # settings.json has CRLF endings, so a pattern anchored with $ never
    # matches -- everything here ends with .* instead
    loc=$(sed -n 's/.*"currentGrimdawnLocation"[^"]*"\(.*\)".*/\1/p' "$iagd_data/settings.json" 2>/dev/null | head -1)
    parsed=$(sed -n 's/.*"isGrimDawnParsed"[^:]*:[ ]*\([a-z]*\).*/\1/p' "$iagd_data/settings.json" 2>/dev/null | head -1)

    known=""; mine=""
    db="$iagd_data/data/userdata.db"
    if [[ -f $db ]] && (( $+commands[sqlite3] )); then
      known=$(sqlite3 "$db" "select count(*) from DatabaseItem_v2;" 2>/dev/null)
      mine=$(sqlite3  "$db" "select count(*) from PlayerItem;"      2>/dev/null)
    fi

    # Two separate counts, and either being zero is a different fault. The
    # first is the game's own items, which it must read before it can show
    # anything. The second is the reader's items, which is what there is to
    # show -- an empty grid with a healthy renderer is usually just this.
    if [[ -z $known ]]; then
      if [[ ! -f $db ]]; then
        bad "there is no item database file yet" \
            "Item Assistant makes it the first time it reads the game"
      else
        info "item counts need sqlite3, which is not on this machine"
      fi
    else
      if (( known > 0 )); then
        ok "it recognises $known item types from Grim Dawn's database"
      else
        bad "it recognises no item types from Grim Dawn's database" \
            "it has not read the game's item database, and nothing can appear until it does"
      fi

      if (( ${mine:-0} > 0 )); then
        ok "$mine of your own items are stored in it"
        newest=$(sqlite3 "$db" "select date(max(created_at)/1000,'unixepoch') from PlayerItem;" 2>/dev/null)
        [[ -n $newest ]] && info "the most recent was stored on $newest"
        # a breakdown, because items under a mod or on hardcore are only shown
        # when the matching mod and mode are selected
        sqlite3 "$db" "select coalesce(nullif(Mod,''),'(base game)') || ', ' ||
                              case IsHardcore when 1 then 'hardcore' else 'softcore' end ||
                              '   ' || count(*)
                       from PlayerItem group by Mod, IsHardcore order by count(*) desc;" 2>/dev/null \
          | while read -r l; do info "   $l"; done
      else
        bad "none of your own items are stored in it" \
            "there is nothing for it to show, whatever the renderer does -- put something in the transfer stash in game and let it read that"
      fi
    fi
  fi

  # ---------------------------------------- which Grim Dawn it is reading
  # The last tab in Item Assistant sets this, and it is the setting a
  # separate-bottle installation gets wrong: the folder is stored as a windows
  # path, and a windows path that no drive letter reaches is accepted silently.
  head2 "Which Grim Dawn it reads"
  if [[ -z $iagd_data ]]; then
    info "nothing set yet -- Item Assistant has not been run"
  elif [[ -z $loc ]]; then
    bad "no Grim Dawn folder is set" \
        "set it on the last tab in Item Assistant; if the game is in another bottle, reach it through the Z: drive"
  else
    # stored with doubled backslashes, being json
    win=${loc//\\\\/\\}
    info "folder       $win"
    real=$(win_to_real "$iagd_bottle" "$win")
    if [[ -z $real ]]; then
      bad "no drive $win[1,2] exists in this bottle, so that folder cannot be read" \
          "map the drive, or set a folder this bottle can reach"
    elif [[ ! -d $real ]]; then
      bad "that folder does not exist" \
          "it resolves to $(tidy $real), and there is nothing there"
    else
      info "which is     $(tidy $real)"
      if [[ $real == $iagd_bottle/drive_c/* ]]; then
        info "             (inside this bottle)"
      else
        other=$real
        while [[ $other != / && ! -f $other/cxbottle.conf ]]; do other=${other:h}; done
        if [[ -f $other/cxbottle.conf ]]; then
          info "             (in the bottle $(basename $other), reached through $win[1,2])"
          notes+=("the game is read from another bottle -- file reading works, but the in-game hook cannot reach a process in a different bottle")
        else
          info "             (outside any bottle)"
        fi
      fi

      # the databases actually sitting there, which is what gets read
      arz=()
      for f in "$real"/database/*.arz "$real"/gdx*/database/*.arz; do arz+=("${f:t}") done
      if (( ${#arz} == 0 )); then
        bad "there are no Grim Dawn databases in that folder" \
            "it is not a Grim Dawn install folder -- point it at the one holding Grim Dawn.exe"
      else
        ok "databases there: ${arz[*]}"
      fi
    fi

    mod=$(sed -n 's/.*"currentGrimdawnMod"[^"]*"\(.*\)".*/\1/p' "$iagd_data/settings.json" 2>/dev/null | head -1)
    info "mod          ${mod:-none (the base game)}"
    [[ $parsed == true ]] && ok "it has finished reading that folder" \
      || warn "it has not finished reading that folder" "the path may be wrong, or unreadable"

    # which expansions are represented in what it read. An install missing one
    # shows no items from it, which looks like items going missing.
    if [[ -n $known ]] && (( known > 0 )); then
      for pair in "gdx1|Ashes of Malmouth" "gdx2|Forgotten Gods" "gdx3|Fangs of Asterkarn"; do
        x=${pair%%|*}; label=${pair##*|}
        n=$(sqlite3 "$db" "select count(*) from DatabaseItem_v2 where baserecord like '%$x%';" 2>/dev/null)
        if (( ${n:-0} > 0 )); then
          ok "read $label  ($n records)"
        else
          warn "read nothing from $label" \
               "either it is not installed, or that part of the database was not read -- its items cannot appear"
        fi
      done
    fi
  fi

  # --------------------------------------------------------------- its own log
  # Item Assistant writes a diagnostics report of its own at every start, which
  # is better evidence than anything this script can infer. It lives under
  # EvilSoft, not under IAGD -- looking in the wrong place reported "no logs"
  # on an installation that had plenty.
  head2 "Item Assistant's own report"
  if [[ -z $iagd_data || ! -f "$iagd_data/log.txt" ]]; then
    info "no log yet -- start Item Assistant once, then run this again"
  else
    info "from $(tidy $iagd_data/log.txt), $(date -r "$iagd_data/log.txt" '+%Y-%m-%d %H:%M')"
    say ""
    # verbatim, less the machine name, which is the one identifying line in it
    sed -n '/\[diag\] Item Assistant diagnostics/,/\[diag\].*Queued transfers/p' "$iagd_data/log.txt" \
      | sed -e 's/.*\[diag\] //' -e '/Machine name/d' -e "s|^|     |"
    say ""

    head2 "How far it got last time"
    for pair in \
      "The Grim Dawn database has been parsed|read the game's item database" \
      "WebView2 initialization successful|started the renderer" \
      "WebView2 navigation succeeded|drew the item grid"; do
      pat=${pair%%|*}; what=${pair##*|}
      if grep -qF "$pat" "$iagd_data/log.txt"; then
        ok "$what"
      else
        bad "never $what" "this is the step it stops at"
      fi
    done

    errs=$(grep -ciE "ERROR|FATAL" "$iagd_data/log.txt")
    if (( errs )); then
      head2 "Errors in that log  ($errs in all)"
      grep -iE "ERROR|FATAL" "$iagd_data/log.txt" | tail -5 \
        | sed -e "s|$HOME|~|g" -e 's/^/     /'
    fi
  fi
fi

# -------------------------------------------------------------------- verdict
head2 "Summary"
if (( ${#problems} == 0 && ${#notes} == 0 )); then
  say "   Nothing wrong found. If the window is still black, say so -- the cause"
  say "   is then something this script does not yet check."
else
  (( ${#problems} )) && { say "   Problems:"; for p in $problems; do say "    - $p"; done }
  (( ${#notes} ))    && { say "   Worth checking:"; for n in $notes; do say "    - $n"; done }
fi

# If the environment is the only thing out of place, say exactly what to change.
# This is the common case once the runtime is right, and it is no use naming a
# setting without saying where it lives.
# If the settings are what is out of place, say exactly what to change. This is
# the common case once the runtime is right, and it is no use naming a setting
# without saying where it lives. Ordered as it has to be done: the file is
# rewritten when CrossOver exits, so it is edited first, with CrossOver closed.
if (( ${#env_wrong} || rule_missing )); then
  head2 "Setting those"
  step=0

  if (( ${#env_wrong} )); then
    say "   $((++step)). Quit CrossOver -- it rewrites this file when it exits."
    say ""
    say "   $((++step)). Open this file in TextEdit:"
    say ""
    say "         $(tidy $iagd_bottle)/cxbottle.conf"
    say ""
    say "      Find the line that reads [EnvironmentVariables], near the bottom,"
    say "      and put these underneath it, replacing any of the same name that"
    say "      are already there:"
    say ""
    for name in $env_wrong; do
      say "         \"$name\" = \"${GOOD_ENV[$name]}\""
    done
    say ""
    say "      Save and close it."
    say ""
  fi

  if (( rule_missing )); then
    # They have already done this twice, for the installer and the updater, in
    # step 2 of the guide. Naming it that way is clearer than any instruction.
    say "   $((++step)). Start CrossOver, and set the same kind of rule step 2 of the"
    say "      setup guide sets -- a Version of win7 -- but on the renderer itself."
    say "      In this bottle: Control Panel > Wine Configuration > Applications,"
    say "      add"
    say ""
    say "         c:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\$GOOD_WEBVIEW\\msedgewebview2.exe"
    say ""
    say "      and set its Windows version to Windows 7."
    say ""
  fi

  say "   $((++step)). Run Item Assistant, then run this script again."
fi

say ""
