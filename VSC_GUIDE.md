# Running the coldclouds MHD suite on the VSC (KU Leuven)

Step-by-step guide, validated end-to-end. Everything below follows the course
instructions (`infoforVSCruns2026-1.pdf`) adapted to this repo. Commands are
meant to be copy-pasted in order.

Conventions used throughout:
- cluster: **wice** (never compile or run on the login node!)
- account: **lp_edu_amrvac**
- AMRVAC version: **amrvac3.3** branch of the official repo
- run directory: `$VSC_DATA/coldclouds_mhd`

---

## 0. One-time setup (skip if already done)

On the login node (ondemand → "login server shell" app):

```bash
# .bashrc additions (from the course PDF) — do this once
cat >> ~/.bashrc << 'EOF'

export AMRVAC_DIR="$HOME/amrvac"
export PATH=".:$AMRVAC_DIR:$AMRVAC_DIR/tools:$PATH"
case ${VSC_INSTITUTE_CLUSTER} in
  wice)
    module load foss/2025a
    ;;
esac
alias myjobs="squeue -M wice"
EOF
source ~/.bashrc

# install MPI-AMRVAC (once)
cd $HOME
git clone https://github.com/amrvac/amrvac.git
cd amrvac
git checkout amrvac3.3
```

## 1. Get the coldclouds files onto the cluster

On the login node:

```bash
mkdir -p $VSC_DATA/coldclouds_mhd
cd $VSC_DATA/coldclouds_mhd
```

Then copy the content of `mhd/Fl10/` from the coldclouds repo (branch
`devin/mhd-runs`) into this directory: `mod_usr.t`, `makefile`, and the
`MHD*.par` files. Two ways:

**Option A — git clone (needs GitHub access to the private repo):**

```bash
module load git  # if git is not available by default
# use a personal access token as password when asked.
# NOTE: use a fresh private temp dir (never a fixed /tmp path on a shared
# login node — another user could pre-create it with malicious content):
TMPD=$(mktemp -d)
git clone --branch devin/mhd-runs https://github.com/hugocamba-FTW/coldclouds.git "$TMPD/cc"
cp "$TMPD"/cc/mhd/Fl10/* $VSC_DATA/coldclouds_mhd/
cp "$TMPD"/cc/run_series.sh $VSC_DATA/coldclouds_mhd/
rm -rf "$TMPD"
```

**Option B — upload through the ondemand Files tab:**
browse to `$VSC_DATA/coldclouds_mhd` in the Files app and upload the files
from your laptop (select all files inside `mhd/Fl10`).

## 2. Compile (interactive session on wice)

Compilation must happen on wice, not on the login node. Ask for an
interactive session — either via the ondemand interactive app (choose
partition **batch**, account **lp_edu_amrvac**) or from a login-node shell:

```bash
srun --nodes=1 --ntasks-per-node=8 -t 1:00:00 -A lp_edu_amrvac --cluster=wice --pty bash -l
```

Once the session starts:

```bash
module load cluster/wice/batch
module load foss/2025a
cd $VSC_DATA/coldclouds_mhd
export AMRVAC_DIR=$HOME/amrvac
touch amrvac.h     # needed once, the makefile's parallel build can race otherwise
make -j8
```

This takes several minutes (it builds the whole libamrvac library once).
Success = an executable called `amrvac` appears in the directory. Keep this
interactive session open for the next step.

## 3. Test run — directly (interactive)

Still inside the interactive session:

```bash
cd $VSC_DATA/coldclouds_mhd
mkdir -p output/MHD3A_test          # AMRVAC does not create output dirs itself
mpirun -np 8 ./amrvac -i MHD3A_test.par 2>&1 | tee MHD3A_test.out
```

The test runs at AMR level 4 on a 64^3 base grid up to t=0.5 (≈4 Myr) and
should finish in a few minutes. Success = last lines say
`Finished AMRVAC` and `output/MHD3A_test/` contains `*.dat` and `*.vtu`
snapshots plus `MHD3A_test.log`.

Type `exit` to release the interactive session when done.

## 4. Test run — as a batch job

From the **login node** (exit any interactive session first):

```bash
cd $VSC_DATA/coldclouds_mhd
sbatch job_test.slurm
```

`job_test.slurm` (in this repo under `vsc/`, copy it next to the par files)
runs the same test on 36 cores. Track it with `myjobs` (alias for
`squeue -M wice`); stdout lands in `slurm-<jobid>.out`. You get mail at
begin/end/fail if you put your address in the script.

## 5. Production runs

`job_run.slurm` is the production template:

```bash
# edit job_run.slurm: set PAR=MHD3A.par (or any other), adjust time/nodes
sbatch job_run.slurm
```

Resource guidance for the level-8, t=18 production runs (effective resolution
up to 512^3–8192^3 depending on refinement; ~150 Myr of evolution):

| scale | nodes × tasks/node | walltime (guess) |
|-------|--------------------|------------------|
| first production try | 1 × 72 | 24 h |
| production | 2–4 × 72 | 12–48 h |

Start conservative; check the timestep rate (`dt_wall` lines in the `.out`
file) after the first hour and rescale.

Notes:
- wice has at most **72 tasks per node**.
- For big runs, output should go to **scratch** (parallel IO; `$VSC_DATA` IO
  is serial). Redirect by editing `base_filename` in the par, e.g.:
  `base_filename = '/scratch/leuven/3xx/vsc3xxxx/coldclouds_out/MHD3A/MHD3A'`
  — scratch is wiped after 21 days, copy back what you want to keep.
- Check quota with `myquota` (75 GB on `$VSC_DATA`).

## 6. Running several pars in one job

`run_series.sh` (repo root) runs a list of pars sequentially inside one
allocation — useful for the smaller runs. In a job script:

```bash
./run_series.sh -n $SLURM_NTASKS -e ./amrvac MHD1N.par MHD1A.par MHD1Na.par
```

For the big level-8 runs prefer one job per par instead (parallelism across
jobs), submitted in a loop:

```bash
for p in MHD1N MHD1A MHD1Na MHD1Ai; do
  sed "s/^#SBATCH --job-name=.*/#SBATCH --job-name=$p/; s/^PAR=.*/PAR=$p.par/" \
      job_run.slurm | sbatch
done
```

## 7. Visualization

- Quick look on the cluster: Paraview is available as an ondemand app.
- python/yt: see `vsc/viz_yt.py` in this repo — reads the `.vtu` snapshots
  (via VTK), loads them into yt, and writes slice/projection plots. Run it
  on the login node or copy the `.vtu` files to your laptop through the
  ondemand Files tab and run it locally. Tested against real MHD3A_test
  output.

## Troubleshooting

| symptom | fix |
|---------|-----|
| `Can't write to output directory` | `mkdir -p` the directory part of `base_filename` |
| `ERROR for processor` in stdout | the line itself is the real error; MPI_ABORT noise after it is cleanup |
| build fails with 0-byte `*.f` files | delete stale `*.f` in the lib dir and rebuild |
| module conflicts | `module purge`, then load only `foss/2025a` |
| job pending forever | check `myjobs`; course account is shared, try fewer nodes or shorter walltime |
