import struct
from pathlib import Path
SECTOR = 2352
USER_OFFSET = 24
USER_SIZE = 2048
BNS_TABLE_VA = 0x80024400
BNS_TABLE_COUNT = 303
EXE_LOAD = 0x80010000
EXE_HEADER = 0x800
class Disc:
    def __init__(self, path):
        path = Path(path)
        if path.suffix.lower() == ".cue":
            text = path.read_text(errors="replace")
            name = next(line.split('"')[1] for line in text.splitlines() if line.strip().startswith("FILE"))
            path = path.parent / name
        self.path = path
        self.f = open(path, "rb")
        self.files = {}
        self._walk_root()
    def sector(self, lba):
        self.f.seek(lba * SECTOR + USER_OFFSET)
        return self.f.read(USER_SIZE)
    def read(self, lba, size):
        n = (size + USER_SIZE - 1) // USER_SIZE
        return b"".join(self.sector(lba + i) for i in range(n))[:size]
    def _walk_root(self):
        pvd = self.sector(16)
        if pvd[1:6] != b"CD001":
            raise ValueError("not an ISO9660 data track")
        self._walk(struct.unpack("<I", pvd[158:162])[0], struct.unpack("<I", pvd[166:170])[0], "")
    def _walk(self, lba, size, prefix):
        data = self.read(lba, size)
        o = 0
        while o < len(data):
            n = data[o]
            if n == 0:
                o = (o // USER_SIZE + 1) * USER_SIZE
                continue
            extent, length = struct.unpack("<I", data[o + 2:o + 6])[0], struct.unpack("<I", data[o + 10:o + 14])[0]
            flags = data[o + 25]
            name = data[o + 33:o + 33 + data[o + 32]].decode("latin1")
            if name not in ("\x00", "\x01"):
                if flags & 2:
                    self._walk(extent, length, prefix + name + "/")
                else:
                    self.files[(prefix + name).split(";")[0]] = (extent, length)
            o += n
    def file(self, name):
        lba, size = self.files[name]
        return self.read(lba, size)
    def file_range(self, name, offset, size):
        lba, total = self.files[name]
        first = offset // USER_SIZE
        skip = offset - first * USER_SIZE
        return self.read(lba + first, skip + size)[skip:skip + size]
def bns_table(disc):
    exe = disc.file("TEKKEN3/SLUS_004.02")
    base = BNS_TABLE_VA - EXE_LOAD + EXE_HEADER
    return [struct.unpack_from("<II", exe, base + 8 * i) for i in range(BNS_TABLE_COUNT)]
LOGICAL_MAP_VA = 0x80098574
def logical_map(disc, count=BNS_TABLE_COUNT):
    exe = disc.file("TEKKEN3/SLUS_004.02")
    base = LOGICAL_MAP_VA - EXE_LOAD + EXE_HEADER
    return list(struct.unpack_from("<%dH" % count, exe, base))
def xa_sector(disc, lba):
    disc.f.seek(lba * SECTOR)
    raw = disc.f.read(SECTOR)
    if raw[:12] != b"\x00" + b"\xff" * 10 + b"\x00" or raw[15] != 2:
        raise ValueError("not a mode 2 sector at LBA %d" % lba)
    form2 = bool(raw[18] & 0x20)
    return {"file": raw[16], "channel": raw[17], "submode": raw[18], "coding": raw[19], "data": raw[24:24 + (2324 if form2 else 2048)]}
