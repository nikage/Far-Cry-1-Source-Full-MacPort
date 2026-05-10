String loadSequenceDiagnosisHelp() {
  return '''
Level load / disconnect sequence — reading log.txt

High-signal lines (verbosity 3, visible at default log_FileVerbosity):
  precache_OnLevelLoaded_done     — counts how often C3DEngine::OnLevelLoaded / precache ran
  ShutdownClient before XDisconnect
  CXClient_OnXConnect
  OnXContextSetup branch=SP_listen_fastpath | full_path client_IXSystem_LoadLevel
  RefreshServerList / Lua_Game_RefreshServerList invoked

Grep examples (run in the directory that contains log.txt):
  rg '[GameCheckpoint]' log.txt
  rg 'precache_OnLevelLoaded_done|LoadLevelCS begin|IXSystem_Server_LoadLevel enter|ShutdownClient|CXClient_OnXConnect|OnXContextSetup branch|RefreshServerList|Lua_Game_RefreshServerList' log.txt

Interpretation:
  Two precache_OnLevelLoaded_done lines without two LoadLevelCS cycles ⇒ two server/client LoadLevel completions (see suspicious load log plan).
  Lua_Game_RefreshServerList ⇒ script called Game:RefreshServerList(); C++ only ⇒ RefreshServerList from native code path.

Finding script callers in shipped data:
  Loose Lua may live under game paks (e.g. FCData). Example: rg -a "RefreshServerList" on extracted scripts or use strings on *.pak.
''';
}
