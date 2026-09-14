import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Theme.js" as Theme

// The compactRepresentation content: the horizontal chip strip from
// reference/src/App.tsx's ScheduleWidget. Cases the reference mockup does
// not model at all (needs_login / no lessons today / never loaded yet) get
// a single placeholder chip instead of an empty strip.
RowLayout {
    id: strip
    spacing: 3

    property string status: "loading"
    property bool hasSchoolToday: true
    property var previousLesson: null
    property var currentLesson: null
    property var upcomingLessons: []
    property bool stale: false

    signal placeholderClicked()

    // "stale" (a network/API error after we'd already fetched something)
    // must still render the retained previous/current/upcoming chips, per
    // spec: "show last-known-good schedule with a small stale indicator
    // rather than going blank". The placeholder only takes over when there
    // is genuinely nothing to show yet (never logged in, first poll still
    // pending, or the very first poll ever failed before we had anything).
    readonly property bool hasAnyLessonData: previousLesson !== null || currentLesson !== null || upcomingLessons.length > 0
    readonly property bool showPlaceholder: {
        if (status === "needs_login") return true
        if (status === "ok") return !hasSchoolToday
        return !hasAnyLessonData
    }

    Rectangle {
        visible: strip.showPlaceholder
        Layout.preferredHeight: 30
        Layout.preferredWidth: placeholderLabel.implicitWidth + 16
        radius: 4
        color: Theme.tint(Kirigami.Theme.textColor, 0.06)
        border.width: 1
        border.color: strip.status === "needs_login"
            ? Kirigami.Theme.neutralTextColor
            : Theme.tint(Kirigami.Theme.textColor, 0.1)

        Text {
            textFormat: Text.PlainText
            id: placeholderLabel
            anchors.centerIn: parent
            font.pixelSize: 11
            color: strip.status === "needs_login" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.disabledTextColor
            text: {
                switch (strip.status) {
                case "needs_login": return "⚠ Log in to Bakaláři"
                case "loading": return "Loading…"
                case "error": return "⚠ Bakaláři unavailable"
                case "stale": return "⚠ Bakaláři unavailable"
                default: return strip.hasSchoolToday ? "…" : "No lessons today"
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: strip.status === "needs_login" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (strip.status === "needs_login") strip.placeholderClicked()
        }
    }

    LessonChip {
        visible: !strip.showPlaceholder && strip.previousLesson !== null
        variant: "previous"
        lesson: strip.previousLesson
    }

    LessonChip {
        visible: !strip.showPlaceholder && strip.currentLesson !== null
        variant: "current"
        lesson: strip.currentLesson
    }

    Repeater {
        model: strip.showPlaceholder ? [] : strip.upcomingLessons
        delegate: LessonChip {
            variant: "upcoming"
            lesson: modelData
        }
    }

    // Small stale indicator — the reference never covers a network-error
    // state, so this is new: a subtle dot rather than reflowing the strip.
    Rectangle {
        visible: strip.stale && !strip.showPlaceholder
        Layout.preferredWidth: 6
        Layout.preferredHeight: 6
        radius: 3
        color: Kirigami.Theme.neutralTextColor
        Layout.alignment: Qt.AlignVCenter
    }
}
