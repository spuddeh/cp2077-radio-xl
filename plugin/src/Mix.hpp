// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Switches for the game's own mix rules that lower or silence the player's radio.
// File Version: 0.8.0
// ======================================================================================
//
// Five switches, each on by default (the game's own behaviour):
//   combat music  - Music_Systemic_Combat ducks the player radio bus by -96 dB while it plays
//   police music  - Music_Systemic_Police, the same duck
//   voices        - five side-chain curves lower the player radio while anyone speaks
//   megabuilding  - H10's building music turns the Radioport down through rms_loudness_pocket_radio_mb
//   menus         - a menu state lowers and muffles the player radio, and a pause muffles it
// A duck is switched by writing its entry's volume on the ducking bus; a curve by loading it again
// through the bank's own curve loader, flat or as shipped. Every Wwise address is reached from a
// RED4ext hash and its bytes are checked; a write happens only under Wwise's global lock, tried, never
// waited on, and only over the value it expects.

#pragma once

#include "Broadcast.hpp"

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace radioxl::mix
{

enum Switch : int
{
    kCombat,
    kPolice,
    kVoices,
    kMegabuilding,
    kMenus,
    kSwitchCount
};

// A function that reads g_pIndex at +0x4f (mov rbx, [rip+rel32]) and calls CAkFunctionCritical's
// constructor at +0x12b, whose lea at +0x17 names g_csMain.
constexpr uint32_t kHashIndexUser = 653209842;  // 0x1a7a650
constexpr size_t kIndexLoadAt = 0x4a;
constexpr uint8_t kIndexLoad[] = {0x48, 0x89, 0x5C, 0x24, 0x70, 0x48, 0x8B, 0x1D};
constexpr size_t kCritCallAt = 0x12b;
constexpr uint8_t kCritPrologue[] = {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B};

// g_pIndex: one table per object type, 0x58 apart. Table 0 holds audio nodes, table 1 buses; each
// keeps its buckets at +0x40 and their count at +0x48 within the table. A bucket chains through +0x8
// and holds the id at +0x10; the object starts 0x10 before the pointer.
constexpr size_t kTableStride = 0x58;
constexpr int kNodes = 0;
constexpr int kBuses = 1;

constexpr uint32_t kPlayerRadioBus = 3776664628;  // Music_Diagetic_Radios_Vehicle_Player_DVR

// A bus's duck list: head at +0x110, count at +0x134; an entry chains through +0 and holds the target
// at +0x08, volume +0x0c, fade out +0x10, fade in +0x14, curve +0x18, property +0x1c.
struct Duck
{
    uint32_t bus;
    float volume;
    int32_t fadeOut;
    int32_t fadeIn;
    uint32_t curve;
};
constexpr Duck kDucks[] = {
    {2791646749, -96.0f, 2000, 3000, 4},  // Music_Systemic_Combat
    {318512183, -96.0f, 2000, 3000, 4},   // Music_Systemic_Police
};

// A curve is matched by its parameter, property and curve id: the loader's second argument is 0 for
// these, and the object they sit on is not passed by id. `target` is the object, looked up only to
// know its bank is still loaded.
// A state's values on a bus. The bus keeps its state data at [object+0x38]: groups chained from +0x08
// through +0x10, each holding its owner (object+0x28) at +0x18, its states at +0x20 (count +0x28, 0x18
// bytes each) and its id at +0x40. A state entry holds its id at +0 and its own property bundle at
// +8: a u16 count, the u16 property ids, then the floats from the next 4-byte boundary. Wwise reads the
// bundle at every change into the state, so a value written here applies from the next change.
struct State
{
    uint32_t bus;
    uint32_t group;
    uint32_t state;
    uint16_t props[2];
    float values[2];
    uint16_t count;
};
constexpr uint32_t kPlayerRadioTop = 4067771226;  // Music_Radio_Car_Player_DVR
constexpr State kStates[] = {
    {kPlayerRadioTop, 2481250406, 2418768486, {0, 2}, {-20.0f, 30.0f}, 2},  // st_menu = st_menu_on
    {kPlayerRadioTop, 4054796535, 2425410597, {2, 0}, {50.0f, 0.0f}, 1},     // st_pause = st_pause_game_paused
};

struct Curve
{
    Switch owner;
    int table;
    uint32_t target;
    uint32_t rtpc;
    uint32_t param;
    uint32_t curve;
};
constexpr Curve kCurves[] = {
    {kVoices, kBuses, 3776664628, 724631792, 0, 1021325208},   // vo_dialog_active, volume
    {kVoices, kBuses, 3776664628, 724631792, 2, 1017306256},   // vo_dialog_active, low-pass
    {kVoices, kBuses, 3776664628, 724631792, 3, 768298234},    // vo_dialog_active, high-pass
    {kVoices, kBuses, 4067771226, 949106528, 0, 1019792690},   // rms_loudness_VO_Gameplay, volume
    {kVoices, kBuses, 4067771226, 3564350091, 0, 213041943},   // rms_loudness_VO_Dialog_Important, volume
    {kVoices, kBuses, 4067771226, 3564350091, 2, 532204427},   // rms_loudness_VO_Dialog_Important, low-pass
    {kMegabuilding, kNodes, 228915200, 2492096760, 0, 68480862},  // radio_pocket, rms_loudness_pocket_radio_mb
};
constexpr size_t kCurveCount = sizeof(kCurves) / sizeof(kCurves[0]);

// A stored curve entry keeps its CAkConversionTable at +0x18 (points +0x18, count +0x20, scaling
// +0x24). The loader's own Set call at +0x126 names CAkConversionTable::Set(table, points, count,
// scaling). Calling Set alone, and not the loader, keeps the entry's cache of recent outputs: a voice
// takes each parameter change as new minus cached, so the next change moves it onto the new curve.
// The loader re-primes that cache, which would leave playing voices on the old curve.
constexpr size_t kSetCallAt = 0x122;
constexpr uint8_t kSetCall[] = {0x44, 0x8B, 0x47, 0x10, 0xE8};
using SetFn = int (*)(void*, const broadcast::GraphPoint*, uint32_t, uint8_t);

struct Captured
{
    uintptr_t entry = 0;
    uint8_t scaling = 0;
    std::vector<broadcast::GraphPoint> shipped;
};

inline std::function<void(const std::string&)> g_log;
inline uintptr_t* g_indexVar = nullptr;
inline LPCRITICAL_SECTION g_lock = nullptr;
inline std::mutex g_captureMutex;
inline Captured g_captured[kCurveCount];
inline std::atomic<bool> g_mutes[kSwitchCount] = {true, true, true, true, true};
inline std::atomic<bool> g_pending{false};
inline bool g_ready = false;
inline SetFn g_set = nullptr;

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("mix: " + aText);
    }
}

inline const char* Name(Switch aSwitch)
{
    switch (aSwitch)
    {
    case kCombat: return "combat music";
    case kPolice: return "police music";
    case kVoices: return "voices";
    case kMegabuilding: return "megabuilding music";
    case kMenus: return "menus";
    default: return "?";
    }
}

template <typename T>
inline T Read(uintptr_t aAt)
{
    T v{};
    std::memcpy(&v, reinterpret_cast<const void*>(aAt), sizeof(T));
    return v;
}

// The object with this id in one of g_pIndex's tables, or 0.
inline uintptr_t Find(int aTable, uint32_t aId)
{
    const uintptr_t index = g_indexVar ? *g_indexVar : 0;
    if (!index)
    {
        return 0;
    }
    const uintptr_t table = index + aTable * kTableStride;
    const auto buckets = Read<uintptr_t>(table + 0x40);
    const auto count = Read<uint32_t>(table + 0x48);
    if (!buckets || !count)
    {
        return 0;
    }
    for (auto node = Read<uintptr_t>(buckets + (aId % count) * 8); node; node = Read<uintptr_t>(node + 0x8))
    {
        if (Read<uint32_t>(node + 0x10) == aId)
        {
            return node - 0x10;
        }
    }
    return 0;
}

// The curve loader's hook asks which switched curve this is (-1 for none), loads it flat while its
// switch is off, and hands back the stored entry once the loader returns.
inline int Match(uint32_t, const broadcast::CurveDesc* aDesc)
{
    if (!aDesc || aDesc->count == 0 || aDesc->count > 16)
    {
        return -1;
    }
    for (size_t i = 0; i < kCurveCount; ++i)
    {
        const Curve& c = kCurves[i];
        if (c.curve == aDesc->curve && c.rtpc == aDesc->rtpc && c.param == aDesc->param)
        {
            return static_cast<int>(i);
        }
    }
    return -1;
}

inline const broadcast::GraphPoint* Points(int aIndex, const broadcast::CurveDesc* aDesc,
                                           const broadcast::GraphPoint* aPoints, std::vector<broadcast::GraphPoint>& aFlat)
{
    if (g_mutes[kCurves[aIndex].owner].load())
    {
        return aPoints;
    }
    aFlat.assign(aPoints, aPoints + aDesc->count);
    for (auto& p : aFlat)
    {
        p.to = 0.0f;
    }
    return aFlat.data();
}

inline void Remember(int aIndex, const broadcast::CurveDesc* aDesc, const broadcast::GraphPoint* aShipped,
                     uintptr_t aEntry)
{
    const Curve& c = kCurves[aIndex];
    if (!aEntry || Read<uint32_t>(aEntry) != c.rtpc || Read<uint32_t>(aEntry + 4) != c.curve ||
        Read<uint32_t>(aEntry + 8) != c.param)
    {
        Log(std::string(Name(c.owner)) + ": curve " + std::to_string(c.rtpc) + " stored where it was not expected - not switchable");
        return;
    }
    bool first = false;
    {
        std::lock_guard<std::mutex> guard(g_captureMutex);
        Captured& cap = g_captured[aIndex];
        first = cap.entry == 0;
        cap.entry = aEntry;
        cap.scaling = aDesc->scaling;
        cap.shipped.assign(aShipped, aShipped + aDesc->count);
    }
    if (first)
    {
        Log(std::string(Name(c.owner)) + ": curve " + std::to_string(c.rtpc) + "/" + std::to_string(c.param) + " on " +
            std::to_string(c.target) + " found (" + std::to_string(aDesc->count) + " points)");
    }
}

// --- applying, under the lock ----------------------------------------------------------------------

inline bool ApplyDuck(const Duck& aDuck, bool aMute)
{
    const uintptr_t bus = Find(kBuses, aDuck.bus);
    if (!bus)
    {
        return false;
    }
    const auto count = Read<uint32_t>(bus + 0x134);
    uintptr_t entry = Read<uintptr_t>(bus + 0x110);
    for (uint32_t i = 0; entry && i < count && i < 16; ++i, entry = Read<uintptr_t>(entry))
    {
        if (Read<uint32_t>(entry + 0x08) != kPlayerRadioBus)
        {
            continue;
        }
        const float now = Read<float>(entry + 0x0c);
        if (Read<int32_t>(entry + 0x10) != aDuck.fadeOut || Read<int32_t>(entry + 0x14) != aDuck.fadeIn ||
            Read<uint32_t>(entry + 0x18) != aDuck.curve || Read<uint32_t>(entry + 0x1c) != 0 ||
            (now != aDuck.volume && now != 0.0f))
        {
            Log("the duck on " + std::to_string(aDuck.bus) + " is not the game's - left alone");
            return true;
        }
        const float want = aMute ? aDuck.volume : 0.0f;
        if (now != want)
        {
            *reinterpret_cast<float*>(entry + 0x0c) = want;
        }
        return true;
    }
    Log("no duck on the player radio from " + std::to_string(aDuck.bus) + " - left alone");
    return true;
}

inline bool ApplyState(const State& aState, bool aMute)
{
    const uintptr_t bus = Find(kBuses, aState.bus);
    if (!bus)
    {
        return false;
    }
    const auto data = Read<uintptr_t>(bus + 0x38);
    uintptr_t group = data ? Read<uintptr_t>(data + 0x08) : 0;
    for (int i = 0; group && i < 32; ++i, group = Read<uintptr_t>(group + 0x10))
    {
        if (Read<uint32_t>(group + 0x40) != aState.group)
        {
            continue;
        }
        if (Read<uintptr_t>(group + 0x18) != bus + 0x28)
        {
            break;
        }
        const auto states = Read<uintptr_t>(group + 0x20);
        const auto count = Read<uint32_t>(group + 0x28);
        for (uint32_t s = 0; states && s < count && s < 64; ++s)
        {
            const uintptr_t entry = states + s * 0x18;
            if (Read<uint32_t>(entry) != aState.state)
            {
                continue;
            }
            const auto bundle = Read<uintptr_t>(entry + 8);
            if (!bundle || Read<uint16_t>(bundle) != aState.count)
            {
                break;
            }
            for (uint16_t p = 0; p < aState.count; ++p)
            {
                if (Read<uint16_t>(bundle + 2 + p * 2) != aState.props[p])
                {
                    Log("the state " + std::to_string(aState.state) + " is not the game's - left alone");
                    return true;
                }
            }
            const uintptr_t values = bundle + ((2u * aState.count + 5u) & ~3u);
            for (uint16_t p = 0; p < aState.count; ++p)
            {
                const float now = Read<float>(values + p * 4);
                if (now != aState.values[p] && now != 0.0f)
                {
                    Log("the state " + std::to_string(aState.state) + " holds an unexpected value - left alone");
                    return true;
                }
            }
            for (uint16_t p = 0; p < aState.count; ++p)
            {
                *reinterpret_cast<float*>(values + p * 4) = aMute ? aState.values[p] : 0.0f;
            }
            return true;
        }
        break;
    }
    Log("the state " + std::to_string(aState.state) + " was not found on " + std::to_string(aState.bus) + " - left alone");
    return true;
}

inline bool ApplyCurve(size_t aIndex, bool aMute)
{
    const Curve& c = kCurves[aIndex];
    Captured cap;
    {
        std::lock_guard<std::mutex> guard(g_captureMutex);
        cap = g_captured[aIndex];
    }
    // A curve not loaded yet takes the switch as it loads; one whose object has gone is left until
    // its bank loads again.
    if (!cap.entry || !g_set || !Find(c.table, c.target))
    {
        return cap.entry == 0;
    }
    const uintptr_t table = cap.entry + 0x18;
    const auto stored = Read<uint32_t>(table + 0x08);
    if (stored != cap.shipped.size() + 2 || Read<uint32_t>(cap.entry) != c.rtpc ||
        Read<uint32_t>(cap.entry + 4) != c.curve)
    {
        Log(std::string(Name(c.owner)) + ": curve " + std::to_string(c.rtpc) + " is not as it loaded - left alone");
        return true;
    }
    std::vector<broadcast::GraphPoint> points = cap.shipped;
    if (!aMute)
    {
        for (auto& p : points)
        {
            p.to = 0.0f;
        }
    }
    const int result = g_set(reinterpret_cast<void*>(table), points.data(), static_cast<uint32_t>(points.size()), cap.scaling);
    if (result != 1 && result != 3)
    {
        Log(std::string(Name(c.owner)) + ": setting curve " + std::to_string(c.rtpc) + " returned " + std::to_string(result));
    }
    return true;
}

// Called from the game-state update. Returns once everything wanted is in place.
inline void Tick()
{
    if (!g_ready || !g_pending.load() || !g_lock || !TryEnterCriticalSection(g_lock))
    {
        return;
    }
    g_pending = false;
    bool done = true;
    for (int s = 0; s < kSwitchCount; ++s)
    {
        const bool mute = g_mutes[s].load();
        if (s == kCombat || s == kPolice)
        {
            done = ApplyDuck(kDucks[s], mute) && done;
        }
    }
    for (size_t i = 0; i < kCurveCount; ++i)
    {
        done = ApplyCurve(i, g_mutes[kCurves[i].owner].load()) && done;
    }
    for (const State& st : kStates)
    {
        done = ApplyState(st, g_mutes[kMenus].load()) && done;
    }
    LeaveCriticalSection(g_lock);
    if (!done)
    {
        g_pending = true;  // a bus not loaded yet: try again
    }
}

inline void Set(int aSwitch, bool aMute)
{
    if (aSwitch < 0 || aSwitch >= kSwitchCount)
    {
        return;
    }
    if (g_mutes[aSwitch].exchange(aMute) != aMute)
    {
        Log(std::string(Name(static_cast<Switch>(aSwitch))) + (aMute ? " lowers the radio" : " no longer lowers the radio"));
    }
    g_pending = true;
}

// Finds g_pIndex and g_csMain through a hashed function; without both, the switches do nothing.
inline bool Init(uintptr_t (*aResolve)(uint32_t))
{
    const auto fn = reinterpret_cast<const uint8_t*>(aResolve(kHashIndexUser));
    if (!fn || std::memcmp(fn + kIndexLoadAt, kIndexLoad, sizeof(kIndexLoad)) != 0 || fn[kCritCallAt] != 0xE8)
    {
        Log("byte check FAILED at the index reader - the mix switches are off");
        return false;
    }
    int32_t rel = 0;
    std::memcpy(&rel, fn + kIndexLoadAt + sizeof(kIndexLoad), sizeof(rel));
    g_indexVar = reinterpret_cast<uintptr_t*>(const_cast<uint8_t*>(fn) + kIndexLoadAt + 12 + rel);

    std::memcpy(&rel, fn + kCritCallAt + 1, sizeof(rel));
    const uint8_t* crit = fn + kCritCallAt + 5 + rel;
    if (std::memcmp(crit, kCritPrologue, sizeof(kCritPrologue)) != 0 || crit[0x17] != 0x48 || crit[0x18] != 0x8D ||
        crit[0x19] != 0x0D)
    {
        Log("byte check FAILED at Wwise's lock - the mix switches are off");
        return false;
    }
    std::memcpy(&rel, crit + 0x1a, sizeof(rel));
    g_lock = reinterpret_cast<LPCRITICAL_SECTION>(const_cast<uint8_t*>(crit) + 0x1e + rel);

    const auto loader = reinterpret_cast<const uint8_t*>(aResolve(broadcast::kHashCurveLoader));
    if (loader && std::memcmp(loader + kSetCallAt, kSetCall, sizeof(kSetCall)) == 0)
    {
        std::memcpy(&rel, loader + kSetCallAt + sizeof(kSetCall), sizeof(rel));
        g_set = reinterpret_cast<SetFn>(const_cast<uint8_t*>(loader) + kSetCallAt + sizeof(kSetCall) + 4 + rel);
    }
    else
    {
        Log("byte check FAILED at the curve setter - voices and megabuilding music take a switch at the next load only");
    }
    g_ready = true;
    Log("ready");
    return true;
}

} // namespace radioxl::mix
