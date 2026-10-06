// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A car's radio, switched on with no station set, picks from its whole startup list.
// File Version: 0.8.0
// ======================================================================================
//
// The receiver's turn-on block (reached through the enable routine's jne at +0x42) copies the car's
// `matchingStartupRadioStations` into a 14-slot array on the stack, filters it while the radio system
// already plays its limit of stations, and picks one at random. Entries past the 14th never reach the
// pick, so a custom station appended after them is never a car's first station. The block is
// detoured at +0x54, where the car's metadata is in rax: a stub copies the whole list into a buffer of
// its own, runs the game's own filter over it, picks, and rejoins the block at its
// TryGetRadioStationChannel call with the name in rcx. An empty pick rejoins where the block's own
// empty case goes. Every address comes from the block's own instructions, checked byte by byte.

#pragma once

#include <Windows.h>

#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

namespace radioxl::startup
{

constexpr size_t kHookAt = 0x54;
constexpr uint8_t kHook[] = {0x48, 0x8B, 0x88, 0x88, 0x00, 0x00, 0x00, 0x33, 0xD2};  // mov rcx,[rax+0x88]; xor edx,edx
constexpr size_t kCapAt = 0x6F;
constexpr uint8_t kCap[] = {0x83, 0xFA, 0x0E};                       // cmp edx, 14
constexpr size_t kCopyAt = 0x7C;
constexpr uint8_t kCopy[] = {0x48, 0x89, 0x44, 0xD5, 0xCF};          // mov [rbp+rdx*8-0x31], rax
constexpr size_t kEngineAt = 0x92;
constexpr uint8_t kEngine[] = {0x48, 0x8B, 0x05};                    // mov rax, [rip+rel32]
constexpr uint8_t kRadioSystem[] = {0x48, 0x8B, 0xB0, 0xA8, 0x00, 0x00, 0x00, 0x48, 0x85, 0xF6};  // +0x99
constexpr uint8_t kRadioManager[] = {0x48, 0x8B, 0xB6, 0xE0, 0x00, 0x00, 0x00};                   // +0xa5
constexpr size_t kActiveCallAt = 0xB4;
constexpr size_t kLimitCallAt = 0xBF;
constexpr size_t kFilterCallAt = 0xE2;
constexpr size_t kPickAt = 0x159;
constexpr uint8_t kPick[] = {0x48, 0x8D, 0x55, 0x67, 0x48, 0x8B, 0x4C, 0xCD, 0xD7, 0xE8};  // lea rdx; mov rcx; call
constexpr size_t kResolveCallAt = 0x162;
constexpr size_t kEmptyAt = 0x174;
constexpr uint8_t kEmpty[] = {0x83, 0x7F, 0x0C};                     // cmp dword [rdi+0xc], imm8

using CountFn = uint32_t (*)(void*);
using FilterFn = uint64_t** (*)(uint64_t**, uint64_t*, uint64_t*, void*);

inline std::function<void(const std::string&)> g_log;
inline uintptr_t* g_engineVar = nullptr;
inline CountFn g_activeCount = nullptr;
inline CountFn g_limit = nullptr;
inline FilterFn g_filter = nullptr;
inline uint64_t g_seed = 0;

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("startup pick: " + aText);
    }
}

inline const uint8_t* CallTarget(const uint8_t* aCall)
{
    int32_t rel = 0;
    std::memcpy(&rel, aCall + 1, sizeof(rel));
    return aCall + 5 + rel;
}

// The station a car switched on with none set starts on, from its whole list; 0 when none can be.
inline uint64_t Pick(const uint8_t* aMetadata)
{
    const auto* data = *reinterpret_cast<uint64_t* const*>(aMetadata + 0x88);
    const auto size = *reinterpret_cast<const uint32_t*>(aMetadata + 0x94);
    if (!data || size == 0)
    {
        return 0;
    }
    std::vector<uint64_t> names(data, data + size);
    uint64_t* end = names.data() + names.size();
    const uintptr_t engine = g_engineVar ? *g_engineVar : 0;
    const uintptr_t audio = engine ? *reinterpret_cast<uintptr_t*>(engine + 0xa8) : 0;
    void* radio = audio ? *reinterpret_cast<void**>(audio + 0xe0) : nullptr;
    if (radio && g_activeCount(radio) >= g_limit(radio))
    {
        uint64_t* kept = nullptr;
        end = *g_filter(&kept, names.data(), end, radio);
    }
    const size_t left = static_cast<size_t>(end - names.data());
    if (left == 0)
    {
        return 0;
    }
    g_seed = g_seed * 6364136223846793005ull + 1442695040888963407ull;
    const size_t index = static_cast<size_t>(g_seed >> 33) % left;
    Log("entry " + std::to_string(index) + " of " + std::to_string(left) + " (list of " + std::to_string(size) + ")");
    return names[index];
}

using WriteFn = bool (*)(void*, const void*, size_t);
using AllocateFn = void* (*)(uintptr_t, size_t);

// `aBlock` is the turn-on block. Checks every site, builds the stub, then writes the jump.
inline bool Install(uint8_t* aBlock, AllocateFn aAllocate, WriteFn aWrite)
{
    struct Site
    {
        size_t at;
        const uint8_t* bytes;
        size_t len;
    };
    const Site sites[] = {
        {kHookAt, kHook, sizeof(kHook)},
        {kCapAt, kCap, sizeof(kCap)},
        {kCopyAt, kCopy, sizeof(kCopy)},
        {kEngineAt, kEngine, sizeof(kEngine)},
        {kEngineAt + 7, kRadioSystem, sizeof(kRadioSystem)},
        {0xA5, kRadioManager, sizeof(kRadioManager)},
        {kPickAt, kPick, sizeof(kPick)},
        {kEmptyAt, kEmpty, sizeof(kEmpty)},
    };
    for (const Site& s : sites)
    {
        if (std::memcmp(aBlock + s.at, s.bytes, s.len) != 0)
        {
            Log("byte check FAILED at +0x" + std::to_string(s.at) + " - a car still picks from its first 14 stations");
            return false;
        }
    }
    for (const size_t call : {kActiveCallAt, kLimitCallAt, kFilterCallAt})
    {
        if (aBlock[call] != 0xE8)
        {
            Log("byte check FAILED at a call - a car still picks from its first 14 stations");
            return false;
        }
    }
    int32_t rel = 0;
    std::memcpy(&rel, aBlock + kEngineAt + 3, sizeof(rel));
    g_engineVar = reinterpret_cast<uintptr_t*>(aBlock + kEngineAt + 7 + rel);
    g_activeCount = reinterpret_cast<CountFn>(const_cast<uint8_t*>(CallTarget(aBlock + kActiveCallAt)));
    g_limit = reinterpret_cast<CountFn>(const_cast<uint8_t*>(CallTarget(aBlock + kLimitCallAt)));
    g_filter = reinterpret_cast<FilterFn>(const_cast<uint8_t*>(CallTarget(aBlock + kFilterCallAt)));
    g_seed = GetTickCount64() | 1;

    // sub rsp,0x20; mov rcx,rax; mov rax,Pick; call rax; add rsp,0x20; test rax,rax; jz empty;
    // mov dword [rbp+0x67],0xff; mov rcx,rax; lea rdx,[rbp+0x67]; mov rax,resolveCall; jmp rax;
    // empty: mov rax,emptyCase; jmp rax
    std::vector<uint8_t> stub = {0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xC8, 0x48, 0xB8};
    const auto push64 = [&stub](uint64_t aValue)
    {
        for (int i = 0; i < 8; ++i)
        {
            stub.push_back(static_cast<uint8_t>(aValue >> (8 * i)));
        }
    };
    push64(reinterpret_cast<uint64_t>(&Pick));
    const uint8_t mid[] = {0xFF, 0xD0, 0x48, 0x83, 0xC4, 0x20, 0x48, 0x85, 0xC0, 0x74, 0x1A,
                           0xC7, 0x45, 0x67, 0xFF, 0x00, 0x00, 0x00, 0x48, 0x8B, 0xC8, 0x48, 0x8D, 0x55, 0x67,
                           0x48, 0xB8};
    stub.insert(stub.end(), std::begin(mid), std::end(mid));
    push64(reinterpret_cast<uint64_t>(aBlock + kResolveCallAt));
    stub.push_back(0xFF);
    stub.push_back(0xE0);
    stub.push_back(0x48);
    stub.push_back(0xB8);
    push64(reinterpret_cast<uint64_t>(aBlock + kEmptyAt));
    stub.push_back(0xFF);
    stub.push_back(0xE0);

    auto* code = static_cast<uint8_t*>(aAllocate(reinterpret_cast<uintptr_t>(aBlock), stub.size()));
    if (!code)
    {
        Log("could not place the stub near the block - a car still picks from its first 14 stations");
        return false;
    }
    std::memcpy(code, stub.data(), stub.size());
    DWORD old = 0;
    if (!VirtualProtect(code, stub.size(), PAGE_EXECUTE_READ, &old))
    {
        Log("could not make the stub executable - a car still picks from its first 14 stations");
        return false;
    }
    FlushInstructionCache(GetCurrentProcess(), code, stub.size());

    const int64_t jump = reinterpret_cast<int64_t>(code) - reinterpret_cast<int64_t>(aBlock + kHookAt + 5);
    if (jump > INT32_MAX || jump < INT32_MIN)
    {
        Log("the stub is out of reach of the block - a car still picks from its first 14 stations");
        return false;
    }
    uint8_t patch[7] = {0xE9, 0, 0, 0, 0, 0x90, 0x90};
    const int32_t rel32 = static_cast<int32_t>(jump);
    std::memcpy(patch + 1, &rel32, sizeof(rel32));
    if (!aWrite(aBlock + kHookAt, patch, sizeof(patch)))
    {
        Log("the jump could not be written - a car still picks from its first 14 stations");
        return false;
    }
    Log("a car switched on with no station picks from its whole list");
    return true;
}

} // namespace radioxl::startup
