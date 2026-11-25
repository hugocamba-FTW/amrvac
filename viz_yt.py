#!/usr/bin/env python3
"""
viz_yt.py — visualize AMRVAC .vtu snapshots with yt.

AMRVAC writes multi-piece VTK UnstructuredGrid files (.vtu), which yt cannot
read natively. This script resamples the cell data onto a uniform grid with
VTK's probe filter, loads the result into yt with yt.load_uniform_grid, and
then uses yt's plotting (SlicePlot / ProjectionPlot) for the actual
visualization.

Usage:
    python viz_yt.py snapshot.vtu [--out PREFIX] [--res 256] [--field rho]
                                  [--axis z] [--width 65]

Requirements: pip install yt vtk numpy

Notes:
- --width is the physical width of the plotted region in code units
  (default: full domain).
- Fields available depend on the par file (saveprim=.true. gives rho, m1..m3,
  e/p, b1..b3, plus tracers if nwauxio=1).
- Resampling resolution: use ~the finest effective AMR resolution you can
  afford. 256^3 is fast; 512^3 is ~8x more memory/time.
"""

import argparse
import sys

import numpy as np

import vtk
from vtk.util import numpy_support


def read_vtu(fname):
    reader = vtk.vtkXMLUnstructuredGridReader()
    reader.SetFileName(fname)
    reader.Update()
    return reader.GetOutput()


def probe_uniform(grid, res, zoom=None, axis='z'):
    """Resample cell data of an unstructured grid onto a uniform image grid.

    zoom: if given, probe only a window of this width centered on the domain
    center (in code units) — much better effective resolution on the cloud.
    The projection axis keeps the full domain depth so projections integrate
    the whole line of sight, and the window is clamped to the domain so no
    probe point falls outside (which would read as a false zero).
    """
    gb = grid.GetBounds()  # (x0,x1,y0,y1,z0,z1)
    if zoom:
        cx = (gb[0] + gb[1]) / 2; cy = (gb[2] + gb[3]) / 2; cz = (gb[4] + gb[5]) / 2
        h = zoom / 2
        x0 = max(cx - h, gb[0]); x1 = min(cx + h, gb[1])
        y0 = max(cy - h, gb[2]); y1 = min(cy + h, gb[3])
        z0 = max(cz - h, gb[4]); z1 = min(cz + h, gb[5])
        # keep full depth along the projection axis
        if axis == 'x': x0, x1 = gb[0], gb[1]
        elif axis == 'y': y0, y1 = gb[2], gb[3]
        else: z0, z1 = gb[4], gb[5]
    else:
        x0, x1, y0, y1, z0, z1 = gb
    nx = ny = nz = res
    # slightly inset the box so probe points stay inside the domain
    eps = 1e-6
    x0, x1 = x0 + eps, x1 - eps
    y0, y1 = y0 + eps, y1 - eps
    z0, z1 = z0 + eps, z1 - eps

    img = vtk.vtkImageData()
    img.SetDimensions(nx, ny, nz)
    img.SetSpacing((x1 - x0) / (nx - 1), (y1 - y0) / (ny - 1), (z1 - z0) / (nz - 1))
    img.SetOrigin(x0, y0, z0)

    # cell data -> point data first, so the probe interpolates
    c2p = vtk.vtkCellDataToPointData()
    c2p.SetInputData(grid)
    c2p.Update()

    probe = vtk.vtkProbeFilter()
    probe.SetInputData(img)
    probe.SetSourceData(c2p.GetOutput())
    probe.Update()
    out = probe.GetOutput()

    fields = {}
    pd = out.GetPointData()
    for i in range(pd.GetNumberOfArrays()):
        arr = pd.GetArray(i)
        if arr.GetNumberOfComponents() != 1:
            continue
        name = arr.GetName()
        if name == 'vtkValidPointMask':
            continue
        data = numpy_support.vtk_to_numpy(arr).reshape((nz, ny, nx), order='C')
        fields[name] = np.ascontiguousarray(data.transpose(2, 1, 0))  # x-fastest for yt
    spacing = ((x1 - x0) / (nx - 1) + (y1 - y0) / (ny - 1) + (z1 - z0) / (nz - 1)) / 3
    return fields, [(x0, x1), (y0, y1), (z0, z1)], spacing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('vtu')
    ap.add_argument('--out', default=None)
    ap.add_argument('--res', type=int, default=256)
    ap.add_argument('--field', default='rho')
    ap.add_argument('--axis', default='z')
    ap.add_argument('--width', type=float, default=None)
    args = ap.parse_args()

    print(f"reading {args.vtu} ...")
    grid = read_vtu(args.vtu)
    print(f"  {grid.GetNumberOfCells()} cells in {grid.GetNumberOfPieces() if hasattr(grid, 'GetNumberOfPieces') else '?'} pieces"
          if hasattr(grid, 'GetNumberOfPieces') else f"  {grid.GetNumberOfCells()} cells")

    zoom = args.width * 1.5 if args.width else None  # probe a bit wider than the plot window
    print(f"probing onto {args.res}^3 uniform grid{f' (zoomed cube of {zoom:.1f} kpc)' if zoom else ''} ...")
    fields, fbbox, dx = probe_uniform(grid, args.res, zoom=zoom, axis=args.axis)
    print("  fields:", sorted(fields))

    import yt
    nx = args.res
    # 1 code length unit = 1 kpc for this setup (unit_length = 3.086e21 cm)
    bbox = np.array(fbbox)
    griddata = {name: (arr, '') for name, arr in fields.items()}
    ds = yt.load_uniform_grid(griddata, [nx, nx, nx], length_unit=(1.0, 'kpc'),
                              bbox=bbox, nprocs=1)

    prefix = args.out or args.vtu.rsplit('.', 1)[0]
    field = args.field if args.field in fields else sorted(fields)[0]
    width = args.width if args.width else None

    print(f"making yt slice of {field} along {args.axis} ...")
    positive = bool(np.all(fields[field] > 0))
    slc = yt.SlicePlot(ds, args.axis, field)
    slc.set_log(field, positive)  # log scale breaks on zero/negative fields (e.g. trp1, b2)
    slc.set_cmap(field, 'viridis')
    if width:
        slc.set_width((width, 'kpc'))
    slc.annotate_title(f"{field} — {args.vtu.split('/')[-1]}")
    out = f"{prefix}_slice_{field}_{args.axis}.png"
    slc.save(out)
    print(f"wrote {out}")

    # a second nice panel: density-weighted projection if density is available
    if 'rho' in fields:
        prj = yt.ProjectionPlot(ds, args.axis, field, weight_field='rho')
        prj.set_cmap(field, 'viridis')
        out2 = f"{prefix}_proj_{field}_{args.axis}.png"
        prj.save(out2)
        print(f"wrote {out2}")


if __name__ == '__main__':
    sys.exit(main())
