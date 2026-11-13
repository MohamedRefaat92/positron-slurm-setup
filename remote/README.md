# Running Positron on a compute node

Connected to the login node, Positron runs its server, its kernels and your analysis *on the login node*. That's fine for editing and quick checks, but not for analysis:

- **It's slow.** Login nodes are shared, and on cluster storage every file read waits. On BMRC a login shell took 13 s there against 1 s on a compute node, and R took minutes to start (figures in [`positron/`](../positron/README.md#4-a-kernel-wont-start-request-failed-with-status-code-500)). Kernels then time out.
- **It's capped.** Your processes on a login node share a per-user memory limit (26.3 GiB on BMRC), and going over gets your kernel killed. See [`positron/`](../positron/README.md#5-memory-on-a-shared-login-node).
- **It's not what login nodes are for.** Many clusters limit or kill heavy processes there.

So the goal is to run Positron's server and kernels on a compute node, inside a Slurm job.

---

## 1. Can you SSH into a compute node?

On many clusters you can, while you have a job running on that node. Test it from the login node:

```bash
srun -p short --time=00:30:00 --pty bash      # terminal 1: note the node with `hostname`
ssh <that-node> hostname                       # terminal 2, while terminal 1's job runs
```

- **It prints the node's name:** use a plain `ProxyJump` through the login node to that node and connect Positron to it. Nothing below is needed.
- **`Connection closed by …`:** the node refuses logins. On BMRC this happens for every login method (`ssh -v` shows the node closing the connection during authentication, whether by Kerberos/GSSAPI or host-based), even with a job running there. The `proxycommand /usr/bin/sss_ssh_knownhostsproxy` that `ssh -G <node>` shows is the system's host-key helper, not the cause. Read on.

---

## 2. The `userd` pattern: your own SSH server inside a Slurm job

When the node's own SSH server won't let you in, a Slurm job can run a **second SSH server under your own account** on a high port. Nodes can still reach each other on high ports, so the login node can forward a connection to it:

```
laptop ──ssh (ControlMaster socket)──▶ login node ──ssh -W node:port──▶ your sshd on the compute node
                                                                         (started by your Slurm job)
```

The laptop side is the `bmrc_compute` host in [`ssh/ssh_config.template`](../ssh/ssh_config.template). Its `ProxyCommand` reads where the server is from a file the job writes, then tunnels through the login node:

```
ProxyCommand bash -c 'read n p < <(ssh -n bmrc_cluster cat .ssh/userd/current_node); exec ssh -W $n:$p bmrc_cluster'
```

**What the job has to provide** (the contract with that config):

- An `sshd` started as **you** (not root), listening on a free high port.
- Its own **host key**, created once and kept in `~/.ssh/userd/` (mode 600), reused on every node. That's why the laptop config uses `HostKeyAlias bmrc_compute`: the node changes with every job, the key doesn't, so `known_hosts` stays valid.
- **Key-only login**: your `~/.ssh/authorized_keys`, password and keyboard-interactive login off, PAM off (a non-root sshd can't use it), only your user allowed.
- The file `~/.ssh/userd/current_node` with one line, `<node-hostname> <port>`, written once the server is up and removed when the job ends. The home folder is shared, so the login node sees it.
- Enough `--time`, `--mem` and `--cpus-per-task` for the whole working session: when the job ends, so does the server and the Positron session.

**Ask the cluster's support first.** A private SSH server is a way around the node's login policy, and some clusters' usage rules forbid it; a short email asking whether it's acceptable protects your account. They may also offer a supported route.

---

## 3. Working on the node

1. Submit the job and wait until it runs (`squeue -u $USER`).
2. On the laptop, make sure the login-node socket is open (`ssh -O check bmrc_cluster`; if not, `ssh bmrc_cluster` and complete 2FA).
3. In Positron: **Remote Explorer → bmrc_compute → Connect**, then open the project folder.
4. When done, cancel the job (`scancel <jobid>`) instead of letting it hold the node until its time limit. Save large objects as you go; a job that hits its limit takes the session with it.

Kernels start quickly there, but the project-side settings in [`positron/`](../positron/README.md#4-a-kernel-wont-start-request-failed-with-status-code-500) still matter: on a BMRC compute node R took 41 s to start until renv's startup check was turned off, and 6 s after.
