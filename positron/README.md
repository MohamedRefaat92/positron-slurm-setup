# Part 2: Positron settings and troubleshooting

Goal: Positron starts your project's own R and Python, and its consoles start reliably on slow cluster storage. Examples assume R from a conda env in `./env` (packages via renv) and Python from a uv env in `./.venv`, as in the [hyprid_proj](https://github.com/MohamedRefaat92/hyprid_proj) template. Checked with Positron 1.138.

## Settings

| Setting | Where | Value | Why |
|---|---|---|---|
| `remoteSSH.transport` | user | `"native"` | Use your `~/.ssh/config` ([Part 1](../ssh/README.md)) |
| `kernelSupervisor.connectionTimeout` | user | `120` | Seconds to wait for a console to start (default 30 is too short on cluster storage) |
| `positron.r.interpreters.condaDiscovery` | workspace | `true` | Otherwise Positron doesn't look for R inside conda envs |

*User* settings are yours, on every project ([`settings.user.jsonc`](settings.user.jsonc)). *Workspace* settings go in the project's `.vscode/settings.json`.

Also set R's `repos` in the project's `.Rprofile`. Otherwise Positron may pick precompiled binaries built for a standard R, which don't suit conda's R.

## The wrong R or Python starts

| Symptom | Fix |
|---|---|
| A system R starts instead of the project's | Turn on `condaDiscovery`, then pick **R x.y.z (Conda: env)** |
| The project's R isn't listed | Command Palette → **Discover All Interpreters** |
| Several **R (Conda: env)** entries | Every project's `./env` gets the same label: choose by the path shown underneath |
| **Unsupported: Python 3.x (Conda)** fails | That's the conda env's own Python; pick the project's **uv** interpreter |

## A console won't start: "Request failed with status code 500"

That only means the console didn't connect in time. The reason is in **View → Output → Kernel Supervisor**:

- a traceback → the console crashed; fix what it names;
- `Timeout waiting for handshake` / `Timed out waiting to connect` → it was just too slow.

For slowness, in order of effect:

1. **Run on a compute node** ([Part 3](../remote/README.md)). On BMRC, a login shell took 13 s on the login node and 1 s on a compute node.
2. **Stop renv's startup check.** It scans the whole project every time R starts (R took 41 s on a compute node; 6 s without it). In `.Rprofile`, before renv activates:
   ```r
   options(renv.config.synchronized.check = FALSE)   # renv::status() still checks on demand
   ```
   Keep data and output folders out of renv's scans with `.renvignore`.
3. **Raise `kernelSupervisor.connectionTimeout`** (above).
4. **Keep `~/.bashrc` short.** Consoles start through a login shell, which runs it every time.

After changing settings, open a new window.

## Memory on the login node

Positron's memory panel shows the whole machine, not your share. On BMRC's login node you get 26 GiB in total for everything you run there, including Positron's own server (2–3 GB). Going over kills a process, usually the console holding your data. Load large data on a compute node.
