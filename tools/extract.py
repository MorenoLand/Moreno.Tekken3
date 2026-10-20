import argparse
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import disc
import formats
import audio
BNS = "TEKKEN3/TEKKEN3.BNS"
def find_disc(arg):
    if arg:
        return arg
    for base in (Path.cwd(), Path(__file__).resolve().parent.parent, Path(__file__).resolve().parent.parent.parent):
        for p in base.glob("*.cue"):
            return str(p)
    raise SystemExit("no disc: pass a .cue path")
def write(path, data, overwrite):
    if path.exists() and not overwrite:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True
def extract_records(d, out, overwrite):
    table = disc.bns_table(d)
    index = []
    for i, (sector, size) in enumerate(table):
        entry = {"id": i, "sector": sector, "size": size}
        if size:
            b = d.file_range(BNS, sector * disc.USER_SIZE, size)
            arc = formats.parse_arc(b)
            if arc:
                entry["kind"] = "arc"
                entry["members"] = []
                for m, (o, s) in enumerate(arc):
                    mb = b[o:o + s]
                    kind = "tim" if formats.is_tim(mb) else "bin"
                    entry["members"].append({"index": m, "offset": o, "size": s, "kind": kind})
                    if s:
                        write(out / "bns" / ("%03d" % i) / ("%02d.%s" % (m, kind)), mb, overwrite)
            elif formats.is_tim(b):
                entry["kind"] = "tim"
                write(out / "bns" / ("%03d.tim" % i), b, overwrite)
            else:
                entry["kind"] = "3dmk" if b[8:12] == b"3DMK" else "vab" if b[:4] == b"pBAV" else "bin"
                write(out / "bns" / ("%03d.%s" % (i, entry["kind"])), b, overwrite)
                tims = formats.packed_tims(b) if entry["kind"] == "bin" and (i in (0, 9, 10, 11, 12, 13, 301, 302) or 14 <= i <= 35) else []
                entry["packed_tims"] = len(tims)
                for k, t in enumerate(tims):
                    write(out / "bns" / ("%03d" % i) / ("p%02d.tim" % k), t, overwrite)
        index.append(entry)
    write(out / "bns" / "index.json", json.dumps(index, indent=1).encode(), True)
    write(out / "system" / "SLUS_004.02", d.file("TEKKEN3/SLUS_004.02"), overwrite)
    return index
def extract_textures(out, overwrite):
    n = 0
    for p in sorted((out / "bns").rglob("*.tim")):
        b = p.read_bytes()
        try:
            t = formats.parse_tim(b)
            if not t["width"] or not t["height"]:
                continue
            target = out / "textures" / p.relative_to(out / "bns").with_suffix(".png")
            if target.exists() and not overwrite:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            formats.write_png(target, t["width"], t["height"], formats.tim_pixels(t))
            n += 1
        except Exception as e:
            print("skip", p, e)
    return n
def extract_common_audio(d, out, overwrite):
    n = 0
    exe = d.file("TEKKEN3/SLUS_004.02")
    start = 0xc3e5c
    banks = []
    for number, vh_offset in enumerate((90192, 94832), 1):
        vh = exe[vh_offset:]
        ps, ts, vs = struct.unpack_from("<HHH", vh, 18)
        table = 32 + 2048 + ps * 16 * 32
        total = sum(x * 8 for x in struct.unpack_from("<256H", vh, table)[:vs + 1])
        samples = audio.vab_samples(vh, exe[start:start + total])
        start += total
        tones = audio.vab_tones(vh)
        for i, data in samples:
            if write(out / "audio" / "common" / ("%d" % number) / ("%02d.wav" % i), audio.wav_bytes(audio.adpcm_decode(data), 44100, 1), overwrite):
                n += 1
        write(out / "audio" / "common" / ("%d" % number) / "tones.json", json.dumps(tones).encode(), True)
    return n
def extract_audio(d, cue, out, overwrite):
    n = 0
    table = disc.bns_table(d)
    index = json.loads((out / "bns" / "index.json").read_text())
    for e in index:
        if e.get("kind") != "vab":
            continue
        vh = (out / "bns" / ("%03d.vab" % e["id"])).read_bytes()
        arc = out / "bns" / ("%03d" % (e["id"] + 1)) / "02.bin"
        if not arc.exists():
            continue
        try:
            samples = audio.vab_samples(vh, arc.read_bytes())
        except ValueError as err:
            print("skip vab", e["id"], err)
            continue
        write(out / "audio" / "vab" / ("%03d" % e["id"]) / "tones.json", json.dumps(audio.vab_tones(vh)).encode(), True)
        for i, data in samples:
            if write(out / "audio" / "vab" / ("%03d" % e["id"]) / ("%02d.wav" % i), audio.wav_bytes(audio.adpcm_decode(data), 44100, 1), overwrite):
                n += 1
    n += extract_common_audio(d, out, overwrite)
    for t in audio.cue_tracks(cue):
        if t["mode"] == "AUDIO":
            if write(out / "audio" / "cdda" / ("track%02d.wav" % t["number"]), audio.wav_bytes(audio.cdda_pcm(t), 44100, 2), overwrite):
                n += 1
    return n
def movie_ranges(d):
    lba, size = d.files["TEKKEN3/TEKKEN3.XAS"]
    movies = []
    for i in range(size // disc.USER_SIZE):
        d.f.seek((lba + i) * disc.SECTOR)
        raw = d.f.read(disc.SECTOR)
        if raw[18] & 4:
            continue
        data = raw[24:24 + (2324 if raw[18] & 0x20 else 2048)]
        if struct.unpack_from("<H", data, 0)[0] != 0x0160:
            continue
        index, frame = struct.unpack_from("<H", data, 4)[0], struct.unpack_from("<I", data, 8)[0]
        if (index == 0 and frame == 1) or not movies:
            movies.append([i, i])
        movies[-1][1] = i
    return lba, movies
def extract_movies(d, out, overwrite):
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        print("ffmpeg not found: movies skipped")
        return 0
    lba, movies = movie_ranges(d)
    count = 0
    for k, (first, last) in enumerate(movies):
        target = out / "movies" / ("%02d.ogv" % k)
        if target.exists() and not overwrite:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".str", delete=False) as tmp:
            d.f.seek((lba + first) * disc.SECTOR)
            tmp.write(d.f.read((last - first + 1) * disc.SECTOR))
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", tmp.name, "-vf", "scale=640:480:flags=lanczos,format=yuv420p", "-c:v", "libtheora", "-g", "1", "-q:v", "8", "-c:a", "libvorbis", "-q:a", "5", str(target)], check=True)
        Path(tmp.name).unlink()
        count += 1
    for k in range(len(movies)):
        sound = out / "movies" / ("%02d.ogg" % k)
        if (overwrite or not sound.exists()) and (out / "movies" / ("%02d.ogv" % k)).exists():
            subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(out / "movies" / ("%02d.ogv" % k)), "-vn", "-c:a", "copy", str(sound)], check=True)
    return count
def xa_tracks(d):
    lba, size = d.files["TEKKEN3/TEKKEN3.XAS"]
    channels = {}
    for i in range(size // disc.USER_SIZE):
        d.f.seek((lba + i) * disc.SECTOR)
        raw = d.f.read(disc.SECTOR)
        if not (raw[18] & 4):
            if struct.unpack_from("<H", raw, 24)[0] == 0x0160:
                break
            continue
        track = channels.setdefault(raw[17], [[]])
        track[-1].append((lba + i, raw))
        if raw[18] & 0x80:
            track.append([])
    return {c: [t for t in tracks if t] for c, tracks in channels.items()}
def extract_xa(d, out, overwrite):
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        print("ffmpeg not found: music skipped")
        return 0
    index = {}
    count = 0
    for channel, tracks in sorted(xa_tracks(d).items()):
        for n, sectors in enumerate(tracks):
            target = out / "audio" / "xa" / ("c%d_%d.ogg" % (channel, n))
            index["c%d_%d" % (channel, n)] = [sectors[0][0], sectors[-1][0]]
            if target.exists() and not overwrite:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(suffix=".str", delete=False) as tmp:
                tmp.write(b"".join(s[1] for s in sectors))
            subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "4", str(target)], check=True)
            Path(tmp.name).unlink()
            count += 1
    write(out / "audio" / "xa" / "index.json", json.dumps(index, indent=1).encode(), True)
    return count
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("disc", nargs="?")
    ap.add_argument("-o", "--output", default=str(Path(__file__).resolve().parent.parent / "assets"))
    ap.add_argument("--records", action="store_true")
    ap.add_argument("--textures", action="store_true")
    ap.add_argument("--audio", action="store_true")
    ap.add_argument("--movies", action="store_true")
    ap.add_argument("--music", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    a = ap.parse_args()
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()
    everything = not (a.records or a.textures or a.audio or a.movies)
    if everything or a.records:
        d = disc.Disc(find_disc(a.disc))
        print("records:", len(extract_records(d, out, a.overwrite)))
    if everything or a.textures:
        print("textures:", extract_textures(out, a.overwrite))
    if a.movies:
        print("movies:", extract_movies(disc.Disc(find_disc(a.disc)), out, a.overwrite))
    if a.music:
        print("music:", extract_xa(disc.Disc(find_disc(a.disc)), out, a.overwrite))
    if everything or a.audio:
        cue = find_disc(a.disc)
        print("audio files:", extract_audio(disc.Disc(cue), cue, out, a.overwrite))
main()
