# Publishing to the AUR

One-time maintainer setup — not needed just to install the widget. Once
done, others install with an AUR helper (`yay -S plasma6-applets-bakawidget`
or `paru -S ...`); plain `pacman` never talks to the AUR directly, since
it's a repository of build recipes, not binary packages.

## 1. Push a tagged release

`PKGBUILD` builds from a git tag rather than local files, since AUR
builds always happen in a clean environment:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`_owner`/`_reponame` in `PKGBUILD` should already match this repo.

## 2. Compute checksums and generate .SRCINFO

```bash
sudo pacman -S --needed pacman-contrib   # for updpkgsums
updpkgsums                               # rewrites sha256sums=() in place
makepkg --printsrcinfo > .SRCINFO
```

## 3. Confirm it actually builds from the tag

```bash
makepkg -si
```

If this fails, the tag/repo layout doesn't match what `package()`
expects — fix that before publishing, not after.

## 4. Push to the AUR

Register at [aur.archlinux.org](https://aur.archlinux.org) and add an SSH
key under your account, then:

```bash
git clone ssh://aur@aur.archlinux.org/plasma6-applets-bakawidget.git aur-pkg
cd aur-pkg
cp /path/to/bakawidget/{PKGBUILD,plasma6-applets-bakawidget.install,.SRCINFO} .
git add PKGBUILD plasma6-applets-bakawidget.install .SRCINFO
git commit -m "Initial upload: v1.0.0"
git push
```

## Future updates

Bump `pkgver`/`pkgrel` in `PKGBUILD`, push a matching tag, re-run
`updpkgsums` and `makepkg --printsrcinfo > .SRCINFO`, then commit and push
those two files to the AUR repo again.

## Other package managers

Nothing here is Arch-specific in principle (QML + Python + a systemd
unit), but there's no "just add a repo" equivalent for other distros
without someone building matching Debian (`debian/control`+`rules`) or
Fedora (`.spec`) packaging — not done here.

`PKGBUILD.local` is a separate, dev-only variant that packages the files
already in this directory instead of downloading a release — useful for
`makepkg -si` testing before you've pushed anything.
