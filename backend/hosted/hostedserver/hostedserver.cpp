#include "backend/hosted/hostedserver/hostedserver.h"

#include "backend/hosted/jellyfin/jellyfin.h"

#include <algorithm>

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

HostedServer::Sort HostedServer::sortFromId(const std::string &id)
{
    if (id == "nameDesc") return Sort::NameDesc;
    if (id == "newest") return Sort::Newest;
    if (id == "oldest") return Sort::Oldest;
    if (id == "artist") return Sort::Artist;
    if (id == "album") return Sort::Album;
    if (id == "year") return Sort::Year;
    if (id == "mostSongs") return Sort::MostSongs;
    if (id == "fewestSongs") return Sort::FewestSongs;
    return Sort::Name;
}

void HostedServer::sortBySongCount(std::vector<HostedCollection> &list, Sort sort)
{
    if (sort != Sort::MostSongs && sort != Sort::FewestSongs)
        return;
    const bool most = sort == Sort::MostSongs;
    std::stable_sort(list.begin(), list.end(), [most](const HostedCollection &a, const HostedCollection &b) {
        return most ? a.songCount > b.songCount : a.songCount < b.songCount;
    });
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
