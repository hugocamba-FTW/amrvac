#!/bin/bash -l
#SBATCH --job-name=build2d
#SBATCH -t 01:00:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH -A lp_edu_amrvac

module load cluster/wice/batch 2>/dev/null
module load foss/2025a
export AMRVAC_DIR=$VSC_HOME/amrvac
cd $VSC_DATA/mhd2d
make -j 8 > build.log 2>&1 && echo "BUILD OK" || echo "BUILD FAILED"
