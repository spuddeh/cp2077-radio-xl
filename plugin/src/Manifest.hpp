// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A station manifest read whole, then checked field by field, every fault by line.
// File Version: 0.2.0
// ======================================================================================
//
// A manifest with a fault is skipped whole rather than half-loaded: a station that loads with one
// field missing looks like a bug somewhere else, and the log line saying which line of which file
// is the whole of what a station author needs.

#pragma once

#include "Json.hpp"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace radioxl
{
// A track is an audio FILE and a title. Nothing else is written by hand: the length is read from
// the file's own headers at load, and AudioXL registers the file and supplies the Wwise id. A
// manifest that carried a duration would be a second place for it to be wrong.
//
// A track can instead be a URL, a live MP3 stream AudioXL plays from the network. A stream has no
// length, so a station with one plays that stream and nothing else.
struct Track
{
    std::string file;       // relative to the station's own manifest folder
    std::string url;        // an http or https stream, in place of file
    std::string title;      // the song title as it is shown, plain text, may be empty
    float duration = 0.0f;  // seconds, from the file's headers - what the station schedules against
    bool ident = false;     // a station ident: written to the station's blips, not its tracks
};

// The level trim every station gets unless its manifest says otherwise. **A station's level belongs
// on its send, not in its samples**, and the framework's own routing bank puts it there, so the
// default here leaves the audio alone. The correction for the game's own custom-radio object, whose
// send reaches a world device 3 to 7 dB hotter than any vanilla station, is applied in script and
// only on the path that uses that object.
constexpr float kDefaultGain = 1.0f;

struct Station
{
    std::string name;          // the station CName, e.g. radio_station_20_tool
    float frequency = -1.0f;   // the station's place on the dial, e.g. 104.9; always set once a manifest is accepted
    std::string displayName;   // the station's name alone, plain text; the label shown is Label()
    std::string icon;          // an inkatlas part name, a UIIcon record name, or empty for the framework's glyph
    std::string atlas;         // the inkatlas resource holding that part, or empty for the framework's
    bool news = false;         // Stanley's news and greetings may reach the station
    float gain = kDefaultGain; // level trim applied to every track's samples, 0..1; see RadioXL_StationGain
    std::vector<Track> tracks;
    std::string source;        // which manifest it came from, for logging
    std::string folder;        // the manifest's own directory, which track files are relative to
};

// A frequency as the dial shows it: one decimal, two when the number has them (104.9, 101.0, 88.85).
inline std::string FrequencyText(double aFrequency)
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%.2f", aFrequency);
    std::string text = buf;
    if (text.size() > 1 && text.back() == '0' && text[text.size() - 2] != '.')
    {
        text.pop_back();
    }
    return text;
}

// The label every receiver shows: the frequency, then the name, the CName standing in for a
// station that gave no name.
inline std::string Label(const Station& aStation)
{
    const std::string& name = aStation.displayName.empty() ? aStation.name : aStation.displayName;
    return aStation.frequency >= 0.0f ? FrequencyText(aStation.frequency) + " " + name : name;
}

// A number at the front of a display name, as written for 0.3.0 manifests, and the name after it.
// False when the text does not start with one.
inline bool LeadingFrequency(const std::string& aText, double& aFrequency, std::string& aRest)
{
    const char* text = aText.c_str();
    char* end = nullptr;
    const double v = std::strtod(text, &end);
    if (!end || end == text || v < 10.0 || (*end != '\0' && *end != ' '))
    {
        return false;
    }
    aFrequency = v;
    aRest = end;
    while (!aRest.empty() && aRest.front() == ' ')
    {
        aRest.erase(aRest.begin());
    }
    return true;
}

// A depot path uses backslashes. A manifest may write either.
inline std::string DepotPath(std::string aPath)
{
    for (auto& c : aPath)
    {
        if (c == '/')
        {
            c = '\\';
        }
    }
    return aPath;
}

// The schedule length every stream track is given. A live stream has no end to schedule against;
// when AudioXL ends the voice (the station stopped sending) the engine posts the same slot again,
// which reconnects.
constexpr float kStreamDuration = 3600.0f;

inline bool IsStreamUrl(std::string_view aUrl)
{
    auto starts = [&](std::string_view aPrefix)
    {
        if (aUrl.size() <= aPrefix.size())
        {
            return false;
        }
        for (size_t i = 0; i < aPrefix.size(); ++i)
        {
            const char c = aUrl[i];
            if ((c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c) != aPrefix[i])
            {
                return false;
            }
        }
        return true;
    };
    return starts("http://") || starts("https://");
}

// A TweakDB UIIcon record by name, `UIIcon.RadioHipHop`, rather than a part in an atlas.
inline bool IsIconRecord(std::string_view aIcon)
{
    constexpr std::string_view kPrefix = "UIIcon.";
    return aIcon.size() > kPrefix.size() && aIcon.substr(0, kPrefix.size()) == kPrefix;
}

// A station name becomes a CName, an event-name prefix and a TweakDB record id, and the last of
// those splits on '.', so the name is held to what every one of them accepts.
inline bool IsStationName(std::string_view aName)
{
    if (aName.empty())
    {
        return false;
    }
    for (const char c : aName)
    {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
        if (!ok)
        {
            return false;
        }
    }
    return true;
}

using ManifestLog = std::function<void(const std::string&)>;

// Reads aText as the manifest at aWhere ("<Mod>/station.json") into aOut. Every line written to
// aLog is `<where>:<line>: <what>`. Returns false when the station must not be registered; a
// warning is logged the same way and does not fail the manifest.
inline bool ReadManifest(std::string_view aText, const std::string& aWhere, Station& aOut, const ManifestLog& aLog)
{
    JsonValue root;
    JsonError error;
    if (!ParseJson(aText, root, error))
    {
        aLog(aWhere + ":" + std::to_string(error.line) + ":" + std::to_string(error.column) + ": " + error.what);
        return false;
    }

    bool ok = true;
    auto at = [&](int aLine, const std::string& aWhat) { aLog(aWhere + ":" + std::to_string(aLine) + ": " + aWhat); };
    auto fail = [&](int aLine, const std::string& aWhat)
    {
        at(aLine, aWhat);
        ok = false;
    };

    if (!root.Is(JsonValue::Kind::Object))
    {
        fail(root.line, "the manifest must be an object, { ... }");
        return false;
    }

    // A member that is present must be the kind the field wants; absent is fine for an optional one.
    auto expect = [&](const JsonValue& aObject, std::string_view aKey, JsonValue::Kind aKind, bool aRequired) -> const JsonValue*
    {
        const JsonValue* value = aObject.Find(aKey);
        if (!value)
        {
            if (aRequired)
            {
                fail(aObject.line, "\"" + std::string(aKey) + "\" is missing");
            }
            return nullptr;
        }
        if (!value->Is(aKind))
        {
            fail(value->line, "\"" + std::string(aKey) + "\" must be " + JsonValue::KindName(aKind) + ", not " +
                                  JsonValue::KindName(value->kind));
            return nullptr;
        }
        return value;
    };

    auto unknownKeys = [&](const JsonValue& aObject, std::initializer_list<std::string_view> aKnown, const char* aWhat)
    {
        for (const auto& [key, value] : aObject.object)
        {
            if (std::find(aKnown.begin(), aKnown.end(), key) == aKnown.end())
            {
                at(value.line, std::string("unknown ") + aWhat + " key \"" + key + "\" - ignored");
            }
        }
    };

    unknownKeys(root, {"name", "frequency", "displayName", "icon", "atlas", "news", "gain", "tracks"}, "manifest");

    if (const JsonValue* name = expect(root, "name", JsonValue::Kind::String, true))
    {
        if (!IsStationName(name->string))
        {
            fail(name->line, "\"name\" must be letters, digits and underscores only: \"" + name->string + "\"");
        }
        aOut.name = name->string;
    }

    const JsonValue* displayName = expect(root, "displayName", JsonValue::Kind::String, false);
    if (displayName)
    {
        aOut.displayName = displayName->string;
    }

    const JsonValue* icon = expect(root, "icon", JsonValue::Kind::String, false);
    const JsonValue* atlas = expect(root, "atlas", JsonValue::Kind::String, false);
    // An `icon` is either an existing UIIcon record, used as it is, or a part name in `atlas`.
    const bool iconIsRecord = icon && IsIconRecord(icon->string);
    if (iconIsRecord && atlas && !atlas->string.empty())
    {
        at(atlas->line, "\"icon\" names a UIIcon record, which carries its own atlas - \"atlas\" ignored");
        atlas = nullptr;
    }
    if (icon && !iconIsRecord && !icon->string.empty() && (!atlas || atlas->string.empty()))
    {
        fail(icon->line, "\"icon\" names an atlas part, so \"atlas\" must name the inkatlas holding it "
                         "(or name a record, \"UIIcon.RadioHipHop\")");
    }
    if (atlas && !atlas->string.empty() && (!icon || icon->string.empty()))
    {
        at(atlas->line, "\"atlas\" without \"icon\" does nothing - ignored");
    }
    if (icon)
    {
        aOut.icon = icon->string;
    }
    if (atlas)
    {
        aOut.atlas = DepotPath(atlas->string);
    }

    // `news: true` makes the station a Stanley station. The other DJs' lines name their own station,
    // so no other speaker is offered.
    if (const JsonValue* news = expect(root, "news", JsonValue::Kind::Bool, false))
    {
        aOut.news = news->boolean;
    }
    if (const JsonValue* gain = expect(root, "gain", JsonValue::Kind::Number, false))
    {
        if (gain->number < 0.0 || gain->number > 1.0)
        {
            at(gain->line, "\"gain\" is 0 to 1 - clamped");
        }
        aOut.gain = std::clamp(static_cast<float>(gain->number), 0.0f, 1.0f);
    }

    if (const JsonValue* tracks = expect(root, "tracks", JsonValue::Kind::Array, true))
    {
        if (tracks->array.empty())
        {
            fail(tracks->line, "\"tracks\" is empty - a station needs at least one");
        }
        for (const JsonValue& item : tracks->array)
        {
            if (!item.Is(JsonValue::Kind::Object))
            {
                fail(item.line, "each track must be an object, { \"file\": ... }, not " + std::string(JsonValue::KindName(item.kind)));
                continue;
            }
            unknownKeys(item, {"file", "url", "title", "ident"}, "track");
            Track track;
            const bool hasUrl = item.Find("url") != nullptr;
            if (hasUrl && item.Find("file"))
            {
                fail(item.line, "a track has \"file\" or \"url\", not both");
            }
            if (hasUrl)
            {
                if (const JsonValue* url = expect(item, "url", JsonValue::Kind::String, true))
                {
                    if (!IsStreamUrl(url->string))
                    {
                        fail(url->line, "\"url\" must start with http:// or https://: \"" + url->string + "\"");
                    }
                    track.url = url->string;
                    track.duration = kStreamDuration;
                }
            }
            else if (const JsonValue* file = expect(item, "file", JsonValue::Kind::String, true))
            {
                if (file->string.empty())
                {
                    fail(file->line, "\"file\" is empty");
                }
                track.file = file->string;
            }
            if (const JsonValue* title = expect(item, "title", JsonValue::Kind::String, false))
            {
                track.title = title->string;
            }
            if (const JsonValue* ident = expect(item, "ident", JsonValue::Kind::Bool, false))
            {
                track.ident = ident->boolean;
                if (track.ident && hasUrl)
                {
                    fail(ident->line, "an ident is a file - a \"url\" track cannot be one");
                }
            }
            aOut.tracks.push_back(std::move(track));
        }
        const bool streams = std::any_of(aOut.tracks.begin(), aOut.tracks.end(), [](const Track& t) { return !t.url.empty(); });
        if (streams && aOut.tracks.size() > 1)
        {
            fail(tracks->line, "a station with a \"url\" track plays that stream only - it must be the one track");
        }
        const bool songs = std::any_of(aOut.tracks.begin(), aOut.tracks.end(), [](const Track& t) { return !t.ident; });
        if (!aOut.tracks.empty() && !songs)
        {
            fail(tracks->line, "every track is an ident - a station needs at least one song");
        }
    }

    // The frequency decides the dial position, so a station must have one. A 0.3.0 manifest wrote
    // it at the front of the display name; that still loads, with a line asking for the field.
    {
        const JsonValue* frequency = expect(root, "frequency", JsonValue::Kind::Number, false);
        if (frequency)
        {
            if (frequency->number <= 0.0 || frequency->number >= 1000.0)
            {
                fail(frequency->line, "\"frequency\" must be a number above 0, e.g. 104.9");
            }
            else
            {
                aOut.frequency = static_cast<float>(frequency->number);
            }
        }
        double leading = 0.0;
        std::string rest;
        if (displayName && LeadingFrequency(displayName->string, leading, rest))
        {
            if (!frequency)
            {
                aOut.frequency = static_cast<float>(leading);
                at(displayName->line, "\"frequency\" is missing - read " + FrequencyText(leading) +
                                          " from the front of \"displayName\"; write it as its own field");
            }
            else
            {
                at(displayName->line, "\"displayName\" starts with a number and \"frequency\" is set - the field "
                                      "places the station, and the label shows the name without the number");
            }
            aOut.displayName = rest;
        }
        else if (!frequency)
        {
            fail(root.line, "\"frequency\" is missing - the number that places the station on the dial, e.g. 104.9");
        }
    }

    return ok;
}
} // namespace radioxl
