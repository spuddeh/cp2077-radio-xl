// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: What differs between the game builds the plugin supports, one table per build.
// File Version: 0.9.1
// ======================================================================================
//
// Every patched function is found by RED4ext hash on every build; what moves between builds is where
// the patched instructions sit inside each function, the bytes they hold, and a few engine offsets.
// Each build's values live in one table, and the plugin uses the table whose every byte check passes
// (`SelectBuild` in Main.cpp). The game version is logged beside the table's name and never decides.
//
// The two newest builds are kept. A new build is a new table, checked site by site against its exe;
// the oldest is removed at the same time.

#pragma once

#include <cstddef>
#include <cstdint>

namespace radioxl
{

struct Build
{
    const char* name;

    // --- the station roster ---
    int vanillaCount;      // the engine's roster size and every bound's vanilla value
    int32_t policeEnum;    // radio_station_police's ERadioStationList value (internal id - 8)

    // The receiver's turn-on block. `enableTest` is the enable routine's `test dl, dl`, followed by a
    // rel32 jump: with `enableJne` the block is that jump's target, otherwise it falls through after it.
    size_t enableTest;
    bool enableJne;
    size_t onPickStore;    // in the block: mov [rdi+0xc], eax
    size_t onPickCmp;      // cmp dword [rdi+0xc], imm8
    size_t onPickJae;      // jae rel32

    // The modulo by the station count: the magic-number load and the multiply back.
    uint8_t divMagic[5];   // mov eax, imm32
    uint8_t imulCount[3];  // imul eax, <reg>, count

    // The vehicle receiver's next-station step, which the plugin detours from +0x68.
    size_t stepImul;
    size_t stepSub;        // 0 when the build has no `sub ecx, eax` checked here
    size_t stepFromDial;   // call dial position -> internal id
    size_t stepBias;       // lea edi, [rax-8]
    size_t stepTo;         // mov [rbx+0xc], edi: the stub returns here

    // The first name reader: the division runs from +0x03 to `nameDivTo`.
    size_t nameDivTo;
    size_t nameImul;
    size_t nameSub;
    size_t nameCmp;        // cmp r8d, imm8; the imm8 is at +3
    size_t nameLea;        // lea rdx, [rip+disp32]; the disp32 is at +3

    // The Radioport's name reader: the division runs from +0x65 to `name2DivTo`.
    size_t name2DivTo;
    size_t name2Imul;
    size_t name2Sub;
    size_t name2Cmp;       // cmp ecx, imm8; the imm8 is at +2
    size_t name2Mov;       // mov rbx, [r14+rcx*8+disp32]; the disp32 is at +4

    // --- a car's startup pick (Startup.hpp), offsets inside the turn-on block ---
    uint8_t startHook[9];  // at +0x54
    uint8_t startCap[3];   // at +0x6F
    size_t startCopyAt;
    uint8_t startCopy[5];
    size_t startEngineAt;  // mov rax, [rip+rel32]: the engine root
    size_t startManagerAt; // mov rsi, [rsi+0xe0]
    size_t startActiveCall;
    size_t startLimitCall;
    size_t startFilterCall;
    size_t startPickAt;
    uint8_t startPick[10];
    size_t startPickLen;
    size_t startResolveCall;
    size_t startEmptyAt;   // the block's own "no station" path: cmp dword [rdi+0xc], imm8

    // --- the engine root ---
    size_t rootAudioSystem;  // engine root -> audio system; +0xe0 of it is the radio manager

    // --- the broadcaster's curve loader (Broadcast.hpp) ---
    uint8_t curveLoaderLead[10];

    // --- Wwise (Mix.hpp, Eq.hpp) ---
    size_t mixFlagLoadAt;    // in the radio system's update: mov rax, [rip+rel32]; cmp [rax+0x1e0], r14b
    size_t mixCritCallAt;    // in the index reader: call to the lock's constructor
    size_t mixSetCallAt;     // in the curve loader: mov r8d, [rdi+0x10]; call CAkConversionTable::Set
    uint8_t setBusEffectPrologue[8];
};

// Steam and GOG 2.31.
constexpr Build kBuild231{
    .name = "2.31",
    .vanillaCount = 14,
    .policeEnum = 15,
    .enableTest = 0x40,
    .enableJne = true,
    .onPickStore = 0x171,
    .onPickCmp = 0x174,
    .onPickJae = 0x178,
    .divMagic = {0xB8, 0x25, 0x49, 0x92, 0x24},  // 0x24924925, then sub/shr/add/shr
    .imulCount = {0x6B, 0xC0, 0x0E},            // imul eax, eax, 14
    .stepImul = 0x85,
    .stepSub = 0x88,
    .stepFromDial = 0x8A,
    .stepBias = 0x8F,
    .stepTo = 0x92,
    .nameDivTo = 0x1C,
    .nameImul = 0x16,
    .nameSub = 0x19,
    .nameCmp = 0x1C,
    .nameLea = 0x22,
    .name2DivTo = 0x77,
    .name2Imul = 0x72,
    .name2Sub = 0x75,
    .name2Cmp = 0x77,
    .name2Mov = 0x7C,
    .startHook = {0x48, 0x8B, 0x88, 0x88, 0x00, 0x00, 0x00, 0x33, 0xD2},  // mov rcx,[rax+0x88]; xor edx,edx
    .startCap = {0x83, 0xFA, 0x0E},                                     // cmp edx, 14
    .startCopyAt = 0x7C,
    .startCopy = {0x48, 0x89, 0x44, 0xD5, 0xCF},  // mov [rbp+rdx*8-0x31], rax
    .startEngineAt = 0x92,
    .startManagerAt = 0xA5,
    .startActiveCall = 0xB4,
    .startLimitCall = 0xBF,
    .startFilterCall = 0xE2,
    .startPickAt = 0x159,
    .startPick = {0x48, 0x8D, 0x55, 0x67, 0x48, 0x8B, 0x4C, 0xCD, 0xD7, 0xE8},  // lea rdx; mov rcx,[rbp+rcx*8-0x29]; call
    .startPickLen = 10,
    .startResolveCall = 0x162,
    .startEmptyAt = 0x174,
    .rootAudioSystem = 0xa8,
    .curveLoaderLead = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x6C, 0x24, 0x10},
    .mixFlagLoadAt = 0x2d,
    .mixCritCallAt = 0x12b,
    .mixSetCallAt = 0x122,
    .setBusEffectPrologue = {0x40, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x83},  // push rbp; r14; r15
};

// Steam 2.5. HKGN is the fifteenth station, and the police scanner moved to internal id 24.
constexpr Build kBuild25{
    .name = "2.5",
    .vanillaCount = 15,
    .policeEnum = 16,
    .enableTest = 0x2B,
    .enableJne = false,
    .onPickStore = 0x144,
    .onPickCmp = 0x147,
    .onPickJae = 0x14B,
    .divMagic = {0xB8, 0x89, 0x88, 0x88, 0x88},  // 0x88888889, then mul/shr 3
    .imulCount = {0x6B, 0xC2, 0x0F},            // imul eax, edx, 15
    .stepImul = 0x7D,
    .stepSub = 0x80,
    .stepFromDial = 0x82,
    .stepBias = 0x87,
    .stepTo = 0x8A,
    .nameDivTo = 0x13,
    .nameImul = 0x0D,
    .nameSub = 0x10,
    .nameCmp = 0x13,
    .nameLea = 0x19,
    .name2DivTo = 0x6F,
    .name2Imul = 0x6A,
    .name2Sub = 0x6D,
    .name2Cmp = 0x6F,
    .name2Mov = 0x74,
    .startHook = {0x48, 0x8B, 0x90, 0x88, 0x00, 0x00, 0x00, 0x33, 0xC9},  // mov rdx,[rax+0x88]; xor ecx,ecx
    .startCap = {0x83, 0xF9, 0x0F},                                     // cmp ecx, 15
    .startCopyAt = 0x74,
    .startCopy = {0x48, 0x8D, 0x4D, 0xD7, 0xE8},  // lea rcx,[rbp-0x29]; call append
    .startEngineAt = 0x97,
    .startManagerAt = 0xAA,
    .startActiveCall = 0xB9,
    .startLimitCall = 0xC4,
    .startFilterCall = 0xE7,
    .startPickAt = 0x12E,
    .startPick = {0x48, 0x8D, 0x55, 0x67, 0x48, 0x8B, 0x08, 0xE8},  // lea rdx; mov rcx,[rax]; call
    .startPickLen = 8,
    .startResolveCall = 0x135,
    .startEmptyAt = 0x147,
    .rootAudioSystem = 0xc8,
    .curveLoaderLead = {0x89, 0x54, 0x24, 0x10, 0x48, 0x89, 0x4C, 0x24, 0x08, 0x53},
    .mixFlagLoadAt = 0x36,
    .mixCritCallAt = 0x13e,
    .mixSetCallAt = 0x1c7,
    .setBusEffectPrologue = {0x41, 0x54, 0x41, 0x56, 0x41, 0x57, 0x48, 0x83},  // push r12; r14; r15
};

constexpr const Build* kBuilds[] = {&kBuild25, &kBuild231};

// The build whose checks passed, or null: nothing that reads a table runs without one.
inline const Build* g_build = nullptr;

} // namespace radioxl
