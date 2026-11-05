# Tuned Chaos

A music player for Linux, Windows and Android with a Qt 6 / QML interface and a
pure C++ backend (FFmpeg for decoding, TagLib for tags; PipeWire for output on
Linux, miniaudio on Windows and Android). It plays your local music and can also
browse and play YouTube Music.

## Screenshots

<p>
  <img src="resources/screenshots/desktop.png" alt="The Queue and the player" width="49%">
  <img src="resources/screenshots/lyrics.png" alt="Synced lyrics" width="49%">
</p>
<p>
  <img src="resources/screenshots/player.png" alt="The player at phone size" width="32%">
  <img src="resources/screenshots/queue.png" alt="The Queue at phone size" width="32%">
  <img src="resources/screenshots/library.png" alt="The Library at phone size" width="32%">
</p>

(The songs and covers shown are made up for these pictures.)

## Install

Download a package from the
[Releases page](https://github.com/ChandanDasGIT/TunedChaos/releases). Each one
brings what it needs; you don't install Qt or anything else yourself.

| Platform | Package | How |
| --- | --- | --- |
| Windows | `...-setup-x64.exe` | Run it. Installs for your user, no administrator rights needed |
| Windows | `...-windows-x64-portable.zip` | Extract the whole ZIP, then run `TunedChaos.exe` |
| Android | `...-arm64.apk` | Open it on your phone and allow installing from that app |
| Linux | `...-x86_64.AppImage` | Make it executable (below), then run it |
| Linux | `...-linux-x86_64.tar.xz` | Unpack it, then run `./install-app.sh` (no root needed; `./uninstall-app.sh` removes it) |
| Linux | `TunedChaos-x86_64.flatpak` | `flatpak install --user TunedChaos-x86_64.flatpak` (fetches the KDE runtime from Flathub if you don't have it) |

Downloads don't keep Linux's "executable" permission, so an AppImage needs it
set once, with its Properties dialog or:

```sh
chmod +x TunedChaos-*.AppImage
```

## Features

### Home

- A greeting, then **Your Mix** (the songs you play most, shuffled),
  recently played, most played this month, albums to jump back into,
  recently added albums, your smart playlists and a YouTube Mix recommended
  from the YouTube song you play most.
- **History**: everything you listened to, by day ("See all"), and **your
  stats**. The history stays on your computer and can be turned off or
  cleared in Settings.
- **Smart playlists**: lists that fill themselves from rules (played more
  than 10 times, added in the last 30 days, artist contains...), matching all
  or any rule, in the order you pick, as long as you want.

### Playing music

- **Play from where you are**: clicking a song in the Library plays the list
  it's in (all songs, an album, an artist, a folder) from that song, with
  next / previous. Nothing is added to the Queue unless you add it.
- **Queue**: your own list. Add songs with *Add to queue* or *Play next* in
  the song menus, by dragging songs, albums, folders or YouTube playlists onto
  it (dropped at the spot you choose), or by dropping files and folders on the
  window. Sort by any column, drag a song by its handle to move it, swipe to
  delete.
- **Playlists**: named playlists that play without touching the Queue;
  import and export them as M3U / M3U8 (or drop an `.m3u` file on the window).
- **Between songs**: gapless playback, or a fade: each song fades out at its
  very end and the next one fades in from its start, so nothing overlaps or
  is cut. Songs that run into each other on an album always stay gapless.
- **10-band equalizer** (31 Hz to 16 kHz, ±12 dB) with presets, heard as you
  move the sliders; boosting keeps the volume (a limiter only catches peaks
  that would distort). Open it from the button beside the volume bar.
- **ReplayGain**: off, by track or by album, so songs play at an even volume.
- **Sleep timer**: pause after a while, or at the end of the song (in
  Settings).
- **Moods**: the heart on the player adds the song to Happy, Sad, Bored,
  Suspense, METAL or Dance; they play from Home.
- **Resume where you left off**: the song, the position and the list it was
  playing from come back, paused, when you start the app again.
- Shuffle, repeat and autoplay (YouTube Mix) side by side, output device
  choice, a quality chip (sample rate, bitrate, format; click it for the
  track's details), and background playing (closing the window keeps the
  music going, if you want).
- **Song-change notifications** with the title, artist and cover, while the
  window isn't in front.

### Library

- Songs, Albums, Artists, Genres and Folders each have search and their own
  sort (by name, date added, date modified, song count and more).

- Songs, Albums, Artists and Folders, with live search, refreshed in the
  background (only new or changed files are read). Albums are grouped by
  album artist, so compilations stay together; recently added albums show on
  Home.
- **Tag editor**: change a song's title, artist, album and other tags from
  its details (a safety copy is kept while the file is saved).
- **Folders** is browsed like a file manager: a path bar, then the folder's
  subfolders and songs; play or queue a whole folder, subfolders included.
- The music folders (and the ones to leave out) are chosen in Settings.

### YouTube Music

- Home, search, your library (liked songs) and saved links; songs play
  through [yt-dlp](https://github.com/yt-dlp/yt-dlp).
- **Search** for songs, albums or artists. An artist's page has their top
  songs, albums, singles and similar artists; albums and playlists open over
  any tab.
- **Mix (autoplay)**: a song plays followed by what YouTube Music plays next,
  topped up as it goes; an album or playlist plays as it is, then its Mix.
  When the Queue ends on a YouTube song, its Mix can follow. Both can be
  turned off.
- **Recent searches**: the searches you used, newest first; remove one or all.
- **Audio quality**: Auto (best, but the smallest streams on a metered
  connection), Best or Lowest.
- Signing in uses the session of a browser you choose (the app never sees
  your password). Local songs can be matched to YouTube Music in the
  background for extra details.

### Lyrics and covers

- **Lyrics**: local `.lrc` files and tags, [LRCLIB](https://lrclib.net) and
  YouTube Music, in the order you choose; synced lyrics follow the song.
  Credit lines and line-by-line translations are left out, and Japanese and
  Korean lyrics use a matching font when one is installed.
- **Album art**: embedded covers and folder images; missing ones can be found
  online (iTunes, MusicBrainz / Cover Art Archive, YouTube Music). YouTube
  songs use their thumbnails.

### Look and layout

- A navigation bar at the bottom: YouTube Music, Queue, Home, Library and
  Settings.
- The layout follows how much of the screen the window covers, on any
  monitor:
  - **full screen**: the Queue or Home, the player, and YouTube Music, the
    Library or Settings side by side, sharing the width equally (Home and
    Settings slide up over the panel under them);
  - **half screen**: two columns at most; an opened panel can push the player
    aside, and a floating mini player stands in for it. Panels can be swiped
    away, or swiped in from the window's edge;
  - **phone size**: the player, with panels sliding over it.
  Pinned panels stay open (also after a restart).
- Theme: follow the system, dark or light. The background takes on the
  colour of the playing song's cover. Optional visualizer.
- **Interface size** from 90% to 150% (applied after a restart, which the app
  can do for you).
- **Settings** open like a phone's settings app, in the right-hand column: a
  list of categories, and a search bar at the bottom that finds any setting.

- **Layout Customisation** (phones): choose the bottom bar's panels and their
  order; choose what opens at start on every platform.
- **Seekbar**: two animations and ten thumbs, also for the bottom bar's toy
  seekbar. **Album art** can grow up to edge to edge.
- **Audio pipeline** in a song's details: every stage from file to speaker.

### Desktop integration

- MPRIS (media keys, desktop media controls, `playerctl`) and one running copy
  at a time.
- **Tray icon** (Linux and Windows): closing the window, or Ctrl+C in a
  terminal, keeps the app in the tray, still playing. Click the icon to show or
  hide the window; its menu has play / pause, next, previous and Quit. It can be
  turned off in Settings → General.
- **Home-screen widget** (Android): the song with previous, play / pause and
  next; add it from the launcher's widgets or Settings → Layout Customisation.
- **Backup and restore** (Settings → About): one `.tcbackup` file with your
  settings, playlists, Queue, history, moods, smart playlists, library and
  server sign-ins; restoring it (on any of your devices) restarts the app with it.
- **Panel sides**: in Settings → Layout Customisation, choose for each panel
  whether it opens left or right of the player, and drag the bottom bar's
  panels into the order you like.

## Keyboard shortcuts

| Action | Keys |
| --- | --- |
| Play / pause | Space |
| Next / previous song | Ctrl+→ / Ctrl+← |
| Seek 5 s forward / back | → / ← |
| Seek 30 s forward / back | Shift+→ / Shift+← |
| Volume up / down | Ctrl+↑ / Ctrl+↓ |
| Mute | M |
| Shuffle | Ctrl+S |
| Repeat (cycles) | Ctrl+R |
| Lyrics | Ctrl+L |
| Search (Library if open, else YouTube Music) | Ctrl+F |
| Queue / YouTube Music / Library | Ctrl+1 / 2 / 3 |
| Settings | Ctrl+, |
| Close lyrics or a dialog; in Settings: back, then close | Esc |
| Quit | Ctrl+Q |

The list is also in Settings → Keyboard shortcuts.

## Requirements (to build it yourself)

- A C++20 compiler, CMake 3.21+ and pkg-config
- Qt 6.10+ (Quick, QuickControls2, Network; DBus on Linux)
- FFmpeg (libavformat, libavcodec, libavutil, libswresample)
- PipeWire (libpipewire-0.3)
- TagLib 2
- ICU, libcurl, nlohmann-json
- At run time, for YouTube playback: `yt-dlp`

Fedora:

```sh
sudo dnf install gcc-c++ cmake ninja-build pkgconf qt6-qtbase-devel qt6-qtdeclarative-devel \
    ffmpeg-free-devel pipewire-devel taglib-devel libicu-devel libcurl-devel json-devel yt-dlp
```

Arch Linux:

```sh
sudo pacman -S base-devel cmake ninja qt6-base qt6-declarative ffmpeg pipewire taglib icu curl \
    nlohmann-json yt-dlp
```

## Build and run

```sh
cmake --preset linux-release
cmake --build --preset linux-release
./build/linux-release/TunedChaos
```

Packaging and releases (Windows, Android and Linux packages) are described in
[release/README.md](release/README.md).

To add it to your app launcher (for your user only), run
`scripts/install-desktop.sh` after building; `scripts/uninstall-desktop.sh`
removes it again.

## Where it keeps your data

| What | Where |
| --- | --- |
| Settings (equalizer and recent searches too) | `~/.config/TunedChaos/settings.conf` |
| Queue, playlists, smart playlists, listening history, library index, what was playing | `~/.local/share/TunedChaos/` |
| Found covers, lyrics and YouTube Music matches | `~/.cache/TunedChaos/` |

(Data from before the app was renamed, in the `ChaoticMusicPlayer` folders,
is moved to these the first time it starts.)

Everything stays on your computer. Your music files are only changed when you
save tags in the tag editor.

## Project layout

- `backend/`: plain C++ (no Qt): decoding, the equalizer and audio output,
  tags, library, playlists, lyrics, covers, YouTube Music. One folder per
  `.h` / `.cpp` pair.
- `wrapper/`: Qt objects and models that expose the backend to QML.
- `frontend/`: the QML interface.
- `scripts/`: launcher install scripts, and `shot-build.sh` / `shot-run.sh`,
  a screenshot test harness that runs the app offscreen in an isolated
  configuration (it refuses to run while the app itself is open).

## Note on YouTube Music

The YouTube Music features use unofficial interfaces and are meant for
personal use. They may stop working if YouTube changes them; updating yt-dlp
usually fixes playback problems.

## License

See [LICENSE](LICENSE).
