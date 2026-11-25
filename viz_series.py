#!/usr/bin/env python3
"""
viz_series.py — time-series visualization of AMRVAC .vtu snapshots.

Renders every snapshot matching a glob pattern with a FIXED color scale
across the whole series, then produces:
  1. an animated GIF cycling through the slices
  2. a side-by-side montage of at most 5 evenly spaced snapshots

Usage:
    python viz_series.py "output/MHD3A_test/*.vtu" [--field rho] [--axis z]
        [--width 4] [--res 256] [--out series/rho] [--fps 2]

Requirements: pip install yt vtk numpy matplotlib imageio
(uses probe_uniform/read_vtu from viz_yt.py, which must be in the same dir)
"""

import argparse
import glob
import sys

import numpy as np

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, Normalize

import imageio.v2 as imageio

from viz_yt import read_vtu, probe_uniform


def snapshot_time(fname):
    """Read the TIME scalar AMRVAC embeds in the vtu FieldData (code units)."""
    import re
    with open(fname, 'rb') as fh:
        head = fh.read(8192).decode('ascii', errors='ignore')
    m = re.search(r'Name="TIME"[^>]*>\s*([0-9.eE+-]+)', head)
    return float(m.group(1)) if m else None


def midplane(arr, axis):
    """Slice a 3D x-fastest array through the central plane of `axis`."""
    idx = {'x': 0, 'y': 1, 'z': 2}[axis]
    n = arr.shape[idx] // 2
    return np.take(arr, n, axis=idx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pattern', help='glob pattern for the snapshots, e.g. "output/MHD3A_test/*.vtu"')
    ap.add_argument('--field', default='rho')
    ap.add_argument('--axis', default='z')
    ap.add_argument('--width', type=float, default=None)
    ap.add_argument('--res', type=int, default=256)
    ap.add_argument('--out', default='series')
    ap.add_argument('--fps', type=float, default=2.0)
    ap.add_argument('--montage', type=int, default=5, help='max frames in the side-by-side panel')
    ap.add_argument('--time-unit', type=float, default=8.4,
                    help='Myr per code time unit (8.4 for the Fl10 setup: '
                         'unit_length=1 kpc, unit_temperature=1e6 K)')
    args = ap.parse_args()

    files = sorted(glob.glob(args.pattern))
    if not files:
        print(f"no files match {args.pattern}")
        return 1
    print(f"{len(files)} snapshots: {files[0]} .. {files[-1]}")

    # pass 1: probe all snapshots, keep the midplane slices
    zoom = args.width * 1.5 if args.width else None
    frames, times_ok = [], []
    extent = None
    for f in files:
        print(f"probing {f} ...")
        grid = read_vtu(f)
        fields, fbbox, dx = probe_uniform(grid, args.res, zoom=zoom, axis=args.axis)
        if args.field not in fields:
            print(f"  field {args.field} not in {sorted(fields)}, skipping")
            continue
        frames.append((f, midplane(fields[args.field], args.axis), snapshot_time(f)))
        # plot-plane extents in kpc for axis labels
        plane = {'x': (fbbox[1], fbbox[2]), 'y': (fbbox[0], fbbox[2]), 'z': (fbbox[0], fbbox[1])}[args.axis]
        extent = [plane[0][0], plane[0][1], plane[1][0], plane[1][1]]
    if len(frames) < 2:
        print("need at least 2 usable snapshots")
        return 1

    # fixed color scale from global percentiles of positive values
    allvals = np.concatenate([fr[1].ravel() for fr in frames])  # fr = (file, slice, time)
    pos = allvals[allvals > 0]
    if len(pos) and np.all(allvals >= 0):
        vmin, vmax = np.percentile(pos, 1), np.percentile(pos, 99.9)
        norm = LogNorm(vmin=max(vmin, pos.min()), vmax=vmax)
    else:
        vmin, vmax = np.percentile(allvals, 1), np.percentile(allvals, 99.9)
        norm = Normalize(vmin=vmin, vmax=vmax)
    print(f"fixed color scale: [{norm.vmin:.3g}, {norm.vmax:.3g}]")

    xlab, ylab = {'x': ('y', 'z'), 'y': ('x', 'z'), 'z': ('x', 'y')}[args.axis]

    def render(ax, data, title):
        im = ax.imshow(data.T, origin='lower', norm=norm, cmap='viridis',
                       extent=extent, aspect='equal')
        ax.set_xlabel(f"{xlab} (kpc)"); ax.set_ylabel(f"{ylab} (kpc)")
        ax.set_title(title, fontsize=9)
        return im

    def tag_of(f, t):
        tag = f.split('/')[-1].rsplit('.vtu', 1)[0]
        if t is not None:
            tag += f"  —  t = {t * args.time_unit:.1f} Myr"
        return tag

    # pass 2: gif frames, uniform figure size so the animation doesn't jitter
    import os
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    pngs = []
    for i, (f, data, t) in enumerate(frames):
        fig, ax = plt.subplots(figsize=(5.2, 4.6), dpi=110)
        im = render(ax, data, f"{args.field} — {tag_of(f, t)}")
        fig.colorbar(im, ax=ax, label=args.field)
        fig.tight_layout()
        png = f"{args.out}_frame{i:03d}.png"
        fig.savefig(png)
        plt.close(fig)
        pngs.append(png)
    gifpath = f"{args.out}_series.gif"
    # pillow expects duration in milliseconds
    with imageio.get_writer(gifpath, mode='I', duration=1000.0 / args.fps, loop=0) as w:
        for png in pngs:
            w.append_data(imageio.imread(png))
        print(f"wrote {gifpath} ({len(pngs)} frames)")

    # pass 3: side-by-side montage of at most --montage evenly spaced frames
    n = min(args.montage, len(frames))
    picks = [frames[int(round(i * (len(frames) - 1) / (n - 1)))] for i in range(n)] if n > 1 else [frames[0]]
    fig, axes = plt.subplots(1, n, figsize=(3.4 * n, 3.8), dpi=110)
    if n == 1:
        axes = [axes]
    im = None
    for ax, (f, data, t) in zip(axes, picks):
        im = render(ax, data, tag_of(f, t))
    fig.subplots_adjust(right=0.88, wspace=0.35)
    cax = fig.add_axes([0.90, 0.15, 0.015, 0.7])
    fig.colorbar(im, cax=cax, label=args.field)
    montage = f"{args.out}_montage.png"
    fig.savefig(montage)
    plt.close(fig)
    print(f"wrote {montage}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
