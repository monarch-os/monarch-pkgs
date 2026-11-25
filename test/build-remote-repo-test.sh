#!/bin/bash
set -euo pipefail

root=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
docker run --rm -i --network none --user root \
  -v "$root:/repo:ro" --entrypoint bash \
  "${MONARCH_TEST_IMAGE:-monarch-pkg-builder:latest-x86_64}" -s <<'SCRIPT'
set -euo pipefail
mkdir -p /http /dependency /pkgbuilds/fixture-app /pkgs.monarchlinux.com/x86_64 /build-output/x86_64
ln -s /repo/build /build
cat > /dependency/PKGBUILD <<'PKGBUILD'
pkgname=fixture-lib
pkgver=1
pkgrel=1
arch=(any)
package() {
  mkdir -p "$pkgdir/usr/share/fixture"
  echo dependency > "$pkgdir/usr/share/fixture/lib"
}
PKGBUILD
cat > /pkgbuilds/fixture-app/PKGBUILD <<'PKGBUILD'
pkgname=fixture-app
pkgver=1
pkgrel=1
arch=(any)
depends=(fixture-lib)
package() {
  test -f /usr/share/fixture/lib
  mkdir -p "$pkgdir/usr/share/fixture"
  echo app > "$pkgdir/usr/share/fixture/app"
}
PKGBUILD
chown -R builder:builder /dependency /src /build-output /pkgs.monarchlinux.com /pkgbuilds
(cd /dependency && sudo -u builder makepkg --noconfirm)
mv /dependency/*.pkg.tar.zst /http/
repo-add /http/monarch.db.tar.zst /http/*.pkg.tar.zst
cp /http/monarch.db.tar.zst /pkgs.monarchlinux.com/x86_64/
printf '[options]\nArchitecture = auto\nSigLevel = Never\nDisableSandboxNetwork\n' > /etc/pacman.conf
python3 - <<'PY'
import http.server
import subprocess
import threading

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="/http", **kwargs)

    def log_message(self, message, *args):
        with open("/http.log", "a") as log:
            log.write(message % args + "\n")

with http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run(["sudo", "-u", "builder", "env",
                        "MONARCH_REPO_SERVER=http://127.0.0.1:8765",
                        "MONARCH_CLEAN_BUILD=1", "bash", "/repo/build/build.sh"], check=True)
    finally:
        server.shutdown()
        thread.join()
PY
test -f /build-output/x86_64/fixture-app-1-1-any.pkg.tar.zst
test ! -e /src/fixture-app
test ! -e /pkgs.monarchlinux.com/x86_64/fixture-lib-1-1-any.pkg.tar.zst
grep 'GET /fixture-lib-1-1-any.pkg.tar.zst HTTP/1.1" 200' /http.log
echo "Remote dependency installed with a database-only production snapshot"
SCRIPT
