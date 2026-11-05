# Releasing Tuned Chaos

Everything about packaging and releasing lives in this folder. Three things
can't: the GitHub workflows (`.github/workflows/`, where GitHub reads them),
`CMakePresets.json` (CMake looks for it at the top of the project), and the
Android media service, which is app code.

## One code base, three platforms

Code that only works on one platform sits behind a small interface with one
`.cpp` per platform, picked in `CMakeLists.txt` (`CMP_PLATFORM` is `linux`,
`windows` or `android`). Everything else is shared, so a new feature needs no
per-platform work. `.github/workflows/build.yml` builds every platform when a
version tag is pushed (not on ordinary pushes).

### Paths

Inside the app a path is a UTF-8 string with `/` between folders, on every
platform (Qt does the same). Where a `std::filesystem::path` becomes such a
string, use `generic_string()`, not `string()` (which gives `\` on Windows).
On Windows the app's manifest sets the UTF-8 code page, so `std::string`
paths are read as UTF-8 by `std::filesystem`, file streams and TagLib. Shown
to the user, a path may use the platform's own separators.

### yt-dlp

YouTube songs play through yt-dlp. At every start the app picks the newest
copy that works (its own, in its data folder; one shipped next to it; the
system's), then checks GitHub for a newer release and, if there is one,
downloads yt-dlp's standalone build for the platform, checks it against
yt-dlp's SHA-256 sums and uses it (`wrapper/youtube/ytdlpmanager.h`).
Settings > YouTube Music shows the version and has an "Update yt-dlp" button.
Build with `-DCMP_YTDLP_SELF_UPDATE=OFF` where the store updates yt-dlp and
forbids downloads at runtime (Flathub).

## Packages

| Platform | Packages |
| --- | --- |
| Linux | tarball with `install-app.sh` / `uninstall-app.sh`, AppImage, Flatpak |
| Windows | portable ZIP, installer EXE (Inno Setup) |
| Android | APK |

## Linux packages (`release/linux/`)

- `io.github.chandandasgit.TunedChaos.desktop` / `.metainfo.xml`: the
  app's launcher entry and what software centers show; every package uses
  them (the app id is also the app's desktop name).
- `make-packages.sh <build> <output>`: the AppImage and the tarball. Both hold
  the app with Qt, its libraries and yt-dlp (linuxdeploy). They run on systems
  as new as the one that built them, so CI builds them on Ubuntu 24.04.
- `install-app.sh` / `uninstall-app.sh`: inside the tarball; installs for the
  user in `~/.local/opt/TunedChaos` with a launcher entry.
- `flatpak/`: the Flatpak manifest (KDE runtime). Built in CI with Flathub's
  own tools; for Flathub, see the notes at its top.

## Publishing a release

Only a pushed version tag starts a build; ordinary pushes don't. GitHub then
builds and tests everything and publishes all six
packages and `SHA256SUMS.txt` by itself (`publish`, the last job of
`.github/workflows/build.yml`). Nothing is built on your computer, and a failed
build or test publishes nothing.

```sh
git push origin master
git tag v1.0
git push origin v1.0
```

- A tag with a dash (`v1.1-test1`) makes a pre-release; without one (`v1.1`)
  a normal release.
- The tag's number must match `project(... VERSION ...)` in `CMakeLists.txt`.
  For a new version, change it there first, and raise
  `QT_ANDROID_VERSION_CODE` too (Android only updates to a higher code).
- To remove a test release and its tag:
  `gh release delete v1.1-test1 --cleanup-tag`
- To check a build without releasing: Actions > Build > Run workflow.

## In-app updates

The app looks for a newer release at startup (Settings > About: the switch,
and "Check now", which also says when it's the newest or GitHub can't be
reached). It installs the update the way that copy was installed
(`wrapper/update/appupdater_<platform>.cpp`): Android's installer for the APK,
the AppImage swapped in one step, the tarball's `install-app.sh` run, the
Windows setup or portable ZIP once the app has closed. Flatpak and own builds
only point to the release page.

Nothing can strand a user:

- Every failure shows what went wrong, "Try again" and "Download it
  yourself" (the latest release's page): trying again is always up to you.
- The version being installed is saved first. Still the older version at the
  next start (or back from Android's installer without it): the app says the
  update didn't finish, with the same two ways.
- `install-app.sh` copies the new app next to the old one and swaps it in only
  once it's complete; a failed copy leaves the old one as it was.
- Programs the updater starts (tar, the installer) run without the app's
  bundled libraries: the launcher points `LD_LIBRARY_PATH` at them, and
  1.1.6's updater broke that way (system xz loading the bundled, older
  liblzma).

Before a release, CI installs the Linux packages in Ubuntu 24.04 and Fedora
containers and lets them update themselves through their own launchers
(`release/linux/test-update.sh`, which runs the app's hidden
`--install-update <file>`); no release if that fails. To run it locally:
`release/linux/test-update.sh build/packages`, in a container with the usual
desktop libraries (see the `update-test` job). Test updaters only with real
packages: a local build started by hand doesn't get the launcher's
environment. Windows and Android updates are tested by hand.

## Building locally

Linux:

```sh
cmake --preset linux-release
cmake --build --preset linux-release
./build/linux-release/TunedChaos
```
