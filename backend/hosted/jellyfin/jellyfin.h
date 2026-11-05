#pragma once

#include "backend/hosted/hostedserver/hostedserver.h"

// A Jellyfin server (its REST API, https://api.jellyfin.org). Plays songs as
// stored on the server (no transcoding).
class JellyfinServer : public HostedServer
{
public:
    explicit JellyfinServer(HostedAccount account);

    static std::optional<HostedAccount> signIn(const std::string &serverUrl, const std::string &userName,
                                               const std::string &password, const std::string &deviceId,
                                               std::string &error);

    std::optional<std::vector<HostedSong>> songs(Sort sort) override;
    std::optional<std::vector<HostedCollection>> collections(Kind kind, Sort sort) override;
    std::optional<std::vector<HostedSong>> songsOf(Kind kind, const std::string &id) override;
    std::optional<FolderContents> folder(const std::string &id, Sort sort) override;
    std::optional<std::vector<HostedSong>> favorites(Sort sort) override;
    std::string folderCoverId(const std::string &folderId) override;
    bool setFavorite(const std::string &songId, bool favorite) override;
    std::string createPlaylist(const std::string &name, const std::vector<std::string> &songIds) override;
    bool addToPlaylist(const std::string &playlistId, const std::vector<std::string> &songIds) override;
    bool removeFromPlaylist(const std::string &playlistId, const std::vector<std::string> &entryIds) override;
    void reportPlayback(PlayEvent event, const std::string &songId, int64_t positionMs) override;

    std::string streamUrl(const std::string &songId) const override;
    std::string coverUrl(const std::string &itemId, int size) const override;

private:
    std::optional<std::string> get(const std::string &pathAndQuery); // the body, or nothing (m_error)
    // POST (body: JSON, "" for none) / DELETE: the answer's body, or nothing (m_error)
    std::optional<std::string> post(const std::string &pathAndQuery, const std::string &body);
    bool remove(const std::string &pathAndQuery);
    std::optional<std::vector<HostedSong>> songList(const std::string &query);

    HostedAccount m_account;
};
