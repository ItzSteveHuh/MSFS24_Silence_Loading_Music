MSFS 2024 - silence the loading-screen music (even with the Music slider at 0)

Why the slider doesn't work: the loading music is in the startup sound package
(Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK), which loads BEFORE your
settings are applied. This tool replaces that one music clip with silence of the same size.
It contains no game files - it edits YOUR copy, and keeps a backup (.bak) next to it.

HOW TO USE (nothing to install - uses PowerShell, which is built into Windows)
 1. Close MSFS 2024.
 2. Unzip this folder anywhere.
 3. Double-click  1_Silence_Loading_Music.bat
    It looks for your MSFS 2024 install on all drives. If it can't find it, run it from a
    command prompt with the full path:
      1_Silence_Loading_Music.bat -Path "D:\SteamLibrary\steamapps\common\MSFS2024\Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK"
 4. Launch the sim.

UNDO: double-click 2_Restore_Original.bat  (or Steam > Properties > Installed Files >
      Verify integrity of game files).

NOTES
 - Steam updates / verify restore the original file. Just run step 3 again.
 - Tested on the Steam version. Microsoft Store / Xbox app installs are searched too
   but untested. The script refuses to touch the file if its layout isn't what it expects.
 - If Windows shows a SmartScreen/"unblocked file" warning, right-click the .zip >
   Properties > Unblock before unzipping, or open the .ps1 in Notepad to read exactly what it does.
 - Use at your own risk. Not affiliated with Asobo or Microsoft.
