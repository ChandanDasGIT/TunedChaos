#include "backend/update/sha256/sha256.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <memory>

namespace {

constexpr std::array<uint32_t, 64> K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

struct State
{
    std::array<uint32_t, 8> h = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

    void block(const unsigned char *p)
    {
        std::array<uint32_t, 64> w{};
        for (int i = 0; i < 16; ++i)
            w[size_t(i)] = uint32_t(p[i * 4]) << 24 | uint32_t(p[i * 4 + 1]) << 16 | uint32_t(p[i * 4 + 2]) << 8
                           | uint32_t(p[i * 4 + 3]);
        for (size_t i = 16; i < 64; ++i) {
            const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (size_t i = 0; i < 64; ++i) {
            const uint32_t t1 = hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
            const uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
            hh = g;
            g = f;
            f = e;
            e = d + t1;
            d = c;
            c = b;
            b = a;
            a = t1 + t2;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
};

} // namespace

std::optional<std::string> Sha256::ofFile(const std::string &path)
{
    std::unique_ptr<std::FILE, int (*)(std::FILE *)> file(std::fopen(path.c_str(), "rb"), &std::fclose);
    if (!file)
        return std::nullopt;
    State state;
    std::array<unsigned char, 64 * 1024> buffer{};
    uint64_t total = 0;
    size_t pending = 0; // bytes at the start of buffer not hashed yet (< 64)
    for (;;) {
        const size_t got = std::fread(buffer.data() + pending, 1, buffer.size() - pending, file.get());
        total += got;
        pending += got;
        size_t done = 0;
        for (; pending - done >= 64; done += 64)
            state.block(buffer.data() + done);
        for (size_t i = done; i < pending; ++i) // keep the tail at the start
            buffer[i - done] = buffer[i];
        pending -= done;
        if (got == 0)
            break;
    }
    if (std::ferror(file.get()))
        return std::nullopt;
    // Padding: 0x80, zeros, then the length in bits (big-endian)
    std::array<unsigned char, 128> tail{};
    for (size_t i = 0; i < pending; ++i)
        tail[i] = buffer[i];
    tail[pending] = 0x80;
    const size_t length = pending + 1 + 8 <= 64 ? 64 : 128;
    const uint64_t bits = total * 8;
    for (int i = 0; i < 8; ++i)
        tail[length - 1 - size_t(i)] = static_cast<unsigned char>(bits >> (8 * i));
    state.block(tail.data());
    if (length == 128)
        state.block(tail.data() + 64);

    static const char *digits = "0123456789abcdef";
    std::string hex;
    for (uint32_t word : state.h)
        for (int shift = 28; shift >= 0; shift -= 4)
            hex += digits[(word >> shift) & 0xF];
    return hex;
}
