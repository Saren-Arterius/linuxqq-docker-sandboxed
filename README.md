# QQ in a Docker container

This project runs Tencent QQ Linux on a Linux host inside a Docker container with strict
limits. Tencent QQ is closed-source software. Do not give it your user account. The
container runs as uid 65534 (nobody), with no Linux capabilities and with a fixed network
policy. QQ can reach the internet and your display. QQ cannot reach your files, your
user account, the ports on this computer, or the other computers on your network.

## Disclaimer

An AI model generated both the configuration and this document: Qwen 3.8 Flash Next,
running locally on the author's computer. Nothing was sent to a cloud service to produce them.

Each command in this document ran on one computer (CachyOS, GNOME on Wayland, an NVIDIA
GPU, Docker with a root daemon), and the expected output comes from that run. Nothing was
tested on a second machine. An AI adversarial review was run against this configuration and
the problems it found are fixed; no human security audit was done.

This is not a Tencent project. QQ is closed-source software from another company, and that
company does not support this configuration. Read "What QQ can still do" before you use it.

## Files

| File | Purpose |
| --- | --- |
| `compose.yaml` | The container and the one-time setup service. All limits are in this file. |
| `Dockerfile` | Builds the image from `ubuntu:26.04` and `QQ.deb`. |
| `QQ.deb` | The official Tencent package. Download it yourself; see "Get a new version". |
| `share/` | You and QQ exchange files here. It appears as `/share` inside the container. |
| `share/.xauth` | A copy of your X session cookie. The setup service creates it. |

## Requirements

- Docker Engine and Docker Compose, with the daemon running as root.
- A GNOME session on Wayland. XWayland must run (it runs by default).
- Your user must belong to the `docker` group.
- Do not use `sudo` for the commands in this document. The setup service gets root by
  itself.

## First use

1. Download the package. Use the mirror URL; the direct Tencent URL gives an HTTP 403
   error from most networks:

   ```bash
   curl -fL "https://dlqq.akkariin.moe/$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '(?<="deb":")[^"]+' | head -1)" -o QQ.deb
   ```

2. Build and start:

   ```bash
   docker compose up -d --build
   ```

3. A QQ window opens on your desktop. Log in there. Your login stays in a Docker volume
   and survives a restart.

## Daily use

```bash
docker compose up -d        # start
docker compose stop qq      # stop, keep the login
docker compose logs -f qq   # read the log
```

The container does not start when the computer starts. You start it.

## How the setup service works

`x-grant` runs one time before QQ starts. It runs as root and it runs only the command in
`compose.yaml`. Tencent code does not run in this service. It does four things:

1. It copies your X session cookie to `share/.xauth`, with owner root, group render, and
   mode 640. The container reads that file because it has group 989 (render). A program
   that runs only as uid 65534 cannot read it. This is why the service does not use
   `xhost +si:localuser:nobody`: that command gives your desktop to every program that runs
   as uid 65534, and `dnsmasq` runs as uid 65534 on many hosts.
2. It adds an ACL to `/tmp/.X11-unix/X0` so uid 65534 can connect to the socket. This
   permits a connection only. The cookie is still necessary.
3. It gives `share/` to uid 65534 so QQ can write files there.
4. It installs the firewall rules. See "Network policy".

## Network policy

The container gets its own bridge, `qq-net`, with the fixed subnet `172.26.0.0/24`. The
subnet is part of the security: the rules select it as the source address.

The setup service adds one rule to the `INPUT` chain and one rule to the `DOCKER-USER`
chain. Both rules send the traffic to the chain `QQ_JAIL`. The service clears `QQ_JAIL`
and builds it again at every start, so a change in `compose.yaml` takes effect on the next
`docker compose up`.

`INPUT` carries traffic to a port on this computer. `DOCKER-USER` carries traffic that
passes through this computer to another network. A packet for a local port does not go to
the `FORWARD` chain, so `DOCKER-USER` alone cannot see it. Both chains are necessary.

`QQ_JAIL` permits one destination and blocks the rest:

- Permit: udp port 53 to `127.0.0.11`. Docker answers DNS there. This rule is insurance;
  in a normal test these chains saw no DNS packets at all.
- Block: `224.0.0.0/4`, `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
  `100.64.0.0/10`, `169.254.0.0/16`.
- Permit everything else: the internet. QQ needs it.

The rules live in memory. A restart of the computer removes them. The container also does
not start by itself, so the container never runs without its rules: `x-grant` installs them
first, and QQ starts only if that service exits with 0.

The container has no IPv6 address. It cannot send IPv6 packets.

## Links and the browser

QQ gives a link to `xdg-open`. The container has Firefox, so the page opens in a Firefox
window on your desktop. Firefox runs inside this container, not on the host. The network
rules and every other limit apply to Firefox in the same way they apply to QQ. Firefox
shows the container ID in its window title, so you can tell the two apart.

The firefox package in the Ubuntu archives installs a snap, and a snap cannot run in a
container. The Dockerfile therefore adds the Mozilla APT repository, `packages.mozilla.org`,
and a pin that selects its package. That repository is a third-party download source; it is
the only part of the image that does not come from the Ubuntu archives.

Firefox cannot build its own sandbox here. Docker's seccomp profile refuses the user
namespace that the Firefox sandbox needs, and the container has no capabilities. This is the
same trade as the `--no-sandbox` flag for QQ: the container is the sandbox. Firefox starts
without a window for more than 25 seconds when it creates its profile for the first time;
after that it starts in about 5 seconds.

Firefox keeps its profile, so history, cookies and logins stay in the same volume as QQ.
Delete the volume to remove both. QQ plus one Firefox page uses about 1 GB. The image is
2.56 GB with Firefox in it.

If a Firefox tab shows a crash page, look at the memory limit first, then at `/dev/shm`:
QQ and Firefox share the 2 GB of shared memory that `shm_size` sets.

### WebGL does not work

A page that needs 3-D shows nothing: `canvas.getContext('webgl')` returns no context. Normal
pages, text, images and video work, and QQ itself is not affected.

Firefox runs 3-D in a separate GPU process, and that process does not start in this image. The
process list then shows `forkserver`, `tab`, `rdd`, `socket` and `utility`, and no GPU entry.
WebGL lives in the GPU process, so WebGL is off. Your Firefox on the host does start a GPU
process, which is why the same page works there.

The GPU process needs EGL with a direct rendering device. The image has no NVIDIA user-space
driver, so EGL either opens a card it cannot drive, when the container has `/dev/dri`, or finds
no device at all, when it does not. GLX is not the problem: inside the container, `glxinfo`
reports `direct rendering: Yes` and Mesa llvmpipe with OpenGL 4.5, and Firefox names `Mesa
llvmpipe` as its adapter.

These settings were measured and changed nothing, so do not spend time on them:
`webgl.force-enabled`, `gfx.blocklist.enabled`, `gfx.x11-egl.force-disabled`,
`layers.acceleration.force-enabled`, `gfx.webrender.software`, `widget.dmabuf.force-disabled`,
`gfx.canvas.accelerated`, `--no-sandbox`, `MOZ_DISABLE_GPU_SANDBOX`, and
`LIBGL_ALWAYS_SOFTWARE`. The result was also the same with the container limits removed: with
Docker's seccomp profile off, with all capabilities, with no process limit, and with the NVIDIA
container runtime. The jail is not what breaks WebGL; the image has no 3-D driver that the GPU
process can use.

The fix is to give the container the same NVIDIA user-space the host uses. That puts a
proprietary driver blob and the driver's kernel interface inside the jail, which is the opposite
of what this repository is for, so the container has no GPU device and no NVIDIA libraries. This
is also why `compose.yaml` no longer passes `/dev/dri`: with the device and without it, `glxinfo`
gives the same llvmpipe result, and with it the GPU process fails harder. If you want WebGL in
the jail, mount the host driver libraries and `/dev/dri`, and accept the larger attack surface.

## Limits on the container

| Setting | Value | Reason |
| --- | --- | --- |
| `user` | `65534:65534` | Never your uid. |
| `cap_drop` | `ALL` | No capabilities. Chrome's `chrome-sandbox` SUID file cannot work, so the entry point passes `--no-sandbox`. The container is the sandbox. |
| `security_opt` | `no-new-privileges:true` | A program cannot gain privileges. Docker also applies its default seccomp profile. |
| `read_only`, `tmpfs` | root read-only, `/tmp` noexec | QQ cannot change its own programs. |
| `shm_size` | `2g` | Electron shows a blank window without enough shared memory. QQ and Firefox share it. |
| `pids_limit`, `mem_limit` | 4096, 8 GB | QQ and Firefox cannot use all of your computer. The limit counts threads, and QQ uses about 100 on its own. The host has 91 GB, so the memory limit is a guardrail, not a limit you reach. |
| `group_add` | group 989 | The host group `render`. Gives read access to `share/.xauth`. The container has no GPU device: see "WebGL" below. |
| `/etc/localtime` | mounted read-only | The clock follows the host timezone. After `timedatectl set-timezone`, restart the container: the mount points at the file the symlink selected at start. |
| `--ozone-platform=x11` | in the entry point | QQ on GNOME does not create a Wayland window. Test the XDG protocol and you see no `xdg_toplevel` object. XWayland works. |
| `--disable-crash-reporter` | in the entry point | Crash reports would go to Tencent with your internet traffic. |

## What QQ can still do

Read this part before you rely on the container.

- **Your display, and what is on it.** QQ can read the keyboard and the mouse, list every
  window on your desktop with its title, and read the clipboard. Measured inside the container:
  `xclip -o` returns the clipboard, and `_NET_CLIENT_LIST` lists the other applications with
  their titles. Window titles show file names, page titles and chat partner names. This is how X
  works: the cookie controls who may connect, not what a client may do after it connects. Closing
  QQ removes both channels. A virtual machine is the proportionate next step, because it also
  removes the display; a nested display server (Xpra or Xephyr) works too and costs more setup
  than it saves here.
- **Screen pixels: not readable in this setup.** `GetImage` on a window that QQ does not own
  returns `BadMatch`, and `xwd -root` returns nothing, because your compositor redirects windows.
  The XComposite pixmap path was not tested, so treat this as "did not work", not "cannot work".
  The container has no GPU device, so the driver cannot be used to read another client's memory.
- **The internet.** QQ can send any data to any internet address at any time. The rules do
  not stop this.
- **This container's browser.** A link in QQ opens a page in the Firefox that runs inside
  this container. It is not your browser: it shares nothing with your browser, and the same
  limits apply to it.
- **DNS.** Docker answers DNS for the container from your host, so the container can look up
  any name and can send data in DNS names.
- **Its own files.** The volume holds your QQ login token and your chat history in clear
  text. Your disk encryption protects them, and nothing else does.

## Check the container

```bash
docker compose ps
docker compose exec qq grep -E 'CapEff|NoNewPrivs|Seccomp' /proc/1/status
# Expect: CapEff 0000000000000000, NoNewPrivs 1, Seccomp 2
ps -eo user,comm | grep qq                       # Expect: nobody
xhost | grep -c 'si:'                            # Expect: 0
sudo iptables -S QQ_JAIL                         # Expect: the rules above
sudo iptables -S INPUT | grep -c QQ_JAIL         # Expect: 1
```

Test the network policy from inside the container:

```bash
docker compose exec qq bash -c 'for hp in 127.0.0.11:53 172.26.0.1:22 192.168.0.1:445 1.1.1.1:443; do h=${hp%:*}; p=${hp#*:}; timeout 3 bash -c "cat < /dev/null > /dev/tcp/$h/$p" 2>/dev/null && echo "OPEN $hp" || echo "blocked $hp"; done'
# Expect: OPEN 1.1.1.1:443 (the internet) and OPEN 127.0.0.11:53 (Docker answers DNS inside
#         its own sandbox, so those packets never reach the chains).
# Expect: blocked 172.26.0.1:22 (this computer) and blocked 192.168.0.1:445 (the LAN).
```

## Troubleshooting

| Problem | Cause and action |
| --- | --- |
| `no xauth cookie found` | You are not in a GNOME Wayland session, or `/run/user/1000` is different. Start the desktop session, then run `docker compose up -d --force-recreate x-grant`. |
| No window, and the container stops | The X cookie is old. Your cookie name changes at every login. Run `docker compose up -d --force-recreate x-grant`. |
| The window stays blank | Not enough shared memory, or the GPU. `shm_size` must stay at 2 GB. Then test `--disable-gpu`. |
| `permission denied` on the X socket | The ACL is missing. Check `getfacl /tmp/.X11-unix/X0`; it must have `user:nobody:rw-`. Run the setup service again. |
| QQ says it cannot reach the network | Check the rules: `sudo iptables -S QQ_JAIL`. A rule for `0.0.0.0/0` would block the internet; there must be no such rule. |
| DNS fails after you change the subnet | The subnet in `compose.yaml` no longer matches the jump rule. Delete the old jump rule and run the setup service again. |

## Get a new version

1. Download the new package with the command in "First use".
2. Run `docker compose up -d --build`.
3. Your login and chat history stay in the volume.

## Remove everything

```bash
docker compose down
docker volume rm linuxqq-docker_qq-home
sudo iptables -D INPUT -s 172.26.0.0/24 -j QQ_JAIL
sudo iptables -D DOCKER-USER -s 172.26.0.0/24 -j QQ_JAIL
sudo iptables -X QQ_JAIL
```

Then delete the files in this directory. `share/` may hold files that QQ received.
