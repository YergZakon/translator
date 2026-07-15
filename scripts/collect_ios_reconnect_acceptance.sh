#!/usr/bin/env bash
set -euo pipefail

DEFAULT_STAGE_URL="https://backend-api-stage-ee06.up.railway.app"
STAGE_URL="${STAGE_URL:-$DEFAULT_STAGE_URL}"
DEVICE_ID=""
OUTPUT_PATH=""

usage() {
    cat <<'EOF'
Usage: scripts/collect_ios_reconnect_acceptance.sh [options]

Options:
  --device ID       Select a physical iPhone by devicectl identifier.
  --stage-url URL   Override the stage backend URL.
  --output FILE     Write the sanitized Markdown report to FILE.
  -h, --help        Show this help.

The script never records a device identifier, audio, transcript text, app token,
client secret, or API key. Human-observable behavior is recorded only as PASS/FAIL.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --device)
            (($# >= 2)) || fail "--device requires a value"
            DEVICE_ID="$2"
            shift 2
            ;;
        --stage-url)
            (($# >= 2)) || fail "--stage-url requires a value"
            STAGE_URL="$2"
            shift 2
            ;;
        --output)
            (($# >= 2)) || fail "--output requires a value"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "run this script in Terminal on the MacBook"
command -v xcrun >/dev/null 2>&1 || fail "Xcode command-line tools are unavailable"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is unavailable"
command -v osascript >/dev/null 2>&1 || fail "osascript is unavailable"
command -v git >/dev/null 2>&1 || fail "git is unavailable"

case "$STAGE_URL" in
    https://*) ;;
    *) fail "stage URL must use https://" ;;
esac
[[ "$STAGE_URL" != *"?"* && "$STAGE_URL" != *"@"* ]] \
    || fail "stage URL must not contain credentials or a query string"
STAGE_URL="${STAGE_URL%/}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" \
    || fail "the script must be run from a Git checkout"
PARSER="$SCRIPT_DIR/lib/devicectl_device_info.js"
[[ -f "$PARSER" ]] || fail "missing parser: $PARSER"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/translator-device-acceptance.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
LIST_JSON="$TMP_DIR/devices.json"
DETAILS_JSON="$TMP_DIR/device-details.json"

printf 'Searching for paired physical iPhones...\n'
if ! xcrun devicectl list devices --json-output "$LIST_JSON" >/dev/null; then
    fail "devicectl could not list devices; unlock the iPhone, connect it, and trust this Mac"
fi

device_ids=()
device_names=()
device_versions=()
while IFS=$'\t' read -r identifier name os_version; do
    [[ -n "$identifier" ]] || continue
    device_ids+=("$identifier")
    device_names+=("${name:-Unknown iPhone}")
    device_versions+=("${os_version:-Unknown}")
done < <(osascript -l JavaScript "$PARSER" list "$LIST_JSON")

((${#device_ids[@]} > 0)) \
    || fail "no physical iPhone was found; unlock it, enable Developer Mode, and trust this Mac"

selected_index=-1
if [[ -n "$DEVICE_ID" ]]; then
    for ((index = 0; index < ${#device_ids[@]}; index++)); do
        if [[ "${device_ids[$index]}" == "$DEVICE_ID" ]]; then
            selected_index=$index
            break
        fi
    done
    ((selected_index >= 0)) || fail "the requested iPhone is not available"
elif ((${#device_ids[@]} == 1)); then
    selected_index=0
else
    printf 'Available iPhones:\n'
    for ((index = 0; index < ${#device_ids[@]}; index++)); do
        printf '  %d) %s — iOS %s\n' "$((index + 1))" "${device_names[$index]}" "${device_versions[$index]}"
    done
    while true; do
        read -r -p "Select iPhone [1-${#device_ids[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#device_ids[@]})); then
            selected_index=$((selection - 1))
            break
        fi
        printf 'Enter a number from 1 to %d.\n' "${#device_ids[@]}"
    done
fi

selected_id="${device_ids[$selected_index]}"
device_model="${device_names[$selected_index]}"
ios_version="${device_versions[$selected_index]}"

if xcrun devicectl device info details --device "$selected_id" --json-output "$DETAILS_JSON" >/dev/null 2>&1; then
    IFS=$'\t' read -r detailed_model detailed_ios \
        < <(osascript -l JavaScript "$PARSER" details "$DETAILS_JSON" "$selected_id")
    [[ -z "${detailed_model:-}" || "$detailed_model" == "Unknown iPhone" ]] || device_model="$detailed_model"
    [[ -z "${detailed_ios:-}" || "$detailed_ios" == "Unknown" ]] || ios_version="$detailed_ios"
fi

xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
git_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

health_result="FAIL"
if command -v curl >/dev/null 2>&1 && curl --fail --silent --show-error --max-time 10 \
    "$STAGE_URL/v1/health" >/dev/null 2>&1; then
    health_result="PASS"
fi

ask_pass_fail() {
    local prompt="$1"
    local answer
    while true; do
        read -r -p "$prompt [PASS/FAIL]: " answer
        answer="$(printf '%s' "$answer" | tr '[:lower:]' '[:upper:]')"
        case "$answer" in
            PASS|FAIL)
                printf '%s' "$answer"
                return
                ;;
        esac
        printf 'Enter PASS or FAIL.\n' >&2
    done
}

choose_route() {
    local answer
    while true; do
        printf 'Audio route:\n  1) speaker\n  2) AirPods\n  3) other\n' >&2
        read -r -p 'Select [1-3]: ' answer
        case "$answer" in
            1) printf 'speaker'; return ;;
            2) printf 'AirPods'; return ;;
            3) printf 'other'; return ;;
        esac
    done
}

choose_error_category() {
    local answer
    while true; do
        printf 'Error category (do not paste logs or conversation text):\n' >&2
        printf '  1) none\n  2) network\n  3) WebRTC\n  4) audio\n  5) subtitles\n  6) stop/close\n  7) other\n' >&2
        read -r -p 'Select [1-7]: ' answer
        case "$answer" in
            1) printf 'none'; return ;;
            2) printf 'network'; return ;;
            3) printf 'WebRTC'; return ;;
            4) printf 'audio'; return ;;
            5) printf 'subtitles'; return ;;
            6) printf 'stop/close'; return ;;
            7) printf 'other'; return ;;
        esac
    done
}

printf '\nDevice detected: %s, iOS %s\n' "$device_model" "$ios_version"
printf 'Stage health: %s\n\n' "$health_result"
cat <<'EOF'
Run the acceptance scenario now:
  1. Build and launch the Stage configuration on this physical iPhone.
  2. Start a translation session and confirm it is active.
  3. Disable the active network for 3–5 seconds, then restore it.
  4. Wait for reconnecting and recovery, then verify translation again.
  5. Stop the session normally.

Do not paste logs, audio, transcript text, app tokens, client secrets, or API keys.
EOF
read -r -p 'Press Enter when the scenario is complete... ' _

reconnect_result="$(ask_pass_fail 'Reconnect completed and session recovered')"
remote_audio_result="$(ask_pass_fail 'Remote English audio works after reconnect')"
source_transcript_result="$(ask_pass_fail 'Source transcript continues after reconnect')"
target_transcript_result="$(ask_pass_fail 'Target transcript continues after reconnect')"
no_duplicate_audio_result="$(ask_pass_fail 'No duplicated audio or microphone sender')"
stop_result="$(ask_pass_fail 'Stop/close completed correctly')"
audio_route="$(choose_route)"
error_category="$(choose_error_category)"

if [[ -z "$OUTPUT_PATH" ]]; then
    output_directory="$HOME/Desktop"
    [[ -d "$output_directory" ]] || output_directory="$PWD"
    OUTPUT_PATH="$output_directory/RealtimeTranslator-IOS12-Acceptance-$(date '+%Y%m%d-%H%M%S').md"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
umask 077
cat >"$OUTPUT_PATH" <<EOF
# IOS-12 physical iPhone reconnect acceptance

This sanitized report intentionally excludes device identifiers, audio, transcript text, app tokens, client secrets, and API keys.

- Generated at: $generated_at
- Device model: $device_model
- iOS: $ios_version
- Xcode: $xcode_version
- Git commit: $git_commit
- Stage URL: $STAGE_URL
- Stage health: $health_result
- WebRTC reconnect and recovery: $reconnect_result
- Remote English audio after reconnect: $remote_audio_result
- Source transcript after reconnect: $source_transcript_result
- Target transcript after reconnect: $target_transcript_result
- No duplicated audio/microphone: $no_duplicate_audio_result
- Stop/close: $stop_result
- Audio route: $audio_route
- Error category: $error_category
EOF

printf '\nSanitized report saved to:\n%s\n' "$OUTPUT_PATH"
