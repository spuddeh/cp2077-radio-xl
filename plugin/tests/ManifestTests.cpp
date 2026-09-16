// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Tests for the JSON reader and the manifest checks - every fault names its line.
// File Version: 0.2.0
// ======================================================================================
//
// Built as RadioXLManifestTests by the plugin's CMake and run by ctest. Exit code is the failure count.

#include "../src/Manifest.hpp"

#include <cstdio>
#include <string>
#include <vector>

namespace
{
int g_failures = 0;

void Check(bool aCondition, const char* aWhat, const std::string& aDetail = {})
{
    if (!aCondition)
    {
        ++g_failures;
        std::printf("FAIL  %s%s%s\n", aWhat, aDetail.empty() ? "" : " - ", aDetail.c_str());
    }
}

// The manifest read, and every line logged, for one text.
struct Read
{
    bool ok = false;
    radioxl::Station station;
    std::vector<std::string> log;

    explicit Read(const std::string& aText)
    {
        ok = radioxl::ReadManifest(aText, "Mod/station.json", station, [this](const std::string& aLine) { log.push_back(aLine); });
    }

    bool Logged(const std::string& aPrefix) const
    {
        for (const auto& line : log)
        {
            if (line.rfind(aPrefix, 0) == 0)
            {
                return true;
            }
        }
        return false;
    }

    std::string Joined() const
    {
        std::string out;
        for (const auto& line : log)
        {
            out += "\n    " + line;
        }
        return out;
    }
};

// Expects the read to fail and the first logged line to start with aPrefix.
void ExpectFault(const char* aName, const std::string& aText, const std::string& aPrefix)
{
    const Read r(aText);
    Check(!r.ok, aName, "expected the manifest to be refused");
    Check(!r.log.empty() && r.log.front().rfind(aPrefix, 0) == 0, aName,
          "expected first log line to start with '" + aPrefix + "', got" + r.Joined());
}

const char* kGood = R"json({
  "name": "radio_station_20_tool",
  "frequency": 104.9, "displayName": "Tool FM",
  "icon": "tool_fm",
  "atlas": "toolfm\\gui\\tool_fm.inkatlas",
  "news": true,
  "tracks": [
    {
      "file": "audio/Tool - Vicarious.mp3",
      "title": "Tool - Vicarious"
    },
    { "file": "audio/Tool - 10.000 Days (Wings Pt 2).mp3", "title": "Tool - 10,000 Days (Wings Pt. 2)" }
  ]
})json";

void TestGood()
{
    const Read r(kGood);
    Check(r.ok, "good manifest reads", r.Joined());
    Check(r.log.empty(), "good manifest logs nothing", r.Joined());
    Check(r.station.name == "radio_station_20_tool", "name");
    Check(r.station.frequency == 104.9f, "frequency");
    Check(r.station.displayName == "Tool FM", "displayName is the name alone", r.station.displayName);
    Check(radioxl::Label(r.station) == "104.9 Tool FM", "label", radioxl::Label(r.station));
    Check(r.station.icon == "tool_fm", "icon");
    Check(r.station.atlas == "toolfm\\gui\\tool_fm.inkatlas", "atlas keeps its backslashes", r.station.atlas);
    Check(r.station.news, "news");
    Check(r.station.gain == radioxl::kDefaultGain, "gain defaults");
    Check(r.station.tracks.size() == 2, "two tracks");
    Check(r.station.tracks[1].title == "Tool - 10,000 Days (Wings Pt. 2)", "second title");
}

void TestFrequency()
{
    auto swapped = [](const std::string& aFrom, const std::string& aTo)
    {
        std::string text = kGood;
        return text.replace(text.find(aFrom), aFrom.size(), aTo);
    };
    auto refused = [&](const char* aName, const std::string& aText, const char* aFragment)
    {
        const Read r(aText);
        Check(!r.ok, aName, "expected the manifest to be refused");
        Check(r.Joined().find(aFragment) != std::string::npos, aName,
              std::string("expected a line with '") + aFragment + "', got" + r.Joined());
    };

    // The number belongs in its field. A name that carries one, at either end or inside, is refused,
    // and so is a manifest with no frequency or no name at all.
    refused("the frequency at the front of the name, no field", swapped("\"frequency\": 104.9, \"displayName\": \"Tool FM\"", "\"displayName\": \"104.9 Tool FM\""),
            "\"frequency\" is missing");
    refused("the frequency at the front of the name, field set", swapped("\"Tool FM\"", "\"101.1 Tool FM\""),
            "\"displayName\" starts with a number");
    refused("a number at the end of the name", swapped("\"Tool FM\"", "\"Tool FM 104.9\""), "\"displayName\" ends with a number");
    refused("the frequency inside the name", swapped("\"Tool FM\"", "\"Tool 104.9 FM\""), "\"displayName\" contains the frequency");
    refused("a name with untidy spaces", swapped("\"Tool FM\"", "\" Tool  FM\""), "\"displayName\" is empty, or has a space");
    refused("an empty name", swapped("\"Tool FM\"", "\"\""), "\"displayName\" is empty");
    refused("no name at all", swapped(", \"displayName\": \"Tool FM\"", ""), "\"displayName\" is missing");
    refused("no frequency at all", swapped("\"frequency\": 104.9, ", ""), "\"frequency\" is missing");

    // A band's number is a name, not a frequency.
    const Read band(swapped("\"Tool FM\"", "\"30H!3 Radio\""));
    Check(band.ok, "a name starting with a band's number reads", band.Joined());
    const Read doors(swapped("\"Tool FM\"", "\"3 Doors Down FM\""));
    Check(doors.ok, "a name starting with a small number reads", doors.Joined());

    ExpectFault("frequency as a string", "{\n  \"name\": \"x\",\n  \"frequency\": \"104.9\", \"displayName\": \"X\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}",
                "Mod/station.json:3: \"frequency\" must be a number, not a string");
    ExpectFault("frequency below the band", "{\n  \"name\": \"x\",\n  \"frequency\": 0, \"displayName\": \"X\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}",
                "Mod/station.json:3: \"frequency\" must be a number from 10 to 999");

    Check(radioxl::FrequencyText(104.9) == "104.9" && radioxl::FrequencyText(101.0) == "101.0" &&
              radioxl::FrequencyText(88.85) == "88.85" && radioxl::FrequencyText(90.0) == "90.0",
          "frequency text keeps one decimal, two when written");
}

void TestShuffleIsNotAField()
{
    // The engine draws songs at random, so a manifest has no shuffle field: the key is reported like
    // any other unknown key and does not refuse the station.
    const std::string text = std::string(kGood).replace(std::string(kGood).find("\"news\""), 0, "\"shuffle\": true,\n  ");
    const Read r(text);
    Check(r.ok, "a manifest with shuffle still reads", r.Joined());
    Check(r.Logged("Mod/station.json:6: unknown manifest key \"shuffle\" - ignored"), "shuffle named as unknown", r.Joined());
}

void TestTolerated()
{
    // CRLF, a byte-order mark, a forward-slash atlas, a gain, and \u escapes with a surrogate pair.
    const std::string text = "\xEF\xBB\xBF{\r\n"
                             "  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\r\n"
                             "  \"atlas\": \"mod/gui/a.inkatlas\", \"icon\": \"p\",\r\n"
                             "  \"gain\": 0.5,\r\n"
                             "  \"tracks\": [ { \"file\": \"a.mp3\", \"title\": \"caf\\u00e9 \\ud83c\\udfb5 \\\"quoted\\\" }]{\" } ]\r\n"
                             "}\r\n";
    const Read r(text);
    Check(r.ok, "BOM and CRLF read", r.Joined());
    Check(r.station.atlas == "mod\\gui\\a.inkatlas", "atlas forward slashes become backslashes", r.station.atlas);
    Check(r.station.gain == 0.5f, "gain read");
    Check(r.station.tracks.size() == 1 && r.station.tracks[0].title == "caf\xC3\xA9 \xF0\x9F\x8E\xB5 \"quoted\" }]{",
          "escapes and brackets inside a title", r.station.tracks.empty() ? "" : r.station.tracks[0].title);
}

void TestTitleThatFooledTheScanner()
{
    // A title carrying the word "file" in quotes, and a track object whose "name" precedes the
    // station's own: the two shapes the substring scanner read wrongly.
    const std::string text = R"json({
  "tracks": [ { "title": "the \"file\" song", "file": "a.mp3" } ],
  "name": "x", "frequency": 90.5, "displayName": "Station X"
})json";
    const Read r(text);
    Check(r.ok, "title containing the word file", r.Joined());
    Check(r.station.tracks.size() == 1 && r.station.tracks[0].file == "a.mp3", "file read past the decoy title");
    Check(r.station.name == "x", "station name found after the tracks array");
}

void TestIconRecord()
{
    const Read r(R"json({
  "name": "x", "frequency": 90.5, "displayName": "Station X",
  "icon": "UIIcon.RadioHipHop",
  "tracks": [ { "file": "a" } ]
})json");
    Check(r.ok, "an icon record needs no atlas", r.Joined());
    Check(r.station.icon == "UIIcon.RadioHipHop", "icon record kept as written", r.station.icon);
    Check(r.station.atlas.empty(), "no atlas");
    const Read both(R"json({
  "name": "x", "frequency": 90.5, "displayName": "Station X",
  "icon": "UIIcon.RadioHipHop",
  "atlas": "m/a.inkatlas",
  "tracks": [ { "file": "a" } ]
})json");
    Check(both.ok, "an icon record with an atlas still reads", both.Joined());
    Check(both.station.atlas.empty(), "the atlas beside a record is dropped", both.station.atlas);
    Check(both.Logged("Mod/station.json:4: \"icon\" names a UIIcon record, which carries its own atlas - \"atlas\" ignored"),
          "the ignored atlas is named", both.Joined());
    ExpectFault("bare UIIcon prefix is a part name", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"icon\": \"UIIcon.\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}",
                "Mod/station.json:3: \"icon\" names an atlas part");
}

void TestStream()
{
    const Read r(R"json({
  "name": "x", "frequency": 90.5, "displayName": "Station X",
  "tracks": [ { "url": "HTTPS://ice1.somafm.com/groovesalad-128-mp3", "title": "Groove Salad" } ]
})json");
    Check(r.ok, "a url track reads", r.Joined());
    Check(r.station.tracks.size() == 1 && r.station.tracks[0].url == "HTTPS://ice1.somafm.com/groovesalad-128-mp3",
          "url kept as written");
    Check(r.station.tracks[0].file.empty(), "a url track has no file");
    Check(r.station.tracks[0].duration == radioxl::kStreamDuration, "a url track takes the stream duration");
    ExpectFault("url and file together", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"file\": \"a\", \"url\": \"http://h/s\" }\n  ]\n}",
                "Mod/station.json:4: a track has \"file\" or \"url\", not both");
    ExpectFault("url not http", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"url\": \"ftp://h/s\" }\n  ]\n}",
                "Mod/station.json:4: \"url\" must start with http:// or https://");
    ExpectFault("url beside other tracks", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"url\": \"http://h/s\" },\n    { \"file\": \"a\" }\n  ]\n}",
                "Mod/station.json:3: a station with a \"url\" track plays that stream only");
}

void TestIdent()
{
    const Read r(R"json({
  "name": "x", "frequency": 90.5, "displayName": "Station X",
  "tracks": [ { "file": "a.mp3", "title": "A" }, { "file": "id.mp3", "ident": true } ]
})json");
    Check(r.ok, "an ident track reads", r.Joined());
    Check(r.station.tracks.size() == 2 && !r.station.tracks[0].ident && r.station.tracks[1].ident, "ident flag read per track");
    ExpectFault("every track an ident", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"file\": \"a\", \"ident\": true }\n  ]\n}",
                "Mod/station.json:3: every track is an ident");
    ExpectFault("a url ident", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"url\": \"http://h/s\", \"ident\": true }\n  ]\n}",
                "Mod/station.json:4: an ident is a file");
    ExpectFault("ident as a string", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"file\": \"a\", \"ident\": \"yes\" }\n  ]\n}",
                "Mod/station.json:4: \"ident\" must be");
}

void TestSyntaxFaults()
{
    ExpectFault("trailing comma in object", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [],\n}", "Mod/station.json:4:1: a trailing comma before '}'");
    ExpectFault("trailing comma in array", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [ { \"file\": \"a\" }, ]\n}", "Mod/station.json:3:32: a trailing comma before ']'");
    ExpectFault("missing comma", "{\n  \"name\": \"x\"\n  \"tracks\": []\n}", "Mod/station.json:3:3: expected ',' or '}' after a value");
    ExpectFault("unterminated string", "{\n  \"name\": \"x,\n  \"tracks\": []\n}", "Mod/station.json:2:14: a string runs past the end of its line");
    ExpectFault("single quotes", "{\n  'name': 'x'\n}", "Mod/station.json:2:3: expected a quoted key, found a single quote");
    ExpectFault("comment", "{\n  // the name\n  \"name\": \"x\"\n}", "Mod/station.json:2:3: expected a quoted key, found '/' (a comment is not JSON)");
    ExpectFault("bad escape", "{\n  \"atlas\": \"mod\\gui\\a.inkatlas\"\n}", "Mod/station.json:2:16: unknown escape \\g");
    ExpectFault("duplicate key", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [],\n  \"name\": \"y\"\n}", "Mod/station.json:4:3: duplicate key \"name\" (first at line 2)");
    ExpectFault("empty file", "", "Mod/station.json:1:1: the file is empty");
    ExpectFault("text after root", "{ \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\", \"tracks\": [] }\n}", "Mod/station.json:2:1: text after the closing bracket");
    ExpectFault("file ends inside object", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n", "Mod/station.json:4:1: the file ends inside an object, '}' missing");
    ExpectFault("root is an array", "[ 1 ]", "Mod/station.json:1: the manifest must be an object");
    ExpectFault("leading zero", "{ \"gain\": 01 }", "Mod/station.json:1:12: a number may not start with 0");
}

void TestSchemaFaults()
{
    ExpectFault("name missing", "{\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:1: \"name\" is missing");
    ExpectFault("name not a string", "{\n  \"name\": 5,\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:2: \"name\" must be a string, not a number");
    ExpectFault("name with a space", "{\n  \"name\": \"my station\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:2: \"name\" must be letters, digits and underscores only");
    ExpectFault("tracks missing", "{\n  \"name\": \"x\"\n}", "Mod/station.json:1: \"tracks\" is missing");
    ExpectFault("tracks empty", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": []\n}", "Mod/station.json:3: \"tracks\" is empty");
    ExpectFault("tracks not an array", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": { \"file\": \"a\" }\n}", "Mod/station.json:3: \"tracks\" must be an array [...], not an object {...}");
    ExpectFault("track not an object", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [ \"a.mp3\" ]\n}", "Mod/station.json:3: each track must be an object");
    ExpectFault("track without file", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"title\": \"t\" }\n  ]\n}", "Mod/station.json:4: \"file\" is missing");
    ExpectFault("track file empty", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"tracks\": [\n    { \"file\": \"\" }\n  ]\n}", "Mod/station.json:4: \"file\" is empty");
    ExpectFault("news as a string", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"news\": \"yes\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"news\" must be true/false, not a string");
    ExpectFault("gain as a string", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"gain\": \"0.5\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"gain\" must be a number, not a string");
    ExpectFault("icon without atlas", "{\n  \"name\": \"x\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"icon\": \"p\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"icon\" names an atlas part");
}

void TestWarnings()
{
    const std::string text = R"json({
  "name": "x", "frequency": 90.5, "displayName": "Station X",
  "subtitle": "typo",
  "gain": 1.5,
  "atlas": "m\\a.inkatlas",
  "tracks": [ { "file": "a", "titel": "typo" } ],
  "speaker": "Stanley"
})json";
    const Read r(text);
    Check(r.ok, "warnings do not refuse the manifest", r.Joined());
    Check(r.Logged("Mod/station.json:3: unknown manifest key \"subtitle\" - ignored"), "unknown top-level key named", r.Joined());
    Check(r.Logged("Mod/station.json:4: \"gain\" is 0 to 1 - clamped"), "gain out of range named", r.Joined());
    Check(r.station.gain == 1.0f, "gain clamped");
    Check(r.Logged("Mod/station.json:5: \"atlas\" without \"icon\" does nothing - ignored"), "atlas without icon named", r.Joined());
    Check(r.Logged("Mod/station.json:6: unknown track key \"titel\" - ignored"), "unknown track key named", r.Joined());
    Check(r.Logged("Mod/station.json:7: unknown manifest key \"speaker\" - ignored"), "speaker named as unknown", r.Joined());
    Check(!r.station.news, "an unknown key does not set news");
    Check(r.log.size() == 5, "exactly five warnings", r.Joined());
}

void TestEveryFaultIsReported()
{
    // Two faults on two lines: both are named, so the author fixes the file once.
    const Read r("{\n  \"name\": \"bad name\", \"frequency\": 90.5, \"displayName\": \"Station X\",\n  \"news\": \"DJ\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}");
    Check(!r.ok, "two faults refuse");
    Check(r.log.size() == 2, "both faults logged", r.Joined());
    Check(r.Logged("Mod/station.json:2:"), "first at line 2", r.Joined());
    Check(r.Logged("Mod/station.json:3:"), "second at line 3", r.Joined());
}
} // namespace

int main()
{
    TestGood();
    TestFrequency();
    TestShuffleIsNotAField();
    TestTolerated();
    TestTitleThatFooledTheScanner();
    TestIconRecord();
    TestStream();
    TestIdent();
    TestSyntaxFaults();
    TestSchemaFaults();
    TestWarnings();
    TestEveryFaultIsReported();
    if (g_failures == 0)
    {
        std::printf("ok\n");
    }
    return g_failures;
}
