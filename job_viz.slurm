#!/bin/bash -l
#SBATCH --job-name=viz
#SBATCH -t 00:30:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH -A lp_edu_amrvac

# Visualization job: renders yt plots from .vtu snapshots.
# Usage: sbatch job_viz.slurm          (edits viz target below)
# First run builds a python venv in $VSC_DATA/venv-viz (~5 min); later
# runs reuse it and finish in a couple of minutes.

module load cluster/wice/batch 2>/dev/null
module load Python/3.13 2>/dev/null || module load Python/3.12 2>/dev/null || module load Python 2>/dev/null

cd $VSC_DATA/coldclouds_mhd

VENV=$VSC_DATA/venv-viz
if [ ! -f "$VENV/bin/activate" ]; then
  echo "creating venv (first time only)..."
  python3 -m venv "$VENV"
  source "$VENV/bin/activate"
  pip install -q --upgrade pip
  pip install -q yt vtk numpy
else
  source "$VENV/bin/activate"
fi

# --- edit these per run ---
VTU=output/MHD3A_test/MHD3A_test0005.vtu
FIELD=rho
WIDTH=4
RES=256
AXIS=z
# ---

mkdir -p viz
python3 viz_yt.py "$VTU" --res $RES --field "$FIELD" --width $WIDTH --axis $AXIS --out "viz/$(basename $VTU .vtu)_$FIELD" || { echo "VIZ FAILED"; exit 1; }
echo "plots in $VSC_DATA/coldclouds_mhd/viz/"
ls viz/
