// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Runtime text for a localization key, answered in place of the loaded row.
// File Version: 0.11.0
// ======================================================================================
//
// The game copies the on-screen rows into its own repository as they load, so a row rewritten
// afterwards is never read. Every on-screen lookup by key, by CName or by string, ends in the
// repository's GetString (vtable slot 3 of OnScreensRepositoryBase), first with the 64-bit key and
// then with the 32-bit one. The hook answers a key that has text set here and passes every other
// key to the game. A key is stored under both widths, as the rows are.

#pragma once

#include <RED4ext/RED4ext.hpp>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <functional>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <unordered_map>

namespace radioxl::text
{
// OnScreensRepositoryBase::GetString(uint64 key, bool female, bool& found) -> String. 2.5: 0x1c46a4.
constexpr uint32_t kHashGetString = 749150586;

// Its prologue on 2.5. Another build's bytes leave the hook off and every key keeps its loaded text.
constexpr uint8_t kGetStringLead[] = {0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x48, 0x89, 0x68, 0x10,
                                      0x48, 0x89, 0x70, 0x20, 0x4C, 0x89, 0x40, 0x18, 0x57};

// A lookup by string first turns the string into the repository's key through this, a hash of its
// own: the by-string key is neither width of the row's key. 2.5: 0x4eddc8.
constexpr uint32_t kHashStringKey = 3552190842;
constexpr uint8_t kStringKeyLead[] = {0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x74, 0x24, 0x18,
                                      0x48, 0x89, 0x7C, 0x24, 0x20, 0x55, 0x48, 0x8B, 0xEC};

struct StringView
{
    const char* data;
    uint32_t size;
};

using GetStringFn = RED4ext::CString* (*)(void*, RED4ext::CString*, uint64_t, bool, bool*);
using StringKeyFn = uint64_t (*)(const StringView*);

inline std::function<void(const std::string&)> g_log;
inline GetStringFn g_origGetString = nullptr;
inline std::shared_mutex g_lock;
inline std::unordered_map<uint64_t, std::string> g_texts;
inline std::atomic<bool> g_any{false};
inline bool g_hooked = false;
inline StringKeyFn g_stringKey = nullptr;

inline void Log(const std::string& aText)
{
    if (g_log)
    {
        g_log("text: " + aText);
    }
}

inline RED4ext::CString* GetString(void* aSelf, RED4ext::CString* aOut, uint64_t aKey, bool aFemale, bool* aFound)
{
    if (g_any.load(std::memory_order_relaxed))
    {
        std::shared_lock lock(g_lock);
        const auto it = g_texts.find(aKey);
        if (it != g_texts.end())
        {
            new (aOut) RED4ext::CString(it->second.c_str());
            if (aFound)
            {
                *aFound = true;
            }
            return aOut;
        }
    }
    return g_origGetString(aSelf, aOut, aKey, aFemale, aFound);
}

inline bool Hook(uintptr_t (*aResolve)(uint32_t), const RED4ext::v1::Sdk* aSdk, RED4ext::v1::PluginHandle aHandle)
{
    auto* fn = reinterpret_cast<uint8_t*>(aResolve(kHashGetString));
    if (!fn || std::memcmp(fn, kGetStringLead, sizeof(kGetStringLead)) != 0)
    {
        Log("byte check FAILED at the on-screen text lookup - runtime names are off");
        return false;
    }
    if (!aSdk->hooking->Attach(aHandle, fn, reinterpret_cast<void*>(&GetString),
                               reinterpret_cast<void**>(&g_origGetString)))
    {
        Log("could not hook the on-screen text lookup - runtime names are off");
        return false;
    }
    g_hooked = true;
    auto* key = reinterpret_cast<uint8_t*>(aResolve(kHashStringKey));
    if (key && std::memcmp(key, kStringKeyLead, sizeof(kStringKeyLead)) == 0)
    {
        g_stringKey = reinterpret_cast<StringKeyFn>(key);
    }
    else
    {
        Log("byte check FAILED at the string key - runtime names show only where a key is looked up by name");
    }
    return true;
}

// Text for a key under both widths and its by-string key; empty text gives the key back to its
// loaded row.
inline bool Set(const std::string& aKey, uint32_t aHash32, uint64_t aHash64, const std::string& aText)
{
    if (!g_hooked)
    {
        return false;
    }
    uint64_t byString = 0;
    if (g_stringKey)
    {
        const StringView view{aKey.c_str(), static_cast<uint32_t>(aKey.size())};
        byString = g_stringKey(&view);
    }
    std::unique_lock lock(g_lock);
    for (const uint64_t k : {static_cast<uint64_t>(aHash32), aHash64, byString})
    {
        if (k == 0)
        {
            continue;
        }
        if (aText.empty())
        {
            g_texts.erase(k);
        }
        else
        {
            g_texts[k] = aText;
        }
    }
    g_any.store(!g_texts.empty(), std::memory_order_relaxed);
    return true;
}
} // namespace radioxl::text
