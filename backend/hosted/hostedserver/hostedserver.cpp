#include "backend/hosted/hostedserver/hostedserver.h"

#include "backend/hosted/jellyfin/jellyfin.h"

bool HostedPath::is(const std::string &path)
{
    return path.rfind(Prefix, 0) == 0;
}

std::string HostedPath::make(const std::string &accountId, const std::string &songId)
{
    return Prefix + accountId + ':' + songId;
}

std::string HostedPath::accountId(const std::string &path)
{
    if (!is(path))
        return {};
    const size_t start = std::string(Prefix).size();
    const size_t colon = path.find(':', start);
    return colon == std::string::npos ? std::string() : path.substr(start, colon - start);
}

std::string HostedPath::songId(const std::string &path)
{
    if (!is(path))
        return {};
    const size_t colon = path.find(':', std::string(Prefix).size());
    return colon == std::string::npos ? std::string() : path.substr(colon + 1);
}

std::optional<HostedAccount> HostedServer::signIn(const std::string &kind, const std::string &serverUrl,
                                                  const std::string &userName, const std::string &password,
                                                  const std::string &deviceId, std::string &error)
{
    if (kind == "jellyfin")
        return JellyfinServer::signIn(serverUrl, userName, password, deviceId, error);
    error = "Unknown kind of server";
    return std::nullopt;
}

std::unique_ptr<HostedServer> HostedServer::open(const HostedAccount &account)
{
    if (account.kind == "jellyfin")
        return std::make_unique<JellyfinServer>(account);
    return nullptr;
}
