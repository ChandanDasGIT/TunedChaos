#include "backend/hosted/hostedstore/hostedstore.h"

#include "backend/storage/tsv/tsv.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <random>
#include <system_error>

namespace fs = std::filesystem;

namespace {

constexpr const char *Header = "TunedChaos hosted v1";
constexpr size_t FieldCount = 8;

std::string hex(uint64_t value, int digits)
{
    static const char *chars = "0123456789abcdef";
    std::string out(size_t(digits), '0');
    for (int i = digits - 1; i >= 0; --i, value >>= 4)
        out[size_t(i)] = chars[value & 0xF];
    return out;
}

// A short name for an account that stays the same everywhere (FNV-1a of server and user).
std::string idFor(const HostedAccount &account)
{
    uint32_t hash = 2166136261u;
    for (const char c : account.kind + '\n' + account.serverUrl + '\n' + account.userId) {
        hash ^= static_cast<unsigned char>(c);
        hash *= 16777619u;
    }
    return hex(hash, 8);
}

std::string randomId()
{
    std::random_device device;
    return hex((uint64_t(device()) << 32) | device(), 16) + hex((uint64_t(device()) << 32) | device(), 16);
}

} // namespace

HostedStore::HostedStore(fs::path file)
    : m_file(std::move(file))
{
}

void HostedStore::load()
{
    std::lock_guard lock(m_mutex);
    m_accounts.clear();
    std::ifstream in(m_file);
    std::string line;
    if (in && std::getline(in, line) && line == Header) {
        while (std::getline(in, line)) {
            const std::vector<std::string> f = tsv::split(line);
            if (f.size() == 2 && f[0] == "device") {
                m_deviceId = tsv::unescape(f[1]);
                continue;
            }
            if (f.size() != FieldCount)
                continue;
            HostedAccount a;
            a.id = tsv::unescape(f[0]);
            a.kind = tsv::unescape(f[1]);
            a.serverUrl = tsv::unescape(f[2]);
            a.serverName = tsv::unescape(f[3]);
            a.userId = tsv::unescape(f[4]);
            a.userName = tsv::unescape(f[5]);
            a.token = tsv::unescape(f[6]);
            a.deviceId = tsv::unescape(f[7]);
            m_accounts.push_back(std::move(a));
        }
    }
    if (m_deviceId.empty())
        m_deviceId = randomId();
}

bool HostedStore::save() const
{
    std::error_code ec;
    fs::create_directories(m_file.parent_path(), ec);
    const fs::path temp = m_file.string() + ".tmp";
    {
        std::lock_guard lock(m_mutex);
        std::ofstream out(temp, std::ios::trunc);
        if (!out)
            return false;
        out << Header << '\n' << "device\t" << tsv::escape(m_deviceId) << '\n';
        for (const HostedAccount &a : m_accounts)
            out << tsv::escape(a.id) << '\t' << tsv::escape(a.kind) << '\t' << tsv::escape(a.serverUrl) << '\t'
                << tsv::escape(a.serverName) << '\t' << tsv::escape(a.userId) << '\t' << tsv::escape(a.userName)
                << '\t' << tsv::escape(a.token) << '\t' << tsv::escape(a.deviceId) << '\n';
        if (!out)
            return false;
    }
    // Only this user may read it (it holds sign-in tokens)
    fs::permissions(temp, fs::perms::owner_read | fs::perms::owner_write, fs::perm_options::replace, ec);
    fs::rename(temp, m_file, ec);
    return !ec;
}

std::string HostedStore::deviceId() const
{
    std::lock_guard lock(m_mutex);
    return m_deviceId;
}

std::vector<HostedAccount> HostedStore::accounts() const
{
    std::lock_guard lock(m_mutex);
    return m_accounts;
}

std::optional<HostedAccount> HostedStore::account(const std::string &id) const
{
    std::lock_guard lock(m_mutex);
    const auto it = std::find_if(m_accounts.begin(), m_accounts.end(), [&](const HostedAccount &a) { return a.id == id; });
    if (it == m_accounts.end())
        return std::nullopt;
    return *it;
}

HostedAccount HostedStore::add(HostedAccount account)
{
    account.id = idFor(account);
    std::lock_guard lock(m_mutex);
    const auto it = std::find_if(m_accounts.begin(), m_accounts.end(), [&](const HostedAccount &a) { return a.id == account.id; });
    if (it != m_accounts.end())
        *it = account;
    else
        m_accounts.push_back(account);
    return account;
}

void HostedStore::remove(const std::string &id)
{
    std::lock_guard lock(m_mutex);
    m_accounts.erase(std::remove_if(m_accounts.begin(), m_accounts.end(), [&](const HostedAccount &a) { return a.id == id; }),
                     m_accounts.end());
}

std::string HostedStore::streamUrl(const std::string &path) const
{
    const std::optional<HostedAccount> a = account(HostedPath::accountId(path));
    if (!a)
        return {};
    const std::unique_ptr<HostedServer> server = HostedServer::open(*a);
    return server ? server->streamUrl(HostedPath::songId(path)) : std::string();
}

std::string HostedStore::coverUrl(const std::string &accountId, const std::string &itemId, int size) const
{
    const std::optional<HostedAccount> a = account(accountId);
    if (!a || itemId.empty())
        return {};
    const std::unique_ptr<HostedServer> server = HostedServer::open(*a);
    return server ? server->coverUrl(itemId, size) : std::string();
}
