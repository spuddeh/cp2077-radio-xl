// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Switches for the game's own mix rules that lower or silence the player's radio.
// File Version: 0.8.0
// ======================================================================================
//
// Six switches, each on by default (the game's own behaviour):
//   combat music  - Music_Systemic_Combat ducks the player radio bus by -96 dB while it plays
//   police music  - Music_Systemic_Police, the same duck
//   voices        - five side-chain curves lower the player radio while anyone speaks
//   megabuilding  - H10's building music turns the Radioport down through rms_loudness_pocket_radio_mb
//   menus         - a menu or the pause screen pauses the player radio, and its states lower and muffle it
//   radioport     - on foot the Radioport plays through its mixer's radio tier 1: lower, low-passed and
//                   high-passed, where a car's radio plays clean at tier 2
// And a boost: a bus volume above 0 dB on the player radio's top bus, which neither game slider can reach.
// A duck is switched by writing its entry's volume on the ducking bus; a curve by loading it again
// through the bank's own curve loader, flat or as shipped. Every Wwise address is reached from a
// RED4ext hash and its bytes are checked; a write happens only under Wwise's global lock, tried, never
// waited on, and only over the value it expects.

#pragma once

#include "Broadcast.hpp"

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <functional>
#include <limits>
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
    kRadioport,
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
constexpr int kActions = 3;  // the indexed pointer is the action itself

// sys_sfx_and_vo_pause holds one pause per bus while a menu or the pause screen is up. Two of them
// silence the radio: one pauses the player radio's top bus, the other Music_Diagetic, where every
// station's playlist plays and broadcasts from, so a receiver left running hears nothing. Other world
// music on Music_Diagetic plays on through a menu with them. An action keeps its target at +0x30, its
// type at +0x34 (0x0202, pause one object) and the target-is-a-bus flag in bit 0x40 of +0x36, and
// looks the target up each time it runs: aimed at id 0 it pauses nothing. The resumes are left alone.
// A paused session also sets GSoundSystem+0x1e0, and while it is set audio::RadioSystem::Update skips
// every station: no clock, no song, so the radio holds where it was. While the menus switch is off the
// hook clears the flag for the radio system's own update and restores it straight after, so the music,
// director and playlist systems stay paused. RadioSystem::Update reads the flag through
// `mov rax, [rip+rel32]` at +0x2d and `cmp byte [rax+0x1e0], r14b` at +0x34.
constexpr uint32_t kHashRadioUpdate = 3455127956;  // 0x247fa0
constexpr size_t kFlagLoadAt = 0x2d;
constexpr uint8_t kFlagLoad[] = {0x48, 0x8B, 0x05};
constexpr uint8_t kFlagCmp[] = {0x44, 0x38, 0xB0, 0xE0, 0x01, 0x00, 0x00};
using RadioUpdateFn = void (*)(void*, float, void*);
inline RadioUpdateFn g_origRadioUpdate = nullptr;
inline uintptr_t* g_soundSystemVar = nullptr;
inline std::atomic<bool> g_heldReported{false};

struct Pause
{
    uint32_t action;
    uint32_t bus;
};
constexpr Pause kPauses[] = {
    {592197528, 4067771226},  // Music_Radio_Car_Player_DVR
    {890107075, 666212655},   // Music_Diagetic
};

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
    int table;
    uint32_t bus;
    uint32_t group;
    uint32_t state;
    uint16_t props[2];
    float values[2];
    uint16_t count;
};
constexpr uint32_t kPlayerRadioTop = 4067771226;  // Music_Radio_Car_Player_DVR
constexpr uint32_t kRadioMixer = 924789914;  // the top actor mixer over every radio sound
constexpr State kStates[] = {
    {kBuses, kPlayerRadioTop, 2481250406, 2418768486, {0, 2}, {-20.0f, 30.0f}, 2},  // st_menu = st_menu_on
    {kBuses, kPlayerRadioTop, 4054796535, 2425410597, {2, 0}, {50.0f, 0.0f}, 1},     // st_pause: low-pass
    // st_pause on the radio mixer: -108 dB, which silences every radio voice while a menu pauses audio.
    // A world or NPC car radio stays paused by its own bus's pause action; the player's radio has none.
    {kNodes, kRadioMixer, 4054796535, 2425410597, {0, 0}, {-108.0f, 0.0f}, 1},
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
    // veh_radio_tier on the Radioport's mixer 801426841. The player's game object holds tier 1 on foot and 2
    // in a vehicle; tier 2 silences the Radioport so it never plays over the car.
    {kRadioport, kNodes, 801426841, 4124810785, 0, 117034723},  // volume: 0 dB at 0, -6 at 1.5, silent at 2
    {kRadioport, kNodes, 801426841, 4124810785, 2, 875835072},  // low-pass: 25 from 0.45 to 1, 0 at 2
    {kRadioport, kNodes, 801426841, 4124810785, 3, 372331119},  // high-pass: 25 at 0.45, 15 at 1, 0 at 2
};
// A switched-off tier curve is flattened only below this tier, so the vehicle tier keeps the Radioport silent.
constexpr float kVehicleTier = 2.0f;

// The boost is a bus volume on the two buses the player radio plays through: Music_Diagetic_Radios_Vehicle_Player_DVR
// (the car, the Radioport) and Music_Diagetic_Radios_Metro_Player_DVR (the metro). It sits after the game's Car Radio
// and Radioport sliders, which act on the buses below them, and after the car mixer's broadcast send, which plays the
// car radio into the world, so neither the world copy nor a slider at 0 is raised; and before the limiter on
// Music_Radio_Car_Player_DVR, which those two buses feed. CAkBus::SetAkProp(bus, prop, gameObject, meaning, value, curve, ms) is the setter the
// "Set Bus Volume" action uses: it keeps the value as a runtime modifier beside the bus's own volume and its
// states, so no stored value is touched. Property 4 is BusVolume; meaning 1 sets the modifier absolutely.
constexpr uint32_t kBoostBuses[] = {3776664628, 2319597885};
constexpr uint32_t kHashBusSetAkProp = 1329276021;  // 0x1b10bc0
constexpr uint8_t kBusSetAkPropPrologue[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74};
using BusSetAkPropFn = void (*)(void*, int, void*, int, float, int, int);
constexpr int kPropBusVolume = 4;
constexpr int kMeaningIndependent = 1;
constexpr int kCurveLinear = 4;
constexpr int kBoostGlideMs = 100;

// The car radio's cabin reverb. The car voices sit under actor mixer 231101095, whose game aux send (property 12)
// feeds the reverb the game sets on the car's game object (revb_indoor_car_hipercar for a hypercar). That send
// leaves the voice before the buses the Car Radio slider acts on, so with the slider at 0 the reverb alone played on. The
// mixer is given the slider's own curve on that send (Music_Diagetic_Radios_Vehicle_Player_INT's
// volume_music_car_radio points), through the node's SetRTPC, the call the bank loader makes for every RTPC a node
// carries; the boost is added to the send's own -4 dB, so the reverb keeps its share of a boosted radio.
constexpr uint32_t kCarRadioMixer = 231101095;
constexpr uint32_t kHashNodeSetRtpc = 2226136046;  // 0x1adda50, the parameter node's SetRTPC (vtable +0x1c0)
constexpr size_t kSetRtpcSlot = 0x1c0;
using NodeSetRtpcFn = int (*)(void*, const broadcast::CurveDesc*, const broadcast::GraphPoint*);
constexpr uint32_t kHashSetAkProp = 3561623913;  // 0x1b07990, CAkParameterNode::SetAkProp
constexpr uint8_t kSetAkPropPrologue[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83};
using SetAkPropFn = void (*)(void*, int, float, float, float);
constexpr uint8_t kPropGameAuxSend = 12;
constexpr float kCarAuxSendDb = -4.0f;
constexpr uint32_t kRtpcCarRadioVolume = 2663631704;  // volume_music_car_radio
// Plain dB, no scaling: on property 12 a dB-scaled curve is misread (Audible Traffic Radios measured +2.548 meant
// as +11 dB arriving as +764 dB), so the slider's own points are given as their dB values.
constexpr broadcast::CurveDesc kCarAuxSliderDesc{0, 2, 0, 0, kRtpcCarRadioVolume, kPropGameAuxSend, 1945851738, 5};
constexpr broadcast::GraphPoint kCarAuxSliderPoints[] = {
    {0.0f, -96.0f, 4}, {25.0f, -16.0f, 4}, {50.0f, -9.0f, 4}, {75.0f, -5.0f, 4}, {100.0f, 0.0f, 4}};
// The game's output runs through Mastering Suite on the System audio device, whose limiter acts on the whole mix:
// past about +12 dB the radio's peaks pull every other sound down with them.
constexpr float kMaxBoost = 12.0f;
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
inline std::atomic<bool> g_mutes[kSwitchCount] = {true, true, true, true, true, true};
inline std::atomic<bool> g_pending{false};
inline bool g_ready = false;
inline SetFn g_set = nullptr;
inline BusSetAkPropFn g_busSetAkProp = nullptr;
inline NodeSetRtpcFn g_nodeSetRtpc = nullptr;
inline SetAkPropFn g_setAkProp = nullptr;
// The car mixer the slider curve was attached to: a new object (its bank loaded again) gets it again.
inline uintptr_t g_carAuxCurveOn = 0;
inline float g_carAuxWritten = kCarAuxSendDb;
inline std::atomic<float> g_boost{0.0f};
// The boost last handed to Wwise; NaN until the first write, so a boost of 0 is applied once too.
inline float g_boostApplied = std::numeric_limits<float>::quiet_NaN();

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
    case kRadioport: return "radioport";
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
inline uintptr_t Find(int aTable, uint32_t aId, uintptr_t aOffset = 0x10)
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
            return node - aOffset;
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

// A switched-off curve's points: every value 0, except a tier curve keeps its vehicle-tier end.
inline void Flatten(const Curve& aCurve, std::vector<broadcast::GraphPoint>& aPoints)
{
    for (auto& p : aPoints)
    {
        if (aCurve.owner != kRadioport || p.from < kVehicleTier)
        {
            p.to = 0.0f;
        }
    }
}

inline const broadcast::GraphPoint* Points(int aIndex, const broadcast::CurveDesc* aDesc,
                                           const broadcast::GraphPoint* aPoints, std::vector<broadcast::GraphPoint>& aFlat)
{
    if (g_mutes[kCurves[aIndex].owner].load())
    {
        return aPoints;
    }
    aFlat.assign(aPoints, aPoints + aDesc->count);
    Flatten(kCurves[aIndex], aFlat);
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

inline bool ApplyPause(const Pause& aPause, bool aMute)
{
    const uintptr_t action = Find(kActions, aPause.action, 0);
    if (!action)
    {
        return false;
    }
    const auto target = Read<uint32_t>(action + 0x30);
    if (Read<uint16_t>(action + 0x34) != 0x0202 || !(Read<uint8_t>(action + 0x36) & 0x40) ||
        (target != aPause.bus && target != 0))
    {
        Log("the menu pause " + std::to_string(aPause.action) + " is not the game's - left alone");
        return true;
    }
    const uint32_t want = aMute ? aPause.bus : 0;
    if (target != want)
    {
        *reinterpret_cast<uint32_t*>(action + 0x30) = want;
        Log("menu pause " + std::to_string(aPause.action) + (aMute ? " pauses its bus again" : " pauses nothing"));
    }
    return true;
}

inline bool ApplyState(const State& aState, bool aMute)
{
    const uintptr_t bus = Find(aState.table, aState.bus);
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
        Flatten(c, points);
    }
    const int result = g_set(reinterpret_cast<void*>(table), points.data(), static_cast<uint32_t>(points.size()), cap.scaling);
    if (result != 1 && result != 3)
    {
        Log(std::string(Name(c.owner)) + ": setting curve " + std::to_string(c.rtpc) + " returned " + std::to_string(result));
    }
    return true;
}

// A property's value in a node's bundle, or 0 (the default) when the bundle does not carry it.
inline float Prop(uintptr_t aObject, uint8_t aProp)
{
    const auto bundle = Read<uintptr_t>(aObject + 0x88);
    const uint8_t count = bundle ? Read<uint8_t>(bundle) : 0;
    for (uint8_t i = 0; i < count; ++i)
    {
        if (Read<uint8_t>(bundle + 1 + i) == aProp)
        {
            return Read<float>(bundle + ((count + 4u) & ~3u) + i * 4u);
        }
    }
    return 0.0f;
}

inline bool ApplyCarReverb()
{
    const uintptr_t mixer = Find(kNodes, kCarRadioMixer);
    if (!mixer)
    {
        return false;
    }
    if (g_nodeSetRtpc && g_carAuxCurveOn != mixer)
    {
        const auto vtable = Read<uintptr_t>(mixer);
        if (vtable && Read<uintptr_t>(vtable + kSetRtpcSlot) == reinterpret_cast<uintptr_t>(g_nodeSetRtpc))
        {
            const int result = g_nodeSetRtpc(reinterpret_cast<void*>(mixer), &kCarAuxSliderDesc, kCarAuxSliderPoints);
            Log(result == 1 ? "car radio: its cabin reverb follows the Car Radio volume"
                            : "car radio: attaching the volume curve to its cabin reverb returned " + std::to_string(result));
        }
        else
        {
            Log("car radio: the mixer's SetRTPC is not the game's - cabin reverb left alone");
        }
        g_carAuxCurveOn = mixer;
    }
    if (g_setAkProp)
    {
        const float want = kCarAuxSendDb + g_boost.load();
        const float now = Prop(mixer, kPropGameAuxSend);
        if (std::fabs(now - want) >= 0.001f)
        {
            if (std::fabs(now - kCarAuxSendDb) < 0.001f || std::fabs(now - g_carAuxWritten) < 0.001f)
            {
                g_setAkProp(reinterpret_cast<void*>(mixer), kPropGameAuxSend, want, 0.0f, 0.0f);
                g_carAuxWritten = want;
            }
            else
            {
                Log("car radio: its cabin reverb send holds " + std::to_string(now) + " dB, not the game's - left alone");
                g_carAuxWritten = now;
            }
        }
    }
    return true;
}

inline bool ApplyBoost()
{
    if (!g_busSetAkProp)
    {
        return true;
    }
    const float want = g_boost.load();
    if (std::fabs(want - g_boostApplied) < 0.001f)
    {
        return true;
    }
    uintptr_t buses[std::size(kBoostBuses)] = {};
    for (size_t i = 0; i < std::size(kBoostBuses); ++i)
    {
        buses[i] = Find(kBuses, kBoostBuses[i]);
        if (!buses[i])
        {
            return false;
        }
    }
    for (const uintptr_t bus : buses)
    {
        g_busSetAkProp(reinterpret_cast<void*>(bus), kPropBusVolume, nullptr, kMeaningIndependent, want, kCurveLinear,
                       kBoostGlideMs);
    }
    g_boostApplied = want;
    return true;
}

inline void RadioUpdate(void* aSystem, float aDelta, void* aInfo)
{
    uint8_t* flag = nullptr;
    if (!g_mutes[kMenus].load() && g_soundSystemVar && *g_soundSystemVar)
    {
        flag = reinterpret_cast<uint8_t*>(*g_soundSystemVar + 0x1e0);
        if (*flag == 0)
        {
            flag = nullptr;
        }
    }
    if (!flag)
    {
        g_origRadioUpdate(aSystem, aDelta, aInfo);
        return;
    }
    if (!g_heldReported.exchange(true))
    {
        Log("menus: the radio keeps playing through a paused session");
    }
    const uint8_t held = *flag;
    *flag = 0;
    g_origRadioUpdate(aSystem, aDelta, aInfo);
    *flag = held;
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
    for (const Pause& pause : kPauses)
    {
        done = ApplyPause(pause, g_mutes[kMenus].load()) && done;
    }
    done = ApplyBoost() && done;
    done = ApplyCarReverb() && done;
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
        if (aSwitch == kRadioport)
        {
            Log(aMute ? "radioport: plays as the game made it" : "radioport: plays at the car's level, unfiltered");
        }
        else
        {
            Log(std::string(Name(static_cast<Switch>(aSwitch))) + (aMute ? " lowers the radio" : " no longer lowers the radio"));
        }
    }
    g_pending = true;
}

inline void SetBoost(float aDb)
{
    const float db = std::isfinite(aDb) ? (std::min)((std::max)(aDb, 0.0f), kMaxBoost) : 0.0f;
    if (std::fabs(g_boost.exchange(db) - db) >= 0.001f)
    {
        Log("boost: the player radio at +" + std::to_string(static_cast<int>(std::lround(db))) + " dB");
    }
    g_pending = true;
}

// Hooks the radio system's update for the menus switch; without it menus still hold the radio.
inline void HookRadioUpdate(uintptr_t (*aResolve)(uint32_t), const RED4ext::v1::Sdk* aSdk,
                            RED4ext::v1::PluginHandle aHandle)
{
    auto* fn = reinterpret_cast<uint8_t*>(aResolve(kHashRadioUpdate));
    if (!fn || std::memcmp(fn + kFlagLoadAt, kFlagLoad, sizeof(kFlagLoad)) != 0 ||
        std::memcmp(fn + kFlagLoadAt + 7, kFlagCmp, sizeof(kFlagCmp)) != 0)
    {
        Log("byte check FAILED at the radio system's update - menus still hold the radio");
        return;
    }
    int32_t rel = 0;
    std::memcpy(&rel, fn + kFlagLoadAt + 3, sizeof(rel));
    g_soundSystemVar = reinterpret_cast<uintptr_t*>(fn + kFlagLoadAt + 7 + rel);
    if (!aSdk->hooking->Attach(aHandle, fn, reinterpret_cast<void*>(&RadioUpdate),
                               reinterpret_cast<void**>(&g_origRadioUpdate)))
    {
        g_soundSystemVar = nullptr;
        Log("could not hook the radio system's update - menus still hold the radio");
    }
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
    g_nodeSetRtpc = reinterpret_cast<NodeSetRtpcFn>(aResolve(kHashNodeSetRtpc));
    const auto setProp = reinterpret_cast<const uint8_t*>(aResolve(kHashSetAkProp));
    if (setProp && std::memcmp(setProp, kSetAkPropPrologue, sizeof(kSetAkPropPrologue)) == 0)
    {
        g_setAkProp = reinterpret_cast<SetAkPropFn>(const_cast<uint8_t*>(setProp));
    }
    else
    {
        Log("byte check FAILED at the node property setter - the cabin reverb is not boosted");
    }
    const auto busSet = reinterpret_cast<const uint8_t*>(aResolve(kHashBusSetAkProp));
    if (busSet && std::memcmp(busSet, kBusSetAkPropPrologue, sizeof(kBusSetAkPropPrologue)) == 0)
    {
        g_busSetAkProp = reinterpret_cast<BusSetAkPropFn>(const_cast<uint8_t*>(busSet));
    }
    else
    {
        Log("byte check FAILED at the bus property setter - no boost");
    }
    g_ready = true;
    Log("ready");
    return true;
}

} // namespace radioxl::mix
