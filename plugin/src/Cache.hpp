// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A track's length read from its header, kept between launches and keyed by the
//              file's size and modified time, so an unchanged file is not read again.
// File Version: 0.6.0
// ======================================================================================
//
// The cache is a convenience and never a source of truth: a missing, unreadable or stale entry
// means the header is read, nothing more. A length is never written into a manifest.

#pragma once

#include "Json.hpp"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>

namespace radioxl
{
class LengthCache
{
public:
    void Load(const std::filesystem::path& aFile)
    {
        m_file = aFile;
        std::ifstream in(aFile, std::ios::binary);
        if (!in)
        {
            return;
        }
        std::stringstream buffer;
        buffer << in.rdbuf();
        JsonValue root;
        JsonError error;
        if (!ParseJson(buffer.str(), root, error) || !root.Is(JsonValue::Kind::Object))
        {
            m_dirty = true;
            return;
        }
        const JsonValue* files = root.Find("files");
        if (!files || !files->Is(JsonValue::Kind::Object))
        {
            m_dirty = true;
            return;
        }
        for (const auto& [key, entry] : files->object)
        {
            const JsonValue* size = entry.Find("size");
            const JsonValue* modified = entry.Find("modified");
            const JsonValue* length = entry.Find("length");
            if (size && size->Is(JsonValue::Kind::Number) && modified && modified->Is(JsonValue::Kind::String) &&
                length && length->Is(JsonValue::Kind::Number))
            {
                m_entries[key] = Entry{static_cast<uint64_t>(size->number), modified->string,
                                       static_cast<float>(length->number)};
            }
        }
    }

    // The file's length, from the cache when its size and modified time match, else from aRead.
    template <typename Read>
    float Length(const std::string& aKey, const std::filesystem::path& aPath, Read&& aRead)
    {
        m_seen.insert(aKey);
        std::error_code ec;
        const uint64_t size = std::filesystem::file_size(aPath, ec);
        if (ec)
        {
            return aRead(aPath);
        }
        const auto time = std::filesystem::last_write_time(aPath, ec);
        if (ec)
        {
            return aRead(aPath);
        }
        // Ticks run past a double's exact range, so the time is kept as text.
        const std::string modified = std::to_string(time.time_since_epoch().count());
        const auto found = m_entries.find(aKey);
        if (found != m_entries.end() && found->second.size == size && found->second.modified == modified)
        {
            ++m_hits;
            return found->second.length;
        }
        const float length = aRead(aPath);
        if (length > 0.0f)
        {
            m_entries[aKey] = Entry{size, modified, length};
            m_dirty = true;
        }
        return length;
    }

    // Drops every entry this load did not ask for, and writes the file when anything changed.
    void Save()
    {
        for (auto it = m_entries.begin(); it != m_entries.end();)
        {
            if (!m_seen.count(it->first))
            {
                it = m_entries.erase(it);
                m_dirty = true;
                continue;
            }
            ++it;
        }
        if (!m_dirty || m_file.empty())
        {
            return;
        }
        JsonValue files;
        files.kind = JsonValue::Kind::Object;
        for (const auto& [key, entry] : m_entries)
        {
            JsonValue item;
            item.kind = JsonValue::Kind::Object;
            JsonValue size;
            size.kind = JsonValue::Kind::Number;
            size.number = static_cast<double>(entry.size);
            JsonValue modified;
            modified.kind = JsonValue::Kind::String;
            modified.string = entry.modified;
            JsonValue length;
            length.kind = JsonValue::Kind::Number;
            length.number = entry.length;
            item.object.emplace_back("size", size);
            item.object.emplace_back("modified", modified);
            item.object.emplace_back("length", length);
            files.object.emplace_back(key, item);
        }
        JsonValue root;
        root.kind = JsonValue::Kind::Object;
        root.object.emplace_back("files", files);
        std::ofstream out(m_file, std::ios::binary | std::ios::trunc);
        if (out)
        {
            out << WriteJson(root);
            m_dirty = false;
        }
    }

    int Hits() const { return m_hits; }

private:
    struct Entry
    {
        uint64_t size = 0;
        std::string modified;
        float length = 0.0f;
    };

    std::filesystem::path m_file;
    std::map<std::string, Entry> m_entries;
    std::set<std::string> m_seen;
    bool m_dirty = false;
    int m_hits = 0;
};
}  // namespace radioxl
