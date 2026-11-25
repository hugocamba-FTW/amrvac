#!/bin/bash -l
#SBATCH --job-name=MHD3A_test
#SBATCH -t 00:30:00
#SBATCH --cluster=wice
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=36
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=youremailadres@student.kuleuven.be
#SBATCH -A lp_edu_amrvac

# Test run: MHD3A_test.par (AMR level 4, t_max=0.5).
# Submit from the login node, inside $VSC_DATA/coldclouds_mhd:
#   sbatch job_test.slurm

module load foss/2025a
cd $VSC_DATA/coldclouds_mhd

mkdir -p output/MHD3A_test
mpirun -np $SLURM_NTASKS ./amrvac -i MHD3A_test.par
