import QtQuick
import Quickshell
import Quickshell.Io

Process {
    id: root

    property int timeoutMs: 0
    property bool timedOut: false

    signal timeoutReached()

    // QProcess signals only the direct child, so a bash wrapper's own children outlive it;
    // collect the tree before TERM, then signal only pids whose start time still matches
    readonly property string _terminateTreeScript:
        'root_pid=$1; case $root_pid in ""|*[!0-9]*) exit 0;; esac; ' +
        'pids=(); starts=(); seen=" "; ' +
        'start_of() { local line rest; { IFS= read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1; ' +
        'rest=${line##*) }; set -- $rest; [ "$#" -ge 20 ] || return 1; printf "%s\\n" "${20}"; }; ' +
        'remember() { local pid=$1 start; case "$seen" in *" $pid "*) return;; esac; ' +
        'start=$(start_of "$pid") || return; seen="$seen$pid "; pids+=("$pid"); starts+=("$start"); }; ' +
        'collect() { local parent=$1 stat line pid rest ppid; for stat in /proc/[0-9]*/stat; do ' +
        '{ IFS= read -r line < "$stat"; } 2>/dev/null || continue; pid=${line%% *}; rest=${line##*) }; ' +
        'set -- $rest; ppid=${2:-}; [ "$ppid" = "$parent" ] && collect "$pid"; done; remember "$parent"; }; ' +
        'signal_saved() { local sig=$1 i current; for ((i=0; i<${#pids[@]}; i++)); do ' +
        'current=$(start_of "${pids[i]}") || continue; [ "$current" = "${starts[i]}" ] ' +
        '&& kill -s "$sig" "${pids[i]}" 2>/dev/null || true; done; }; ' +
        'root_start=$(start_of "$root_pid") || exit 0; collect "$root_pid"; signal_saved TERM; sleep 2; ' +
        'current=$(start_of "$root_pid") || current=; [ "$current" != "$root_start" ] || collect "$root_pid"; ' +
        'signal_saved KILL'

    // a binary that is gone fails to start without emitting exited, and callers recover only there
    property bool _exitSeen: false
    property Connections _runningWatch: Connections {
        target: root
        function onExited() { root._exitSeen = true }
        function onRunningChanged() {
            if (root.running) {
                root.timedOut = false
                return
            }
            if (!root._exitSeen) root.exited(127, 0)
            root._exitSeen = false
        }
    }

    property Timer _timeout: Timer {
        interval: Math.max(1, root.timeoutMs)
        running: root.running && root.timeoutMs > 0
        onTriggered: {
            if (!root.running) return
            root.timedOut = true
            const pid = root.processId
            if (pid > 0)
                Quickshell.execDetached(["bash", "-c", root._terminateTreeScript,
                    "silere-timeout", String(pid)])
            else
                root.running = false
            root.timeoutReached()
        }
    }

    // backstop a tree helper that never ran; its own KILL pass normally lands first
    property Timer _killGrace: Timer {
        interval: 3000
        running: root.timedOut && root.running
        onTriggered: {
            const pid = root.processId
            if (root.running && pid > 0)
                Quickshell.execDetached(["kill", "-KILL", String(pid)])
        }
    }
}
