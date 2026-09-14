.pragma library

// Small helpers shared by the QML components.
//
// THEMING SPLIT: general chrome (panel/chip backgrounds, borders, dimmed
// text) must come from the live Plasma theme so it adapts to whatever
// color scheme the user runs, unlike the reference mockup which hardcodes
// Breeze Dark hex values. `tint()` turns a theme color into a translucent
// overlay, which is the QML equivalent of the reference's
// rgba(255,255,255, alpha) neutral overlays — except tinted with the
// user's actual theme text/background color instead of a hardcoded white.

function tint(themeColor, alpha) {
    return Qt.rgba(themeColor.r, themeColor.g, themeColor.b, alpha)
}

function shQuote(s) {
    // Safe single-quoting for embedding an arbitrary string as one
    // argument in a POSIX shell command line.
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

function stripFileUrl(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? s.substring(7) : s
}
