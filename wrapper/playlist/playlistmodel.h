#pragma once

#include "backend/library/track/track.h"
#include "backend/playlist/playlist/playlist.h"

#include <QAbstractListModel>

#include <vector>
#include <QString>
#include <QtQml/qqmlregistration.h>

// List model view of a backend Playlist (exposed as PlaylistController.model).
// All playlist mutations go through here so views get the right notifications.
class PlaylistModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Use PlaylistController.model")

public:
    enum Role {
        PathRole = Qt::UserRole + 1,
        TitleRole,
        ArtistAlbumRole,
        TrackLabelRole,
        DurationRole,
        IsCurrentRole,
        ThumbnailRole,  // YouTube tracks: cover URL ("" for local files)
        IsYouTubeRole,
    };
    Q_ENUM(Role)

    PlaylistModel(Playlist &playlist, QObject *parent);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Inserts at the sorted position; false if the path is already present.
    bool addTrack(Track track);
    // Adds at the end; false if the path is already present.
    bool appendTrack(Track track);
    // Inserts at `row` (clamped); false if the path is already present.
    bool insertTrack(int row, Track track);
    void removeTrack(int row);
    void moveTrack(int from, int to);
    void setTracks(std::vector<Track> tracks); // replaces everything
    void clear();
    void sortBy(Playlist::SortColumn column, bool descending);
    // Call after the playlist's current track changed (was `previousRow`).
    void refreshCurrent(int previousRow);
    void refreshRow(int row); // its song's tags changed

    static QString artistAlbum(const Track &track);
    static QString trackLabel(const Track &track);

private:
    Playlist &m_playlist;
};
