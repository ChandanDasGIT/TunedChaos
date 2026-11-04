#pragma once

#include <atomic>
#include <functional>
#include <optional>
#include <string>
#include <vector>

// The app's own updates: what the newest release on GitHub is, and getting a
// file of it (resumed where it stopped, checked before use). Blocking: call
// from worker threads.
struct UpdateAsset
{
    std::string name;
    std::string url;
    long long size = 0;
    std::string sha256; // "" = GitHub didn't say
};

struct UpdateRelease
{
    std::string version; // "1.2" (from the tag "v1.2")
    std::string pageUrl;  // the release's page, for reading or downloading by hand
    std::string notes;    // what's new (Markdown, as written on the release)
    std::vector<UpdateAsset> assets;

    // The file whose name ends with `suffix` (".apk", ".AppImage"...), if there is one.
    const UpdateAsset *asset(const std::string &suffix) const;
};

namespace AppUpdate {

// GitHub's newest release (TUNEDCHAOS_UPDATE_URL replaces the address, for tests).
std::optional<UpdateRelease> latest();

std::string versionOfTag(const std::string &tag); // "v1.2" -> "1.2"; "" if not a version
bool isNewer(const std::string &version, const std::string &running); // 1.10 > 1.9, 1.1.0 == 1.1

// Saves the asset as `target` (via target + ".part", which a later call
// carries on from) and checks its size and checksum. "" when it's ready, else
// what went wrong; "" too when `cancelled` stopped it (the target then doesn't exist).
std::string download(const UpdateAsset &asset, const std::string &target, const std::atomic_bool &cancelled,
                     const std::function<void(int percent)> &progress);

} // namespace AppUpdate
