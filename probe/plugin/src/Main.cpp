// Radio Station Probe - reads the engine's radio station objects once a second and logs what changes.
//
// A measuring instrument, never released. Every offset is game 2.31 and is read, never written.
//
// The engine keeps one object per radio station in the radio manager (engine root -> audio system
// -> radio manager -> station array). Each station carries a list of listeners, an "active" flag
// recomputed from that list every frame, its clock, and the handles of the voices it is playing.
// While a station is active it watches its voice and posts the next track when the voice ends;
// when the flag clears it stops every voice it owns with a zero fade. A station that keeps posting
// with nobody listening is a station whose flag never cleared, and this logs which listener is
// keeping it set.

#include <Windows.h>
#include <RED4ext/RED4ext.hpp>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <intrin.h>
#include <iterator>
#include <map>
#include <unordered_map>

namespace
{
// The global holding the engine root pointer (0x342ac00 on 2.31), by RED4ext hash.
constexpr uint32_t kHashEngineRoot = 2549221846;

// The radio mode's inputs (0xbd054c): GSoundSystem, its +0x90 flag, and the mix metrics at [+0x140] +0x90.
constexpr uint32_t kHashIsBusSilent = 1559499847;
constexpr uintptr_t kRvaGSoundSystem = 0x3429620;
constexpr size_t kSoundSystemFlag90 = 0x90;
constexpr size_t kSoundSystemMixOwner = 0x140;
constexpr size_t kMixOwnerMetrics = 0x90;
constexpr uint32_t kMixConfigSystemicMusic = 5;     // Music_Systemic_Combat (+ police)
constexpr uint32_t kMixConfigNpcVehicleRadios = 6;  // Music_Diagetic_Radios_Vehicle_NPC

// Engine root -> audio system -> radio manager, as GetRadioStationCurrentTrackName walks them.
constexpr size_t kRootAudioSystem = 0xa8;
constexpr size_t kAudioRadioManager = 0xe0;

// The manager's station array and its count, as the name-to-station lookup reads them.
constexpr size_t kManagerStations = 0x0;
constexpr size_t kManagerCount = 0xc;

// A station object, as the manager's per-frame update and the listener predicate read it.
constexpr size_t kStationListeners = 0x100;      // array of listener object pointers
constexpr size_t kStationListenerCount = 0x10c;
constexpr size_t kStationHandles = 0x120;        // array of playing handles
constexpr size_t kStationHandleCount = 0x12c;
constexpr size_t kStationType = 0x148;           // state: 0 ready for a song, 5 while a blip plays
constexpr size_t kStationClock = 0x14c;          // float, accumulates while active
constexpr size_t kStationHandle = 0x158;         // the current voice's handle
constexpr size_t kStationFlagA = 0x21a;
constexpr size_t kStationActive = 0x21b;         // recomputed every frame from the listeners
constexpr size_t kStationFlagD = 0x21d;
constexpr size_t kStationManager = 0x118;        // the station's pointer back to the manager

// The schedule, as the 2.31 picker (0x6bcdfc) and blip function (0x219a45c) read and write it.
constexpr size_t kStationMetadata = 0x110;       // the station's audioRadioStationMetadata
constexpr size_t kStationQueued = 0x150;         // a queued track, which a pick takes first
constexpr size_t kStationRemaining = 0x160;      // the tracks not yet picked this cycle
constexpr size_t kStationRemainingCount = 0x16c;
constexpr size_t kStationPicks = 0x170;          // byte: picks since the last blip
constexpr size_t kStationBlip = 0x178;           // the playing blip's name
constexpr size_t kStationBlipCursor = 0x188;     // index into the blip order
constexpr size_t kStationRng = 0x210;            // PCG32 state, seeded once at construction (0x6bc134)

// An announcement, as the quest handler 0xb43c20 and the request writer 0xb43d98 leave it on a
// station. A queued one waits at +0x1a0/+0x1a8 until the station has no active sound; a request
// then carries its mode at +0x1e0 and the scene being played at +0x1f8/+0x200.
constexpr size_t kStationQueuedScene = 0x1a0;    // raRef<scnSceneResource>: a resource path hash
constexpr size_t kStationQueuedInput = 0x1a8;    // sceneInput CName
constexpr size_t kStationRequestMode = 0x1e0;    // byte: 1 once a request is written
constexpr size_t kStationPlayingScene = 0x1f8;
constexpr size_t kStationPlayingInput = 0x200;
constexpr size_t kStationRequestFlags = 0x208;   // bytes +0x208, +0x209, +0x20a
constexpr size_t kScheduleMs = 100;

// The DJ selector table the token lookup 0x4fe680 reads: one 24-byte entry per speaker, in
// audioRadioSpeakerType order, rebuilt every 0.2 s by 0x9da83c as { station name, listener value,
// distance squared }.
constexpr size_t kManagerDjTable = 0x1d0;
constexpr size_t kDjEntryStride = 0x18;
constexpr const char* kDjSpeakers[] = {"Stanley", "MaximumMike", "PoliceDispatch", "Kurtz", "spk4", "spk5"};

// The engine's custom-sound voice slots, as AudioXL reads them (2.31 RVAs): a count, and per slot
// the registry row, the Wwise playing id and a position. Row names are the registry's name array.
constexpr uintptr_t kRvaSlotCount = 0x349AE74;   // uint16
constexpr uintptr_t kRvaSlotRow = 0x349CE80;     // uint16[]
constexpr uintptr_t kRvaSlotPlayingId = 0x349DE80; // uint32[]
constexpr uintptr_t kRvaSlotPos = 0x349FE80;     // uint32[]
constexpr uintptr_t kRvaRowNames = 0x48EE910;    // CName[] by row
constexpr uint16_t kMaxSlots = 256;

// The manager's inline list of station names that may be active: four 24-byte entries.
constexpr size_t kManagerList = 0x168;
constexpr size_t kManagerListCount = 0x60;       // relative to kManagerList
constexpr size_t kManagerListStride = 0x18;

// A listener's kind byte and the flag beside it, as the station update reads them: kind 4 is
// skipped by the update; in radio mode 1 (+0x27b) a station whose every listener is kind 2 (traffic) is
// held inactive (0x2a775c).
constexpr size_t kListenerKind = 0x12c;
constexpr size_t kListenerFlag = 0x12d;

// Virtuals: +0x70 writes the object's CName into *out and returns out; +0x100 on a listener answers
// whether it counts.
constexpr size_t kVtblGetName = 0x70;
constexpr size_t kVtblListenerActive = 0x100;

using GetNameFn = uint64_t* (*)(void* aSelf, uint64_t* aOut);
using ListenerActiveFn = bool (*)(void* aSelf);

const RED4ext::v1::Sdk* g_sdk = nullptr;
RED4ext::v1::PluginHandle g_handle = nullptr;
uint64_t g_lastTick = 0;
std::unordered_map<uintptr_t, std::string> g_last;
uint64_t g_walks = 0;
std::string g_lastList;
bool g_failed = false;
uint64_t g_lastSchedule = 0;
bool g_scheduleFailed = false;
size_t g_tracksOffset = 0;   // audioRadioStationMetadata.tracks, from RTTI
size_t g_blipsOffset = 0;    // audioRadioStationMetadata.blips, from RTTI

void Log(const std::string& aText)
{
    if (g_sdk && g_sdk->logger)
    {
        g_sdk->logger->Info(g_handle, aText.c_str());
    }
}

uintptr_t ResolveByHash(uint32_t aHash)
{
    using ResolveFn = uintptr_t (*)(uint32_t);
    static const ResolveFn resolve = []() -> ResolveFn
    {
        const HMODULE red4ext = GetModuleHandleW(L"RED4ext.dll");
        return red4ext ? reinterpret_cast<ResolveFn>(GetProcAddress(red4ext, "RED4ext_ResolveAddress"))
                       : nullptr;
    }();
    return resolve ? resolve(aHash) : 0;
}

template <typename T>
T Read(uintptr_t aAddress)
{
    return *reinterpret_cast<T*>(aAddress);
}

// audio::MixMetrics::IsBusSilent (0xbd0600), a pure read of the meter's level against -200 dB. Refused unless
// its prologue is 2.31's.
using IsBusSilentFn = bool (*)(void* aMetrics, uint32_t aConfig);
IsBusSilentFn ResolveIsBusSilent()
{
    static const IsBusSilentFn fn = []() -> IsBusSilentFn
    {
        static const uint8_t kPrologue[] = {0x48, 0x83, 0xEC, 0x28, 0x4C, 0x8D, 0x44, 0x24};
        const auto address = ResolveByHash(kHashIsBusSilent);
        if (!address || std::memcmp(reinterpret_cast<void*>(address), kPrologue, sizeof(kPrologue)) != 0)
        {
            return nullptr;
        }
        return reinterpret_cast<IsBusSilentFn>(address);
    }();
    return fn;
}

std::string NameOf(void* aObject)
{
    if (!aObject)
    {
        return "null";
    }
    const auto vtbl = Read<uintptr_t>(reinterpret_cast<uintptr_t>(aObject));
    const auto getName = Read<GetNameFn>(vtbl + kVtblGetName);
    uint64_t out = 0;
    getName(aObject, &out);
    const RED4ext::CName name(out);
    const char* text = name.ToString();
    if (text && *text)
    {
        return text;
    }
    char buf[32];
    std::snprintf(buf, sizeof(buf), "cname:%016llx", static_cast<unsigned long long>(out));
    return buf;
}

// Builds one line per station of type 0 and hands it to the change filter.
void Walk(std::string& aReport)
{
    const auto rootSlot = ResolveByHash(kHashEngineRoot);
    if (!rootSlot)
    {
        aReport = "engine root did not resolve - no address database for this build";
        return;
    }
    const auto root = Read<uintptr_t>(rootSlot);
    if (!root)
    {
        return;
    }
    const auto audio = Read<uintptr_t>(root + kRootAudioSystem);
    if (!audio)
    {
        return;
    }
    const auto manager = Read<uintptr_t>(audio + kAudioRadioManager);
    if (!manager)
    {
        return;
    }
    const auto stations = Read<uintptr_t>(manager + kManagerStations);
    const auto count = Read<uint32_t>(manager + kManagerCount);
    if (!stations || count > 256)
    {
        return;
    }

    for (uint32_t i = 0; i < count; ++i)
    {
        const auto station = Read<uintptr_t>(stations + i * 8);
        if (!station)
        {
            continue;
        }
        const auto type = Read<int32_t>(station + kStationType);
        if (type != 0)
        {
            continue;
        }

        std::string line = NameOf(reinterpret_cast<void*>(station));
        line += " active=" + std::to_string(Read<uint8_t>(station + kStationActive));
        line += " a=" + std::to_string(Read<uint8_t>(station + kStationFlagA));
        line += " d=" + std::to_string(Read<uint8_t>(station + kStationFlagD));
        line += " handles=" + std::to_string(Read<uint32_t>(station + kStationHandleCount));
        char buf[48];
        std::snprintf(buf, sizeof(buf), " handle=%llx", static_cast<unsigned long long>(Read<uint64_t>(station + kStationHandle)));
        line += buf;

        const auto listeners = Read<uintptr_t>(station + kStationListeners);
        const auto listenerCount = Read<uint32_t>(station + kStationListenerCount);
        line += " listeners=" + std::to_string(listenerCount) + " [";
        if (listeners && listenerCount <= 64)
        {
            for (uint32_t l = 0; l < listenerCount; ++l)
            {
                const auto listener = Read<uintptr_t>(listeners + l * 8);
                if (!listener)
                {
                    line += "null ";
                    continue;
                }
                const auto vtbl = Read<uintptr_t>(listener);
                const auto active = Read<ListenerActiveFn>(vtbl + kVtblListenerActive);
                line += NameOf(reinterpret_cast<void*>(listener));
                line += active(reinterpret_cast<void*>(listener)) ? ":on" : ":off";
                char kind[24];
                std::snprintf(kind, sizeof(kind), "/k%u/f%u ", Read<uint8_t>(listener + kListenerKind),
                              Read<uint8_t>(listener + kListenerFlag));
                line += kind;
            }
        }
        line += "]";

        // The clock is reported coarsely so a running clock does not make every second a change.
        const float clock = Read<float>(station + kStationClock);
        const bool ticking = clock != 0.0f;
        line += ticking ? " clock=running" : " clock=0";

        auto& last = g_last[station];
        if (last != line)
        {
            last = line;
            aReport += line + "\n";
        }

        // The clock's value, every ten seconds, for the custom stations and one vanilla control
        // (Body Heat). Whether it advances while nobody listens is what decides if it is the
        // station's schedule time or the voice's own elapsed time.
        const std::string name = NameOf(reinterpret_cast<void*>(station));
        const bool custom = name.rfind("radio_station_0", 0) != 0 && name.rfind("radio_station_1", 0) != 0 &&
                            name.rfind("radio_station_p", 0) != 0;
        if (g_walks % 10 == 0 && (custom || name == "radio_station_05_pop"))
        {
            char clockBuf[96];
            std::snprintf(clockBuf, sizeof(clockBuf), "%s clock=%.2f active=%u handles=%u", name.c_str(), clock,
                          Read<uint8_t>(station + kStationActive), Read<uint32_t>(station + kStationHandleCount));
            aReport += std::string(clockBuf) + "\n";
        }
    }
    // **The manager keeps a four-slot inline list of station names (+0x168, count +0x1c8, 24-byte
    // entries), and a station is active only while its name is in it.** The per-frame update asks
    // `0xc0749c(manager, name)` for the first switched-on listener; a miss clears the active flag
    // whatever the listener says. Logged whenever it changes, so a station that goes silent under a
    // live listener shows its name leaving this list.
    {
        std::string list = "manager list:";
        const auto count = Read<uint32_t>(manager + kManagerList + kManagerListCount);
        for (uint32_t i = 0; i < count && i < 4; ++i)
        {
            const auto entry = manager + kManagerList + i * kManagerListStride;
            const RED4ext::CName name(Read<uint64_t>(entry));
            const char* text = name.ToString();
            char buf[96];
            std::snprintf(buf, sizeof(buf), " [%s %llx %llx]", text && *text ? text : "?",
                          static_cast<unsigned long long>(Read<uint64_t>(entry + 8)),
                          static_cast<unsigned long long>(Read<uint64_t>(entry + 16)));
            list += buf;
        }
        if (count > 4)
        {
            list += " count=" + std::to_string(count) + " (over four - not this layout)";
        }
        if (g_lastList != list)
        {
            g_lastList = list;
            aReport += list + "\n";
        }
    }
    // The radio system's mode (+0x27b), recomputed every sound update by 0xbd054c from +0x27c, +0x27d and two
    // mix buses: in mode 1 a station whose every listener is a traffic emitter (kind 2) is held inactive.
    // With +0x27d clear, mode 1 is GSoundSystem +0x90 set, or meter 5 (systemic combat/police music) heard
    // while meter 6 (NPC vehicle radios) is silent. `snd90`, `combat` and `npc` are those three inputs.
    {
        const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        const auto sound = Read<uintptr_t>(base + kRvaGSoundSystem);
        int flag90 = -1;
        int combatSilent = -1;
        int npcSilent = -1;
        if (sound)
        {
            flag90 = Read<uint8_t>(sound + kSoundSystemFlag90);
            const auto sub = Read<uintptr_t>(sound + kSoundSystemMixOwner);
            const auto metrics = sub ? Read<uintptr_t>(sub + kMixOwnerMetrics) : 0;
            const auto isBusSilent = ResolveIsBusSilent();
            // The raw levels each meter holds (MixBusMeter +0x18 and +0x38, linear; CollectMeteringData turns a
            // value under its floor into -200 dB), once a second: NPC vehicle radios (+0x68) and combat (+0x58).
            static uint64_t lastMeter = 0;
            const uint64_t nowTick = GetTickCount64();
            if (metrics && nowTick - lastMeter >= 1000)
            {
                lastMeter = nowTick;
                const auto npc = Read<uintptr_t>(metrics + 0x68);
                const auto combat = Read<uintptr_t>(metrics + 0x58);
                char meter[160];
                std::snprintf(meter, sizeof(meter), "meter npc=%.6g/%.6g combat=%.6g/%.6g",
                              npc ? Read<float>(npc + 0x18) : -1.0f, npc ? Read<float>(npc + 0x38) : -1.0f,
                              combat ? Read<float>(combat + 0x18) : -1.0f, combat ? Read<float>(combat + 0x38) : -1.0f);
                aReport += std::string(meter) + "\n";
            }
            if (metrics && isBusSilent)
            {
                combatSilent = isBusSilent(reinterpret_cast<void*>(metrics), kMixConfigSystemicMusic) ? 1 : 0;
                npcSilent = isBusSilent(reinterpret_cast<void*>(metrics), kMixConfigNpcVehicleRadios) ? 1 : 0;
            }
        }
        char mode[160];
        std::snprintf(mode, sizeof(mode), "radio mode=%u 27c=%u 27d=%u snd90=%d combat=%s npc=%s",
                      Read<uint8_t>(manager + 0x27b), Read<uint8_t>(manager + 0x27c), Read<uint8_t>(manager + 0x27d),
                      flag90, combatSilent < 0 ? "?" : (combatSilent ? "silent" : "heard"),
                      npcSilent < 0 ? "?" : (npcSilent ? "silent" : "heard"));
        static std::string lastMode;
        if (lastMode != mode)
        {
            lastMode = mode;
            aReport += std::string(mode) + "\n";
        }
    }
    ++g_walks;
}

// --- the schedule ------------------------------------------------------------------------------
// One POD snapshot per station, read behind SEH; the text is built outside it.
struct Sched
{
    uintptr_t station;
    uint64_t name;
    int32_t state;
    uint8_t picks;
    uint8_t active;
    uint32_t remaining;
    // The remaining list's first words, read 32 bits at a time: a list of 4-byte indices reads as
    // small numbers, a list of 8-byte entries reads as pairs with a zero high half. Reading by the
    // narrower width can never run past a 4-byte buffer.
    uint32_t remainWords;
    uint32_t remainRaw[64];
    uint32_t remainCapacity;   // the list's buffer, +0x168; 0 after a metadata swap
    uint32_t blipCursor;
    uint64_t current;
    uint64_t blip;
    uint64_t queued;
    float clock;
    uintptr_t metadata;
    uint64_t rng;
    uint64_t queuedScene;
    uint64_t queuedInput;
    uint8_t requestMode;
    uint64_t playingScene;
    uint64_t playingInput;
    uint8_t flags[3];
};

constexpr uint32_t kMaxStations = 128;
Sched g_snap[kMaxStations];
std::unordered_map<uintptr_t, std::string> g_lastSched;
std::unordered_map<uintptr_t, uint32_t> g_listedCount;  // tracks listed per station, relisted on a change
std::unordered_map<uintptr_t, std::string> g_lastAnnounce;
std::unordered_map<uintptr_t, std::string> g_lastRemain;

struct DjEntry
{
    uint64_t name;
    uint64_t value;
    float distSq;
};
DjEntry g_dj[6];
std::string g_lastDj;
std::string g_lastOrder;

struct Slot
{
    uint16_t row;
    uint32_t playingId;
    uint32_t pos;
    uint64_t name;
};
Slot g_slots[kMaxSlots];
std::string g_lastSlots;
bool g_slotsFailed = false;

uint32_t ReadSchedule()
{
    const auto rootSlot = ResolveByHash(kHashEngineRoot);
    if (!rootSlot)
    {
        return 0;
    }
    const auto root = Read<uintptr_t>(rootSlot);
    const auto audio = root ? Read<uintptr_t>(root + kRootAudioSystem) : 0;
    const auto manager = audio ? Read<uintptr_t>(audio + kAudioRadioManager) : 0;
    if (!manager)
    {
        return 0;
    }
    const auto stations = Read<uintptr_t>(manager + kManagerStations);
    const auto count = Read<uint32_t>(manager + kManagerCount);
    if (!stations || count > kMaxStations)
    {
        return 0;
    }
    uint32_t n = 0;
    for (uint32_t i = 0; i < count; ++i)
    {
        const auto station = Read<uintptr_t>(stations + i * 8);
        if (!station)
        {
            continue;
        }
        Sched& s = g_snap[n++];
        s.station = station;
        const auto vtbl = Read<uintptr_t>(station);
        uint64_t name = 0;
        Read<GetNameFn>(vtbl + kVtblGetName)(reinterpret_cast<void*>(station), &name);
        s.name = name;
        s.state = Read<int32_t>(station + kStationType);
        s.picks = Read<uint8_t>(station + kStationPicks);
        s.active = Read<uint8_t>(station + kStationActive);
        s.remaining = Read<uint32_t>(station + kStationRemainingCount);
        s.remainWords = 0;
        s.remainCapacity = Read<uint32_t>(station + kStationRemaining + 0x8);
        const auto remainingEntries = Read<uintptr_t>(station + kStationRemaining);
        for (uint32_t w = 0; remainingEntries && w < s.remaining && w < 64; ++w)
        {
            s.remainRaw[w] = Read<uint32_t>(remainingEntries + w * 4);
            ++s.remainWords;
        }
        s.blipCursor = Read<uint32_t>(station + kStationBlipCursor);
        s.current = Read<uint64_t>(station + kStationHandle);
        s.blip = Read<uint64_t>(station + kStationBlip);
        s.queued = Read<uint64_t>(station + kStationQueued);
        s.clock = Read<float>(station + kStationClock);
        s.metadata = Read<uintptr_t>(station + kStationMetadata);
        s.rng = Read<uint64_t>(station + kStationRng);
        s.queuedScene = Read<uint64_t>(station + kStationQueuedScene);
        s.queuedInput = Read<uint64_t>(station + kStationQueuedInput);
        s.requestMode = Read<uint8_t>(station + kStationRequestMode);
        s.playingScene = Read<uint64_t>(station + kStationPlayingScene);
        s.playingInput = Read<uint64_t>(station + kStationPlayingInput);
        for (int f = 0; f < 3; ++f)
        {
            s.flags[f] = Read<uint8_t>(station + kStationRequestFlags + f);
        }
    }
    for (uint32_t d = 0; d < 6; ++d)
    {
        const auto entry = manager + kManagerDjTable + d * kDjEntryStride;
        g_dj[d].name = Read<uint64_t>(entry);
        g_dj[d].value = Read<uint64_t>(entry + 8);
        g_dj[d].distSq = Read<float>(entry + 16);
    }
    return n;
}

// The slot table lives in the game module, not behind the manager.
uint16_t ReadSlots()
{
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto count = Read<uint16_t>(base + kRvaSlotCount);
    const uint16_t n = count < kMaxSlots ? count : kMaxSlots;
    for (uint16_t i = 0; i < n; ++i)
    {
        g_slots[i].row = Read<uint16_t>(base + kRvaSlotRow + i * 2);
        g_slots[i].playingId = Read<uint32_t>(base + kRvaSlotPlayingId + i * 4);
        g_slots[i].pos = Read<uint32_t>(base + kRvaSlotPos + i * 4);
        g_slots[i].name = g_slots[i].row != 0xFFFF ? Read<uint64_t>(base + kRvaRowNames + g_slots[i].row * 8) : 0;
    }
    return count;
}

bool SafeReadSlots(uint16_t* aCount)
{
    __try
    {
        *aCount = ReadSlots();
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool SafeReadSchedule(uint32_t* aCount)
{
    __try
    {
        *aCount = ReadSchedule();
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// A CName as text when the pool knows it, as its hash otherwise.
std::string Text(uint64_t aHash)
{
    if (aHash == 0)
    {
        return "-";
    }
    const char* text = RED4ext::CName(aHash).ToString();
    if (text && *text)
    {
        return text;
    }
    char buf[24];
    std::snprintf(buf, sizeof(buf), "%016llx", static_cast<unsigned long long>(aHash));
    return buf;
}

// The metadata's tracks and blips arrays, read through the offsets RTTI gives. A DynArray is
// { entries, capacity, size }; each entry here is one 8-byte CName.
bool SafeReadList(uintptr_t aMetadata, size_t aOffset, uint64_t* aOut, uint32_t aMax, uint32_t* aSize)
{
    __try
    {
        const auto entries = Read<uintptr_t>(aMetadata + aOffset);
        const auto size = Read<uint32_t>(aMetadata + aOffset + 0xc);
        *aSize = size;
        for (uint32_t i = 0; entries && i < size && i < aMax; ++i)
        {
            aOut[i] = Read<uint64_t>(entries + i * 8);
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

std::string ListNames(uintptr_t aMetadata, size_t aOffset)
{
    if (!aMetadata || !aOffset)
    {
        return "?";
    }
    uint64_t names[256] = {};
    uint32_t size = 0;
    if (!SafeReadList(aMetadata, aOffset, names, 256, &size))
    {
        return "(fault)";
    }
    std::string out = std::to_string(size) + ":";
    for (uint32_t i = 0; i < size && i < 256; ++i)
    {
        out += " " + std::to_string(i) + "=" + Text(names[i]);
    }
    return out;
}

void Schedule()
{
    uint32_t count = 0;
    if (!SafeReadSchedule(&count))
    {
        g_scheduleFailed = true;
        Log("schedule: a read faulted - schedule logging stopped");
        return;
    }
    if (!g_tracksOffset)
    {
        if (auto* cls = RED4ext::CRTTISystem::Get()->GetClass("audioRadioStationMetadata"))
        {
            if (auto* p = cls->GetProperty(RED4ext::CName("tracks")))
            {
                g_tracksOffset = p->valueOffset;
            }
            if (auto* p = cls->GetProperty(RED4ext::CName("blips")))
            {
                g_blipsOffset = p->valueOffset;
            }
            char buf[96];
            std::snprintf(buf, sizeof(buf), "schedule: metadata tracks at +0x%zx, blips at +0x%zx", g_tracksOffset,
                          g_blipsOffset);
            Log(buf);
        }
    }
    for (uint32_t i = 0; i < count; ++i)
    {
        const Sched& s = g_snap[i];
        const std::string name = Text(s.name);
        // The track list is logged when a station is first seen and again whenever its count changes: a quest can
        // add tracks to a live station. The metadata pointer rides along, so a grown list and a
        // swapped object are told apart.
        if (s.metadata && g_tracksOffset)
        {
            uint32_t trackCount = 0;
            uint64_t scratch[1] = {};
            if (SafeReadList(s.metadata, g_tracksOffset, scratch, 0, &trackCount))
            {
                auto found = g_listedCount.find(s.station);
                if (found == g_listedCount.end() || found->second != trackCount)
                {
                    const bool first = found == g_listedCount.end();
                    g_listedCount[s.station] = trackCount;
                    char meta[48];
                    std::snprintf(meta, sizeof(meta), " metadata=%016llx", static_cast<unsigned long long>(s.metadata));
                    Log(std::string("schedule: ") + name + (first ? " tracks " : " tracks CHANGED ") +
                        ListNames(s.metadata, g_tracksOffset) + meta);
                    if (first)
                    {
                        Log("schedule: " + name + " blips " + ListNames(s.metadata, g_blipsOffset));
                    }
                }
            }
        }
        // An announcement: logged on every change of the queued or playing scene, the request mode or
        // its flags. The scene is a resource path hash, resolved offline.
        {
            char ann[256];
            std::snprintf(ann, sizeof(ann), "queued=%016llx/%s mode=%u playing=%016llx/%s flags=%u%u%u",
                          static_cast<unsigned long long>(s.queuedScene), Text(s.queuedInput).c_str(), s.requestMode,
                          static_cast<unsigned long long>(s.playingScene), Text(s.playingInput).c_str(), s.flags[0],
                          s.flags[1], s.flags[2]);
            auto& lastAnn = g_lastAnnounce[s.station];
            if (lastAnn != ann)
            {
                const bool first = lastAnn.empty();
                lastAnn = ann;
                if (!first || s.queuedScene || s.playingScene)
                {
                    char clk[48];
                    std::snprintf(clk, sizeof(clk), " state=%d clock=%.2f ", s.state, s.clock);
                    Log("announce " + name + clk + ann);
                }
            }
        }

        // The remaining list's words, on every change of the list. `remain <station> <count>: w0 w1 ...`
        {
            std::string remain = std::to_string(s.remaining) + " cap=" + std::to_string(s.remainCapacity) + ":";
            for (uint32_t w = 0; w < s.remainWords; ++w)
            {
                char word[16];
                std::snprintf(word, sizeof(word), " %08x", s.remainRaw[w]);
                remain += word;
            }
            auto& lastRemain = g_lastRemain[s.station];
            if (lastRemain != remain)
            {
                lastRemain = remain;
                Log("remain " + name + " " + remain);
            }
        }

        // Logged on every change of state, pick count, current track or blip; the clock rides along.
        char key[160];
        std::snprintf(key, sizeof(key), "%d|%u|%llx|%llx|%llx", s.state, s.picks,
                      static_cast<unsigned long long>(s.current), static_cast<unsigned long long>(s.blip),
                      static_cast<unsigned long long>(s.queued));
        auto& last = g_lastSched[s.station];
        if (last == key)
        {
            continue;
        }
        last = key;
        char line[200];
        std::snprintf(line, sizeof(line), " state=%d picks=%u active=%u remaining=%u blipCursor=%u clock=%.2f rng=%016llx",
                      s.state, s.picks, s.active, s.remaining, s.blipCursor, s.clock,
                      static_cast<unsigned long long>(s.rng));
        Log("sched " + name + line + " track=" + Text(s.current) + " blip=" + Text(s.blip) +
            " queued=" + Text(s.queued));
    }

    // Array order decides which station wins a DJ token (the last qualifying one).
    std::string order = "stations order:";
    for (uint32_t i = 0; i < count; ++i)
    {
        order += " " + std::to_string(i) + "=" + Text(g_snap[i].name);
    }
    if (order != g_lastOrder)
    {
        g_lastOrder = order;
        Log(order);
    }

    // The DJ table, on every change of a station or listener value; the distance rides along.
    std::string djKey;
    std::string dj = "dj table:";
    for (uint32_t d = 0; d < 6; ++d)
    {
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%llx|%llx;", static_cast<unsigned long long>(g_dj[d].name),
                      static_cast<unsigned long long>(g_dj[d].value));
        djKey += buf;
        char entry[96];
        std::snprintf(entry, sizeof(entry), " v=%llx d2=%.1f]", static_cast<unsigned long long>(g_dj[d].value),
                      g_dj[d].distSq);
        dj += std::string(" [") + kDjSpeakers[d] + " " + Text(g_dj[d].name) + entry;
    }
    if (djKey != g_lastDj)
    {
        g_lastDj = djKey;
        Log(dj);
    }

    // The custom-sound slot table: whether a stopped station's playing id leaves it is what decides
    // where AudioXL can retire a voice the renderer is no longer called for.
    if (!g_slotsFailed)
    {
        uint16_t slotCount = 0;
        if (!SafeReadSlots(&slotCount))
        {
            g_slotsFailed = true;
            Log("slots: a read faulted - slot logging stopped");
            return;
        }
        std::string key = std::to_string(slotCount) + ":";
        std::string text = "slots count=" + std::to_string(slotCount) + ":";
        for (uint16_t i = 0; i < slotCount && i < kMaxSlots; ++i)
        {
            const Slot& sl = g_slots[i];
            char buf[48];
            std::snprintf(buf, sizeof(buf), "%u/%u;", sl.row, sl.playingId);
            key += buf;
            char pos[64];
            std::snprintf(pos, sizeof(pos), " pid=%u row=%u pos=%u]", sl.playingId, sl.row, sl.pos);
            text += " [" + std::to_string(i) + " " + Text(sl.name) + pos;
        }
        if (key != g_lastSlots)
        {
            g_lastSlots = key;
            Log(text);
        }
    }
}

// The walk reads engine memory by offset, so a wrong offset on another build would fault. SEH
// keeps a bad read from taking the game down: the probe reports once and stops.
bool SafeWalk(std::string& aReport)
{
    __try
    {
        Walk(aReport);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void CheckLiveRadios();
void SweepListeners();
void WriteMeters();
void WatchVehicleParams();
void WriteChannels();

// Scroll Lock writes a marker line, so a pop heard in game can be matched to the lines around it.
void PollMarker()
{
    static bool down = false;
    static uint32_t count = 0;
    const bool now = (GetAsyncKeyState(VK_SCROLL) & 0x8000) != 0;
    if (now && !down)
    {
        Log("MARK " + std::to_string(++count) + " - heard in game");
    }
    down = now;
}

bool OnUpdate(RED4ext::CGameApplication*)
{
    PollMarker();
    if (g_failed)
    {
        return false;
    }
    const uint64_t now = GetTickCount64();
    if (!g_scheduleFailed && now - g_lastSchedule >= kScheduleMs)
    {
        g_lastSchedule = now;
        Schedule();
        CheckLiveRadios();
        SweepListeners();
        WriteMeters();
        WatchVehicleParams();
        WriteChannels();
    }
    if (now - g_lastTick < 1000)
    {
        return false;
    }
    g_lastTick = now;

    std::string report;
    if (!SafeWalk(report))
    {
        g_failed = true;
        Log("a read faulted - offsets are not this build's. Probe stopped.");
        return false;
    }
    if (!report.empty())
    {
        if (!report.empty() && report.back() == '\n')
        {
            report.pop_back();
        }
        Log(report);
    }
    return false;
}
} // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"RadioStationProbe";
    aInfo->author = L"Spuddeh";
    aInfo->version = RED4EXT_V1_SEMVER(0, 2, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}

namespace
{
// **A native's code is reached through a handler table the game fills at runtime**, indexed by the
// function's own index (`+0xAC`), so the address cannot be read from the file. Logged once after
// RTTI registration as an RVA, for the disassembler.
constexpr uint32_t kHashHandlerTable = 0x5A7D28A9;  // RED4ext's CBaseFunction_Handlers

void LogNativeHandlers()
{
    const auto table = reinterpret_cast<void**>(ResolveByHash(kHashHandlerTable));
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    auto* cls = RED4ext::CRTTISystem::Get()->GetClass("vehicleBaseObject");
    if (!table || !cls)
    {
        Log("native handlers: no table or no vehicleBaseObject class");
        return;
    }
    const char* names[] = {"ToggleRadioReceiver", "SetRadioReceiverStation", "NextRadioReceiverStation",
                           "IsRadioReceiverActive", "GetRadioReceiverStationName", "ToggleRadioReceiverForced"};
    for (const char* name : names)
    {
        auto* fn = cls->GetFunction(RED4ext::CName(name));
        if (!fn)
        {
            Log(std::string("native handlers: vehicleBaseObject::") + name + " not found");
            continue;
        }
        const auto index = static_cast<int32_t>(fn->GetRegIndex());
        const auto handler = (index >= 0 && index < 0x10000) ? reinterpret_cast<uintptr_t>(table[index]) : 0;
        char buf[160];
        std::snprintf(buf, sizeof(buf), "native handlers: vehicleBaseObject::%s index %d -> rva %llx", name, index,
                      static_cast<unsigned long long>(handler ? handler - base : 0));
        Log(buf);
    }
}
} // namespace

// --- traffic car radios ----------------------------------------------------------------------------
// A traffic car's radio is started by `audio::TrafficVehicleEmitter::PlayRadio` when its engine sound
// starts (by chance) and cut by `StopRadio` when the engine sound stops. Each is logged with the car's
// distance from the audio listener, so a heard pop or cut can be matched to one line.
//
// The car is tied to its emitter by the entity id `InitializeAudio` posts as the
// `traffic_vehicle_entity_id` switch, which the emitter keeps at +0x138. The car's position is the
// argument of `UpdateAudio`, which hands it to the sound system every frame the car's audio is on.
namespace
{
struct HookTarget
{
    const char* name;
    uint32_t hash;
    uintptr_t rva;
    uint8_t prologue[8];
};

constexpr HookTarget kPlayRadio{"TrafficVehicleEmitter::PlayRadio", 2826768706, 0x9d8684,
                                {0x4c, 0x8b, 0xdc, 0x49, 0x89, 0x5b, 0x10, 0x49}};
constexpr HookTarget kStopRadio{"TrafficVehicleEmitter::StopRadio", 2874413394, 0x13e3868,
                                {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x74}};
constexpr HookTarget kPerformAudioAction{"TrafficDynamicMovementVehicles::PerformAudioAction", 115156017, 0x88d6c4,
                                         {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x6c}};
constexpr HookTarget kUpdateAudio{"TrafficDynamicMovementVehicles::UpdateAudio", 1823610974, 0x414224,
                                  {0x48, 0x89, 0x5c, 0x24, 0x10, 0x55, 0x56, 0x41}};
constexpr HookTarget kInitializeAudio{"TrafficDynamicMovementVehicles::InitializeAudio", 1133978076, 0x11b0e34,
                                      {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x74}};
constexpr HookTarget kGetRandomStation{"RadioSystem::GetRandomStation(ArraySpan<CName>)", 68099298, 0x9d8240,
                                       {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x74}};
constexpr HookTarget kAmbientPlay{"AmbientPaletteSpace::PostPlayRadioEvent", 1552948042, 0x9d7934,
                                  {0x48, 0x8b, 0xc4, 0x48, 0x89, 0x58, 0x10, 0x48}};
constexpr HookTarget kAmbientStop{"AmbientPaletteSpace::PostStopEvent", 2277250296, 0x9d7af8,
                                  {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x74}};
constexpr HookTarget kPostBroadcast{"RadioEmitter::PostRadioBroadcastEvent", 3062830569, 0x9da22c,
                                    {0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x7c}};
// Every radio emitter dies here: TrafficVehicleEmitter's destructor (0x9d8910) tail-jumps into it. A car that
// despawns frees its emitter without StopRadio, so stored emitter pointers are dropped here, before the free.
constexpr HookTarget kRadioEmitterDtor{"RadioEmitter::~RadioEmitter", 2727086681, 0x9d9ef0,
                                       {0x40, 0x53, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8d}};

// The car's receiver sound, as TrafficVehicleEmitter::IsRadioPlaying (0x9dadec) reads it: the emitter's
// sounds (+0x58, count +0x64), each a pointer to a pointer to an entry with its event name at +0x8, the
// Wwise playing id at +0x44 and a state byte at +0x59. The listener counts only for the entry named by the
// vehicle audio data's +0x80 with a playing id and a state other than 4 or 5.
constexpr size_t kEmitterSounds = 0x58;
constexpr size_t kEmitterSoundCount = 0x64;
constexpr size_t kEmitterBroadcastEvent = 0x120;  // RadioEmitter: the broadcast event PostRadioBroadcastEvent posts
constexpr size_t kEmitterMetadata = 0x140;
constexpr size_t kMetadataReceiverEvent = 0x80;
constexpr size_t kSoundName = 0x8;
constexpr size_t kSoundPlayingId = 0x44;
constexpr size_t kSoundState = 0x59;
constexpr uintptr_t kRvaTrafficEmitterVtbl = 0x2b458a0;

// The emitter, as PlayRadio, StopRadio and HandleSwitchLogic read it.
constexpr size_t kEmitterStation = 0x110;        // CName; s_noneStation when the radio is off
constexpr size_t kEmitterEntityId = 0x138;       // traffic_vehicle_entity_id
constexpr size_t kEmitterParamEntityId = 0x108;  // RadioEmitter::GetEntityId, the RTPC key
constexpr size_t kEmitterBroadcastChannel = 0x128; // channel stored by PostRadioBroadcastEvent (uint32)
constexpr size_t kEmitterFlags = 0x150;          // the state UpdateSounds compares against its last value
constexpr size_t kEmitterLastFlags = 0x151;      // UpdateSounds' last value; a bit falling here is a stop
constexpr size_t kEmitterForceOff = 0x155;       // while set, UpdateSounds treats every bit as off
constexpr size_t kEmitterRadioDisabled = 0x152;  // DisableAbilityToPlayRadio
constexpr size_t kEmitterRadioOn = 0x153;        // set by PlayRadio

// The traffic movement object and the audio data InitializeAudio is handed.
constexpr size_t kMovementAudioActive = 0x430;
constexpr size_t kAudioDataEntityId = 0x8;

// The listener position, as audio::SoundSystem::GetListenerPosition reads it (engine root +0xa8).
constexpr size_t kSoundSystemListener = 0x10;

constexpr const char* kActionNames[] = {"StartEngine", "StopEngine", "StartWheel", "StopWheel", "StartRainLoop",
                                        "StopRainLoop", "Horn", "HornForced", "DisableAbilityToPlayRadio",
                                        "StartBrakeLoop", "EndBrakeLoop", "ApplyBrake", "ReleaseBrake"};

using PlayRadioFn = void (*)(void* aEmitter);
using StopRadioFn = void (*)(void* aEmitter);
using EmitterDtorFn = void (*)(void* aEmitter);
using PerformAudioActionFn = void (*)(void* aMovement, uint32_t aAction);
using UpdateAudioFn = void (*)(void* aMovement, const float* aPosition);
using InitializeAudioFn = void (*)(void* aMovement, const void* aAudioData);
using GetRandomStationFn = void (*)(void* aRadioSystem, uint64_t* aOut, const uint64_t* const* aSpan);

PlayRadioFn g_origPlayRadio = nullptr;
StopRadioFn g_origStopRadio = nullptr;
EmitterDtorFn g_origEmitterDtor = nullptr;
PerformAudioActionFn g_origPerformAudioAction = nullptr;
UpdateAudioFn g_origUpdateAudio = nullptr;
InitializeAudioFn g_origInitializeAudio = nullptr;
GetRandomStationFn g_origGetRandomStation = nullptr;

struct Car
{
    float pos[3];
    bool hasPos;
    uint64_t entityId;
};

SRWLOCK g_carsLock = SRWLOCK_INIT;
std::unordered_map<uintptr_t, Car> g_cars;              // by movement object
std::unordered_map<uint64_t, uintptr_t> g_carByEntity;  // entity id -> movement object
std::string g_lastSpan;
uint64_t g_startTick = 0;

bool SafeReadListener(float* aOut)
{
    __try
    {
        const auto rootSlot = ResolveByHash(kHashEngineRoot);
        const auto root = rootSlot ? Read<uintptr_t>(rootSlot) : 0;
        const auto sound = root ? Read<uintptr_t>(root + kRootAudioSystem) : 0;
        if (!sound)
        {
            return false;
        }
        for (int i = 0; i < 3; ++i)
        {
            aOut[i] = Read<float>(sound + kSoundSystemListener + i * 4);
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

struct EmitterState
{
    uint64_t station;
    uint64_t entityId;
    uint8_t flags;
    uint8_t lastFlags;
    uint8_t forceOff;
    uint8_t radioDisabled;
    uint8_t radioOn;
};

bool SafeReadEmitter(void* aEmitter, EmitterState* aOut)
{
    __try
    {
        const auto e = reinterpret_cast<uintptr_t>(aEmitter);
        aOut->station = Read<uint64_t>(e + kEmitterStation);
        aOut->entityId = Read<uint64_t>(e + kEmitterEntityId);
        aOut->flags = Read<uint8_t>(e + kEmitterFlags);
        aOut->lastFlags = Read<uint8_t>(e + kEmitterLastFlags);
        aOut->forceOff = Read<uint8_t>(e + kEmitterForceOff);
        aOut->radioDisabled = Read<uint8_t>(e + kEmitterRadioDisabled);
        aOut->radioOn = Read<uint8_t>(e + kEmitterRadioOn);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool SafeReadByte(uintptr_t aAddress, uint8_t* aOut)
{
    __try
    {
        *aOut = Read<uint8_t>(aAddress);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool SafeReadU64(uintptr_t aAddress, uint64_t* aOut)
{
    __try
    {
        *aOut = Read<uint64_t>(aAddress);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// Seconds since the plugin loaded, and the distance from the listener to a car, or -1 when the car's
// position is not known.
std::string Stamp()
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "t=%.3f", static_cast<double>(GetTickCount64() - g_startTick) / 1000.0);
    return buf;
}

float DistanceTo(const Car* aCar)
{
    float listener[3];
    if (!aCar || !aCar->hasPos || !SafeReadListener(listener))
    {
        return -1.0f;
    }
    const float dx = aCar->pos[0] - listener[0];
    const float dy = aCar->pos[1] - listener[1];
    const float dz = aCar->pos[2] - listener[2];
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

// The car for an entity id, copied out under the lock.
bool CarByEntity(uint64_t aEntityId, Car* aOut, uintptr_t* aMovement)
{
    AcquireSRWLockShared(&g_carsLock);
    bool found = false;
    const auto byEntity = g_carByEntity.find(aEntityId);
    if (byEntity != g_carByEntity.end())
    {
        const auto car = g_cars.find(byEntity->second);
        if (car != g_cars.end())
        {
            *aOut = car->second;
            *aMovement = byEntity->second;
            found = true;
        }
    }
    ReleaseSRWLockShared(&g_carsLock);
    return found;
}

std::string RadioLine(const char* aWhat, const EmitterState& aState, uint64_t aStation)
{
    Car car{};
    uintptr_t movement = 0;
    const bool known = CarByEntity(aState.entityId, &car, &movement);
    char buf[256];
    std::snprintf(buf, sizeof(buf), "traffic radio %s %s ent=%llx car=%llx dist=%.1f station=%s flags=%02x last=%02x off=%u disabled=%u",
                  aWhat, Stamp().c_str(), static_cast<unsigned long long>(aState.entityId),
                  static_cast<unsigned long long>(movement), known ? DistanceTo(&car) : -1.0f, Text(aStation).c_str(),
                  aState.flags, aState.lastFlags, aState.forceOff, aState.radioDisabled);
    return buf;
}

// A traffic radio makes sound only while its station is active and holds a voice; a station that is not
// among the ones the engine is playing leaves the car silent. Each radio between PLAY and STOP is checked
// on the 100 ms schedule and logs when it turns audible or silent; STOP says whether it was ever heard.
struct LiveRadio
{
    uint64_t station;
    uint64_t startTick;
    bool audible;
    bool everAudible;
    uintptr_t emitter;
    std::string lastReceiver;
};

struct ReceiverState
{
    uint64_t receiverEvent;   // vehicle audio data +0x80, the name IsRadioPlaying looks for
    uint64_t broadcastEvent;  // emitter +0x120
    uint32_t count;
    uint32_t listed;
    uint64_t names[8];
    uint32_t ids[8];
    uint8_t states[8];
};

// The vehicle audio data at +0x140 exists only on a TrafficVehicleEmitter; on any other radio emitter (a player
// car's receiver, a world device) that slot is something else, so it is read only behind the vtable check.
bool SafeReadReceiver(uintptr_t aEmitter, ReceiverState* aOut)
{
    static const uintptr_t trafficVtbl = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + kRvaTrafficEmitterVtbl;
    __try
    {
        const bool traffic = Read<uintptr_t>(aEmitter) == trafficVtbl;
        const auto metadata = traffic ? Read<uintptr_t>(aEmitter + kEmitterMetadata) : 0;
        aOut->receiverEvent = metadata ? Read<uint64_t>(metadata + kMetadataReceiverEvent) : 0;
        aOut->broadcastEvent = Read<uint64_t>(aEmitter + kEmitterBroadcastEvent);
        const auto sounds = Read<uintptr_t>(aEmitter + kEmitterSounds);
        aOut->count = Read<uint32_t>(aEmitter + kEmitterSoundCount);
        aOut->listed = 0;
        for (uint32_t i = 0; sounds && i < aOut->count && i < 8; ++i)
        {
            const auto element = Read<uintptr_t>(sounds + i * 8);
            const auto entry = element ? Read<uintptr_t>(element) : 0;
            aOut->names[i] = entry ? Read<uint64_t>(entry + kSoundName) : 0;
            aOut->ids[i] = entry ? Read<uint32_t>(entry + kSoundPlayingId) : 0;
            aOut->states[i] = entry ? Read<uint8_t>(entry + kSoundState) : 0xff;
            ++aOut->listed;
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// `recv=<name>` is what IsRadioPlaying looks for; each sound is `name:id/state`, `*` marking the receiver.
std::string ReceiverText(const ReceiverState& aState)
{
    std::string out = "recv=" + Text(aState.receiverEvent) + " bcast=" + Text(aState.broadcastEvent) +
                      " sounds=" + std::to_string(aState.count) + ":";
    for (uint32_t i = 0; i < aState.listed; ++i)
    {
        char buf[48];
        std::snprintf(buf, sizeof(buf), ":%u/%u", aState.ids[i], aState.states[i]);
        out += std::string(" ") + (aState.names[i] == aState.receiverEvent ? "*" : "") + Text(aState.names[i]) + buf;
    }
    return out;
}

SRWLOCK g_liveLock = SRWLOCK_INIT;
std::unordered_map<uint64_t, LiveRadio> g_live;  // by entity id
std::unordered_map<uintptr_t, uint64_t> g_others; // non-traffic receivers tuned to a station, by emitter

// --- Wwise queries ---
// AK::SoundEngine::Query, statically linked (2.31 RVAs, names from cp2077-symbols). Each is refused unless its
// first bytes match. They take Wwise's own lock, so they are callable from the game thread.
using AkGetGameObjectFromPlayingIDFn = uint64_t (*)(uint32_t aPlayingId);
using AkGetRTPCValueFn = int (*)(uint32_t aRtpc, uint64_t aGameObject, uint32_t aPlayingId, float* aValue, int* aType);
using AkGetIsGameObjectActiveFn = bool (*)(uint64_t aGameObject);
using AkGetPlayingIDsFn = int (*)(uint64_t aGameObject, uint32_t* aCount, uint32_t* aIds);
using AkGetListenersFn = int (*)(uint64_t aGameObject, uint64_t* aIds, uint32_t* aCount);
using AkGetDryLevelFn = int (*)(uint64_t aEmitter, uint64_t aListener, float* aLevel);
using AkGetEventIDFn = uint32_t (*)(uint32_t aPlayingId);
using AkGetMaxRadiusFn = float (*)(uint64_t aGameObject);
// AkWorldTransform: front float[3] at 0, top float[3] at 0xc, position double[3] at 0x18 (0x30 bytes, read from
// GetPosition's copy of AkSoundPositionRef::GetDefaultPosition). An object with no position gets that default.
using AkGetPositionFn = int (*)(uint64_t aGameObject, uint8_t* aTransform);

struct AkQuery
{
    AkGetGameObjectFromPlayingIDFn gameObject = nullptr;
    AkGetRTPCValueFn rtpc = nullptr;
    AkGetIsGameObjectActiveFn active = nullptr;
    AkGetPlayingIDsFn playing = nullptr;
    AkGetListenersFn listeners = nullptr;
    AkGetDryLevelFn dry = nullptr;
    AkGetEventIDFn event = nullptr;
    AkGetMaxRadiusFn radius = nullptr;
    AkGetPositionFn position = nullptr;
    bool ok = false;
};

template <typename T>
T ResolveRva(uintptr_t aRva, std::initializer_list<uint8_t> aPrologue)
{
    const auto address = reinterpret_cast<uint8_t*>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + aRva);
    size_t i = 0;
    for (const auto b : aPrologue)
    {
        if (address[i++] != b)
        {
            return nullptr;
        }
    }
    return reinterpret_cast<T>(address);
}

const AkQuery& Ak()
{
    static const AkQuery q = []()
    {
        AkQuery r;
        r.gameObject = ResolveRva<AkGetGameObjectFromPlayingIDFn>(0x1ad2680, {0x8B, 0xD1, 0x48, 0x8B, 0x0D});
        r.rtpc = ResolveRva<AkGetRTPCValueFn>(0x1ad2c60, {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x6C});
        r.active = ResolveRva<AkGetIsGameObjectActiveFn>(0x1ad26a0, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B});
        r.playing = ResolveRva<AkGetPlayingIDsFn>(0x1ad2a10, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x0D});
        r.listeners = ResolveRva<AkGetListenersFn>(0x1ad27c0, {0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x6C});
        r.dry = ResolveRva<AkGetDryLevelFn>(0x1ad25d0, {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74});
        r.event = ResolveRva<AkGetEventIDFn>(0x1ad2450, {0x8B, 0xD1, 0x48, 0x8B, 0x0D});
        r.radius = ResolveRva<AkGetMaxRadiusFn>(0x1ad28b0, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x8B});
        r.position = ResolveRva<AkGetPositionFn>(0x1ad2a40, {0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83});
        r.ok = r.gameObject && r.rtpc && r.active && r.playing && r.listeners && r.dry && r.event && r.radius &&
               r.position;
        return r;
    }();
    return q;
}

// Wwise's global lock, a CRITICAL_SECTION the audio thread holds for its whole render pass. Every query above
// enters it, so calling them from the game thread waits out the render pass: milliseconds of stall. Each batch of
// queries tries the lock first and is skipped, to retry on the next pass, while the audio thread holds it. The
// section is re-entrant, so the queries inside take it again freely. Its address is the lea at +0x17 in
// CAkFunctionCritical's enter (0x1af6d90): 48 8D 0D rel32.
LPCRITICAL_SECTION WwiseLock()
{
    static const LPCRITICAL_SECTION lock = []() -> LPCRITICAL_SECTION
    {
        const auto enter = ResolveRva<const uint8_t*>(0x1af6d90, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B});
        if (!enter || enter[0x17] != 0x48 || enter[0x18] != 0x8D || enter[0x19] != 0x0D)
        {
            return nullptr;
        }
        int32_t rel = 0;
        std::memcpy(&rel, enter + 0x1a, sizeof(rel));
        return reinterpret_cast<LPCRITICAL_SECTION>(const_cast<uint8_t*>(enter) + 0x1e + rel);
    }();
    return lock;
}

// RTPC ids (FNV-1 of the names in eventsmetadata.json).
constexpr uint32_t kRtpcBroadcastChannel = 3643107758;  // radio_broadcast_channel (mono receivers)
constexpr uint32_t kRtpcBroadcastLeft = 975869506;      // radio_broadcast_channel_left (stereo receivers)
constexpr uint32_t kRtpcEngageMovingFaster = 139023859; // veh_engage_moving_faster (NPC mixer volume)

// The player's audio listener, as the last voice query reported it; 0 until one has.
uint64_t g_listenerGo = 0;

// One voice as Wwise sees it: its game object, whether that object is active, how many voices it holds, the
// event, the channel RTPCs as resolved for this playing id (value and the scope it came from: 0 default,
// 1 global, 2 game object, 3 playing id, 4 unavailable), the NPC volume RTPC, max radius, and the dry level to
// each listener.
bool SafeAkVoice(uint32_t aPlayingId, char* aBuf, size_t aSize)
{
    const auto& ak = Ak();
    __try
    {
        const uint64_t go = ak.gameObject(aPlayingId);
        if (go == ~0ull)
        {
            std::snprintf(aBuf, aSize, "pid=%u go=none", aPlayingId);
            return true;
        }
        const bool active = ak.active(go);
        uint32_t voices = 0;
        ak.playing(go, &voices, nullptr);
        const uint32_t eventId = ak.event(aPlayingId);
        float chan = -1.0f, left = -1.0f, fast = -1.0f;
        int chanType = 3, leftType = 3, fastType = 3;
        ak.rtpc(kRtpcBroadcastChannel, go, aPlayingId, &chan, &chanType);
        ak.rtpc(kRtpcBroadcastLeft, go, aPlayingId, &left, &leftType);
        ak.rtpc(kRtpcEngageMovingFaster, go, aPlayingId, &fast, &fastType);
        const float radius = ak.radius(go);
        uint64_t listeners[4] = {};
        uint32_t listenerCount = 4;
        ak.listeners(go, listeners, &listenerCount);
        if (listenerCount)
        {
            g_listenerGo = listeners[0];
        }
        int n = std::snprintf(aBuf, aSize,
                              "pid=%u go=%llx active=%u voices=%u event=%u chan=%.0f/t%d left=%.0f/t%d fast=%.2f/t%d radius=%.1f listeners=%u",
                              aPlayingId, static_cast<unsigned long long>(go), active ? 1u : 0u, voices, eventId,
                              chan, chanType, left, leftType, fast, fastType, radius, listenerCount);
        alignas(8) uint8_t at[0x30] = {};
        const int atResult = ak.position(go, at);
        const auto* pos = reinterpret_cast<const double*>(at + 0x18);
        n += std::snprintf(aBuf + n, aSize - n, " pos=%d:%.1f,%.1f,%.1f", atResult, pos[0], pos[1], pos[2]);
        for (uint32_t i = 0; i < listenerCount && i < 4 && n > 0 && n < static_cast<int>(aSize) - 96; ++i)
        {
            float dry = -1.0f;
            ak.dry(go, listeners[i], &dry);
            alignas(8) uint8_t lt[0x30] = {};
            ak.position(listeners[i], lt);
            const auto* lp = reinterpret_cast<const double*>(lt + 0x18);
            const double dx = pos[0] - lp[0], dy = pos[1] - lp[1], dz = pos[2] - lp[2];
            n += std::snprintf(aBuf + n, aSize - n, " dry[%llx]=%.3f lpos=%.1f,%.1f,%.1f wdist=%.1f",
                               static_cast<unsigned long long>(listeners[i]), dry, lp[0], lp[1], lp[2],
                               std::sqrt(dx * dx + dy * dy + dz * dz));
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

std::string AkVoiceText(uint32_t aPlayingId)
{
    if (!Ak().ok)
    {
        return "ak=unresolved";
    }
    char buf[512];
    if (!SafeAkVoice(aPlayingId, buf, sizeof(buf)))
    {
        std::snprintf(buf, sizeof(buf), "pid=%u ak=fault", aPlayingId);
    }
    return buf;
}

// The playing id of the sound named aName on the emitter, or 0 when it is not playing.
uint32_t PlayingIdOf(const ReceiverState& aState, uint64_t aName)
{
    for (uint32_t i = 0; i < aState.listed; ++i)
    {
        if (aState.names[i] == aName && aState.ids[i] != 0 && aState.states[i] != 4 && aState.states[i] != 5)
        {
            return aState.ids[i];
        }
    }
    return 0;
}

bool SafeStationPlaying(uint64_t aStation, bool* aPlaying)
{
    __try
    {
        *aPlaying = false;
        const auto rootSlot = ResolveByHash(kHashEngineRoot);
        const auto root = rootSlot ? Read<uintptr_t>(rootSlot) : 0;
        const auto audio = root ? Read<uintptr_t>(root + kRootAudioSystem) : 0;
        const auto manager = audio ? Read<uintptr_t>(audio + kAudioRadioManager) : 0;
        if (!manager)
        {
            return false;
        }
        const auto stations = Read<uintptr_t>(manager + kManagerStations);
        const auto count = Read<uint32_t>(manager + kManagerCount);
        for (uint32_t i = 0; stations && i < count && i < kMaxStations; ++i)
        {
            const auto station = Read<uintptr_t>(stations + i * 8);
            if (!station)
            {
                continue;
            }
            uint64_t name = 0;
            Read<GetNameFn>(Read<uintptr_t>(station) + kVtblGetName)(reinterpret_cast<void*>(station), &name);
            if (name == aStation)
            {
                *aPlaying = Read<uint8_t>(station + kStationActive) != 0 &&
                            Read<uint32_t>(station + kStationHandleCount) != 0;
                return true;
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// Reads a stored emitter only while it is still stored, holding the lock the destructor hook takes, so the
// emitter cannot be freed during the read.
bool ReadStoredReceiver(uintptr_t aEmitter, ReceiverState* aOut)
{
    if (!aEmitter)
    {
        return false;
    }
    AcquireSRWLockShared(&g_liveLock);
    bool stored = g_others.count(aEmitter) != 0;
    for (auto it = g_live.begin(); !stored && it != g_live.end(); ++it)
    {
        stored = it->second.emitter == aEmitter;
    }
    const bool read = stored && SafeReadReceiver(aEmitter, aOut);
    ReleaseSRWLockShared(&g_liveLock);
    return read;
}

// Each active station's own voices: a station is an AudioEmitter (RadioStation::PlaySong posts through its
// vtable +8), so its sounds list reads like a receiver's. Stations live for the session, so no lifetime guard.
struct StationVoice
{
    uint64_t name;
    uint64_t sound;
    uint32_t pid;
    uint8_t state;
};

bool SafeStationVoices(StationVoice* aOut, uint32_t aMax, uint32_t* aCount)
{
    *aCount = 0;
    __try
    {
        const auto rootSlot = ResolveByHash(kHashEngineRoot);
        const auto root = rootSlot ? Read<uintptr_t>(rootSlot) : 0;
        const auto audio = root ? Read<uintptr_t>(root + kRootAudioSystem) : 0;
        const auto manager = audio ? Read<uintptr_t>(audio + kAudioRadioManager) : 0;
        if (!manager)
        {
            return true;
        }
        const auto stations = Read<uintptr_t>(manager + kManagerStations);
        const auto count = Read<uint32_t>(manager + kManagerCount);
        for (uint32_t i = 0; stations && i < count && i < kMaxStations; ++i)
        {
            const auto station = Read<uintptr_t>(stations + i * 8);
            if (!station || !Read<uint8_t>(station + kStationActive))
            {
                continue;
            }
            uint64_t name = 0;
            Read<GetNameFn>(Read<uintptr_t>(station) + kVtblGetName)(reinterpret_cast<void*>(station), &name);
            const auto sounds = Read<uintptr_t>(station + kEmitterSounds);
            const auto soundCount = Read<uint32_t>(station + kEmitterSoundCount);
            for (uint32_t k = 0; sounds && k < soundCount && k < 8 && *aCount < aMax; ++k)
            {
                const auto element = Read<uintptr_t>(sounds + k * 8);
                const auto entry = element ? Read<uintptr_t>(element) : 0;
                if (!entry)
                {
                    continue;
                }
                aOut[*aCount] = StationVoice{name, Read<uint64_t>(entry + kSoundName),
                                             Read<uint32_t>(entry + kSoundPlayingId), Read<uint8_t>(entry + kSoundState)};
                ++*aCount;
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void CheckLiveRadios()
{
    AcquireSRWLockShared(&g_liveLock);
    const auto live = g_live;
    const auto others = g_others;
    ReleaseSRWLockShared(&g_liveLock);
    const uint64_t now = GetTickCount64();
    // `wwise` lines, once a second: every playing traffic receiver and every other tuned receiver.
    static uint64_t lastWwise = 0;
    const auto wwiseLock = WwiseLock();
    if (now - lastWwise >= 1000 && wwiseLock && TryEnterCriticalSection(wwiseLock))
    {
        lastWwise = now;
        for (const auto& [entity, radio] : live)
        {
            ReceiverState receiver{};
            if (!ReadStoredReceiver(radio.emitter, &receiver))
            {
                continue;
            }
            const uint32_t pid = PlayingIdOf(receiver, receiver.receiverEvent);
            if (!pid)
            {
                continue;
            }
            Car car{};
            uintptr_t movement = 0;
            const bool known = CarByEntity(entity, &car, &movement);
            char head[192];
            std::snprintf(head, sizeof(head), "wwise traffic %s ent=%llx dist=%.1f station=%s recv=%s ", Stamp().c_str(),
                          static_cast<unsigned long long>(entity), known ? DistanceTo(&car) : -1.0f,
                          Text(radio.station).c_str(), Text(receiver.receiverEvent).c_str());
            Log(head + AkVoiceText(pid));
        }
        StationVoice voices[64];
        uint32_t voiceCount = 0;
        if (SafeStationVoices(voices, 64, &voiceCount))
        {
            for (uint32_t i = 0; i < voiceCount; ++i)
            {
                char head[192];
                std::snprintf(head, sizeof(head), "wwise station %s %s sound=%s state=%u ", Stamp().c_str(),
                              Text(voices[i].name).c_str(), Text(voices[i].sound).c_str(), voices[i].state);
                Log(head + (voices[i].pid ? AkVoiceText(voices[i].pid) : std::string("pid=0")));
            }
        }
        for (const auto& [emitter, station] : others)
        {
            ReceiverState receiver{};
            if (!ReadStoredReceiver(emitter, &receiver))
            {
                continue;
            }
            const uint32_t pid = PlayingIdOf(receiver, receiver.broadcastEvent);
            if (!pid)
            {
                continue;
            }
            char head[192];
            std::snprintf(head, sizeof(head), "wwise other %s emitter=%llx station=%s bcast=%s ", Stamp().c_str(),
                          static_cast<unsigned long long>(emitter), Text(station).c_str(),
                          Text(receiver.broadcastEvent).c_str());
            Log(head + AkVoiceText(pid));
        }
        LeaveCriticalSection(wwiseLock);
    }
    for (const auto& [entity, radio] : live)
    {
        ReceiverState receiver{};
        if (ReadStoredReceiver(radio.emitter, &receiver))
        {
            const std::string text = ReceiverText(receiver);
            if (text != radio.lastReceiver)
            {
                AcquireSRWLockExclusive(&g_liveLock);
                const auto found = g_live.find(entity);
                if (found != g_live.end())
                {
                    found->second.lastReceiver = text;
                }
                ReleaseSRWLockExclusive(&g_liveLock);
                char head[96];
                std::snprintf(head, sizeof(head), "traffic receiver %s ent=%llx after=%.2fs ", Stamp().c_str(),
                              static_cast<unsigned long long>(entity),
                              static_cast<double>(now - radio.startTick) / 1000.0);
                Log(head + text);
            }
        }
        bool playing = false;
        if (!SafeStationPlaying(radio.station, &playing) || playing == radio.audible)
        {
            continue;
        }
        AcquireSRWLockExclusive(&g_liveLock);
        const auto found = g_live.find(entity);
        if (found != g_live.end())
        {
            found->second.audible = playing;
            found->second.everAudible |= playing;
        }
        ReleaseSRWLockExclusive(&g_liveLock);
        Car car{};
        uintptr_t movement = 0;
        const bool known = CarByEntity(entity, &car, &movement);
        char buf[224];
        std::snprintf(buf, sizeof(buf), "traffic %s %s ent=%llx dist=%.1f station=%s after=%.2fs",
                      playing ? "AUDIBLE" : "SILENT", Stamp().c_str(), static_cast<unsigned long long>(entity),
                      known ? DistanceTo(&car) : -1.0f, Text(radio.station).c_str(),
                      static_cast<double>(now - radio.startTick) / 1000.0);
        Log(buf);
    }
}

void DetourPlayRadio(void* aEmitter)
{
    g_origPlayRadio(aEmitter);
    EmitterState state{};
    if (SafeReadEmitter(aEmitter, &state))
    {
        // PlayRadio leaves the radio off when the pick was s_noneStation; only a station that started is a pop.
        if (state.radioOn)
        {
            AcquireSRWLockExclusive(&g_liveLock);
            g_live[state.entityId] = LiveRadio{state.station, GetTickCount64(), false, false,
                                               reinterpret_cast<uintptr_t>(aEmitter), std::string()};
            ReleaseSRWLockExclusive(&g_liveLock);
        }
        Log(RadioLine(state.radioOn ? "PLAY" : "PLAY-none", state, state.station));
    }
}

// The game's vectored handler ends the process on a first-chance access violation before SEH runs, so a freed
// emitter must never be read: every stored emitter pointer leaves g_live and g_others here.
void DetourEmitterDtor(void* aEmitter)
{
    const auto emitter = reinterpret_cast<uintptr_t>(aEmitter);
    AcquireSRWLockExclusive(&g_liveLock);
    g_others.erase(emitter);
    for (auto it = g_live.begin(); it != g_live.end();)
    {
        it = it->second.emitter == emitter ? g_live.erase(it) : std::next(it);
    }
    ReleaseSRWLockExclusive(&g_liveLock);
    g_origEmitterDtor(aEmitter);
}

void DetourStopRadio(void* aEmitter)
{
    EmitterState before{};
    const bool read = SafeReadEmitter(aEmitter, &before);
    g_origStopRadio(aEmitter);
    EmitterState after{};
    // StopRadio does nothing when the station is already none, so only a change is a cut.
    if (read && SafeReadEmitter(aEmitter, &after) && after.station != before.station)
    {
        AcquireSRWLockExclusive(&g_liveLock);
        const auto found = g_live.find(before.entityId);
        const char* heard = found == g_live.end() ? "?" : found->second.audible ? "now" : found->second.everAudible ? "earlier" : "never";
        if (found != g_live.end())
        {
            g_live.erase(found);
        }
        ReleaseSRWLockExclusive(&g_liveLock);
        Log(RadioLine("STOP", before, before.station) + " heard=" + heard);
    }
}

void DetourPerformAudioAction(void* aMovement, uint32_t aAction)
{
    g_origPerformAudioAction(aMovement, aAction);
    // Engine edges and the radio switch-off only; the brake and wheel actions fire every few frames.
    if (aAction != 0 && aAction != 1 && aAction != 8)
    {
        return;
    }
    AcquireSRWLockShared(&g_carsLock);
    const auto found = g_cars.find(reinterpret_cast<uintptr_t>(aMovement));
    const Car car = found != g_cars.end() ? found->second : Car{};
    ReleaseSRWLockShared(&g_carsLock);
    char buf[192];
    std::snprintf(buf, sizeof(buf), "traffic action %s %s ent=%llx car=%llx dist=%.1f", kActionNames[aAction],
                  Stamp().c_str(), static_cast<unsigned long long>(car.entityId),
                  static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(aMovement)), DistanceTo(&car));
    Log(buf);
}

void DetourUpdateAudio(void* aMovement, const float* aPosition)
{
    g_origUpdateAudio(aMovement, aPosition);
    uint8_t active = 0;
    if (!aPosition || !SafeReadByte(reinterpret_cast<uintptr_t>(aMovement) + kMovementAudioActive, &active) || !active)
    {
        return;
    }
    AcquireSRWLockExclusive(&g_carsLock);
    Car& car = g_cars[reinterpret_cast<uintptr_t>(aMovement)];
    car.pos[0] = aPosition[0];
    car.pos[1] = aPosition[1];
    car.pos[2] = aPosition[2];
    car.hasPos = true;
    ReleaseSRWLockExclusive(&g_carsLock);
}

void DetourInitializeAudio(void* aMovement, const void* aAudioData)
{
    g_origInitializeAudio(aMovement, aAudioData);
    uint64_t entityId = 0;
    if (!aAudioData || !SafeReadU64(reinterpret_cast<uintptr_t>(aAudioData) + kAudioDataEntityId, &entityId))
    {
        return;
    }
    const auto movement = reinterpret_cast<uintptr_t>(aMovement);
    AcquireSRWLockExclusive(&g_carsLock);
    Car& car = g_cars[movement];
    if (car.entityId && car.entityId != entityId)
    {
        g_carByEntity.erase(car.entityId);
    }
    car.entityId = entityId;
    g_carByEntity[entityId] = movement;
    ReleaseSRWLockExclusive(&g_carsLock);
}

// The only caller is PlayRadio, which hands the vehicle's matchingStartupRadioStations as the span.
// Logged whenever the span's contents change, so a run shows whether a custom station ever reaches it.
bool SafeReadSpan(const uint64_t* const* aSpan, uint64_t* aOut, uint32_t aMax, uint32_t* aCount)
{
    __try
    {
        const uint64_t* begin = aSpan[0];
        const uint64_t* end = aSpan[1];
        const auto count = static_cast<uint32_t>(end - begin);
        *aCount = count;
        for (uint32_t i = 0; begin && i < count && i < aMax; ++i)
        {
            aOut[i] = begin[i];
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void DetourGetRandomStation(void* aRadioSystem, uint64_t* aOut, const uint64_t* const* aSpan)
{
    uint64_t names[32] = {};
    uint32_t count = 0;
    const bool read = aSpan && SafeReadSpan(aSpan, names, 32, &count);
    g_origGetRandomStation(aRadioSystem, aOut, aSpan);
    if (!read)
    {
        return;
    }
    std::string span = std::to_string(count) + ":";
    for (uint32_t i = 0; i < count && i < 32; ++i)
    {
        span += " " + Text(names[i]);
    }
    if (span != g_lastSpan)
    {
        g_lastSpan = span;
        uint64_t picked = 0;
        SafeReadU64(reinterpret_cast<uintptr_t>(aOut), &picked);
        Log("traffic span " + span + " -> " + Text(picked));
    }
}

// --- ambient palette radios ---
// A palette space keeps five `ambient_palette_radio` emitters (slots 0-4). PostPlayRadioEvent moves one to a
// tag's position and tunes it to the brush's station; PostStopEvent tunes it to station_none, which removes
// it as a listener. Each is logged with the tag position and its distance from the listener, so a pop can
// be found on the map. Slots 5 and up are the palette's other sounds and are not logged.
using AmbientPlayFn = void (*)(void* aSpace, uint64_t aEvent, uint32_t aSlot, const float* aPosition, uint64_t aStation);
using AmbientStopFn = void (*)(void* aSpace, uint64_t aEvent, uint32_t aSlot);
AmbientPlayFn g_origAmbientPlay = nullptr;
AmbientStopFn g_origAmbientStop = nullptr;

struct AmbientSlot
{
    float pos[3];
    uint64_t station;
    uint64_t startTick;
};
SRWLOCK g_ambientLock = SRWLOCK_INIT;
std::unordered_map<uint64_t, AmbientSlot> g_ambient;  // by space pointer and slot

float DistanceFromListener(const float* aPos)
{
    float listener[3];
    if (!SafeReadListener(listener))
    {
        return -1.0f;
    }
    const float dx = aPos[0] - listener[0];
    const float dy = aPos[1] - listener[1];
    const float dz = aPos[2] - listener[2];
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

bool SafeReadVec3(const float* aSource, float* aOut)
{
    __try
    {
        aOut[0] = aSource[0];
        aOut[1] = aSource[1];
        aOut[2] = aSource[2];
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void DetourAmbientPlay(void* aSpace, uint64_t aEvent, uint32_t aSlot, const float* aPosition, uint64_t aStation)
{
    g_origAmbientPlay(aSpace, aEvent, aSlot, aPosition, aStation);
    float pos[3] = {};
    if (!aPosition || !SafeReadVec3(aPosition, pos))
    {
        return;
    }
    const uint64_t key = (reinterpret_cast<uint64_t>(aSpace) << 4) | (aSlot & 0xf);
    AcquireSRWLockExclusive(&g_ambientLock);
    g_ambient[key] = AmbientSlot{{pos[0], pos[1], pos[2]}, aStation, GetTickCount64()};
    ReleaseSRWLockExclusive(&g_ambientLock);
    char buf[256];
    std::snprintf(buf, sizeof(buf), "ambient PLAY %s slot=%u station=%s event=%s pos=%.1f,%.1f,%.1f dist=%.1f",
                  Stamp().c_str(), aSlot, Text(aStation).c_str(), Text(aEvent).c_str(), pos[0], pos[1], pos[2],
                  DistanceFromListener(pos));
    Log(buf);
}

void DetourAmbientStop(void* aSpace, uint64_t aEvent, uint32_t aSlot)
{
    g_origAmbientStop(aSpace, aEvent, aSlot);
    if (aSlot >= 5)
    {
        return;
    }
    const uint64_t key = (reinterpret_cast<uint64_t>(aSpace) << 4) | (aSlot & 0xf);
    AcquireSRWLockExclusive(&g_ambientLock);
    const auto found = g_ambient.find(key);
    const bool known = found != g_ambient.end();
    const AmbientSlot slot = known ? found->second : AmbientSlot{};
    if (known)
    {
        g_ambient.erase(found);
    }
    ReleaseSRWLockExclusive(&g_ambientLock);
    char buf[256];
    std::snprintf(buf, sizeof(buf), "ambient STOP %s slot=%u station=%s pos=%.1f,%.1f,%.1f dist=%.1f after=%.2fs",
                  Stamp().c_str(), aSlot, known ? Text(slot.station).c_str() : "?", slot.pos[0], slot.pos[1],
                  slot.pos[2], known ? DistanceFromListener(slot.pos) : -1.0f,
                  known ? static_cast<double>(GetTickCount64() - slot.startTick) / 1000.0 : -1.0);
    Log(buf);
}

using PostBroadcastFn = void (*)(void* aEmitter, uint64_t aStation);
PostBroadcastFn g_origPostBroadcast = nullptr;

// Every receiver retunes through here; only traffic emitters are logged. The receiver sound's state is read
// straight after the post, so a post Wwise refuses shows as a zero playing id.
void DetourPostBroadcast(void* aEmitter, uint64_t aStation)
{
    g_origPostBroadcast(aEmitter, aStation);
    static const uintptr_t trafficVtbl = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + kRvaTrafficEmitterVtbl;
    uint64_t vtbl = 0;
    if (!SafeReadU64(reinterpret_cast<uintptr_t>(aEmitter), &vtbl))
    {
        return;
    }
    // SetBroadcastChannelParam keys the channel RTPC on GetEntityId (+0x108), and SetSoundParameter drops the
    // call when that id is 0, so `param_ent=0` means the receiver never learns its channel (+0x128).
    uint64_t paramEntity = 0;
    uint64_t channel = 0;
    SafeReadU64(reinterpret_cast<uintptr_t>(aEmitter) + kEmitterParamEntityId, &paramEntity);
    SafeReadU64(reinterpret_cast<uintptr_t>(aEmitter) + kEmitterBroadcastChannel, &channel);
    char ids[96];
    std::snprintf(ids, sizeof(ids), " param_ent=%llx chan=%u", static_cast<unsigned long long>(paramEntity),
                  static_cast<uint32_t>(channel));
    if (vtbl != trafficVtbl)
    {
        Log(std::string("other post ") + Stamp() + " station=" + Text(aStation) + ids);
        static const uint64_t none = RED4ext::CName("station_none").hash;
        AcquireSRWLockExclusive(&g_liveLock);
        if (aStation == 0 || aStation == none)
        {
            g_others.erase(reinterpret_cast<uintptr_t>(aEmitter));
        }
        else
        {
            g_others[reinterpret_cast<uintptr_t>(aEmitter)] = aStation;
        }
        ReleaseSRWLockExclusive(&g_liveLock);
        return;
    }
    EmitterState state{};
    ReceiverState receiver{};
    if (!SafeReadEmitter(aEmitter, &state) || !SafeReadReceiver(reinterpret_cast<uintptr_t>(aEmitter), &receiver))
    {
        return;
    }
    Car car{};
    uintptr_t movement = 0;
    const bool known = CarByEntity(state.entityId, &car, &movement);
    char head[160];
    std::snprintf(head, sizeof(head), "traffic post %s ent=%llx dist=%.1f station=%s ", Stamp().c_str(),
                  static_cast<unsigned long long>(state.entityId), known ? DistanceTo(&car) : -1.0f,
                  Text(aStation).c_str());
    Log(head + ReceiverText(receiver) + ids);
}

// --- every listener on every station ---
// Each 100 ms: every listener of every station, with its kind, whether it counts (vtable +0x100), where it
// is (its position entry, emitter +0xb8, position at +0x10) and the state of the broadcast sound it posts
// (name at +0x120, found in its sounds as for IsRadioPlaying). A listener is logged whenever its station,
// whether it counts, whether its station plays or its sound's state changes, and when it leaves. The same
// sweep is written to the RadioProbeOverlay CET mod's folder for its in-game markers, one line per listener:
//   kind x y z counts playing station
constexpr size_t kEmitterPositionEntry = 0xb8;
constexpr size_t kPositionEntryPos = 0x10;
constexpr uint32_t kMaxListeners = 512;

struct ListenerSnap
{
    uintptr_t emitter;
    uint64_t name;
    uint64_t station;
    uint8_t kind;
    bool counts;
    bool playing;      // the station is active and holds a voice
    bool hasPos;
    float pos[3];
    uint64_t sound;    // the broadcast event
    uint32_t soundId;
    uint8_t soundState;
    bool soundFound;
};
ListenerSnap g_listeners[kMaxListeners];
// The slot list as the same sweep saw it: the stations holding a slot, and the mode bytes that set the limit
// (CalculateRadioDistanceToPlayer_NoLock 0x9da83c: +0x27c 0 -> 3; 1 -> +0x27d ? 3 : 4; otherwise 1).
uint64_t g_slotNames[4];
uint32_t g_slotCount = 0;
uint8_t g_mode27c = 0;
uint8_t g_mode27d = 0;
uint64_t g_lastDemand = 0;
std::unordered_map<uintptr_t, std::string> g_lastListener;
bool g_listenerFailed = false;
std::wstring g_livePath;

uint32_t ReadListeners()
{
    const auto rootSlot = ResolveByHash(kHashEngineRoot);
    const auto root = rootSlot ? Read<uintptr_t>(rootSlot) : 0;
    const auto audio = root ? Read<uintptr_t>(root + kRootAudioSystem) : 0;
    const auto manager = audio ? Read<uintptr_t>(audio + kAudioRadioManager) : 0;
    if (!manager)
    {
        return 0;
    }
    const auto stations = Read<uintptr_t>(manager + kManagerStations);
    const auto count = Read<uint32_t>(manager + kManagerCount);
    g_slotCount = Read<uint32_t>(manager + kManagerList + kManagerListCount);
    for (uint32_t k = 0; k < 4; ++k)
    {
        g_slotNames[k] = k < g_slotCount ? Read<uint64_t>(manager + kManagerList + k * kManagerListStride) : 0;
    }
    g_mode27c = Read<uint8_t>(manager + 0x27c);
    g_mode27d = Read<uint8_t>(manager + 0x27d);
    uint32_t n = 0;
    for (uint32_t i = 0; stations && i < count && i < kMaxStations; ++i)
    {
        const auto station = Read<uintptr_t>(stations + i * 8);
        if (!station)
        {
            continue;
        }
        uint64_t stationName = 0;
        Read<GetNameFn>(Read<uintptr_t>(station) + kVtblGetName)(reinterpret_cast<void*>(station), &stationName);
        const bool playing = Read<uint8_t>(station + kStationActive) != 0 && Read<uint32_t>(station + kStationHandleCount) != 0;
        const auto listeners = Read<uintptr_t>(station + kStationListeners);
        const auto listenerCount = Read<uint32_t>(station + kStationListenerCount);
        for (uint32_t l = 0; listeners && l < listenerCount && l < 64 && n < kMaxListeners; ++l)
        {
            const auto e = Read<uintptr_t>(listeners + l * 8);
            if (!e)
            {
                continue;
            }
            ListenerSnap& s = g_listeners[n++];
            s.emitter = e;
            s.station = stationName;
            s.playing = playing;
            s.kind = Read<uint8_t>(e + kListenerKind);
            const auto vtbl = Read<uintptr_t>(e);
            uint64_t name = 0;
            Read<GetNameFn>(vtbl + kVtblGetName)(reinterpret_cast<void*>(e), &name);
            s.name = name;
            s.counts = Read<ListenerActiveFn>(vtbl + kVtblListenerActive)(reinterpret_cast<void*>(e));
            const auto entry = Read<uintptr_t>(e + kEmitterPositionEntry);
            s.hasPos = entry != 0;
            for (int k = 0; k < 3; ++k)
            {
                s.pos[k] = entry ? Read<float>(entry + kPositionEntryPos + k * 4) : 0.0f;
            }
            s.sound = Read<uint64_t>(e + kEmitterBroadcastEvent);
            s.soundFound = false;
            s.soundId = 0;
            s.soundState = 0xff;
            const auto sounds = Read<uintptr_t>(e + kEmitterSounds);
            const auto soundCount = Read<uint32_t>(e + kEmitterSoundCount);
            for (uint32_t k = 0; sounds && k < soundCount && k < 64; ++k)
            {
                const auto element = Read<uintptr_t>(sounds + k * 8);
                const auto sound = element ? Read<uintptr_t>(element) : 0;
                if (sound && Read<uint64_t>(sound + kSoundName) == s.sound)
                {
                    s.soundFound = true;
                    s.soundId = Read<uint32_t>(sound + kSoundPlayingId);
                    s.soundState = Read<uint8_t>(sound + kSoundState);
                    break;
                }
            }
        }
    }
    return n;
}

bool SafeReadListeners(uint32_t* aCount)
{
    __try
    {
        *aCount = ReadListeners();
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void SweepListeners()
{
    if (g_listenerFailed)
    {
        return;
    }
    uint32_t n = 0;
    if (!SafeReadListeners(&n))
    {
        g_listenerFailed = true;
        Log("listeners: a read faulted - listener logging stopped");
        return;
    }
    if (g_livePath.empty())
    {
        wchar_t exe[MAX_PATH];
        GetModuleFileNameW(nullptr, exe, MAX_PATH);
        std::wstring dir(exe);
        dir = dir.substr(0, dir.find_last_of(L"\\/"));
        g_livePath = dir + L"\\plugins\\cyber_engine_tweaks\\mods\\RadioProbeOverlay\\radio_live.txt";
    }
    std::string live;
    std::unordered_map<uintptr_t, bool> seen;
    for (uint32_t i = 0; i < n; ++i)
    {
        const ListenerSnap& s = g_listeners[i];
        seen[s.emitter] = true;
        char line[96];
        std::snprintf(line, sizeof(line), "%u %.1f %.1f %.1f %d %d %s\n", s.kind, s.pos[0], s.pos[1], s.pos[2],
                      s.counts ? 1 : 0, s.playing ? 1 : 0, Text(s.station).c_str());
        if (s.hasPos)
        {
            live += line;
        }
        char key[160];
        std::snprintf(key, sizeof(key), "%llx|%d|%d|%d|%u", static_cast<unsigned long long>(s.station), s.counts,
                      s.playing, s.soundId != 0, s.soundState);
        auto& last = g_lastListener[s.emitter];
        if (last == key)
        {
            continue;
        }
        last = key;
        char buf[320];
        std::snprintf(buf, sizeof(buf),
                      "listener %s k%u %s station=%s counts=%s playing=%s sound=%s:%s:%u/%u pos=%.1f,%.1f,%.1f dist=%.1f",
                      Stamp().c_str(), s.kind, Text(s.name).c_str(), Text(s.station).c_str(), s.counts ? "on" : "off",
                      s.playing ? "yes" : "no", Text(s.sound).c_str(), s.soundFound ? "found" : "missing", s.soundId,
                      s.soundState, s.pos[0], s.pos[1], s.pos[2], s.hasPos ? DistanceFromListener(s.pos) : -1.0f);
        Log(buf);
    }
    for (auto it = g_lastListener.begin(); it != g_lastListener.end();)
    {
        if (!seen.count(it->first))
        {
            char buf[96];
            std::snprintf(buf, sizeof(buf), "listener %s gone emitter=%llx", Stamp().c_str(),
                          static_cast<unsigned long long>(it->first));
            Log(buf);
            it = g_lastListener.erase(it);
        }
        else
        {
            ++it;
        }
    }
    // Once a second: every station something wants playing, against the slots. A station is wanted when it
    // has a counting listener; `traffic-only` marks one whose every listener is a traffic car, which mode 1
    // holds silent whatever the slots. `over` is wanted minus the limit, counting only what the limit decides.
    const uint64_t nowTick = GetTickCount64();
    if (nowTick - g_lastDemand >= 1000)
    {
        g_lastDemand = nowTick;
        std::unordered_map<uint64_t, bool> wanted;     // station -> has a non-traffic listener
        for (uint32_t i = 0; i < n; ++i)
        {
            const ListenerSnap& s = g_listeners[i];
            if (s.counts)
            {
                wanted.try_emplace(s.station, false);
            }
        }
        for (uint32_t i = 0; i < n; ++i)
        {
            const ListenerSnap& s = g_listeners[i];
            if (s.kind != 2 && wanted.count(s.station))
            {
                wanted[s.station] = true;
            }
        }
        const uint32_t limit = g_mode27c == 0 ? 3 : (g_mode27c == 1 ? (g_mode27d ? 3 : 4) : 1);
        uint32_t eligible = 0;
        std::string list;
        for (const auto& [station, nonTraffic] : wanted)
        {
            const bool counted = nonTraffic || g_mode27c == 0;
            eligible += counted ? 1 : 0;
            list += " " + Text(station) + (counted ? "" : "(traffic-only)");
        }
        if (!wanted.empty())
        {
            std::string slots;
            for (uint32_t k = 0; k < g_slotCount && k < 4; ++k)
            {
                slots += " " + Text(g_slotNames[k]);
            }
            char head[160];
            std::snprintf(head, sizeof(head), "demand %s wanted=%zu eligible=%u limit=%u held=%u over=%d |",
                          Stamp().c_str(), wanted.size(), eligible, limit, g_slotCount,
                          static_cast<int>(eligible) - static_cast<int>(limit));
            Log(head + list + " | slots:" + slots);
        }
    }
    const std::wstring temp = g_livePath + L".tmp";
    if (FILE* f = _wfopen(temp.c_str(), L"wb"))
    {
        std::fwrite(live.data(), 1, live.size(), f);
        std::fclose(f);
        MoveFileExW(temp.c_str(), g_livePath.c_str(), MOVEFILE_REPLACE_EXISTING);
    }
}

// --- the vehicle interior parameters ---
// Each 100 ms: the game parameters vanilla uses for being in a car, read global (scope 1) and on the player's
// listener (scope 2), each as value/scope-it-came-from. A `vehicle params` line is logged on any change, and the
// values are written to params_live.txt beside radio_live.txt for the overlay.
struct WatchedParam
{
    const char* name;
    uint32_t id;
};
constexpr WatchedParam kWatchedParams[] = {
    {"veh_interior", 290459857},
    {"veh_player_mounted", 2820449795},
    {"amb_interior", 1470762554},
};

bool SafeReadParam(uint32_t aId, uint64_t aGameObject, int aScope, float* aValue, int* aType)
{
    __try
    {
        *aType = aScope;
        *aValue = -1.0f;
        Ak().rtpc(aId, aGameObject, 0, aValue, aType);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void WatchVehicleParams()
{
    static std::string last;
    if (!Ak().ok || g_livePath.empty())
    {
        return;
    }
    const auto lock = WwiseLock();
    if (!lock || !TryEnterCriticalSection(lock))
    {
        return;
    }
    std::string line, live;
    char part[96];
    for (const auto& param : kWatchedParams)
    {
        float global = -1.0f, onListener = -1.0f;
        int globalType = 0, listenerType = 0;
        SafeReadParam(param.id, ~0ull, 1, &global, &globalType);
        if (g_listenerGo)
        {
            SafeReadParam(param.id, g_listenerGo, 2, &onListener, &listenerType);
        }
        std::snprintf(part, sizeof(part), " %s=%.2f/t%d listener=%.2f/t%d", param.name, global, globalType,
                      onListener, listenerType);
        line += part;
        std::snprintf(part, sizeof(part), "%s %.2f %d %.2f %d\n", param.name, global, globalType, onListener,
                      listenerType);
        live += part;
    }
    LeaveCriticalSection(lock);
    if (line != last)
    {
        last = line;
        Log("vehicle params " + Stamp() + line);
    }
    const std::wstring path = g_livePath.substr(0, g_livePath.find_last_of(L'\\') + 1) + L"params_live.txt";
    const std::wstring temp = path + L".tmp";
    if (FILE* f = _wfopen(temp.c_str(), L"wb"))
    {
        std::fwrite(live.data(), 1, live.size(), f);
        std::fclose(f);
        MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
    }
}

// --- bus meters for the in-game overlay ---
// AK::SoundEngine::RegisterBusMeteringCallback (0x1acb900). A bus with no effect never calls back for 3D
// voices, so each meter sits on the nearest ancestor that has one:
//   Music_Diagetic_RTPC  (1151059771): NPC car radios, world radios, shops, clubs, arcades - not the player's car
//   Music_Systemic       (2321364702): combat, police and open-world music; combat and police duck NPC car radios
//   Music_Radio_Car_Player_DVR (4067771226): the player's own radio - car inside and outside, pocket radio, metro
// Wwise keeps one callback per bus. The engine's own MixBusMeters (0x93f03d) sit on Music_Systemic_Combat,
// _Police, Music_Diagetic_Radios_Vehicle_NPC and VO_Important_Somi_Holo, so these three replace none of them.
// Callback info: AkMetering at +0x10 (peak vector at +0, RMS at +0x10, linear per channel), channel count in
// the low byte of +0x18.
using RegisterMeterFn = int (*)(uint32_t aBus, void (*aCallback)(void*), uint32_t aFlags, void* aCookie);
constexpr uint32_t kMeterPeakAndRms = 1 | 4;

struct BusMeter
{
    const char* name;
    uint32_t bus;
    std::atomic<float> peak{0.0f};
    std::atomic<float> rms{0.0f};
    std::atomic<float> peakHold{0.0f};
    std::atomic<float> rmsL{0.0f};    // channels 0 and 1: front left and front right in Wwise order
    std::atomic<float> rmsR{0.0f};
    std::atomic<float> peakL{0.0f};
    std::atomic<float> peakR{0.0f};
    std::atomic<uint32_t> calls{0};
};
BusMeter g_diegetic{"diegetic", 1151059771};
BusMeter g_systemic{"systemic", 2321364702};
BusMeter g_player{"player", 4067771226};

void ReadBusMeter(void* aInfo, BusMeter& aOut)
{
    const auto info = reinterpret_cast<uintptr_t>(aInfo);
    const auto metering = *reinterpret_cast<uintptr_t*>(info + 0x10);
    const auto channels = *reinterpret_cast<uint8_t*>(info + 0x18);
    aOut.calls.fetch_add(1);
    if (!metering || !channels)
    {
        return;
    }
    const auto* peak = *reinterpret_cast<float**>(metering);
    const auto* rms = *reinterpret_cast<float**>(metering + 0x10);
    float p = 0.0f, r = 0.0f;
    for (uint8_t i = 0; i < channels; ++i)
    {
        p = (std::max)(p, peak ? peak[i] : 0.0f);
        r = (std::max)(r, rms ? rms[i] : 0.0f);
    }
    aOut.peak.store(p);
    aOut.rms.store(r);
    aOut.rmsL.store(rms ? rms[0] : 0.0f);
    aOut.peakL.store(peak ? peak[0] : 0.0f);
    aOut.rmsR.store(channels > 1 && rms ? rms[1] : 0.0f);
    aOut.peakR.store(channels > 1 && peak ? peak[1] : 0.0f);
    if (p > aOut.peakHold.load())
    {
        aOut.peakHold.store(p);
    }
}

void DiegeticMeterCallback(void* aInfo)
{
    ReadBusMeter(aInfo, g_diegetic);
}

void SystemicMeterCallback(void* aInfo)
{
    ReadBusMeter(aInfo, g_systemic);
}

void PlayerMeterCallback(void* aInfo)
{
    ReadBusMeter(aInfo, g_player);
}

float ToDb(float aLinear)
{
    return aLinear <= 0.000001f ? -120.0f : 20.0f * std::log10(aLinear);
}

// Each 100 ms: meter_live.txt beside radio_live.txt, one line per bus:
//   name rms_db peak_db peak_hold_db calls rms_left_db rms_right_db peak_left_db peak_right_db
// Once a second a `bus meter` log line, while any of them is calling back.
void WriteMeters()
{
    static bool registered = false;
    static bool failed = false;
    static uint64_t lastLog = 0;
    if (failed || g_livePath.empty())
    {
        return;
    }
    if (!registered)
    {
        registered = true;
        const auto reg = ResolveRva<RegisterMeterFn>(0x1acb900, {0x48, 0x83, 0xEC, 0x38, 0x80, 0x3D, 0x49, 0x3E});
        if (!reg)
        {
            failed = true;
            Log("bus meter: RegisterBusMeteringCallback is not this build's - no meters");
            return;
        }
        Log("bus meter: diegetic " + std::to_string(reg(g_diegetic.bus, &DiegeticMeterCallback, kMeterPeakAndRms,
                                                         nullptr)) +
            ", systemic " + std::to_string(reg(g_systemic.bus, &SystemicMeterCallback, kMeterPeakAndRms, nullptr)) +
            ", player " + std::to_string(reg(g_player.bus, &PlayerMeterCallback, kMeterPeakAndRms, nullptr)) +
            " (1 = registered)");
    }
    std::string text;
    char line[160];
    for (BusMeter* m : {&g_diegetic, &g_systemic, &g_player})
    {
        std::snprintf(line, sizeof(line), "%s %.1f %.1f %.1f %u %.1f %.1f %.1f %.1f\n", m->name, ToDb(m->rms.load()),
                      ToDb(m->peak.load()), ToDb(m->peakHold.load()), m->calls.load(), ToDb(m->rmsL.load()),
                      ToDb(m->rmsR.load()), ToDb(m->peakL.load()), ToDb(m->peakR.load()));
        text += line;
    }
    std::wstring path = g_livePath.substr(0, g_livePath.find_last_of(L"\\/")) + L"\\meter_live.txt";
    const std::wstring temp = path + L".tmp";
    if (FILE* f = _wfopen(temp.c_str(), L"wb"))
    {
        std::fwrite(text.data(), 1, text.size(), f);
        std::fclose(f);
        MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
    }
    const uint64_t now = GetTickCount64();
    if (now - lastLog < 1000)
    {
        return;
    }
    lastLog = now;
    const uint32_t dc = g_diegetic.calls.exchange(0);
    const uint32_t sc = g_systemic.calls.exchange(0);
    const uint32_t pc = g_player.calls.exchange(0);
    if (!dc && !sc && !pc)
    {
        return;
    }
    char wide[320];
    std::snprintf(wide, sizeof(wide),
                  "bus meter %s diegetic rms=%.1f L=%.1f R=%.1f max=%.1f calls=%u  systemic rms=%.1f L=%.1f R=%.1f "
                  "max=%.1f calls=%u  player rms=%.1f L=%.1f R=%.1f max=%.1f calls=%u",
                  Stamp().c_str(), ToDb(g_diegetic.rms.load()), ToDb(g_diegetic.rmsL.load()),
                  ToDb(g_diegetic.rmsR.load()), ToDb(g_diegetic.peakHold.exchange(0.0f)), dc,
                  ToDb(g_systemic.rms.load()), ToDb(g_systemic.rmsL.load()), ToDb(g_systemic.rmsR.load()),
                  ToDb(g_systemic.peakHold.exchange(0.0f)), sc, ToDb(g_player.rms.load()), ToDb(g_player.rmsL.load()),
                  ToDb(g_player.rmsR.load()), ToDb(g_player.peakHold.exchange(0.0f)), pc);
    Log(wide);
}

template <typename Fn>
void Attach(const HookTarget& aTarget, Fn aDetour, Fn* aOriginal)
{
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto address = ResolveByHash(aTarget.hash);
    char buf[192];
    if (!address || address - base != aTarget.rva)
    {
        std::snprintf(buf, sizeof(buf), "traffic: %s did not resolve to 2.31's 0x%llx - not hooked", aTarget.name,
                      static_cast<unsigned long long>(aTarget.rva));
        Log(buf);
        return;
    }
    if (std::memcmp(reinterpret_cast<void*>(address), aTarget.prologue, sizeof(aTarget.prologue)) != 0)
    {
        std::snprintf(buf, sizeof(buf), "traffic: %s does not start with 2.31's bytes (another hook?) - not hooked",
                      aTarget.name);
        Log(buf);
        return;
    }
    if (!g_sdk->hooking->Attach(g_handle, reinterpret_cast<void*>(address), reinterpret_cast<void*>(aDetour),
                                reinterpret_cast<void**>(aOriginal)))
    {
        Log(std::string("traffic: attach failed for ") + aTarget.name);
        return;
    }
    Log(std::string("traffic: hooked ") + aTarget.name);
}

// --- broadcast channel users ---
// Every broadcast channel the game sets goes through audio::SetSoundParameter (0x33afc8, entity id, parameter,
// value, emitter name, ramp) as one of five parameters: the three a radio station and its receivers set, the TV
// channel and the reflection channel. Each emitter's current value per parameter is kept, a change is logged as
// `channel set` with the function that set it (`from=` an RVA), and channels_live.txt beside meter_live.txt lists
// every emitter on each value, so a channel two sources share shows as one line with two users. A channel fixed
// inside a bank never passes through here.
constexpr HookTarget kSetSoundParameter{"audio::SetSoundParameter", 1874005891, 0x33afc8,
                                        {0x48, 0x83, 0xec, 0x38, 0x48, 0x8b, 0x05, 0x4d}};

struct ChannelParam
{
    uint64_t hash;
    const char* name;
};
constexpr ChannelParam kChannelParams[] = {
    {0xe96bc1db34134bcc, "mono"},
    {0xbd4665c7c72920f1, "right"},
    {0xe88df021660bc324, "left"},
    {0xe79edd506174a8cf, "tv"},
    {0xa22c80d6ba1a71bc, "reflection"},
};

struct ChannelUser
{
    uint64_t entity;
    uint64_t emitter;
    int param;      // index into kChannelParams
    int value;
    uintptr_t from; // RVA of the caller
};

using SetSoundParameterFn = void (*)(uint64_t, RED4ext::CName, float, RED4ext::CName, float);
SetSoundParameterFn g_origSetSoundParameter = nullptr;
SRWLOCK g_channelLock = SRWLOCK_INIT;
std::unordered_map<uint64_t, ChannelUser> g_channelUsers;  // key: entity ^ emitter ^ param, folded
std::atomic<bool> g_channelsDirty{false};

void DetourSetSoundParameter(uint64_t aEntity, RED4ext::CName aParam, float aValue, RED4ext::CName aEmitter,
                             float aRamp)
{
    const uintptr_t from = reinterpret_cast<uintptr_t>(_ReturnAddress()) -
                           reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    g_origSetSoundParameter(aEntity, aParam, aValue, aEmitter, aRamp);

    int param = -1;
    for (int i = 0; i < static_cast<int>(std::size(kChannelParams)); ++i)
    {
        if (kChannelParams[i].hash == aParam.hash)
        {
            param = i;
        }
    }
    if (param < 0)
    {
        return;
    }
    const int value = static_cast<int>(std::lround(aValue));
    const uint64_t key = (aEntity * 0x9E3779B97F4A7C15ull) ^ (aEmitter.hash * 31) ^ static_cast<uint64_t>(param);
    bool changed = false;
    AcquireSRWLockExclusive(&g_channelLock);
    auto it = g_channelUsers.find(key);
    if (it == g_channelUsers.end() || it->second.value != value)
    {
        g_channelUsers[key] = ChannelUser{aEntity, aEmitter.hash, param, value, from};
        changed = true;
    }
    ReleaseSRWLockExclusive(&g_channelLock);
    if (changed)
    {
        g_channelsDirty = true;
        char buf[224];
        std::snprintf(buf, sizeof(buf), "channel set %s %s=%d ent=%llx emitter=%s from=0x%llx", Stamp().c_str(),
                      kChannelParams[param].name, value, static_cast<unsigned long long>(aEntity),
                      Text(aEmitter.hash).c_str(), static_cast<unsigned long long>(from));
        Log(buf);
    }
}

// channels_live.txt: one line per channel value in use, `<value> <param>:<entity>:<emitter>:<from> ...`.
// The radio parameters and the TV parameter are different numbers on the same channel space only where a bank's
// curve maps them so; the file lists the raw value each was given.
void WriteChannels()
{
    if (!g_channelsDirty.exchange(false) || g_livePath.empty())
    {
        return;
    }
    std::map<int, std::string> byValue;
    AcquireSRWLockShared(&g_channelLock);
    for (const auto& [key, u] : g_channelUsers)
    {
        char item[160];
        std::snprintf(item, sizeof(item), " %s:%llx:%s:0x%llx", kChannelParams[u.param].name,
                      static_cast<unsigned long long>(u.entity), Text(u.emitter).c_str(),
                      static_cast<unsigned long long>(u.from));
        byValue[u.value] += item;
    }
    ReleaseSRWLockShared(&g_channelLock);
    std::string text;
    for (const auto& [value, users] : byValue)
    {
        text += std::to_string(value) + users + "\n";
    }
    std::wstring path = g_livePath.substr(0, g_livePath.find_last_of(L"\\/")) + L"\\channels_live.txt";
    const std::wstring temp = path + L".tmp";
    if (FILE* f = _wfopen(temp.c_str(), L"wb"))
    {
        std::fwrite(text.data(), 1, text.size(), f);
        std::fclose(f);
        MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
    }
}

void InstallTrafficHooks()
{
    g_startTick = GetTickCount64();
    Attach(kSetSoundParameter, &DetourSetSoundParameter, &g_origSetSoundParameter);
    Attach(kInitializeAudio, &DetourInitializeAudio, &g_origInitializeAudio);
    Attach(kUpdateAudio, &DetourUpdateAudio, &g_origUpdateAudio);
    Attach(kPerformAudioAction, &DetourPerformAudioAction, &g_origPerformAudioAction);
    Attach(kGetRandomStation, &DetourGetRandomStation, &g_origGetRandomStation);
    Attach(kPlayRadio, &DetourPlayRadio, &g_origPlayRadio);
    Attach(kStopRadio, &DetourStopRadio, &g_origStopRadio);
    Attach(kPostBroadcast, &DetourPostBroadcast, &g_origPostBroadcast);
    Attach(kRadioEmitterDtor, &DetourEmitterDtor, &g_origEmitterDtor);
    Attach(kAmbientPlay, &DetourAmbientPlay, &g_origAmbientPlay);
    Attach(kAmbientStop, &DetourAmbientStop, &g_origAmbientStop);
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        g_sdk = aSdk;
        g_handle = aHandle;
        RED4ext::CRTTISystem::Get()->AddPostRegisterCallback(&LogNativeHandlers);
        InstallTrafficHooks();
        static RED4ext::v1::GameState state{
            .OnEnter = nullptr,
            .OnUpdate = OnUpdate,
            .OnExit = nullptr,
        };
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &state);
        Log("radio station probe loaded - one line per station whenever its listeners or flags change");
    }
    return true;
}
