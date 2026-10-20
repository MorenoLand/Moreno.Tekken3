import argparse
import json
import sys
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
        index.append(entry)
    write(out / "bns" / "index.json", json.dumps(index, indent=1).encode(), True)
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
        for i, data in samples:
            if write(out / "audio" / "vab" / ("%03d" % e["id"]) / ("%02d.wav" % i), audio.wav_bytes(audio.adpcm_decode(data), 44100, 1), overwrite):
                n += 1
    for t in audio.cue_tracks(cue):
        if t["mode"] == "AUDIO":
            if write(out / "audio" / "cdda" / ("track%02d.wav" % t["number"]), audio.wav_bytes(audio.cdda_pcm(t), 44100, 2), overwrite):
                n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("disc", nargs="?")
    ap.add_argument("-o", "--output", default=str(Path(__file__).resolve().parent.parent / "assets"))
    ap.add_argument("--records", action="store_true")
    ap.add_argument("--textures", action="store_true")
    ap.add_argument("--audio", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    a = ap.parse_args()
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()
    everything = not (a.records or a.textures or a.audio)
    if everything or a.records:
        d = disc.Disc(find_disc(a.disc))
        print("records:", len(extract_records(d, out, a.overwrite)))
    if everything or a.textures:
        print("textures:", extract_textures(out, a.overwrite))
    if everything or a.audio:
        cue = find_disc(a.disc)
        print("audio files:", extract_audio(disc.Disc(cue), cue, out, a.overwrite))


main()

