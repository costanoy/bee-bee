"""Bee Bee — checks voxel GLBs against STYLE.md: triangle budgets, the cube
grid, T-junctions, size and node names. Plain Python (numpy), no Blender.

  python check_glb.py <file.glb | models_dir> [...] [--vox 0.04]

Per file: triangles (total and per mesh) against the budget for that file
name, the bounding box in cubes in Blender axes (x right, y toward the back,
z up; node transforms applied), whether every vertex sits on the cube grid
(--vox, default 0.04; the sun is 0.3, the backdrops 0.2; a warning only,
since tilted pivots and nudged overlays are off it on purpose), how many
triangle edges have another vertex inside them (T-junctions, which open
hairline cracks in the game), how many triangles face the back (+Y, never
seen unless the model turns), the materials and the vertex colour range (in sRGB, as authored).
Exits with 1 if anything is over budget or has T-junctions.
"""
import json, os, re, struct, sys
import numpy as np

BUDGETS = [  # (file name pattern, triangles): STYLE.md "Budgets"
    (r"hedge_voxel_cap", 1000), (r"hedge_voxel_[abc]\.glb", 2000), (r"bee_voxel", 5000),
    (r"flower_voxel_", 2500), (r"cloud_voxel_a", 2000), (r"cloud_voxel_b", 1500), (r"cloud_voxel_c", 1000),
    (r"gull_voxel", 1500), (r"tree_voxel_", 2500), (r"ground_voxel", 10000), (r"moon_voxel", 8000),
    (r"jupiter_voxel", 8000), (r"ufo_voxel", 8000), (r"sun_voxel", 6000), (r"backdrop_voxel_", 10000),
]


def load(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<III", data, 0)[2]
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    size = np.dtype(comp).itemsize * n
    stride = bv.get("byteStride", 0) or size
    raw = np.frombuffer(binc, np.uint8, count=stride * (a["count"] - 1) + size, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, (a["count"], size), (stride, 1))
    out = rows.copy().view(comp).reshape(a["count"], n).astype(np.float64)
    if a.get("normalized"):
        out /= {np.uint8: 255.0, np.uint16: 65535.0}.get(comp, 1.0)
    return out


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R @ np.diag(n.get("scale", [1, 1, 1]))
    M[:3, 3] = n.get("translation", [0, 0, 0])
    return M


def meshes(js, binc):
    """[(node name, positions in Blender axes, triangles, colours, material names)]"""
    out = []

    def walk(ni, parent):
        n = js["nodes"][ni]
        M = parent @ node_matrix(n)
        if "mesh" in n:
            for p in js["meshes"][n["mesh"]]["primitives"]:
                pos = accessor(js, binc, p["attributes"]["POSITION"])
                pos = (M @ np.c_[pos, np.ones(len(pos))].T).T[:, :3]
                pos = np.c_[pos[:, 0], -pos[:, 2], pos[:, 1]]           # glTF (Y up) -> Blender (Z up)
                idx = accessor(js, binc, p["indices"]).reshape(-1, 3).astype(int) if "indices" in p \
                    else np.arange(len(pos)).reshape(-1, 3)
                colc = accessor(js, binc, p["attributes"]["COLOR_0"]) if "COLOR_0" in p["attributes"] else None
                mat = js["materials"][p["material"]].get("name", "?") if "material" in p else None
                out.append((n.get("name", "?"), pos, idx, colc, mat))
        for c in n.get("children", []):
            walk(c, M)

    for ni in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(ni, np.eye(4))
    return out


def t_junctions(grid, tris):
    """Axis-aligned triangle edges with another vertex of the mesh strictly inside."""
    verts = set(map(tuple, grid))
    bad = 0
    seen = set()
    for t in tris:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            p, q = tuple(grid[a]), tuple(grid[b])
            key = (min(p, q), max(p, q))
            if key in seen:
                continue
            seen.add(key)
            diff = [q[i] - p[i] for i in range(3)]
            axes = [i for i in range(3) if diff[i]]
            if len(axes) != 1 or abs(diff[axes[0]]) < 2:
                continue
            ax, step = axes[0], (1 if diff[axes[0]] > 0 else -1)
            for s in range(1, abs(diff[ax])):
                m = list(p)
                m[ax] += s * step
                if tuple(m) in verts:
                    bad += 1
                    break
    return bad


def budget_for(name):
    for pat, n in BUDGETS:
        if re.search(pat, name):
            return n
    return None


def check(path, vox):
    js, binc = load(path)
    name = os.path.basename(path)
    ms = meshes(js, binc)
    total = sum(len(t) for _, _, t, _, _ in ms)
    budget = budget_for(name)
    ok = budget is None or total <= budget
    allp = np.vstack([p for _, p, _, _, _ in ms]) if ms else np.zeros((1, 3))
    lo, hi = allp.min(0) / vox, allp.max(0) / vox
    print("%s: %d triangles%s" % (name, total, "" if budget is None else
                                   "  (budget %d: %s)" % (budget, "ok" if total <= budget else "OVER")))
    print("  box in cubes: x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  (%.0f x %.0f x %.0f)"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], *(hi - lo)))
    for node, pos, tris, colc, mat in ms:
        # on the grid = every vertex a whole number of cubes from the first
        # one (models centred on a cube, like the bee, sit half a cube off)
        g = pos / vox
        shift = g[0] - np.round(g[0]) if len(g) else np.zeros(3)
        gs = g - shift
        off = float(np.abs(gs - np.round(gs)).max()) if len(g) else 0.0
        tj = t_junctions(np.round(gs).astype(int), tris) if off < 1e-3 else -1
        n = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
        back = int((n[:, 1] > 1e-9 * np.abs(n).max()).sum()) if len(n) else 0
        crange = ""
        if colc is not None:
            # glTF stores linear colour; shown back in sRGB, as authored
            c = np.where(colc[:, :3] <= 0.0031308, colc[:, :3] * 12.92, 1.055 * np.abs(colc[:, :3]) ** (1 / 2.4) - 0.055)
            crange = " sRGB %s..%s" % (np.round(c.min(0), 2).tolist(), np.round(c.max(0), 2).tolist())
            if colc.shape[1] > 3 and colc[:, 3].min() < 0.999:
                crange += " alpha %.2f..%.2f" % (colc[:, 3].min(), colc[:, 3].max())
        flags = []
        if np.abs(shift).max() > 1e-3 and off < 1e-3:
            crange += "  grid offset %s cubes" % np.round(shift, 2).tolist()
        if off >= 1e-3:
            # a warning only: a wing on a tilted pivot or an overlay nudged
            # off its surface is off the grid on purpose (and isn't checked
            # for T-junctions)
            flags.append("off grid by %.3f cubes" % off)
        if tj > 0:
            flags.append("%d T-JUNCTIONS" % tj)
            ok = False
        print("  mesh %-14s %5d tris, %4d back-facing, material %s%s%s"
              % (node, len(tris), back, mat, crange, ("  <- " + ", ".join(flags)) if flags else ""))
    return ok


def main(argv):
    vox = 0.04
    files = []
    i = 0
    while i < len(argv):
        if argv[i] == "--vox":
            vox = float(argv[i + 1])
            i += 2
            continue
        a = argv[i]
        files += sorted(os.path.join(a, f) for f in os.listdir(a) if f.endswith(".glb")) if os.path.isdir(a) else [a]
        i += 1
    ok = all([check(f, vox) for f in files])
    print("ALL OK" if ok else "PROBLEMS FOUND")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
