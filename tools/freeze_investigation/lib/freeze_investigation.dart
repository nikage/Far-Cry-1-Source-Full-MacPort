/// Runtime investigation helpers for post-load freezes (audio vs main thread, SIGKILL).
library freeze_investigation;

/// Commands to run while the game is **visibly hung** (replace `<pid>`).
const String kStackCaptureShellBlock = r'''
# Terminal A: run game outside IDE, note PID from Activity Monitor or:
#   pgrep -x FarCry

# 10s sample of all threads (safe on hung process):
sample <pid> 10 -file /tmp/farcry_hang.sample.txt

# Or attach lldb (Ctrl+D to quit after capturing):
lldb -p <pid> -o "bt all" -o "detach" -o "quit"
''';

/// Exit code 9 is SIGKILL — distinguish IDE Stop vs OS kill.
const String kExitCode9Notes = r'''
Exit code 9 means SIGKILL. Common sources:
1. IDE/debugger "Stop" — not a game bug.
2. macOS memory pressure (rare on desktop) — check Console.app around kill time.
3. Manual `kill -9`.

Reproduce from Terminal without IDE; if exit code is not 9 on normal quit, prior 9 was tooling.
''';

/// In-game log prefix for load-pipeline checkpoints ([FreezeInv] in GameLoading.cpp / Game.cpp).
const String kFreezeInvLogPrefix = '[FreezeInv]';

/// Engine areas that assign EF_LoadShader without checking for null (audit for Metal gaps).
const List<String> kShaderNullRiskSites = <String>[
  'CryGame/XVehicle.cpp — CVehicle::InitHeadLight / InitFakeLight set m_pHeadLight->m_pShader from EF_LoadShader',
  'CryGame/XPlayerLight.cpp — m_pDynLight->m_pShader from EF_LoadShader',
  'CryGame/ScriptObjectWeaponClass.cpp — DynLight.m_pShader from EF_LoadShader',
];

List<String> investigationChecklist() => <String>[
      '1. Reproduce hang; capture kStackCaptureShellBlock output.',
      '2. In log, find last [FreezeInv] line — last phase completed before stall.',
      '3. Read kExitCode9Notes if process shows exit code 9.',
      '4. Search log for Sound path contains control char — bad path upstream of MacOSSoundSystem::LoadSound.',
      '5. Review kShaderNullRiskSites if Metal logs show unregistered shader names at hang time.',
    ];
