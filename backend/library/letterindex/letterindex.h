#pragma once

#include <string>

// The letter a name is filed under in the Library's letter groups (like the
// app lists of Windows phones): "A".."Z" (accents dropped: "É" is "E"), "#"
// for digits and symbols, Other for letters of other scripts (Bengali,
// Devanagari, Cyrillic...).
namespace LetterIndex {

inline constexpr const char *Other = "…";

std::string letterOf(const std::string &utf8Name);

} // namespace LetterIndex
