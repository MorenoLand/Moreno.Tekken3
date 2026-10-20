import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import disc
import formats
import audio
import models
import pose
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
def extract_models(d, out, overwrite):
    n = 0
    exe = pose.Exe(d.file("TEKKEN3/SLUS_004.02"))
    motion, skel = pose.Motion(exe), pose.Pose(exe)
    common = (out / "bns" / "279.bin").read_bytes()
    for p in sorted((out / "bns").glob("*.3dmk")):
        fighter = (int(p.stem) - 71) // 4
        model = p.read_bytes()
        character = (out / "bns" / ("%03d.bin" % (int(p.stem) + 3))).read_bytes()
        world = pose.skeleton(model, skel, pose.idle_pose(motion, character, common), pose.FACING)
        poses = [world.get(s, (pose.IDENTITY, [0, 0, 0])) for s in range(32)]
        arc = out / "bns" / ("%03d" % (int(p.stem) + 2)) / "00.tim"
        vram = formats.compose_vram(formats.tim_stream(arc.read_bytes())) if arc.exists() else None
        surfaces = {}
        parts = []
        for m in models.build_parts(model, poses):
            bykey = {}
            for poly in m["polys"]:
                key = (poly["page"], poly["clut"])
                surf = bykey.setdefault(key, {"tex": surfaces.setdefault(key, len(surfaces)), "idx": [], "uv": []})
                v, uv = poly["verts"], poly["uv"]
                order = [0, 1, 2] if len(v) == 3 else [0, 1, 2, 2, 1, 3]
                surf["idx"] += [v[k] for k in order]
                surf["uv"] += [c for k in order for c in uv[k]]
            parts.append({"part": m["part"], "verts": [list(v) for v in m["verts"]], "surfaces": list(bykey.values())})
        folder = out / "models" / p.stem
        n += write(folder / "model.json", json.dumps(parts, separators=(",", ":")).encode(), overwrite)
        if vram:
            for (page, clut), k in surfaces.items():
                target = folder / ("surface_%02d.png" % k)
                if overwrite or not target.exists():
                    formats.write_png(target, 256, 256, formats.decode_page(vram, page, clut))
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("disc", nargs="?")
    ap.add_argument("-o", "--output", default=str(Path(__file__).resolve().parent.parent / "assets"))
    ap.add_argument("--records", action="store_true")
    ap.add_argument("--textures", action="store_true")
    ap.add_argument("--audio", action="store_true")
    ap.add_argument("--models", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    a = ap.parse_args()
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()
    everything = not (a.records or a.textures or a.audio or a.models)
    if everything or a.records:
        d = disc.Disc(find_disc(a.disc))
        print("records:", len(extract_records(d, out, a.overwrite)))
    if everything or a.textures:
        print("textures:", extract_textures(out, a.overwrite))
    if everything or a.models:
        print("models:", extract_models(disc.Disc(find_disc(a.disc)), out, a.overwrite))
    if everything or a.audio:
        cue = find_disc(a.disc)
        print("audio files:", extract_audio(disc.Disc(cue), cue, out, a.overwrite))
main()
