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
constexpr size_t kStationType = 0x148;           // 0 station, 5 playlist
constexpr size_t kStationClock = 0x14c;          // float, accumulates while active
constexpr size_t kStationHandle = 0x158;         // the current voice's handle
constexpr size_t kStationFlagA = 0x21a;
constexpr size_t kStationActive = 0x21b;         // recomputed every frame from the listeners
constexpr size_t kStationFlagD = 0x21d;

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
bool g_failed = false;

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
                line += active(reinterpret_cast<void*>(listener)) ? ":on " : ":off ";
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

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        g_sdk = aSdk;
        g_handle = aHandle;
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
