#pragma once

#include "backend/hosted/hostedserver/hostedserver.h"

#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// The servers signed in to (tab-separated text in the app's config folder):
// their sign-in tokens, never passwords. Also this device's id for servers.
// Thread-safe: the player asks for stream addresses from its own thread.
class HostedStore
{
public:
    explicit HostedStore(std::filesystem::path file);

    void load();
    bool save() const;

    std::string deviceId() const; // made once, then kept

    std::vector<HostedAccount> accounts() const;
    std::optional<HostedAccount> account(const std::string &id) const;
    // Adds it (or replaces the same user on the same server); gives it its id.
    HostedAccount add(HostedAccount account);
    void remove(const std::string &id);

    // Where a "hosted:" song streams from ("" if its server is gone).
    std::string streamUrl(const std::string &path) const;
    // A picture of one of its items ("" if none / unknown server).
    std::string coverUrl(const std::string &accountId, const std::string &itemId, int size) const;

private:
    std::filesystem::path m_file;
    mutable std::mutex m_mutex;
    std::string m_deviceId;
    std::vector<HostedAccount> m_accounts;
};
