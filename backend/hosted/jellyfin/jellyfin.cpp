#include "backend/hosted/jellyfin/jellyfin.h"

#include "backend/network/httpclient/httpclient.h"

#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace {

constexpr long TimeoutMs = 20000;
constexpr long ListTimeoutMs = 60000; // a whole library can take a while

#if defined(__ANDROID__)
constexpr const char *DeviceName = "Android";
#elif defined(_WIN32)
constexpr const char *DeviceName = "Windows";
#else
constexpr const char *DeviceName = "Linux";
#endif

// "music.example.com/" -> "http://music.example.com"
std::string normalizedUrl(std::string url)
{
    while (!url.empty() && (url.back() == '/' || url.back() == ' '))
        url.pop_back();
    while (!url.empty() && url.front() == ' ')
        url.erase(url.begin());
    if (!url.empty() && url.find("://") == std::string::npos)
        url = "http://" + url;
    return url;
}

// Who is asking: Jellyfin wants the app and device in every request.
std::string authorization(const std::string &deviceId, const std::string &token)
{
    std::string value = std::string("MediaBrowser Client=\"Tuned Chaos\", Device=\"") + DeviceName
                        + "\", DeviceId=\"" + deviceId + "\", Version=\"1\"";
    if (!token.empty())
        value += ", Token=\"" + token + "\"";
    return value;
}

std::vector<std::string> headers(const std::string &deviceId, const std::string &token)
{
    const std::string auth = authorization(deviceId, token);
    // (Older servers read X-Emby-Authorization)
    return {"Authorization: " + auth, "X-Emby-Authorization: " + auth, "Accept: application/json",
            "Content-Type: application/json"};
}

std::string text(const json &item, const char *key)
{
    const auto it = item.find(key);
    return it != item.end() && it->is_string() ? it->get<std::string>() : std::string();
}

int64_t number(const json &item, const char *key)
{
    const auto it = item.find(key);
    return it != item.end() && it->is_number() ? it->get<int64_t>() : 0;
}

bool hasPrimaryImage(const json &item)
{
    const auto tags = item.find("ImageTags");
    return tags != item.end() && tags->is_object() && tags->contains("Primary");
}

std::string joined(const json &item, const char *key)
{
    std::string out;
    const auto it = item.find(key);
    if (it == item.end() || !it->is_array())
        return out;
    for (const json &name : *it)
        if (name.is_string()) {
            if (!out.empty())
                out += ", ";
            out += name.get<std::string>();
        }
    return out;
}

HostedSong songOf(const json &item)
{
    HostedSong song;
    song.id = text(item, "Id");
    song.title = text(item, "Name");
    song.artist = joined(item, "Artists");
    if (song.artist.empty())
        song.artist = text(item, "AlbumArtist");
    song.album = text(item, "Album");
    song.albumId = text(item, "AlbumId");
    song.coverId = hasPrimaryImage(item) ? song.id
                 : !text(item, "AlbumPrimaryImageTag").empty() ? song.albumId : std::string();
    song.disc = int(number(item, "ParentIndexNumber"));
    song.track = int(number(item, "IndexNumber"));
    song.durationMs = number(item, "RunTimeTicks") / 10000; // ticks of 100 ns
    return song;
}

HostedCollection collectionOf(const json &item, bool album)
{
    HostedCollection c;
    c.id = text(item, "Id");
    c.name = text(item, "Name");
    c.subtitle = album ? text(item, "AlbumArtist") : std::string();
    c.coverId = hasPrimaryImage(item) ? c.id : std::string();
    c.songCount = int(number(item, "ChildCount"));
    c.year = int(number(item, "ProductionYear"));
    return c;
}

// The "Items" array of a list answer (nothing if it isn't one).
const json *itemsOf(const json &answer)
{
    const auto it = answer.find("Items");
    return it != answer.end() && it->is_array() ? &*it : nullptr;
}

// Jellyfin's SortBy / SortOrder for a sort (songs: track order within albums)
std::string sortQuery(HostedServer::Sort sort, bool songs)
{
    using Sort = HostedServer::Sort;
    const std::string inAlbum = songs ? ",ParentIndexNumber,IndexNumber" : "";
    switch (sort) {
    case Sort::Name: return "&SortBy=SortName&SortOrder=Ascending";
    case Sort::NameDesc: return "&SortBy=SortName&SortOrder=Descending";
    case Sort::Newest: return "&SortBy=DateCreated,SortName&SortOrder=Descending";
    case Sort::Oldest: return "&SortBy=DateCreated,SortName&SortOrder=Ascending";
    case Sort::Artist:
        return songs ? "&SortBy=Artist,Album" + inAlbum + ",SortName&SortOrder=Ascending"
                     : "&SortBy=AlbumArtist,SortName&SortOrder=Ascending";
    case Sort::Album: return "&SortBy=Album" + inAlbum + ",SortName&SortOrder=Ascending";
    case Sort::Year: return "&SortBy=ProductionYear,SortName&SortOrder=Descending";
    }
    return "&SortBy=SortName";
}

std::string reason(const HttpResponse &response)
{
    if (!response.error.empty())
        return "Couldn't reach the server: " + response.error;
    if (response.status == 401)
        return "The server didn't accept the sign-in (wrong user name or password, or signed out)";
    return "The server answered with an error (HTTP " + std::to_string(response.status) + ")";
}

} // namespace

JellyfinServer::JellyfinServer(HostedAccount account)
    : m_account(std::move(account))
{
}

std::optional<HostedAccount> JellyfinServer::signIn(const std::string &serverUrl, const std::string &userName,
                                                    const std::string &password, const std::string &deviceId,
                                                    std::string &error)
{
    HostedAccount account;
    account.kind = "jellyfin";
    account.serverUrl = normalizedUrl(serverUrl);
    account.deviceId = deviceId;
    if (account.serverUrl.empty()) {
        error = "Enter the server's address";
        return std::nullopt;
    }

    // Is it a Jellyfin server at all?
    const HttpResponse info = HttpClient::get(account.serverUrl + "/System/Info/Public", headers(deviceId, {}), TimeoutMs);
    if (!info.ok()) {
        error = info.error.empty() ? "No Jellyfin server at that address" : reason(info);
        return std::nullopt;
    }
    const json about = json::parse(info.body, nullptr, false);
    if (about.is_discarded() || !about.is_object() || text(about, "Id").empty()) {
        error = "No Jellyfin server at that address";
        return std::nullopt;
    }
    account.serverName = text(about, "ServerName");

    const json body = {{"Username", userName}, {"Pw", password}};
    const HttpResponse response = HttpClient::post(account.serverUrl + "/Users/AuthenticateByName", body.dump(),
                                                   headers(deviceId, {}), TimeoutMs);
    if (!response.ok()) {
        error = reason(response);
        return std::nullopt;
    }
    const json answer = json::parse(response.body, nullptr, false);
    if (answer.is_discarded() || !answer.is_object()) {
        error = "The server's answer couldn't be read";
        return std::nullopt;
    }
    account.token = text(answer, "AccessToken");
    if (const auto user = answer.find("User"); user != answer.end() && user->is_object()) {
        account.userId = text(*user, "Id");
        account.userName = text(*user, "Name");
    }
    if (account.token.empty() || account.userId.empty()) {
        error = "The server's answer couldn't be read";
        return std::nullopt;
    }
    return account;
}

std::optional<std::string> JellyfinServer::get(const std::string &pathAndQuery)
{
    const HttpResponse response = HttpClient::get(m_account.serverUrl + pathAndQuery,
                                                  headers(m_account.deviceId, m_account.token), ListTimeoutMs);
    if (!response.ok()) {
        m_error = reason(response);
        return std::nullopt;
    }
    return response.body;
}

std::optional<std::vector<HostedSong>> JellyfinServer::songs(Sort sort)
{
    return songList("/Users/" + HttpClient::urlEncode(m_account.userId)
                    + "/Items?IncludeItemTypes=Audio&Recursive=true&EnableTotalRecordCount=false" + sortQuery(sort, true));
}

std::optional<std::vector<HostedCollection>> JellyfinServer::collections(Kind kind, Sort sort)
{
    const std::string user = HttpClient::urlEncode(m_account.userId);
    std::string query;
    switch (kind) {
    case Kind::Albums:
        query = "/Users/" + user + "/Items?IncludeItemTypes=MusicAlbum&Recursive=true"
                "&Fields=ChildCount&EnableTotalRecordCount=false" + sortQuery(sort, false);
        break;
    case Kind::Artists:
        query = "/Artists/AlbumArtists?UserId=" + user + "&EnableTotalRecordCount=false"
                + sortQuery(sort == Sort::NameDesc ? sort : Sort::Name, false);
        break;
    case Kind::Playlists:
        query = "/Users/" + user + "/Items?IncludeItemTypes=Playlist&Recursive=true"
                "&Fields=ChildCount&EnableTotalRecordCount=false" + sortQuery(sort, false);
        break;
    }
    const std::optional<std::string> body = get(query);
    if (!body)
        return std::nullopt;
    const json answer = json::parse(*body, nullptr, false);
    const json *items = answer.is_discarded() ? nullptr : itemsOf(answer);
    if (!items) {
        m_error = "The server's answer couldn't be read";
        return std::nullopt;
    }
    std::vector<HostedCollection> out;
    for (const json &item : *items)
        if (item.is_object())
            out.push_back(collectionOf(item, kind == Kind::Albums));
    return out;
}

std::optional<std::vector<HostedSong>> JellyfinServer::songsOf(Kind kind, const std::string &id)
{
    const std::string user = HttpClient::urlEncode(m_account.userId);
    const std::string common = "&IncludeItemTypes=Audio&Recursive=true&EnableTotalRecordCount=false";
    std::string query;
    if (kind == Kind::Albums)
        query = "/Users/" + user + "/Items?ParentId=" + HttpClient::urlEncode(id)
                + "&SortBy=ParentIndexNumber,IndexNumber,SortName" + common;
    else if (kind == Kind::Artists)
        query = "/Users/" + user + "/Items?ArtistIds=" + HttpClient::urlEncode(id)
                + "&SortBy=Album,ParentIndexNumber,IndexNumber,SortName" + common;
    else // a playlist: in its own order
        query = "/Playlists/" + HttpClient::urlEncode(id) + "/Items?UserId=" + user;
    return songList(query);
}

std::optional<std::vector<HostedSong>> JellyfinServer::songList(const std::string &query)
{
    const std::optional<std::string> body = get(query);
    if (!body)
        return std::nullopt;
    const json answer = json::parse(*body, nullptr, false);
    const json *items = answer.is_discarded() ? nullptr : itemsOf(answer);
    if (!items) {
        m_error = "The server's answer couldn't be read";
        return std::nullopt;
    }
    std::vector<HostedSong> out;
    for (const json &item : *items)
        if (item.is_object() && text(item, "Type") != "Folder" && text(item, "MediaType") != "Video")
            out.push_back(songOf(item));
    return out;
}

std::string JellyfinServer::streamUrl(const std::string &songId) const
{
    return m_account.serverUrl + "/Audio/" + HttpClient::urlEncode(songId) + "/stream?static=true&api_key="
           + HttpClient::urlEncode(m_account.token) + "&DeviceId=" + HttpClient::urlEncode(m_account.deviceId);
}

std::string JellyfinServer::coverUrl(const std::string &itemId, int size) const
{
    if (itemId.empty())
        return {};
    const std::string px = std::to_string(size);
    return m_account.serverUrl + "/Items/" + HttpClient::urlEncode(itemId) + "/Images/Primary?maxWidth=" + px
           + "&maxHeight=" + px + "&quality=90&api_key=" + HttpClient::urlEncode(m_account.token);
}
