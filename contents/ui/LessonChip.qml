import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import "Theme.js" as Theme

// One taskbar-strip chip: previous / current / upcoming lesson.
// 1:1 port of the ScheduleWidget chip markup in reference/src/App.tsx
// (previousClass block, "Current class" block, "Upcoming chips" block).
Item {
    id: chip

    // "previous" | "current" | "upcoming"
    property string variant: "upcoming"
    property var lesson: null

    readonly property bool isCancelled: !!(lesson && lesson.cancelled)
    readonly property bool isSubstituted: !!(lesson && lesson.substituted && !isCancelled)
    readonly property color subjectColor: (lesson && lesson.color) ? lesson.color : Kirigami.Theme.neutralTextColor

    readonly property real chipHeight: variant === "current" ? 36 : (variant === "previous" ? 30 : 32)
    readonly property real hPad: variant === "current" ? 10 : 8

    width: Math.max(codeLabel.implicitWidth, roomLabel.implicitWidth) + hPad * 2
    height: chipHeight

    // Glow behind the current chip — the closest native stand-in for the
    // reference's `box-shadow: 0 0 10px ${color}55`, which has no direct
    // QML equivalent. Qt5Compat.GraphicalEffects' RectangularGlow is the
    // built-in Qt6 primitive for exactly this "soft glow around a rounded
    // rect" look.
    RectangularGlow {
        anchors.fill: bg
        visible: variant === "current" && !isCancelled
        glowRadius: 8
        spread: 0.15
        color: Theme.tint(subjectColor, 0.33)
        cornerRadius: bg.radius + glowRadius
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 4
        color: {
            if (isCancelled) return Theme.tint(Kirigami.Theme.negativeTextColor, 0.16)
            if (variant === "current") return subjectColor
            if (variant === "previous") return Theme.tint(Kirigami.Theme.textColor, 0.04)
            return Theme.tint(Kirigami.Theme.textColor, 0.07)
        }
        opacity: variant === "previous" ? 0.38 : 1.0

        border.width: isSubstituted ? 2 : (variant === "current" ? 0 : 1)
        border.color: {
            if (isCancelled) return Theme.tint(Kirigami.Theme.negativeTextColor, 0.5)
            if (isSubstituted) return Kirigami.Theme.neutralTextColor
            if (variant === "previous") return Theme.tint(Kirigami.Theme.textColor, 0.07)
            if (variant === "current") return "transparent"
            return Theme.tint(Kirigami.Theme.textColor, 0.11)
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 1

        Text {
            textFormat: Text.PlainText
            id: codeLabel
            Layout.alignment: Qt.AlignHCenter
            text: lesson ? lesson.code : ""
            font.pixelSize: variant === "current" ? 12.5 : (variant === "previous" ? 10.5 : 11)
            font.weight: variant === "current" ? Font.Bold : (variant === "upcoming" ? Font.DemiBold : Font.Medium)
            font.letterSpacing: variant === "current" ? 0.4 : 0
            font.strikeout: isCancelled
            color: variant === "current" ? "#ffffff" : (variant === "previous" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor)
            opacity: variant === "upcoming" ? 0.85 : 1.0
        }

        Text {
            textFormat: Text.PlainText
            id: roomLabel
            Layout.alignment: Qt.AlignHCenter
            text: lesson ? lesson.room : ""
            font.pixelSize: variant === "current" ? 9 : (variant === "previous" ? 8 : 8.5)
            font.family: "monospace"
            color: variant === "current" ? Qt.rgba(1, 1, 1, 0.8) : Kirigami.Theme.disabledTextColor
        }
    }
}
