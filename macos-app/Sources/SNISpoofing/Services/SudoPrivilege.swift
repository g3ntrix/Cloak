import Foundation
import AppKit

/// One-time admin escalation that installs NOPASSWD sudoers helpers so the
/// app can run the Python listener, toggle the system SOCKS proxy, and bring
/// up a utun-based packet tunnel without a password prompt on every action.
///
/// Helpers (all root-owned, scoped to specific scripts in the sudoers rule):
///   - `/usr/local/bin/cloak-listener` — runs the bundled PyInstaller SNI listener.
///   - `/usr/local/bin/cloak-proxy`    — enables/disables the macOS system SOCKS proxy.
///   - `/usr/local/bin/cloak-tun`      — spawns bundled tun2socks + manages utun routes.
enum SudoPrivilege {
    static let sudoersPath = "/etc/sudoers.d/cloak"
    static let wrapperPath = "/usr/local/bin/cloak-listener"
    static let proxyHelperPath = "/usr/local/bin/cloak-proxy"
    static let tunHelperPath = "/usr/local/bin/cloak-tun"
    /// Bumped whenever any embedded script changes — forces re-install.
    static let wrapperVersion = "12"

    enum SudoError: LocalizedError {
        case promptCancelled
        case installFailed(String)
        case missingListenerCore

        var errorDescription: String? {
            switch self {
            case .promptCancelled:
                return "Admin permission was cancelled. Cloak needs it once to set up its background helpers."
            case .installFailed(let msg):
                return "Setup failed: \(msg)"
            case .missingListenerCore:
                return "Bundled listener binary is missing. Reinstall Cloak from a full release build."
            }
        }
    }

    /// Fire-and-forget: ask the installed root wrapper to pkill any python it spawned.
    /// Used on app termination so a crashed/force-quit Cloak doesn't leave a listener
    /// consuming CPU. Safe to call when nothing is running.
    static func killLeftoverListener() {
        guard FileManager.default.isExecutableFile(atPath: wrapperPath) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", wrapperPath, "--kill-leftover"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    /// Run the proxy helper passwordless. Returns exit status (0 = success).
    @discardableResult
    static func runProxyHelper(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", proxyHelperPath] + args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Run the tun helper passwordless. Returns (exit status, captured stdout).
    /// Used by `PacketTunnelManager` to start/stop the utun + tun2socks bridge.
    @discardableResult
    static func runTunHelper(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", tunHelperPath] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, "") }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, text)
    }

    /// True when all helpers are installed and NOPASSWD sudo works against them.
    static func isInstalled() -> Bool {
        listenerHelperReady() && proxyHelperReady() && tunHelperReady()
    }

    static func listenerHelperReady() -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: wrapperPath),
              fm.fileExists(atPath: sudoersPath)
        else { return false }
        return selfCheck(wrapperPath, expectVersion: wrapperVersion)
    }

    static func proxyHelperReady() -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: proxyHelperPath),
              fm.fileExists(atPath: sudoersPath)
        else { return false }
        return selfCheck(proxyHelperPath, expectVersion: wrapperVersion)
    }

    static func tunHelperReady() -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: tunHelperPath),
              fm.fileExists(atPath: sudoersPath)
        else { return false }
        return selfCheck(tunHelperPath, expectVersion: wrapperVersion)
    }

    private static func selfCheck(_ helper: String, expectVersion: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helper, "--self-check"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return false }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text == expectVersion
        } catch {
            return false
        }
    }

    /// Prompts once for an admin password and installs both helpers + the sudoers rule.
    static func install() throws {
        guard let corePath = ListenerCore.bundledExecutablePath() else {
            throw SudoError.missingListenerCore
        }

        let user = NSUserName()
        let configPath = appSupportListenerConfigPath()

        let listenerScript = """
        #!/bin/bash
        # Auto-generated by Cloak. Runs the bundled SNI-spoofing listener as root.
        # The sudoers rule at /etc/sudoers.d/cloak only grants NOPASSWD for
        # running THIS file, so the surface is small and easy to audit.
        set -euo pipefail
        if [ "${1:-}" = "--self-check" ]; then echo "\(wrapperVersion)"; exit 0; fi
        if [ "${1:-}" = "--wrapper-version" ]; then echo "\(wrapperVersion)"; exit 0; fi
        if [ "${1:-}" = "--kill-leftover" ]; then
          /usr/bin/pkill -f \(wrapperPath) >/dev/null 2>&1 || true
          /usr/bin/pkill -f cloak-core- >/dev/null 2>&1 || true
          exit 0
        fi
        CORE=\"\(corePath)\"
        if [ ! -x \"$CORE\" ]; then
          echo \"error: bundled listener missing at $CORE — reinstall Cloak.\" >&2
          exit 12
        fi
        export CLOAK_CONFIG=\"\(configPath)\"
        export PYTHONUNBUFFERED=1
        export HOME=\"\(NSHomeDirectory())\"
        exec \"$CORE\" \"$@\"
        """

        let proxyScript = """
        #!/bin/bash
        # cloak-proxy: scoped wrapper that toggles the macOS system HTTP/HTTPS/SOCKS proxies
        # on every active network service via the whitelisted `networksetup`
        # subcommands. Sudoers grants NOPASSWD only for THIS path.
        set -euo pipefail
        if [ "${1:-}" = "--self-check" ]; then echo "\(wrapperVersion)"; exit 0; fi
        ACTION="${1:-}"
        HOST="${2:-}"
        SOCKS_PORT="${3:-}"
        HTTP_PORT="${4:-$SOCKS_PORT}"
        case "$ACTION" in
          enable)
            if [ -z "$HOST" ] || [ -z "$SOCKS_PORT" ] || [ -z "$HTTP_PORT" ]; then
              echo "usage: $0 enable <host> <socks-port> <http-port>" >&2; exit 1
            fi
            /usr/sbin/networksetup -listallnetworkservices \\
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \\
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setproxybypassdomains "$svc" localhost 127.0.0.1 ::1 2>/dev/null || true
                  /usr/sbin/networksetup -setwebproxy "$svc" "$HOST" "$HTTP_PORT" 2>/dev/null || true
                  /usr/sbin/networksetup -setsecurewebproxy "$svc" "$HOST" "$HTTP_PORT" 2>/dev/null || true
                  /usr/sbin/networksetup -setsocksfirewallproxy "$svc" "$HOST" "$SOCKS_PORT" off 2>/dev/null || true
                  /usr/sbin/networksetup -setwebproxystate "$svc" on 2>/dev/null || true
                  /usr/sbin/networksetup -setsecurewebproxystate "$svc" on 2>/dev/null || true
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" on 2>/dev/null || true
                done
            ;;
          disable)
            /usr/sbin/networksetup -listallnetworkservices \\
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \\
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setwebproxystate "$svc" off 2>/dev/null || true
                  /usr/sbin/networksetup -setsecurewebproxystate "$svc" off 2>/dev/null || true
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
                done
            ;;
          *)
            echo "usage: $0 enable <host> <socks-port> <http-port> | disable" >&2; exit 1
            ;;
        esac
        """

        let tunScript = """
        #!/bin/bash
        # cloak-tun: starts/stops a utun-based packet tunnel by spawning the
        # bundled tun2socks binary (received via --bin <path>) and rewriting the
        # default route through the new utun device. Sudoers grants NOPASSWD
        # only for THIS path, so the surface is limited to start/stop ops.
        set -uo pipefail
        STATE_DIR="/var/run/cloak-tun"
        PID_FILE="$STATE_DIR/tun2socks.pid"
        STATE_FILE="$STATE_DIR/state"
        LOG_FILE="$STATE_DIR/tun2socks.log"
        TUN_NAME="utun8"
        TUN_IP="198.18.0.1"
        TUN_NETMASK="255.255.255.0"

        if [ "${1:-}" = "--self-check" ]; then echo "\(wrapperVersion)"; exit 0; fi

        case "${1:-}" in
          start)
            shift
            CONNECT_IP=""; SOCKS_HOST="127.0.0.1"; SOCKS_PORT=""; TUN2SOCKS_BIN=""; LOGLEVEL="info"
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --connect-ip) CONNECT_IP="${2:-}"; shift 2 ;;
                --socks-host) SOCKS_HOST="${2:-}"; shift 2 ;;
                --socks-port) SOCKS_PORT="${2:-}"; shift 2 ;;
                --bin) TUN2SOCKS_BIN="${2:-}"; shift 2 ;;
                --loglevel) LOGLEVEL="${2:-info}"; shift 2 ;;
                *) echo "unknown arg: $1" >&2; exit 2 ;;
              esac
            done
            if [ -z "$SOCKS_PORT" ] || [ -z "$TUN2SOCKS_BIN" ]; then
              echo "usage: $0 start --connect-ip <ip> --socks-host <host> --socks-port <port> --bin <tun2socks-path> [--loglevel <lvl>]" >&2
              exit 1
            fi
            if [ ! -x "$TUN2SOCKS_BIN" ]; then
              echo "tun2socks not found / not executable: $TUN2SOCKS_BIN" >&2
              exit 1
            fi
            mkdir -p "$STATE_DIR"
            # Tear down anything left over from a prior run before bringing this up.
            if [ -f "$PID_FILE" ]; then
              OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
              if [ -n "$OLD_PID" ]; then
                kill "$OLD_PID" 2>/dev/null || true
              fi
              rm -f "$PID_FILE"
            fi
            DEFAULT_GW="$(/usr/sbin/netstat -rn -f inet | /usr/bin/awk '/^default/ {print $2; exit}')"
            DEFAULT_IF="$(/usr/sbin/netstat -rn -f inet | /usr/bin/awk '/^default/ {print $4; exit}')"
            if [ -z "$DEFAULT_GW" ] || [ -z "$DEFAULT_IF" ]; then
              echo "could not detect current default gateway" >&2
              exit 1
            fi
            if [ -n "$CONNECT_IP" ]; then
              /sbin/route -nq add -host "$CONNECT_IP" "$DEFAULT_GW" >/dev/null 2>&1 \\
                || /sbin/route -nq change -host "$CONNECT_IP" "$DEFAULT_GW" >/dev/null 2>&1 || true
            fi
            utun_before="$(/sbin/ifconfig -l | /usr/bin/tr ' ' '\\n' | /usr/bin/grep '^utun')"
            : > "$LOG_FILE"
            nohup "$TUN2SOCKS_BIN" \\
              -device "utun" \\
              -proxy "socks5://$SOCKS_HOST:$SOCKS_PORT" \\
              -loglevel "$LOGLEVEL" \\
              >> "$LOG_FILE" 2>&1 &
            T2S_PID=$!
            echo "$T2S_PID" > "$PID_FILE"
            # Wait up to ~3s for the dynamic utun device to appear.
            TUN_NAME=""
            for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
              utun_after="$(/sbin/ifconfig -l | /usr/bin/tr ' ' '\\n' | /usr/bin/grep '^utun')"
              for dev in $utun_after; do
                if ! echo "$utun_before" | /usr/bin/grep -q "^$dev$"; then
                  TUN_NAME="$dev"
                  break
                fi
              done
              if [ -n "$TUN_NAME" ]; then break; fi
              if ! kill -0 "$T2S_PID" 2>/dev/null; then
                echo "tun2socks exited early. Tail of $LOG_FILE:" >&2
                /usr/bin/tail -n 40 "$LOG_FILE" >&2 || true
                exit 1
              fi
              sleep 0.25
            done
            if [ -z "$TUN_NAME" ]; then
              echo "No new utun device came up; killing tun2socks" >&2
              kill "$T2S_PID" 2>/dev/null || true
              rm -f "$PID_FILE"
              exit 1
            fi
            /usr/bin/printf 'gw=%s\\nif=%s\\nconnect_ip=%s\\ntun=%s\\n' \\
              "$DEFAULT_GW" "$DEFAULT_IF" "$CONNECT_IP" "$TUN_NAME" > "$STATE_FILE"
            /sbin/ifconfig "$TUN_NAME" inet "$TUN_IP" "$TUN_IP" netmask "$TUN_NETMASK" up
            /sbin/route -nq delete default >/dev/null 2>&1 || true
            /sbin/route -nq add default -interface "$TUN_NAME"
            /usr/sbin/networksetup -listallnetworkservices \\
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \\
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setdnsservers "$svc" 1.1.1.1 8.8.8.8 2>/dev/null || true
                done
            /usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true
            echo "$TUN_NAME"
            ;;
          stop)
            if [ -f "$PID_FILE" ]; then
              PID="$(cat "$PID_FILE" 2>/dev/null || true)"
              if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                kill "$PID" 2>/dev/null || true
                for _ in 1 2 3 4 5 6 7 8; do
                  kill -0 "$PID" 2>/dev/null || break
                  sleep 0.25
                done
                kill -9 "$PID" 2>/dev/null || true
              fi
              rm -f "$PID_FILE"
            fi
            if [ -f "$STATE_FILE" ]; then
              # shellcheck disable=SC1090
              . "$STATE_FILE"
              /sbin/route -nq delete default >/dev/null 2>&1 || true
              if [ -n "${gw:-}" ]; then
                /sbin/route -nq add default "$gw" >/dev/null 2>&1 || true
              fi
              if [ -n "${connect_ip:-}" ]; then
                /sbin/route -nq delete -host "$connect_ip" >/dev/null 2>&1 || true
              fi
              rm -f "$STATE_FILE"
            fi
            /usr/sbin/networksetup -listallnetworkservices \\
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \\
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setdnsservers "$svc" empty 2>/dev/null || true
                done
            /usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true
            ;;
          status)
            if [ -f "$PID_FILE" ]; then
              PID="$(cat "$PID_FILE" 2>/dev/null || true)"
              if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then echo "running"; exit 0; fi
            fi
            echo "stopped"
            ;;
          *)
            echo "usage: $0 {start|stop|status}" >&2
            exit 1
            ;;
        esac
        """

        let listenerB64 = Data(listenerScript.utf8).base64EncodedString()
        let proxyB64 = Data(proxyScript.utf8).base64EncodedString()
        let tunB64 = Data(tunScript.utf8).base64EncodedString()

        let sudoersContent = """
        \(user) ALL=(ALL) NOPASSWD: \(wrapperPath)
        \(user) ALL=(ALL) NOPASSWD: \(proxyHelperPath)
        \(user) ALL=(ALL) NOPASSWD: \(tunHelperPath)
        """
        let sudoersB64 = Data(sudoersContent.utf8).base64EncodedString()

        let shell = """
        set -e
        mkdir -p /usr/local/bin
        echo '\(listenerB64)' | /usr/bin/base64 -D > '\(wrapperPath)'
        chown root:wheel '\(wrapperPath)'
        chmod 755 '\(wrapperPath)'
        echo '\(proxyB64)' | /usr/bin/base64 -D > '\(proxyHelperPath)'
        chown root:wheel '\(proxyHelperPath)'
        chmod 755 '\(proxyHelperPath)'
        echo '\(tunB64)' | /usr/bin/base64 -D > '\(tunHelperPath)'
        chown root:wheel '\(tunHelperPath)'
        chmod 755 '\(tunHelperPath)'
        echo '\(sudoersB64)' | /usr/bin/base64 -D > '\(sudoersPath)'
        chown root:wheel '\(sudoersPath)'
        chmod 440 '\(sudoersPath)'
        /usr/sbin/visudo -cf '\(sudoersPath)' >/dev/null
        # Best-effort cleanup of obsolete helpers from older versions so they
        # can't be invoked via a stale sudoers rule cached in another process.
        rm -f /usr/local/bin/cloak-xray /usr/local/bin/cloak-tun-routes 2>/dev/null || true
        """

        let appleScriptSource = """
        do shell script "\(escapeForAppleScript(shell))" with administrator privileges with prompt "Cloak needs one-time admin permission so it can start the listener and toggle the system proxy without asking for your password every time."
        """

        var err: NSDictionary?
        if let script = NSAppleScript(source: appleScriptSource) {
            _ = script.executeAndReturnError(&err)
        }
        if let e = err {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { throw SudoError.promptCancelled }
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown"
            throw SudoError.installFailed(msg)
        }
        guard isInstalled() else {
            throw SudoError.installFailed("Sudoers rule did not activate — try again.")
        }
    }

    /// Removes the sudoers rule and helper scripts (prompts for admin again).
    static func uninstall() throws {
        let shell = """
        rm -f '\(sudoersPath)'
        rm -f '\(wrapperPath)'
        rm -f '\(proxyHelperPath)'
        rm -f '\(tunHelperPath)'
        rm -f /usr/local/bin/cloak-xray /usr/local/bin/cloak-tun-routes
        rm -rf /var/run/cloak-tun
        """
        let source = """
        do shell script "\(escapeForAppleScript(shell))" with administrator privileges with prompt "Remove Cloak's passwordless helpers?"
        """
        var err: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&err)
        }
        if let e = err {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { throw SudoError.promptCancelled }
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown"
            throw SudoError.installFailed(msg)
        }
    }

    /// Writable config path the wrapper passes to the listener.
    static func appSupportListenerConfigPath() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SNISpoofing", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("listener-config.json").path
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default: out.append(ch)
            }
        }
        return out
    }
}
