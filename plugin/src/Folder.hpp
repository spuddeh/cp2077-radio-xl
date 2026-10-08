// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Keeps a station's track list in step with its folder, for a station that opts in
//              with "addUnlistedFiles": true. No filesystem calls: the caller lists the folder.
// File Version: 0.7.0
// ======================================================================================

#pragma once

#include "Json.hpp"

#include <algorithm>
#include <functional>
#include <set>
#include <string>
#include <vector>

namespace radioxl
{
// A path compared the way the file system and a track's identity compare it: forward slashes,
// ASCII lower case.
inline std::string NormalisePath(std::string aPath)
{
    for (char& c : aPath)
    {
        if (c == '\\')
        {
            c = '/';
        }
        else if (c >= 'A' && c <= 'Z')
        {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return aPath;
}

inline bool IsAudioFile(const std::string& aPath)
{
    const auto dot = aPath.find_last_of('.');
    if (dot == std::string::npos)
    {
        return false;
    }
    const std::string ext = NormalisePath(aPath.substr(dot + 1));
    return ext == "wav" || ext == "mp3" || ext == "ogg" || ext == "flac";
}

// The station builder's rule (`titleFromFile`): folder and extension dropped, `_` read as a space.
inline std::string TitleFromFile(const std::string& aPath)
{
    std::string base = aPath;
    const auto slash = base.find_last_of("/\\");
    if (slash != std::string::npos)
    {
        base = base.substr(slash + 1);
    }
    const auto dot = base.find_last_of('.');
    if (dot != std::string::npos && dot > 0)
    {
        base = base.substr(0, dot);
    }
    std::replace(base.begin(), base.end(), '_', ' ');
    const auto first = base.find_first_not_of(' ');
    const auto last = base.find_last_not_of(' ');
    return first == std::string::npos ? std::string() : base.substr(first, last - first + 1);
}

// JSON laid out the way the station builder writes it: two-space indent, one member per line.
inline void WriteJsonIndented(const JsonValue& aValue, std::string& aOut, int aDepth = 0)
{
    const std::string pad(static_cast<size_t>(aDepth + 1) * 2, ' ');
    const std::string close(static_cast<size_t>(aDepth) * 2, ' ');
    if (aValue.Is(JsonValue::Kind::Array) && !aValue.array.empty())
    {
        aOut += "[\n";
        for (size_t i = 0; i < aValue.array.size(); ++i)
        {
            aOut += pad;
            WriteJsonIndented(aValue.array[i], aOut, aDepth + 1);
            aOut += i + 1 < aValue.array.size() ? ",\n" : "\n";
        }
        aOut += close + "]";
        return;
    }
    if (aValue.Is(JsonValue::Kind::Object) && !aValue.object.empty())
    {
        aOut += "{\n";
        for (size_t i = 0; i < aValue.object.size(); ++i)
        {
            JsonValue key;
            key.kind = JsonValue::Kind::String;
            key.string = aValue.object[i].first;
            aOut += pad;
            WriteJson(key, aOut);
            aOut += ": ";
            WriteJsonIndented(aValue.object[i].second, aOut, aDepth + 1);
            aOut += i + 1 < aValue.object.size() ? ",\n" : "\n";
        }
        aOut += close + "}";
        return;
    }
    WriteJson(aValue, aOut);
}

struct FolderSync
{
    bool changed = false;
    std::string text;                  // the manifest to write, when changed
    std::vector<std::string> added;    // relative paths
    std::vector<std::string> removed;  // relative paths, as the manifest spelled them
};

// For a manifest with "addUnlistedFiles": true, the track list after adding every audio file in
// `aOnDisk` (relative paths) it does not list, and removing every listed file not in `aOnDisk`.
// Every other key is kept as it is. A manifest without the key, one that does not parse, and a
// stream station (whose one track is its stream) are left alone.
inline FolderSync SyncFolder(const std::string& aManifest, const std::vector<std::string>& aOnDisk)
{
    FolderSync result;
    JsonValue root;
    JsonError error;
    if (!ParseJson(aManifest, root, error) || !root.Is(JsonValue::Kind::Object))
    {
        return result;
    }
    const JsonValue* opt = root.Find("addUnlistedFiles");
    if (!opt || !opt->Is(JsonValue::Kind::Bool) || !opt->boolean)
    {
        return result;
    }
    JsonValue* tracks = nullptr;
    for (auto& [key, value] : root.object)
    {
        if (key == "tracks" && value.Is(JsonValue::Kind::Array))
        {
            tracks = &value;
        }
    }
    if (!tracks)
    {
        return result;
    }
    for (const JsonValue& item : tracks->array)
    {
        if (item.Is(JsonValue::Kind::Object) && item.Find("url"))
        {
            return result;
        }
    }

    std::set<std::string> present;
    for (const auto& path : aOnDisk)
    {
        present.insert(NormalisePath(path));
    }

    std::set<std::string> listed;
    std::vector<JsonValue> kept;
    for (const JsonValue& item : tracks->array)
    {
        const JsonValue* file = item.Is(JsonValue::Kind::Object) ? item.Find("file") : nullptr;
        if (file && file->Is(JsonValue::Kind::String))
        {
            const std::string key = NormalisePath(file->string);
            if (!present.count(key))
            {
                result.removed.push_back(file->string);
                continue;
            }
            listed.insert(key);
        }
        kept.push_back(item);
    }

    std::vector<std::string> candidates = aOnDisk;
    std::sort(candidates.begin(), candidates.end());
    for (const auto& path : candidates)
    {
        const std::string key = NormalisePath(path);
        if (!IsAudioFile(path) || listed.count(key))
        {
            continue;
        }
        listed.insert(key);
        JsonValue entry;
        entry.kind = JsonValue::Kind::Object;
        JsonValue file;
        file.kind = JsonValue::Kind::String;
        file.string = path;
        JsonValue title;
        title.kind = JsonValue::Kind::String;
        title.string = TitleFromFile(path);
        entry.object.emplace_back("file", file);
        entry.object.emplace_back("title", title);
        kept.push_back(entry);
        result.added.push_back(path);
    }

    if (result.added.empty() && result.removed.empty())
    {
        return result;
    }
    tracks->array = std::move(kept);
    result.changed = true;
    WriteJsonIndented(root, result.text);
    result.text += "\n";
    return result;
}
}  // namespace radioxl
