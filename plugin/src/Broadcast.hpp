// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Broadcast channels past 255, so custom stations share a channel with nothing.
// File Version: 0.8.0
// ======================================================================================
//
// **Every broadcast source shares 256 channels**: radio stations, TVs, world playlists, reflections and
// over a hundred scene, music and ambience sounds whose channel is fixed in their bank. Two sources on
// one channel are heard together. Two limits hold the space at 256, and this lifts both:
//
// 1. **The plugin's table.** `CDPVoiceBroadcaster` keeps, in one static object, a frame toggle (`+0`),
//    the frame count (`+2`), a u16 reference count per channel (`+4`) and a buffer pointer per channel
//    (`+0x208`). Its send, receive, register and unregister functions bound the channel at 256, and the
//    pointer table sits straight after 256 counts. A copy of the object with room for `kChannels` of
//    each replaces it: `GetInstance` returns the copy, every `+0x208` displacement becomes `+0x808`,
//    every bound becomes `kChannels`, and the per-frame swap is replaced by `Swap` below, which clears
//    the copy's buffers the same way.
// 2. **The curves.** Every send and receiver maps its channel game parameter on a curve ending at 255,
//    and holds any higher value at 255. The bank loader's curve setter is hooked, and a curve that is
//    exactly (0,0)-(255,255) on one of the three radio channel parameters is loaded as
//    (0,0)-(kChannels-1, kChannels-1). Values up to 255 map as before; the TV curve and every other
//    shape are untouched.
//
// Both run at plugin load, before Wwise starts, and only when every byte checks out.

#pragma once

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

namespace radioxl::broadcast
{

constexpr uint32_t kChannels = 1024;
constexpr uint32_t kOldTable = 0x208;
constexpr uint32_t kNewTable = 0x808;  // +4 plus 1024 two-byte counts, rounded to 8
constexpr size_t kObjectSize = kNewTable + kChannels * sizeof(void*);

constexpr uint32_t kHashGetInstance = 1727598446;     // 0x1be6d10
constexpr uint32_t kHashReceive = 3591902795;         // 0x1be6d20
constexpr uint32_t kHashReceiveStereo = 2386893062;   // 0x1be6d70
constexpr uint32_t kHashRegister = 482807247;         // 0x1be6e60
constexpr uint32_t kHashSend = 1181621829;            // 0x1be6e70
constexpr uint32_t kHashSendStereo = 1069883648;      // 0x1be7000
constexpr uint32_t kHashUnregister = 960698264;       // 0x1be7200
constexpr uint32_t kHashSwap = 39265186;              // 0x1be6ca0
constexpr uint32_t kHashCurveLoader = 3699780356;     // 0x1b08bf0

// The three radio channel parameters, as Wwise ids (FNV-1 32 of the lower-case name).
constexpr uint32_t kRtpcMono = 3643107758;   // radio_broadcast_channel
constexpr uint32_t kRtpcRight = 2368727641;  // radio_broadcast_channel_right
constexpr uint32_t kRtpcLeft = 975869506;    // radio_broadcast_channel_left

enum Fn : int
{
    kReceive,
    kReceiveStereo,
    kRegister,
    kSend,
    kSendStereo,
    kUnregister,
    kFnCount
};
constexpr uint32_t kFnHash[kFnCount] = {kHashReceive, kHashReceiveStereo, kHashRegister,
                                        kHashSend, kHashSendStereo, kHashUnregister};

// An immediate to rewrite: the instruction's first bytes, where the immediate starts, its value now and after.
struct Bound
{
    Fn fn;
    size_t offset;
    uint8_t lead[3];
    uint8_t leadLen;
    size_t immAt;
    uint32_t from;
    uint32_t to;
};
constexpr Bound kBounds[] = {
    {kReceive, 0x00, {0x81, 0xFA}, 2, 2, 0x100, kChannels},
    {kReceiveStereo, 0x00, {0x81, 0xFA}, 2, 2, 0x100, kChannels},
    {kReceiveStereo, 0x14, {0x41, 0x81, 0xF8}, 3, 3, 0x100, kChannels},
    {kRegister, 0x00, {0x81, 0xFA}, 2, 2, 0x100, kChannels},
    {kSend, 0x00, {0x81, 0xFA}, 2, 2, 0x100, kChannels},
    {kSendStereo, 0x00, {0x81, 0xFA}, 2, 2, 0x100, kChannels},
    {kSendStereo, 0x1e, {0x41, 0x81, 0xF8}, 3, 3, 0x100, kChannels},
    {kUnregister, 0x0c, {0x3D}, 1, 1, 0xFE, kChannels - 2},  // (channel - 1) <= this
};

// Each `[base + index*8 + 0x208]`; the displacement is the four bytes at +4.
struct Disp
{
    Fn fn;
    size_t offset;
};
constexpr Disp kDisps[] = {
    {kReceive, 0x1e},
    {kReceiveStereo, 0x5d}, {kReceiveStereo, 0x6b},
    {kSend, 0x43}, {kSend, 0x73}, {kSend, 0x91},
    {kSendStereo, 0x68}, {kSendStereo, 0x8b}, {kSendStereo, 0xa9}, {kSendStereo, 0xcd}, {kSendStereo, 0xeb},
    {kSendStereo, 0xf6},
    {kUnregister, 0x26}, {kUnregister, 0x3c},
};

inline std::function<void(const std::string&)> g_log;
inline uint8_t* g_object = nullptr;
inline bool g_widened = false;
inline std::atomic<uint32_t> g_curvesWidened{0};

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("broadcast: " + aText);
    }
}

// What CDPVoiceBroadcastSwapBuffers does, over every channel: flip the frame toggle and clear the half
// of each live buffer that the new frame writes into.
inline void Swap(void*, int, void*)
{
    uint8_t* o = g_object;
    const uint8_t toggle = o[0] == 0 ? 1 : 0;
    o[0] = toggle;
    const uint16_t frames = *reinterpret_cast<uint16_t*>(o + 2);
    auto** table = reinterpret_cast<float**>(o + kNewTable);
    for (uint32_t i = 0; i < kChannels; ++i)
    {
        if (float* buffer = table[i])
        {
            std::memset(buffer + static_cast<size_t>(frames) * toggle, 0, static_cast<size_t>(frames) * sizeof(float));
        }
    }
}

// --- the curves ---------------------------------------------------------------------------------

struct GraphPoint
{
    float from;
    float to;
    uint32_t interp;
};

// The curve loader's description of one curve, as 0x1b08bf0 reads it.
struct CurveDesc
{
    uint8_t type;
    uint8_t accum;
    uint8_t scaling;
    uint8_t pad;
    uint32_t rtpc;
    uint32_t param;
    uint32_t curve;
    uint32_t count;
};

using CurveLoaderFn = int (*)(void*, uint32_t, uint64_t, CurveDesc*, GraphPoint*, void**);
inline CurveLoaderFn g_origCurveLoader = nullptr;

// The mix switches (Mix.hpp) see every curve through the same hook: which switched curve it is, the
// points to load for it, and the entry the loader stored.
inline int (*g_mixMatch)(uint32_t, const CurveDesc*) = nullptr;
inline const GraphPoint* (*g_mixPoints)(int, const CurveDesc*, const GraphPoint*, std::vector<GraphPoint>&) = nullptr;
inline void (*g_mixRemember)(int, const CurveDesc*, const GraphPoint*, uintptr_t) = nullptr;

inline int CurveLoader(void* aContainer, uint32_t aTarget, uint64_t aUnused, CurveDesc* aDesc, GraphPoint* aPoints,
                       void** aOut)
{
    if (aDesc && aPoints && aDesc->count == 2 &&
        (aDesc->rtpc == kRtpcMono || aDesc->rtpc == kRtpcRight || aDesc->rtpc == kRtpcLeft) &&
        aPoints[0].from == 0.0f && aPoints[0].to == 0.0f && aPoints[1].from == 255.0f && aPoints[1].to == 255.0f)
    {
        GraphPoint wide[2] = {aPoints[0], aPoints[1]};
        wide[1].from = static_cast<float>(kChannels - 1);
        wide[1].to = static_cast<float>(kChannels - 1);
        const uint32_t n = g_curvesWidened.fetch_add(1) + 1;
        if (n <= 3 || n % 100 == 0)
        {
            Log("curve " + std::to_string(n) + " widened (parameter " + std::to_string(aDesc->rtpc) + ")");
        }
        return g_origCurveLoader(aContainer, aTarget, aUnused, aDesc, wide, aOut);
    }
    const int mix = (g_mixMatch && aDesc && aPoints) ? g_mixMatch(aTarget, aDesc) : -1;
    if (mix < 0)
    {
        return g_origCurveLoader(aContainer, aTarget, aUnused, aDesc, aPoints, aOut);
    }
    std::vector<GraphPoint> flat;
    void* entry = nullptr;
    void** out = aOut ? aOut : &entry;
    const int result = g_origCurveLoader(aContainer, aTarget, aUnused, aDesc,
                                         const_cast<GraphPoint*>(g_mixPoints(mix, aDesc, aPoints, flat)), out);
    if ((result == 1 || result == 3) && *out)
    {
        g_mixRemember(mix, aDesc, aPoints, reinterpret_cast<uintptr_t>(*out));
    }
    return result;
}

using ResolveFn = uintptr_t (*)(uint32_t);
using WriteFn = bool (*)(void*, const void*, size_t);

// Verifies every site, builds the new object, then writes. Any mismatch leaves the plugin as it was.
inline bool Widen(ResolveFn aResolve, WriteFn aWrite, const RED4ext::v1::Sdk* aSdk, RED4ext::v1::PluginHandle aHandle)
{
    uint8_t* fn[kFnCount] = {};
    for (int i = 0; i < kFnCount; ++i)
    {
        fn[i] = reinterpret_cast<uint8_t*>(aResolve(kFnHash[i]));
        if (!fn[i])
        {
            Log("a broadcaster function did not resolve - left at 256 channels");
            return false;
        }
    }
    auto* getInstance = reinterpret_cast<uint8_t*>(aResolve(kHashGetInstance));
    auto* swap = reinterpret_cast<uint8_t*>(aResolve(kHashSwap));
    auto* curveLoader = reinterpret_cast<uint8_t*>(aResolve(kHashCurveLoader));
    if (!getInstance || !swap || !curveLoader)
    {
        Log("GetInstance, the swap or the curve loader did not resolve - left at 256 channels");
        return false;
    }

    // GetInstance: lea rax, [rip+disp32]; ret - followed by int3 padding to 16 bytes.
    const uint8_t getLead[] = {0x48, 0x8D, 0x05};
    if (std::memcmp(getInstance, getLead, sizeof(getLead)) != 0 || getInstance[7] != 0xC3 || getInstance[8] != 0xCC ||
        getInstance[11] != 0xCC)
    {
        Log("byte check FAILED at GetInstance - left at 256 channels");
        return false;
    }
    int32_t rel = 0;
    std::memcpy(&rel, getInstance + 3, sizeof(rel));
    uint8_t* original = getInstance + 7 + rel;

    for (const Bound& b : kBounds)
    {
        uint32_t imm = 0;
        std::memcpy(&imm, fn[b.fn] + b.offset + b.immAt, sizeof(imm));
        if (std::memcmp(fn[b.fn] + b.offset, b.lead, b.leadLen) != 0 || imm != b.from)
        {
            Log("byte check FAILED at a channel bound - left at 256 channels");
            return false;
        }
    }
    for (const Disp& d : kDisps)
    {
        uint32_t disp = 0;
        std::memcpy(&disp, fn[d.fn] + d.offset + 4, sizeof(disp));
        if (disp != kOldTable)
        {
            Log("byte check FAILED at a table displacement - left at 256 channels");
            return false;
        }
    }
    const uint8_t swapLead[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83, 0xEC, 0x20};
    if (std::memcmp(swap, swapLead, sizeof(swapLead)) != 0)
    {
        Log("byte check FAILED at the buffer swap - left at 256 channels");
        return false;
    }
    const uint8_t loaderLead[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x6C, 0x24, 0x10};
    if (std::memcmp(curveLoader, loaderLead, sizeof(loaderLead)) != 0)
    {
        Log("byte check FAILED at the curve loader - left at 256 channels");
        return false;
    }

    // The new object: the old header and counts, the old pointers at the new table offset.
    g_object = static_cast<uint8_t*>(VirtualAlloc(nullptr, kObjectSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!g_object)
    {
        Log("could not allocate the wider broadcaster - left at 256 channels");
        return false;
    }
    std::memcpy(g_object, original, kOldTable);
    std::memcpy(g_object + kNewTable, original + kOldTable, 256 * sizeof(void*));

    // The curve hook first: if it cannot attach, nothing else is written.
    if (!aSdk->hooking->Attach(aHandle, curveLoader, reinterpret_cast<void*>(&CurveLoader),
                               reinterpret_cast<void**>(&g_origCurveLoader)))
    {
        Log("could not hook the curve loader - left at 256 channels");
        return false;
    }

    uint8_t getNew[12] = {0x48, 0xB8};  // mov rax, imm64; ret
    const uint64_t object = reinterpret_cast<uint64_t>(g_object);
    std::memcpy(getNew + 2, &object, sizeof(object));
    getNew[10] = 0xC3;
    getNew[11] = 0xCC;

    uint8_t swapNew[12] = {0x48, 0xB8};  // mov rax, imm64; jmp rax
    const uint64_t target = reinterpret_cast<uint64_t>(&Swap);
    std::memcpy(swapNew + 2, &target, sizeof(target));
    swapNew[10] = 0xFF;
    swapNew[11] = 0xE0;

    bool ok = aWrite(getInstance, getNew, sizeof(getNew)) && aWrite(swap, swapNew, sizeof(swapNew));
    for (const Bound& b : kBounds)
    {
        ok = ok && aWrite(fn[b.fn] + b.offset + b.immAt, &b.to, sizeof(b.to));
    }
    for (const Disp& d : kDisps)
    {
        ok = ok && aWrite(fn[d.fn] + d.offset + 4, &kNewTable, sizeof(kNewTable));
    }
    if (!ok)
    {
        Log("a write failed - the broadcaster may be half patched, restart the game");
        return false;
    }
    g_widened = true;
    Log("widened to " + std::to_string(kChannels) + " channels; radio channel curves are widened as banks load");
    return true;
}

} // namespace radioxl::broadcast
