#include "backend/update/appupdate/appupdate.h"

#include "backend/network/httpclient/httpclient.h"
#include "backend/update/sha256/sha256.h"

#include <cstdlib>
#include <filesystem>
#include <nlohmann/json.hpp>

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace {

constexpr const char *LatestUrl = "https://api.github.com/repos/ChandanDasGIT/TunedChaos/releases/latest";

// "1.10.2" -> {1, 10, 2}; empty if it isn't one
std::vector<long> parts(const std::string &version)
{
    std::vector<long> out;
    long value = -1;
    for (const char c : version) {
        if (c >= '0' && c <= '9') {
            value = (value < 0 ? 0 : value * 10) + (c - '0');
        } else if (c == '.' && value >= 0) {
            out.push_back(value);
            value = -1;
        } else {
            return {};
        }
    }
    if (value < 0)
        return {};
    out.push_back(value);
    return out;
}

bool complete(const std::string &path, const UpdateAsset &asset)
{
    std::error_code ec;
    if (fs::file_size(path, ec) != (uintmax_t)asset.size || ec)
        return false;
    if (asset.sha256.empty())
        return true;
    const std::optional<std::string> sum = Sha256::ofFile(path);
    return sum && *sum == asset.sha256;
}

} // namespace

const UpdateAsset *UpdateRelease::asset(const std::string &suffix) const
{
    for (const UpdateAsset &a : assets)
        if (a.name.size() >= suffix.size() && a.name.compare(a.name.size() - suffix.size(), suffix.size(), suffix) == 0)
            return &a;
    return nullptr;
}

std::string AppUpdate::versionOfTag(const std::string &tag)
{
    const std::string text = !tag.empty() && tag.front() == 'v' ? tag.substr(1) : tag;
    return parts(text).empty() ? std::string() : text;
}

bool AppUpdate::isNewer(const std::string &version, const std::string &running)
{
    std::vector<long> a = parts(version), b = parts(running);
    if (a.empty() || b.empty())
        return false;
    a.resize(std::max(a.size(), b.size()), 0); // 1.1 == 1.1.0
    b.resize(a.size(), 0);
    return a > b;
}

std::optional<UpdateRelease> AppUpdate::latest()
{
    const char *custom = std::getenv("TUNEDCHAOS_UPDATE_URL");
    const HttpResponse response = HttpClient::get(custom && *custom ? custom : LatestUrl,
                                                  {"Accept: application/vnd.github+json"}, 15000);
    if (!response.ok())
        return std::nullopt;
    const json release = json::parse(response.body, nullptr, false);
    if (release.is_discarded() || !release.is_object())
        return std::nullopt;
    UpdateRelease out;
    out.version = versionOfTag(release.value("tag_name", std::string()));
    out.pageUrl = release.value("html_url", std::string());
    if (out.version.empty())
        return std::nullopt;
    if (const auto assets = release.find("assets"); assets != release.end() && assets->is_array())
        for (const json &item : *assets) {
            if (!item.is_object())
                continue;
            UpdateAsset a;
            a.name = item.value("name", std::string());
            a.url = item.value("browser_download_url", std::string());
            a.size = item.value("size", 0LL);
            const std::string digest = item.value("digest", std::string()); // "sha256:..."
            if (digest.rfind("sha256:", 0) == 0)
                a.sha256 = digest.substr(7);
            if (!a.name.empty() && !a.url.empty() && a.size > 0)
                out.assets.push_back(std::move(a));
        }
    return out;
}

std::string AppUpdate::download(const UpdateAsset &asset, const std::string &target, const std::atomic_bool &cancelled,
                                const std::function<void(int)> &progress)
{
    const std::string part = target + ".part";
    std::error_code ec;
    fs::create_directories(fs::path(target).parent_path(), ec);
    if (!fs::exists(target)) {
        if (fs::exists(part) && fs::file_size(part, ec) > (uintmax_t)asset.size)
            fs::remove(part, ec);
        // (A second go from the start if the server couldn't carry on from the part: it's removed then)
        for (int attempt = 0; attempt < 2 && (!fs::exists(part) || fs::file_size(part, ec) < (uintmax_t)asset.size);
             ++attempt) {
            const bool resuming = fs::exists(part);
            int shown = -1;
            const HttpResponse response = HttpClient::download(asset.url, part, [&](long long size) {
                const int percent = int(size * 100 / asset.size);
                if (percent != shown)
                    progress(shown = percent);
                return !cancelled.load();
            });
            if (cancelled.load())
                return {};
            if (response.ok())
                break;
            if (!resuming || fs::exists(part))
                return "The download failed. Try again.";
        }
        fs::rename(part, target, ec);
        if (ec)
            return "Couldn't save the download.";
    }
    // Also a copy from an earlier start: a damaged one must never be installed
    if (!complete(target, asset)) {
        fs::remove(target, ec);
        return "The download was damaged. Try again.";
    }
    return {};
}
