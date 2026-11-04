#include "wrapper/opener/fileopener.h"

#include "backend/library/metadata/metadata.h"
#include "backend/library/track/track.h"
#include "backend/playlist/m3u/m3u.h"
#include "wrapper/library/librarycontroller.h"
#include "wrapper/playlist/playlistcontroller.h"

#include <QFileInfo>
#include <QUrl>

#include <vector>

namespace {

QString pathOf(const QString &fileOrUrl)
{
    const QUrl url(fileOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : fileOrUrl;
}

bool isPlaylist(const QString &path)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    return suffix == QLatin1String("m3u") || suffix == QLatin1String("m3u8");
}

} // namespace

FileOpener::FileOpener(PlaylistController *playlist, LibraryController *library, QObject *parent)
    : QObject(parent)
    , m_playlist(playlist)
    , m_library(library)
{
    m_pool.setMaxThreadCount(1); // one batch after the other, in the order asked
}

FileOpener::~FileOpener()
{
    m_pool.waitForDone(); // no task may post to a destroyed object
}

QStringList FileOpener::filesIn(const QStringList &arguments)
{
    QStringList files;
    for (const QString &argument : arguments)
        if (!argument.startsWith(QLatin1Char('-')) && !argument.isEmpty())
            files << argument;
    return files;
}

void FileOpener::open(const QStringList &files)
{
    QStringList paths;
    QList<QUrl> folders;
    for (const QString &file : files) {
        const QString path = pathOf(file);
        const QFileInfo info(path);
        if (info.isDir())
            folders << QUrl::fromLocalFile(path); // scanned like a dropped folder
        else if (info.isFile())
            paths << path;
    }
    if (!folders.isEmpty())
        m_library->addUrls(folders);
    if (paths.isEmpty()) {
        if (!folders.isEmpty())
            emit opened();
        return;
    }

    // Tags read on the side (a playlist reads all of its songs). (The pool is
    // waited for when this goes: `this` outlives the task.)
    m_pool.start([this, paths] {
        std::vector<::Track> tracks;
        for (const QString &path : paths) {
            if (isPlaylist(path)) {
                const M3u::Result list = M3u::read(path.toStdString());
                tracks.insert(tracks.end(), list.tracks.begin(), list.tracks.end());
            } else {
                tracks.push_back(Metadata::read(path.toStdString()));
            }
        }
        QMetaObject::invokeMethod(this, [this, tracks = std::move(tracks)]() mutable {
            if (tracks.empty())
                return;
            m_playlist->addAndPlay(std::move(tracks), true); // (songs already there aren't added twice)
            emit opened();
        }, Qt::QueuedConnection);
    });
}

#ifndef Q_OS_ANDROID
void FileOpener::listenToSystem() {} // (the desktop hands files over on the command line)
#endif
