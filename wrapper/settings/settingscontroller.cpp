#include "wrapper/settings/settingscontroller.h"

#include "wrapper/files/files.h"
#include "backend/storage/tsv/tsv.h"

#include <QDir>
#include <QUrl>

#include "backend/settings/settings/settings.h"

#include <QJSEngine>

#include <algorithm>
#include <QStandardPaths>

namespace {

constexpr const char *VolumeKey = "volume";
constexpr const char *PinnedKey = "playlistPinned";
constexpr const char *YoutubePinnedKey = "youtube.panelPinned";
constexpr const char *LibraryPinnedKey = "library.panelPinned";
constexpr const char *HomePinnedKey = "home.panelPinned";
constexpr const char *ArtistAlbumWidthKey = "column.artistAlbum.width";
constexpr const char *TrackWidthKey = "column.track.width";
constexpr const char *DurationWidthKey = "column.duration.width";
constexpr const char *SortColumnKey = "sort.column";
constexpr const char *SortDescendingKey = "sort.descending";
constexpr const char *ShuffleKey = "shuffle";
constexpr const char *RepeatModeKey = "repeat";
constexpr const char *VolumeStepKey = "volume.step";
constexpr const char *RestorePlaylistKey = "playlist.restoreOnStartup";
constexpr const char *BackgroundPlaybackKey = "playback.background";
constexpr const char *HistoryEnabledKey = "history.enabled";
constexpr const char *ReplayGainKey = "playback.replayGain";
constexpr const char *NotificationsKey = "general.notifications";
constexpr const char *HistoryYouTubeKey = "history.youtube";
constexpr const char *ThemeModeKey = "appearance.theme";
constexpr const char *CoverSizeKey = "appearance.coverSize";
constexpr const char *SeekbarStyleKey = "appearance.seekbar";
constexpr const char *SeekbarThumbKey = "appearance.seekbarThumb";
constexpr const char *FidgetStyleKey = "appearance.fidgetStyle";
constexpr const char *FidgetThumbKey = "appearance.fidgetThumb";
constexpr const char *PanelOrderKey = "layout.panels";
constexpr const char *NavDividersKey = "layout.dividers";
constexpr const char *HiddenPanelsKey = "layout.hidden";
constexpr const char *StartPanelKey = "layout.start";
constexpr const char *DefaultPanelKey = "layout.default";
constexpr const char *LibrarySortKey = "library.sort";
constexpr const char *AlbumSortKey = "library.sort.albums";
constexpr const char *ArtistSortKey = "library.sort.artists";
constexpr const char *GenreSortKey = "library.sort.genres";
constexpr const char *FolderSortKey = "library.sort.folders";
constexpr const char *ResumeKey = "playback.resume";
constexpr const char *SessionPathKey = "session.path";
constexpr const char *SessionPositionKey = "session.positionMs";
constexpr const char *SessionDurationKey = "session.durationMs";
constexpr const char *SessionListKey = "session.list";
constexpr const char *OldDarkModeKey = "appearance.dark"; // before "Follow system": a dark / light switch
constexpr const char *OutputDeviceKey = "audio.outputDevice";
constexpr const char *ShowRemainingKey = "seekbar.showRemaining";
constexpr const char *FadeKey = "playback.crossfadeSeconds"; // (its name from before fades replaced crossfades)
constexpr int MaxFadeSeconds = 12;
constexpr const char *LyricsSourcesKey = "lyrics.sources";
constexpr const char *LyricsSyncedKey = "lyrics.syncedByDefault";
constexpr const char *LyricsLatinKey = "lyrics.latinScript";
constexpr const char *YtLookupKey = "youtube.backgroundLookup";
constexpr const char *YtAutoplayKey = "youtube.autoplay";
constexpr const char *AppUpdateCheckKey = "updates.check";
constexpr const char *AppUpdateSkippedKey = "updates.skippedVersion";
constexpr const char *YtQueueMixKey = "youtube.queueMix";
constexpr const char *ListsToQueueKey = "playback.listsToQueue";
constexpr const char *YtSearchHistoryKey = "youtube.searchHistory";
constexpr const char *YtQualityKey = "youtube.quality";
constexpr const char *EqEnabledKey = "eq.enabled";
constexpr const char *EqGainsKey = "eq.gains"; // "0,0,3,..." dB, 31 Hz first
constexpr const char *EqPresetKey = "eq.preset";
constexpr int EqBands = 10;
constexpr qreal EqMaxDb = 12;
constexpr int MaxYtSearchHistory = 50;
constexpr const char *YtCookiesKey = "youtube.cookiesBrowser";
constexpr const char *TintStrengthKey = "appearance.tintStrength";
constexpr const char *InterfaceScaleKey = "appearance.interfaceScale";
constexpr const char *CoversOnlineKey = "covers.online";
constexpr const char *CoversDisabledKey = "covers.disabledSources"; // comma-separated ids
const QList<QPair<QString, QString>> CoverSourceNames = {
    {QStringLiteral("folder"), QStringLiteral("Images in the song's folder (cover.jpg …)")},
    {QStringLiteral("itunes"), QStringLiteral("iTunes (Apple)")},
    {QStringLiteral("musicbrainz"), QStringLiteral("MusicBrainz (Cover Art Archive)")},
    {QStringLiteral("ytmusic"), QStringLiteral("YouTube Music")},
};
constexpr const char *LibraryFoldersKey = "library.folders";   // tab-separated, tsv-escaped
constexpr const char *LibraryExcludedKey = "library.excluded";

// "file:///home/me/Music/" or "/home/me/Music/" -> "/home/me/Music"
QString cleanFolder(const QString &folder)
{
    QString path = folder.startsWith(QStringLiteral("file:")) ? QUrl(folder).toLocalFile() : folder;
    path = QDir::cleanPath(path);
    return path;
}
constexpr const char *VisualizerKey = "appearance.visualizer";
constexpr const char *VisualizerStyleKey = "appearance.visualizerStyle";
constexpr int VisualizerStyleCount = 3;

// id -> display name, in the default order
const QList<QPair<QString, QString>> LyricsSourceNames = {
    {QStringLiteral("local"), QStringLiteral("Local files (.lrc / tags)")},
    {QStringLiteral("lrclib"), QStringLiteral("LRCLIB (online)")},
    {QStringLiteral("ytmusic"), QStringLiteral("YouTube Music")},
};

std::string settingsFile()
{
    return (Files::configDir()
            + QStringLiteral("/settings.conf")).toStdString();
}

qreal clampScale(qreal scale)
{
    return qBound(0.75, scale, 2.0);
}

} // namespace

SettingsController::SettingsController(QObject *parent)
    : QObject(parent)
{
    Q_ASSERT(!s_instance);
    s_instance = this;

    m_settings = std::make_unique<Settings>(settingsFile());
    m_settings->load();

    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(500);
    connect(&m_saveTimer, &QTimer::timeout, this, [this] { m_settings->save(); });
}

SettingsController::~SettingsController()
{
    m_settings->save();
    s_instance = nullptr;
}

SettingsController *SettingsController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

qreal SettingsController::volume() const
{
    return qBound(0.0, m_settings->doubleValue(VolumeKey, 0.8), 1.0);
}

void SettingsController::setVolume(qreal volume)
{
    if (qFuzzyCompare(volume, this->volume()))
        return;
    m_settings->setDouble(VolumeKey, volume);
    scheduleSave();
    emit volumeChanged();
}

bool SettingsController::playlistPinned() const
{
    return m_settings->boolValue(PinnedKey, true); // docked by default on big windows
}

void SettingsController::setPlaylistPinned(bool pinned)
{
    if (pinned == playlistPinned())
        return;
    m_settings->setBool(PinnedKey, pinned);
    scheduleSave();
    emit playlistPinnedChanged();
}

bool SettingsController::youtubePanelPinned() const
{
    return m_settings->boolValue(YoutubePinnedKey, false);
}

void SettingsController::setYoutubePanelPinned(bool pinned)
{
    if (pinned == youtubePanelPinned())
        return;
    m_settings->setBool(YoutubePinnedKey, pinned);
    scheduleSave();
    emit youtubePanelPinnedChanged();
    if (pinned) {
        setLibraryPanelPinned(false);
        setHomePanelPinned(false);
    }
}

bool SettingsController::libraryPanelPinned() const
{
    return m_settings->boolValue(LibraryPinnedKey, false);
}

void SettingsController::setLibraryPanelPinned(bool pinned)
{
    if (pinned == libraryPanelPinned())
        return;
    m_settings->setBool(LibraryPinnedKey, pinned);
    scheduleSave();
    emit libraryPanelPinnedChanged();
    if (pinned) {
        setYoutubePanelPinned(false);
        setHomePanelPinned(false);
    }
}

bool SettingsController::homePanelPinned() const
{
    return m_settings->boolValue(HomePinnedKey, false);
}

void SettingsController::setHomePanelPinned(bool pinned)
{
    if (pinned == homePanelPinned())
        return;
    m_settings->setBool(HomePinnedKey, pinned);
    scheduleSave();
    emit homePanelPinnedChanged();
    if (pinned) {
        setYoutubePanelPinned(false);
        setLibraryPanelPinned(false);
    }
}

int SettingsController::artistAlbumWidth() const
{
    return m_settings->intValue(ArtistAlbumWidthKey, 220);
}

void SettingsController::setArtistAlbumWidth(int width)
{
    setWidth(ArtistAlbumWidthKey, width, 60, 800);
}

int SettingsController::trackWidth() const
{
    return m_settings->intValue(TrackWidthKey, 52);
}

void SettingsController::setTrackWidth(int width)
{
    setWidth(TrackWidthKey, width, 36, 160);
}

int SettingsController::durationWidth() const
{
    return m_settings->intValue(DurationWidthKey, 60);
}

void SettingsController::setDurationWidth(int width)
{
    setWidth(DurationWidthKey, width, 44, 160);
}

int SettingsController::sortColumn() const
{
    return m_settings->intValue(SortColumnKey, 2); // Playlist::SortColumn::Track
}

bool SettingsController::sortDescending() const
{
    return m_settings->boolValue(SortDescendingKey, false);
}

void SettingsController::setSort(int column, bool descending)
{
    m_settings->setInt(SortColumnKey, column);
    m_settings->setBool(SortDescendingKey, descending);
    scheduleSave();
}

bool SettingsController::restorePlaylist() const
{
    return m_settings->boolValue(RestorePlaylistKey, true);
}

void SettingsController::setRestorePlaylist(bool restore)
{
    if (restore == restorePlaylist())
        return;
    m_settings->setBool(RestorePlaylistKey, restore);
    scheduleSave();
    emit restorePlaylistChanged();
}

bool SettingsController::backgroundPlayback() const
{
    return m_settings->boolValue(BackgroundPlaybackKey, false);
}

void SettingsController::setBackgroundPlayback(bool enabled)
{
    if (enabled == backgroundPlayback())
        return;
    m_settings->setBool(BackgroundPlaybackKey, enabled);
    scheduleSave();
    emit backgroundPlaybackChanged();
}

bool SettingsController::notificationsEnabled() const
{
    return m_settings->boolValue(NotificationsKey, true);
}

void SettingsController::setNotificationsEnabled(bool enabled)
{
    if (enabled == notificationsEnabled())
        return;
    m_settings->setBool(NotificationsKey, enabled);
    scheduleSave();
    emit notificationsEnabledChanged();
}

int SettingsController::replayGain() const
{
    return qBound(0, m_settings->intValue(ReplayGainKey, 0), 2);
}

void SettingsController::setReplayGain(int mode)
{
    mode = qBound(0, mode, 2);
    if (mode == replayGain())
        return;
    m_settings->setInt(ReplayGainKey, mode);
    scheduleSave();
    emit replayGainChanged();
}

bool SettingsController::historyEnabled() const
{
    return m_settings->boolValue(HistoryEnabledKey, true);
}

void SettingsController::setHistoryEnabled(bool enabled)
{
    if (enabled == historyEnabled())
        return;
    m_settings->setBool(HistoryEnabledKey, enabled);
    scheduleSave();
    emit historyChanged();
}

bool SettingsController::historyYouTube() const
{
    return m_settings->boolValue(HistoryYouTubeKey, true);
}

void SettingsController::setHistoryYouTube(bool enabled)
{
    if (enabled == historyYouTube())
        return;
    m_settings->setBool(HistoryYouTubeKey, enabled);
    scheduleSave();
    emit historyChanged();
}

bool SettingsController::resumeSession() const
{
    return m_settings->boolValue(ResumeKey, true);
}

void SettingsController::setResumeSession(bool resume)
{
    if (resume == resumeSession())
        return;
    m_settings->setBool(ResumeKey, resume);
    scheduleSave();
    emit resumeSessionChanged();
}

QString SettingsController::sessionPath() const
{
    return QString::fromStdString(m_settings->value(SessionPathKey));
}

qint64 SettingsController::sessionPosition() const
{
    return QString::fromStdString(m_settings->value(SessionPositionKey)).toLongLong();
}

qint64 SettingsController::sessionDuration() const
{
    return QString::fromStdString(m_settings->value(SessionDurationKey)).toLongLong();
}

QString SettingsController::sessionList() const
{
    return QString::fromStdString(m_settings->value(SessionListKey));
}

void SettingsController::setSession(const QString &path, qint64 positionMs, qint64 durationMs, const QString &list)
{
    const std::string position = std::to_string(positionMs);
    if (path == sessionPath() && m_settings->value(SessionPositionKey) == position && list == sessionList())
        return;
    m_settings->setValue(SessionPathKey, path.toStdString());
    m_settings->setValue(SessionPositionKey, position);
    m_settings->setValue(SessionDurationKey, std::to_string(durationMs));
    m_settings->setValue(SessionListKey, list.toStdString());
    scheduleSave();
}

int SettingsController::coverSize() const
{
    return qBound(60, m_settings->intValue(CoverSizeKey, 60), 100);
}

void SettingsController::setCoverSize(int size)
{
    size = qBound(60, size, 100);
    if (size == coverSize())
        return;
    m_settings->setValue(CoverSizeKey, std::to_string(size));
    scheduleSave();
    emit coverSizeChanged();
}

QString SettingsController::seekbarStyle() const
{
    return m_settings->value(SeekbarStyleKey) == "dot" ? QStringLiteral("dot") : QStringLiteral("wave");
}

void SettingsController::setSeekbarStyle(const QString &style)
{
    if (style == seekbarStyle() || (style != QLatin1String("wave") && style != QLatin1String("dot")))
        return;
    m_settings->setValue(SeekbarStyleKey, style.toStdString());
    scheduleSave();
    emit seekbarStyleChanged();
}

namespace {

QStringList seekbarThumbs()
{
    return {QStringLiteral("circle"), QStringLiteral("ring"), QStringLiteral("pill"), QStringLiteral("diamond"),
            QStringLiteral("heart"),  QStringLiteral("star"), QStringLiteral("note"), QStringLiteral("disc"),
            QStringLiteral("play"),   QStringLiteral("arrow")};
}

} // namespace

QString SettingsController::fidgetStyle() const
{
    return m_settings->value(FidgetStyleKey) == "wave" ? QStringLiteral("wave") : QStringLiteral("dot");
}

void SettingsController::setFidgetStyle(const QString &style)
{
    if (style == fidgetStyle() || (style != QLatin1String("wave") && style != QLatin1String("dot")))
        return;
    m_settings->setValue(FidgetStyleKey, style.toStdString());
    scheduleSave();
    emit seekbarStyleChanged();
}

QString SettingsController::fidgetThumb() const
{
    const QString thumb = QString::fromStdString(m_settings->value(FidgetThumbKey));
    return seekbarThumbs().contains(thumb) ? thumb : QStringLiteral("circle");
}

void SettingsController::setFidgetThumb(const QString &thumb)
{
    if (thumb == fidgetThumb() || !seekbarThumbs().contains(thumb))
        return;
    m_settings->setValue(FidgetThumbKey, thumb.toStdString());
    scheduleSave();
    emit seekbarThumbChanged();
}

QString SettingsController::seekbarThumb() const
{
    const QString thumb = QString::fromStdString(m_settings->value(SeekbarThumbKey));
    return seekbarThumbs().contains(thumb) ? thumb : QStringLiteral("circle");
}

void SettingsController::setSeekbarThumb(const QString &thumb)
{
    if (thumb == seekbarThumb() || !seekbarThumbs().contains(thumb))
        return;
    m_settings->setValue(SeekbarThumbKey, thumb.toStdString());
    scheduleSave();
    emit seekbarThumbChanged();
}

QString SettingsController::themeMode() const
{
    const QString mode = QString::fromStdString(m_settings->value(ThemeModeKey));
    if (mode == QLatin1String("system") || mode == QLatin1String("dark") || mode == QLatin1String("light"))
        return mode;
    return m_settings->boolValue(OldDarkModeKey, true) ? QStringLiteral("dark") : QStringLiteral("light");
}

void SettingsController::setThemeMode(const QString &mode)
{
    if (mode == themeMode() || (mode != QLatin1String("system") && mode != QLatin1String("dark")
                                && mode != QLatin1String("light")))
        return;
    m_settings->setValue(ThemeModeKey, mode.toStdString());
    scheduleSave();
    emit themeModeChanged();
}

namespace {

QStringList defaultPanels()
{
    return {QStringLiteral("youtube"), QStringLiteral("queue"), QStringLiteral("home"), QStringLiteral("library")};
}

} // namespace

bool SettingsController::navDividers() const
{
    return m_settings->boolValue(NavDividersKey, true);
}

void SettingsController::setNavDividers(bool on)
{
    if (on == navDividers())
        return;
    m_settings->setBool(NavDividersKey, on);
    scheduleSave();
    emit navDividersChanged();
}

QStringList SettingsController::panelOrder() const
{
    const QStringList all = defaultPanels();
    QStringList order;
    for (const QString &panel : pathList(PanelOrderKey)) {
        if (all.contains(panel) && !order.contains(panel))
            order << panel;
    }
    for (const QString &panel : all) {
        if (!order.contains(panel))
            order << panel;
    }
    return order;
}

QStringList SettingsController::hiddenPanels() const
{
    return pathList(HiddenPanelsKey);
}

void SettingsController::movePanel(int index, int delta)
{
    QStringList order = panelOrder();
    const int target = index + delta;
    if (index < 0 || index >= order.size() || target < 0 || target >= order.size())
        return;
    order.move(index, target);
    setPathList(PanelOrderKey, order);
    scheduleSave();
    emit panelsChanged();
}

void SettingsController::setPanelHidden(const QString &panel, bool hidden)
{
    QStringList list = hiddenPanels();
    if (!defaultPanels().contains(panel) || list.contains(panel) == hidden)
        return;
    if (hidden)
        list << panel;
    else
        list.removeAll(panel);
    setPathList(HiddenPanelsKey, list);
    scheduleSave();
    emit panelsChanged();
}

QString SettingsController::startPanel() const
{
    const QString panel = QString::fromStdString(m_settings->value(StartPanelKey));
    return defaultPanels().contains(panel) ? panel : QStringLiteral("player");
}

void SettingsController::setStartPanel(const QString &panel)
{
    if (panel == startPanel() || (panel != QLatin1String("player") && !defaultPanels().contains(panel)))
        return;
    m_settings->setValue(StartPanelKey, panel.toStdString());
    scheduleSave();
    emit startPanelChanged();
}

namespace {

// What can take the player's place (any panel of the bottom bar but Settings).
bool isBasePanel(const QString &panel)
{
    return panel == QLatin1String("player") || defaultPanels().contains(panel);
}

} // namespace

QString SettingsController::defaultPanel() const
{
    const QString panel = QString::fromStdString(m_settings->value(DefaultPanelKey));
    return isBasePanel(panel) ? panel : QStringLiteral("player");
}

void SettingsController::setDefaultPanel(const QString &panel)
{
    if (panel == defaultPanel() || !isBasePanel(panel))
        return;
    m_settings->setValue(DefaultPanelKey, panel.toStdString());
    scheduleSave();
    emit defaultPanelChanged();
}

namespace {

QStringList librarySorts()
{
    return {QStringLiteral("title"),  QStringLiteral("titleDesc"),   QStringLiteral("newest"),
            QStringLiteral("oldest"), QStringLiteral("modifiedNew"), QStringLiteral("modifiedOld"),
            QStringLiteral("artist"), QStringLiteral("album")};
}

QStringList albumSorts()
{
    return {QStringLiteral("name"),   QStringLiteral("nameDesc"),    QStringLiteral("newest"),
            QStringLiteral("oldest"), QStringLiteral("modifiedNew"), QStringLiteral("modifiedOld"),
            QStringLiteral("artist"), QStringLiteral("mostSongs")};
}

QStringList artistSorts()
{
    return {QStringLiteral("name"), QStringLiteral("nameDesc"), QStringLiteral("mostSongs"),
            QStringLiteral("fewestSongs")};
}

QStringList folderSorts()
{
    return artistSorts() + QStringList{QStringLiteral("modifiedNew"), QStringLiteral("modifiedOld")};
}

} // namespace

QString SettingsController::sortValue(const char *key, const QStringList &allowed) const
{
    const QString sort = QString::fromStdString(m_settings->value(key));
    return allowed.contains(sort) ? sort : allowed.first();
}

void SettingsController::setSortValue(const char *key, const QStringList &allowed, const QString &sort)
{
    if (sort == sortValue(key, allowed) || !allowed.contains(sort))
        return;
    m_settings->setValue(key, sort.toStdString());
    scheduleSave();
    emit librarySortChanged();
}

QString SettingsController::librarySort() const { return sortValue(LibrarySortKey, librarySorts()); }
void SettingsController::setLibrarySort(const QString &sort) { setSortValue(LibrarySortKey, librarySorts(), sort); }
QString SettingsController::albumSort() const { return sortValue(AlbumSortKey, albumSorts()); }
void SettingsController::setAlbumSort(const QString &sort) { setSortValue(AlbumSortKey, albumSorts(), sort); }
QString SettingsController::artistSort() const { return sortValue(ArtistSortKey, artistSorts()); }
void SettingsController::setArtistSort(const QString &sort) { setSortValue(ArtistSortKey, artistSorts(), sort); }
QString SettingsController::genreSort() const { return sortValue(GenreSortKey, artistSorts()); }
void SettingsController::setGenreSort(const QString &sort) { setSortValue(GenreSortKey, artistSorts(), sort); }
QString SettingsController::folderSort() const { return sortValue(FolderSortKey, folderSorts()); }
void SettingsController::setFolderSort(const QString &sort) { setSortValue(FolderSortKey, folderSorts(), sort); }

QString SettingsController::outputDevice() const
{
    return QString::fromStdString(m_settings->value(OutputDeviceKey));
}

void SettingsController::setOutputDevice(const QString &deviceId)
{
    if (deviceId == outputDevice())
        return;
    m_settings->setValue(OutputDeviceKey, deviceId.toStdString());
    scheduleSave();
}

int SettingsController::volumeStep() const
{
    return qBound(1, m_settings->intValue(VolumeStepKey, 5), 25);
}

void SettingsController::setVolumeStep(int step)
{
    step = qBound(1, step, 25);
    if (step == volumeStep())
        return;
    m_settings->setInt(VolumeStepKey, step);
    scheduleSave();
    emit volumeStepChanged();
}

bool SettingsController::showRemainingTime() const
{
    return m_settings->boolValue(ShowRemainingKey, true);
}

void SettingsController::setShowRemainingTime(bool show)
{
    if (show == showRemainingTime())
        return;
    m_settings->setBool(ShowRemainingKey, show);
    scheduleSave();
    emit showRemainingTimeChanged();
}

// Stored as "local:1,lrclib:1,ytmusic:0"; unknown ids are dropped and
// missing ones appended (enabled), so new sources show up after updates.
QList<SettingsController::LyricsSource> SettingsController::lyricsSourceList() const
{
    QList<LyricsSource> list;
    const QString stored = QString::fromStdString(m_settings->value(LyricsSourcesKey));
    for (const QString &entry : stored.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        const QString id = entry.section(QLatin1Char(':'), 0, 0);
        const bool known = std::any_of(LyricsSourceNames.begin(), LyricsSourceNames.end(),
                                       [&](const auto &pair) { return pair.first == id; });
        const bool duplicate = std::any_of(list.begin(), list.end(),
                                           [&](const LyricsSource &s) { return s.id == id; });
        if (known && !duplicate)
            list.append({id, entry.section(QLatin1Char(':'), 1, 1) != QLatin1String("0")});
    }
    for (const auto &[id, name] : LyricsSourceNames) {
        if (std::none_of(list.begin(), list.end(), [&](const LyricsSource &s) { return s.id == id; }))
            list.append({id, true});
    }
    return list;
}

void SettingsController::storeLyricsSources(const QList<LyricsSource> &sources)
{
    QStringList parts;
    for (const LyricsSource &source : sources)
        parts << source.id + (source.enabled ? QStringLiteral(":1") : QStringLiteral(":0"));
    m_settings->setValue(LyricsSourcesKey, parts.join(QLatin1Char(',')).toStdString());
    scheduleSave();
    emit lyricsSourcesChanged();
}

QVariantList SettingsController::lyricsSources() const
{
    QVariantList result;
    for (const LyricsSource &source : lyricsSourceList()) {
        QString name;
        for (const auto &[id, displayName] : LyricsSourceNames) {
            if (id == source.id)
                name = displayName;
        }
        result.append(QVariantMap{
            {QStringLiteral("id"), source.id},
            {QStringLiteral("name"), name},
            {QStringLiteral("enabled"), source.enabled},
        });
    }
    return result;
}

QStringList SettingsController::enabledLyricsSourceIds() const
{
    QStringList ids;
    for (const LyricsSource &source : lyricsSourceList()) {
        if (source.enabled)
            ids << source.id;
    }
    return ids;
}

void SettingsController::moveLyricsSource(int index, int delta)
{
    QList<LyricsSource> sources = lyricsSourceList();
    const int target = index + delta;
    if (index < 0 || index >= sources.size() || target < 0 || target >= sources.size())
        return;
    sources.move(index, target);
    storeLyricsSources(sources);
}

void SettingsController::setLyricsSourceEnabled(int index, bool enabled)
{
    QList<LyricsSource> sources = lyricsSourceList();
    if (index < 0 || index >= sources.size() || sources[index].enabled == enabled)
        return;
    sources[index].enabled = enabled;
    storeLyricsSources(sources);
}

bool SettingsController::lyricsSyncedByDefault() const
{
    return m_settings->boolValue(LyricsSyncedKey, true);
}

void SettingsController::setLyricsSyncedByDefault(bool synced)
{
    if (synced == lyricsSyncedByDefault())
        return;
    m_settings->setBool(LyricsSyncedKey, synced);
    scheduleSave();
    emit lyricsSyncedByDefaultChanged();
}

int SettingsController::fadeSeconds() const
{
    return qBound(0, m_settings->intValue(FadeKey, 4), MaxFadeSeconds);
}

void SettingsController::setFadeSeconds(int seconds)
{
    seconds = qBound(0, seconds, MaxFadeSeconds);
    if (seconds == fadeSeconds())
        return;
    m_settings->setInt(FadeKey, seconds);
    scheduleSave();
    emit fadeSecondsChanged();
}

bool SettingsController::lyricsLatinScript() const
{
    return m_settings->boolValue(LyricsLatinKey, false);
}

void SettingsController::setLyricsLatinScript(bool latin)
{
    if (latin == lyricsLatinScript())
        return;
    m_settings->setBool(LyricsLatinKey, latin);
    scheduleSave();
    emit lyricsLatinScriptChanged();
}

bool SettingsController::ytBackgroundLookup() const
{
    return m_settings->boolValue(YtLookupKey, true);
}

void SettingsController::setYtBackgroundLookup(bool enabled)
{
    if (enabled == ytBackgroundLookup())
        return;
    m_settings->setBool(YtLookupKey, enabled);
    scheduleSave();
    emit ytBackgroundLookupChanged();
}

bool SettingsController::ytAutoplay() const
{
    return m_settings->boolValue(YtAutoplayKey, true);
}

void SettingsController::setYtAutoplay(bool enabled)
{
    if (enabled == ytAutoplay())
        return;
    m_settings->setBool(YtAutoplayKey, enabled);
    scheduleSave();
    emit ytAutoplayChanged();
}

bool SettingsController::appUpdateCheck() const
{
    return m_settings->boolValue(AppUpdateCheckKey, true);
}

void SettingsController::setAppUpdateCheck(bool enabled)
{
    if (enabled == appUpdateCheck())
        return;
    m_settings->setBool(AppUpdateCheckKey, enabled);
    scheduleSave();
    emit appUpdateCheckChanged();
}

QString SettingsController::appUpdateSkipped() const
{
    return QString::fromStdString(m_settings->value(AppUpdateSkippedKey));
}

void SettingsController::setAppUpdateSkipped(const QString &version)
{
    if (version == appUpdateSkipped())
        return;
    m_settings->setValue(AppUpdateSkippedKey, version.toStdString());
    scheduleSave();
    emit appUpdateSkippedChanged();
}

bool SettingsController::ytQueueMix() const
{
    return m_settings->boolValue(YtQueueMixKey, true);
}

void SettingsController::setYtQueueMix(bool enabled)
{
    if (enabled == ytQueueMix())
        return;
    m_settings->setBool(YtQueueMixKey, enabled);
    scheduleSave();
    emit ytQueueMixChanged();
}

bool SettingsController::listsToQueue() const
{
    return m_settings->boolValue(ListsToQueueKey, false);
}

void SettingsController::setListsToQueue(bool enabled)
{
    if (enabled == listsToQueue())
        return;
    m_settings->setBool(ListsToQueueKey, enabled);
    scheduleSave();
    emit listsToQueueChanged();
}

bool SettingsController::eqEnabled() const
{
    return m_settings->boolValue(EqEnabledKey, false);
}

void SettingsController::setEqEnabled(bool enabled)
{
    if (enabled == eqEnabled())
        return;
    m_settings->setBool(EqEnabledKey, enabled);
    scheduleSave();
    emit eqChanged();
}

QList<qreal> SettingsController::eqGains() const
{
    QList<qreal> gains(EqBands, 0);
    const QStringList saved = QString::fromStdString(m_settings->value(EqGainsKey)).split(QLatin1Char(','));
    for (int i = 0; i < EqBands && i < saved.size(); ++i)
        gains[i] = qBound(-EqMaxDb, saved[i].toDouble(), EqMaxDb);
    return gains;
}

QString SettingsController::eqPreset() const
{
    const QString preset = QString::fromStdString(m_settings->value(EqPresetKey));
    return preset.isEmpty() ? QStringLiteral("flat") : preset;
}

void SettingsController::setEqGain(int band, qreal db)
{
    if (band < 0 || band >= EqBands)
        return;
    QList<qreal> gains = eqGains();
    gains[band] = qBound(-EqMaxDb, db, EqMaxDb);
    setEqPreset(QStringLiteral("custom"), gains);
}

void SettingsController::setEqPreset(const QString &preset, const QList<qreal> &gains)
{
    QStringList values;
    for (int i = 0; i < EqBands; ++i)
        values << QString::number(i < gains.size() ? qBound(-EqMaxDb, gains[i], EqMaxDb) : 0.0);
    const std::string joined = values.join(QLatin1Char(',')).toStdString();
    if (joined == m_settings->value(EqGainsKey) && preset == eqPreset())
        return;
    m_settings->setValue(EqGainsKey, joined);
    m_settings->setValue(EqPresetKey, preset.toStdString());
    scheduleSave();
    emit eqChanged();
}

SettingsController::YtQuality SettingsController::ytQuality() const
{
    return YtQuality(qBound(int(YtAuto), m_settings->intValue(YtQualityKey, YtAuto), int(YtLowest)));
}

void SettingsController::setYtQuality(YtQuality quality)
{
    if (quality == ytQuality())
        return;
    m_settings->setInt(YtQualityKey, int(quality));
    scheduleSave();
    emit ytQualityChanged();
}

QStringList SettingsController::ytSearchHistory() const
{
    return pathList(YtSearchHistoryKey);
}

void SettingsController::rememberYtSearch(const QString &query)
{
    const QString q = query.simplified();
    if (q.isEmpty())
        return;
    QStringList history = ytSearchHistory();
    if (!history.isEmpty() && history.first() == q)
        return;
    history.removeIf([&](const QString &old) { return old.compare(q, Qt::CaseInsensitive) == 0; });
    history.prepend(q);
    while (history.size() > MaxYtSearchHistory)
        history.removeLast();
    setPathList(YtSearchHistoryKey, history);
    emit ytSearchHistoryChanged();
}

void SettingsController::forgetYtSearch(const QString &query)
{
    QStringList history = ytSearchHistory();
    if (history.removeAll(query) == 0)
        return;
    setPathList(YtSearchHistoryKey, history);
    emit ytSearchHistoryChanged();
}

void SettingsController::clearYtSearchHistory()
{
    if (ytSearchHistory().isEmpty())
        return;
    setPathList(YtSearchHistoryKey, {});
    emit ytSearchHistoryChanged();
}

QString SettingsController::ytCookiesBrowser() const
{
    return QString::fromStdString(m_settings->value(YtCookiesKey));
}

void SettingsController::setYtCookiesBrowser(const QString &browser)
{
    if (browser == ytCookiesBrowser())
        return;
    m_settings->setValue(YtCookiesKey, browser.toStdString());
    scheduleSave();
    emit ytCookiesBrowserChanged();
}

qreal SettingsController::coverTintStrength() const
{
    return qBound(0.0, m_settings->doubleValue(TintStrengthKey, 1.0), 1.0);
}

void SettingsController::setCoverTintStrength(qreal strength)
{
    strength = qBound(0.0, strength, 1.0);
    if (qFuzzyCompare(strength + 1, coverTintStrength() + 1))
        return;
    m_settings->setDouble(TintStrengthKey, strength);
    scheduleSave();
    emit coverTintStrengthChanged();
}

qreal SettingsController::interfaceScale() const
{
    return clampScale(m_settings->doubleValue(InterfaceScaleKey, 1.0));
}

void SettingsController::setInterfaceScale(qreal scale)
{
    scale = clampScale(scale);
    if (qFuzzyCompare(scale, interfaceScale()))
        return;
    m_settings->setDouble(InterfaceScaleKey, scale);
    scheduleSave();
    emit interfaceScaleChanged();
}

qreal SettingsController::storedInterfaceScale()
{
    Settings settings(settingsFile());
    settings.load();
    return clampScale(settings.doubleValue(InterfaceScaleKey, 1.0));
}

void SettingsController::flush()
{
    m_saveTimer.stop();
    m_settings->save();
}

bool SettingsController::coversOnline() const
{
    return m_settings->boolValue(CoversOnlineKey, true);
}

void SettingsController::setCoversOnline(bool online)
{
    if (online == coversOnline())
        return;
    m_settings->setBool(CoversOnlineKey, online);
    scheduleSave();
    emit coversOnlineChanged();
}

QVariantList SettingsController::coverSources() const
{
    const QStringList disabled = QString::fromStdString(m_settings->value(CoversDisabledKey)).split(QLatin1Char(','));
    QVariantList result;
    for (const auto &[id, name] : CoverSourceNames)
        result.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name},
                                  {QStringLiteral("enabled"), !disabled.contains(id)}});
    return result;
}

void SettingsController::setCoverSourceEnabled(const QString &id, bool enabled)
{
    QStringList disabled = QString::fromStdString(m_settings->value(CoversDisabledKey)).split(QLatin1Char(','), Qt::SkipEmptyParts);
    if (enabled == !disabled.contains(id))
        return;
    if (enabled)
        disabled.removeAll(id);
    else
        disabled << id;
    m_settings->setValue(CoversDisabledKey, disabled.join(QLatin1Char(',')).toStdString());
    scheduleSave();
    emit coverSourcesChanged();
}

QStringList SettingsController::enabledCoverSourceIds() const
{
    QStringList ids;
    for (const QVariant &source : coverSources()) {
        const QVariantMap map = source.toMap();
        if (map.value(QStringLiteral("enabled")).toBool())
            ids << map.value(QStringLiteral("id")).toString();
    }
    return ids;
}

QStringList SettingsController::pathList(const char *key) const
{
    QStringList paths;
    for (const std::string &field : tsv::split(m_settings->value(key))) {
        if (!field.empty())
            paths << QString::fromStdString(tsv::unescape(field));
    }
    return paths;
}

void SettingsController::setPathList(const char *key, const QStringList &paths)
{
    std::string joined;
    for (const QString &path : paths) {
        if (!joined.empty())
            joined += '\t';
        joined += tsv::escape(path.toStdString());
    }
    m_settings->setValue(key, joined);
    scheduleSave();
}

QStringList SettingsController::libraryFolders() const
{
    return pathList(LibraryFoldersKey);
}

QStringList SettingsController::libraryExcluded() const
{
    return pathList(LibraryExcludedKey);
}

bool SettingsController::addLibraryFolder(const QString &folder)
{
    const QString path = cleanFolder(folder);
    QStringList folders = libraryFolders();
    if (path.isEmpty() || folders.contains(path))
        return false;
    folders << path;
    setPathList(LibraryFoldersKey, folders);
    emit libraryFoldersChanged();
    return true;
}

void SettingsController::removeLibraryFolder(const QString &folder)
{
    QStringList folders = libraryFolders();
    if (folders.removeAll(cleanFolder(folder)) == 0)
        return;
    setPathList(LibraryFoldersKey, folders);
    emit libraryFoldersChanged();
}

bool SettingsController::addLibraryExcluded(const QString &folder)
{
    const QString path = cleanFolder(folder);
    QStringList excluded = libraryExcluded();
    if (path.isEmpty() || excluded.contains(path))
        return false;
    excluded << path;
    setPathList(LibraryExcludedKey, excluded);
    emit libraryExcludedChanged();
    return true;
}

void SettingsController::removeLibraryExcluded(const QString &folder)
{
    QStringList excluded = libraryExcluded();
    if (excluded.removeAll(cleanFolder(folder)) == 0)
        return;
    setPathList(LibraryExcludedKey, excluded);
    emit libraryExcludedChanged();
}

bool SettingsController::visualizerEnabled() const
{
    return m_settings->boolValue(VisualizerKey, true);
}

void SettingsController::setVisualizerEnabled(bool enabled)
{
    if (enabled == visualizerEnabled())
        return;
    m_settings->setBool(VisualizerKey, enabled);
    scheduleSave();
    emit visualizerEnabledChanged();
}

int SettingsController::visualizerStyle() const
{
    return qBound(0, m_settings->intValue(VisualizerStyleKey, 0), VisualizerStyleCount - 1);
}

void SettingsController::setVisualizerStyle(int style)
{
    style = qBound(0, style, VisualizerStyleCount - 1);
    if (style == visualizerStyle())
        return;
    m_settings->setInt(VisualizerStyleKey, style);
    scheduleSave();
    emit visualizerStyleChanged();
}

bool SettingsController::shuffle() const
{
    return m_settings->boolValue(ShuffleKey, false);
}

void SettingsController::setShuffle(bool shuffle)
{
    m_settings->setBool(ShuffleKey, shuffle);
    scheduleSave();
}

int SettingsController::repeatMode() const
{
    return qBound(0, m_settings->intValue(RepeatModeKey, 0), 2);
}

void SettingsController::setRepeatMode(int mode)
{
    m_settings->setInt(RepeatModeKey, mode);
    scheduleSave();
}

void SettingsController::setWidth(const char *key, int width, int min, int max)
{
    width = qBound(min, width, max);
    if (width == m_settings->intValue(key, -1))
        return;
    m_settings->setInt(key, width);
    scheduleSave();
    emit columnWidthsChanged();
}

void SettingsController::scheduleSave()
{
    m_saveTimer.start();
}
