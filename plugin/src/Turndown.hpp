// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The game's turn-downs of the player radio that sit before RadioXL's leveller, found from the banks
//              that loaded.
// File Version: 0.11.0
// ======================================================================================
//
// Every curve a bank carries passes through the curve loader (Broadcast.hpp), which hands over the owner's id.
// A volume curve (parameter 0, or 4 for a bus's own bus volume) is kept with its points. Once the session is up,
// each kept owner is looked up in the Wwise index and followed upward: a node through its parent (+0x70) and its
// output bus (+0x78), a bus through its parent bus (+0x78). A curve whose owner reaches
// Music_Diagetic_Radios_Vehicle_Player_DVR, or is that bus, acts before the leveller in its slot 3. The bus's own
// bus volume acts after its effects and is not one of them.

#pragma once

#include "Broadcast.hpp"
#include "Eq.hpp"
#include "Mix.hpp"

#include <atomic>
#include <cstdint>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <tuple>
#include <vector>

namespace radioxl::turndown
{

constexpr uint32_t kLevellerBus = eq::kVehicleBus;
constexpr uint32_t kThresholdRtpc = 3375154464;  // the leveller's threshold game parameter
constexpr uint32_t kParamVolume = 0;
constexpr uint32_t kParamBusVolume = 4;
constexpr uint32_t kTypeObject = 0;   // the loader's second argument for a node or a bus
constexpr uint32_t kTypeShareSet = 3;  // and for an effect ShareSet
constexpr size_t kParent = 0x70;      // a node's parent node
constexpr size_t kOutput = 0x78;      // a node's output bus; a bus's parent bus
constexpr size_t kId = 0x20;          // an object's id, where mix::Find matches it
constexpr int kMaxDepth = 32;
constexpr uint32_t kMaxPoints = 64;
constexpr uint64_t kWalkEveryMs = 3000;

// AK::SoundEngine::Query::GetRTPCValue(parameter, gameObject, playingId, value, type): type in is the scope asked
// for (0 global, 1 game object, 2 playing id), out the scope that answered.
constexpr uint32_t kHashGetRtpc = 3938393104;
constexpr uint8_t kGetRtpcPrologue[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x6C};
using GetRtpcFn = int (*)(uint32_t, uint64_t, uint32_t, float*, int*);

struct Kept
{
    uint32_t type;
    uint64_t owner;
    broadcast::CurveDesc desc;
    std::vector<broadcast::GraphPoint> points;
};

inline std::function<void(const std::string&)> g_log;
inline GetRtpcFn g_getRtpc = nullptr;
inline std::mutex g_mutex;
inline std::map<std::tuple<uint64_t, uint32_t, uint32_t, uint32_t>, Kept> g_kept;
inline uint32_t g_generation = 0;
inline uintptr_t g_levellerContainer = 0;
inline uint32_t g_walked = ~0u;
inline uint64_t g_lastWalk = 0;
inline std::set<std::string> g_reported;
inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("turndown: " + aText);
    }
}

// From the curve loader hook, for every curve of every bank.
inline void Collect(void* aContainer, uint32_t aType, uint64_t aOwner, const broadcast::CurveDesc* aDesc,
                    const broadcast::GraphPoint* aPoints)
{
    if (!aDesc || !aPoints || aDesc->count == 0 || aDesc->count > kMaxPoints)
    {
        return;
    }
    std::lock_guard<std::mutex> guard(g_mutex);
    if (aType == kTypeShareSet && aDesc->rtpc == kThresholdRtpc)
    {
        g_levellerContainer = reinterpret_cast<uintptr_t>(aContainer);
        return;
    }
    if (aType != kTypeObject || (aDesc->param != kParamVolume && aDesc->param != kParamBusVolume))
    {
        return;
    }
    Kept& k = g_kept[{aOwner, aDesc->rtpc, aDesc->param, aDesc->curve}];
    k.type = aType;
    k.owner = aOwner;
    k.desc = *aDesc;
    k.points.assign(aPoints, aPoints + aDesc->count);
    ++g_generation;
}

inline uint32_t IdOf(uintptr_t aObject)
{
    return aObject ? mix::Read<uint32_t>(aObject + kId) : 0;
}

// The buses from aBus up to the leveller bus, or empty when it never gets there.
inline std::vector<uint32_t> BusChain(uintptr_t aBus, uintptr_t aLeveller)
{
    std::vector<uint32_t> chain;
    for (int d = 0; aBus && d < kMaxDepth; ++d, aBus = mix::Read<uintptr_t>(aBus + kOutput))
    {
        chain.push_back(IdOf(aBus));
        if (aBus == aLeveller)
        {
            return chain;
        }
    }
    return {};
}

inline std::string Ids(const std::vector<uint32_t>& aIds)
{
    std::string s;
    for (size_t i = 0; i < aIds.size(); ++i)
    {
        s += (i ? ">" : "") + std::to_string(aIds[i]);
    }
    return s;
}

inline std::string PointsText(const Kept& aKept)
{
    std::string s;
    char buf[64];
    for (const auto& p : aKept.points)
    {
        std::snprintf(buf, sizeof(buf), " (%g,%g,%u)", p.from, p.to, p.interp);
        s += buf;
    }
    return s;
}

inline std::string GlobalValue(uint32_t aRtpc)
{
    if (!g_getRtpc)
    {
        return "?";
    }
    float v = 0.0f;
    int scope = 0;
    const int result = g_getRtpc(aRtpc, ~0ull, 0, &v, &scope);
    char buf[48];
    std::snprintf(buf, sizeof(buf), result == 1 ? "%g" : "unset", v);
    return buf;
}

// Under Wwise's lock: which kept curves act before the leveller, each logged once.
inline void Walk()
{
    const uintptr_t leveller = mix::Find(mix::kBuses, kLevellerBus);
    if (!leveller)
    {
        return;
    }
    std::vector<Kept> kept;
    {
        std::lock_guard<std::mutex> guard(g_mutex);
        g_walked = g_generation;
        kept.reserve(g_kept.size());
        for (const auto& [key, k] : g_kept)
        {
            kept.push_back(k);
        }
    }
    size_t found = 0;
    for (const Kept& k : kept)
    {
        const uint32_t owner = static_cast<uint32_t>(k.owner);
        std::string where;
        if (const uintptr_t bus = mix::Find(mix::kBuses, owner))
        {
            const std::vector<uint32_t> chain = BusChain(bus, leveller);
            if (chain.empty())
            {
                continue;
            }
            where = "bus " + Ids(chain);
            if (bus == leveller && k.desc.param == kParamBusVolume)
            {
                where += " (its bus volume, after the leveller)";
            }
        }
        else if (const uintptr_t node = mix::Find(mix::kNodes, owner))
        {
            // The node and its parents, each with the buses its output reaches.
            std::vector<uint32_t> nodes;
            std::string outs;
            bool reaches = false;
            uintptr_t n = node;
            for (int d = 0; n && d < kMaxDepth; ++d, n = mix::Read<uintptr_t>(n + kParent))
            {
                nodes.push_back(IdOf(n));
                const uintptr_t out = mix::Read<uintptr_t>(n + kOutput);
                const std::vector<uint32_t> chain = BusChain(out, leveller);
                if (!chain.empty())
                {
                    reaches = true;
                    outs += " " + std::to_string(IdOf(n)) + "->" + Ids(chain);
                }
                else if (out)
                {
                    outs += " " + std::to_string(IdOf(n)) + "->" + std::to_string(IdOf(out)) + "(elsewhere)";
                }
            }
            if (!reaches)
            {
                continue;
            }
            where = "node " + Ids(nodes) + " outputs" + outs;
        }
        else
        {
            continue;
        }
        ++found;
        char head[160];
        std::snprintf(head, sizeof(head), "rtpc %u param %u curve %u scaling %u accum %u kind %u now %s on ",
                      k.desc.rtpc, k.desc.param, k.desc.curve, k.desc.scaling, k.desc.accum, k.desc.type,
                      GlobalValue(k.desc.rtpc).c_str());
        const std::string line = head + where + " points" + PointsText(k);
        if (g_reported.insert(line).second)
        {
            Log(line);
        }
    }
    Log(std::to_string(found) + " of " + std::to_string(kept.size()) + " volume curves act before the leveller" +
        (g_levellerContainer ? "; the leveller's threshold curve is loaded" : ""));
}

// Called from the game-state update.
inline void Tick()
{
    if (!mix::g_ready || !mix::g_lock)
    {
        return;
    }
    uint32_t generation = 0;
    {
        std::lock_guard<std::mutex> guard(g_mutex);
        generation = g_generation;
    }
    const uint64_t now = GetTickCount64();
    if (generation == g_walked || now - g_lastWalk < kWalkEveryMs || !TryEnterCriticalSection(mix::g_lock))
    {
        return;
    }
    g_lastWalk = now;
    Walk();
    LeaveCriticalSection(mix::g_lock);
}

inline void Init(uintptr_t (*aResolve)(uint32_t))
{
    const auto fn = reinterpret_cast<const uint8_t*>(aResolve(kHashGetRtpc));
    if (fn && std::memcmp(fn, kGetRtpcPrologue, sizeof(kGetRtpcPrologue)) == 0)
    {
        g_getRtpc = reinterpret_cast<GetRtpcFn>(const_cast<uint8_t*>(fn));
    }
    else
    {
        Log("byte check FAILED at GetRTPCValue: " +
            (fn ? diag::Mismatch(fn, kGetRtpcPrologue, sizeof(kGetRtpcPrologue)) : std::string("did not resolve")));
    }
}

} // namespace radioxl::turndown
