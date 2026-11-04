#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// A music server the Hosted library plays from (Jellyfin first; the app's own
// server later). Each kind implements HostedServer; everything else in the app
// only sees these types, so another kind plugs in without other changes.
//
// Its songs get playlist paths "hosted:<accountId>:<songId>" (HostedPath),
// turned into stream addresses when they play (HostedStore::streamUrl).

// Signing in to a server gives an account: enough to talk to it again later.
struct HostedAccount
{
    std::string id;         // the app's own name for it, in song paths
    std::string kind;       // "jellyfin"
    std::string serverUrl;  // "https://music.example.com" (no trailing "/")
    std::string serverName;
    std::string userId;
    std::string userName;
    std::string token;      // the server's sign-in token (never the password)
    std::string deviceId;   // this app on this device, as the server knows it
};

struct HostedSong
{
    std::string id;
    std::string title;
    std::string artist;
    std::string album;
    std::string albumId;
    std::string coverId; // item whose picture is the cover ("" = none)
    int disc = 0;
    int track = 0;
    int64_t durationMs = 0;
};

// An album, artist, playlist or folder: something with songs in it.
struct HostedCollection
{
    std::string id;
    std::string name;
    std::string subtitle; // album: its artist; playlist: "" (count is shown)
    std::string coverId;
    int songCount = 0;    // 0 = not known
    int year = 0;
};

namespace HostedPath {

inline constexpr const char *Prefix = "hosted:";

bool is(const std::string &path);
std::string make(const std::string &accountId, const std::string &songId);
// "" for paths that aren't hosted songs
std::string accountId(const std::string &path);
std::string songId(const std::string &path);

} // namespace HostedPath

class HostedServer
{
public:
    enum class Kind { Albums, Artists, Playlists, Folders };
    // How a list comes back (a kind of server may ignore what it can't do)
    enum class Sort { Name, NameDesc, Newest, Oldest, Artist, Album, Year };
    static Sort sortFromId(const std::string &id); // "name", "nameDesc", "newest"... (unknown: Name)

    virtual ~HostedServer() = default;

    // Signs in with a user name and password: the account, or nothing (lastError() says why).
    // `deviceId`: the same for every sign-in from this device.
    static std::optional<HostedAccount> signIn(const std::string &kind, const std::string &serverUrl,
                                               const std::string &userName, const std::string &password,
                                               const std::string &deviceId, std::string &error);
    // Talks to the server of an account (nothing for an unknown kind).
    static std::unique_ptr<HostedServer> open(const HostedAccount &account);

    // Blocking (call from worker threads). Nothing on failure: lastError() says why.
    virtual std::optional<std::vector<HostedSong>> songs(Sort sort) = 0;
    virtual std::optional<std::vector<HostedCollection>> collections(Kind kind, Sort sort) = 0;
    // Folders: songsOf(Kind::Folders, id) is every song under it, subfolders too.
    virtual std::optional<std::vector<HostedSong>> songsOf(Kind kind, const std::string &id) = 0;

    // The folders as stored on the server. id "": the music libraries (the top
    // folders). Otherwise what's right in that folder: its folders, its songs.
    struct FolderContents
    {
        std::vector<HostedCollection> folders;
        std::vector<HostedSong> songs;
    };
    virtual std::optional<FolderContents> folder(const std::string &id, Sort sort) = 0;

    // Addresses (no network): the song's audio as stored, a picture at about `size` pixels.
    virtual std::string streamUrl(const std::string &songId) const = 0;
    virtual std::string coverUrl(const std::string &itemId, int size) const = 0;

    const std::string &lastError() const { return m_error; }

protected:
    std::string m_error;
};
