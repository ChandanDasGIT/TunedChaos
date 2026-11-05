#pragma once

#include <string>
#include <vector>

// One backup file holding the app's settings and data folders (settings,
// playlists, the Queue, history, moods, smart playlists, the library index,
// measured loudness, server accounts).
//
// The file: a first line "TUNEDCHAOS-BACKUP 1", then each file as a line
// "<folder>/<path>\t<size in bytes>" followed by exactly that many bytes.
// <folder> is "config" or "data"; paths use '/' and never go up ("..").
//
// Restoring can't write over the files while the app runs (it saves its own
// state as it quits), so restore() only puts them in a staging folder; the
// next start calls applyStaged() before anything reads them.
namespace BackupArchive {

struct Folders
{
    std::string config; // the app's settings folder
    std::string data;   // its data folder
};

// Writes every file of both folders to `file`. False (and `error` set) on failure.
bool create(const Folders &folders, const std::string &file, std::string &error);

// Checks `file` and unpacks it into `staging` (emptied first), with a note of
// `pid`, the process that has to end before the files are put in place.
// Returns the number of files, or -1 (and `error` set).
int restore(const std::string &file, const std::string &staging, long pid, std::string &error);

// A staged restore waiting: once process `pid` (from restore) has ended, or
// after a few seconds, moves the staged files over the folders' own and
// removes `staging`. True if a restore was applied.
bool applyStaged(const std::string &staging, const Folders &folders);

} // namespace BackupArchive
