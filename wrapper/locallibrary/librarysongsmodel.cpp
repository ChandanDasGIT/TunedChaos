#include "wrapper/locallibrary/librarysongsmodel.h"

#include "backend/library/letterindex/letterindex.h"

int LibrarySongsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_tracks.size());
}

QVariantMap LibrarySongsModel::get(int row) const
{
    if (row < 0 || size_t(row) >= m_tracks.size())
        return {};
    const Track &track = m_tracks[size_t(row)];
    return {{QStringLiteral("path"), QString::fromStdString(track.path)},
            {QStringLiteral("title"), QString::fromStdString(track.title)},
            {QStringLiteral("artist"), QString::fromStdString(track.artist)},
            {QStringLiteral("album"), QString::fromStdString(track.album)},
            {QStringLiteral("duration"), qint64(track.durationMs)}};
}

QVariant LibrarySongsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || size_t(index.row()) >= m_tracks.size())
        return {};
    const Track &track = m_tracks[size_t(index.row())];
    switch (role) {
    case PathRole: return QString::fromStdString(track.path);
    case TitleRole: return QString::fromStdString(track.title);
    case ArtistRole: return QString::fromStdString(track.artist);
    case AlbumRole: return QString::fromStdString(track.album);
    case DurationRole: return qint64(track.durationMs);
    case TrackNumberRole: return track.track;
    case LetterRole: return QString::fromStdString(LetterIndex::letterOf(track.title)); // its letter group
    }
    return {};
}

QHash<int, QByteArray> LibrarySongsModel::roleNames() const
{
    return {
        {PathRole, "path"},       {TitleRole, "title"},       {ArtistRole, "artist"},
        {AlbumRole, "album"},     {DurationRole, "duration"}, {TrackNumberRole, "trackNumber"},
        {LetterRole, "letter"},
    };
}

void LibrarySongsModel::setTracks(std::vector<Track> tracks)
{
    const bool countChanges = tracks.size() != m_tracks.size();
    beginResetModel();
    m_tracks = std::move(tracks);
    endResetModel();
    if (countChanges)
        emit countChanged();
}
