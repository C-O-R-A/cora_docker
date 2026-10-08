# How the Cora workspace works

`README.md` tells you **what to type**. This document explains **what happens
when you type it**, and why things are set up this way. Read it top to bottom
once; afterwards use it as a reference.

Contents:

1. [The problem this solves](#1-the-problem-this-solves)
2. [The big picture](#2-the-big-picture)
3. [Docker: containers and images](#3-docker-containers-and-images)
4. [The Dockerfile, line by line](#4-the-dockerfile-line-by-line)
5. [Users, UIDs and file ownership](#5-users-uids-and-file-ownership)
6. [Docker Compose](#6-docker-compose)
7. [Bind mounts: where your files live](#7-bind-mounts-where-your-files-live)
8. [Showing windows: X11, Wayland and the cookie](#8-showing-windows-x11-wayland-and-the-cookie)
9. [The GPU](#9-the-gpu)
10. [Networking and ROS discovery](#10-networking-and-ros-discovery)
11. [ROS 2 workspaces: packages, colcon, sourcing](#11-ros-2-workspaces-packages-colcon-sourcing)
12. [Dependencies: package.xml and rosdep](#12-dependencies-packagexml-and-rosdep)
13. [apt vs pip](#13-apt-vs-pip)
14. [vcstool and .repos files](#14-vcstool-and-repos-files)
15. [Pinning versions](#15-pinning-versions)
16. [setup.sh](#16-setupsh)
17. [Walkthrough: from `docker compose up` to Gazebo](#17-walkthrough-from-docker-compose-up-to-gazebo)
18. [Glossary](#18-glossary)

---

## 1. The problem this solves

ROS 2 Jazzy officially supports exactly one OS, **Ubuntu 24.04**. Teammates
run different Ubuntu versions (this laptop runs 26.04), so installing ROS
directly on each laptop gives everyone a slightly different, fragile setup.

The old setup used a container, which was a good start, but it was built by
hand:

| Old setup | Problem |
|---|---|
| A long `docker run ...` command typed once | Nobody else can reproduce it exactly |
| Packages installed by hand inside the container | Lost when the container is deleted; teammates don't have them |
| `install.sh` | Failed completely on one invalid package name |
| Container ran as `root` | Files it created on your laptop were owned by root |
| `xhost +local:root` before each session | Manual, and opened your screen to every local program |
| Three nested workspaces with a `cora_common` copy in each | Three different versions; the wrong one silently won |

The new setup turns each of those manual steps into a file that's in version
control: anyone gets the same environment by running the same commands.

---

## 2. The big picture

```
┌──────────────────────────── YOUR LAPTOP (the "host") ─────────────────────────────┐
│  Ubuntu 26.04, your desktop, your editor, Docker                                   │
│                                                                                    │
│  ~/dev/cora/cora_ws/ ─────────────────────┐ shared folder (bind mount)             │
│    Dockerfile, compose.yaml, .env ...     │                                        │
│    src/  build/  install/                 │                                        │
│                                           ▼                                        │
│   ┌────────────────── CONTAINER "cora-dev" (from image cora-dev:jazzy) ─────────┐  │
│   │  Ubuntu 24.04 + ROS 2 Jazzy + Gazebo + MoveIt + CoDI                         │  │
│   │  user "cora" (same UID as you)                                               │  │
│   │  /ros_ws  ← the same folder as ~/dev/cora/cora_ws                            │  │
│   │                                                                              │  │
│   │  colcon build, ros2 launch ... ──── windows ───▶ your screen (X11 socket)     │  │
│   │                                ──── graphics ──▶ GPU (/dev/dri, NVIDIA)       │  │
│   │                                ──── ROS traffic ▶ host network               │  │
│   └──────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Who does what:

| Tool | Job | Defined in |
|---|---|---|
| **vcstool** | Download the Cora repos into `src/` | `desktop.repos`, `robot.repos` |
| **Docker** | Build the image: Ubuntu 24.04 with everything installed | `Dockerfile`, `.dockerignore` |
| **Docker Compose** | Start the container with the right connections to your laptop | `compose.yaml`, `compose.nvidia.yaml`, `.env` |
| **rosdep** | Find out which Ubuntu packages the Cora packages need (during the image build) | `package.xml` files |
| **colcon** | Build the Cora packages (inside the container) | `package.xml`, `CMakeLists.txt`, `setup.py` |
| **setup.sh** | Run the one-time steps in the right order | `setup.sh` |

---

## 3. Docker: containers and images

### A container is an isolated process, not a virtual machine

A virtual machine emulates a whole computer with its own kernel; it's slow to
start and heavy. A **container** is just a normal process on your laptop that
the Linux kernel *isolates*:

- it sees its **own filesystem** (Ubuntu 24.04 with ROS) instead of yours,
- it has its **own list of processes and users**,
- it can only see the files, devices and network you explicitly give it.

Because it shares your laptop's kernel, it starts in a second and runs at full
speed. That's also why GPU access works with a few settings: the kernel and
drivers are your laptop's own.

### Image vs. container

| | Image | Container |
|---|---|---|
| What | A read-only filesystem snapshot plus some settings | A running (or stopped) instance of an image |
| Analogy | A cooked recipe, frozen | A plate served from it |
| Changes | Never; you build a new one | Has a thin writable layer on top of the image |
| Create with | `docker compose build` | `docker compose up -d` |
| Delete with | `docker rmi cora-dev:jazzy` | `docker compose down` |
| How many | One per version of the Dockerfile | As many as you like from one image |

**Anything you change *inside* a container (e.g. `sudo apt install`) is
stored in that container's writable layer and disappears when the container is
deleted.** That's why the old hand-installed packages were fragile, and why
dependencies now go in the Dockerfile (via `package.xml`), so they're part of
the image.

### Layers and the build cache

Each instruction in a Dockerfile (`RUN`, `COPY`, ...) produces a **layer**: the
set of files that instruction added or changed. An image is a stack of layers:

```
  layer 6  rosdep packages for Cora        ← rebuilt when a package.xml changes
  layer 5  CoDI + OpenCV                   ← rebuilt when CODI_REF changes
  layer 4  user "cora"                     ← rebuilt when your UID changes
  layer 3  tools (sudo, git, glxinfo...)
  ─────────────────────────────────────
  osrf/ros:jazzy-desktop-full              ← downloaded once (~6 GB)
```

When you rebuild, Docker reuses (**caches**) every layer whose instruction and
inputs haven't changed, **up to the first one that has**. Everything after that
is rebuilt. That's why the Dockerfile puts rarely-changing steps first and the
`package.xml`-dependent step last: changing a dependency only reruns the last
steps, not the whole build.

### Build context and .dockerignore

`docker compose build` sends a folder (the **build context**, here `cora_ws`) to
Docker, and `COPY` instructions can only use files from it. `.dockerignore`
filters what gets sent. Ours sends *only* `docker/` and the `package.xml` files:

```
*                       # ignore everything...
!docker/                # ...except this folder
!src/**/package.xml     # ...and every package.xml
```

Two benefits: Docker receives about 14 kB instead of 251 MB (the meshes), and
the cache stays valid when you edit code, because code isn't part of the
context.

---

## 4. The Dockerfile, line by line

```dockerfile
FROM osrf/ros:jazzy-desktop-full
```
Start from an existing image instead of from scratch. This one is maintained by
the ROS developers (Open Robotics) and contains Ubuntu 24.04, ROS 2 Jazzy
"desktop-full" (RViz, rqt, ...), and Gazebo Harmonic.

```dockerfile
ARG USERNAME=cora
ARG USER_UID=1000
ARG USER_GID=1000
ARG CODI_REF=b475de33...
```
**Build arguments**: variables with defaults that can be overridden at build
time (`--build-arg USER_UID=1001`). Compose passes your UID/GID from `.env`.
They only exist during the build.

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
```
An **environment variable** baked into the image. This one stops `apt` from
asking interactive questions (like "which timezone?"), which would hang a
build because nobody can answer.

```dockerfile
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
```
Run the `RUN` commands with bash and `pipefail`, so `a | b` fails if `a`
fails (by default only `b`'s result counts, which hides errors).

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ... \
    && rm -rf /var/lib/apt/lists/*
```
**`RUN`** executes a command during the build; its result becomes a layer.
`apt-get update` downloads the package lists, `install -y` installs without
asking, `--no-install-recommends` skips optional extras. Deleting
`/var/lib/apt/lists` at the end of the *same* `RUN` keeps the layer small: a
file deleted in a later `RUN` would still take up space in the earlier layer.

```dockerfile
RUN if id -u ubuntu ...; then userdel --remove ubuntu; fi && ... useradd ...
```
Creates the user `cora` with your UID (see [section 5](#5-users-uids-and-file-ownership)).
Ubuntu 24.04 images ship a user `ubuntu` with UID 1000, which would collide,
so it's removed first. The user gets passwordless `sudo` via a file in
`/etc/sudoers.d/`.

```dockerfile
RUN pip install --no-deps --break-system-packages \
      "opencv-python-headless==4.10.0.84" \
      "git+https://github.com/C-O-R-A/CoDI.git@${CODI_REF}" \
    && python3 -c "import numpy, cv2; from codi import CoraServer; ..."
```
Installs CoDI straight from GitHub at a fixed commit (see
[section 13](#13-apt-vs-pip) for the flags). The last line is a **self-test**:
if CoDI can't be imported, the build fails right here, instead of `codi_node`
crashing 30 seconds into a simulation. That test caught a real problem during
setup: CoDI needs OpenCV ≥ 4.8 and Ubuntu only ships 4.6.

```dockerfile
COPY src /tmp/cora_manifests
RUN apt-get update && rosdep update && rosdep install --from-paths /tmp/cora_manifests ... \
    && rm -rf ... /tmp/cora_manifests
```
**`COPY`** copies files from the build context into the image. Because of
`.dockerignore`, `src` contains only the `package.xml` files at this point.
`rosdep install` reads them and installs every missing dependency (see
[section 12](#12-dependencies-packagexml-and-rosdep)). Then the copies are
deleted; they were only needed for rosdep.

```dockerfile
COPY docker/cora.bashrc /etc/cora.bashrc
RUN echo "source /etc/cora.bashrc" >> "/home/${USERNAME}/.bashrc"
```
Bash runs `~/.bashrc` whenever it starts an interactive terminal. This hooks
in `cora.bashrc`, which sources ROS and, if it exists, your built workspace.
That's why every container terminal "just has" `ros2`.

```dockerfile
USER ${USERNAME}
RUN rosdep update --rosdistro "${ROS_DISTRO}"
WORKDIR /ros_ws
CMD ["bash"]
```
- **`USER`**: from here on, and when the container runs, act as `cora`, not root.
- The `rosdep update` gives `cora` its own copy of rosdep's package database, so
  `rosdep` works inside the container without `sudo`.
- **`WORKDIR`**: the starting directory (where the workspace gets mounted).
- **`CMD`**: the default command when a container starts. Compose overrides it
  (see below).

---

## 5. Users, UIDs and file ownership

Linux doesn't actually track files by user *name*; it stores a number, the
**UID** (user ID), on every file. Your user `martijn-boonen` is UID 1000. Names
are just looked up in `/etc/passwd` for display.

The container has its own `/etc/passwd`, but it writes to the *same* files
on your laptop's disk (through the bind mount). So:

| Container runs as | Files it creates get UID | On your laptop they show as |
|---|---|---|
| `root` (old setup) | 0 | `root`. You can't edit or delete them without `sudo` |
| `cora` with UID 1000 (new setup) | 1000 | `martijn-boonen`, i.e. yours |

That's the whole trick: the name inside (`cora`) doesn't matter, the number
does. On a laptop where the user is UID 1001, `setup.sh` writes
`USER_UID=1001` into `.env`, and the image is built with a `cora` user of UID
1001.

The same number also makes the display work without `xhost`
([section 8](#8-showing-windows-x11-wayland-and-the-cookie)).

---

## 6. Docker Compose

### What it is

Creating a container that's connected to your laptop needs many options:
network, display, devices, folders, environment variables. Your old command was:

```bash
docker run -it -d --name ros-jazzy-gpu --network host --gpus all -e DISPLAY=$DISPLAY \
  -e QT_X11_NO_MITSHM=1 -e NVIDIA_DRIVER_CAPABILITIES=all ... -v ... -w /ros_ws osrf/ros:jazzy-desktop-full bash
```

**Docker Compose** puts those options in a file, `compose.yaml`, so the command
becomes `docker compose up -d`. The file is in version control, so everyone
gets the same container. Compose calls each container a **service**; ours is
called `dev` (hence `docker compose exec dev bash`).

### compose.yaml, explained

```yaml
name: cora                         # project name; containers/networks get this prefix

services:
  dev:                             # the service name used in `docker compose exec dev ...`
    image: cora-dev:jazzy          # which image to run (and the name to give it when building)
    build:                         # how to build that image: `docker compose build`
      context: .                   #   build context = this folder
      args:                        #   build arguments for the Dockerfile
        USER_UID: ${USER_UID:-1000}   #   ${VAR:-default}: from .env, else 1000
    container_name: cora-dev       # fixed name instead of the generated "cora-dev-1"

    network_mode: host             # share the laptop's network (section 10)
    ipc: host                      # share memory with the host: faster DDS and X11

    environment:                   # environment variables inside the container
      DISPLAY: ${DISPLAY:?...}     # ${VAR:?msg}: stop with msg if DISPLAY isn't set
      XAUTHORITY: /tmp/.Xauthority # where the X cookie is mounted (section 8)
      ROS_AUTOMATIC_DISCOVERY_RANGE: ${ROS_AUTOMATIC_DISCOVERY_RANGE:-LOCALHOST}
      ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}

    volumes:                       # bind mounts: host path : container path
      - .:/ros_ws                  # the workspace (section 7)
      - /tmp/.X11-unix:/tmp/.X11-unix                        # X11 socket
      - ${XAUTHORITY:-${HOME}/.Xauthority}:/tmp/.Xauthority:ro   # X cookie, read-only

    devices:
      - /dev/dri:/dev/dri          # GPU render devices (section 9)
    group_add:
      - "${RENDER_GID:-video}"     # extra group so `cora` may use them

    command: sleep infinity        # what the container runs: nothing, forever
    init: true                     # a tiny init process that cleans up zombie processes
```

`command: sleep infinity` might look odd. A container lives as long as its main
process does. We don't want a specific program as the main process; we want a
container that stays up so we can open shells in it with `docker compose exec`.
`sleep infinity` does exactly that and uses no CPU.

### .env and variable substitution

Before reading `compose.yaml`, Compose loads `.env` from the same folder and
replaces every `${...}`:

| Syntax | Meaning |
|---|---|
| `${VAR}` | Value of `VAR` (from `.env` or your shell) |
| `${VAR:-default}` | Value of `VAR`, or `default` if it's empty or unset |
| `${VAR:?message}` | Value of `VAR`, or stop with `message` if it's empty or unset |

Your shell's variables (like `DISPLAY` and `XAUTHORITY`) are used too, and
override `.env`. That's why `.env` holds only what differs per laptop and isn't
shared in git.

`.env` can also set Compose's own options. `COMPOSE_FILE=compose.yaml:compose.nvidia.yaml`
tells Compose to always load both files, so you never have to type
`-f compose.yaml -f compose.nvidia.yaml`.

### Override files

When Compose loads several files, it **merges** them: later files add to or
replace settings of earlier ones. `compose.nvidia.yaml` only contains the
NVIDIA additions (GPU reservation plus a few environment variables), so the base
file stays usable on laptops without NVIDIA.

Check the merged result at any time:

```bash
docker compose config
```

### The lifecycle commands

| Command | What happens | Survives? |
|---|---|---|
| `docker compose build` | Builds the image from the Dockerfile | — |
| `docker compose up -d` | Creates the container if needed and starts it. If the config changed (different `.env`, new image, new X cookie path), it **recreates** it. | — |
| `docker compose exec dev bash` | Starts an extra `bash` process in the running container | — |
| `docker compose stop` | Stops the container (processes end) | Container, including anything installed inside it |
| `docker compose start` | Starts the stopped container again | — |
| `docker compose down` | Stops **and deletes** the container | Image, and your files on the host |
| `docker compose ps` | Shows the container and its status | — |
| `docker compose logs` | Output of the main process (not very useful with `sleep`) | — |

Your code, `build/` and `install/` survive **everything** above, because they
live on your laptop, not in the container.

---

## 7. Bind mounts: where your files live

A **bind mount** makes a folder of your laptop appear at a path inside the
container. It's the *same* folder, not a copy:

```
host:      ~/dev/cora/cora_ws/src/cora_desktop/cora_gazebo/launch/gazebo.launch.py
container: /ros_ws/src/cora_desktop/cora_gazebo/launch/gazebo.launch.py
           └── same file on disk; a change on one side is instantly visible on the other
```

That's why you can edit with VS Code on the host and build in the container,
and why `docker compose down` never loses work.

What lives where:

| Thing | Location | Lost on `docker compose down`? |
|---|---|---|
| Source code (`src/`) | Host (bind mount) | No |
| Build output (`build/`, `install/`, `log/`) | Host (bind mount) | No |
| ROS, Gazebo, MoveIt, CoDI | Image | No |
| Things you `sudo apt install`ed in the container | Container's writable layer | **Yes** |
| Shell history, VS Code's server in the container | Container's writable layer | **Yes** (VS Code reinstalls itself) |

One catch: `build/` contains absolute paths (`/ros_ws/...`). A `build/` created
on the host (`~/dev/cora/cora_ws/...`) doesn't match, and colcon/CMake
complains. Always build inside the container; if you mixed them, remove
`build install log` and build again.

---

## 8. Showing windows: X11, Wayland and the cookie

### How a window gets on your screen

Linux desktops use a **display server** that owns the screen. Programs
(clients) connect to it and ask it to draw windows.

- **X11** is the classic display server protocol. RViz, Gazebo and most ROS
  tools speak X11.
- **Wayland** is the modern replacement. Ubuntu's desktop (GNOME) uses it. To
  run X11 programs it starts **XWayland**, an X11 server that runs inside your
  Wayland session.

An X11 client finds the server through:

| | Value on this laptop | Meaning |
|---|---|---|
| `DISPLAY` | `:0` | Use X server number 0 |
| Socket | `/tmp/.X11-unix/X0` | The file the client connects to for display `:0` |

So, to let the container draw windows, compose:
1. passes `DISPLAY` into the container, and
2. bind-mounts `/tmp/.X11-unix`, so the socket exists inside.

### Who is allowed to connect

The X server won't accept just anyone; otherwise any program could read your
keystrokes or take screenshots. There are two mechanisms:

**1. The cookie (`xauth`).** At login, the desktop creates a random secret
(the "MIT-MAGIC-COOKIE") and stores it in a file that only you can read. The
path is in `$XAUTHORITY`. On this laptop it's something like
`/run/user/1000/.mutter-Xwaylandauth.0RM3V3`. A client that presents the cookie
is allowed in.

**2. The access list (`xhost`).** Rules like "allow all local connections".
`xhost +local:root` doesn't mean "allow root": it means "allow **every** local
connection" (the `root` part is ignored). That's why it worked for the root
container, and also why it was broader than intended.

### What the new setup does

Compose mounts **your cookie file** into the container (read-only) and sets
`XAUTHORITY` to it. The container's processes present the cookie and get
in, like any of your own programs. No `xhost` needed, and nothing else is
opened up.

This works because the container user has your UID: the cookie file is
readable only by UID 1000 (`-rw-------`), and inside the container `cora` *is*
UID 1000.

### Why "run `docker compose up -d` after logging in again"

Every login creates a **new cookie in a file with a new random name**. The
running container still has the old (now deleted) file mounted. When you run
`docker compose up -d`, Compose sees that `${XAUTHORITY}` now points to a
different path, decides the configuration changed, and recreates the container
with the new file. That takes a few seconds and doesn't affect your files.

---

## 9. The GPU

Gazebo and RViz draw 3D graphics with **OpenGL**. Without a GPU, the CPU has to
do it ("software rendering", shown as `llvmpipe` in `glxinfo -B`), which is
slow. That's why the old non-GPU container was sluggish.

### Intel/AMD: /dev/dri and Mesa

The kernel exposes GPUs as device files in `/dev/dri/`:

```
/dev/dri/card1, card2           ← full control of a GPU (group "video")
/dev/dri/renderD128, renderD129 ← rendering only (group "render")
```

**Mesa** is the open-source OpenGL implementation for Intel and AMD GPUs; it's
already in the image. To use the GPU, the container needs:

1. the device files: `devices: - /dev/dri:/dev/dri`, and
2. permission: the files belong to group `render` (and `video`). The group's
   **number** differs per laptop (990 here), so `setup.sh` writes it to `.env`
   as `RENDER_GID`, and compose adds `cora` to that group with `group_add`.

Check: `glxinfo -B` in the container shows `Mesa Intel(R) Graphics`.

### NVIDIA: the Container Toolkit

NVIDIA's driver is proprietary and must match the kernel module on the host
exactly, so it can't simply be installed in the image. The **NVIDIA Container
Toolkit** (installed on the host) solves this: when a container requests a
GPU, it mounts the host's NVIDIA driver libraries and devices into it.

`compose.nvidia.yaml` requests the GPU:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]        # = `docker run --gpus all`
environment:
  NVIDIA_DRIVER_CAPABILITIES: all    # mount graphics libraries too, not just compute (CUDA)
```

### Hybrid laptops: PRIME offload

This laptop has **two** GPUs: Intel (always on, drives the screen, saves power)
and NVIDIA (fast). By default, OpenGL uses the Intel one. **PRIME render
offload** tells a program to render on NVIDIA and hand the result to the Intel
GPU for display:

```yaml
__NV_PRIME_RENDER_OFFLOAD: "1"        # offload rendering to NVIDIA
__GLX_VENDOR_LIBRARY_NAME: nvidia     # use NVIDIA's OpenGL library instead of Mesa
```

Check: `glxinfo -B` shows `NVIDIA RTX A1000 Laptop GPU`.

---

## 10. Networking and ROS discovery

### Host networking

By default, Docker gives each container its own virtual network. ROS 2 doesn't
like that: nodes find each other with **multicast discovery** (DDS), which
doesn't cross Docker's virtual network easily. `network_mode: host` skips
Docker's network entirely: the container uses your laptop's network directly,
as if its processes ran on the host.

### Who can see your nodes

With host networking, your nodes are on your laptop's real network, and by
default ROS 2 talks to **everyone on the same Wi-Fi** running ROS with the same
domain ID. Two teammates running the simulation in the same room would get
each other's `/joint_states`.

Two variables control this (set in `compose.yaml`, overridable in `.env`):

| Variable | Our default | Meaning |
|---|---|---|
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | `LOCALHOST` | Only discover nodes on this laptop. `SUBNET` = the whole local network (needed to talk to the real robot). |
| `ROS_DOMAIN_ID` | `0` | A channel number (0–101). Only nodes with the same ID see each other. |

The old and new containers both use host networking, so their nodes **would**
see each other. That's why you stop one before using the other.

---

## 11. ROS 2 workspaces: packages, colcon, sourcing

### Packages

A ROS **package** is a folder with a `package.xml` (name, version,
dependencies) and either a `CMakeLists.txt` (C++/ament_cmake packages, e.g.
`cora_gazebo`, `cora_msgs`) or a `setup.py` (Python/ament_python packages, e.g.
`cora_moveit`, `cora_codi`).

A **workspace** is a folder with a `src/` containing packages, here in several
git repos:

```
/ros_ws/src/
├── cora_common/                 ← git repo
│   ├── cora_bringup/            ← package
│   ├── cora_codi/               ← package
│   ├── cora_description/        ← package
│   └── ...
└── cora_desktop/                ← git repo
    └── cora_gazebo/             ← package
```

### colcon build

`colcon build` (run in `/ros_ws`):

1. finds every `package.xml` under `src/`,
2. works out the build order from their dependencies (`cora_msgs` before
   `cora_moveit`, because `cora_moveit` uses its messages),
3. builds each package in `build/<package>/`,
4. installs the result into `install/<package>/` (executables, Python modules,
   launch files, configs, meshes),
5. writes logs to `log/`.

`--symlink-install` makes `install/` contain **links** to your source files
instead of copies, where possible: Python files, launch files, YAML configs,
URDFs. Editing them then takes effect without rebuilding. C++ code always needs
a rebuild (it must be compiled), and so do *new* files (the link doesn't exist
yet).

### Sourcing: underlays and overlays

`ros2 launch cora_gazebo ...` needs to know where `cora_gazebo` is installed.
**Sourcing** a `setup.bash` adds a workspace's paths to environment variables
(`AMENT_PREFIX_PATH`, `PYTHONPATH`, `LD_LIBRARY_PATH`, ...) in the current
terminal:

```bash
source /opt/ros/jazzy/setup.bash   # the "underlay": ROS itself, from the image
source /ros_ws/install/setup.bash  # the "overlay": your Cora packages, on top
```

If a package exists in both, the **overlay wins**. Order matters, and it only
applies to the terminal where you ran it. `cora.bashrc` does both automatically
in every new container terminal; after a build that added *new* packages, run
`source install/setup.bash` once in terminals that were already open.

### Why one workspace instead of three

The old setup had three workspaces stacked as overlays:
`/opt/ros/jazzy` → `cora_common_ws` → `cora_desktop_ws`. Each workspace had its
own `cora_common` (directly, or as a submodule), at a different version:

| Copy | Version |
|---|---|
| `cora_common_ws/src/cora_common` | 2026-09-21 |
| `cora_desktop_ws/src/cora_common` (submodule) | 2026-07-11 |
| `cora_robot_ws/src/cora_common` (submodule) | 2026-02-10 |

Because the overlay wins, the simulation ran the **July** code from the desktop
copy, not the September code you might have been editing in
`cora_common_ws`. Nothing warned about it. That's called **shadowing**.

Now there's one workspace with exactly one `cora_common`. colcon would refuse to
build two packages with the same name in one workspace, so this can't silently
happen again.

---

## 12. Dependencies: package.xml and rosdep

### Declaring dependencies

Each `package.xml` lists what the package needs:

| Tag | Needed when | Example |
|---|---|---|
| `<build_depend>` | Compiling | a C++ header library |
| `<exec_depend>` | Running | `moveit_servo` (started by a launch file) |
| `<depend>` | Both (shorthand) | `rclcpp`, message packages |
| `<test_depend>` | Running tests | `ament_flake8` |
| `<buildtool_depend>` | The build system itself | `ament_cmake` |

Rule of thumb: **anything your code imports, or your launch files start or
`find`, must be listed.** Many Cora packages didn't, which is why
`moveit_servo`, `moveit_py` and `gz_ros2_control` had to be installed by hand.
`cora_gazebo` listed nothing at all.

### rosdep keys

Dependencies aren't written as Ubuntu package names, but as **rosdep keys**,
which work across operating systems. rosdep has a big public database that maps
keys to system packages:

| Key in package.xml | rosdep turns it into (Ubuntu 24.04) |
|---|---|
| `moveit_servo` (a ROS package) | `ros-jazzy-moveit-servo` |
| `gz_ros2_control` | `ros-jazzy-gz-ros2-control` |
| `python3-numpy` (a system library) | `python3-numpy` |
| `numpy` | ❌ no such key. This was in `cora_moveit_config` and made `rosdep install` abort completely |

Look a key up with `rosdep resolve <key>` (inside the container) or at
<https://index.ros.org>.

### rosdep install

```bash
rosdep install --from-paths src --ignore-src -y
```

- `--from-paths src`: read all `package.xml` files under `src/`,
- `--ignore-src`: skip dependencies that are themselves in `src/` (like
  `cora_msgs`; colcon builds those),
- `-y`: don't ask, just `apt install` the rest.

The image build runs exactly this (on the copied `package.xml` files). So
**adding a dependency = add it to `package.xml` + rebuild the image**, and
every teammate gets it.

This replaced `install.sh`, which had a hand-written `apt install` list. That
list went stale (`ros-jazzy-gazebo-ros-pkgs` doesn't exist for Jazzy), and one
bad name made the whole install fail.

---

## 13. apt vs pip

Python packages can come from two places:

| | apt (`python3-numpy`) | pip (`pip install numpy`) |
|---|---|---|
| Source | Ubuntu's archive | PyPI (python.org's package index) |
| Versions | Fixed per Ubuntu release, tested together with ROS | Newest, unless pinned |
| Used by ROS | Yes; ROS packages are built against these | No |

Mixing them is risky. If pip upgrades `numpy` to 2.x, ROS's own Python
modules, compiled against numpy 1.26 from apt, can break. So:

- **Prefer apt** (via rosdep keys like `python3-numpy`). CoDI's dependencies
  numpy, msgpack and PyYAML come from apt.
- **pip only for what apt doesn't have**: CoDI itself (it's not packaged
  anywhere), and OpenCV ≥ 4.8 (Ubuntu ships 4.6, CoDI needs 4.8+).
- **`--no-deps`**: install only the named package, don't let pip pull in or
  upgrade its dependencies (that's how numpy stays at the apt version).
- **`--break-system-packages`**: Ubuntu 24.04 blocks system-wide `pip install`
  by default (rule "PEP 668"), exactly because of the risk above. We override
  it deliberately, inside a disposable image, for two carefully chosen packages.
- **`opencv-python-headless`** instead of `opencv-python`: the regular one
  bundles its own copy of Qt, which conflicts with the Qt that RViz and Gazebo
  use. "Headless" means without GUI parts; CoDI doesn't need them.

---

## 14. vcstool and .repos files

### What a .repos file is

A YAML list of git repositories: where each comes from, which version, and
which folder it goes in:

```yaml
repositories:
  cora_common:                                       # → src/cora_common
    type: git
    url: git@github.com:C-O-R-A/cora_common.git
    version: 161ee79e45d37657d1802d3d5b9b96b34890b867   # an exact commit
  cora_desktop:                                      # → src/cora_desktop
    type: git
    url: git@github.com:C-O-R-A/cora_desktop.git
    version: main                                    # a branch
```

`vcs import src < desktop.repos` clones each one into `src/` and checks out the
given version. Other useful commands: `vcs status src`, `vcs pull src`,
`vcs export src --exact`.

### Why not git submodules

A **submodule** is a repo embedded inside another repo, pinned to a commit.
`cora_desktop` and `cora_robot` each embed `cora_common` that way. The problem
is that each parent pins its own version, so you end up with several
`cora_common` copies at different commits (and the shadowing problem above).

With `.repos` files, the code repos stay independent and side by side, and one
file decides which versions go together. Most ROS 2 projects work this way
(MoveIt, Nav2, ...).

The submodules still exist in `cora_desktop` and `cora_robot`. We just don't
download them: `vcs import` without `--recursive` leaves the submodule folder
empty. Removing the submodules from those repos is a separate team decision.

### Detached HEAD

`cora_common` is pinned to a commit, so `git status` there says
`HEAD detached at 161ee79`. That just means "you're on a specific commit, not
on a branch". Reading and building is fine. Before making changes, create a
branch (`git switch -c my-branch`) so your commits have a name to live on.

---

## 15. Pinning versions

"Pinning" means depending on one **exact** version instead of "the latest".

| What | Pinned to | Where | Why |
|---|---|---|---|
| `cora_common` (desktop) | commit `161ee79` (2026-07-11) | `desktop.repos` | The version the simulation already ran with |
| `cora_common` (robot) | commit `c2d6518` (2026-02-10) | `robot.repos` | What `cora_robot`'s submodule points to |
| CoDI | commit `b475de3` (2026-06-13) | `CODI_REF` in `Dockerfile` | Last CoDI version with the API that `cora_common` 161ee79 uses |
| OpenCV (pip) | `4.10.0.84` | `Dockerfile` | Satisfies CoDI's needs, works with numpy 1.26 |
| `cora_desktop`, `cora_robot` | branch `main` | `.repos` files | Follows current work |

Pinned versions give **reproducibility**: building the image today or in three
months, on any laptop, gives the same result. The cost is that upgrades are
deliberate. For example, moving `cora_common` to its September version means
also moving `CODI_REF`, because CoDI changed its API in July (it switched to
pydantic models, and the call signatures changed).

A commit hash like `161ee79e45d3...` is a fingerprint of a commit's exact
content and history. The first 7 characters (`161ee79`) are usually enough to
identify it.

---

## 16. setup.sh

A bash script that runs the one-time steps in order and stops with a clear
message when something's missing:

```
1/4 Checking prerequisites    docker, docker group, compose, git, vcs, GitHub SSH
2/4 Machine settings (.env)   UID/GID, render group, NVIDIA (if Docker has the nvidia runtime)
3/4 Downloading repos         vcs import --skip-existing src < desktop.repos
4/4 Building the image        docker compose build
```

Design choices worth knowing:

- **Idempotent**: running it twice is safe. An existing `.env` is kept,
  existing repos are skipped (`--skip-existing`, so your branches and changes
  aren't touched), and the image build is cached.
- **No `sudo` inside**: it only tells you what to install. Changing your
  system stays your decision.
- **Refuses to run inside a container or as root**, the two most likely mix-ups.
- `set -euo pipefail` at the top: stop at the first failing command
  (`-e`), treat unset variables as errors (`-u`), and catch failures inside
  pipes (`pipefail`).

---

## 17. Walkthrough: from `docker compose up` to Gazebo

**`docker compose up -d`** (host)
1. Compose reads `.env`, then `compose.yaml` and `compose.nvidia.yaml`
   (because of `COMPOSE_FILE`), substitutes the variables, and merges them.
2. No container `cora-dev` exists yet, so it creates one from `cora-dev:jazzy`.
   It sets up the bind mounts (workspace, X socket, cookie), the GPU devices,
   the extra group, host networking and the environment variables.
3. It starts the main process, `sleep infinity`, as user `cora`. `-d` returns
   your terminal immediately.

**`docker compose exec dev bash`** (host)
4. Docker starts a new `bash` process inside the running container, connected
   to your terminal. Bash reads `~/.bashrc` → `/etc/cora.bashrc` → sources ROS
   and `/ros_ws/install/setup.bash`.

**`colcon build --symlink-install`** (container)
5. colcon finds the 10 packages in `/ros_ws/src`, builds them in dependency
   order into `/ros_ws/build`, and installs them into `/ros_ws/install`. These
   folders appear on your laptop too, owned by you.

**`ros2 launch cora_gazebo gazebo.launch.py`** (container)
6. `ros2` finds `cora_gazebo` through `AMENT_PREFIX_PATH` (set by sourcing) and
   runs its launch file.
7. The launch file uses `xacro` to turn `cora.urdf.xacro` into the robot
   description (`hardware_type:=Gazebo` selects the `gz_ros2_control` plugin),
   starts Gazebo with `main_world.sdf` (the default added during this setup),
   and spawns the robot.
8. Gazebo connects to `DISPLAY=:0` through `/tmp/.X11-unix/X0`, presents the
   cookie from `/tmp/.Xauthority`, and opens its window. It renders through
   OpenGL on the NVIDIA GPU (PRIME offload).
9. When spawning finishes, `cora_bringup` starts MoveIt (`move_group`),
   MoveIt Servo, the ros2_control controllers and RViz. After 30 seconds the
   CoDI node starts and opens its server.
10. All nodes discover each other over DDS on the host network, limited to
    this laptop (`ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`).

---

## 18. Glossary

| Term | Meaning |
|---|---|
| **Host** | Your laptop's own operating system, outside any container |
| **Image** | Read-only snapshot of a filesystem plus settings; the template for containers |
| **Container** | An isolated running process with its own filesystem, created from an image |
| **Layer** | The changes made by one Dockerfile instruction; images are stacks of layers |
| **Build context** | The folder sent to Docker when building; `COPY` can only use files from it |
| **Dockerfile** | The recipe to build an image |
| **Docker Compose** | Tool that creates and starts containers from a YAML file |
| **Service** | A container definition in `compose.yaml` (ours: `dev`) |
| **Bind mount** | A host folder or file made visible inside a container (same data, not a copy) |
| **UID / GID** | User ID / group ID numbers; file ownership is stored as these numbers |
| **X11 / Wayland / XWayland** | Display server protocols; XWayland runs X11 apps on a Wayland desktop |
| **`DISPLAY`** | Tells X11 programs which display server to use (`:0`) |
| **Xauthority / cookie** | Secret that proves a program may use your display |
| **Mesa** | Open-source OpenGL drivers (Intel/AMD) |
| **NVIDIA Container Toolkit** | Host software that gives containers access to NVIDIA GPUs |
| **PRIME offload** | Rendering on the NVIDIA GPU while the Intel GPU drives the screen |
| **DDS** | The communication middleware ROS 2 uses; handles discovery and messages |
| **Package** | A ROS unit of code with a `package.xml` |
| **Workspace** | A folder with `src/` (packages) that colcon builds into `build/` and `install/` |
| **colcon** | The ROS 2 build tool |
| **Sourcing** | Running `source setup.bash` to make a workspace's packages available in a terminal |
| **Underlay / overlay** | A workspace sourced first / a workspace sourced on top (which wins on conflicts) |
| **Shadowing** | An overlay package silently hiding a package with the same name underneath |
| **rosdep** | Tool that installs system dependencies listed in `package.xml` files |
| **rosdep key** | OS-independent dependency name (e.g. `python3-numpy`) that rosdep maps to a system package |
| **vcstool (`vcs`)** | Tool that clones/updates many git repos from a `.repos` file |
| **Submodule** | A git repo embedded in another repo at a pinned commit |
| **Pinning** | Depending on an exact version (commit/version number) instead of "latest" |
| **Detached HEAD** | Git state where you're on a specific commit rather than a branch |
| **PEP 668** | The rule that makes Ubuntu refuse system-wide `pip install` by default |
