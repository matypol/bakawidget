# Security model

## What happens to your password and token

- **Your password is never stored anywhere, ever** — not in this repo,
  not in KWallet, not in a config file, not even locally beyond the few
  milliseconds it takes the backend to exchange it for an OAuth token. It
  briefly touches disk as a 0600 temp file (created with `umask 077`
  before it exists, so there's no window where it's world-readable),
  which the backend deletes immediately after reading — before doing
  anything else, not after. Once the token exchange happens, the password
  is gone. Nobody, including you, can recover it from anything this
  project writes down, because it's never written down anywhere durable.
- **The only thing persisted is a refresh token** (an opaque OAuth
  credential — not a derivation of your password, and nothing your
  password can be recovered from), and it lives *only* in KWallet, an
  OS-level encrypted secret store on your own machine. It's never written
  to `config/main.xml` or any file under this project's directories, so
  it never ends up in git or GitHub, no matter what gets pushed or who
  compromises that account. There's nothing secret in the published
  source to steal.
- **The one honest limit**: the background poller needs to read that
  token unattended, on a timer, with nobody present — that's the entire
  point of a background schedule widget. KWallet auto-unlocks alongside
  your login session for this, the same tradeoff as a browser's saved
  passwords or an SSH agent — which means anything else that manages to
  run code as you *while your session is unlocked* could in principle ask
  KWallet for it too. That's not a flaw specific to this project; it's
  the universal limit of any local secret store that also needs to work
  unattended. The alternative (KWallet prompting on every single poll)
  trades that away for an interruption every 15 minutes, defeating the
  point of a background widget — this project keeps the standard,
  low-friction balance instead.

## Specific hardening

- **Shell command construction is quoted, not interpolated raw.** The
  one place free-typed text (subdomain/username/password) becomes part
  of a shell command is the login action. Every value goes through a
  proper POSIX single-quote escaper (`Theme.shQuote`) before being
  embedded — backticks, `$(...)`, and embedded newlines are all inert
  inside a correctly single-quoted string, and a NUL byte can't survive
  into a process argument regardless of quoting. The backend additionally
  rejects malformed-looking subdomains/usernames outright, as an
  independent second layer.
- **No core dumps.** The backend holds a live access token (and briefly a
  refresh token) in memory for as long as it runs. Both the systemd unit
  (`LimitCORE=0`) and the script itself (`RLIMIT_CORE` set to 0) disable
  core dumps, so a crash can't leave tokens sitting in
  `/var/lib/systemd/coredump`, readable via `coredumpctl` afterwards.
- **Error messages never carry raw API response bodies for the login/
  refresh endpoint** — the one place a response body could plausibly
  contain token-shaped data. Failures there report a short fixed
  classification instead ("invalid credentials", "rejected by the
  server"). The timetable-fetch endpoint (lower sensitivity — the token
  only travels in a request header, never echoed back) still includes a
  short, capped excerpt, since that's genuinely useful for diagnosing a
  broken instance.
- **The `/tmp` fallback directory is hardened against a predictable-path
  attack.** If `$XDG_RUNTIME_DIR` is ever unset (rare — logind normally
  guarantees it), the backend verifies any pre-existing directory is
  actually owned by the current user with no group/other access, rather
  than trusting it outright. File writes additionally use `O_NOFOLLOW`
  so they can't be tricked into writing through a symlink.
- **KWallet failures degrade gracefully.** Any unexpected D-Bus failure
  (kwalletd6 not running, access declined, a timeout) is caught and
  turned into a clean "please log in" state rather than a raw traceback.
- **No lesson text renders as HTML.** Lesson subject/topic fields are
  free text a teacher types into Bakaláři — QML's `Text` element
  auto-detects and renders HTML-like content by default, which could
  otherwise make the widget fire a network request (`<img src="...">`)
  just from rendering a popup. Every text element explicitly disables
  this (`textFormat: Text.PlainText`).
- **The systemd unit sandboxes what it safely can**: `NoNewPrivileges`,
  `ProtectKernelTunables/Modules/Logs`, `ProtectControlGroups`,
  `RestrictSUIDSGID`, `RestrictRealtime`, `LockPersonality`,
  `MemoryDenyWriteExecute`. Deliberately *not* `ProtectHome`/
  `ProtectSystem=strict`, which would need a precise `ReadWritePaths=`
  allowlist that's easy to get subtly wrong and silently break logins.

## Known limitations

- **KWallet identity across invocation paths** (the systemd daemon vs.
  the config page's one-shot calls) should be consistent, since both use
  the same hardcoded app identifier — but this hasn't been verified
  against a live `kwalletd6`. Worth testing once: does a systemd-
  triggered poll get wallet access without a fresh prompt on a machine
  where you've only ever run the login flow, never the daemon directly?
- **Timetable parsing follows the Bakaláři v3 API schema as documented
  by existing open-source clients**, not one verified against a live
  instance directly. Two spots are explicitly best-effort in the code:
  whether `/api/3/timetable/actual` omits no-school days entirely vs.
  returning an empty day, and the exact shape of the per-lesson `Change`
  object used to detect cancellations vs. substitutions (no single
  confirmed enum across school deployments). If something looks wrong,
  run `bakawidget_backend.py debug-dump` and open an issue with the
  output — it's opt-in and redacts known Name-shaped fields, but review
  it yourself before sharing since room codes, subjects, and internal
  IDs are kept on purpose (they're what's needed to diagnose the bug).
- **The language config field** (`ConfigGeneral.qml`'s `cfg_language`)
  aliases a `QQC2.ComboBox`'s `currentValue` directly — a pattern that
  should correctly initialize from and write back to KConfigXT on modern
  Qt6/Plasma6, but hasn't been confirmed against a live config dialog. If
  the language selector doesn't remember your choice after closing and
  reopening the config page, this is the first place to look.
