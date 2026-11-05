cmake_minimum_required(VERSION 3.21)

project(TunedChaos VERSION 1.1.5 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# Platforms: one code base for Linux, Windows and Android. Code that only
# works on one of them lives behind a small interface with one .cpp per
# platform; the lists below pick the right ones (see release/README.md).
# ---------------------------------------------------------------------------
if(ANDROID)
    set(CMP_PLATFORM android)
elseif(WIN32)
    set(CMP_PLATFORM windows)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(CMP_PLATFORM linux)
else()
    message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_NAME}")
endif()
message(STATUS "Building for ${CMP_PLATFORM}")

# Warnings, and UTF-8 source files with Microsoft's compiler
if(MSVC)
    set(CMP_WARNINGS /W3 /utf-8 /Zc:__cplusplus)
else()
    set(CMP_WARNINGS -Wall -Wextra)
endif()
if(WIN32)
    # Windows' headers would otherwise define min / max as macros (breaking std::min)
    add_compile_definitions(NOMINMAX)
endif()

set(CMP_QT_COMPONENTS Quick QuickControls2 Network)
if(CMP_PLATFORM STREQUAL "linux")
    list(APPEND CMP_QT_COMPONENTS DBus) # media controls (MPRIS), notifications
endif()
if(CMP_PLATFORM STREQUAL "linux" OR CMP_PLATFORM STREQUAL "windows")
    list(APPEND CMP_QT_COMPONENTS Widgets) # the tray icon and its menu
endif()
find_package(Qt6 6.10 REQUIRED COMPONENTS ${CMP_QT_COMPONENTS})
qt_standard_project_setup(REQUIRES 6.10) # the oldest Qt built and tested (CI)

find_package(Threads REQUIRED)
find_package(CURL REQUIRED)
find_package(nlohmann_json 3 REQUIRED)

# FFmpeg, TagLib and ICU: the system's on Linux (pkg-config); from vcpkg
# (release/vcpkg.json) on Windows and Android.
add_library(cmp_deps INTERFACE)
if(CMP_PLATFORM STREQUAL "linux")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavformat libavcodec libavutil libswresample)
    pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3) # sound output
    pkg_check_modules(TAGLIB REQUIRED IMPORTED_TARGET taglib)
    pkg_check_modules(ICU REQUIRED IMPORTED_TARGET icu-uc icu-i18n)
    target_link_libraries(cmp_deps INTERFACE PkgConfig::FFMPEG PkgConfig::PIPEWIRE PkgConfig::TAGLIB PkgConfig::ICU)
else()
    find_package(FFMPEG REQUIRED)
    target_include_directories(cmp_deps INTERFACE ${FFMPEG_INCLUDE_DIRS})
    target_link_directories(cmp_deps INTERFACE ${FFMPEG_LIBRARY_DIRS})
    find_package(TagLib CONFIG REQUIRED)
    find_package(ICU REQUIRED COMPONENTS uc i18n data)
    find_path(MINIAUDIO_INCLUDE_DIR miniaudio.h REQUIRED) # sound output
    target_include_directories(cmp_deps INTERFACE ${MINIAUDIO_INCLUDE_DIR})
    target_link_libraries(cmp_deps INTERFACE ${FFMPEG_LIBRARIES} TagLib::tag ICU::i18n ICU::uc ICU::data)
endif()

# ---------------------------------------------------------------------------
# Backend: pure C++ engine. Must never link Qt.
# ---------------------------------------------------------------------------
add_library(backend STATIC
    backend/audioengine/audiooutput/audiooutput.h
    backend/audioengine/decoder/decoder.cpp
    backend/audioengine/decoder/decoder.h
    backend/library/tageditor/tageditor.cpp
    backend/library/tageditor/tageditor.h
    backend/playlist/smartplaylist/smartplaylist.cpp
    backend/playlist/smartplaylist/smartplaylist.h
    backend/history/listeninghistory/listeninghistory.cpp
    backend/history/listeninghistory/listeninghistory.h
    backend/audioengine/equalizer/equalizer.cpp
    backend/audioengine/equalizer/equalizer.h
    backend/audioengine/player/player.cpp
    backend/audioengine/player/player.h
    backend/audioengine/ringbuffer/ringbuffer.h
    backend/audioengine/spectrum/spectrum.cpp
    backend/audioengine/spectrum/spectrum.h
    backend/library/coverfinder/coverfinder.cpp
    backend/library/coverfinder/coverfinder.h
    backend/hosted/hostedserver/hostedserver.cpp
    backend/hosted/hostedserver/hostedserver.h
    backend/hosted/hostedstore/hostedstore.cpp
    backend/hosted/hostedstore/hostedstore.h
    backend/hosted/jellyfin/jellyfin.cpp
    backend/hosted/jellyfin/jellyfin.h
    backend/library/letterindex/letterindex.cpp
    backend/library/letterindex/letterindex.h
    backend/library/metadata/metadata.cpp
    backend/library/metadata/metadata.h
    backend/library/musiclibrary/musiclibrary.cpp
    backend/library/musiclibrary/musiclibrary.h
    backend/library/scanner/scanner.cpp
    backend/library/scanner/scanner.h
    backend/library/track/track.h
    backend/backup/backuparchive/backuparchive.cpp
    backend/backup/backuparchive/backuparchive.h
    backend/loudness/loudnessmeter/loudnessmeter.cpp
    backend/loudness/loudnessmeter/loudnessmeter.h
    backend/loudness/loudnessstore/loudnessstore.cpp
    backend/loudness/loudnessstore/loudnessstore.h
    backend/lyrics/lrcparser/lrcparser.cpp
    backend/lyrics/lrcparser/lrcparser.h
    backend/lyrics/lyricsprovider/lyricsprovider.cpp
    backend/lyrics/lyricsprovider/lyricsprovider.h
    backend/lyrics/transliterator/transliterator.cpp
    backend/lyrics/transliterator/transliterator.h
    backend/network/httpclient/httpclient.cpp
    backend/network/httpclient/httpclient.h
    backend/storage/tsv/tsv.h
    backend/system/process/process.h
    backend/update/appupdate/appupdate.cpp
    backend/update/appupdate/appupdate.h
    backend/update/sha256/sha256.cpp
    backend/update/sha256/sha256.h
    backend/youtube/linklibrary/linklibrary.cpp
    backend/youtube/linklibrary/linklibrary.h
    backend/youtube/streamresolver/streamresolver.cpp
    backend/youtube/streamresolver/streamresolver.h
    backend/youtube/ytdlp/ytdlp.cpp
    backend/youtube/ytdlp/ytdlp.h
    backend/youtube/ytmatcher/ytmatcher.cpp
    backend/youtube/ytmatcher/ytmatcher.h
    backend/youtube/ytmetadatastore/ytmetadatastore.cpp
    backend/youtube/ytmetadatastore/ytmetadatastore.h
    backend/youtube/ytmusicclient/ytmusicclient.cpp
    backend/youtube/ytmusicclient/ytmusicclient.h
    backend/playlist/m3u/m3u.cpp
    backend/playlist/m3u/m3u.h
    backend/playlist/playlist/playlist.cpp
    backend/playlist/playlist/playlist.h
    backend/playlist/playlistlibrary/playlistlibrary.cpp
    backend/playlist/playlistlibrary/playlistlibrary.h
    backend/playlist/playliststore/playliststore.cpp
    backend/playlist/playliststore/playliststore.h
    backend/settings/settings/settings.cpp
    backend/settings/settings/settings.h
)

# The platform's parts (see CMP_PLATFORM above)
if(CMP_PLATFORM STREQUAL "linux")
    target_sources(backend PRIVATE
        backend/audioengine/audiooutput/audiooutput_linux.cpp
        backend/system/process/process_posix.cpp
    )
elseif(CMP_PLATFORM STREQUAL "windows")
    target_sources(backend PRIVATE
        backend/audioengine/audiooutput/audiooutput_miniaudio.cpp
        backend/system/process/process_windows.cpp
    )
elseif(CMP_PLATFORM STREQUAL "android")
    target_sources(backend PRIVATE
        backend/audioengine/audiooutput/audiooutput_miniaudio.cpp
        backend/system/process/process_android.cpp
    )
endif()

set_target_properties(backend PROPERTIES AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
target_include_directories(backend PUBLIC ${CMAKE_SOURCE_DIR})
target_compile_options(backend PRIVATE ${CMP_WARNINGS})
target_link_libraries(backend PRIVATE
    cmp_deps
    CURL::libcurl
    nlohmann_json::nlohmann_json
    Threads::Threads
)

# ---------------------------------------------------------------------------
# ChaoticStyle: the app's Qt Quick Controls style. It only replaces ToolTip;
# everything else falls back to the Basic style.
# ---------------------------------------------------------------------------
qt_add_library(chaoticstyle STATIC)
qt_add_qml_module(chaoticstyle
    URI ChaoticStyle
    VERSION 1.1.5
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/ChaoticStyle
    QML_FILES
        frontend/style/ToolTip.qml
    IMPORTS
        QtQuick.Controls.Basic
)

# ---------------------------------------------------------------------------
# Application: wrapper + frontend QML module
# ---------------------------------------------------------------------------
qt_add_executable(TunedChaos
    main.cpp
    # Not QML types, so not part of the QML module below
    wrapper/session/sessioncontroller.cpp
    wrapper/session/sessioncontroller.h
    wrapper/singleinstance/singleinstance.cpp
    wrapper/singleinstance/singleinstance.h
    wrapper/systemmedia/systemmedia.h
    wrapper/opener/fileopener.cpp
    wrapper/opener/fileopener.h
    wrapper/update/appupdater.cpp
    wrapper/update/appupdater.h
    wrapper/tray/trayicon.cpp
    wrapper/tray/trayicon.h
    wrapper/backup/backupcontroller.cpp
    wrapper/backup/backupcontroller.h
)

# The platform's parts (see CMP_PLATFORM above)
if(CMP_PLATFORM STREQUAL "linux")
    target_sources(TunedChaos PRIVATE
        wrapper/mpris/mprisadaptor.cpp
        wrapper/mpris/mprisadaptor.h
        wrapper/notifications/notificationcontroller_linux.cpp
        wrapper/systemmedia/systemmedia_linux.cpp
        wrapper/update/appupdater_linux.cpp
        wrapper/tray/terminalsignals.cpp
        wrapper/tray/terminalsignals.h
    )
elseif(CMP_PLATFORM STREQUAL "windows")
    target_sources(TunedChaos PRIVATE
        wrapper/notifications/notificationcontroller_windows.cpp
        wrapper/systemmedia/systemmedia_windows.cpp
        wrapper/update/appupdater_windows.cpp
        # Icon, and the manifest: UTF-8 as the text encoding (see release/README.md)
        release/windows/TunedChaos.rc
        release/windows/TunedChaos.manifest
    )
    set_target_properties(TunedChaos PROPERTIES WIN32_EXECUTABLE TRUE) # no console window
    target_link_libraries(TunedChaos PRIVATE windowsapp) # C++/WinRT: media controls, toasts
elseif(CMP_PLATFORM STREQUAL "android")
    target_sources(TunedChaos PRIVATE
        wrapper/notifications/notificationcontroller_android.cpp
        wrapper/systemmedia/systemmedia_android.cpp
        wrapper/update/appupdater_android.cpp
        wrapper/opener/fileopener_android.cpp
    )
    # The APK: android/ holds its manifest, Gradle build (with Python and
    # yt-dlp: Chaquopy), Java parts and icon
    set_target_properties(TunedChaos PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR ${CMAKE_SOURCE_DIR}/android
        QT_ANDROID_PACKAGE_NAME io.github.chandandasgit.tunedchaos
        QT_ANDROID_MIN_SDK_VERSION 28    # Android 9 (Qt 6.11's minimum)
        QT_ANDROID_TARGET_SDK_VERSION 35 # Android 15
        QT_ANDROID_COMPILE_SDK_VERSION 36 # (androidx.core 1.17 needs it)
        QT_ANDROID_SDK_BUILD_TOOLS_REVISION 36.0.0
        QT_ANDROID_VERSION_NAME ${PROJECT_VERSION}
        QT_ANDROID_VERSION_CODE 8
    )
endif()

set_source_files_properties(frontend/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)
set_source_files_properties(frontend/Util.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)
set_source_files_properties(frontend/dragdrop/SongDrag.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(TunedChaos
    URI TunedChaos
    VERSION 1.1.5
    # Keep the module's build output out of the way of the executable,
    # which has the same name.
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/TunedChaos
    SOURCES
        wrapper/albumart/albumartprovider.cpp
        wrapper/albumart/albumartprovider.h
        wrapper/albumart/covercontroller.cpp
        wrapper/albumart/covercontroller.h
        wrapper/albumart/coverpalette.cpp
        wrapper/albumart/coverpalette.h
        wrapper/history/historycontroller.cpp
        wrapper/history/historycontroller.h
        wrapper/library/librarycontroller.cpp
        wrapper/library/librarycontroller.h
        wrapper/locallibrary/librarysongsmodel.cpp
        wrapper/locallibrary/librarysongsmodel.h
        wrapper/locallibrary/locallibrarycontroller.cpp
        wrapper/locallibrary/locallibrarycontroller.h
        wrapper/hosted/hostedcontroller.cpp
        wrapper/hosted/hostedcontroller.h
        wrapper/loudness/loudnesscontroller.cpp
        wrapper/loudness/loudnesscontroller.h
        wrapper/lyrics/lyricscontroller.cpp
        wrapper/lyrics/lyricscontroller.h
        wrapper/player/playercontroller.cpp
        wrapper/player/playercontroller.h
        wrapper/files/files.cpp
        wrapper/files/files.h
        wrapper/notifications/notificationcontroller.cpp
        wrapper/notifications/notificationcontroller.h
        wrapper/playlist/playlistcontroller.cpp
        wrapper/playlist/playlistcontroller.h
        wrapper/playlist/playlistmodel.cpp
        wrapper/playlist/playlistmodel.h
        wrapper/moods/moodscontroller.cpp
        wrapper/moods/moodscontroller.h
        wrapper/playlists/playlistscontroller.cpp
        wrapper/playlists/playlistscontroller.h
        wrapper/sleeptimer/sleeptimercontroller.cpp
        wrapper/sleeptimer/sleeptimercontroller.h
        wrapper/smartplaylists/smartplaylistscontroller.cpp
        wrapper/smartplaylists/smartplaylistscontroller.h
        wrapper/settings/settingscontroller.cpp
        wrapper/settings/settingscontroller.h
        wrapper/visualizer/visualizercontroller.cpp
        wrapper/visualizer/visualizercontroller.h
        wrapper/youtube/youtubecontroller.cpp
        wrapper/youtube/youtubecontroller.h
        wrapper/youtube/ytdlpmanager.cpp
        wrapper/youtube/ytdlpmanager.h
        wrapper/youtube/ytmetadatacontroller.cpp
        wrapper/youtube/ytmetadatacontroller.h
    QML_FILES
        Main.qml
        frontend/splash/Splash.qml
        frontend/Theme.qml
        frontend/Util.qml
        frontend/Icon.qml
        frontend/controls/ControlButton.qml
        frontend/controls/FadeLabel.qml
        frontend/controls/ListPopulate.qml
        frontend/controls/PillButton.qml
        frontend/controls/PlayingBars.qml
        frontend/controls/SeekBar.qml
        frontend/controls/SeekThumb.qml
        frontend/controls/TabRow.qml
        frontend/controls/ThemedMenu.qml
        frontend/controls/Toast.qml
        frontend/controls/ThemedSlider.qml
        frontend/controls/TransportControls.qml
        frontend/controls/VolumeSlider.qml
        frontend/detailsdialog/TrackDetailsDialog.qml
        frontend/dialogs/ConfirmDialog.qml
        frontend/dialogs/FolderPicker.qml
        frontend/dialogs/NameDialog.qml
        frontend/dialogs/UpdateDialog.qml
        frontend/dragdrop/DragCard.qml
        frontend/dragdrop/DragSource.qml
        frontend/dragdrop/DropHint.qml
        frontend/dragdrop/SongDrag.qml
        frontend/dropzone/DropOverlay.qml
        frontend/layout/AppShortcuts.qml
        frontend/layout/DockSlot.qml
        frontend/layout/NavBar.qml
        frontend/home/HomePanel.qml
        frontend/home/HomeSongRow.qml
        frontend/home/SmartPlaylistDialog.qml
        frontend/library/LibraryFolderRow.qml
        frontend/library/LibraryPanel.qml
        frontend/library/LibraryAddAllMenu.qml
        frontend/library/LibrarySongMenu.qml
        frontend/hosted/HostedLibraryView.qml
        frontend/hosted/HostedRow.qml
        frontend/library/LetterHeader.qml
        frontend/library/LetterJumpGrid.qml
        frontend/library/LibrarySongRow.qml
        frontend/library/LibrarySourceChooser.qml
        frontend/lyrics/LyricsView.qml
        frontend/nowplaying/AlbumArt.qml
        frontend/nowplaying/MiniPlayer.qml
        frontend/nowplaying/NowPlayingPanel.qml
        frontend/nowplaying/QualityChip.qml
        frontend/nowplaying/Visualizer.qml
        frontend/playlist/PlaylistContextMenu.qml
        frontend/settingsdialog/ReorderList.qml
        frontend/settingsdialog/SettingsPanel.qml
        frontend/settingsdialog/SettingsRow.qml
        frontend/settingsdialog/SettingsSwitch.qml
        frontend/youtube/YouTubePanel.qml
        frontend/youtube/YtArtistView.qml
        frontend/youtube/YtCard.qml
        frontend/youtube/YtCollectionView.qml
        frontend/youtube/YtHomeView.qml
        frontend/youtube/YtLibraryView.qml
        frontend/youtube/YtSavedLinksView.qml
        frontend/youtube/YtSearchView.qml
        frontend/youtube/YtShelf.qml
        frontend/youtube/YtSongMenu.qml
        frontend/youtube/YtStatus.qml
        frontend/youtube/YtThumbnail.qml
        frontend/youtube/YtTrackRow.qml
        frontend/playlist/PlaylistHeader.qml
        frontend/playlist/PlaylistPanel.qml
        frontend/playlist/PlaylistRow.qml
        frontend/playlists/AddToPlaylistMenu.qml
    RESOURCES
        frontend/fonts/fa-solid-900.ttf
        resources/icons/tunedchaos.svg
)

# Wrapper folders are include paths so the generated QML type registration
# can find the headers of QML_ELEMENT classes.
target_include_directories(TunedChaos PRIVATE
    ${CMAKE_SOURCE_DIR}
    wrapper/albumart
    wrapper/files
    wrapper/history
    wrapper/hosted
    wrapper/library
    wrapper/locallibrary
    wrapper/loudness
    wrapper/lyrics
    wrapper/moods
    wrapper/player
    wrapper/playlist
    wrapper/playlists
    wrapper/settings
    wrapper/sleeptimer
    wrapper/smartplaylists
    wrapper/visualizer
    wrapper/youtube
)

target_compile_options(TunedChaos PRIVATE ${CMP_WARNINGS})

# Linux install (Flatpak, distribution packages): the app, its launcher entry,
# icon and metainfo, named by the app id (release/linux).
if(CMP_PLATFORM STREQUAL "linux")
    include(GNUInstallDirs)
    set(CMP_APP_ID io.github.chandandasgit.TunedChaos)
    install(TARGETS TunedChaos RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(FILES release/linux/${CMP_APP_ID}.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES release/linux/${CMP_APP_ID}.metainfo.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
    install(FILES resources/icons/tunedchaos.svg
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps RENAME ${CMP_APP_ID}.svg)
endif()

# yt-dlp updates itself (wrapper/youtube/ytdlpmanager.h). Off for builds whose
# store updates yt-dlp and forbids downloads at runtime (Flathub).
option(CMP_YTDLP_SELF_UPDATE "Let the app download yt-dlp updates" ON)
target_compile_definitions(TunedChaos PRIVATE CMP_YTDLP_SELF_UPDATE=$<BOOL:${CMP_YTDLP_SELF_UPDATE}>)

# Shown in Settings > About (QCoreApplication::applicationVersion).
target_compile_definitions(TunedChaos PRIVATE APP_VERSION="${PROJECT_VERSION}")
if(CMP_PLATFORM STREQUAL "linux" OR CMP_PLATFORM STREQUAL "windows")
    target_compile_definitions(TunedChaos PRIVATE CMP_TRAY)
endif()

target_link_libraries(TunedChaos PRIVATE
    backend
    Qt6::Quick
    Qt6::QuickControls2
    $<$<STREQUAL:${CMP_PLATFORM},linux>:Qt6::DBus>
    $<$<OR:$<STREQUAL:${CMP_PLATFORM},linux>,$<STREQUAL:${CMP_PLATFORM},windows>>:Qt6::Widgets>
    Qt6::Network
    chaoticstyleplugin
)
