#include "backuparchive.h"

#include <chrono>
#include <cstdint>
#include <iterator>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#endif

namespace fs = std::filesystem;

namespace BackupArchive {

namespace {

constexpr const char *Magic = "TUNEDCHAOS-BACKUP 1";
constexpr const char *PidFile = ".restore-pid";
constexpr std::uintmax_t MaxFileSize = 512ull * 1024 * 1024; // a sanity limit per file

bool processAlive(long pid)
{
    if (pid <= 0)
        return false;
#ifdef _WIN32
    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid));
    if (!process)
        return false;
    const bool alive = WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
    CloseHandle(process);
    return alive;
#else
    return ::kill(static_cast<pid_t>(pid), 0) == 0 || errno == EPERM;
#endif
}

// A stored path is safe: relative, '/'-separated, inside config/ or data/, never ".."
bool safePath(const std::string &path)
{
    if (path.rfind("config/", 0) != 0 && path.rfind("data/", 0) != 0)
        return false;
    if (path.find('\\') != std::string::npos || path.find('\0') != std::string::npos)
        return false;
    std::stringstream parts(path);
    std::string part;
    while (std::getline(parts, part, '/')) {
        if (part.empty() || part == "." || part == "..")
            return false;
    }
    return path.back() != '/';
}

void addFolder(const std::string &root, const std::string &name, std::vector<std::pair<std::string, fs::path>> &out)
{
    std::error_code ec;
    if (root.empty() || !fs::is_directory(root, ec))
        return;
    for (auto it = fs::recursive_directory_iterator(root, ec); !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
        if (!it->is_regular_file(ec))
            continue;
        const std::string relative = fs::relative(it->path(), root, ec).generic_string();
        if (ec || relative.empty())
            continue;
        out.emplace_back(name + '/' + relative, it->path());
    }
}

// Owner-only: the files hold server sign-ins
void ownerOnly(const fs::path &path)
{
    std::error_code ec;
    fs::permissions(path, fs::perms::owner_read | fs::perms::owner_write, fs::perm_options::replace, ec);
}

} // namespace

bool create(const Folders &folders, const std::string &file, std::string &error)
{
    std::vector<std::pair<std::string, fs::path>> files;
    addFolder(folders.config, "config", files);
    addFolder(folders.data, "data", files);
    if (files.empty()) {
        error = "nothing to back up";
        return false;
    }

    const std::string partial = file + ".partial";
    {
        std::ofstream out(partial, std::ios::binary | std::ios::trunc);
        if (!out) {
            error = "can't write " + file;
            return false;
        }
        out << Magic << '\n';
        for (const auto &[name, path] : files) {
            std::ifstream in(path, std::ios::binary);
            if (!in)
                continue; // gone meanwhile
            const std::string bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            out << name << '\t' << bytes.size() << '\n';
            out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
        }
        out.flush();
        if (!out) {
            error = "can't write " + file;
            return false;
        }
    }
    ownerOnly(partial);
    std::error_code ec;
    fs::rename(partial, file, ec);
    if (ec) {
        fs::remove(partial, ec);
        error = "can't write " + file;
        return false;
    }
    return true;
}

int restore(const std::string &file, const std::string &staging, long pid, std::string &error)
{
    std::ifstream in(file, std::ios::binary);
    std::string line;
    if (!in || !std::getline(in, line) || line != Magic) {
        error = "not a Tuned Chaos backup";
        return -1;
    }

    // Read it all first: a damaged file changes nothing
    std::vector<std::pair<std::string, std::string>> files;
    while (std::getline(in, line)) {
        const size_t tab = line.rfind('\t');
        if (tab == std::string::npos) {
            error = "the backup is damaged";
            return -1;
        }
        const std::string name = line.substr(0, tab);
        std::uintmax_t size = 0;
        try {
            size = std::stoull(line.substr(tab + 1));
        } catch (...) {
            error = "the backup is damaged";
            return -1;
        }
        if (!safePath(name) || size > MaxFileSize) {
            error = "the backup is damaged";
            return -1;
        }
        std::string bytes(size, '\0');
        if (size > 0 && !in.read(bytes.data(), static_cast<std::streamsize>(size))) {
            error = "the backup is damaged (cut short)";
            return -1;
        }
        files.emplace_back(name, std::move(bytes));
    }
    if (files.empty()) {
        error = "the backup is empty";
        return -1;
    }

    std::error_code ec;
    fs::remove_all(staging, ec);
    for (const auto &[name, bytes] : files) {
        const fs::path target = fs::path(staging) / fs::path(name);
        fs::create_directories(target.parent_path(), ec);
        std::ofstream out(target, std::ios::binary | std::ios::trunc);
        out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
        out.close();
        ownerOnly(target);
        if (!out) {
            fs::remove_all(staging, ec);
            error = "can't unpack the backup";
            return -1;
        }
    }
    std::ofstream(fs::path(staging) / PidFile) << pid << '\n';
    return static_cast<int>(files.size());
}

bool applyStaged(const std::string &staging, const Folders &folders)
{
    std::error_code ec;
    if (staging.empty() || !fs::is_directory(staging, ec))
        return false;

    // The copy that staged it saves its own files as it quits: wait for it
    long pid = 0;
    std::ifstream(fs::path(staging) / PidFile) >> pid;
    for (int i = 0; i < 100 && processAlive(pid); ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // The backup replaces the folders' contents (what it doesn't have goes)
    for (const auto &[name, root] : {std::pair<std::string, std::string>{"config", folders.config},
                                     std::pair<std::string, std::string>{"data", folders.data}}) {
        const fs::path from = fs::path(staging) / name;
        if (root.empty() || !fs::is_directory(from, ec))
            continue;
        for (auto it = fs::directory_iterator(root, ec); !ec && it != fs::directory_iterator(); it.increment(ec))
            fs::remove_all(it->path(), ec);
        fs::create_directories(root, ec);
        for (auto it = fs::recursive_directory_iterator(from, ec); !ec && it != fs::recursive_directory_iterator();
             it.increment(ec)) {
            const fs::path target = fs::path(root) / fs::relative(it->path(), from, ec);
            if (it->is_directory(ec))
                fs::create_directories(target, ec);
            else if (fs::copy_file(it->path(), target, fs::copy_options::overwrite_existing, ec))
                ownerOnly(target);
        }
    }
    fs::remove_all(staging, ec);
    return true;
}

} // namespace BackupArchive
