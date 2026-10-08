// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The player radio's equaliser and processing: nine EQ bands in three Parametric EQ ShareSets, an AGC,
//              a peak compressor and a limiter, all RadioXL's own ShareSets, built as a soundbank in memory, loaded
//              once, and inserted into the buses the car, the Radioport and the metro play through. A band's gain is
//              a game parameter of RadioXL's own; each processing stage is on or off, off being an empty slot.
// File Version: 0.8.0
// ======================================================================================
//
// The car and the Radioport play through Music_Diagetic_Radios_Vehicle_Player_DVR, the metro through
// Music_Diagetic_Radios_Metro_Player_DVR; neither bus carries an effect, so all four slots are free. Slots 0 to 2
// take the three EQs, slot 3 the AGC. One ShareSet in both buses gives two instances that read the same settings.
// Both feed Music_Radio_Car_Player_DVR, whose slots 0 and 1 hold the game's dialogue EQ and meter; its slot 2 takes
// the peak compressor and slot 3 the limiter. The volume boost is the child buses' bus volume, so it reaches the
// top bus, and its limiter, whichever way Wwise orders a bus's own volume against its effects. The game's ducks
// are voice volume, applied to each voice before any bus effect, so every stage sees the radio already ducked.
//
// A ShareSet comes into being only through the bank reader (0x1afa210), so the plugin writes a bank holding them and
// loads it with AK::SoundEngine::LoadBankMemoryCopy (16-byte aligned; 1 loaded, 69 already loaded, 92 the init bank
// is not loaded yet). AK::SoundEngine::SetBusEffect(bus, slot, shareSet) puts one into a slot; a ShareSet id of 0
// empties the slot. Both are called from the game thread outside Wwise's lock: the bank load waits on the bank
// thread, and SetBusEffect queues its change for the audio thread.
//
// Each band's gain carries a curve in the bank from its own game parameter: input and output in dB, no scaling,
// exclusive, so the parameter's value IS the band's gain. A dB-scaled curve is misread on some properties, and plain
// dB is the form measured correct. AK::SoundEngine::SetRTPCValue on the global game object sets it.

#pragma once

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

namespace radioxl::eq
{

constexpr uint32_t kHashLoadBankMemoryCopy = 3400209645;  // 0x1ac7e00
constexpr uint8_t kLoadBankPrologue[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74};
using LoadBankFn = int32_t (*)(const void*, uint32_t, uint32_t*);
constexpr uint32_t kHashSetBusEffect = 3497922771;  // 0x1ace280
constexpr uint8_t kSetBusEffectPrologue[] = {0x40, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x83};
using SetBusEffectFn = int32_t (*)(uint32_t, uint32_t, uint32_t);
constexpr uint32_t kHashSetRtpc = 796138256;  // 0x1acf570
constexpr uint8_t kSetRtpcPrologue[] = {0x48, 0x83, 0xEC, 0x48, 0x0F, 0xB6, 0x44, 0x24};
using SetRtpcFn = int32_t (*)(uint32_t, float, uint64_t, int32_t, int32_t, bool);
constexpr uint64_t kGlobalObject = ~0ull;
constexpr int32_t kCurveLinear = 4;
constexpr int32_t kGainGlideMs = 100;

constexpr uint32_t kVehicleBus = 3776664628;  // Music_Diagetic_Radios_Vehicle_Player_DVR: the car and the Radioport
constexpr uint32_t kMetroBus = 2319597885;    // Music_Diagetic_Radios_Metro_Player_DVR
constexpr uint32_t kBuses[] = {kVehicleBus, kMetroBus};
constexpr uint32_t kTopBus = 4067771226;      // Music_Radio_Car_Player_DVR

// FNV-1 32 of the radioxl_ names, outside the 0xA770xxxx-0xA77Fxxxx ids Audible Traffic Radios uses.
constexpr uint32_t kBankId = 3385278659;                                  // radioxl_eq
constexpr uint32_t kShareSets[3] = {3625712483, 3625712480, 3625712481};  // radioxl_eq_1 .. _3, slots 0 to 2
constexpr size_t kBandCount = 9;
// radioxl_eq_band_1 .. _9, and each one's curve id (radioxl_eq_band_N_curve).
constexpr uint32_t kBandRtpc[kBandCount] = {2408984243, 2408984240, 2408984241, 2408984246, 2408984247,
                                           2408984244, 2408984245, 2408984250, 2408984251};
constexpr uint32_t kBandCurve[kBandCount] = {579835719,  1529091028, 2328075109, 1911558210, 1246224139,
                                            4158523976, 3690860137, 830218182,  2191738463};
constexpr float kBandHz[kBandCount] = {63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
constexpr float kBandQ = 1.41f;      // one octave
constexpr uint32_t kPeaking = 6;
constexpr float kGainLimit = 24.0f;  // the Parametric EQ clamps a gain to +-24 dB

// The processing stages. Levels are as the bus sees them, about 15 dB under a file's own level, and the limiter's
// after the boost. Measured on the car radio, each stage held on: the AGC's output gain brings it level with the
// radio unprocessed while holding it within about 0.3 dB second to second; the peak compressor's threshold sits just
// under the music's peaks, so it leaves the average alone; the limiter held boosted peaks to its threshold.
// Compressor (0x006C0003) and Peak Limiter (0x006E0003) settings are 22 bytes, as init.bnk's 3717463198 and
// 564272455 carry them: five floats then two bytes. Compressor: threshold dB, ratio, attack s, release s, output
// gain dB, process LFE, link channels. Peak Limiter: threshold dB, ratio, look-ahead s, release s, output gain dB,
// process LFE, link channels.
enum Stage : int
{
    kAgc,
    kPeakCompressor,
    kLimiter,
    kStageCount
};
// A stage's threshold (parameter 0) and output gain (parameter 4) each carry a curve from a game parameter of
// RadioXL's own, as the game's own Compressor and Peak Limiter ShareSets drive those two; the plugin sets both at
// load and whenever they change, since an unset game parameter would read 0.
struct Processor
{
    uint32_t id;
    uint32_t plugin;
    float values[5];
    uint32_t slot;
    bool onChildBuses;  // else on the top bus
    const char* name;
    uint32_t rtpc[2];   // threshold, output gain
    uint32_t curve[2];
};
constexpr uint8_t kProcessorParams[2] = {0, 4};
constexpr float kProcessorRange = 96.0f;
constexpr Processor kProcessors[kStageCount] = {
    {1503678448, 0x006C0003, {-36.0f, 2.0f, 1.0f, 3.0f, 8.5f}, 3, true, "AGC",
     {3375154464, 2103187666}, {856972996, 3553739982}},
    {801420832, 0x006C0003, {-18.0f, 3.0f, 0.01f, 0.08f, 1.5f}, 2, false, "peak compressor",
     {1222611792, 112991042}, {1941822388, 1997244222}},
    {1705528755, 0x006E0003, {-6.0f, 10.0f, 0.01f, 0.1f, 0.0f}, 3, false, "limiter",
     {1602624095, 1395259047}, {2434784355, 331337659}},
};

// The bank's header, as the game's own banks carry it (version 150).
constexpr uint32_t kBankVersion = 150;
constexpr uint32_t kLanguageId = 393239870;

inline std::function<void(const std::string&)> g_log;
inline LoadBankFn g_loadBank = nullptr;
inline SetBusEffectFn g_setBusEffect = nullptr;
inline SetRtpcFn g_setRtpc = nullptr;
inline bool g_bankLoaded = false;
inline bool g_bankFailed = false;
inline std::atomic<bool> g_wanted{true};
inline bool g_applied = false;
inline bool g_appliedValid = false;
inline std::atomic<bool> g_stageWanted[kStageCount] = {false, false, false};
inline bool g_stageApplied[kStageCount] = {};
inline bool g_stageValid[kStageCount] = {};
inline std::atomic<float> g_procValues[kStageCount][2] = {{-36.0f, 8.5f}, {-18.0f, 1.5f}, {-6.0f, 0.0f}};
inline float g_procSent[kStageCount][2] = {};
inline bool g_procSentValid = false;
inline std::atomic<float> g_gains[kBandCount] = {};
inline float g_gainsSent[kBandCount] = {};
inline std::atomic<bool> g_gainsPending{true};

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("eq: " + aText);
    }
}

template <typename T>
inline void Put(std::vector<uint8_t>& aOut, T aValue)
{
    const auto* p = reinterpret_cast<const uint8_t*>(&aValue);
    aOut.insert(aOut.end(), p, p + sizeof(T));
}

// One Parametric EQ ShareSet (0x00690003): three bands of {u32 type, f32 gain dB, f32 frequency Hz, f32 Q, u8 on},
// f32 output level, u8 process LFE (56 bytes, the layout of init.bnk's ShareSets 2706720451 and 935112557), then a
// curve on each band's gain (parameter band * 5 + 1) and a starting value for each curved parameter.
inline std::vector<uint8_t> ShareSet(size_t aEq)
{
    std::vector<uint8_t> body;
    Put<uint32_t>(body, kShareSets[aEq]);
    Put<uint32_t>(body, 0x00690003);
    Put<uint32_t>(body, 56);
    for (size_t b = 0; b < 3; ++b)
    {
        Put<uint32_t>(body, kPeaking);
        Put<float>(body, 0.0f);
        Put<float>(body, kBandHz[aEq * 3 + b]);
        Put<float>(body, kBandQ);
        Put<uint8_t>(body, 1);
    }
    Put<float>(body, 0.0f);  // output level
    Put<uint8_t>(body, 0);   // process LFE
    Put<uint8_t>(body, 0);   // bank data count
    Put<uint16_t>(body, 3);  // RTPC curves
    for (size_t b = 0; b < 3; ++b)
    {
        const size_t band = aEq * 3 + b;
        Put<uint32_t>(body, kBandRtpc[band]);
        Put<uint8_t>(body, 0);                            // a game parameter
        Put<uint8_t>(body, 1);                            // exclusive: the curve's value is the gain
        Put<uint8_t>(body, static_cast<uint8_t>(b * 5 + 1));  // the band's gain (one varint byte)
        Put<uint32_t>(body, kBandCurve[band]);
        Put<uint8_t>(body, 0);                            // no scaling: dB in, dB out
        Put<uint16_t>(body, 2);
        Put<float>(body, -kGainLimit);
        Put<float>(body, -kGainLimit);
        Put<uint32_t>(body, kCurveLinear);
        Put<float>(body, kGainLimit);
        Put<float>(body, kGainLimit);
        Put<uint32_t>(body, kCurveLinear);
    }
    Put<uint8_t>(body, 0);   // state properties
    Put<uint8_t>(body, 0);   // state groups
    Put<uint16_t>(body, 3);  // property values: each curved parameter, its accumulation and its start
    for (size_t b = 0; b < 3; ++b)
    {
        Put<uint8_t>(body, static_cast<uint8_t>(b * 5 + 1));
        Put<uint8_t>(body, 1);
        Put<float>(body, 0.0f);
    }

    std::vector<uint8_t> item;
    Put<uint8_t>(item, 16);  // FX ShareSet
    Put<uint32_t>(item, static_cast<uint32_t>(body.size()));
    item.insert(item.end(), body.begin(), body.end());
    return item;
}

inline std::vector<uint8_t> ProcessorShareSet(const Processor& aProc)
{
    std::vector<uint8_t> body;
    Put<uint32_t>(body, aProc.id);
    Put<uint32_t>(body, aProc.plugin);
    Put<uint32_t>(body, 22);
    for (const float v : aProc.values)
    {
        Put<float>(body, v);
    }
    Put<uint8_t>(body, 0);   // process LFE
    Put<uint8_t>(body, 1);   // link channels
    Put<uint8_t>(body, 0);   // bank data count
    Put<uint16_t>(body, 2);  // RTPC curves: threshold and output gain, dB in, dB out
    for (size_t k = 0; k < 2; ++k)
    {
        Put<uint32_t>(body, aProc.rtpc[k]);
        Put<uint8_t>(body, 0);
        Put<uint8_t>(body, 1);
        Put<uint8_t>(body, kProcessorParams[k]);
        Put<uint32_t>(body, aProc.curve[k]);
        Put<uint8_t>(body, 0);
        Put<uint16_t>(body, 2);
        Put<float>(body, -kProcessorRange);
        Put<float>(body, -kProcessorRange);
        Put<uint32_t>(body, kCurveLinear);
        Put<float>(body, kProcessorRange);
        Put<float>(body, kProcessorRange);
        Put<uint32_t>(body, kCurveLinear);
    }
    Put<uint8_t>(body, 0);   // state properties
    Put<uint8_t>(body, 0);   // state groups
    Put<uint16_t>(body, 2);  // property values
    for (size_t k = 0; k < 2; ++k)
    {
        Put<uint8_t>(body, kProcessorParams[k]);
        Put<uint8_t>(body, 1);
        Put<float>(body, aProc.values[k == 0 ? 0 : 4]);
    }

    std::vector<uint8_t> item;
    Put<uint8_t>(item, 16);  // FX ShareSet
    Put<uint32_t>(item, static_cast<uint32_t>(body.size()));
    item.insert(item.end(), body.begin(), body.end());
    return item;
}

inline std::vector<uint8_t> BuildBank()
{
    std::vector<uint8_t> hirc;
    Put<uint32_t>(hirc, 3 + kStageCount);
    for (size_t eq = 0; eq < 3; ++eq)
    {
        const std::vector<uint8_t> item = ShareSet(eq);
        hirc.insert(hirc.end(), item.begin(), item.end());
    }
    for (const Processor& proc : kProcessors)
    {
        const std::vector<uint8_t> item = ProcessorShareSet(proc);
        hirc.insert(hirc.end(), item.begin(), item.end());
    }

    std::vector<uint8_t> bkhd;
    for (const uint32_t v : {kBankVersion, kBankId, kLanguageId, 16u, 476u, 0u, kBankId, 1u, 0u, 0u})
    {
        Put<uint32_t>(bkhd, v);
    }

    std::vector<uint8_t> bank;
    bank.insert(bank.end(), {'B', 'K', 'H', 'D'});
    Put<uint32_t>(bank, static_cast<uint32_t>(bkhd.size()));
    bank.insert(bank.end(), bkhd.begin(), bkhd.end());
    bank.insert(bank.end(), {'H', 'I', 'R', 'C'});
    Put<uint32_t>(bank, static_cast<uint32_t>(hirc.size()));
    bank.insert(bank.end(), hirc.begin(), hirc.end());
    return bank;
}

inline bool LoadBank()
{
    const std::vector<uint8_t> bank = BuildBank();
    std::vector<uint8_t> aligned(bank.size() + 16);
    uint8_t* p = aligned.data() + ((16 - (reinterpret_cast<uintptr_t>(aligned.data()) & 15)) & 15);
    std::memcpy(p, bank.data(), bank.size());
    uint32_t bankId = 0;
    const int32_t result = g_loadBank(p, static_cast<uint32_t>(bank.size()), &bankId);
    if (result == 92)
    {
        return false;  // the init bank is not loaded yet: the next tick tries again
    }
    if (result == 1 || result == 69)
    {
        g_bankLoaded = true;
        Log("bank loaded (" + std::to_string(bank.size()) + " bytes, result " + std::to_string(result) + ")");
    }
    else
    {
        g_bankFailed = true;
        Log("loading the bank returned " + std::to_string(result) + " - no equaliser");
    }
    return true;
}

inline void SendProcessing()
{
    for (int st = 0; st < kStageCount; ++st)
    {
        for (int k = 0; k < 2; ++k)
        {
            const float v = g_procValues[st][k].load();
            if (!g_procSentValid || v != g_procSent[st][k])
            {
                g_setRtpc(kProcessors[st].rtpc[k], v, kGlobalObject, kGainGlideMs, kCurveLinear, false);
                g_procSent[st][k] = v;
            }
        }
    }
    g_procSentValid = true;
}

inline void SendGains()
{
    if (!g_gainsPending.exchange(false))
    {
        return;
    }
    for (size_t i = 0; i < kBandCount; ++i)
    {
        const float db = g_gains[i].load();
        if (db != g_gainsSent[i])
        {
            g_setRtpc(kBandRtpc[i], db, kGlobalObject, kGainGlideMs, kCurveLinear, false);
            g_gainsSent[i] = db;
        }
    }
}

// Called from the game-state update.
inline void Tick()
{
    if (!g_loadBank || !g_setBusEffect || !g_setRtpc || g_bankFailed)
    {
        return;
    }
    if (!g_bankLoaded && !LoadBank())
    {
        return;
    }
    if (!g_bankLoaded)
    {
        return;
    }
    SendGains();
    SendProcessing();
    for (int st = 0; st < kStageCount; ++st)
    {
        const bool on = g_stageWanted[st].load();
        if (g_stageValid[st] && g_stageApplied[st] == on)
        {
            continue;
        }
        const Processor& proc = kProcessors[st];
        std::string results;
        bool found = true;
        for (const uint32_t bus : proc.onChildBuses ? std::vector<uint32_t>{kVehicleBus, kMetroBus}
                                                    : std::vector<uint32_t>{kTopBus})
        {
            const int32_t result = g_setBusEffect(bus, proc.slot, on ? proc.id : 0);
            found = found && result != 15;
            results += " " + std::to_string(bus) + "/" + std::to_string(proc.slot) + ":" + std::to_string(result);
        }
        if (found)
        {
            g_stageApplied[st] = on;
            g_stageValid[st] = true;
            Log(std::string(proc.name) + (on ? " on" : " off") + " (results" + results + ")");
        }
    }
    const bool want = g_wanted.load();
    if (g_appliedValid && g_applied == want)
    {
        return;
    }
    std::string results;
    bool allFound = true;
    for (const uint32_t bus : kBuses)
    {
        for (uint32_t slot = 0; slot < 3; ++slot)
        {
            const int32_t result = g_setBusEffect(bus, slot, want ? kShareSets[slot] : 0);
            allFound = allFound && result != 15;
            results += " " + std::to_string(bus) + "/" + std::to_string(slot) + ":" + std::to_string(result);
        }
    }
    if (!allFound)
    {
        return;  // a bus is not loaded yet
    }
    g_applied = want;
    g_appliedValid = true;
    Log(std::string(want ? "inserted into" : "removed from") + " the player radio buses (results" + results + ")");
}

inline void SetEnabled(bool aOn)
{
    g_wanted = aOn;
}

// A stage's threshold (0) or output gain (1), in dB.
inline void SetProcessingValue(int32_t aStage, int32_t aWhich, float aDb)
{
    if (aStage >= 0 && aStage < kStageCount && (aWhich == 0 || aWhich == 1) && std::isfinite(aDb))
    {
        g_procValues[aStage][aWhich] = (std::min)((std::max)(aDb, -kProcessorRange), kProcessorRange);
    }
}

inline void SetStage(int32_t aStage, bool aOn)
{
    if (aStage >= 0 && aStage < kStageCount)
    {
        g_stageWanted[aStage] = aOn;
    }
}

// A band's gain in dB, 0 = flat.
inline void SetBand(int32_t aBand, float aDb)
{
    if (aBand < 0 || aBand >= static_cast<int32_t>(kBandCount))
    {
        return;
    }
    const float db = std::isfinite(aDb) ? (std::min)((std::max)(aDb, -kGainLimit), kGainLimit) : 0.0f;
    g_gains[aBand] = db;
    g_gainsPending = true;
}

inline void Init(uintptr_t (*aResolve)(uint32_t))
{
    const auto load = reinterpret_cast<const uint8_t*>(aResolve(kHashLoadBankMemoryCopy));
    const auto set = reinterpret_cast<const uint8_t*>(aResolve(kHashSetBusEffect));
    const auto rtpc = reinterpret_cast<const uint8_t*>(aResolve(kHashSetRtpc));
    if (!load || std::memcmp(load, kLoadBankPrologue, sizeof(kLoadBankPrologue)) != 0 || !set ||
        std::memcmp(set, kSetBusEffectPrologue, sizeof(kSetBusEffectPrologue)) != 0 || !rtpc ||
        std::memcmp(rtpc, kSetRtpcPrologue, sizeof(kSetRtpcPrologue)) != 0)
    {
        Log("byte check FAILED at the bank loader, the bus effect setter or the game parameter setter - no equaliser");
        return;
    }
    g_loadBank = reinterpret_cast<LoadBankFn>(const_cast<uint8_t*>(load));
    g_setBusEffect = reinterpret_cast<SetBusEffectFn>(const_cast<uint8_t*>(set));
    g_setRtpc = reinterpret_cast<SetRtpcFn>(const_cast<uint8_t*>(rtpc));
    Log("ready");
}

} // namespace radioxl::eq
