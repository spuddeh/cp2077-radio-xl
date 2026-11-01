// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The byte dumps a failed check logs, so a moved site can be re-found from one launch.
// File Version: 0.9.0
// ======================================================================================
//
// A byte check that fails names the site, the bytes found and the bytes wanted, and the code around
// it is dumped once per function. Every reader here reads inside the game's own image.

#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <string>

namespace radioxl::diag
{

using LogFn = std::function<void(const std::string&)>;

// `aLen` bytes as upper-case hex pairs separated by spaces.
inline std::string Bytes(const uint8_t* aAt, size_t aLen)
{
    if (!aAt)
    {
        return "(null)";
    }
    std::string out;
    char hex[4];
    for (size_t i = 0; i < aLen; ++i)
    {
        std::snprintf(hex, sizeof(hex), i ? " %02X" : "%02X", aAt[i]);
        out += hex;
    }
    return out;
}

inline std::string Offset(size_t aOffset)
{
    char buf[24];
    std::snprintf(buf, sizeof(buf), "+0x%zX", aOffset);
    return buf;
}

// "found .. wanted ..", the found run as long as the wanted one.
inline std::string Mismatch(const uint8_t* aAt, const uint8_t* aWant, size_t aLen)
{
    return "found " + Bytes(aAt, aLen) + ", wanted " + Bytes(aWant, aLen);
}

// `aBase + aFrom` to `aBase + aTo`, 0x20 bytes a line, each line led by its offset from `aBase`.
inline void Region(const LogFn& aLog, const std::string& aLabel, const uint8_t* aBase, size_t aFrom, size_t aTo)
{
    if (!aLog || !aBase)
    {
        return;
    }
    for (size_t at = aFrom; at < aTo; at += 0x20)
    {
        const size_t len = aTo - at < 0x20 ? aTo - at : 0x20;
        aLog(aLabel + " " + Offset(at) + ": " + Bytes(aBase + at, len));
    }
}

} // namespace radioxl::diag
