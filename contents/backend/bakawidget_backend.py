#!/usr/bin/env python3
"""
bakawidget_backend.py — background helper for the bakawidget
plasmoid.

Owns everything that must NOT live in QML/JS:
  * the Bakaláři v3 OAuth-style login/refresh-token exchange
  * secret storage (refresh token) in KWallet
  * polling the timetable API on an interval
  * turning the raw API response into the small JSON shape the widget renders

IPC with the plasmoid (see ../ui/main.qml for the other side):
  * Non-secret settings (subdomain, username, poll interval) live in
      $XDG_CONFIG_HOME/bakawidget/config.json
    This file is co-owned: the plasmoid's config XML is the primary source
    for subdomain/username/interval, but this script also needs them while
    running standalone as a systemd unit, so `login` and `set-interval`
    (re)write this file.
  * The parsed lesson list is published to
      $XDG_RUNTIME_DIR/bakawidget/state.json
    which the plasmoid polls every few seconds by running `cat` on it
    through Plasma5Support's "executable" data engine — the same
    primitive used for the one-shot actions below, deliberately not a
    file:// XMLHttpRequest (not a documented/blessed QML local-file API).
    This was chosen over a local socket or D-Bus because it is by far the
    least QML/C++ glue to write for a "watch a JSON blob and redraw" use
    case, at the cost of the widget only noticing new data on its own next
    poll tick rather than instantly, plus one tiny spawned process per
    tick. Both are cheap enough at a few seconds' interval to not matter.
  * One-shot actions (login, logout, force a refresh, change the interval)
    are invoked by the plasmoid via the same "executable" data engine,
    i.e. this script is run once per action and exits.
  * The password itself is passed via a 0600 temp file (see `login` below),
    never via argv or an env var, so it never shows up in `ps`. The
    directory it's written into is verified — not just assumed — safe
    first, via a dedicated `ensure-dirs` command the plasmoid runs before
    that write (see _ensure_secure_dir()); see also atomic_write_json's
    own O_NOFOLLOW for the Python-side equivalent.

KWallet integration uses the plain org.kde.KWallet D-Bus API against the
org.kde.kwalletd6 service (the Plasma 6 wallet daemon). That D-Bus API has
been stable since KDE4 and is not specific to any school's Bakaláři
instance, so unlike the timetable parsing below, it is safe to hardcode.

ASSUMPTIONS ABOUT THE BAKALÁŘI V3 API — please read
=====================================================
I don't have credentials for a live Bakaláři instance to test against, so
the timetable parsing below follows the schema documented/reverse-engineered
by existing open-source Bakaláři clients (e.g. bakalari-api, "Lepší
rozvrh"). Two things are known to vary between school deployments:

  1. Whether /api/3/timetable/actual covers "today" at all for a given day
     (some instances omit weekends/holidays from the Days array entirely
     rather than returning an empty Atoms list) — handled defensively
     below (treated as "no school today", not an error).
  2. The exact shape of the per-lesson `Change` object used to flag
     cancellations/substitutions. There is no single stable enum across
     all Bakaláři deployments for this that I could confirm without a live
     example, so `_classify_change()` below uses a best-effort heuristic
     on common field names/values and is intentionally conservative (falls
     back to "substituted" rather than silently hiding anything unusual).

If lessons, cancellations or colors don't look right, run
`bakawidget_backend.py debug-dump` (see cmd_debug_dump below) and send me
its output. It is a deliberately separate, opt-in, read-only command — the
regular poll/daemon path does NOT write the raw API response to disk by
default any more, because that response includes full teacher/subject/
group names and internal IDs, and a file sitting on disk named something
like "debug_raw.json" is exactly the kind of thing a well-meaning person
attaches to a public GitHub issue without registering that it's their
child's full timetable and named teachers. `debug-dump` prints to stdout
instead of a lingering file, and redacts every Name-shaped field it finds
before printing anything — but still review its output yourself before
pasting it anywhere public; redaction here is a best-effort filter on
known field names, not a guarantee nothing identifying survives (room
codes, subject names, and internal IDs are deliberately kept, since
they're what's actually needed to diagnose a parsing bug).
"""

import hashlib
import json
import os
import re
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

try:
    import resource
    # Belt-and-suspenders alongside the systemd unit's LimitCORE=0: this
    # process holds live tokens in memory, so a crash should never leave a
    # core dump (readable via coredumpctl) lying around. Enforced here too
    # in case this ever runs outside systemd (plasmoidviewer, manual `poll`
    # from a terminal, etc.), where the unit's own limit doesn't apply.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
except (ImportError, ValueError, OSError):
    pass  # non-POSIX platform, or already restricted tighter than this — fine either way

# Deliberately generous (schools use varied Bakaláři usernames — student
# numbers, emails, dotted names) but still rejects anything containing
# whitespace or shell/control characters, as a second, independent layer
# alongside (not instead of) correct shell-quoting on the QML side.
_VALID_SUBDOMAIN_RE = re.compile(r"^(https?://)?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(/.*)?$")
_VALID_USERNAME_RE = re.compile(r"^[^\s'\"$`\\;|&<>]+$")

APP_ID = "bakawidget"
APP_DISPLAY_NAME = "BakaWidget"
CLIENT_ID = "ANDR"  # public client id used by Bakaláři's own mobile app;
                     # not a secret, just an app identifier the API expects.
KWALLET_FOLDER = "BakaWidget"

# Deterministic per-subject color palette (the one concrete visual detail
# ported literally from the Figma reference, per the "hash into a fixed
# palette" decision — the v3 API does not expose subject colors itself).
COLOR_PALETTE = [
    "#e07030",  # orange
    "#c0143c",  # crimson
    "#6b52ae",  # purple
    "#3b82c4",  # blue
    "#2f9e6f",  # green
    "#c9992b",  # amber
    "#4a90a4",  # teal
    "#a44a90",  # magenta
    "#5a6b7a",  # slate
    "#b2542f",  # rust
]


# ── paths ─────────────────────────────────────────────────────────────────

class InsecurePathError(Exception):
    """Raised when a directory this script needs already exists but isn't
    safely ours — see _ensure_secure_dir()."""


def _ensure_secure_dir(d):
    """Create `d` (mode 0700) if missing. If it already exists, verify it's
    actually a directory, owned by us, and not group/other-writable before
    trusting it — rather than the bare `os.makedirs(..., exist_ok=True)`
    this replaces, which would silently accept a directory anyone else had
    already created there.

    This matters most for the `/tmp/bakawidget-<uid>` fallback used when
    $XDG_RUNTIME_DIR is unset (rare on a normal Plasma session, where
    logind always sets it — but not guaranteed, e.g. a stripped-down
    environment or a manual invocation). `/tmp` is world-writable, and
    `bakawidget-<uid>` is a fully predictable name, so without this check
    another local user could pre-create that directory (or a symlink
    inside it named state.json/config.json/login_request.json pointing at
    some file *we* can write) before this script ever runs, and either
    read whatever we write there or redirect our next atomic write
    somewhere else entirely. A directory under the real $XDG_RUNTIME_DIR
    doesn't have this problem — logind creates it mode 0700, owned by the
    user, before any user code runs — so this check is a no-op there.
    """
    try:
        st = os.lstat(d)
    except FileNotFoundError:
        os.makedirs(d, mode=0o700)
        return
    import stat as _stat
    if not _stat.S_ISDIR(st.st_mode):
        raise InsecurePathError(f"{d} exists and is not a directory.")
    if st.st_uid != os.getuid():
        raise InsecurePathError(f"{d} is not owned by the current user — refusing to use it.")
    if st.st_mode & 0o077:
        # Group/other has some permission bit set. Tighten it rather than
        # trust whatever was there — this is our own directory (we just
        # verified ownership above), so chmod-ing it is safe.
        os.chmod(d, 0o700)


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/bakawidget-{os.getuid()}"
    d = os.path.join(base, "bakawidget")
    _ensure_secure_dir(d)
    return d


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    d = os.path.join(base, "bakawidget")
    _ensure_secure_dir(d)
    return d


def state_path():
    return os.path.join(runtime_dir(), "state.json")


def config_path():
    return os.path.join(config_dir(), "config.json")


def atomic_write_json(path, data):
    tmp = path + ".tmp"
    # O_NOFOLLOW: refuse to write through a pre-existing symlink at `tmp`
    # rather than following it (Python's plain open(path, "w") would
    # follow it) — belt-and-suspenders alongside _ensure_secure_dir above,
    # in case anything else ever plants a symlink at a predictable path
    # inside a directory we otherwise trust. 0600 regardless of umask,
    # since even the "non-secret" files here (config.json has your
    # subdomain/username) don't need to be group/other readable.
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    fd = os.open(tmp, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def load_json(path, default=None):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _safe_int(value, default, lo, hi):
    """Parse an interval value defensively and clamp it. The intended
    caller (a bounded QQC2.SpinBox) can't produce anything malformed, but
    every one of these commands is also directly user-invocable from a
    terminal (see README's manual-reset instructions) and login/set-
    interval both round-trip through JSON files — cheap to not crash on a
    bad value instead of relying on the UI to always be the only caller."""
    try:
        n = int(value)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, n))


# ── state.json helpers ───────────────────────────────────────────────────

def write_state(**fields):
    state = load_json(state_path(), {}) or {}
    state.update(fields)
    state["generated_at"] = now_iso()
    atomic_write_json(state_path(), state)


def write_needs_login(message):
    write_state(status="needs_login", error=message, stale=False)
    # Also to stderr: when this runs as a one-shot `login` invocation from
    # the config page, Plasma's executable data engine captures stderr and
    # ConfigGeneral.qml shows it directly, so a beginner sees the real
    # reason right where they're looking instead of "something went wrong".
    print(message, file=sys.stderr)


def write_error_keep_stale(message):
    """Network/API error: keep whatever lessons we last had, just flag stale."""
    state = load_json(state_path(), {}) or {}
    state["status"] = "stale" if state.get("current") is not None or state.get("upcoming") else "error"
    state["error"] = message
    state["stale"] = True
    state["generated_at"] = now_iso()
    atomic_write_json(state_path(), state)


# ── KWallet (org.kde.KWallet over D-Bus, service org.kde.kwalletd6) ──────

class WalletError(Exception):
    pass


def _wallet_bus():
    try:
        import dbus  # python-dbus; see README for the package name on Arch
    except ImportError as e:
        raise WalletError(
            "python-dbus is not installed. Install it (pacman -S python-dbus) "
            "so credentials can be stored in KWallet."
        ) from e
    return dbus


def _wallet_iface(dbus):
    bus = dbus.SessionBus()
    proxy = bus.get_object("org.kde.kwalletd6", "/modules/kwalletd6")
    return dbus.Interface(proxy, "org.kde.KWallet")


def _wallet_open(iface, dbus):
    wallet_name = iface.networkWallet()
    handle = iface.open(wallet_name, dbus.Int64(0), APP_ID)
    if handle < 0:
        raise WalletError("Could not open KWallet (user may have declined access).")
    if not iface.hasFolder(handle, KWALLET_FOLDER, APP_ID):
        iface.createFolder(handle, KWALLET_FOLDER, APP_ID)
    return handle


def _wallet_call(func):
    """Decorator: convert ANY exception a wallet_* function raises — not
    just the ones we explicitly raise ourselves — into WalletError.

    Without this, a real D-Bus failure (kwalletd6 not running, the user
    dismissing the access-grant dialog at a call other than open(), a
    timeout, a version mismatch) surfaces as a raw dbus.exceptions.
    DBusException that none of the call sites' `except WalletError`
    clauses catch. For a one-shot action like `login`, that means an
    unhandled traceback on stderr instead of a clean write_needs_login()
    — and since ConfigGeneral.qml shows stderr directly to the user, a
    raw traceback would otherwise end up in the config page itself, and
    critically, the widget would be left stuck in whatever state it was
    already in rather than clearly reporting a login failure.
    """
    def wrapped(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except WalletError:
            raise
        except Exception as e:
            raise WalletError(f"KWallet error: {e}") from e
    return wrapped


@_wallet_call
def wallet_store(subdomain, username, refresh_token):
    dbus = _wallet_bus()
    iface = _wallet_iface(dbus)
    handle = _wallet_open(iface, dbus)
    try:
        payload = json.dumps({
            "subdomain": subdomain,
            "username": username,
            "refresh_token": refresh_token,
        })
        iface.writePassword(handle, KWALLET_FOLDER, subdomain, payload, APP_ID)
    finally:
        iface.close(handle, False, APP_ID)


@_wallet_call
def wallet_load(subdomain):
    dbus = _wallet_bus()
    iface = _wallet_iface(dbus)
    handle = _wallet_open(iface, dbus)
    try:
        if not iface.hasEntry(handle, KWALLET_FOLDER, subdomain, APP_ID):
            return None
        raw = iface.readPassword(handle, KWALLET_FOLDER, subdomain, APP_ID)
    finally:
        iface.close(handle, False, APP_ID)
    if not raw:
        return None
    try:
        return json.loads(str(raw))
    except json.JSONDecodeError:
        return None


@_wallet_call
def wallet_remove(subdomain):
    dbus = _wallet_bus()
    iface = _wallet_iface(dbus)
    handle = _wallet_open(iface, dbus)
    try:
        iface.removeEntry(handle, KWALLET_FOLDER, subdomain, APP_ID)
    finally:
        iface.close(handle, False, APP_ID)


# ── Bakaláři v3 API ───────────────────────────────────────────────────────

class ApiError(Exception):
    def __init__(self, message, invalid_grant=False):
        super().__init__(message)
        self.invalid_grant = invalid_grant


def _base_url(subdomain):
    subdomain = subdomain.strip()
    if subdomain.startswith("http://") or subdomain.startswith("https://"):
        return subdomain.rstrip("/")
    return f"https://{subdomain}.bakalari.cz"


def _post_form(url, fields, timeout=15):
    # Used only for /api/login (password AND refresh-token exchanges) — the
    # one endpoint where a response body could plausibly contain
    # token-shaped data. Its error messages therefore deliberately never
    # include raw body text: they end up in write_needs_login()/
    # write_error_keep_stale(), which both print to stderr (captured by
    # journald) and land in state.json's on-screen error banner. A short,
    # fixed classification is enough to distinguish "bad credentials" from
    # "network error" without risking anything token-shaped ever reaching
    # a log or a screen. See _get_json below for the (lower-sensitivity)
    # timetable-fetch case, where a short body excerpt is still allowed.
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        invalid_grant = e.code in (400, 401) and "invalid_grant" in body
        reason = "invalid credentials or expired session" if invalid_grant else "rejected by the server"
        raise ApiError(f"HTTP {e.code} — {reason}", invalid_grant=invalid_grant) from e
    except urllib.error.URLError as e:
        raise ApiError(f"Could not reach {url}: {e.reason}") from e


def _get_json(url, access_token, timeout=15):
    # The timetable fetch, not the token endpoint — the token itself only
    # ever travels in the (never-echoed) Authorization request header, so a
    # short body excerpt here is lower-risk than in _post_form above and
    # stays useful for diagnosing a genuinely broken/misconfigured
    # instance. Still capped short on principle.
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {access_token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise ApiError(f"HTTP {e.code} from {url}: {body[:150]}") from e
    except urllib.error.URLError as e:
        raise ApiError(f"Could not reach {url}: {e.reason}") from e


def login_password(subdomain, username, password):
    url = f"{_base_url(subdomain)}/api/login"
    return _post_form(url, {
        "client_id": CLIENT_ID,
        "grant_type": "password",
        "username": username,
        "password": password,
    })


def refresh_access_token(subdomain, refresh_token):
    url = f"{_base_url(subdomain)}/api/login"
    return _post_form(url, {
        "client_id": CLIENT_ID,
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    })


def fetch_timetable(subdomain, access_token, which="actual"):
    url = f"{_base_url(subdomain)}/api/3/timetable/{which}"
    return _get_json(url, access_token)


# ── debug dump redaction ─────────────────────────────────────────────────

# Field names that hold free-text identifying data in the v3 API's
# Teachers/Subjects/Rooms/Groups dictionaries. Kept deliberately broad
# (better to over-redact than leak) — Id/Abbrev survive, since those are
# what's actually needed to correlate an Atom to a diagnosable bug.
_REDACT_KEYS = {"name", "fullname", "displayname", "description",
                "changedescription"}


def _redact_for_debug(value):
    """Recursively blank out identifying free-text fields in a raw API
    response before it's ever printed. Best-effort: a filter on known key
    names, not a guarantee — see the module docstring."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            if k.lower() in _REDACT_KEYS and isinstance(v, str) and v:
                out[k] = "[REDACTED]"
            else:
                out[k] = _redact_for_debug(v)
        return out
    if isinstance(value, list):
        return [_redact_for_debug(v) for v in value]
    return value


# ── timetable parsing ────────────────────────────────────────────────────

def _index_by_id(items):
    return {str(i.get("Id")): i for i in (items or [])}


def _subject_color(key):
    digest = hashlib.md5(key.encode("utf-8")).hexdigest()
    idx = int(digest[:8], 16) % len(COLOR_PALETTE)
    return COLOR_PALETTE[idx]


def _classify_change(change):
    """Best-effort classification of an Atom's `Change` object.

    See the module docstring: this enum is not confirmed against a live
    instance. Defaults to "substituted" for anything it doesn't recognize
    as a cancellation, so changes are never silently hidden.
    """
    if not change:
        return False, False, None
    type_field = str(change.get("TypeAbbrev") or change.get("ChangeType") or change.get("Type") or "").lower()
    description = change.get("Description") or change.get("ChangeDescription") or ""
    haystack = f"{type_field} {description}".lower()
    cancel_markers = ("can", "removed", "odpad", "zrus", "cancel")
    cancelled = any(marker in haystack for marker in cancel_markers)
    substituted = not cancelled
    return cancelled, substituted, (description or None)


def parse_lessons_for_day(payload, target_date):
    """Return a list of lesson dicts for `target_date` (date object), or
    None if the API's Days array has no entry at all for that date (taken
    to mean "no school that day" rather than an error)."""
    hours_by_id = _index_by_id(payload.get("Hours"))
    subjects_by_id = _index_by_id(payload.get("Subjects"))
    teachers_by_id = _index_by_id(payload.get("Teachers"))
    rooms_by_id = _index_by_id(payload.get("Rooms"))
    groups_by_id = _index_by_id(payload.get("Groups"))

    day = None
    for d in payload.get("Days") or []:
        raw_date = (d.get("Date") or "")[:10]
        if raw_date == target_date.isoformat():
            day = d
            break
    if day is None:
        return None

    lessons = []
    for atom in day.get("Atoms") or []:
        hour = hours_by_id.get(str(atom.get("HourId")), {})
        subject = subjects_by_id.get(str(atom.get("SubjectId")), {})
        teacher = teachers_by_id.get(str(atom.get("TeacherId")), {})
        room = rooms_by_id.get(str(atom.get("RoomId")), {})
        group_ids = atom.get("GroupIds") or ([atom["GroupId"]] if atom.get("GroupId") else [])
        group_names = [groups_by_id.get(str(g), {}).get("Abbrev", "") for g in group_ids]
        group_names = [g for g in group_names if g]

        cancelled, substituted, change_note = _classify_change(atom.get("Change"))
        code = subject.get("Abbrev") or subject.get("Name") or "?"
        color_key = str(atom.get("SubjectId") or code)

        begin = hour.get("BeginTime") or "00:00"
        end = hour.get("EndTime") or begin

        lessons.append({
            "code": code,
            "subject": subject.get("Name") or code,
            "teacher": teacher.get("Abbrev") or "",
            "group": ", ".join(group_names),
            "room": room.get("Abbrev") or "",
            "topic": atom.get("Theme") or "",
            "start": begin[:5],
            "end": end[:5],
            "color": _subject_color(color_key),
            "cancelled": cancelled,
            "substituted": substituted if not cancelled else False,
            "change_note": change_note,
            "_hour_order": hour.get("Caption") or begin,
        })

    lessons.sort(key=lambda l: l["start"])
    return lessons


def split_by_wallclock(lessons, now):
    """Return (previous, current, upcoming[]) given lessons for today."""
    current_time = now.strftime("%H:%M")
    previous = None
    current = None
    upcoming = []
    active_ones = [l for l in lessons if not l["cancelled"]]
    for i, lesson in enumerate(active_ones):
        if lesson["start"] <= current_time < lesson["end"]:
            current = lesson
        elif lesson["end"] <= current_time:
            previous = lesson
        elif lesson["start"] > current_time:
            upcoming.append(lesson)
    return previous, current, upcoming


# ── commands ─────────────────────────────────────────────────────────────

def cmd_ensure_dirs():
    """Create/verify the runtime and config directories via the same
    _ensure_secure_dir() check every other command already goes through —
    invoked as a separate first step by ConfigGeneral.qml's login shell
    command, so the directory is verified safe *before* that shell command
    writes login_request.json into it via `printf > file`, which (unlike
    atomic_write_json above) has no O_NOFOLLOW-equivalent protection of
    its own. Also clears a stale login_request.json left over from an
    earlier interrupted run — safe to do here specifically because by this
    point the containing directory has already been verified as genuinely
    ours."""
    d = runtime_dir()
    config_dir()
    stale = os.path.join(d, "login_request.json")
    try:
        os.remove(stale)
    except OSError:
        pass
    return 0


def cmd_login(cred_file):
    creds = load_json(cred_file)
    try:
        os.remove(cred_file)
    except OSError:
        pass
    if not creds:
        write_needs_login("Could not read the login request.")
        return 1

    subdomain = creds.get("subdomain", "").strip()
    username = creds.get("username", "").strip()
    password = creds.get("password", "")
    interval_minutes = _safe_int(creds.get("interval_minutes"), 15, 1, 1440)

    if not subdomain or not username or not password:
        write_needs_login("Subdomain, username and password are all required.")
        return 1

    # Defense-in-depth, independent of the QML side's shell-quoting: reject
    # anything that isn't a plausible subdomain/URL or username shape
    # before it goes anywhere near a network call. This doesn't paper over
    # a quoting bug (there isn't one in the current QML->shell path — see
    # Theme.shQuote — since this backend never itself re-invokes a shell
    # with these values), it's a second, independent layer catching
    # malformed input for its own sake.
    if not _VALID_SUBDOMAIN_RE.match(subdomain):
        write_needs_login("That doesn't look like a valid subdomain or URL (e.g. \"skola\" or \"https://skola.bakalari.cz\").")
        return 1
    if not _VALID_USERNAME_RE.match(username):
        write_needs_login("That doesn't look like a valid username.")
        return 1

    try:
        token_resp = login_password(subdomain, username, password)
    except ApiError as e:
        write_needs_login(f"Login failed: {e}")
        return 1
    finally:
        password = None  # noqa: F841 - drop reference ASAP

    refresh_token = token_resp.get("refresh_token")
    if not refresh_token:
        write_needs_login("Login response did not include a refresh token.")
        return 1

    try:
        wallet_store(subdomain, username, refresh_token)
    except WalletError as e:
        write_needs_login(f"Login succeeded but KWallet storage failed: {e}")
        return 1

    atomic_write_json(config_path(), {
        "subdomain": subdomain,
        "username": username,
        "interval_minutes": interval_minutes,
    })

    return cmd_poll()


def cmd_logout():
    cfg = load_json(config_path())
    if cfg and cfg.get("subdomain"):
        try:
            wallet_remove(cfg["subdomain"])
        except WalletError:
            pass
    for p in (config_path(), state_path()):
        try:
            os.remove(p)
        except OSError:
            pass
    write_state(status="needs_login", error=None, stale=False,
                previous=None, current=None, upcoming=[], all_today=[],
                has_school_today=None)
    return 0


def cmd_set_interval(minutes):
    cfg = load_json(config_path(), {}) or {}
    cfg["interval_minutes"] = _safe_int(minutes, 15, 1, 1440)
    atomic_write_json(config_path(), cfg)
    return 0


def cmd_poll():
    cfg = load_json(config_path())
    if not cfg or not cfg.get("subdomain") or not cfg.get("username"):
        write_needs_login("Not logged in yet.")
        return 1

    subdomain = cfg["subdomain"]
    wallet = None
    try:
        wallet = wallet_load(subdomain)
    except WalletError as e:
        write_error_keep_stale(f"Could not reach KWallet: {e}")
        return 1

    if not wallet or not wallet.get("refresh_token"):
        write_needs_login("No stored credentials found — please log in again.")
        return 1

    try:
        token_resp = refresh_access_token(subdomain, wallet["refresh_token"])
    except ApiError as e:
        if e.invalid_grant:
            try:
                wallet_remove(subdomain)
            except WalletError:
                pass
            write_needs_login("Your Bakaláři session expired — please log in again.")
            return 1
        write_error_keep_stale(str(e))
        return 1

    access_token = token_resp.get("access_token")
    new_refresh = token_resp.get("refresh_token")
    if new_refresh and new_refresh != wallet["refresh_token"]:
        try:
            wallet_store(subdomain, wallet.get("username", cfg.get("username", "")), new_refresh)
        except WalletError:
            pass  # non-fatal; we can still serve this poll with the current access token

    today = datetime.now().date()
    raw = None
    lessons = None
    try:
        raw = fetch_timetable(subdomain, access_token, "actual")
        lessons = parse_lessons_for_day(raw, today)
        if lessons is None:
            # Not present in "actual" (e.g. far from the current rotation) —
            # fall back to the permanent schedule before deciding it's a
            # non-school day.
            raw = fetch_timetable(subdomain, access_token, "permanent")
            lessons = parse_lessons_for_day(raw, today)
    except ApiError as e:
        write_error_keep_stale(str(e))
        return 1

    has_school_today = lessons is not None
    lessons = lessons or []
    previous, current, upcoming = split_by_wallclock(lessons, datetime.now())

    write_state(
        status="ok",
        error=None,
        stale=False,
        last_success_at=now_iso(),
        date=today.isoformat(),
        has_school_today=has_school_today,
        previous=previous,
        current=current,
        upcoming=upcoming,
        all_today=lessons,
    )
    return 0


def cmd_debug_dump():
    """Opt-in, read-only diagnostic: fetch the raw timetable, redact
    known identifying fields, print to stdout. Never touches state.json or
    any file on disk — nothing lingers after this process exits besides
    whatever the caller chooses to do with stdout."""
    cfg = load_json(config_path())
    if not cfg or not cfg.get("subdomain"):
        print("Not logged in — nothing to dump.", file=sys.stderr)
        return 1

    subdomain = cfg["subdomain"]
    try:
        wallet = wallet_load(subdomain)
        if not wallet or not wallet.get("refresh_token"):
            print("No stored credentials found.", file=sys.stderr)
            return 1
        token_resp = refresh_access_token(subdomain, wallet["refresh_token"])
        access_token = token_resp.get("access_token")
        raw = fetch_timetable(subdomain, access_token, "actual")
    except (WalletError, ApiError) as e:
        print(f"Could not fetch a fresh dump: {e}", file=sys.stderr)
        return 1

    print(
        "This dump has known Name-shaped fields redacted, but review it "
        "yourself before sharing — room codes, subject names, and internal "
        "IDs are deliberately kept since they're what's needed to diagnose "
        "a parsing bug, and a school's own customizations may put "
        "identifying text somewhere this filter doesn't know to look.",
        file=sys.stderr,
    )
    print(json.dumps(_redact_for_debug(raw), ensure_ascii=False, indent=2))
    return 0


def cmd_daemon():
    stop = {"flag": False}

    def _handle_sigterm(signum, frame):
        stop["flag"] = True

    signal.signal(signal.SIGTERM, _handle_sigterm)
    signal.signal(signal.SIGINT, _handle_sigterm)

    while not stop["flag"]:
        try:
            cmd_poll()
        except Exception as e:  # keep the daemon alive no matter what
            write_error_keep_stale(f"Unexpected backend error: {e}")
        cfg = load_json(config_path(), {}) or {}
        interval = _safe_int(cfg.get("interval_minutes"), 15, 1, 1440)
        for _ in range(interval * 60):
            if stop["flag"]:
                break
            time.sleep(1)
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, rest = argv[1], argv[2:]
    try:
        if cmd == "login" and rest:
            return cmd_login(rest[0])
        if cmd == "logout":
            return cmd_logout()
        if cmd == "poll":
            return cmd_poll()
        if cmd == "daemon":
            return cmd_daemon()
        if cmd == "set-interval" and rest:
            return cmd_set_interval(rest[0])
        if cmd == "debug-dump":
            return cmd_debug_dump()
        if cmd == "ensure-dirs":
            return cmd_ensure_dirs()
    except Exception as e:
        # Last-resort safety net. Anything escaping to here (a malformed
        # API response that isn't valid JSON despite a 200 status, an
        # InsecurePathError from _ensure_secure_dir, a wallet failure that
        # somehow wasn't wrapped as WalletError, ...) would otherwise be an
        # unhandled traceback on stderr — which for a one-shot action
        # invoked from the config page flows straight into the on-screen
        # status text. write_error_keep_stale() is used rather than
        # write_needs_login() because we might already hold a validly
        # stored token by the time something unrelated breaks (e.g. inside
        # cmd_login's trailing cmd_poll() call) — this reports the failure
        # without incorrectly implying you need to log in again.
        try:
            write_error_keep_stale(f"Unexpected error: {e}")
        except Exception:
            pass  # e.g. the original failure WAS the state dir being unsafe — don't mask it with a second crash
        print(f"Unexpected error running '{cmd}': {e}", file=sys.stderr)
        return 1
    print(f"Unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
