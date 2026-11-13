# Positron settings and troubleshooting for HPC work

Connecting is covered in [`ssh/`](../ssh/); this section is about what comes after: Positron finding the right R and Python, and kernels that start reliably on cluster storage. Running on a compute node instead of the login node is covered in [`remote/`](../remote/).

The examples assume a project laid out like the [hyprid_proj](https://github.com/MohamedRefaat92/hyprid_proj) template: R from a conda environment in `./env` (packages managed by renv), Python from a uv environment in `./.venv`. The principles apply to any project where R or Python lives in a project-local environment.

Checked against Positron 1.138.

---

## 1. Settings

Settings live in two places, and it matters which:

- **User settings** (`settings.json` on your machine, or the **Remote** tab while connected): things that depend on the *machine*, such as timeouts.
- **Workspace settings** (`.vscode/settings.json` in the project, committed): things that depend on the *project*, such as where its interpreters are.

| Setting | Where | Value | Why |
|---|---|---|---|
| `remoteSSH.transport` | user | `"native"` | Use the system `ssh` and your `~/.ssh/config` (see [`ssh/`](../ssh/README.md#4-positron-setting)) |
| `kernelSupervisor.connectionTimeout` | user | `120` | Seconds Positron waits for a new kernel to connect (default 30). Too short for cluster storage; see [section 4](#4-a-kernel-wont-start-request-failed-with-status-code-500) |
| `positron.r.interpreters.condaDiscovery` | workspace | `true` | Positron doesn't look inside conda environments for R otherwise ([section 2](#2-the-wrong-r-starts-or-the-projects-r-is-missing)) |

A user settings template with comments is in [`settings.user.jsonc`](settings.user.jsonc).

**Package repositories:** Positron sets R's `repos` option when R's startup files don't (`positron.r.defaultRepositories`, default `auto`), and can choose Posit Package Manager's precompiled binaries. Those are built for a standard R, not for conda's R, which must install from source. Set `repos` in the project's `.Rprofile` (the template does), and Positron leaves it alone.

---

## 2. The wrong R starts, or the project's R is missing

Positron's R console always runs through its own R kernel, **Ark**. Ark is never the problem; *which R Ark starts* is.

| Symptom | Cause | Fix |
|---|---|---|
| The console starts a system R (e.g. `/Library/Frameworks/R.framework` on a Mac), and the project's `.Rprofile` complains that it isn't the project's R | Positron looks for R only in standard places; a conda env isn't one | Turn on `positron.r.interpreters.condaDiscovery` in the workspace settings, then pick **R x.y.z (Conda: env)** |
| The setting is on, but this project's R is still not listed | Positron caches the R installations it found, and searches again only when the standard R locations or its R settings change. A new conda env doesn't trigger a search | Command Palette → **Discover All Interpreters** |
| Several entries read **R x.y.z (Conda: env)** | Conda names an env after its folder, so every project with an `./env` gets the same label | Choose by the path shown under the label. On the cluster, a session once started another project's R: the supervisor log showed `conda activate /…/other-project/env` |

With `condaDiscovery`, Positron *activates* the conda env before starting R: the supervisor runs it in a login shell (`bash -l`, which reads your `~/.bashrc`) followed by `conda activate`. On a cluster both are slow, and the time counts against the kernel timeout ([section 4](#4-a-kernel-wont-start-request-failed-with-status-code-500)).

**An alternative worth trying** (not yet tested in this setup): point Positron straight at the project's R. `positron.r.customBinaries` and `positron.r.interpreters.default` accept `${workspaceFolder}`, so this is not a hard-coded path:

```jsonc
// .vscode/settings.json
"positron.r.customBinaries": ["${workspaceFolder}/env/bin/R"],
"positron.r.interpreters.default": "${workspaceFolder}/env/bin/R"
```

That would make Positron start the right R in every project automatically, without conda activation. It relies on the project's `.Rprofile` setting up what activation normally would (`PATH`, compilers); the template's does.

---

## 3. Python

| Symptom | Cause | Fix |
|---|---|---|
| **Unsupported: Python 3.x (Conda)** is offered, and fails with `module 'typing' has no attribute 'no_type_check_decorator'` | That's the conda env's own Python (it runs JupyterLab, not your analysis). It can be newer than Positron supports: Python 3.15 removed something Positron's kernel code still uses | Pick the project's uv interpreter, **Python 3.x.y (uv: \<project\>)** |
| `.vscode/settings.json` gains `"python-envs.defaultEnvManager": "ms-python.python:conda"` and a matching `defaultPackageManager` line | The Python Environments extension writes them when a manager is picked in its panel | Discard them (`git checkout .vscode/settings.json`) if uv manages the project's Python |

---

## 4. A kernel won't start: "Request failed with status code 500"

The message only says the kernel supervisor gave up. The reason is in its log:

- **Command Palette → Kernel Supervisor: Show the Kernel Supervisor Log**, or **View → Output → Kernel Supervisor**
- on the remote machine: `/tmp/kallichore-*.log` (one per Positron session; newest first with `ls -t /tmp/kallichore-*`)
- each kernel's own log: `/tmp/kernel-*/kernel.log`

```bash
grep -E "ERROR" "$(ls -t /tmp/kallichore-*.log | grep -v out | head -1)" | tail -20
```

How to read it:

| Log says | Meaning |
|---|---|
| `KS-14: The kernel exited before a connection could be established`, followed by a traceback | The kernel crashed. Fix what the traceback names |
| `Timeout waiting for handshake` (R) or `Timed out waiting to connect to session's ZeroMQ sockets after 30 seconds` (Python), with empty output | Nothing crashed: the kernel was too slow to start |

**When it's a timeout, time the pieces** from the project folder, on the machine where Positron runs:

```bash
time bash -lic exit                                   # login shell (kernels start in one)
time .venv/bin/python -c "import ipykernel"           # Python kernel's main import
time env/bin/R --quiet --no-echo -e 'invisible(0)'    # R with the project's startup files
```

Compare `real` with `user`. If `real` is much larger, the time goes to *waiting* (usually on the filesystem), not computing. Measured on BMRC with a large single-cell project (R and Python on GPFS):

| | Login node | Compute node |
|---|---|---|
| `bash -lic exit` | 13 s (0.7 s user) | 1.1 s |
| `import ipykernel` | 8 s (0.2 s user) | 1.4 s |
| R startup, renv checking the project at startup | 3 min 30 s | 41 s |
| R startup, that check turned off | | 6 s |

**Fixes, in order of effect:**

1. **Make R's startup cheap.** renv compares the library with the lockfile at every R start, and to do so scans every file in the project for package use: 20 to 90 s on cluster storage. Turn it off in `.Rprofile`, before renv activates; `renv::status()` still runs it on demand:
   ```r
   options(renv.config.synchronized.check = FALSE)
   ```
   Also keep folders that hold no code out of renv's scans with `.renvignore` (`data/`, `output/`, the environments). renv follows symlinks, so a `data/` folder of linked datasets is expensive even when it looks small. Notebooks with large saved outputs are slow to scan too.
2. **Raise `kernelSupervisor.connectionTimeout`** (user settings, e.g. `120`).
3. **Keep `~/.bashrc` light.** Kernels start in a login shell, so every line in it runs before each kernel.
4. **Run Positron on a compute node** ([`remote/`](../remote/)). The figures above show why.

After changing settings, open a new window or run **Kernel Supervisor: Restart the Kernel Supervisor**. A supervisor left over from an earlier session can be stopped on the remote with `pkill -u $USER -f kallichore`.

---

## 5. Memory on a shared login node

Positron's memory panel shows the **whole machine**: total RAM, everyone else's use ("Other") and what's free. It doesn't show your own limit, which on a login node is usually much lower. Check it:

```bash
cat /sys/fs/cgroup/memory/user.slice/user-$(id -u).slice/memory.limit_in_bytes 2>/dev/null \
 || cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/memory.max
```

On BMRC's login node it is 26.3 GiB, for everything you run there together: Positron's server and extensions (2–3 GB), every kernel and every terminal. Going over gets a process killed, usually the kernel holding your data. Load large objects on a compute node.
