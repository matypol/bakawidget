import QtQuick
import QtQuick.Layouts
import Qt.labs.platform as Labs
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import "Theme.js" as Theme

PlasmoidItem {
    id: root

    // ── backend wiring ───────────────────────────────────────────────
    // IPC choice (see contents/backend/bakawidget_backend.py docstring for
    // the full rationale): the backend publishes lessons as a JSON file
    // under $XDG_RUNTIME_DIR. This file is read here via the same
    // Plasma5Support "executable" data engine used for the one-shot write
    // actions (login/logout/interval changes, triggered from
    // ui/config/ConfigGeneral.qml) and the service self-heal below —
    // deliberately NOT via a file:// XMLHttpRequest, which is not a
    // documented/blessed QML API for local file access and has been
    // narrowed by security hardening passes elsewhere in Qt/Plasma before.
    // `cat`-ing the file through the executable engine costs one tiny
    // spawned process every poll tick instead of an in-process read, but
    // depends only on a primitive this project already relies on
    // elsewhere and knows is stable.
    readonly property string runtimeDirUrl: Labs.StandardPaths.writableLocation(Labs.StandardPaths.RuntimeLocation).toString()
    readonly property string stateFilePath: Theme.stripFileUrl(runtimeDirUrl) + "/bakawidget/state.json"

    property string status: "loading"
    property bool hasSchoolToday: true
    property bool stale: false
    property string errorMessage: ""
    property string lastUpdated: ""
    property var previousLesson: null
    property var currentLesson: null
    property var upcomingLessons: []
    property var allToday: []

    readonly property var headerLesson: currentLesson !== null ? currentLesson : (upcomingLessons.length > 0 ? upcomingLessons[0] : null)
    readonly property bool headerIsNext: currentLesson === null && headerLesson !== null
    readonly property var restOfDay: currentLesson !== null ? upcomingLessons : upcomingLessons.slice(1)
    readonly property var visibleUpcoming: upcomingLessons.slice(0, Math.max(1, Plasmoid.configuration.lessonCount))

    Plasmoid.title: "BakaWidget"
    // Never inline-expand the full card into the panel itself (e.g. on a
    // very tall vertical panel) — it should only ever appear as a hover
    // tooltip or a click popup, matching the reference's hover-only design.
    switchWidth: -1
    switchHeight: -1

    Timer {
        id: pollTimer
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.reloadState()
    }

    // ── self-heal the background service ────────────────────────────
    // A pacman/AUR install cannot enable a systemd --user unit itself —
    // package install hooks run as root with no access to any user's
    // session, so that step normally has to be manual (see README). To
    // keep the AUR path beginner-friendly, the plasmoid checks for its own
    // poller on load and enables+starts it silently if it isn't running
    // yet. This is a no-op (the `is-active` check short-circuits) on every
    // load after the first, and after installs that already handle this
    // themselves (install.sh, or a future distro package with proper user
    // service activation).
    Plasma5Support.DataSource {
        id: serviceSelfHeal
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    Component.onCompleted: {
        serviceSelfHeal.connectSource(
            "systemctl --user is-active --quiet bakawidget-backend.service "
            + "|| (systemctl --user daemon-reload && systemctl --user enable --now bakawidget-backend.service)"
        )
    }

    Plasma5Support.DataSource {
        id: stateReader
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data.stdout || ""
            if (out.length > 0) {
                try {
                    root.applyState(JSON.parse(out))
                } catch (e) {
                    console.warn("bakawidget: could not parse state.json:", e)
                }
            }
            // Empty stdout: no state file yet (backend never polled) or a
            // transient read race — root.status just stays whatever it
            // was, and the next 4-second tick tries again.
        }
    }

    function reloadState() {
        stateReader.connectSource("cat " + Theme.shQuote(root.stateFilePath) + " 2>/dev/null")
    }

    function applyState(data) {
        status = data.status || "loading"
        stale = !!data.stale
        errorMessage = data.error || ""
        hasSchoolToday = data.has_school_today !== false
        previousLesson = data.previous || null
        currentLesson = data.current || null
        upcomingLessons = data.upcoming || []
        allToday = data.all_today || []
        lastUpdated = data.last_success_at || data.generated_at || ""
    }

    function openConfiguration() {
        var action = Plasmoid.internalAction ? Plasmoid.internalAction("configure") : Plasmoid.action("configure")
        if (action) action.trigger()
    }

    compactRepresentation: PlasmaCore.ToolTipArea {
        id: toolTipArea
        width: strip.implicitWidth
        height: strip.implicitHeight
        interactive: true

        mainItem: DetailCard {
            status: root.status
            hasSchoolToday: root.hasSchoolToday
            stale: root.stale
            errorMessage: root.errorMessage
            lastUpdated: root.lastUpdated
            headerLesson: root.headerLesson
            headerIsNext: root.headerIsNext
            restOfDay: root.restOfDay
        }

        ScheduleStrip {
            id: strip
            anchors.fill: parent
            status: root.status
            hasSchoolToday: root.hasSchoolToday
            previousLesson: root.previousLesson
            currentLesson: root.currentLesson
            upcomingLessons: root.visibleUpcoming
            stale: root.stale
            onPlaceholderClicked: root.openConfiguration()
        }
    }

    fullRepresentation: DetailCard {
        Layout.preferredHeight: implicitHeight
        status: root.status
        hasSchoolToday: root.hasSchoolToday
        stale: root.stale
        errorMessage: root.errorMessage
        lastUpdated: root.lastUpdated
        headerLesson: root.headerLesson
        headerIsNext: root.headerIsNext
        restOfDay: root.restOfDay
    }
}
