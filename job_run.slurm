#!/bin/bash -l
#SBATCH --job-name=MHD3A
#SBATCH -t 24:00:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=72
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=youremailadres@student.kuleuven.be
#SBATCH -A lp_edu_amrvac

# Production template. Set PAR to the par file to run, then:
#   sbatch job_run.slurm
# For several independent runs, submit one job per par (see VSC_GUIDE.md §6).

PAR=MHD3A.par

module load foss/2025a
cd $VSC_DATA/coldclouds_mhd

# create the output directory encoded in the par's base_filename
# (handles both relative 'output/<RUN>/...' and absolute scratch paths)
BASE="$(sed 's/!.*//' "$PAR" | grep -i 'base_filename' | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")"
mkdir -p "$(dirname "$BASE")"

mpirun -np $SLURM_NTASKS ./amrvac -i "$PAR"
