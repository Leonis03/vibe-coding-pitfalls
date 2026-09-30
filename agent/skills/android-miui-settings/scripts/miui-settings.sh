#!/usr/bin/env bash
# miui-settings.sh -- Android and Xiaomi MIUI / HyperOS settings CLI helper via nsenter
#
# Production script deployed under:
#   ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh
#   ~/.claude/skills/android-miui-settings/scripts/miui-settings.sh
#   /root/vibe-coding-pitfalls-private/agent/skills/android-miui-settings/scripts/miui-settings.sh
#
# [PRODUCTION STABLE RELEASE]
#
# Supported subcommands:
#   get <system|secure|global> <key>
#   put <system|secure|global> <key> <value>
#   delete <system|secure|global> <key>
#   list <system|secure|global> [pattern]
#   dns [status | auto | off | hostname <domain> | ali | dnspod | cloudflare | google]
#   phantom [status | disable | enable | limit <num>]
#   refresh-rate [status | 60 | 90 | 120 | auto]
#   animation [status | off | fast | normal]
#   powerkeeper [status | restrict | restore]
#   doze [status | whitelist <pkg> | unwhitelist <pkg>]
#   preset [performance | balanced | battery | stock]
#   input [focus | tap <x> <y> | swipe <x1> <y1> <x2> <y2> [ms] | key <code_or_name> | text <str> | launch <action_or_pkg>]
#   screencap [target_file]
#   backup [output.json]
#   restore <backup.json> [--all | --dns | --display | --animation | --phantom | --dry-run]
#
# Requirements:
#   - Root privileges (uid=0) inside Debian chroot
#   - util-linux (nsenter)
#   - jq (for backup/restore)

set -Eeuo pipefail

# Check root privilege
if [[ "$(id -u)" -ne 0 ]]; then
    printf 'error: miui-settings requires root privileges (uid=0).\n' >&2
    exit 1
fi

# Check nsenter availability
if ! command -v nsenter >/dev/null 2>&1; then
    printf 'error: nsenter utility not found. Install util-linux: apt-get install -y util-linux\n' >&2
    exit 1
fi

# Run command inside Android host mount namespace
host_exec() {
    nsenter -t 1 -m "$@"
}

# Verify Android host environment
if ! host_exec /system/bin/test -x /system/bin/settings; then
    printf 'error: /system/bin/settings not accessible in host namespace.\n' >&2
    exit 1
fi

show_usage() {
    cat << 'EOF'
Android & MIUI / HyperOS Settings CLI Tool (via targeted nsenter -m)

Usage:
  miui-settings.sh <subcommand> [options...]

Core Settings Subcommands:
  get <system|secure|global> <key>
      Read a setting value from the specified table.
  put <system|secure|global> <key> <value>
      Write or update a setting value.
  delete <system|secure|global> <key>
      Delete an override key (reverts to system default).
  list <system|secure|global> [pattern]
      List all keys in table, optionally filtered by grep pattern.

System Optimization & Tuning:
  dns [status | auto | off | hostname <domain> | ali | dnspod | cloudflare | google]
      Manage Android Private DNS (DNS-over-TLS).
  phantom [status | disable | enable | limit <num>]
      Manage Android 12/13/14 Phantom Process Killer & subprocess limits.
  refresh-rate [status | 60 | 90 | 120 | auto]
      Manage MIUI display refresh rate (PRIORITY_MIUI_REFRESH_RATE & smart fps).
  animation [status | off | fast | normal]
      Adjust window, transition, and animator duration scales (0, 0.5, 1.0).
  powerkeeper [status | restrict | restore]
      Restrict or restore Xiaomi PowerKeeper background killer permissions.
  doze [status | whitelist <pkg> | unwhitelist <pkg>]
      Query or modify Android Doze battery optimization whitelists.
  dnd [status | contacts-only | off | on]
      Manage Do Not Disturb & Zen Mode ringer policies (e.g. contacts only).
  volume [status | media <0-150> | ring <0-15> | alarm <1-15>]
      Inspect or set specific audio stream volumes.
  preset [performance | balanced | battery | stock]
      Apply curated system presets for AI agent workflows or device tuning.

Device Interaction & Diagnostics:
  input [focus | tap <x> <y> | swipe <x1> <y1> <x2> <y2> [ms] | key <code_or_name> | text <str> | launch <action>]
      Interact with host UI with foreground window safety checks.
  screencap [target_file]
      Capture screen with automatic container/host path translation.
  backup [output.json]
      Export full snapshot of system, secure, and global settings to JSON.
  restore <backup.json> [--all | --dns | --display | --animation | --phantom | --dry-run]
      Restore settings from JSON backup.

Examples:
  miui-settings.sh dns ali
  miui-settings.sh refresh-rate 120
  miui-settings.sh phantom disable
  miui-settings.sh animation fast
  miui-settings.sh preset performance
  miui-settings.sh screencap /root/md/screen.png
  miui-settings.sh backup /root/md/settings_backup.json
EOF
}

cmd_dns() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            local mode spec
            mode="$(host_exec /system/bin/settings get global private_dns_mode 2>/dev/null || echo "null")"
            spec="$(host_exec /system/bin/settings get global private_dns_specifier 2>/dev/null || echo "null")"
            printf '=== Android Private DNS Status ===\n'
            printf '  Mode:      %s\n' "$mode"
            printf '  Specifier: %s\n' "$spec"
            printf '\n=== ConnectivityService Verification ===\n'
            local conn_dns
            conn_dns="$(host_exec /system/bin/dumpsys connectivity 2>/dev/null | grep -E "UsePrivateDns|PrivateDnsServerName|ValidatedPrivateDnsAddresses" | head -n 6 || true)"
            if [[ -n "$conn_dns" ]]; then
                printf '%s\n' "$conn_dns"
            else
                printf '  (No active interface reporting Private DNS yet)\n'
            fi
            ;;
        auto|opportunistic)
            printf 'Setting Private DNS to opportunistic (Auto)...\n'
            host_exec /system/bin/settings put global private_dns_mode opportunistic
            host_exec /system/bin/settings delete global private_dns_specifier || true
            printf 'Private DNS set to Auto.\n'
            ;;
        off)
            printf 'Turning off Private DNS...\n'
            host_exec /system/bin/settings put global private_dns_mode off
            host_exec /system/bin/settings delete global private_dns_specifier || true
            printf 'Private DNS turned off.\n'
            ;;
        ali)
            cmd_dns hostname dns.alidns.com
            ;;
        dnspod)
            cmd_dns hostname dot.pub
            ;;
        cloudflare)
            cmd_dns hostname 1dot1dot1dot1.cloudflare-dns.com
            ;;
        google)
            cmd_dns hostname dns.google
            ;;
        hostname)
            local domain="${2:-}"
            if [[ -z "$domain" ]]; then
                printf 'error: missing domain. Usage: miui-settings.sh dns hostname <domain>\n' >&2
                exit 2
            fi
            printf 'Setting Private DNS hostname to %s...\n' "$domain"
            host_exec /system/bin/settings put global private_dns_mode hostname
            host_exec /system/bin/settings put global private_dns_specifier "$domain"
            printf 'Private DNS provider hostname configured to %s.\n' "$domain"
            sleep 1
            cmd_dns status
            ;;
        *)
            printf 'error: unknown dns subaction "%s".\n' "$subaction" >&2
            show_usage
            exit 2
            ;;
    esac
}

cmd_phantom() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            local monitor max_phantom am_setting
            monitor="$(host_exec /system/bin/settings get global settings_enable_monitor_phantom_procs 2>/dev/null || echo "null")"
            max_phantom="$(host_exec /system/bin/device_config get activity_manager max_phantom_processes 2>/dev/null || echo "null")"
            am_setting="$(host_exec /system/bin/dumpsys activity settings 2>/dev/null | grep -i "max_phantom_processes" || echo "  (default 32)")"
            printf '=== Android Phantom Process Killer Status ===\n'
            printf '  Monitor Enabled:      %s\n' "$monitor"
            printf '  Configured Max Limit: %s\n' "$max_phantom"
            printf '  ActivityManager Live: %s\n' "$am_setting"
            printf '\n=== Tracked Phantom Processes ===\n'
            local procs
            procs="$(host_exec /system/bin/dumpsys activity processes 2>/dev/null | grep -E "PhantomProcessRecord|knownSince" | head -n 10 || true)"
            if [[ -n "$procs" ]]; then
                printf '%s\n' "$procs"
            else
                printf '  (No phantom processes currently tracked)\n'
            fi
            ;;
        disable)
            printf 'Disabling Phantom Process Killer & maximizing limit to 2147483647...\n'
            host_exec /system/bin/settings put global settings_enable_monitor_phantom_procs false
            host_exec /system/bin/device_config put activity_manager max_phantom_processes 2147483647
            printf 'Phantom Process Killer disabled successfully.\n'
            cmd_phantom status
            ;;
        enable)
            printf 'Re-enabling stock Phantom Process Killer monitoring...\n'
            host_exec /system/bin/settings put global settings_enable_monitor_phantom_procs true
            host_exec /system/bin/device_config delete activity_manager max_phantom_processes || true
            printf 'Stock Phantom Process Killer re-enabled.\n'
            cmd_phantom status
            ;;
        limit)
            local num="${2:-}"
            if [[ -z "$num" ]] || ! [[ "$num" =~ ^[0-9]+$ ]]; then
                printf 'error: limit requires a numeric argument. Usage: miui-settings.sh phantom limit <num>\n' >&2
                exit 2
            fi
            printf 'Setting max_phantom_processes to %s...\n' "$num"
            host_exec /system/bin/device_config put activity_manager max_phantom_processes "$num"
            cmd_phantom status
            ;;
        *)
            printf 'error: unknown phantom subaction "%s".\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_refresh_rate() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            local min peak user_rate miui_rate smart_fps active_vote
            min="$(host_exec /system/bin/settings get system min_refresh_rate 2>/dev/null || echo "null")"
            peak="$(host_exec /system/bin/settings get system peak_refresh_rate 2>/dev/null || echo "null")"
            user_rate="$(host_exec /system/bin/settings get secure user_refresh_rate 2>/dev/null || echo "null")"
            miui_rate="$(host_exec /system/bin/settings get secure miui_refresh_rate 2>/dev/null || echo "null")"
            smart_fps="$(host_exec /system/bin/settings get system is_smart_fps 2>/dev/null || echo "null")"
            active_vote="$(host_exec /system/bin/dumpsys display 2>/dev/null | grep -A 2 "PRIORITY_MIUI_REFRESH_RATE" | head -n 3 || echo "  (not found)")"

            printf '=== MIUI Display & Refresh Rate Status ===\n'
            printf '  system min_refresh_rate:   %s\n' "$min"
            printf '  system peak_refresh_rate:  %s\n' "$peak"
            printf '  secure miui_refresh_rate:  %s\n' "$miui_rate"
            printf '  secure user_refresh_rate:  %s\n' "$user_rate"
            printf '  system is_smart_fps:       %s\n' "$smart_fps"
            printf '\n=== DisplayModeDirector Live Vote ===\n'
            printf '%s\n' "$active_vote"
            ;;
        60)
            printf 'Switching display refresh rate to 60Hz...\n'
            host_exec /system/bin/settings put secure miui_refresh_rate 60
            host_exec /system/bin/settings put secure user_refresh_rate 60
            host_exec /system/bin/settings put system peak_refresh_rate 60.0
            host_exec /system/bin/settings put system min_refresh_rate 60.0
            printf 'Refresh rate set to 60Hz.\n'
            sleep 0.5
            cmd_refresh_rate status
            ;;
        90)
            printf 'Switching display refresh rate to 90Hz...\n'
            host_exec /system/bin/settings put secure miui_refresh_rate 90
            host_exec /system/bin/settings put secure user_refresh_rate 90
            host_exec /system/bin/settings put system peak_refresh_rate 90.0
            host_exec /system/bin/settings put system min_refresh_rate 90.0
            printf 'Refresh rate set to 90Hz.\n'
            sleep 0.5
            cmd_refresh_rate status
            ;;
        120)
            printf 'Locking display refresh rate to constant 120Hz (disabling smart dynamic drop)...\n'
            host_exec /system/bin/settings put secure miui_refresh_rate 120
            host_exec /system/bin/settings put secure user_refresh_rate 120
            host_exec /system/bin/settings put system peak_refresh_rate 120.0
            host_exec /system/bin/settings put system min_refresh_rate 120.0
            host_exec /system/bin/settings put system is_smart_fps 0
            printf 'Display locked to 120Hz.\n'
            sleep 0.5
            cmd_refresh_rate status
            ;;
        auto|dynamic)
            printf 'Restoring MIUI smart dynamic refresh rate (up to 120Hz)...\n'
            host_exec /system/bin/settings put secure miui_refresh_rate 120
            host_exec /system/bin/settings put secure user_refresh_rate 120
            host_exec /system/bin/settings put system peak_refresh_rate 120.0
            host_exec /system/bin/settings delete system min_refresh_rate || true
            host_exec /system/bin/settings put system is_smart_fps 1
            printf 'Dynamic refresh rate restored.\n'
            sleep 0.5
            cmd_refresh_rate status
            ;;
        *)
            printf 'error: unknown refresh-rate action "%s". Supported: status, 60, 90, 120, auto\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_animation() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            local w t a
            w="$(host_exec /system/bin/settings get global window_animation_scale 2>/dev/null || echo "null")"
            t="$(host_exec /system/bin/settings get global transition_animation_scale 2>/dev/null || echo "null")"
            a="$(host_exec /system/bin/settings get global animator_duration_scale 2>/dev/null || echo "null")"
            printf '=== System Animation Scales ===\n'
            printf '  Window Animation Scale:    %s\n' "$w"
            printf '  Transition Animation Scale:%s\n' "$t"
            printf '  Animator Duration Scale:   %s\n' "$a"
            ;;
        off|0)
            printf 'Disabling system animation scales (instant transitions)...\n'
            host_exec /system/bin/settings put global window_animation_scale 0.0
            host_exec /system/bin/settings put global transition_animation_scale 0.0
            host_exec /system/bin/settings put global animator_duration_scale 0.0
            printf 'Animations disabled.\n'
            cmd_animation status
            ;;
        fast|0.5)
            printf 'Setting system animation scales to 0.5x (fast transitions)...\n'
            host_exec /system/bin/settings put global window_animation_scale 0.5
            host_exec /system/bin/settings put global transition_animation_scale 0.5
            host_exec /system/bin/settings put global animator_duration_scale 0.5
            printf 'Animations set to 0.5x.\n'
            cmd_animation status
            ;;
        normal|1|1.0)
            printf 'Restoring system animation scales to stock 1.0x...\n'
            host_exec /system/bin/settings put global window_animation_scale 1.0
            host_exec /system/bin/settings put global transition_animation_scale 1.0
            host_exec /system/bin/settings put global animator_duration_scale 1.0
            printf 'Animations restored to 1.0x.\n'
            cmd_animation status
            ;;
        *)
            printf 'error: unknown animation subaction "%s". Supported: status, off, fast, normal\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_powerkeeper() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            printf '=== Xiaomi PowerKeeper AppOps Status ===\n'
            for op in RUN_IN_BACKGROUND WRITE_SETTINGS GET_USAGE_STATS; do
                printf '  %s: ' "$op"
                host_exec /system/bin/cmd appops get com.miui.powerkeeper "$op" 2>&1 | tr -d '\r'
            done
            ;;
        restrict)
            printf 'Restricting com.miui.powerkeeper RUN_IN_BACKGROUND (preventing background killing)...\n'
            host_exec /system/bin/cmd appops set com.miui.powerkeeper RUN_IN_BACKGROUND ignore
            printf 'PowerKeeper restricted.\n'
            cmd_powerkeeper status
            ;;
        restore)
            printf 'Restoring com.miui.powerkeeper RUN_IN_BACKGROUND to default...\n'
            host_exec /system/bin/cmd appops set com.miui.powerkeeper RUN_IN_BACKGROUND default
            printf 'PowerKeeper AppOps restored.\n'
            cmd_powerkeeper status
            ;;
        *)
            printf 'error: unknown powerkeeper action "%s". Supported: status, restrict, restore\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_doze() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            printf '=== Android Doze Whitelist (Partial) ===\n'
            host_exec /system/bin/dumpsys deviceidle whitelist 2>/dev/null | grep -E "termux|miui|powerkeeper|google" || true
            ;;
        whitelist)
            local pkg="${2:-}"
            if [[ -z "$pkg" ]]; then
                printf 'error: package name required. Usage: miui-settings.sh doze whitelist <pkg>\n' >&2
                exit 2
            fi
            printf 'Adding %s to Doze whitelist...\n' "$pkg"
            host_exec /system/bin/dumpsys deviceidle whitelist "+$pkg"
            printf 'Package %s whitelisted in Doze.\n' "$pkg"
            ;;
        unwhitelist)
            local pkg="${2:-}"
            if [[ -z "$pkg" ]]; then
                printf 'error: package name required. Usage: miui-settings.sh doze unwhitelist <pkg>\n' >&2
                exit 2
            fi
            printf 'Removing %s from Doze whitelist...\n' "$pkg"
            host_exec /system/bin/dumpsys deviceidle whitelist "-$pkg"
            printf 'Package %s removed from Doze whitelist.\n' "$pkg"
            ;;
        *)
            printf 'error: unknown doze action "%s". Supported: status, whitelist <pkg>, unwhitelist <pkg>\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_preset() {
    local preset="${1:-}"
    if [[ -z "$preset" ]]; then
        printf 'error: preset name required. Available presets: performance, balanced, battery, stock\n' >&2
        exit 2
    fi

    case "$preset" in
        performance)
            printf '>>> Applying [Performance Preset] for AI Agent Workloads <<<\n'
            cmd_phantom disable
            cmd_refresh_rate 120
            cmd_animation fast
            cmd_powerkeeper restrict
            cmd_doze whitelist com.termux
            printf '\nPerformance preset applied successfully.\n'
            ;;
        balanced)
            printf '>>> Applying [Balanced Preset] <<<\n'
            cmd_phantom limit 512
            cmd_refresh_rate auto
            cmd_animation fast
            cmd_powerkeeper restore
            cmd_doze whitelist com.termux
            printf '\nBalanced preset applied successfully.\n'
            ;;
        battery)
            printf '>>> Applying [Battery Saver Preset] <<<\n'
            cmd_phantom limit 128
            cmd_refresh_rate 60
            cmd_animation normal
            cmd_powerkeeper restore
            printf '\nBattery preset applied successfully.\n'
            ;;
        stock)
            printf '>>> Restoring [Stock Default Settings] <<<\n'
            cmd_phantom enable
            cmd_refresh_rate auto
            cmd_animation normal
            cmd_powerkeeper restore
            printf '\nStock default settings restored.\n'
            ;;
        *)
            printf 'error: unknown preset "%s". Supported: performance, balanced, battery, stock\n' "$preset" >&2
            exit 2
            ;;
    esac
}

cmd_input() {
    local subaction="${1:-focus}"
    case "$subaction" in
        focus)
            printf '=== Foreground Window & Activity Focus ===\n'
            host_exec /system/bin/dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" || true
            ;;
        tap)
            local x="${2:-}" y="${3:-}"
            if [[ -z "$x" || -z "$y" ]]; then
                printf 'error: tap requires x y coordinates. Usage: miui-settings.sh input tap <x> <y>\n' >&2
                exit 2
            fi
            local cur_focus
            cur_focus="$(host_exec /system/bin/dumpsys window 2>/dev/null | grep "mCurrentFocus" || true)"
            if [[ "$cur_focus" =~ com.termux ]]; then
                printf 'WARNING: Current focus is Termux (%s). Tapping may hit terminal keyboard!\n' "$cur_focus"
            fi
            printf 'Dispatching tap at (%s, %s)...\n' "$x" "$y"
            host_exec /system/bin/input tap "$x" "$y"
            ;;
        swipe)
            local x1="${2:-}" y1="${3:-}" x2="${4:-}" y2="${5:-}" duration="${6:-300}"
            if [[ -z "$x1" || -z "$y1" || -z "$x2" || -z "$y2" ]]; then
                printf 'error: swipe requires x1 y1 x2 y2. Usage: miui-settings.sh input swipe <x1> <y1> <x2> <y2> [duration_ms]\n' >&2
                exit 2
            fi
            printf 'Dispatching swipe (%s,%s) -> (%s,%s) in %sms...\n' "$x1" "$y1" "$x2" "$y2" "$duration"
            host_exec /system/bin/input swipe "$x1" "$y1" "$x2" "$y2" "$duration"
            ;;
        key)
            local keycode="${2:-}"
            if [[ -z "$keycode" ]]; then
                printf 'error: key code required. Usage: miui-settings.sh input key <code_or_name>\n' >&2
                exit 2
            fi
            printf 'Dispatching keyevent %s...\n' "$keycode"
            host_exec /system/bin/input keyevent "$keycode"
            ;;
        text)
            local txt="${2:-}"
            if [[ -z "$txt" ]]; then
                printf 'error: text string required. Usage: miui-settings.sh input text <string>\n' >&2
                exit 2
            fi
            printf 'Typing text: %s...\n' "$txt"
            host_exec /system/bin/input text "$txt"
            ;;
        launch)
            local target="${2:-}"
            if [[ -z "$target" ]]; then
                printf 'error: target required. Usage: miui-settings.sh input launch <action_or_component>\n' >&2
                exit 2
            fi
            if [[ "$target" =~ / ]]; then
                printf 'Launching component %s...\n' "$target"
                host_exec /system/bin/am start -n "$target"
            elif [[ "$target" =~ \. ]]; then
                printf 'Launching action %s...\n' "$target"
                host_exec /system/bin/am start -a "$target"
            else
                printf 'Launching package %s...\n' "$target"
                host_exec /system/bin/monkey -p "$target" -c android.intent.category.LAUNCHER 1
            fi
            ;;
        *)
            printf 'error: unknown input action "%s".\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_screencap() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        target="/sdcard/screenshot_$(date +%Y%m%d_%H%M%S).png"
    fi

    # Check if target is a direct Android host path
    if [[ "$target" =~ ^/sdcard/ || "$target" =~ ^/storage/emulated/0/ || "$target" =~ ^/data/local/tmp/ ]]; then
        printf 'Capturing screen to host Android path %s...\n' "$target"
        host_exec /system/bin/screencap -p "$target"
        if host_exec /system/bin/test -s "$target"; then
            printf 'Screenshot saved successfully: %s\n' "$target"
        else
            printf 'error: screencap failed to write to %s.\n' "$target" >&2
            exit 1
        fi
    else
        # Target is a container local path (e.g. /root/md/screen.png or ./test.png)
        local abs_target
        if [[ "$target" = /* ]]; then
            abs_target="$target"
        else
            abs_target="$(pwd)/$target"
        fi
        mkdir -p "$(dirname "$abs_target")"

        local tmp_host_file="/sdcard/.screencap_tmp_$(date +%s%N).png"
        local tmp_container_file="/android/storage/emulated/0/${tmp_host_file#/sdcard/}"

        printf 'Capturing screen to container path %s...\n' "$abs_target"
        host_exec /system/bin/screencap -p "$tmp_host_file"

        if [[ -f "$tmp_container_file" && -s "$tmp_container_file" ]]; then
            mv "$tmp_container_file" "$abs_target"
            printf 'Screenshot successfully saved to container: %s (%s bytes)\n' "$abs_target" "$(wc -c < "$abs_target" | tr -d ' ')"
        else
            printf 'error: screencap intermediate file was not found at %s.\n' "$tmp_container_file" >&2
            exit 1
        fi
    fi
}

cmd_backup() {
    if ! command -v jq >/dev/null 2>&1; then
        printf 'error: jq utility is required for settings backup. Install with: apt-get install -y jq\n' >&2
        exit 1
    fi

    local target="${1:-/root/md/settings_backup_$(date +%Y%m%d_%H%M%S).json}"
    mkdir -p "$(dirname "$target")"

    printf 'Creating complete snapshot of Android & MIUI settings...\n'
    local model os_rel miui_ver
    model="$(host_exec /system/bin/getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "unknown")"
    os_rel="$(host_exec /system/bin/getprop ro.build.version.release 2>/dev/null | tr -d '\r' || echo "unknown")"
    miui_ver="$(host_exec /system/bin/getprop ro.miui.ui.version.name 2>/dev/null | tr -d '\r' || echo "unknown")"

    local g_json s_json sec_json
    g_json="$(host_exec /system/bin/settings list global | jq -R -s 'split("\n") | map(select(length > 0 and contains("="))) | map({(.[0:index("=")]): .[index("=")+1:]}) | add // {}')"
    s_json="$(host_exec /system/bin/settings list system | jq -R -s 'split("\n") | map(select(length > 0 and contains("="))) | map({(.[0:index("=")]): .[index("=")+1:]}) | add // {}')"
    sec_json="$(host_exec /system/bin/settings list secure | jq -R -s 'split("\n") | map(select(length > 0 and contains("="))) | map({(.[0:index("=")]): .[index("=")+1:]}) | add // {}')"

    jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg model "$model" \
        --arg os "$os_rel" \
        --arg miui "$miui_ver" \
        --argjson global "$g_json" \
        --argjson system "$s_json" \
        --argjson secure "$sec_json" \
        '{
            timestamp: $ts,
            device: {
                model: $model,
                android_version: $os,
                miui_version: $miui
            },
            global: $global,
            system: $system,
            secure: $secure
        }' > "$target"

    printf 'Settings snapshot successfully written to: %s\n' "$target"
    jq -r '"  Summary: global=\(.global | length) keys, system=\(.system | length) keys, secure=\(.secure | length) keys"' "$target"
}

cmd_restore() {
    if ! command -v jq >/dev/null 2>&1; then
        printf 'error: jq utility is required for settings restore. Install with: apt-get install -y jq\n' >&2
        exit 1
    fi

    local backup_file="${1:-}"
    shift || true

    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        printf 'error: valid backup JSON file required. Usage: miui-settings.sh restore <backup.json> [--all|--dns|--display|--animation|--phantom|--dry-run]\n' >&2
        exit 2
    fi

    local restore_mode="managed"
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                restore_mode="all"
                ;;
            --dns)
                restore_mode="dns"
                ;;
            --display|--refresh)
                restore_mode="display"
                ;;
            --animation)
                restore_mode="animation"
                ;;
            --phantom)
                restore_mode="phantom"
                ;;
            --dry-run)
                dry_run=1
                ;;
            *)
                printf 'warning: unknown restore option "%s", ignoring.\n' "$1" >&2
                ;;
        esac
        shift
    done

    printf 'Restoring settings from %s (mode: %s, dry_run: %d)...\n' "$backup_file" "$restore_mode" "$dry_run"

    apply_key() {
        local ns="$1" key="$2" val="$3"
        if [[ "$dry_run" -eq 1 ]]; then
            printf '[DRY-RUN] settings put %s %s "%s"\n' "$ns" "$key" "$val"
        else
            host_exec /system/bin/settings put "$ns" "$key" "$val"
            printf '  Restored %s.%s = "%s"\n' "$ns" "$key" "$val"
        fi
    }

    if [[ "$restore_mode" == "dns" || "$restore_mode" == "all" || "$restore_mode" == "managed" ]]; then
        local dns_mode dns_spec
        dns_mode="$(jq -r '.global.private_dns_mode // empty' "$backup_file")"
        dns_spec="$(jq -r '.global.private_dns_specifier // empty' "$backup_file")"
        if [[ -n "$dns_mode" ]]; then apply_key "global" "private_dns_mode" "$dns_mode"; fi
        if [[ -n "$dns_spec" ]]; then apply_key "global" "private_dns_specifier" "$dns_spec"; fi
    fi

    if [[ "$restore_mode" == "display" || "$restore_mode" == "all" || "$restore_mode" == "managed" ]]; then
        local peak min user_rate miui_rate smart_fps
        peak="$(jq -r '.system.peak_refresh_rate // empty' "$backup_file")"
        min="$(jq -r '.system.min_refresh_rate // empty' "$backup_file")"
        user_rate="$(jq -r '.secure.user_refresh_rate // empty' "$backup_file")"
        miui_rate="$(jq -r '.secure.miui_refresh_rate // empty' "$backup_file")"
        smart_fps="$(jq -r '.system.is_smart_fps // empty' "$backup_file")"

        if [[ -n "$peak" ]]; then apply_key "system" "peak_refresh_rate" "$peak"; fi
        if [[ -n "$min" ]]; then apply_key "system" "min_refresh_rate" "$min"; fi
        if [[ -n "$user_rate" ]]; then apply_key "secure" "user_refresh_rate" "$user_rate"; fi
        if [[ -n "$miui_rate" ]]; then apply_key "secure" "miui_refresh_rate" "$miui_rate"; fi
        if [[ -n "$smart_fps" ]]; then apply_key "system" "is_smart_fps" "$smart_fps"; fi
    fi

    if [[ "$restore_mode" == "animation" || "$restore_mode" == "all" || "$restore_mode" == "managed" ]]; then
        local w t a
        w="$(jq -r '.global.window_animation_scale // empty' "$backup_file")"
        t="$(jq -r '.global.transition_animation_scale // empty' "$backup_file")"
        a="$(jq -r '.global.animator_duration_scale // empty' "$backup_file")"

        if [[ -n "$w" ]]; then apply_key "global" "window_animation_scale" "$w"; fi
        if [[ -n "$t" ]]; then apply_key "global" "transition_animation_scale" "$t"; fi
        if [[ -n "$a" ]]; then apply_key "global" "animator_duration_scale" "$a"; fi
    fi

    if [[ "$restore_mode" == "phantom" || "$restore_mode" == "all" || "$restore_mode" == "managed" ]]; then
        local phantom_mon
        phantom_mon="$(jq -r '.global.settings_enable_monitor_phantom_procs // empty' "$backup_file")"
        if [[ -n "$phantom_mon" ]]; then apply_key "global" "settings_enable_monitor_phantom_procs" "$phantom_mon"; fi
    fi

    if [[ "$restore_mode" == "all" ]]; then
        printf 'Full bulk restore: applying remaining keys...\n'
        for ns in global system secure; do
            while IFS='=' read -r k v; do
                [[ -z "$k" ]] && continue
                apply_key "$ns" "$k" "$v"
            done < <(jq -r ".$ns | to_entries[] | \"\(.key)=\(.value)\"" "$backup_file")
        done
    fi

    printf 'Restore operation completed.\n'
}

cmd_dnd() {
    local subaction="${1:-status}"
    case "$subaction" in
        status)
            local zen_mode mode_ringer quiet_mode
            zen_mode="$(host_exec /system/bin/settings get global zen_mode 2>/dev/null || echo "null")"
            mode_ringer="$(host_exec /system/bin/settings get global mode_ringer 2>/dev/null || echo "null")"
            quiet_mode="$(host_exec /system/bin/settings get secure quiet_mode_enable 2>/dev/null || echo "null")"
            printf '=== Do Not Disturb & Zen Mode Status ===\n'
            printf '  global zen_mode:          %s (0=off, 1=priority, 2=total silence, 3=alarms)\n' "$zen_mode"
            printf '  global mode_ringer:       %s (0=silent, 1=vibrate, 2=normal)\n' "$mode_ringer"
            printf '  secure quiet_mode_enable: %s\n' "$quiet_mode"
            printf '\n=== Active Notification Policy ===\n'
            host_exec /system/bin/dumpsys notification --noredact 2>/dev/null | grep -A 4 "mConfig=allow" || true
            ;;
        contacts-only|contacts)
            printf 'Enabling Do Not Disturb (Contacts Only Ringing)...\n'
            # 1. Ensure ringer mode is normal so whitelisted calls can ring
            host_exec /system/bin/settings put global mode_ringer 2
            # 2. Sync MIUI Quiet Mode
            host_exec /system/bin/settings put secure quiet_mode_enable 1
            # 3. Set Android DND to Priority Mode
            host_exec /system/bin/cmd notification set_dnd priority
            # 4. Ensure media volume is audible (not muted at 0)
            local cur_media
            cur_media="$(host_exec /system/bin/cmd media_session volume --stream 3 --get 2>/dev/null | grep -o 'volume is [0-9]*' | awk 'NR==1{print $3}' || echo "0")"
            if [[ "$cur_media" -eq 0 ]]; then
                printf 'Media volume was 0 (muted). Setting STREAM_MUSIC to 75 (50%%)...\n'
                host_exec /system/bin/cmd media_session volume --stream 3 --set 75
            fi
            printf 'Contacts-only ringing policy successfully applied.\n'
            cmd_dnd status
            ;;
        off)
            printf 'Turning off Do Not Disturb...\n'
            host_exec /system/bin/settings put secure quiet_mode_enable 0
            host_exec /system/bin/cmd notification set_dnd off
            printf 'Do Not Disturb turned off.\n'
            cmd_dnd status
            ;;
        on|all)
            printf 'Turning on Do Not Disturb...\n'
            host_exec /system/bin/settings put secure quiet_mode_enable 1
            host_exec /system/bin/cmd notification set_dnd on
            cmd_dnd status
            ;;
        *)
            printf 'error: unknown dnd action "%s". Supported: status, contacts-only, off, on\n' "$subaction" >&2
            exit 2
            ;;
    esac
}

cmd_volume() {
    local stream="${1:-status}"
    case "$stream" in
        status)
            printf '=== Audio Stream Volumes ===\n'
            for s in 3 2 4 5; do
                local sname
                case "$s" in
                    3) sname="Media (STREAM_MUSIC)" ;;
                    2) sname="Ringtone (STREAM_RING)" ;;
                    4) sname="Alarm (STREAM_ALARM)" ;;
                    5) sname="Notification (STREAM_NOTIFICATION)" ;;
                esac
                printf '  %s: ' "$sname"
                host_exec /system/bin/cmd media_session volume --stream "$s" --get 2>&1 | grep "volume is" || true
            done
            ;;
        media)
            local val="${2:-}"
            [[ -z "$val" ]] && { printf 'error: volume value required. Usage: miui-settings.sh volume media <0-150>\n' >&2; exit 2; }
            host_exec /system/bin/cmd media_session volume --stream 3 --set "$val"
            cmd_volume status
            ;;
        ring)
            local val="${2:-}"
            [[ -z "$val" ]] && { printf 'error: volume value required. Usage: miui-settings.sh volume ring <0-15>\n' >&2; exit 2; }
            host_exec /system/bin/cmd media_session volume --stream 2 --set "$val"
            cmd_volume status
            ;;
        alarm)
            local val="${2:-}"
            [[ -z "$val" ]] && { printf 'error: volume value required. Usage: miui-settings.sh volume alarm <1-15>\n' >&2; exit 2; }
            host_exec /system/bin/cmd media_session volume --stream 4 --set "$val"
            cmd_volume status
            ;;
        *)
            printf 'error: unknown volume action "%s". Supported: status, media <N>, ring <N>, alarm <N>\n' "$stream" >&2
            exit 2
            ;;
    esac
}

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    local action="$1"
    shift

    case "$action" in
        get)
            [[ $# -lt 2 ]] && { show_usage; exit 2; }
            local ns="$1" key="$2"
            host_exec /system/bin/settings get "$ns" "$key"
            ;;
        put)
            [[ $# -lt 3 ]] && { show_usage; exit 2; }
            local ns="$1" key="$2" val="$3"
            host_exec /system/bin/settings put "$ns" "$key" "$val"
            ;;
        delete)
            [[ $# -lt 2 ]] && { show_usage; exit 2; }
            local ns="$1" key="$2"
            host_exec /system/bin/settings delete "$ns" "$key"
            ;;
        list)
            [[ $# -lt 1 ]] && { show_usage; exit 2; }
            local ns="$1" pattern="${2:-}"
            if [[ -n "$pattern" ]]; then
                host_exec /system/bin/settings list "$ns" | grep -Ei "$pattern" || true
            else
                host_exec /system/bin/settings list "$ns"
            fi
            ;;
        dns)
            cmd_dns "$@"
            ;;
        phantom)
            cmd_phantom "$@"
            ;;
        refresh-rate|refresh)
            cmd_refresh_rate "$@"
            ;;
        animation|anim)
            cmd_animation "$@"
            ;;
        powerkeeper)
            cmd_powerkeeper "$@"
            ;;
        doze)
            cmd_doze "$@"
            ;;
        dnd|quiet)
            cmd_dnd "$@"
            ;;
        volume|vol)
            cmd_volume "$@"
            ;;
        preset)
            cmd_preset "$@"
            ;;
        input)
            cmd_input "$@"
            ;;
        screencap)
            cmd_screencap "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            printf 'error: unknown action "%s".\n' "$action" >&2
            show_usage
            exit 2
            ;;
    esac
}

main "$@"
