#pragma once

#include "backend/library/track/track.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

#include <vector>

// A read-only list of library songs for QML (the Songs tab, an album, an artist).
class LibrarySongsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Provided by LocalLibraryController")

    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Role { PathRole = Qt::UserRole + 1, TitleRole, ArtistRole, AlbumRole, DurationRole, TrackNumberRole, LetterRole };

    using QAbstractListModel::QAbstractListModel;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_tracks.size()); }
    // One row's roles by name, for views that aren't item views (the grid): { path, title, artist, album, duration }
    Q_INVOKABLE QVariantMap get(int row) const;
    const std::vector<Track> &tracks() const { return m_tracks; }
    void setTracks(std::vector<Track> tracks);

signals:
    void countChanged();

private:
    std::vector<Track> m_tracks;
};
