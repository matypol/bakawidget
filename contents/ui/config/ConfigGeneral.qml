import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt.labs.platform as Labs
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../Theme.js" as Theme

// Standard KConfigXT-backed config page. The `cfg_<name>` properties below
// are the well-known Plasma applet config convention: KDeclarative binds
// each one to the matching <entry name="..."> in ../../config/main.xml and
// persists it automatically on Apply/OK. `password` is deliberately NOT one
// of these — it is a plain local property that only ever gets written into
// a 0600 temp file consumed once by the backend (see doLogin() below), and
// is never part of the applet's saved configuration.
Kirigami.FormLayout {
    id: page

    property alias cfg_subdomain: subdomainField.text
    property alias cfg_username: usernameField.text
    property alias cfg_refreshIntervalMinutes: intervalField.value
    property alias cfg_lessonCount: lessonCountField.value

    property string password: ""
    property string loginStatusText: ""
    property bool loginStatusIsError: false
    property bool loginInFlight: false
    // "login" | "logout" | "interval" — which action the single shared
    // DataSource below is currently running, so its one onNewData handler
    // can report the right message instead of always assuming "login".
    property string pendingAction: ""

    readonly property string backendPath: Theme.stripFileUrl(Qt.resolvedUrl("../../backend/bakawidget_backend.py"))
    readonly property string runtimeDirPath: Theme.stripFileUrl(Labs.StandardPaths.writableLocation(Labs.StandardPaths.RuntimeLocation).toString())

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            page.loginInFlight = false
            var code = data["exit code"]
            // The backend prints the actual reason to stderr on failure
            // (see write_needs_login() in bakawidget_backend.py) — show
            // that directly instead of a generic "something went wrong".
            var reason = (data.stderr || "").trim()
            var action = page.pendingAction
            page.pendingAction = ""

            if (action === "interval") {
                // Fires on every interval change; stay quiet on success so
                // it doesn't spam the status label for a routine action.
                if (code !== 0) {
                    page.loginStatusIsError = true
                    page.loginStatusText = "Could not update the refresh interval" + (reason ? ": " + reason : ".")
                }
                return
            }

            if (code === 0) {
                page.loginStatusIsError = false
                page.loginStatusText = action === "logout" ? "Logged out." : "Signed in."
                if (action === "login") {
                    page.password = ""
                    passwordField.text = ""
                }
            } else {
                page.loginStatusIsError = true
                var verb = action === "logout" ? "Log out" : "Login"
                page.loginStatusText = reason.length > 0
                    ? verb + " failed: " + reason
                    : verb + " failed before the backend could even run — is python3 and python-dbus installed? See the README's Dependencies section."
            }
        }
    }

    QQC2.TextField {
        id: subdomainField
        Kirigami.FormData.label: "School subdomain:"
        placeholderText: "e.g. \"skola\" for skola.bakalari.cz"
    }

    QQC2.TextField {
        id: usernameField
        Kirigami.FormData.label: "Username:"
    }

    QQC2.TextField {
        id: passwordField
        Kirigami.FormData.label: "Password:"
        echoMode: TextInput.Password
        onTextChanged: page.password = text
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: true
        text: "The password is sent once to exchange it for a Bakaláři login token, then discarded. Only the token is kept, encrypted in KWallet — the password itself is never saved anywhere, including in this widget's own settings file."
    }

    RowLayout {
        Kirigami.FormData.label: " "
        QQC2.Button {
            text: page.loginInFlight ? "Signing in…" : "Log in"
            enabled: !page.loginInFlight && subdomainField.text.length > 0 && usernameField.text.length > 0 && passwordField.text.length > 0
            onClicked: page.doLogin()
        }
        QQC2.Button {
            text: "Log out / clear stored credentials"
            enabled: !page.loginInFlight
            onClicked: page.doLogout()
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.loginStatusText.length > 0
        text: page.loginStatusText
        textFormat: Text.PlainText
        color: page.loginStatusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
        wrapMode: Text.WordWrap
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: "Polling"
    }

    QQC2.SpinBox {
        id: intervalField
        Kirigami.FormData.label: "Refresh every (minutes):"
        from: 1
        to: 180
        value: 15
        onValueModified: page.applyIntervalToBackend()
    }

    QQC2.SpinBox {
        id: lessonCountField
        Kirigami.FormData.label: "Upcoming lessons to show:"
        from: 1
        to: 6
        value: 2
    }

    function shq(s) {
        return Theme.shQuote(s)
    }

    function doLogin() {
        loginInFlight = true
        pendingAction = "login"
        loginStatusText = ""
        var payload = JSON.stringify({
            subdomain: subdomainField.text.trim(),
            username: usernameField.text.trim(),
            password: passwordField.text,
            interval_minutes: intervalField.value
        })
        var dir = runtimeDirPath + "/bakawidget"
        var reqFile = dir + "/login_request.json"
        // `ensure-dirs` runs FIRST and separately: it creates the runtime
        // directory if missing, or verifies (not just trusts) that a
        // pre-existing one is actually owned by us with no group/other
        // access before this shell command writes anything into it — see
        // _ensure_secure_dir() in the backend. If that check fails, this
        // whole chain aborts before `printf` ever runs. `set -o noclobber`
        // is a second, independent layer specifically on the file-create
        // step: it refuses to write through a pre-existing file or symlink
        // at that exact path rather than following it, the same class of
        // protection atomic_write_json's O_NOFOLLOW gives the Python side.
        var cmd = "python3 " + shq(backendPath) + " ensure-dirs"
            + " && umask 077 && set -o noclobber"
            + " && printf '%s' " + shq(payload) + " > " + shq(reqFile)
            + " && python3 " + shq(backendPath) + " login " + shq(reqFile)
        executable.connectSource(cmd)
    }

    function doLogout() {
        loginInFlight = true
        pendingAction = "logout"
        loginStatusText = ""
        subdomainField.text = ""
        usernameField.text = ""
        passwordField.text = ""
        var cmd = "python3 " + shq(backendPath) + " logout"
        executable.connectSource(cmd)
    }

    function applyIntervalToBackend() {
        pendingAction = "interval"
        var cmd = "python3 " + shq(backendPath) + " set-interval " + shq(String(intervalField.value))
        executable.connectSource(cmd)
    }
}
