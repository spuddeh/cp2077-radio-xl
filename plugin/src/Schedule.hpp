// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A station's own remaining-tracks list, read for the song keys and consumed by them.
// File Version: 0.3.0
// Credits: RED4ext by WopsS.
// ======================================================================================
//
// **The engine draws each station's songs from a remaining list and refills it only when it is
// empty, and a song requested through `RequestSongOnRadioStation` never leaves that list.** So a
// song key that requests a song by itself leaves the station to play it again later in the same
// cycle, and the ident that follows every third pick never hears of the key. These two natives let
// the deck draw from the station's list and take what it plays out of it, the way the picker does:
// the entry is erased and the pick counter goes up by one.
//
// Only the deck calls these. Nothing here hooks the request path, so the game's own quest requests
// are untouched.
//
// The walk reads engine memory by offset, so it is wrapped in SEH like the clock: a bad read hands
// the deck an empty list and a false, and the deck falls back to its own bag.

#pragma once

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <cstdint>
#include <cstring>
#include <string>

#include "Clock.hpp"

namespace radioxl::schedule
{

// A station object's schedule, as the 2.31 picker (0x6bcdfc) reads and writes it.
constexpr size_t kStationMetadata = 0x110;        // the station's audioRadioStationMetadata
constexpr size_t kStationRemaining = 0x160;       // DynArray of track indices: entries, size at +0xc
constexpr size_t kStationRemainingCount = 0x16c;
constexpr size_t kStationPicks = 0x170;           // byte: picks since the last blip
constexpr size_t kDynArraySize = 0xc;             // a DynArray is { entries, capacity, size }

// One entry of the remaining list. The picker refills the list with 0..n-1 and rolls an index
// into it, so an entry is an index into the metadata's tracks. Its width is confirmed by the
// probe's `remain` line.
using Entry = uint32_t;

constexpr uint32_t kMaxTracks = 256;

// audioRadioStationMetadata.tracks, from RTTI on first use. Zero until then.
inline size_t g_tracksOffset = 0;
inline bool g_failed = false;

inline size_t TracksOffset()
{
    if (!g_tracksOffset)
    {
        if (auto* cls = RED4ext::CRTTISystem::Get()->GetClass("audioRadioStationMetadata"))
        {
            if (auto* p = cls->GetProperty(RED4ext::CName("tracks")))
            {
                g_tracksOffset = p->valueOffset;
            }
        }
    }
    return g_tracksOffset;
}

// The station object by name, in any state, or 0. Plain data only: SEH guards the callers.
inline uintptr_t FindStation(uint64_t aNameHash)
{
    const auto rootSlot = clock::ResolveByHash(clock::kHashEngineRoot);
    if (!rootSlot)
    {
        return 0;
    }
    const auto root = clock::Read<uintptr_t>(rootSlot);
    const auto audio = root ? clock::Read<uintptr_t>(root + clock::kRootAudioSystem) : 0;
    const auto manager = audio ? clock::Read<uintptr_t>(audio + clock::kAudioRadioManager) : 0;
    if (!manager)
    {
        return 0;
    }
    const auto stations = clock::Read<uintptr_t>(manager + clock::kManagerStations);
    const auto count = clock::Read<uint32_t>(manager + clock::kManagerCount);
    if (!stations || count > 256)
    {
        return 0;
    }
    for (uint32_t i = 0; i < count; ++i)
    {
        const auto station = clock::Read<uintptr_t>(stations + i * 8);
        if (!station)
        {
            continue;
        }
        const auto vtbl = clock::Read<uintptr_t>(station);
        const auto getName = clock::Read<clock::GetNameFn>(vtbl + clock::kVtblGetName);
        uint64_t name = 0;
        getName(reinterpret_cast<void*>(station), &name);
        if (name == aNameHash)
        {
            return station;
        }
    }
    return 0;
}

// The names of the tracks still in a station's remaining list, in list order. Returns the number
// written, or -1 when the station is not in the manager. An entry past the track list is skipped:
// it would mean the layout is not this build's, and the list is then better left alone.
inline int ReadRemaining(uint64_t aStation, size_t aTracksOffset, uint64_t* aNames, uint32_t aMax)
{
    const auto station = FindStation(aStation);
    if (!station || !aTracksOffset)
    {
        return -1;
    }
    const auto metadata = clock::Read<uintptr_t>(station + kStationMetadata);
    if (!metadata)
    {
        return -1;
    }
    const auto tracks = clock::Read<uintptr_t>(metadata + aTracksOffset);
    const auto trackCount = clock::Read<uint32_t>(metadata + aTracksOffset + kDynArraySize);
    const auto entries = clock::Read<uintptr_t>(station + kStationRemaining);
    const auto count = clock::Read<uint32_t>(station + kStationRemainingCount);
    if (!tracks || !entries || trackCount > kMaxTracks || count > kMaxTracks)
    {
        return count == 0 ? 0 : -1;
    }
    int n = 0;
    for (uint32_t i = 0; i < count && static_cast<uint32_t>(n) < aMax; ++i)
    {
        const auto index = clock::Read<Entry>(entries + i * sizeof(Entry));
        if (index < trackCount)
        {
            aNames[n++] = clock::Read<uint64_t>(tracks + static_cast<size_t>(index) * 8);
        }
    }
    return n;
}

// Takes a track out of a station's remaining list, the way the picker does when it draws it, and
// when `aCount` is set adds one to the pick counter, the way the picker does on every pick.
// Returns -1 when the station is not in the manager or names no such track, 1 when the entry
// was erased, 0 when the track was not in the list (the counter still moves when asked).
inline int Consume(uint64_t aStation, uint64_t aTrack, bool aCount, size_t aTracksOffset)
{
    const auto station = FindStation(aStation);
    if (!station || !aTracksOffset)
    {
        return -1;
    }
    const auto metadata = clock::Read<uintptr_t>(station + kStationMetadata);
    if (!metadata)
    {
        return -1;
    }
    const auto tracks = clock::Read<uintptr_t>(metadata + aTracksOffset);
    const auto trackCount = clock::Read<uint32_t>(metadata + aTracksOffset + kDynArraySize);
    if (!tracks || trackCount > kMaxTracks)
    {
        return -1;
    }
    uint32_t index = trackCount;
    for (uint32_t i = 0; i < trackCount; ++i)
    {
        if (clock::Read<uint64_t>(tracks + static_cast<size_t>(i) * 8) == aTrack)
        {
            index = i;
            break;
        }
    }
    if (index == trackCount)
    {
        return -1;
    }
    int erased = 0;
    const auto entries = clock::Read<uintptr_t>(station + kStationRemaining);
    const auto count = clock::Read<uint32_t>(station + kStationRemainingCount);
    if (entries && count <= kMaxTracks)
    {
        for (uint32_t i = 0; i < count; ++i)
        {
            if (clock::Read<Entry>(entries + i * sizeof(Entry)) != static_cast<Entry>(index))
            {
                continue;
            }
            // The tail moves down first and the size drops after, so a picker that reads in
            // between sees a list of valid entries throughout.
            auto* at = reinterpret_cast<Entry*>(entries + i * sizeof(Entry));
            std::memmove(at, at + 1, (count - i - 1) * sizeof(Entry));
            *reinterpret_cast<uint32_t*>(station + kStationRemainingCount) = count - 1;
            erased = 1;
            break;
        }
    }
    if (aCount)
    {
        auto* picks = reinterpret_cast<uint8_t*>(station + kStationPicks);
        if (*picks < 255)
        {
            *picks = static_cast<uint8_t>(*picks + 1);
        }
    }
    return erased;
}

inline bool SafeReadRemaining(uint64_t aStation, size_t aTracksOffset, uint64_t* aNames, uint32_t aMax, int* aOut)
{
    __try
    {
        *aOut = ReadRemaining(aStation, aTracksOffset, aNames, aMax);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

inline bool SafeConsume(uint64_t aStation, uint64_t aTrack, bool aCount, size_t aTracksOffset, int* aOut)
{
    __try
    {
        *aOut = Consume(aStation, aTrack, aCount, aTracksOffset);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

inline void Fail(const char* aWhat)
{
    g_failed = true;
    clock::Log(std::string("a ") + aWhat +
               " of the station schedule faulted - offsets are not this build's. The song keys draw "
               "from their own bag.");
}

} // namespace radioxl::schedule

// --- the natives ---------------------------------------------------------------------------

// The tracks not yet picked this cycle on a station, by event name. Empty when the station is not
// in the manager, when its list is empty, or after a faulted read.
inline void RadioXL_StationRemaining(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame,
                                     RED4ext::DynArray<RED4ext::CName>* aOut, int64_t)
{
    RED4ext::CName station;
    RED4ext::GetParameter(aFrame, &station);
    ++aFrame->code;
    if (!aOut)
    {
        return;
    }
    aOut->Clear();
    if (radioxl::schedule::g_failed)
    {
        return;
    }
    uint64_t names[radioxl::schedule::kMaxTracks] = {};
    int n = 0;
    if (!radioxl::schedule::SafeReadRemaining(station.hash, radioxl::schedule::TracksOffset(), names,
                                              radioxl::schedule::kMaxTracks, &n))
    {
        radioxl::schedule::Fail("read");
        return;
    }
    for (int i = 0; i < n; ++i)
    {
        aOut->PushBack(RED4ext::CName(names[i]));
    }
}

// Takes `track` out of `station`'s remaining list and, when `countPick` is set, counts it as a
// pick toward the next ident. True when the station and the track were found, whether or not the
// track was still in the list; false for an unknown station or track, or a faulted read.
inline void RadioXL_StationConsume(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::CName station;
    RED4ext::CName track;
    bool countPick = true;
    RED4ext::GetParameter(aFrame, &station);
    RED4ext::GetParameter(aFrame, &track);
    RED4ext::GetParameter(aFrame, &countPick);
    ++aFrame->code;
    if (aOut)
    {
        *aOut = false;
    }
    if (radioxl::schedule::g_failed)
    {
        return;
    }
    int result = -1;
    if (!radioxl::schedule::SafeConsume(station.hash, track.hash, countPick, radioxl::schedule::TracksOffset(),
                                        &result))
    {
        radioxl::schedule::Fail("write");
        return;
    }
    if (aOut)
    {
        *aOut = result >= 0;
    }
}
