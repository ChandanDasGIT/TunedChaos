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

    std::optional<std::vector<HostedSong>> songs() override;
    std::optional<std::vector<HostedCollection>> collections(Kind kind) override;
    std::optional<std::vector<HostedSong>> songsOf(Kind kind, const std::string &id) override;

    std::string streamUrl(const std::string &songId) const override;
    std::string coverUrl(const std::string &itemId, int size) const override;

private:
    std::optional<std::string> get(const std::string &pathAndQuery); // the body, or nothing (m_error)

    HostedAccount m_account;
};
