# SRT shifter

**Backlog:** T-004 · `srt-shifter`

Shift SRT or WebVTT cue timings by N milliseconds (positive or negative) and save.

## Usage

```bash
cd cli/srt-shifter
python3 srt_shifter.py movie.srt --by 1500
python3 srt_shifter.py movie.srt --by -500 -o fixed.srt
python3 srt_shifter.py movie.vtt --by 1000 -o -
```

- `--by MS` — required offset in milliseconds
- `-o` / `--output` — write elsewhere (default: overwrite input; `-` = stdout)
- Format from `.srt` / `.vtt` extension, or `WEBVTT` content

## Not for

Transcoding video, translating cue text, or editing ASS/SSA subtitles.
