#include "backend/library/letterindex/letterindex.h"

#include <cstdint>

namespace {

// The first character as a code point (0 for none / invalid).
char32_t firstCodePoint(const std::string &s, size_t &pos)
{
    while (pos < s.size() && (s[pos] == ' ' || s[pos] == '\t'))
        ++pos; // leading blanks don't count
    if (pos >= s.size())
        return 0;
    const auto c = static_cast<unsigned char>(s[pos]);
    int extra = c < 0x80 ? 0 : (c >> 5) == 0x6 ? 1 : (c >> 4) == 0xE ? 2 : (c >> 3) == 0x1E ? 3 : -1;
    if (extra < 0 || pos + size_t(extra) >= s.size() + 1 - (extra > 0 ? 1 : 0))
        return 0; // invalid, or cut off
    char32_t cp = extra == 0 ? c : extra == 1 ? (c & 0x1F) : extra == 2 ? (c & 0x0F) : (c & 0x07);
    for (int i = 1; i <= extra; ++i)
        cp = (cp << 6) | (static_cast<unsigned char>(s[pos + size_t(i)]) & 0x3F);
    return cp;
}

// Latin letters with accents (Latin-1 Supplement and Latin Extended-A) to their base letter.
char latinBase(char32_t cp)
{
    if (cp >= 'a' && cp <= 'z')
        return char(cp - 'a' + 'A');
    if (cp >= 'A' && cp <= 'Z')
        return char(cp);
    static const char *latin1 = // U+00C0 .. U+00FF
        "AAAAAAACEEEEIIII" "DNOOOOO*OUUUUYTS" "AAAAAAACEEEEIIII" "DNOOOOO/OUUUUYTY";
    if (cp >= 0xC0 && cp <= 0xFF) {
        const char base = latin1[cp - 0xC0];
        return base >= 'A' && base <= 'Z' ? base : 0;
    }
    static const char *extendedA = // U+0100 .. U+017F, in pairs (capital, small)
        "AAAAAACCCCCCCCDDDDEEEEEEEEEEGGGGGGGGHHHHIIIIIIIIIIIIJJKKKLLLLLLLLLLNNNNNNNNNOOOOOOOORRRRRRSSSSSSSSTTTTTTUUUUUUUUUUUUWWYYYZZZZZZS";
    if (cp >= 0x100 && cp <= 0x17F)
        return extendedA[cp - 0x100];
    return 0;
}

} // namespace

std::string LetterIndex::letterOf(const std::string &utf8Name)
{
    size_t pos = 0;
    const char32_t cp = firstCodePoint(utf8Name, pos);
    if (cp == 0)
        return "#";
    if (const char base = latinBase(cp))
        return std::string(1, base);
    // Other scripts' letters (roughly: past the Latin blocks, except punctuation and symbols)
    const bool symbol = cp < 0x250 || (cp >= 0x2000 && cp <= 0x2BFF) || (cp >= 0x3000 && cp <= 0x303F)
                        || (cp >= 0xFE00 && cp <= 0xFE6F) || (cp >= 0xFF00 && cp <= 0xFF20)
                        || (cp >= 0x1F000 && cp <= 0x1FAFF);
    return symbol ? "#" : LetterIndex::Other;
}
