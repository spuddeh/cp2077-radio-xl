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

#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map>

namespace
{
// The global holding the engine root pointer (0x342ac00 on 2.31), by RED4ext hash.
constexpr uint32_t kHashEngineRoot = 2549221846;

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
// skipped by the update, kind 2 is the only kind that keeps a station active in manager mode 1.
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

bool OnUpdate(RED4ext::CGameApplication*)
{
    if (g_failed)
    {
        return false;
    }
    const uint64_t now = GetTickCount64();
    if (!g_scheduleFailed && now - g_lastSchedule >= kScheduleMs)
    {
        g_lastSchedule = now;
        Schedule();
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
    aInfo->version = RED4EXT_V1_SEMVER(0, 1, 0);
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

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        g_sdk = aSdk;
        g_handle = aHandle;
        RED4ext::CRTTISystem::Get()->AddPostRegisterCallback(&LogNativeHandlers);
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
