import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt.labs.platform as Labs
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../Theme.js" as Theme
import "../Strings.js" as Strings

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
    property alias cfg_language: languageField.currentValue

    readonly property string language: Strings.resolveLanguage(cfg_language)

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
    readonly property string stateFilePath: runtimeDirPath + "/bakawidget/state.json"

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            page.loginInFlight = false
            var code = data["exit code"]
            var stderrText = (data.stderr || "").trim()
            var action = page.pendingAction
            page.pendingAction = ""

            // For login/logout, the command chain below always ends with
            // `cat state.json` regardless of its own success/failure (see
            // doLogin()/doLogout()), so data.stdout carries the backend's
            // freshest state — including error_code, the stable identifier
            // Strings.errorText() translates. This is what lets a failure
            // here show a fully localized reason instead of raw English
            // stderr, without re-implementing the backend's own logic.
            var errorCode = ""
            var stdout = (data.stdout || "").trim()
            if (stdout.length > 0) {
                try {
                    errorCode = JSON.parse(stdout).error_code || ""
                } catch (e) {
                    // Not JSON — e.g. state.json didn't exist yet. Fall
                    // through to the raw stderr text below.
                }
            }

            if (action === "interval") {
                // Fires on every interval change; stay quiet on success so
                // it doesn't spam the status label for a routine action.
                if (code !== 0) {
                    page.loginStatusIsError = true
                    page.loginStatusText = Strings.t(page.language, "error_prefix_interval") + (stderrText ? ": " + stderrText : ".")
                }
                return
            }

            if (code === 0) {
                page.loginStatusIsError = false
                page.loginStatusText = action === "logout" ? Strings.t(page.language, "status_loggedOut") : Strings.t(page.language, "status_signedIn")
                if (action === "login") {
                    page.password = ""
                    passwordField.text = ""
                }
            } else {
                page.loginStatusIsError = true
                var verbKey = action === "logout" ? "error_prefix_logout" : "error_prefix_login"
                var detail = Strings.errorText(page.language, errorCode, stderrText)
                page.loginStatusText = detail.length > 0
                    ? Strings.t(page.language, verbKey) + ": " + detail
                    : Strings.t(page.language, "error_couldNotRunBackend")
            }
        }
    }

    QQC2.TextField {
        id: subdomainField
        Kirigami.FormData.label: Strings.t(page.language, "label_subdomain")
        placeholderText: Strings.t(page.language, "placeholder_subdomain")
    }

    QQC2.TextField {
        id: usernameField
        Kirigami.FormData.label: Strings.t(page.language, "label_username")
    }

    QQC2.TextField {
        id: passwordField
        Kirigami.FormData.label: Strings.t(page.language, "label_password")
        echoMode: TextInput.Password
        onTextChanged: page.password = text
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: true
        text: Strings.t(page.language, "inlineMessage")
    }

    RowLayout {
        Kirigami.FormData.label: " "
        QQC2.Button {
            text: page.loginInFlight ? Strings.t(page.language, "button_signingIn") : Strings.t(page.language, "button_logIn")
            enabled: !page.loginInFlight && subdomainField.text.length > 0 && usernameField.text.length > 0 && passwordField.text.length > 0
            onClicked: page.doLogin()
        }
        QQC2.Button {
            text: Strings.t(page.language, "button_logOut")
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
        Kirigami.FormData.label: Strings.t(page.language, "section_polling")
    }

    QQC2.SpinBox {
        id: intervalField
        Kirigami.FormData.label: Strings.t(page.language, "label_interval")
        from: 1
        to: 180
        value: 15
        onValueModified: page.applyIntervalToBackend()
    }

    QQC2.SpinBox {
        id: lessonCountField
        Kirigami.FormData.label: Strings.t(page.language, "label_lessonCount")
        from: 1
        to: 6
        value: 2
    }

    // Label deliberately bilingual and fixed regardless of the current
    // language, and option text uses the language's own name rather than a
    // translation of it — a safety net so switching to a language you
    // don't read never leaves you unable to find your way back.
    QQC2.ComboBox {
        id: languageField
        Kirigami.FormData.label: Strings.t(page.language, "label_language")
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "auto", text: Strings.t(page.language, "option_auto") },
            { value: "en", text: Strings.t(page.language, "option_en") },
            { value: "cs", text: Strings.t(page.language, "option_cs") },
        ]
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
        // The whole thing is wrapped so `cat state.json` always runs last
        // regardless of success/failure, and `exit $ec` preserves the
        // actual login attempt's own exit code rather than cat's.
        var loginChain = "python3 " + shq(backendPath) + " ensure-dirs"
            + " && umask 077 && set -o noclobber"
            + " && printf '%s' " + shq(payload) + " > " + shq(reqFile)
            + " && python3 " + shq(backendPath) + " login " + shq(reqFile)
        var cmd = "(" + loginChain + ") ; ec=$? ; cat " + shq(stateFilePath) + " 2>/dev/null ; exit $ec"
        executable.connectSource(cmd)
    }

    function doLogout() {
        loginInFlight = true
        pendingAction = "logout"
        loginStatusText = ""
        subdomainField.text = ""
        usernameField.text = ""
        passwordField.text = ""
        var logoutChain = "python3 " + shq(backendPath) + " logout"
        var cmd = "(" + logoutChain + ") ; ec=$? ; cat " + shq(stateFilePath) + " 2>/dev/null ; exit $ec"
        executable.connectSource(cmd)
    }

    function applyIntervalToBackend() {
        pendingAction = "interval"
        var cmd = "python3 " + shq(backendPath) + " set-interval " + shq(String(intervalField.value))
        executable.connectSource(cmd)
    }
}
