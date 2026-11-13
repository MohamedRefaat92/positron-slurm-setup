# positron-slurm-setup

Run [Positron](https://positron.posit.co) on a Slurm cluster's **compute node**, not the crowded login node. Examples use Oxford's BMRC cluster.

## TL;DR

**Once:** connect to the cluster ([Part 1](ssh/README.md)), then put two small scripts on it:

```bash
scp remote/setup_userd.sh remote/positron_node.sbatch bmrc_cluster:   # copy the scripts to your cluster home
ssh bmrc_cluster bash setup_userd.sh                                    # make a key + settings for your own SSH server
```

**Every time:**

```bash
ssh bmrc_cluster                                                         # log in with 2FA; leave it open
ssh bmrc_cluster 'sbatch -o ~/positron_%j.log ~/positron_node.sbatch'   # start a job that runs your SSH server on a compute node
ssh bmrc_cluster 'squeue --me'                                           # wait until the job shows R (running)
positron --folder-uri "vscode-remote://ssh-remote+bmrc_compute/path/to/project"   # open your project on that node
ssh bmrc_cluster 'scancel -n positron'                                   # when done: end the job (closing Positron doesn't)
```

## What's going on

```
Mac: Positron window
  │  ssh bmrc_compute                  your ~/.ssh/config turns this into the route below
  ▼
cluster1.bmrc.ox.ac.uk (login node)    normal SSH on port 22, the connection you opened with 2FA
  │  ssh -W compe020:45930             the login node only passes the bytes on
  ▼
compe020, port 45930 (compute node)    YOUR sshd, running as you inside Slurm job 35162231
  │                                    it wrote "compe020 45930" to ~/.ssh/userd/current_node,
  │                                    which is how your Mac knew where to go
  └─ Positron server
       ├─ R console
       ├─ Python console
       └─ terminals                    all using the job's CPUs and memory
```

BMRC doesn't let you SSH into compute nodes, but it does let your jobs run programs there, and it lets the login node reach them. So a job runs a second SSH server, as you, and the login node relays your connection to it. To Positron, `bmrc_compute` is just another host.

## The guide

| Part | Covers |
|---|---|
| [1. Connect](ssh/README.md) | SSH key, `~/.ssh/config`, logging in once for 2FA |
| [2. Positron settings](positron/README.md) | Making Positron start your project's R and Python; consoles that won't start ("status code 500") |
| [3. Compute node](remote/README.md) | The setup above in detail: how it works, resources, troubleshooting |

## Other clusters

Change the host names in `~/.ssh/config` and the partition (`-p short`) at the top of [`remote/positron_node.sbatch`](remote/positron_node.sbatch). If your cluster lets you SSH into your job's node directly, you don't need Part 3's server at all (see the check at the end of [Part 3](remote/README.md#troubleshooting)).
