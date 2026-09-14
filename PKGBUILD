# Maintainer: You <you@example.invalid>
#
# AUR-ready package: builds from a tagged GitHub release rather than local
# files, since AUR/makepkg builds always happen in a clean environment.
#
# Before this is ready to push to the AUR you must:
#   1. Fill in _owner and _reponame below (and `url=`) to match wherever
#      you push this project's git repo.
#   2. Push a tag matching pkgver, e.g.: git tag v1.0.0 && git push origin v1.0.0
#   3. Run `updpkgsums` (pacman-contrib) to fill in the real sha256sums,
#      replacing the SKIP placeholder.
#   4. Run `makepkg --printsrcinfo > .SRCINFO` (required by the AUR, and
#      not included here since it must exactly match this file).
#   5. Test it actually builds: `makepkg -si`
# See README.md's "Publishing to the AUR" section for the full walkthrough.
pkgname=plasma6-applets-bakawidget
pkgver=1.0.0
pkgrel=1
pkgdesc="Plasma 6 taskbar widget showing your upcoming Bakaláři school lessons"
arch=('any')
_owner=CHANGEME        # <-- your GitHub username/org
_reponame=CHANGEME     # <-- the GitHub repo name
url="https://github.com/${_owner}/${_reponame}"
license=('MIT')
depends=('plasma-workspace' 'python' 'python-dbus')
install="${pkgname}.install"
source=("$pkgname-$pkgver.tar.gz::https://github.com/${_owner}/${_reponame}/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')    # <-- replace via `updpkgsums` before publishing

package() {
    local plugin_id=bakawidget
    # GitHub's release tarballs extract to "<repo>-<tag-without-leading-v>".
    local srcroot="${srcdir}/${_reponame}-${pkgver}"
    local dest="${pkgdir}/usr/share/plasma/plasmoids/${plugin_id}"

    install -dm755 "${dest}"
    cp -r "${srcroot}/contents" "${dest}/"
    install -Dm644 "${srcroot}/metadata.json" "${dest}/metadata.json"

    install -Dm644 "${srcroot}/systemd/bakawidget-backend.service" \
        "${pkgdir}/usr/lib/systemd/user/bakawidget-backend.service"
}
