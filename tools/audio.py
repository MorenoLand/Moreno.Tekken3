import re
import struct
from pathlib import Path
PRED = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))
SECTOR = 2352
def adpcm_decode(data):
    h1 = h2 = 0
    out = bytearray()
    for o in range(0, len(data) - 15, 16):
        shift = min(12, data[o] & 15)
        pred = data[o] >> 4
        if pred > 4:
            pred = 0
        f0, f1 = PRED[pred]
        for packed in data[o + 2:o + 16]:
            for nib in (packed & 15, packed >> 4):
                v = nib - 16 if nib & 8 else nib
                s = ((v << 12) >> shift) + ((h1 * f0 + h2 * f1 + 32) >> 6)
                s = max(-32768, min(32767, s))
                h2, h1 = h1, s
                out += struct.pack("<h", s)
        if data[o + 1] & 1:
            break
    return bytes(out)
def wav_bytes(pcm, rate, channels):
    return b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, channels, rate, rate * channels * 2, channels * 2, 16) + b"data" + struct.pack("<I", len(pcm)) + pcm
def vab_samples(vh, vb):
    ps, ts, vs = struct.unpack_from("<HHH", vh, 18)
    table = 32 + 2048 + ps * 16 * 32
    sizes = [s * 8 for s in struct.unpack_from("<256H", vh, table)]
    if sum(sizes[:vs + 1]) != len(vb):
        raise ValueError("VB size does not match the VH sample table")
    out = []
    pos = 0
    for i in range(vs + 1):
        if sizes[i]:
            out.append((i, vb[pos:pos + sizes[i]]))
        pos += sizes[i]
    return out
def cue_tracks(cue):
    cue = Path(cue)
    tracks = []
    current = None
    for line in cue.read_text(errors="replace").splitlines():
        m = re.match(r'\s*FILE\s+"?(.+?)"?\s+BINARY', line, re.I)
        if m:
            current = cue.parent / m.group(1)
        m = re.match(r"\s*TRACK\s+(\d+)\s+(\S+)", line, re.I)
        if m:
            tracks.append({"number": int(m.group(1)), "mode": m.group(2).upper(), "file": current, "start": 0})
        m = re.match(r"\s*INDEX\s+01\s+(\d+):(\d+):(\d+)", line, re.I)
        if m and tracks:
            tracks[-1]["start"] = (int(m.group(1)) * 60 + int(m.group(2))) * 75 + int(m.group(3))
    return tracks
def cdda_pcm(track):
    raw = Path(track["file"]).read_bytes()
    return raw[track["start"] * SECTOR:]
