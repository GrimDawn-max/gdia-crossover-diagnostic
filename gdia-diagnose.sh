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
problems=()
notes=()

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

# find the bottle holding Item Assistant
iagd_bottle=""
for b in $bottles; do
  if [[ -d "$b/drive_c/Program Files/IAGD" || -d "$b/drive_c/Program Files (x86)/IAGD" ]]; then
    iagd_bottle=$b
    break
  fi
done

if [[ -z $iagd_bottle ]]; then
  bad "Item Assistant is not installed in any bottle" \
      "step 5 of the setup guide has not been done, or it went into a bottle this script cannot see"
else
  head2 "The bottle holding Item Assistant"
  info "$(basename "$iagd_bottle")   at $(tidy $iagd_bottle)"
  tmpl=$(grep -E '^"Template"' "$iagd_bottle/cxbottle.conf" 2>/dev/null | head -1 | cut -d'"' -f4)
  info "template   ${tmpl:-unknown}"
  winver=$(reg_value "$iagd_bottle/system.reg" 'Software\\Microsoft\\Windows NT\\CurrentVersion' CurrentVersion)
  [[ -n $winver ]] && info "windows    $winver"

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
  head2 "Renderer settings  (why a window can be black with the right runtime)"
  args=$(grep -E '^"WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"' "$iagd_bottle/cxbottle.conf" 2>/dev/null | cut -d'"' -f4)
  if [[ -z $args ]]; then
    warn "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is not set" \
         "a working reference install sets it to force software rendering; see the summary"
  else
    info "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS ="
    info "   $args"
    for flag in --disable-gpu --use-gl=swiftshader --in-process-gpu; do
      [[ $args == *$flag* ]] || warn "$flag is not among those arguments" \
          "software rendering may not be forced"
    done
  fi
  v=$(reg_value "$iagd_bottle/user.reg" 'Software\\Wine\\AppDefaults\\msedgewebview2.exe' Version)
  info "msedgewebview2.exe version override: ${v:-none}"

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
    info "files        $(ls -1 "$d" | wc -l | tr -d ' ') items"
  done

  # --------------------------------------------------------------- logs
  head2 "Logs"
  logs=()
  for l in "$iagd_bottle/drive_c/users"/*/"AppData/Local/IAGD"/**/*.log \
           "$iagd_bottle/drive_c/users"/*/"Documents/IAGD"/**/*.log; do
    logs+=("$l")
  done
  if (( ${#logs} == 0 )); then
    info "no Item Assistant log files found"
  else
    for l in ${logs[1,3]}; do
      info "$(tidy $l)  ($(wc -l < "$l" | tr -d ' ') lines, modified $(date -r "$l" '+%Y-%m-%d %H:%M'))"
      grep -iE "error|exception|fail" "$l" 2>/dev/null | tail -3 | sed 's/^/              /'
    done
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
say ""
