// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Equaliser presets: one JSON file each in red4ext/plugins/RadioXL/presets/, read at load.
// File Version: 0.8.0
// ======================================================================================
//
// A preset is a name and nine band gains, nothing else:
//   { "name": "Techno", "bands": [6, 4, 1, -1, -2, -1, 1, 3, 3] }
// The bands are dB at 63, 125, 250, 500 Hz and 1, 2, 4, 8, 16 kHz, each -24 to 24. Which station plays which
// preset is the player's setting, not the file's. A file with a fault is skipped and its fault logged as
// presets/<file>:<line>: <what>; an unknown key is logged and ignored. Two presets may not share a name, ignoring
// case: the later file is skipped. "Flat" sorts first, the rest by name.

#pragma once

#include "Json.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

namespace radioxl::presets
{

constexpr size_t kBands = 9;
constexpr double kBandLimit = 24.0;

struct Preset
{
    std::string name;
    std::array<float, kBands> bands{};
    float trim = 0.0f;  // dB on every band, so the preset changes tone rather than loudness
};

inline std::vector<Preset> g_presets;

inline std::string Utf8(const std::u8string& aText)
{
    return std::string(reinterpret_cast<const char*>(aText.data()), aText.size());
}

inline std::string Lower(std::string aText)
{
    std::transform(aText.begin(), aText.end(), aText.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return aText;
}

// The level a set of band gains adds, taken as the mean of their power over the nine octaves, and its opposite.
inline float LevelTrim(const std::array<float, kBands>& aBands)
{
    double power = 0.0;
    for (const float g : aBands)
    {
        power += std::pow(10.0, g / 10.0);
    }
    return static_cast<float>(-10.0 * std::log10(power / kBands));
}

inline bool Read(const std::string& aText, const std::string& aWhere, Preset& aOut,
                 const std::function<void(const std::string&)>& aLog)
{
    JsonValue root;
    JsonError error;
    if (!ParseJson(aText, root, error))
    {
        aLog(aWhere + ":" + std::to_string(error.line) + ": " + error.what);
        return false;
    }
    if (!root.Is(JsonValue::Kind::Object))
    {
        aLog(aWhere + ":" + std::to_string(root.line) + ": a preset is an object {...}");
        return false;
    }
    for (const auto& [key, value] : root.object)
    {
        if (key != "name" && key != "bands")
        {
            aLog(aWhere + ":" + std::to_string(value.line) + ": unknown key \"" + key + "\" - ignored");
        }
    }
    const JsonValue* name = root.Find("name");
    if (!name || !name->Is(JsonValue::Kind::String))
    {
        aLog(aWhere + ":" + std::to_string(name ? name->line : root.line) + ": \"name\" must be a string");
        return false;
    }
    if (name->string.empty() || name->string.front() == ' ' || name->string.back() == ' ')
    {
        aLog(aWhere + ":" + std::to_string(name->line) + ": \"name\" is empty or has a space at an end");
        return false;
    }
    const JsonValue* bands = root.Find("bands");
    if (!bands || !bands->Is(JsonValue::Kind::Array) || bands->array.size() != kBands)
    {
        aLog(aWhere + ":" + std::to_string(bands ? bands->line : root.line) + ": \"bands\" must be an array of " +
             std::to_string(kBands) + " numbers (63 Hz to 16 kHz)");
        return false;
    }
    for (size_t i = 0; i < kBands; ++i)
    {
        const JsonValue& band = bands->array[i];
        if (!band.Is(JsonValue::Kind::Number) || std::fabs(band.number) > kBandLimit)
        {
            aLog(aWhere + ":" + std::to_string(band.line) + ": band " + std::to_string(i + 1) +
                 " must be a number from -24 to 24");
            return false;
        }
        aOut.bands[i] = static_cast<float>(band.number);
    }
    aOut.name = name->string;
    aOut.trim = LevelTrim(aOut.bands);
    return true;
}

inline void Load(const std::filesystem::path& aFolder, const std::function<void(const std::string&)>& aLog)
{
    g_presets.clear();
    std::error_code ec;
    if (!std::filesystem::is_directory(aFolder, ec))
    {
        aLog("presets: no presets folder - the equaliser has Flat only");
    }
    std::vector<std::filesystem::path> files;
    for (auto it = std::filesystem::recursive_directory_iterator(aFolder, ec);
         !ec && it != std::filesystem::recursive_directory_iterator(); it.increment(ec))
    {
        if (it->is_regular_file(ec) && Lower(it->path().extension().string()) == ".json")
        {
            files.push_back(it->path());
        }
    }
    std::sort(files.begin(), files.end());
    for (const auto& file : files)
    {
        const std::string where = "presets/" + Utf8(std::filesystem::relative(file, aFolder, ec).generic_u8string());
        std::ifstream in(file, std::ios::binary);
        if (!in)
        {
            aLog(where + ": cannot be opened - skipped");
            continue;
        }
        std::stringstream buffer;
        buffer << in.rdbuf();
        Preset preset;
        if (!Read(buffer.str(), where, preset, aLog))
        {
            aLog(where + ": skipped");
            continue;
        }
        const std::string key = Lower(preset.name);
        if (std::any_of(g_presets.begin(), g_presets.end(), [&](const Preset& p) { return Lower(p.name) == key; }))
        {
            aLog(where + ": a preset named \"" + preset.name + "\" is already loaded - skipped");
            continue;
        }
        g_presets.push_back(preset);
    }
    if (std::none_of(g_presets.begin(), g_presets.end(), [](const Preset& p) { return Lower(p.name) == "flat"; }))
    {
        g_presets.push_back(Preset{"Flat", {}, 0.0f});
    }
    std::stable_sort(g_presets.begin(), g_presets.end(), [](const Preset& a, const Preset& b)
    {
        const bool af = Lower(a.name) == "flat";
        const bool bf = Lower(b.name) == "flat";
        if (af != bf)
        {
            return af;
        }
        return Lower(a.name) < Lower(b.name);
    });
    aLog("presets: " + std::to_string(g_presets.size()) + " loaded");
}

constexpr size_t kMaxNameLength = 40;
enum SaveResult : int32_t
{
    kSaveBadName = -1,    // empty, longer than kMaxNameLength, a control character, a space at an end, or "Custom"
    kSaveNameTaken = -2,  // a loaded preset has the name, ignoring case
    kSaveWriteFailed = -3,
};

inline std::string JsonQuoted(const std::string& aText)
{
    std::string out = "\"";
    for (const char c : aText)
    {
        if (c == '"' || c == '\\')
        {
            out += '\\';
        }
        out += c;
    }
    return out + "\"";
}

// The file a new preset is written to: its name in lower case, letters and digits kept and every other run of
// characters one hyphen, with -2, -3 and so on added while that file exists.
inline std::filesystem::path FileFor(const std::filesystem::path& aFolder, const std::string& aName)
{
    std::string stem;
    for (const unsigned char c : Lower(aName))
    {
        if (std::isalnum(c) && c < 0x80)
        {
            stem += static_cast<char>(c);
        }
        else if (!stem.empty() && stem.back() != '-')
        {
            stem += '-';
        }
    }
    while (!stem.empty() && stem.back() == '-')
    {
        stem.pop_back();
    }
    if (stem.empty())
    {
        stem = "preset";
    }
    std::error_code ec;
    auto path = aFolder / (stem + ".json");
    for (int n = 2; std::filesystem::exists(path, ec); ++n)
    {
        path = aFolder / (stem + "-" + std::to_string(n) + ".json");
    }
    return path;
}

// Writes a new preset file and reloads the folder. Returns the preset's index, or a SaveResult.
inline int32_t Save(const std::filesystem::path& aFolder, const std::string& aName, const std::vector<int32_t>& aBands,
                    const std::function<void(const std::string&)>& aLog)
{
    const bool control = std::any_of(aName.begin(), aName.end(), [](unsigned char c) { return c < 0x20 || c == 0x7f; });
    if (aName.empty() || aName.size() > kMaxNameLength || control || aName.front() == ' ' || aName.back() == ' ' ||
        Lower(aName) == "custom")
    {
        aLog("presets: \"" + aName + "\" is not a name a preset can have - not saved");
        return kSaveBadName;
    }
    const std::string key = Lower(aName);
    if (std::any_of(g_presets.begin(), g_presets.end(), [&](const Preset& p) { return Lower(p.name) == key; }))
    {
        aLog("presets: a preset named \"" + aName + "\" is already loaded - not saved");
        return kSaveNameTaken;
    }
    std::string text = "{\n  \"name\": " + JsonQuoted(aName) + ",\n  \"bands\": [";
    for (size_t i = 0; i < kBands; ++i)
    {
        const int32_t gain = i < aBands.size() ? std::clamp<int32_t>(aBands[i], -24, 24) : 0;
        text += (i ? ", " : "") + std::to_string(gain);
    }
    text += "]\n}\n";
    std::error_code ec;
    std::filesystem::create_directories(aFolder, ec);
    const auto path = FileFor(aFolder, aName);
    {
        std::ofstream out(path, std::ios::binary);
        out << text;
        if (!out)
        {
            aLog("presets: " + Utf8(path.filename().generic_u8string()) + " could not be written - not saved");
            return kSaveWriteFailed;
        }
    }
    aLog("presets: \"" + aName + "\" saved as " + Utf8(path.filename().generic_u8string()));
    Load(aFolder, aLog);
    for (size_t i = 0; i < g_presets.size(); ++i)
    {
        if (Lower(g_presets[i].name) == key)
        {
            return static_cast<int32_t>(i);
        }
    }
    return kSaveWriteFailed;
}

inline const Preset* At(int32_t aIndex)
{
    return aIndex >= 0 && aIndex < static_cast<int32_t>(g_presets.size()) ? &g_presets[aIndex] : nullptr;
}

} // namespace radioxl::presets
