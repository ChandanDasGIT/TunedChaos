#pragma once

#include <optional>
#include <string>

// SHA-256 of a file, as lowercase hex (FIPS 180-4). For checking downloads.
namespace Sha256 {

std::optional<std::string> ofFile(const std::string &path); // nothing if it can't be read

} // namespace Sha256
