#include "wrapper/playlist/playlistmodel.h"

#include <algorithm>

PlaylistModel::PlaylistModel(Playlist &playlist, QObject *parent)
    : QAbstractListModel(parent)
    , m_playlist(playlist)
{
}

int PlaylistModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_playlist.size());
}

QVariant PlaylistModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};

    const Track &track = m_playlist.at(size_t(index.row()));
    switch (role) {
    case PathRole:        return QString::fromStdString(track.path);
    case Qt::DisplayRole:
    case TitleRole:       return QString::fromStdString(track.title);
    case ArtistAlbumRole: return artistAlbum(track);
    case TrackLabelRole:  return trackLabel(track);
    case DurationRole:    return qint64(track.durationMs);
    case IsCurrentRole:   return index.row() == m_playlist.currentIndex();
    case ThumbnailRole:   return QString::fromStdString(track.thumbnailUrl);
    case IsYouTubeRole:   return !track.videoId.empty();
    }
    return {};
}

QHash<int, QByteArray> PlaylistModel::roleNames() const
{
    return {
        {PathRole, "path"},
        {TitleRole, "title"},
        {ArtistAlbumRole, "artistAlbum"},
        {TrackLabelRole, "trackLabel"},
        {DurationRole, "durationMs"},
        {IsCurrentRole, "isCurrent"},
        {ThumbnailRole, "thumbnail"},
        {IsYouTubeRole, "isYouTube"},
    };
}

bool PlaylistModel::addTrack(Track track)
{
    if (m_playlist.contains(track.path))
        return false;

    const int row = int(m_playlist.insertPosition(track));
    beginInsertRows({}, row, row);
    m_playlist.insert(size_t(row), std::move(track));
    endInsertRows();
    return true;
}

bool PlaylistModel::appendTrack(Track track)
{
    if (m_playlist.contains(track.path))
        return false;
    const int row = rowCount();
    beginInsertRows({}, row, row);
    m_playlist.append(std::move(track));
    endInsertRows();
    return true;
}

bool PlaylistModel::insertTrack(int row, Track track)
{
    if (m_playlist.contains(track.path))
        return false;
    row = std::clamp(row, 0, rowCount());
    beginInsertRows({}, row, row);
    m_playlist.insert(size_t(row), std::move(track));
    endInsertRows();
    return true;
}

void PlaylistModel::moveTrack(int from, int to)
{
    if (from < 0 || to < 0 || from >= rowCount() || to >= rowCount() || from == to)
        return;
    // Qt's destination is "insert before this row" in the old numbering.
    if (!beginMoveRows({}, from, from, {}, to > from ? to + 1 : to))
        return;
    m_playlist.move(size_t(from), size_t(to));
    endMoveRows();
}

void PlaylistModel::removeTrack(int row)
{
    if (row < 0 || row >= rowCount())
        return;
    beginRemoveRows({}, row, row);
    m_playlist.remove(size_t(row));
    endRemoveRows();
}

void PlaylistModel::setTracks(std::vector<Track> tracks)
{
    beginResetModel();
    m_playlist.setTracks(std::move(tracks));
    endResetModel();
}

void PlaylistModel::clear()
{
    beginResetModel();
    m_playlist.clear();
    endResetModel();
}

void PlaylistModel::sortBy(Playlist::SortColumn column, bool descending)
{
    beginResetModel();
    m_playlist.sort(column, descending);
    endResetModel();
}

void PlaylistModel::refreshRow(int row)
{
    if (row >= 0 && row < rowCount())
        emit dataChanged(index(row), index(row));
}

void PlaylistModel::refreshCurrent(int previous)
{
    const int current = m_playlist.currentIndex();
    if (current == previous)
        return;

    for (int row : {previous, current}) {
        if (row >= 0)
            emit dataChanged(this->index(row), this->index(row), {IsCurrentRole});
    }
}

// "Artist - Album", or whichever of the two exists.
QString PlaylistModel::artistAlbum(const Track &track)
{
    const QString artist = QString::fromStdString(track.artist);
    const QString album = QString::fromStdString(track.album);
    if (artist.isEmpty() || album.isEmpty())
        return artist.isEmpty() ? album : artist;
    return artist + QStringLiteral(" - ") + album;
}

// "1.03" for multi-disc albums, otherwise "03"; empty when unknown.
QString PlaylistModel::trackLabel(const Track &track)
{
    if (track.track <= 0)
        return {};
    const QString number = QStringLiteral("%1").arg(track.track, 2, 10, QLatin1Char('0'));
    if (track.discTotal > 1 || track.disc > 1)
        return QStringLiteral("%1.%2").arg(qMax(track.disc, 1)).arg(number);
    return number;
}
