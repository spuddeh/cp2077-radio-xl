# The compiled station roster

The fifteen dial stations are not data. They are two 15-slot `CName` arrays in BSS. Startup
initialisers fill them, a handful of functions read them with the count as an 8-bit immediate, and
three places reduce the index modulo fifteen. A station past the vanilla ones needs every one of
those extended, and nothing else. After that the engine builds the station like any other.

Addresses below are RVAs on the Steam 2.5 exe. Every function is found by its RED4ext hash, and the
hashes are the same on 2.31 and 2.5.

## The roster holds identity

The function and variable names below are the game's own C++ names.
[cp2077-symbols](https://codeberg.org/bartmoss/cp2077-symbols) recovers them from the hashes CDPR
ships in `cyberpunk2077_addresses.json`. A name tells you where to read, not what the code does.
Every claim here comes from the disassembly.

`[M]` **`audio::c_radioStationNames`, a 15-slot `CName` array at RVA `0x3d2e1f0`, indexed by
`ERadioStationList`.** It is zero on disk. An initialiser at `0x8d960` fills it by calling the
magic-static CName accessor for each station name in turn. `ERadioStationList` has 15 members, 0
to 14. `radio_station_police` and `radio_station_kurtz` are in neither this array nor the enum.
The game reaches them by name only.

It has exactly two readers besides its initialiser. A byte search for the array's RVA as a raw
`disp32` finds no image-base-relative reader.

**Name to index, `0x442e48`** (RED4ext hash `4164035396`),
`audio::RadioStationChannelData::TryGetRadioStationChannel(CName, Broadcast::Channel&)`. It is a
leaf function and is not in `.pdata`:

```c
bool ResolveStation(CName name, int* out)
{
    if (name == special_A) { *out = 0xff; return true; }        // none
    for (int i = 0; i < 15; i++)                                 // cmp eax, 0x0f  <- imm8
        if (name == roster[i]) { *out = i + 8; return true; }    // add eax, 8
    if (name == special_B) { *out = 0x18; return true; }         // 24
    if (name == special_C) { *out = 0x21; return true; }         // 33
    return false;                                                // *out untouched
}
```

`[M]` **Internal station ids are `ERadioStationList` + 8**, so 8 to 22. The two non-dial stations
are 24 (police) and 33 (Kurtz), and none is 255. Custom stations start at enum 26, id 34, one past
Kurtz. The function has ten call sites. On 2.31 all ten test the return value, so a name that misses
here fails safely. This is not the function that kills the radios.

**Index to name, `0x191f7a4`** (hash `2956468185`),
`audio::RadioStationChannelData::GetRadioStationName(Broadcast::Channel)`:

```
lea  eax, [rdx - 8]          ; undo the +8 bias
cmp  eax, 0x0e               ; the bound, 14  <- imm8
ja   <abort>
lea  rdx, [0x3d2e1f0]
mov  rax, [rdx + rax*8]
```

## The name table holds the label

`[M]` **`audio::c_radioStationLocKeys`, a second 15-slot `CName` array at `0x3d2e270`** (hash
`1433472801`), straight after the roster. An initialiser at `0x8d8a0` fills it. On 2.31 it runs
just before the roster's. Each slot is a **localization key**, such as
`Gameplay-Devices-Radio-RadioStationAggroIndie`. It is not text.

It has two readers, and **both reduce the index modulo fifteen before the bounds check**. So an
unpatched slot past the vanilla ones shows a vanilla station's label. Slot 15 wraps to slot 0, Radio
Vexelstrom. The first custom station, slot 26, wraps to slot 11, Growl FM. That was the whole
wrong-label bug, on the dashboard and on the Radioport. It was never a UI problem.

**Reader one, `0x2067950`** (hash `2735481579`), the vehicle dashboard's. It has no recovered name.
Its only caller is `vehicle::VehicleAudioRadioController::GetRadioReceiverLocalizedStationName`:

```
+0x00  44 8B C2            mov  r8d, edx           ; the station index
+0x03  B8 89 88 88 88      mov  eax, 0x88888889    \
       ...                                          > magic-number division by 15
+0x0D  6B C2 0F            imul eax, edx, 0x0f     /
+0x10  44 2B C0            sub  r8d, eax           ; r8d = index % 15
+0x13  41 83 F8 0E         cmp  r8d, 0x0e          ; <- imm8
+0x19  48 8D 15 <disp32>   lea  rdx, [0x3d2e270]
+0x20  4A 8B 04 C2         mov  rax, [rdx + r8*8]
```

**Reader two, `0x2170100`** (hash `131147224`), the Radioport's: `game::funcGetRadioStationLocalizedName`,
the script native `GetRadioStationLocalizedName`. We missed it for a long time, because it reaches
the table as `[r14 + rcx*8 + disp32]` with `r14` holding the image base, not through a `lea`.
It does the same division from `+0x5D`, with one difference:

```
+0x5D  B8 89 88 88 88      mov  eax, 0x88888889
+0x62  48 FF 07            inc  qword [rdi]        ; a live side effect INSIDE the division
+0x65  F7 E1               mul  ecx
       ...
+0x6A  6B C2 0F            imul eax, edx, 0x0f
+0x6D  2B C8               sub  ecx, eax
+0x6F  83 F9 0E            cmp  ecx, 0x0e          ; <- imm8
+0x74  49 8B 9C CE <d32>   mov  rbx, [r14 + rcx*8 + disp32]
```

The `inc` at `+0x62` is not part of the division and has to stay. So this block is erased as two
runs of `nop`, one on each side of it.

**The modulo is removed, not retuned.** The index register already holds the index at the top of
each reader, and `index % 15 == index` for every vanilla index. Erasing the division changes
nothing for the fifteen and stops the wrap for every station past them.

## The vehicle receiver's bound, and its next-station step

`[M]` `0x2b9b0c0` (hash `4148435735`), the vehicle receiver's set-station,
`vehicle::VehicleAudioRadioController::SetRadioReceiverStation(uint, bool)`:

```
+0x5E  83 FF 0F            cmp  edi, 0x0f          ; the requested index against 15  <- imm8
+0x61                      jb   accept
                           mov  edi, [rbx + 0xc]   ; reject: keep the current station
```

A rejection gives no error. On 2.31, `SetRadioReceiverStation(14)` left the receiver on its old
station. Raising the immediate at `+0x60` makes direct selection work: the car changes station and
plays. `SetRadioReceiverStation` takes the `ERadioStationList` value, not the internal id.

`[M]` **The same function's third argument selects the next-station step**, `+0x68` to `+0x8A`:

```
+0x68  8B 4B 0C            mov  ecx, [rbx + 0xc]   ; the current ERadioStationList value
+0x6B  E8 <rel32>          call 0x20679d0          ; enum -> dial position, a switch on 0..14
+0x70  8D 48 01            lea  ecx, [rax + 1]
+0x73  B8 89 88 88 88      mov  eax, 0x88888889    \
       ...                                          > (position + 1) % 15
+0x7D  6B C2 0F            imul eax, edx, 0x0f     /
+0x80  2B C8               sub  ecx, eax
+0x82  E8 <rel32>          call 0x20678c0          ; dial position -> internal id, a switch on 0..14
+0x87  8D 78 F8            lea  edi, [rax - 8]     ; undo the id bias
+0x8A  89 7B 0C            mov  [rbx + 0xc], edi   ; the new station
```

**A car steps through the dial in frequency order, not enum order.** The two switches are inverse
permutations of the fifteen. The order they encode runs from 88.9 to 107.5, with HKGN (102.0) at
position 10:

| dial position | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ERadioStationList` | 4 | 0 | 11 | 10 | 1 | 9 | 8 | 6 | 13 | 2 | 14 | 3 | 7 | 5 | 12 |

The first switch returns 0 for any value past 14, and the second returns id 12 (enum 4, position 0)
for any position past 14. So a custom station gets a wrong answer at both ends before the modulo is
even reached. The remainder is used here, not thrown away, so the division cannot be erased the way
it is in the name readers. Its `imul` operand cannot be retuned either, because the magic constant
belongs to 15.

**The whole block is detoured.** Its 34 bytes become a `jmp` to a 49-byte stub, allocated within
rip-relative reach of the site. The same allocation holds two tables of the plugin's own after the
stub: `position[]`, indexed by enum value, and `dial[]`, indexed by dial position. The enum range
is longer than the dial, because it holds the reserved slots 15 to 25. The stub is made executable
before any game byte is written:

```
mov  ecx, [rbx+0xc]
xor  eax, eax
cmp  ecx, total           ; the enum range, a 32-bit immediate, so this bound is not one of the 8-bit ones
jae  unknown              ; a value off the roster steps from position 0, as vanilla did
lea  rax, [rip+position]
mov  eax, [rax+rcx*4]     ; the dial position
unknown:
inc  eax
xor  edx, edx
mov  ecx, dialCount
div  ecx                  ; edx = (position + 1) % dialCount
lea  rax, [rip+dial]
mov  edi, [rax+rdx*4]     ; the station at that position
jmp  +0x8A
```

The stub uses the same registers as the block it replaces (`ecx`, `eax`, `edx` scratch, `edi`
the result, `rbx` the receiver). The only jump into the replaced bytes is the `jne` at `+0x5C`,
and it lands on the `jmp`.

**The tables hold every station in dial order, with custom ones at their frequency.** At patch
time the plugin asks the game's own switch for the fifteen's order, through the `call` target
read from the verified block, so that order cannot drift. Each custom station then goes in before
the first station whose frequency is above its own. The plugin compares the manifest's own
`frequency` against the fifteen vanilla frequencies it carries (`kVanillaFrequency`). Two
stations on one frequency keep slot order, the vanilla one first. The script-side receivers get the
same two tables through `RadioXL_DialPosition` and `RadioXL_DialStation`, so a car, a world device
and the pocket radio all step through one dial.

## Three radio sites divide by fifteen

`[M]` The magic constant `0x88888889` appears 74 times in the code section, because it also
divides by other multiples of 15. Seven of those loads are followed by `imul ..., 15`. Three are
the radio's, below. The other four (decal and vehicle-destruction code among them) read neither the
roster nor the name table.

| RVA | What | State |
| --- | --- | --- |
| `0x2067953` | name-table reader one | erased |
| `0x217015d` | name-table reader two, the Radioport's | erased |
| `0x2b9b133` | the vehicle receiver's next-station wrap | **detoured**, with the block around it |

The third is the end of a division whose remainder is used, not a reduction that can be deleted.
The two switches on either side of it also give a wrong answer for a custom index on their own. So
it goes with the whole block, as above.

## The patch

The patch is twelve sites across two tables and one detour. Every byte is checked first, and a
single mismatch abandons all of them. Two new arrays are allocated within rip-relative reach of
their readers. The second name-table reader addresses from the image base, so its table has to be
within 2 GB of that. The fifteen vanilla entries are copied in. Slots 15 to 25 hold no station
except the police and Kurtz names at 16 and 25. The custom stations go in from slot 26.

| Site | Edit |
| --- | --- |
| resolver `lea r8` | displacement to the new roster |
| resolver `cmp eax` | 15 to the new total |
| index-to-name `lea rdx` | displacement to the new roster |
| index-to-name `cmp eax` | 14 to total - 1 |
| vehicle receiver `cmp edi` | 15 to the new total |
| name reader one | division erased, `cmp` to total - 1, `lea rdx` to the new table |
| name reader two | division erased around the `inc`, `cmp` to total - 1, `disp32` to the new table |
| vehicle receiver `+0x68..+0x8A` | `jmp` to the next-station stub, which carries the totals as imm32s and the dial tables behind it |
| receiver turn-on check | 15 to the new total |
| receiver turn-on, the check after the random pick | 15 to the new total |
| traffic hand-over callback (`0xe9852c`) | 15 to the new total |
| save load (`vehicle::Audio::LoadFromPSData`, `0xe98278`) | 15 to the new total |

The turn-on block has no hash of its own. It is found from the receiver's enable routine and
verified in place, as is the load block. A car's startup pick is a separate detour in the same block
(`Startup.hpp`).

`[M]` Every hash resolves to the RVA the disassembly predicts. On 2.31, every radio still worked
with the roster at fifteen.

**Every raised bound is an 8-bit immediate, so the roster tops out at 127 ids.** Custom stations
start at enum 26, so that leaves room for 101 custom stations. Raising the limit means replacing the
readers rather than patching them. The vehicle step's bound is not one of these limits any more.

## Two things this table does not cover

- **The specials.** `special_A` and `special_B` are `audio::RadioStationChannelData::s_noneStation`
  (`0x3bf7d10`) and `s_policeStation` (`0x3bf7d20`). `special_C` (`0x3bf7d30`) is the Kurtz
  accessor's target. They are the separate handling for none, police and kurtz.
- **The list the UI walks through.** `RadioStationDataProvider` (game redscript) holds the
  fifteen in switch bodies, and `VehiclesManagerDataHelper` pushes sixteen literal TweakDB ids (no
  station, then the fifteen). Those are script with no table behind them, and they are the only
  things the framework wraps.
