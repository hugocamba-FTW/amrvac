#!/bin/bash -l
#SBATCH --job-name=ccrun
#SBATCH -t 12:00:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=72
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=youremailadres@student.kuleuven.be
#SBATCH -A lp_edu_amrvac

# Production run. Pass the par file as argument:
#   sbatch job_run.slurm MHD3A_l5t9.par
# (default: MHD3A.par). Edit walltime/nodes above as needed;
# wice has at most 72 tasks per node.

PAR="${1:-MHD3A.par}"

module load foss/2025a
cd $VSC_DATA/coldclouds_mhd

# create the output directory encoded in the par's base_filename
# (handles both relative 'output/<RUN>/...' and absolute scratch paths)
BASE="$(sed 's/!.*//' "$PAR" | grep -i 'base_filename' | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")"
mkdir -p "$(dirname "$BASE")"

mpirun -np $SLURM_NTASKS ./amrvac -i "$PAR"
