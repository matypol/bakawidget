import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Theme.js" as Theme
import "Strings.js" as Strings

// The hover-popup content, ported from the `{hovered && (...)}` block in
// reference/src/App.tsx's ScheduleWidget. Used both as the mainItem of the
// compact representation's PlasmaCore.ToolTipArea and as the applet's
// fullRepresentation (see main.qml) so clicking the applet shows the same
// card natively docked instead of a floating window.
//
// The reference's `.plasma-glass` panel (background + 1px border, with
// `backdrop-filter: blur(20px) saturate(1.4)` behind it) has no faithful
// QML equivalent inside an arbitrary Item: hand-rolling a blur here would
// mean grabbing whatever happens to be behind this Item and running it
// through a shader, which for a tooltip window is either unavailable or
// wildly more expensive than what it is imitating. Both host contexts this
// component is placed in (PlasmaCore.ToolTipArea's popup, and a
// PlasmoidItem's fullRepresentation dialog) already come with Plasma's own
// themed, KWin-blurred panel background for free, so this component
// deliberately paints no outer background/border of its own — the
// substitution is "use the native popup chrome" rather than "reimplement
// glass in QML".
ColumnLayout {
    id: card
    spacing: 0
    // Both set explicitly: Layout.preferredWidth for when this is placed
    // inside a Layout (fullRepresentation), implicitWidth for when it's
    // handed directly to PlasmaCore.ToolTipArea.mainItem, which is not
    // inside a Layout and sizes the popup from the item's own implicit size.
    implicitWidth: 256
    Layout.preferredWidth: 256

    property string language: "en"
    property string status: "loading"
    property bool hasSchoolToday: true
    property bool stale: false
    property string errorMessage: ""
    property string errorCode: ""
    property string lastUpdated: ""
    // The lesson shown in the colored header: the current lesson, or the
    // next upcoming one if nothing is in session right now (a case the
    // reference doesn't model — it always hardcodes schedule[0] as current).
    property var headerLesson: null
    property bool headerIsNext: false
    // Everything else today, in order, excluding headerLesson.
    property var restOfDay: []

    readonly property bool empty: status === "ok" && hasSchoolToday && headerLesson === null && restOfDay.length === 0

    // ── Needs login / error placeholder ────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: card.status === "needs_login" || card.status === "error" || (card.status === "ok" && !card.hasSchoolToday) || card.empty
        Layout.margins: 16
        spacing: 6

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Kirigami.Theme.textColor
            text: {
                if (card.status === "needs_login") return Strings.t(card.language, "heading_pleaseLogIn")
                if (card.status === "error") return Strings.t(card.language, "heading_unavailable")
                if (card.status === "ok" && !card.hasSchoolToday) return Strings.t(card.language, "heading_noLessonsToday")
                return Strings.t(card.language, "heading_nothingLeftToday")
            }
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text.length > 0
            font.pixelSize: 10.5
            color: Kirigami.Theme.disabledTextColor
            text: {
                if (card.status === "needs_login") return Strings.errorText(card.language, card.errorCode, card.errorMessage) || Strings.t(card.language, "hint_openSettings")
                if (card.status === "error") return Strings.errorText(card.language, card.errorCode, card.errorMessage) || Strings.t(card.language, "hint_couldNotReach")
                return ""
            }
        }
    }

    // ── Header (current or next lesson) ────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: card.headerLesson !== null
        color: card.headerLesson ? card.headerLesson.color : "transparent"
        implicitHeight: headerContent.implicitHeight + 23
        Layout.topMargin: 0

        ColumnLayout {
            id: headerContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 0
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            spacing: 0

            Text {
            textFormat: Text.PlainText
                Layout.fillWidth: true
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: Qt.rgba(1, 1, 1, 0.7)
                text: (card.headerIsNext ? Strings.t(card.language, "next_prefix") + " · " : "") + (card.headerLesson ? card.headerLesson.code.toUpperCase() : "")
            }
            Text {
            textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: 3
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#ffffff"
                font.strikeout: card.headerLesson ? !!card.headerLesson.cancelled : false
                text: card.headerLesson ? card.headerLesson.subject : ""
                wrapMode: Text.WordWrap
            }
            Text {
            textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: card.headerLesson && card.headerLesson.topic
                font.pixelSize: 10.5
                font.italic: true
                color: Qt.rgba(1, 1, 1, 0.72)
                text: card.headerLesson ? card.headerLesson.topic : ""
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 11
                Text {
            textFormat: Text.PlainText
                    Layout.fillWidth: true
                    font.pixelSize: 10.5
                    color: Qt.rgba(1, 1, 1, 0.8)
                    elide: Text.ElideRight
                    text: card.headerLesson
                        ? [card.headerLesson.teacher, card.headerLesson.group].filter(s => s).join(" ")
                          + (card.headerLesson.room ? " · " + Strings.t(card.language, "room_prefix") + " " + card.headerLesson.room : "")
                        : ""
                }
                Text {
            textFormat: Text.PlainText
                    font.pixelSize: 10
                    font.family: "monospace"
                    color: Qt.rgba(1, 1, 1, 0.65)
                    text: card.headerLesson ? card.headerLesson.start + "–" + card.headerLesson.end : ""
                }
            }
        }
    }

    // ── Rest of today ───────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: card.restOfDay.length > 0
        spacing: 0
        Layout.topMargin: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: rows.implicitHeight + 10
            color: Theme.tint(Kirigami.Theme.backgroundColor, 0.6)

            ColumnLayout {
                id: rows
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 0

                Repeater {
                    model: card.restOfDay
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 3
                            Layout.preferredHeight: 30
                            radius: 2
                            color: modelData.cancelled ? Kirigami.Theme.negativeTextColor : modelData.color
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Text {
            textFormat: Text.PlainText
                                    font.pixelSize: 11.5
                                    font.weight: Font.DemiBold
                                    font.strikeout: !!modelData.cancelled
                                    color: Kirigami.Theme.textColor
                                    text: modelData.code
                                }
                                Text {
            textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: 11.5
                                    color: Kirigami.Theme.disabledTextColor
                                    text: modelData.subject
                                }
                                Text {
            textFormat: Text.PlainText
                                    visible: !!modelData.cancelled
                                    font.pixelSize: 9.5
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.negativeTextColor
                                    text: Strings.t(card.language, "cancelled")
                                }
                                Text {
            textFormat: Text.PlainText
                                    visible: !modelData.cancelled && !!modelData.substituted
                                    font.pixelSize: 9.5
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.neutralTextColor
                                    text: Strings.t(card.language, "substituted")
                                }
                            }
                            Text {
            textFormat: Text.PlainText
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: 9.5
                                color: Kirigami.Theme.disabledTextColor
                                text: modelData.start + " · " + Strings.t(card.language, "room_prefix") + " " + modelData.room + " · "
                                    + [modelData.teacher, modelData.group].filter(s => s).join(" ")
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        Layout.margins: 8
        visible: card.stale
        font.pixelSize: 9
        color: Kirigami.Theme.neutralTextColor
        text: Strings.t(card.language, "stale_prefix")
            + (card.lastUpdated ? " (" + card.lastUpdated + ")" : "")
            + (card.errorMessage ? " — " + Strings.errorText(card.language, card.errorCode, card.errorMessage) : "")
        wrapMode: Text.WordWrap
    }
}
