#!/bin/bash -l
#SBATCH --job-name=vizall
#SBATCH -t 01:00:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH -A lp_edu_amrvac

# Renders yt plots for every snapshot of a run, plus a fixed-scale
# animated gif and a side-by-side montage of up to 5 evenly spaced
# snapshots. Edit the SNAPSHOTS/FIELD/WIDTH lines below, then:
#   sbatch job_viz_all.slurm
# Requires the venv built once by job_viz.slurm ($VSC_DATA/venv-viz).

module load cluster/wice/batch 2>/dev/null
source $VSC_DATA/venv-viz/bin/activate
pip install -q imageio 2>/dev/null   # one-time, tiny; already present afterwards
cd $VSC_DATA/coldclouds_mhd

# --- edit these per run ---
SNAPSHOTS="output/MHD3A_test/*.vtu"
TAG=MHD3A_test
FIELD=rho
WIDTH=4
RES=256
AXIS=z
# ---

mkdir -p viz
for VTU in $SNAPSHOTS; do
  python3 viz_yt.py "$VTU" --res $RES --field "$FIELD" --width $WIDTH --axis $AXIS \
    --out "viz/$(basename $VTU .vtu)_$FIELD" || echo "FAILED $VTU"
done

# series products: animated gif + side-by-side montage, fixed color scale
python3 viz_series.py "$SNAPSHOTS" --field "$FIELD" --width $WIDTH \
  --axis $AXIS --res $RES --out "viz/${TAG}_${FIELD}" || echo "SERIES FAILED"
ls viz/
