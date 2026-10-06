// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Broadcast channels of their own for each custom station, past 255.
// File Version: 0.8.0
// ======================================================================================
//
// **Every receiver hears a station through three broadcast channels**, set as RTPCs on the
// station's emitter and on each receiver's: `radio_broadcast_channel` (the mono send, world
// devices), `_right` and `_left` (the stereo send, the Radioport and cars). The engine derives them
// from the station's internal id as id, id + 50 and id + 220, and the game's own sources fill 222 of
// the first 256 channels. Broadcast.hpp widens the broadcaster to 1024 channels; this gives each
// custom station three channels from 256 up, where nothing else broadcasts, and the five places that
// set a station's channels read them from `g_table` instead of the formula. Every other id keeps the
// formula's values in the table, so nothing changes for the game's own stations.
//
// Each site is the 5-byte `cvtsi2ss xmmN, reg` that turns the channel into the RTPC's float. It
// is replaced by a call to a stub that reads the station id from the register the function keeps
// it in (r14, r15 or rbp, all preserved across the calls in between), looks the channel up and
// does the conversion itself. The stub preserves every register and the flags but the target xmm.

#pragma once

#include <Windows.h>

#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

namespace radioxl::channels
{

enum Kind : int
{
    kMono = 0,
    kRight = 1,
    kLeft = 2,
};

constexpr int kOffset[3] = {0, 0x32, 0xdc};
constexpr int kFirstWide = 256;  // the first channel past the game's own

// The channel each internal id plays on, per kind. Read by the stubs, written only here.
alignas(64) inline int32_t g_table[3][256];

inline std::vector<int> g_ids;  // each custom station's internal id, in roster order
inline int g_assigned = 0;      // custom stations with channels of their own
inline std::function<void(const std::string&)> g_log;

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("channels: " + aText);
    }
}

inline std::string Describe()
{
    std::string line;
    for (int i = 0; i < g_assigned; ++i)
    {
        const int id = g_ids[i];
        line += (line.empty() ? "" : ", ") + std::to_string(id) + "=" + std::to_string(g_table[kMono][id]) + "/" +
                std::to_string(g_table[kRight][id]) + "/" + std::to_string(g_table[kLeft][id]);
    }
    return line;
}

// The formula for every id, then three channels from 256 up for each custom station, in roster order.
inline void Init(const std::vector<int>& aIds, int aChannels, std::function<void(const std::string&)> aLog)
{
    g_log = std::move(aLog);
    g_ids = aIds;
    for (int k = 0; k < 3; ++k)
    {
        for (int id = 0; id < 256; ++id)
        {
            g_table[k][id] = id + kOffset[k];
        }
    }
    g_assigned = 0;
    int channel = kFirstWide;
    for (const int id : g_ids)
    {
        if (id > 255 || channel + 3 > aChannels)
        {
            break;
        }
        g_table[kMono][id] = channel++;
        g_table[kRight][id] = channel++;
        g_table[kLeft][id] = channel++;
        ++g_assigned;
    }
    if (g_assigned < static_cast<int>(g_ids.size()))
    {
        Log(std::to_string(static_cast<int>(g_ids.size()) - g_assigned) +
            " custom station(s) found no channels past 255 and keep the formula's");
    }
}

// --- the patch -------------------------------------------------------------------------------

struct Site
{
    uint32_t hash;        // the function, by RED4ext hash
    const char* what;
    size_t offset;        // the cvtsi2ss, from the function start
    uint8_t modrm;        // its ModRM byte, which names the xmm and the source register
    uint8_t rex;          // its REX byte (0x48 or 0x49)
    Kind kind;
    uint8_t idReg;        // where the function keeps the station id: 14 = r14, 15 = r15, 5 = rbp
    uint8_t xmm;          // the xmm the RTPC value goes to
    size_t leaOffset;     // right and left: the `lea` that adds the offset to the id, 0 for mono
    uint8_t lea[3];       // its first bytes, which name the id register
    uint8_t leaLen;
};

// 2.31. Each function computes mono, then right (id + 0x32), then left (id + 0xdc), and converts
// each with the cvtsi2ss below.
constexpr uint32_t kHashAnnouncement = 2113936565;  // 0x6bb690 audio::RadioStation::HandleAnnouncementVO
constexpr uint32_t kHashPlaySong = 2091323364;      // 0x6bc5e0 audio::RadioStation::PlaySong
constexpr uint32_t kHashStationInit = 1637816450;   // 0x6bc88c audio::RadioStation::Init
constexpr uint32_t kHashEmitterParam = 682629967;   // 0x9da6bc audio::RadioEmitter::SetBroadcastChannelParam
constexpr uint32_t kHashEmitterPost = 70520146;     // 0x219a45c an emitter's song post, unnamed

constexpr Site kSites[] = {
    {kHashAnnouncement, "HandleAnnouncementVO mono", 0x0b8, 0xF6, 0x49, kMono, 14, 6, 0, {}, 0},
    {kHashAnnouncement, "HandleAnnouncementVO right", 0x0e9, 0xF1, 0x48, kRight, 14, 6, 0x0d8, {0x41, 0x8D, 0x4E}, 3},
    {kHashAnnouncement, "HandleAnnouncementVO left", 0x11d, 0xF1, 0x48, kLeft, 14, 6, 0x109, {0x41, 0x8D, 0x8E}, 3},
    {kHashPlaySong, "PlaySong mono", 0x0fe, 0xFF, 0x49, kMono, 15, 7, 0, {}, 0},
    {kHashPlaySong, "PlaySong right", 0x154, 0xF9, 0x48, kRight, 15, 7, 0x140, {0x41, 0x8D, 0x4F}, 3},
    {kHashPlaySong, "PlaySong left", 0x1aa, 0xF9, 0x48, kLeft, 15, 7, 0x193, {0x41, 0x8D, 0x8F}, 3},
    {kHashStationInit, "Init mono", 0x112, 0xFE, 0x49, kMono, 14, 7, 0, {}, 0},
    {kHashStationInit, "Init right", 0x16b, 0xF9, 0x48, kRight, 14, 7, 0x157, {0x41, 0x8D, 0x4E}, 3},
    {kHashStationInit, "Init left", 0x1c4, 0xF9, 0x48, kLeft, 14, 7, 0x1ad, {0x41, 0x8D, 0x8E}, 3},
    {kHashEmitterParam, "SetBroadcastChannelParam mono", 0x05d, 0xD5, 0x48, kMono, 5, 2, 0, {}, 0},
    {kHashEmitterParam, "SetBroadcastChannelParam right", 0x0b9, 0xD2, 0x48, kRight, 5, 2, 0x0a7, {0x8D, 0x55}, 2},
    {kHashEmitterParam, "SetBroadcastChannelParam left", 0x108, 0xD2, 0x48, kLeft, 5, 2, 0x0f3, {0x8D, 0x95}, 2},
    {kHashEmitterPost, "emitter post mono", 0x12f, 0xFF, 0x49, kMono, 15, 7, 0, {}, 0},
    {kHashEmitterPost, "emitter post right", 0x197, 0xF9, 0x48, kRight, 15, 7, 0x183, {0x41, 0x8D, 0x4F}, 3},
    {kHashEmitterPost, "emitter post left", 0x1ff, 0xF9, 0x48, kLeft, 15, 7, 0x1e8, {0x41, 0x8D, 0x8F}, 3},
};
constexpr size_t kSiteCount = sizeof(kSites) / sizeof(kSites[0]);

constexpr size_t kStubSize = 48;

//   pushfq
//   push rax
//   mov  eax, <id>              44 89 F0 (r14d) | 44 89 F8 (r15d) | 89 E8 (ebp)
//   cmp  eax, 255
//   ja   formula
//   push rcx
//   mov  rcx, &g_table[kind]
//   mov  eax, [rcx+rax*4]
//   pop  rcx
//   jmp  convert
// formula:
//   add  eax, offset
// convert:
//   cvtsi2ss xmmN, rax
//   pop  rax
//   popfq
//   ret
inline size_t BuildStub(uint8_t* aOut, const Site& aSite)
{
    uint8_t* p = aOut;
    *p++ = 0x9C;
    *p++ = 0x50;
    if (aSite.idReg == 14)
    {
        *p++ = 0x44; *p++ = 0x89; *p++ = 0xF0;
    }
    else if (aSite.idReg == 15)
    {
        *p++ = 0x44; *p++ = 0x89; *p++ = 0xF8;
    }
    else
    {
        *p++ = 0x89; *p++ = 0xE8;
    }
    *p++ = 0x3D; *p++ = 0xFF; *p++ = 0x00; *p++ = 0x00; *p++ = 0x00;
    *p++ = 0x77; *p++ = 0x11;  // over the 17 bytes of the lookup
    *p++ = 0x51;
    *p++ = 0x48; *p++ = 0xB9;
    const uint64_t table = reinterpret_cast<uint64_t>(&g_table[aSite.kind][0]);
    std::memcpy(p, &table, sizeof(table));
    p += sizeof(table);
    *p++ = 0x8B; *p++ = 0x04; *p++ = 0x81;
    *p++ = 0x59;
    *p++ = 0xEB; *p++ = 0x05;  // over the add
    *p++ = 0x05;
    const int32_t offset = kOffset[aSite.kind];
    std::memcpy(p, &offset, sizeof(offset));
    p += sizeof(offset);
    *p++ = 0xF3; *p++ = 0x48; *p++ = 0x0F; *p++ = 0x2A; *p++ = static_cast<uint8_t>(0xC0 | (aSite.xmm << 3));
    *p++ = 0x58;
    *p++ = 0x9D;
    *p++ = 0xC3;
    return static_cast<size_t>(p - aOut);
}

using ResolveFn = uintptr_t (*)(uint32_t);
using AllocateFn = void* (*)(uintptr_t, size_t);
using WriteFn = bool (*)(void*, const void*, size_t);

// Verifies all fifteen sites, builds every stub, and only then writes the calls. Any mismatch
// leaves the game on the formula.
inline bool Patch(ResolveFn aResolve, AllocateFn aAllocate, WriteFn aWrite)
{
    uint8_t* at[kSiteCount] = {};
    for (size_t i = 0; i < kSiteCount; ++i)
    {
        const Site& s = kSites[i];
        const auto fn = reinterpret_cast<uint8_t*>(aResolve(s.hash));
        if (!fn)
        {
            Log(std::string("could not resolve ") + s.what + " - channels left on the formula");
            return false;
        }
        at[i] = fn + s.offset;
        const uint8_t want[] = {0xF3, s.rex, 0x0F, 0x2A, s.modrm};
        const bool leaOk = s.leaLen == 0 || std::memcmp(fn + s.leaOffset, s.lea, s.leaLen) == 0;
        if (std::memcmp(at[i], want, sizeof(want)) != 0 || !leaOk)
        {
            Log(std::string("byte check FAILED at ") + s.what + " - channels left on the formula");
            return false;
        }
    }

    auto* block = static_cast<uint8_t*>(aAllocate(reinterpret_cast<uintptr_t>(at[0]), kSiteCount * kStubSize));
    if (!block)
    {
        Log("could not allocate the channel stubs within reach - channels left on the formula");
        return false;
    }
    uint8_t call[kSiteCount][5];
    for (size_t i = 0; i < kSiteCount; ++i)
    {
        uint8_t* stub = block + i * kStubSize;
        BuildStub(stub, kSites[i]);
        const int64_t d = reinterpret_cast<int64_t>(stub) - reinterpret_cast<int64_t>(at[i] + 5);
        if (d > INT32_MAX || d < INT32_MIN)
        {
            Log(std::string("the stub for ") + kSites[i].what + " is out of reach - channels left on the formula");
            return false;
        }
        const int32_t rel = static_cast<int32_t>(d);
        call[i][0] = 0xE8;
        std::memcpy(&call[i][1], &rel, sizeof(rel));
    }
    DWORD old = 0;
    if (!VirtualProtect(block, kSiteCount * kStubSize, PAGE_EXECUTE_READ, &old))
    {
        Log("could not make the channel stubs executable - channels left on the formula");
        return false;
    }
    FlushInstructionCache(GetCurrentProcess(), block, kSiteCount * kStubSize);

    for (size_t i = 0; i < kSiteCount; ++i)
    {
        if (!aWrite(at[i], call[i], sizeof(call[i])))
        {
            Log(std::string("a write failed at ") + kSites[i].what + " - restart the game");
            return false;
        }
    }
    Log("fifteen sites patched; custom station channels (id=mono/right/left): " + Describe());
    return true;
}

} // namespace radioxl::channels
