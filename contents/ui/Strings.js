.pragma library

// All widget-visible text lives here, keyed by language. `resolveLanguage()`
// turns the "auto"/"en"/"cs" config value into an actual "en"/"cs" to look
// up, and `t()`/`errorText()` do the lookups with an English fallback so a
// missing key never renders blank.
//
// Backend-originated status/error text is translated via `errorText()`
// against a stable `error_code` the backend writes to state.json alongside
// its own (always-English) human message — see write_needs_login() /
// write_error_keep_stale() in bakawidget_backend.py. Only a handful of
// dynamic, non-enumerable details (raw HTTP reason text, KWallet's own
// error strings) fall back to that raw English message, since giving every
// possible failure string its own translation isn't practical.

var STRINGS = {
    en: {
        placeholder_needsLogin: "⚠ Log in to Bakaláři",
        placeholder_loading: "Loading…",
        placeholder_unavailable: "⚠ Bakaláři unavailable",
        placeholder_noLessonsToday: "No lessons today",
        placeholder_ellipsis: "…",

        heading_pleaseLogIn: "Please log in",
        heading_unavailable: "Bakaláři unavailable",
        heading_noLessonsToday: "No lessons today",
        heading_nothingLeftToday: "Nothing left today",
        hint_openSettings: "Open the widget settings to sign in to Bakaláři.",
        hint_couldNotReach: "Could not reach the timetable service.",
        next_prefix: "NEXT",
        room_prefix: "Room",
        cancelled: "Cancelled",
        substituted: "Substituted",
        stale_prefix: "⚠ Showing last known schedule",

        label_subdomain: "School subdomain:",
        placeholder_subdomain: "e.g. \"skola\" for skola.bakalari.cz",
        label_username: "Username:",
        label_password: "Password:",
        inlineMessage: "The password is sent once to exchange it for a Bakaláři login token, then discarded. Only the token is kept, encrypted in KWallet — the password itself is never saved anywhere, including in this widget's own settings file.",
        button_logIn: "Log in",
        button_signingIn: "Signing in…",
        button_logOut: "Log out / clear stored credentials",
        status_signedIn: "Signed in.",
        status_loggedOut: "Logged out.",
        section_polling: "Polling",
        label_interval: "Refresh every (minutes):",
        label_lessonCount: "Upcoming lessons to show:",
        label_language: "Language / Jazyk:",
        option_auto: "Auto (system)",
        option_en: "English",
        option_cs: "Čeština",
        error_couldNotRunBackend: "Could not run the backend — is python3 and python-dbus installed? See the README's Dependencies section.",
        error_prefix_login: "Login failed",
        error_prefix_logout: "Log out failed",
        error_prefix_interval: "Could not update the refresh interval",
    },
    cs: {
        placeholder_needsLogin: "⚠ Přihlaste se k Bakalářům",
        placeholder_loading: "Načítání…",
        placeholder_unavailable: "⚠ Bakaláři nedostupní",
        placeholder_noLessonsToday: "Dnes žádné hodiny",
        placeholder_ellipsis: "…",

        heading_pleaseLogIn: "Přihlaste se prosím",
        heading_unavailable: "Bakaláři nedostupní",
        heading_noLessonsToday: "Dnes žádné hodiny",
        heading_nothingLeftToday: "Dnes už nic dalšího",
        hint_openSettings: "Otevřete nastavení widgetu a přihlaste se k Bakalářům.",
        hint_couldNotReach: "Nepodařilo se spojit se službou rozvrhu.",
        next_prefix: "DALŠÍ",
        room_prefix: "Místnost",
        cancelled: "Zrušeno",
        substituted: "Suplováno",
        stale_prefix: "⚠ Zobrazen poslední známý rozvrh",

        label_subdomain: "Subdoména školy:",
        placeholder_subdomain: "např. „skola“ pro skola.bakalari.cz",
        label_username: "Uživatelské jméno:",
        label_password: "Heslo:",
        inlineMessage: "Heslo se odešle jen jednou k výměně za přihlašovací token Bakalářů a poté se zahodí. Uchovává se pouze token, zašifrovaný v KWalletu — samotné heslo se nikde neukládá, ani v nastavení tohoto widgetu.",
        button_logIn: "Přihlásit se",
        button_signingIn: "Přihlašování…",
        button_logOut: "Odhlásit se / smazat uložené údaje",
        status_signedIn: "Přihlášeno.",
        status_loggedOut: "Odhlášeno.",
        section_polling: "Aktualizace",
        label_interval: "Obnovovat každých (minut):",
        label_lessonCount: "Počet zobrazených hodin:",
        label_language: "Language / Jazyk:",
        option_auto: "Automaticky (dle systému)",
        option_en: "English",
        option_cs: "Čeština",
        error_couldNotRunBackend: "Nepodařilo se spustit backend — je nainstalovaný python3 a python-dbus? Viz sekce Dependencies v README.",
        error_prefix_login: "Přihlášení se nezdařilo",
        error_prefix_logout: "Odhlášení se nezdařilo",
        error_prefix_interval: "Nepodařilo se změnit interval obnovování",
    },
}

// Backend error_code -> localized message. Codes not listed here (or no
// code at all, e.g. an older state.json) fall back to whatever raw English
// message the backend itself wrote.
var ERROR_CODES = {
    en: {
        not_logged_in: "Not logged in yet.",
        bad_request: "Could not read the login request.",
        missing_fields: "Subdomain, username and password are all required.",
        invalid_subdomain: "That doesn't look like a valid subdomain or URL.",
        invalid_username: "That doesn't look like a valid username.",
        login_failed: "Login failed.",
        no_refresh_token: "Login response did not include a refresh token.",
        wallet_store_failed: "Login succeeded, but saving to KWallet failed.",
        wallet_unreachable: "Could not reach KWallet.",
        no_credentials: "No stored credentials found — please log in again.",
        session_expired: "Your Bakaláři session expired — please log in again.",
        poll_failed: "Could not reach Bakaláři.",
        unexpected_error: "An unexpected error occurred.",
    },
    cs: {
        not_logged_in: "Zatím nejste přihlášeni.",
        bad_request: "Nepodařilo se přečíst přihlašovací požadavek.",
        missing_fields: "Je nutné vyplnit subdoménu, uživatelské jméno i heslo.",
        invalid_subdomain: "Toto nevypadá jako platná subdoména nebo URL adresa.",
        invalid_username: "Toto nevypadá jako platné uživatelské jméno.",
        login_failed: "Přihlášení se nezdařilo.",
        no_refresh_token: "Odpověď při přihlášení neobsahovala obnovovací token.",
        wallet_store_failed: "Přihlášení proběhlo, ale uložení do KWalletu se nezdařilo.",
        wallet_unreachable: "Nepodařilo se spojit s KWalletem.",
        no_credentials: "Nebyly nalezeny žádné uložené přihlašovací údaje — přihlaste se prosím znovu.",
        session_expired: "Vaše přihlášení k Bakalářům vypršelo — přihlaste se prosím znovu.",
        poll_failed: "Nepodařilo se spojit s Bakaláři.",
        unexpected_error: "Došlo k neočekávané chybě.",
    },
}

function resolveLanguage(configValue) {
    if (configValue === "en" || configValue === "cs") return configValue
    // "auto" (or anything unrecognized): follow the system locale.
    try {
        var name = Qt.locale().name || ""
        if (name.toLowerCase().indexOf("cs") === 0) return "cs"
    } catch (e) {
        // Qt.locale() unavailable in this context — fall through to English.
    }
    return "en"
}

function t(lang, key) {
    var table = STRINGS[lang] || STRINGS.en
    if (table[key] !== undefined) return table[key]
    return STRINGS.en[key] !== undefined ? STRINGS.en[key] : key
}

function errorText(lang, code, fallback) {
    var table = ERROR_CODES[lang] || ERROR_CODES.en
    if (code && table[code] !== undefined) return table[code]
    if (code && ERROR_CODES.en[code] !== undefined) return ERROR_CODES.en[code]
    // Unrecognized/missing code: show whatever the backend itself said
    // (always English) rather than nothing.
    return fallback || ""
}
