<h3 align="center">🇬🇧 English &nbsp;|&nbsp; <a href="README.cs.md">🇨🇿 Čeština</a></h3>

# BakaWidget

A KDE Plasma 6 taskbar widget that shows your upcoming Bakaláři school
lessons — current lesson, what's next, cancellations and substitutions —
right in the panel, with a detail popup on hover or click.

## Features

- Compact strip in the panel: previous lesson (faint), current lesson
  (highlighted, subject-colored), and your next few upcoming lessons
- Hover or click for a full detail popup: subject, teacher, room, topic,
  and the rest of the day
- Cancelled lessons shown with strikethrough; substituted lessons marked
  distinctly
- Handles no-school days, network hiccups (shows last-known schedule,
  not a blank widget), and "please log in" clearly
- Per-subject colors, consistent every time

## Requirements

- KDE Plasma 6
- Python 3 and `python-dbus` (`pacman -S python python-dbus` on Arch)
- KWallet (enabled by default on Plasma 6)

## Install

```bash
cd bakawidget
./install.sh
```

This installs the plasmoid and sets up a background service that keeps
your schedule up to date. Add **BakaWidget** to a panel afterwards
(right-click the panel → *Add Widgets…*).

Prefer a real pacman package? `makepkg -si` builds
`plasma6-applets-bakawidget` instead — see [PUBLISHING.md](PUBLISHING.md)
if you want to publish it to the AUR. To remove everything again, run
`./uninstall.sh`.

## First-time login

Right-click the widget → **Configure BakaWidget…** → enter your school's
subdomain (the `skola` part of `skola.bakalari.cz`), your username and
password → **Log in**. The widget should populate within a few seconds.

Your password is used once to sign in and is never stored anywhere —
see [SECURITY.md](SECURITY.md) for exactly how that works.

## Settings

- **Refresh interval** — how often to check for updates (default 15 min)
- **Upcoming lessons to show** — how many chips appear in the strip

Both apply immediately, no need to log in again. Changing the subdomain
or username does need a fresh login, since those are tied to your stored
session.

## Resetting / logging out

Click **Log out / clear stored credentials** on the config page, or run:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py logout
```

## Troubleshooting

If lessons, cancellations, or subjects look wrong, it's likely a
schema difference in your school's Bakaláři instance (see
[SECURITY.md](SECURITY.md#known-limitations) for why). Run:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py debug-dump
```

and open an issue with the output — it redacts names before printing,
but please skim it yourself first.

## How it works

- **`contents/ui/`** — the plasmoid itself (QML, Kirigami). Pure
  presentation; never touches the network or your password.
- **`contents/backend/bakawidget_backend.py`** — a small Python daemon
  that owns login, token refresh, KWallet storage, and polling.
- The two talk through a JSON file (`state.json`) the backend writes and
  the widget reads, plus one-shot commands (log in, log out, change
  interval) for anything that needs to happen once.
- The backend runs continuously as a `systemd --user` service, so your
  schedule stays current whether or not the widget is visible.

## Development

```bash
plasmoidviewer -a bakawidget
```

Loads the applet standalone for quick iteration, without a full
install/panel-restart cycle. See [DESIGN_NOTES.md](DESIGN_NOTES.md) for
where and why the QML port deviates from the original Figma mockup.

## Security

Your password is never stored — see [SECURITY.md](SECURITY.md) for the
full model (what's stored where, how login works, and known limitations).

## License

MIT — see [LICENSE](LICENSE).
