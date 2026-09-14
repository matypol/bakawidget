# bakawidget

A KDE Plasma 6 taskbar widget that shows your upcoming Bakaláři school
lessons, ported 1:1 from a Figma-driven React mockup (see `../reference/`
in this repo, kept read-only) into native QML + a small Python backend.

**Scope note:** this is Plasma-only, deliberately. A plasmoid is QML that
loads directly into `plasmashell` using Plasma-specific APIs with no
equivalent in GNOME Shell, XFCE's panel, or Cinnamon, so there's no way
for one codebase to "autodetect" and natively embed into all of their
different panel plugin systems. A genuinely cross-desktop version would
mean a second, separate app (e.g. a system tray icon sharing the same
Python backend) — not built here, since Plasma-only covers the actual
target environment.

## How it's put together

- **`contents/ui/*.qml`** — the plasmoid itself (`PlasmoidItem`,
  `PlasmaComponents3`/Kirigami). Pure presentation; it never talks HTTP and
  never sees your password.
- **`contents/backend/bakawidget_backend.py`** — owns the Bakaláři v3 OAuth
  login/refresh flow, stores the refresh token in KWallet, and polls the
  timetable on an interval.
- **IPC between them** (see the long comment at the top of
  `bakawidget_backend.py` for the full reasoning): the backend writes the
  parsed lesson list to `$XDG_RUNTIME_DIR/bakawidget/state.json`, which the
  QML side polls every few seconds by running `cat` on it through Plasma's
  `executable` data engine — the same primitive used for the one-shot
  actions (log in, log out, change the poll interval). Earlier versions
  used a `file://` `XMLHttpRequest` for reads instead; that was replaced
  because it isn't a documented/blessed QML API for local file access, so
  everything now goes through the one IPC primitive this project actually
  knows is stable. This was the simplest of the three IPC options (socket /
  JSON file / D-Bus) to wire into a plasmoid without a compiled C++ helper.
- The backend runs continuously as a **systemd --user service**, so it
  keeps polling and surviving crashes/reboots independently of whether the
  widget is currently visible.

## Dependencies

- KDE Plasma 6 / Qt 6, `kpackagetool6`
- Python 3 (standard library only for the HTTP/JSON parts — no `requests`)
- `python-dbus` (Arch: `pacman -S python-dbus`) — used to talk to
  `org.kde.kwalletd6` over D-Bus for credential storage
- KWallet running (default on Plasma 6); the "Bakaláři" wallet folder will
  be created automatically on first login and you'll get the normal
  KWallet access prompt the first time

## Install

Pick whichever fits how you got this directory. All three end up in the
same place (`~/.local/share/plasma/plasmoids/` for the script, or a real
pacman entry for the package) and all three still need the one-time
first-login step further down — that part can't be packaged away, since
it needs your password interactively.

A plain Flatpak isn't an option here: Flatpak sandboxes standalone apps,
and a plasmoid isn't one — it's a plugin that loads directly into
`plasmashell` and the Plasma config/theme system, which has no sandboxed
app model to fit into.

### Option A — one script (fastest)

```bash
cd bakawidget
./install.sh
```

Installs the plasmoid via `kpackagetool6` and sets up the systemd --user
service in one go. `./uninstall.sh` reverses it completely (backend
service, KWallet entry, and the plasmoid itself).

### Option B — a real pacman package

```bash
cd bakawidget
makepkg -si
```

This is a genuine local package (`plasma6-applets-bakawidget`),
built and installed with `makepkg -si` (needs the `base-devel` group).
Once installed it shows up in `pacman -Qi plasma6-applets-bakawidget`
and comes off cleanly with `pacman -R`. If you want to share this with
other people, the resulting `.pkg.tar.zst` in this directory can be
pushed to the AUR as-is.

A pacman/AUR install (unlike `install.sh`) **cannot enable the systemd
service for you** — package install hooks run as root during the
transaction and have no access to any user's own systemd session, which
is a hard OS boundary, not something a smarter PKGBUILD could work
around. The `.install` hook prints a reminder about this. To keep this
from actually blocking a beginner, though: **the plasmoid itself checks
for its own background service on load and silently enables+starts it if
missing** (see the `serviceSelfHeal` block in `contents/ui/main.qml`), so
in practice just adding the widget to a panel after a pacman/AUR install
is enough — you shouldn't need to touch a terminal for this at all. The
manual `systemctl --user enable --now bakawidget-backend.service` is only
a fallback if that self-heal itself doesn't fire (e.g. `systemctl` not on
`$PATH` in whatever shell Plasma spawns it in — rare, but possible).

### Option C — a single file to hand someone

Both of the above assume you have this whole directory. If you just want
one file to copy/send:

```bash
cd bakawidget
tar czf ../bakawidget.tar.gz --exclude=pkg --exclude=src --exclude='*.pkg.tar.*' .
```

The recipient un-tars it and runs `./install.sh` inside, or builds the
package with Option B. There's also KDE's own native single-file format —
zip the same contents with a `.plasmoid` extension and it's installable
with `kpackagetool6 -i thatfile.plasmoid`, or (if you ever publish it to
store.kde.org) discoverable and installable with zero terminal at all
through Plasma's own "Add Widgets → Get New Widgets" dialog. I haven't
set up that publishing step since it requires a KDE Store account and
public listing — say the word if you want it.

### Whichever you pick, check it works before trusting it

I haven't been able to runtime-test the QML against real `plasmashell` (no
Linux/KDE environment on my end) — run it with `plasmoidviewer` first
(see "Dev / testing" below) so if something doesn't compile you see it
immediately, before wiring it into a real panel.

You can check on the backend service any time with:

```bash
systemctl --user status bakawidget-backend.service
journalctl --user -u bakawidget-backend.service -f
```

## First-time login

1. Right-click the widget → **Configure BakaWidget…**
2. Fill in your school's subdomain (the `skola` part of
   `skola.bakalari.cz`), your Bakaláři username, and your password.
3. Click **Log in**. This writes a short-lived, permissions-0600 request
   file under `$XDG_RUNTIME_DIR`, hands it to the backend, and the backend
   deletes it immediately after reading it. The backend exchanges your
   password for an OAuth token pair right away — your password itself is
   never written to the widget's own settings file (`config/main.xml`
   only ever stores the subdomain/username/interval/lesson-count, all
   non-secret) and never touches QML/JS beyond that one temp file.
4. The backend stores the refresh token in KWallet and immediately runs
   one poll, so the widget should populate within a couple of seconds.
   After that, the systemd service keeps it fresh on your configured
   interval (default 15 minutes).

Changing just the refresh interval afterwards doesn't require logging in
again — the config page pushes interval changes to the backend directly.
Changing the subdomain or username does require pressing **Log in** again
with your password, since those are tied to the stored token.

## Security model

What actually happens to your Bakaláři password and token, precisely:

- **Your password is never stored anywhere, ever** — not in this repo, not
  in KWallet, not in a config file, not even locally beyond the few
  milliseconds it takes the backend to exchange it for an OAuth token (see
  "First-time login" above for exactly how it briefly touches disk as a
  0600 temp file that gets deleted immediately after). Once that exchange
  happens, the password is gone. Nobody — including you — can recover it
  from anything this project writes down, because it's simply never
  written down.
- **The only thing persisted is a refresh token** (an opaque OAuth
  credential — not a derivation of your password, and not something your
  password can be recovered from), and it lives *only* in KWallet, an
  OS-level encrypted secret store on your own machine. It is never
  written to `config/main.xml`, never written to any file under this
  project's own directories, and therefore **never ends up in git or
  GitHub, no matter what gets pushed or who compromises that account**.
  There is nothing secret in the published source to steal.
- The **one honest limit**: the background poller needs to read that
  token unattended, on a timer, with nobody present — that's the entire
  point of a background schedule widget. KWallet auto-unlocks alongside
  your login session for this (the same convenience/security tradeoff as
  a browser's saved passwords or an SSH agent), which means anything else
  that manages to run code as you *while your session is unlocked* could
  in principle ask KWallet for it too. That's not a flaw specific to this
  project — it's the universal limit of any local secret store that also
  needs to work unattended. No software claiming otherwise while still
  polling automatically would be telling the truth. The alternative
  (KWallet prompting for approval on every single poll) trades that away
  for an interruption every 15 minutes, which defeats the point of a
  background widget — this project deliberately keeps the standard,
  low-friction balance instead.

### A few more specific things, since they're easy to get wrong quietly

- **Command construction is quoted, not interpolated raw.** The one place
  free-typed text (subdomain/username/password) becomes part of a shell
  command is the login action; every value is passed through a proper
  POSIX single-quote escaper (`Theme.shQuote` — replace `'` with `'\''`,
  wrap in `'...'`) before being embedded. Single-quoted POSIX shell
  strings are fully literal with exactly one exception (an embedded `'`
  itself, which the escaper handles) — backticks, `$(...)`, and embedded
  newlines are all inert inside them, and a NUL byte can't survive into a
  process argument at all regardless of quoting. The backend additionally
  rejects malformed-looking subdomains/usernames outright before doing
  anything with them, as an independent second layer. All of that said:
  Plasma's `executable` data engine only takes a command-line *string*
  (it runs everything through a shell), so eliminating the shell step
  entirely isn't possible without a compiled C++ helper — the mitigation
  here is verified-correct quoting plus a second validation layer, not
  "there's no shell involved."
- **No core dumps.** The backend holds a live access token (and briefly a
  refresh token, mid-exchange) in memory for as long as it runs. Both the
  systemd unit (`LimitCORE=0`) and the script itself
  (`resource.setrlimit(RLIMIT_CORE, (0, 0))`, for when it's run outside
  systemd) disable core dumps, so a crash can't leave a memory image with
  live tokens sitting in `/var/lib/systemd/coredump` readable via
  `coredumpctl` after the fact. Unencrypted swap has the same underlying
  exposure and isn't something this project can fix — that's a system-wide
  setting, not a per-app one.
- **Error messages never carry raw API response bodies for the token
  endpoint.** A failed login/refresh reports a short fixed classification
  ("invalid credentials", "rejected by the server") rather than the
  server's actual response text, since that's the one endpoint where
  token-shaped data could plausibly appear in an error body — and those
  messages get printed to stderr (captured by `journalctl --user`, which
  is typically retained far longer than anything else in this project) as
  well as shown on-screen. The timetable-fetch endpoint (lower
  sensitivity — the token only ever travels in a request header, never
  echoed back) still includes a short response excerpt in its own error
  messages, capped to 150 characters, since that's genuinely useful for
  diagnosing a broken instance.
- **KWallet identity should be consistent across both invocation paths**
  (the systemd daemon and the config page's one-shot calls), since both
  are the same script using the same hardcoded `APP_ID` string passed to
  every KWallet D-Bus call — the classic `org.kde.KWallet` API grants
  access per self-declared `appid` string, not per calling-binary
  identity, so using one fixed string everywhere should mean one grant
  covers both paths. I can reason through the API this way but haven't
  been able to verify it against a live `kwalletd6` myself (no Plasma
  environment here) — worth explicitly testing once: does a systemd-
  triggered poll get wallet access without a fresh prompt on a machine
  where you've only ever run the config page's login flow, never the
  daemon directly?

### Second pass findings (fixed)

A closer look turned up a few more concrete issues, since found-and-fixed
is worth more than never having looked:

- **No text in the widget renders as HTML.** Lesson `subject`/`topic`
  fields are free text a *teacher* types into Bakaláři, not something
  this project controls — and QML's `Text` element defaults to
  auto-detecting and rendering HTML-like content as rich text, which
  supports things like `<img src="...">`. Without an explicit override,
  a lesson topic containing `<img src="http://example.com/beacon">` would
  make the widget fire an outbound request just from rendering the popup,
  no click needed — a privacy/tracking leak entirely outside this
  project's own code, sourced from whatever a school's own Bakaláři
  content happens to contain. Every `Text`/`Label` in the widget now sets
  `textFormat: Text.PlainText` explicitly, which disables that
  auto-detection completely.
- **The `/tmp` fallback directory is hardened against a classic
  predictable-path attack.** When `$XDG_RUNTIME_DIR` is unset (rare on a
  real Plasma session — logind normally guarantees it — but not
  impossible), the backend used to fall back to `/tmp/bakawidget-<uid>`
  and trust it via `os.makedirs(..., exist_ok=True)` without checking who
  actually owns it. Since `/tmp` is world-writable and that name is fully
  predictable, another local user could have pre-created it (or a symlink
  inside it at the exact filename this project writes to) before this
  script ever ran. `_ensure_secure_dir()` now verifies — not just
  assumes — that any pre-existing directory is actually owned by the
  current user with no group/other access, refusing to proceed otherwise;
  `atomic_write_json()` additionally uses `O_NOFOLLOW` so it can't be
  tricked into writing through a symlink even inside a directory it does
  trust. The login flow's temp file (created by a shell command, not
  Python) gets the same protection via a new `ensure-dirs` step that runs
  first and a `set -o noclobber` on the write itself.
- **KWallet D-Bus failures now degrade gracefully instead of crashing.**
  The wallet functions only used to catch the errors they raised
  themselves — a real D-Bus failure (kwalletd6 not running, the access
  dialog being declined, a timeout) would have escaped as a raw,
  unhandled exception instead of the intended "please log in" state,
  and for the one-shot `login` action, that traceback would have flowed
  straight into the config page's on-screen status text. Every wallet
  function now converts any unexpected failure into the same `WalletError`
  the rest of the code already knows how to handle — and `main()` itself
  now has a last-resort catch-all for anything else unexpected (e.g. a
  malformed, non-JSON API response despite a 200 status), so no path
  through this script can end in a raw traceback reaching the screen.
- **The systemd unit now sandboxes what it safely can.** Added
  `NoNewPrivileges`, `ProtectKernelTunables/Modules/Logs`,
  `ProtectControlGroups`, `RestrictSUIDSGID`, `RestrictRealtime`,
  `LockPersonality`, and `MemoryDenyWriteExecute` — all safe for a
  pure-Python network client that never needs kernel modules, SUID/SGID
  execution, or JIT compilation. Deliberately did **not** add
  `ProtectHome`/`ProtectSystem=strict`, which would need a precise
  `ReadWritePaths=` allowlist for `~/.config/bakawidget` and
  `$XDG_RUNTIME_DIR` — getting that wrong would silently break logins in
  a way I can't verify without a live Plasma session to test against, and
  a guess that might break the widget isn't an improvement over the
  narrower hardening actually shipped.

## Resetting / clearing stored credentials

Click **Log out / clear stored credentials** on the config page. This:

- deletes the KWallet entry (folder "BakaWidget") for your subdomain
- deletes `$XDG_CONFIG_HOME/bakawidget/config.json`
- deletes `$XDG_RUNTIME_DIR/bakawidget/state.json`

If you ever need to do this without opening Plasma (e.g. the widget is
misbehaving), the equivalent from a terminal is:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py logout
```

## Handled edge cases

- **Expired/invalid refresh token**: the widget shows a distinct "please
  log in" state (not a blank/broken strip); the backend also proactively
  clears the now-useless KWallet entry so a stale token can't linger.
- **Network errors**: the last known-good schedule stays on screen with a
  small amber dot / "stale" note in the popup, rather than the widget
  going blank.
- **No lessons today** (weekend/holiday): an explicit "No lessons today"
  chip instead of an empty strip.
- **Cancelled lessons**: strikethrough code + a muted red chip in the
  strip, and a red "Cancelled" label in the popup list.
- **Substituted lessons**: a colored ring around the chip in the strip,
  and a "Substituted" label in the popup list.

## A caveat I couldn't resolve without live API access

I don't have a real Bakaláři instance/credentials to test the timetable
parser against, so `bakawidget_backend.py` follows the v3 API schema as
documented by existing open-source clients (bakalari-api, "Lepší
rozvrh"), not a schema I've verified myself. Two spots are explicitly
flagged in the code as best-effort:

1. Whether `/api/3/timetable/actual` omits days with no school entirely
   vs. returning an empty day (handled defensively either way).
2. The exact shape of the per-lesson `Change` object used to detect
   cancellations vs. substitutions — there's no single confirmed enum
   across school deployments.

If lessons, cancellations, or anything else look wrong against your real
timetable, run:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py debug-dump
```

and send me its output so I can fix the parser against your instance's
actual shape instead of guessing further — per your original instructions
not to silently paper over instance-specific unknowns. This is a
deliberately opt-in, read-only command, not something that runs
automatically: it prints the raw timetable response to stdout (nothing
written to disk, nothing left lingering) with known Name-shaped fields
redacted first. **Still review the output yourself before pasting it
anywhere public** — the redaction is a best-effort filter on known field
names, not a guarantee, and room codes/subject names/internal IDs are
kept on purpose since they're what's actually needed to diagnose a
parsing bug. An earlier version of this project wrote an *unredacted* raw
dump to disk on every single poll by default — that was a real bug (the
kind of file a well-meaning person attaches whole to a public GitHub
issue without registering it's their timetable and named teachers), fixed
by making this opt-in and redacted instead of automatic.

## Differences from the Figma reference mockup

The reference (`../reference/`) is a browser mockup simulating a Plasma
desktop, not a real one, so some things could not be, and should not be,
ported literally:

- **Glass/blur panels** (`backdrop-filter: blur(20px) saturate(1.4)` on
  `.plasma-glass`): QML has no equivalent for blurring "whatever happens
  to be behind this specific popup" the way CSS backdrop-filter does.
  Rather than fake it with `Qt5Compat.GraphicalEffects` blurring a grabbed
  snapshot (expensive and only approximately right), the popup and full
  representation deliberately paint no background/border of their own and
  rely on Plasma's own tooltip/dialog chrome, which the compositor
  already blurs via KWin's blur effect when the user has it enabled. This
  is arguably more correct for a native widget, since it follows the
  user's actual Plasma theme frame instead of a fixed translucent
  rectangle.
- **`box-shadow: 0 0 10px ${color}55` glow on the current-lesson chip**:
  ported using `Qt5Compat.GraphicalEffects.RectangularGlow`, which is the
  closest built-in Qt6 primitive; visually very close but not pixel-for-
  pixel identical to a CSS box-shadow's falloff curve.
  - **Neutral chip/border colors** (`rgba(255,255,255,0.04/0.07/0.11/0.18)`
  etc.): re-derived from `Kirigami.Theme.textColor` at the same alphas
  instead of hardcoded white, per the theming split — on a light Plasma
  theme these tint dark instead of staying (near-invisibly) white-on-
  light. This means the widget will *not* look identical to the reference
  screenshot on a light theme; it will look correct for whatever theme
  you're running instead, which is deliberate.
- **Fonts**: the reference imports "Noto Sans"/"Noto Sans Mono" from
  Google Fonts. The QML port uses the system default font for body text
  (via Kirigami's theming, i.e. whatever your Plasma font settings are)
  and the generic Qt `"monospace"` family alias for the mono bits (room
  codes, times), instead of pinning a specific webfont a user may not
  even have installed.
- **Dashed borders / CSS-only affordances**: QML `Rectangle` borders can't
  be dashed, so "substituted" lessons are marked with a solid colored
  ring instead of a dashed one, plus an explicit "Substituted" text label
  in the popup (the reference's sample data has no cancelled/substituted
  lessons at all, so this whole visual language is new, not a port).
- **Hover vs. click**: the reference only supports hover-to-reveal. The
  QML port keeps hover (via `PlasmaCore.ToolTipArea`) but *also* wires the
  same detail card as the applet's `fullRepresentation`, so clicking the
  panel item opens the same card as a normal Plasma popup — this is
  native taskbar-item behavior (e.g. how the digital clock applet works)
  that the browser mockup has no equivalent of, added rather than a
  deviation from something the reference specified.
- **Everything else** (chip paddings/heights/radii, font sizes/weights,
  the popup's 256px width, the header block layout, the "rest of day"
  list row layout) is ported at the literal pixel values from
  `reference/src/App.tsx` / `reference/src/index.css`.

## Dev / testing

```bash
plasmoidviewer -a bakawidget
```

Run it from this project's directory (or point `-a` at the full path) to
iterate without a full install/panel-restart cycle. `plasmoidviewer`
loads the applet standalone; the config dialog and the executable-engine
backend calls work the same way there as in a real panel.

## Publishing to the AUR

This is a one-time job for whoever maintains this package (probably you),
not something each installer needs to do. Once it's done, anyone can
install with an AUR helper — **plain `pacman` cannot install from the AUR
directly**; the AUR is a repository of build recipes, not binary
packages, so people need `yay`/`paru` (which build the package and hand
the result to pacman) or to clone + `makepkg -si` by hand.

I can't do the account-creation steps below for you — creating accounts
on your behalf isn't something I'll do regardless of the site — but
everything else (the PKGBUILD, the checksums, the .SRCINFO command) is
ready to go the moment those accounts exist.

### 1. Put the source somewhere public (e.g. GitHub)

The AUR only stores the PKGBUILD; `makepkg` downloads the actual project
from wherever `source=()` points, in a clean directory with none of your
local files. Push **the contents of this directory** (not the parent repo
that also contains `../reference/`) as the root of its own public git
repo:

```bash
cd bakawidget
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin https://github.com/<you>/bakawidget.git
git push -u origin main
git tag v1.0.0
git push origin v1.0.0
```

### 2. Fill in the PKGBUILD placeholders

Edit `PKGBUILD` (not `PKGBUILD.local`, which is a separate dev-only copy
that keeps working with `makepkg -si` for local testing without any of
this): set `_owner` and `_reponame` to match the repo from step 1.

### 3. Compute real checksums and generate .SRCINFO

```bash
sudo pacman -S --needed pacman-contrib   # for updpkgsums, if you don't have it
updpkgsums                               # rewrites sha256sums=() in place
makepkg --printsrcinfo > .SRCINFO
```

### 4. Test it actually builds from the real source

```bash
makepkg -si
```

If this fails, it means step 1's tag/repo layout doesn't line up with
what `package()` expects (it assumes the repo's root == this directory's
root) — fix that before publishing, not after.

### 5. Create your AUR account and push the package

- Register at https://aur.archlinux.org and add an SSH public key under
  your account's "My Account" page (you'll need one, e.g.
  `ssh-keygen -t ed25519` if you don't already have one to give it).
- Then, from a fresh location (not inside this project):

```bash
git clone ssh://aur@aur.archlinux.org/plasma6-applets-bakawidget.git aur-pkg
cd aur-pkg
cp /path/to/bakawidget/PKGBUILD .
cp /path/to/bakawidget/plasma6-applets-bakawidget.install .
cp /path/to/bakawidget/.SRCINFO .
git add PKGBUILD plasma6-applets-bakawidget.install .SRCINFO
git commit -m "Initial upload: v1.0.0"
git push
```

### 6. What everyone else runs afterwards

```bash
yay -S plasma6-applets-bakawidget
# or
paru -S plasma6-applets-bakawidget
```

### Future updates

Bump `pkgver`/`pkgrel` in `PKGBUILD`, push a matching git tag, re-run
`updpkgsums` and `makepkg --printsrcinfo > .SRCINFO`, then commit and push
those two files (PKGBUILD + .SRCINFO) to the AUR git repo again.

### Other distros

Nothing here is Arch-specific in principle (it's QML + Python + a
systemd unit), but there's no equivalent of "just add a repo and
`apt`/`dnf` install it" without someone building the matching Debian
(`debian/control` + `debian/rules`) or Fedora (`.spec`) packaging, which
isn't done here since you're on Arch — say so if you end up wanting one
of those too.
