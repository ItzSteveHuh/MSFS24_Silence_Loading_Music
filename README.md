# MSFS 2024 - Silence Loading Music

Silences the loading-screen music in Microsoft Flight Simulator 2024 **even when the in-game Music slider is set to 0**. Nothing to install: it uses PowerShell, which is built into Windows.

![Overview](docs/overview.png)

## Why the slider doesn't work

The loading music is part of the startup sound package, which the sim loads *before* your settings are applied:

```
Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK
```

That file is a Wwise `AKPK` container holding four sound banks and one streamed music clip (~2 minutes, looping). This tool replaces that clip with silence of exactly the same byte size, so the container layout is untouched. The in-game music (`MUSIC.PC.PCK`) is not modified, so the slider keeps working normally once you're in the sim.

**This repo contains no game files.** The script edits *your own* copy and keeps a backup next to it (`SHARED_MINIMAL.PC.PCK.bak`).

## Usage

1. Close MSFS 2024.
2. Download this repo (or the zip from Releases) and unzip it.
3. Double-click **`1_Silence_Loading_Music.bat`**.
4. Launch the sim.

It searches all drives for your install. If it can't find it, pass the full path to the file. Your install location will be different from anyone else's, so point it at wherever *your* MSFS 2024 folder is:

```powershell
.\msfs24_silence_loading_music.ps1 -Path "<your MSFS 2024 folder>\Packages\fs-base-onboarding\SOUNDINIT\SHARED_MINIMAL.PC.PCK"
```

Typical install folders (yours may be on another drive or library):
- **Steam:** `...\steamapps\common\MSFS2024`
- **Microsoft Store / Xbox app:** `...\XboxGames\Microsoft Flight Simulator 2024\Content`

Tip: in Steam, right-click the game > Manage > Browse local files to open your install folder.

Other options: `-DryRun` (show what it would do), `-Restore` (put the original back; same as `2_Restore_Original.bat`).

![Tool output](docs/tool_output.png)

## Notes

- **Updates:** Steam updates and "Verify integrity of game files" restore the original file. Just run the tool again. It finds the clip by reading the file's own index, so it isn't tied to a single game version.
- **Safety:** if the file's layout isn't what the tool expects (for example after a big game update), it refuses to modify anything. It is idempotent: running it twice does nothing the second time.
- **Tested** on the Steam version of MSFS 2024. Microsoft Store / Xbox app install paths are searched but untested.
- **Undo:** run `2_Restore_Original.bat`, or use Steam > Properties > Installed Files > Verify integrity of game files.
- The script is plain text: open `msfs24_silence_loading_music.ps1` in Notepad to read exactly what it does.

## How it works (technical)

1. Parse the `AKPK` header: soundbank table and streamed-file table (each entry is `id, block size, size, start block, language`).
2. For each streamed file over 1 MB that is a RIFF `fmt` tag `0xFFFF` (Wwise Vorbis), build a silent stereo 48 kHz 16-bit PCM `RIFF/WAVE` of exactly the same size (extensible `fmt`, zeroed `data`, small `JUNK` chunk as padding).
3. Write it over the original bytes in place, then re-read and verify.

## Disclaimer

Use at your own risk. Not affiliated with or endorsed by Asobo Studio, Xbox Game Studios or Microsoft. "Microsoft Flight Simulator" is a trademark of Microsoft.

## License

[MIT](LICENSE)
