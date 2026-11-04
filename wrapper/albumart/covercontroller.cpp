#include "wrapper/albumart/covercontroller.h"

#include "wrapper/files/files.h"
#include "backend/library/coverfinder/coverfinder.h"
#include "backend/library/metadata/metadata.h"
#include "backend/youtube/streamresolver/streamresolver.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/settings/settingscontroller.h"
#include "wrapper/youtube/ytmetadatacontroller.h"

#include <QJSEngine>
#include <QStandardPaths>

namespace {

std::string cacheDir()
{
    static const std::string dir =
        (Files::cacheDir() + QStringLiteral("/covers"))
            .toStdString();
    return dir;
}

CoverQuery queryFor(const Track &track)
{
    CoverQuery query;
    query.path = track.path;
    query.title = track.title;
    query.artist = track.artist;
    query.album = track.album;
    query.albumArtist = track.albumArtist;
    query.durationMs = track.durationMs;
    return query;
}

} // namespace

CoverController::CoverController(PlayerController *player, YtMetadataController *ytMetadata,
                                 SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_ytMetadata(ytMetadata)
    , m_settings(settings)
{
    Q_ASSERT(!s_instance);
    s_instance = this;
    m_pool.setMaxThreadCount(1);
    m_pool.start([] { CoverFinder(cacheDir()).removeOldCache(); }); // before any lookup (one worker)
    connect(m_player, &PlayerController::sourceChanged, this, &CoverController::onSourceChanged);
}

CoverController::~CoverController()
{
    m_pool.waitForDone();
    s_instance = nullptr;
}

CoverController *CoverController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

std::vector<unsigned char> CoverController::coverBytes(const std::string &path)
{
    std::vector<unsigned char> data = Metadata::readCover(path);
    if (!data.empty())
        return data;
    return CoverFinder(cacheDir()).cached(queryFor(Metadata::read(path))).data;
}

void CoverController::onSourceChanged()
{
    const QString path = m_player->source();
    if (path == m_path)
        return;
    m_path = path;
    const int generation = ++m_generation;
    m_currentSource.clear();
    m_searching = false;
    emit currentChanged();
    if (path.isEmpty() || StreamResolver::isRemote(path.toStdString()))
        return; // YouTube songs come with their own picture

    std::string ytThumbnail, ytAlbum;
    const QVariantMap yt = m_ytMetadata->infoFor(path);
    if (yt.value(QStringLiteral("state")).toString() == QLatin1String("matched")) {
        ytThumbnail = yt.value(QStringLiteral("thumbnail")).toString().toStdString();
        ytAlbum = yt.value(QStringLiteral("album")).toString().toStdString();
    }

    const bool online = m_settings->coversOnline();
    std::vector<std::string> sources;
    for (const QString &id : m_settings->enabledCoverSourceIds())
        sources.push_back(id.toStdString());

    m_pool.start([this, generation, file = path.toStdString(), ytThumbnail, ytAlbum, online, sources] {
        if (!Metadata::readCover(file).empty()) {
            QMetaObject::invokeMethod(this, [this, generation] { finish(generation, QStringLiteral("embedded"), false); },
                                      Qt::QueuedConnection);
            return;
        }
        // The file's own tags (with the album artist), not what a list remembers.
        CoverQuery query = queryFor(Metadata::read(file));
        query.knownYtThumbnail = ytThumbnail;
        query.knownYtAlbum = ytAlbum;
        const CoverFinder finder(cacheDir());
        if (!online || finder.lookedUp(query)) {
            const QString source = QString::fromStdString(finder.cached(query).source);
            QMetaObject::invokeMethod(this, [this, generation, source] { finish(generation, source, false); },
                                      Qt::QueuedConnection);
            return;
        }
        QMetaObject::invokeMethod(this, [this, generation] {
            if (generation == m_generation) {
                m_searching = true;
                emit currentChanged();
            }
        }, Qt::QueuedConnection);

        // Shown as soon as something is found, and again when a sharper one arrives.
        const CoverFinder::Image image = finder.find(query, sources, [this, generation](const CoverFinder::Image &better) {
            const QString source = QString::fromStdString(better.source);
            QMetaObject::invokeMethod(this, [this, generation, source] { improve(generation, source); },
                                      Qt::QueuedConnection);
        });
        const QString source = QString::fromStdString(image.source);
        QMetaObject::invokeMethod(this, [this, generation, source] { finish(generation, source, false); },
                                  Qt::QueuedConnection);
    });
}

void CoverController::improve(int generation, const QString &source)
{
    ++m_revision; // other songs of the album may show it too, even if the track changed meanwhile
    emit revisionChanged();
    if (generation == m_generation && source != m_currentSource) {
        m_currentSource = source;
        emit currentChanged();
    }
}

void CoverController::finish(int generation, const QString &source, bool found)
{
    if (found) { // other songs of the album may show it too, even if the track changed meanwhile
        ++m_revision;
        emit revisionChanged();
    }
    if (generation != m_generation)
        return;
    m_currentSource = source;
    m_searching = false;
    emit currentChanged();
}
