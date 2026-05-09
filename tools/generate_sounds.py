"""Procedurally generate mystical sound effects for Juntra.

All output is 16-bit PCM mono WAV at 44.1 kHz — universal, lightweight, no
codec dependency. Designed to match the gold/purple mystical brand:

  shuffle.wav   — soft riffle of cards, 6 transient flicks over filtered noise
  card_pick.wav — short crystal "tink" when the seeker taps a card
  reveal.wav    — singing-bowl bell with high shimmer for the 3D card flip
  complete.wav  — ascending pentatonic chime when the reading is finalized

Reproducible: seeded RNG. Re-run any time to regenerate. ~30–80 KB each.

Usage:  python tools/generate_sounds.py
Reads:  (none)
Writes: assets/sounds/{shuffle,card_pick,reveal,complete}.wav
"""
from pathlib import Path
import numpy as np
from scipy.io import wavfile

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)


def to_int16(audio: np.ndarray, headroom_db: float = -3.0) -> np.ndarray:
    """Normalize peak to leave `headroom_db` of margin, then quantize to int16."""
    peak = float(np.max(np.abs(audio)))
    if peak > 0:
        target = 10.0 ** (headroom_db / 20.0)
        audio = audio / peak * target
    return np.clip(audio * 32767.0, -32768.0, 32767.0).astype(np.int16)


def card_pick() -> np.ndarray:
    """Bright two-tone crystal click — 180 ms, exponential decay."""
    dur = 0.18
    n = int(SR * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    tone = (
        np.sin(2 * np.pi * 2400 * t) * 0.6
        + np.sin(2 * np.pi * 4800 * t) * 0.3
        + np.sin(2 * np.pi * 900 * t) * 0.35
    )
    env = np.exp(-t * 28.0)
    return tone * env


def shuffle_riffle() -> np.ndarray:
    """Filtered pink-ish noise + 6 transient flicks suggesting a card riffle."""
    dur = 1.6
    n = int(SR * dur)
    rng = np.random.default_rng(42)

    noise = rng.normal(0.0, 1.0, n)
    # one-pole IIR LP for warmth
    out = np.zeros(n)
    a = 0.92
    for i in range(1, n):
        out[i] = a * out[i - 1] + (1 - a) * noise[i]
    out *= 0.55

    for i in range(6):
        idx = int((0.15 + i * 0.22) * SR)
        flick_n = int(SR * 0.04)
        if idx + flick_n < n:
            tt = np.linspace(0, 0.04, flick_n)
            flick = rng.normal(0.0, 1.0, flick_n) * np.exp(-tt * 60.0)
            out[idx:idx + flick_n] += flick * 0.85

    fade_n = int(SR * 0.08)
    out[:fade_n] *= np.linspace(0, 1, fade_n)
    out[-fade_n:] *= np.linspace(1, 0, fade_n)
    return out


def reveal_bell() -> np.ndarray:
    """Singing-bowl chime: stretched harmonic stack + brief high shimmer."""
    dur = 1.8
    n = int(SR * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    fund = 392.0  # G4
    # (frequency_ratio, amplitude, decay_rate)
    parts = [
        (1.00, 1.00, 4.0),
        (2.04, 0.60, 4.5),
        (3.07, 0.40, 5.5),
        (4.15, 0.25, 6.5),
        (6.20, 0.15, 7.5),
    ]
    audio = np.zeros(n)
    for ratio, amp, decay in parts:
        audio += amp * np.sin(2 * np.pi * fund * ratio * t) * np.exp(-t * decay)

    # High shimmer in the first 0.4 s — differenced white noise = HP-ish
    sparkle_n = int(SR * 0.4)
    rng = np.random.default_rng(1)
    sparkle = np.diff(rng.normal(0.0, 1.0, sparkle_n), prepend=0.0)
    sparkle *= np.exp(-np.linspace(0, 0.4, sparkle_n) * 12.0)
    audio[:sparkle_n] += sparkle * 0.12

    attack_n = int(SR * 0.01)
    audio[:attack_n] *= np.linspace(0, 1, attack_n)
    return audio


def complete_arpeggio() -> np.ndarray:
    """Ascending G-major pentatonic chime — 5 bell-ish notes overlapping."""
    notes_hz = [392.00, 493.88, 587.33, 659.25, 783.99]  # G4 B4 D5 E5 G5
    note_dur = 0.32
    overlap = 0.10
    tail = 0.7
    total = note_dur * len(notes_hz) - overlap * (len(notes_hz) - 1) + tail
    n = int(SR * total)
    audio = np.zeros(n)
    for i, hz in enumerate(notes_hz):
        start = int(SR * i * (note_dur - overlap))
        seg_n = min(int(SR * (note_dur + tail)), n - start)
        if seg_n <= 0:
            continue
        tt = np.linspace(0, seg_n / SR, seg_n, endpoint=False)
        seg = (
            np.sin(2 * np.pi * hz * tt)
            + 0.40 * np.sin(2 * np.pi * hz * 2.0 * tt)
            + 0.18 * np.sin(2 * np.pi * hz * 3.5 * tt)
        )
        seg *= np.exp(-tt * 4.0)
        audio[start:start + seg_n] += seg
    return audio


def main() -> None:
    sounds = {
        "card_pick.wav": card_pick(),
        "shuffle.wav": shuffle_riffle(),
        "reveal.wav": reveal_bell(),
        "complete.wav": complete_arpeggio(),
    }
    for name, audio in sounds.items():
        path = OUT / name
        wavfile.write(str(path), SR, to_int16(audio))
        kb = path.stat().st_size / 1024
        print(f"wrote {path.name}  {len(audio)/SR:.2f}s  {kb:.1f} KB")


if __name__ == "__main__":
    main()
