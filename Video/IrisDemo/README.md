# Iris cinematic demo

A 1:42, 16:9 film in three acts. It opens on the problem, shows the real app on a phone, and ends with how it works and what's next. Delivered at **1920 × 1080, 60 fps** (`exports/iris-demo-1080p60.mp4`), with captions burned in and as `exports/iris-demo.srt`.

| Time | Shot | Story beat |
|---|---|---|
| 0:00 | Close your eyes | The viewer is put in the user's place: the table as low vision sees it, blurred. |
| 0:07 | Every day | Why we built it: family members of ours live with low vision. |
| 0:14 | Scale | 43M people are blind and 295M live with moderate to severe vision loss; over half a billion by 2050 (IAPB Vision Atlas). |
| 0:23 | The gap | Most tools describe the scene; few get your hand to the object. |
| 0:29 | So we built Iris | The first sharp picture in the film arrives through the phone: the bottle, outlined. |
| 0:35 | Locate | The app's spoken question. |
| 0:40 | Real app footage | The iPhone recording, with its own ElevenLabs voice: find, reach, take hold, read. The silent wait for the user's answer is cut. |
| 1:14 | Under the surface | Vision, depth, voice. |
| 1:23 | What's next | Testing with our families, guidance without LiDAR, medication labels; 1.8B people with vision loss by 2050 (Lancet Global Health Commission). |
| 1:35 | Iris | Closing title. |

There is no voiceover: the story is told in on-screen text, and the only voice is Iris's own, from the recording. Explore is not in this cut.

Rendered with Eevee, 16 samples, 1080p60 (about 0.6–0.9 s a frame on an M3, roughly 50 minutes). The first cut (4K, 2:00) is archived in `review/v1` and `review/v1-renders`.

## What is real

Maestro captured welcome, options, Explore, and Locate from the native simulator app. The main demonstration uses the supplied iPhone recording from 13.5–53.5 seconds: bottle detection, guidance, pickup, label reading, and spoken identification. Explore is explicitly marked as a simulator feature preview. The opening 5.5 seconds use a held clean frame from source time 19 seconds to remove camera permission and Control Center overlays; subsequent action and original audio keep their timing. No synthetic detection or spoken results are added. The smaller three-phone recap uses stills from the real recording.

The soundtrack and transition effects are an original procedural composition. Iris's voice is extracted from the supplied recording. Speech is transcribed locally using MLX Whisper; no source video is uploaded. Bundled Nunito fonts retain their SIL Open Font License files.

## Capture and scene build

Requires Xcode, an iOS simulator, Maestro, Blender 5.3, uv, FFmpeg, Python with NumPy/SciPy/Pillow, and the community MCP for Blender add-on. This machine's Blender MCP server is registered in Codex and listens on localhost through the Blender add-on.

```sh
# From the repository root. IRIS_SIMULATOR can override the simulator UDID.
Video/IrisDemo/scripts/capture.sh

# Start Blender with its MCP add-on enabled.
blender --python Video/IrisDemo/scripts/start_blender.py

# In another terminal, build through the actual MCP protocol.
uv run --with mcp python Video/IrisDemo/scripts/mcp_client.py --script Video/IrisDemo/scripts/build_scene.py

python3 Video/IrisDemo/scripts/prepare_source.py

# Regenerate the soundtrack and captions from the preserved source and transcript.
python3 Video/IrisDemo/scripts/make_audio.py
```

The original recording is preserved at `assets/source/iris-locate-original.mov`. To recreate transcripts, use `mlx-community/whisper-small.en-mlx` locally with `word_timestamps=True`; save its result as `assets/audio/transcript.json`.

## Preview and final rendering

```sh
blender --factory-startup -b Video/IrisDemo/scenes/iris-film.blend -P Video/IrisDemo/scripts/render.py -- --preview
python3 Video/IrisDemo/scripts/assemble.py preview

# Final render, per-shot encoding, assembly, and export validation.
python3 Video/IrisDemo/scripts/produce.py
```

The reviewed renderer is **Eevee, native 4K, 32 temporal samples, 60 fps**. Cycles is available in the scene-build source, but a measured 69-second 4K frame implied roughly four days for this machine. Eevee measured around 10 seconds per consecutive 4K frame, suggesting approximately 12–16 hours for animation plus encoding. This is an estimate, not a completion guarantee. The 40-second live demonstration uses one rendered plate and the original video, avoiding redundant scene rendering.

`python3 Video/IrisDemo/scripts/status.py` prints progress. `renders/production-status.json` records the current stage and completed shots. Restart `produce.py` to resume unchanged scenes. It validates dimensions, frame rate, and duration before deleting reproducible PNG caches for a completed shot. Representative final frames remain in `review/final/`. It stops before rendering another shot if fewer than 12 GiB are free. Scene changes require archiving prior outputs before beginning a fresh production run.

## Review criteria

- Readable phone screens and text; no broken texture paths or unintended clipping.
- Continuous real-demo audio and correctly timed speech captions.
- Complete shot frame counts, 120-second final duration, 3840 × 2160 resolution, 60 fps.
- Full export decode without errors; final visual and audio review before publication.

No upload, publication, or paid rendering is performed by these scripts.
