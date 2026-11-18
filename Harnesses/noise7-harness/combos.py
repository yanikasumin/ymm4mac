"""Shared case table for NOISE7 verification.

Each case: honke noise type + parameter fields (Animation values and
enum fields). The Python side converts fields to the shader constant
block exactly as MetalNoiseProcessor.renderGenerator does (frame 0);
the generated Swift harness builds the matching NoiseEffectDefinition.
"""
import math
import struct

DEFAULTS = {
    "Strength": 100.0, "Threshold": 0.0, "Levels": 256.0, "Octaves": 5.0,
    "Lacunarity": 2.0, "Gain": 0.5, "WarpStrength": 0.0, "WarpScale": 100.0,
    "X": 0.0, "Y": 0.0, "Z": 0.0, "Size": 100.0,
    "ScaleX": 100.0, "ScaleY": 100.0, "ScaleZ": 100.0, "Angle": 0.0,
    "FractalMode": 0, "DistanceMode": 0, "OutputMode": 0,
    "StripeInterval": 64.0, "StripeWarpAmount": 100.0, "FlowAmount": 100.0,
}

DIS = {
    "Block": "blocknoise_dis.txt", "Perlin": "perlinnoise_dis.txt",
    "Cellular": "cellularnoise_dis.txt", "Voronoi": "voronoinoise_dis.txt",
    "Simplex": "simplexnoise_dis.txt", "Marble": "marble_dis.txt",
    "Flow": "flownoise_dis.txt", "Fractal": "fractalnoise_dis.txt",
    "Random": "randomnoise_dis.txt", "Curl": "curlnoise_dis.txt",
}


def case(name, ntype, color=False, **fields):
    f = dict(DEFAULTS)
    f.update(fields)
    return {"name": name, "type": ntype, "color": color, "fields": f}


CASES = [
    case("block-default", "Block"),
    case("block-oct0", "Block", Octaves=0.0),
    case("block-scale", "Block", ScaleX=25.0, ScaleY=50.0, ScaleZ=200.0),
    case("block-turb", "Block", FractalMode=1),
    case("block-ridge", "Block", FractalMode=2),
    case("block-warp", "Block", WarpStrength=40.0, WarpScale=150.0),
    case("block-angle", "Block", Angle=35.0),
    case("block-offset", "Block", X=13.7, Y=-5.2, Z=3.1),
    case("block-color", "Block", color=True),
    case("block-post", "Block", Levels=2.0, Threshold=50.0, Strength=150.0),
    case("perlin-default", "Perlin"),
    case("perlin-oct0", "Perlin", Octaves=0.0),
    case("perlin-turb", "Perlin", FractalMode=1),
    case("perlin-warp", "Perlin", WarpStrength=25.0),
    case("cell-e-f1", "Cellular"),
    case("cell-e-f2", "Cellular", OutputMode=1),
    case("cell-e-diff", "Cellular", OutputMode=2),
    case("cell-m-f1", "Cellular", DistanceMode=1),
    case("cell-c-f1", "Cellular", DistanceMode=2),
    case("cell-m-diff", "Cellular", DistanceMode=1, OutputMode=2),
    case("cell-oct1-f2", "Cellular", Octaves=1.0, OutputMode=1),
    case("cell-scale", "Cellular", ScaleX=50.0, ScaleY=50.0, ScaleZ=50.0),
    case("vor-cell", "Voronoi"),
    case("vor-edge", "Voronoi", OutputMode=1),
    case("vor-manh-cell", "Voronoi", DistanceMode=1),
    case("vor-cheb-edge", "Voronoi", DistanceMode=2, OutputMode=1),
    case("simplex-default", "Simplex"),
    case("simplex-oct0", "Simplex", Octaves=0.0),
    case("simplex-ridge", "Simplex", FractalMode=2),
    case("simplex-warp", "Simplex", WarpStrength=30.0),
    case("marble-default", "Marble"),
    case("marble-nowarp", "Marble", StripeWarpAmount=0.0),
    case("marble-i16-w300", "Marble", StripeInterval=16.0, StripeWarpAmount=300.0),
    case("marble-scale", "Marble", ScaleX=50.0, ScaleY=50.0, ScaleZ=50.0),
    case("flow-default", "Flow"),
    case("flow-zero", "Flow", FlowAmount=0.0),
    case("flow-300", "Flow", FlowAmount=300.0),
    case("flow-oct2", "Flow", Octaves=2.0),
    # Existing three types (Fractal / Random / Curl). Before the
    # NOISEFIX correction, fractal-cross compensated the port's known
    # differences (Octaves + 1, Scale x64) in gen_harness.py. After
    # the correction the port matches honke directly, so all cases
    # here run with identical parameters on both sides.
    case("fractal-cross", "Fractal", Octaves=4.0),
    case("fractal-default", "Fractal"),
    case("fractal-warp", "Fractal", WarpStrength=40.0, WarpScale=150.0),
    case("fractal-turb", "Fractal", FractalMode=1),
    case("fractal-ridge", "Fractal", FractalMode=2),
    case("random-default", "Random"),
    case("random-warp", "Random", WarpStrength=25.0),
    case("curl-default", "Curl"),
    case("curl-warp", "Curl", WarpStrength=30.0),
    # Round-8 review (R8-03) additions: the octave-loop boundary
    # (Octaves=0 still evaluates once), Curl with non-default
    # FractalMode, and Random combined with the axes that its
    # shader handles differently (angle / scale / offset).
    case("fractal-oct0", "Fractal", Octaves=0.0),
    case("curl-oct0", "Curl", Octaves=0.0),
    case("curl-turb", "Curl", FractalMode=1),
    case("curl-ridge", "Curl", FractalMode=2),
    case("random-axes", "Random", Angle=30.0, ScaleX=150.0, ScaleY=75.0,
         ScaleZ=125.0, X=10.0, Y=-5.0, Z=3.0),
]


def _f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def _bits_f(x):
    return struct.unpack("<I", struct.pack("<f", _f32(x)))[0]


def _bits_i(x):
    return int(x) & 0xFFFFFFFF


def build_cb(fields, seed_offset):
    """Mirror MetalNoiseProcessor.renderGenerator at frame 0.
    Returns (6, 4) uint32 numpy array."""
    import numpy as np
    f = fields
    size = f["Size"]
    scale = lambda v: 100.0 / max(0.001, v * (size / 100.0))
    vals = [
        (_bits_f(math.fmod(f["X"], 123456.789)),
         _bits_f(math.fmod(f["Y"], 154321.0987)),
         _bits_f(math.fmod(f["Z"], 160213.8549)),
         _bits_f(f["Threshold"] / 100.0)),
        (_bits_f(scale(f["ScaleX"])), _bits_f(scale(f["ScaleY"])),
         _bits_f(scale(f["ScaleZ"])), _bits_f(f["Strength"] / 100.0)),
        (_bits_i(int(f["Octaves"])), _bits_i(seed_offset % 1234),
         _bits_i(int(f["Levels"])), _bits_f(-(f["Angle"] * math.pi / 180.0))),
        (_bits_f(f["WarpStrength"]), _bits_f(max(0.01, f["WarpScale"] / 100.0)),
         _bits_i(f["FractalMode"]), _bits_i(f["DistanceMode"])),
        (_bits_i(f["OutputMode"]), _bits_f(f["Lacunarity"]),
         _bits_f(f["Gain"]), _bits_f(0.0)),
        (_bits_f(f["StripeInterval"]), _bits_f(f["StripeWarpAmount"]),
         _bits_f(f["FlowAmount"] / 100.0), _bits_f(0.0)),
    ]
    return np.array(vals, dtype=np.uint32)
