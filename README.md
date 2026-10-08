# Cora development workspace

Everything you need to build and run the Cora software (ROS2 Jazzy, Gazebo,
MoveIt 2) inside a Docker container. It works the same on every laptop,
whatever Linux version it runs.

- **Part 1, one-time setup:** do this once per laptop.
- **Part 2, daily use:** start the container, build, launch the simulation.
- **Part 3, reference:** background, updating, troubleshooting.

Every command block says where to run it:

- 🖥️ **HOST:** a normal terminal on your laptop (Ctrl+Alt+T). Prompt looks like `you@laptop:~$`.
- 📦 **CONTAINER:** a terminal inside the container. Prompt looks like `cora@laptop:/ros_ws$`.

---

## Two words you need: image and container

| | What it is | Analogy | Created with |
|---|---|---|---|
| **Image** | A frozen snapshot with Ubuntu, ROS, Gazebo, MoveIt and all Cora dependencies installed. Read-only. | An installer / a recipe that's been cooked | `docker compose build` (Part 1, step 6) |
| **Container** | A running instance of the image, where you actually work. | A program that's running | `docker compose up -d` (Part 2, step 1) |

You build the image once (and again when dependencies change). You can create,
stop and delete containers as often as you like. Your code is **not** inside the
container: the `cora_ws` folder on your laptop is shared with it, so nothing is
lost when a container is removed.

---

# Part 1: one-time setup

### Step 1: Install Docker, git and vcstool

🖥️ **HOST**

Install Docker Engine by following <https://docs.docker.com/engine/install/ubuntu/>
(not the Snap package, and not Docker Desktop). Then:

```bash
sudo usermod -aG docker $USER     # lets you use docker without sudo
sudo apt install git python3-vcstool
```

**Log out and back in** (needed for the docker group to take effect). Then check:

```bash
docker run --rm hello-world       # should print "Hello from Docker!"
docker compose version            # should print a version number
vcs --version                     # should print a version number
```

### Step 2: Check your GitHub SSH key

🖥️ **HOST**

```bash
ssh -T git@github.com
```

✅ Expected: `Hi <your-username>! You've successfully authenticated...`

❌ If you get `Permission denied (publickey)`, set up a key first:
<https://docs.github.com/en/authentication/connecting-to-github-with-ssh>.

### Step 3 (only with an NVIDIA GPU): NVIDIA Container Toolkit

Skip this if your laptop only has Intel/AMD graphics.

🖥️ **HOST.** Install the NVIDIA driver and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), then check:

```bash
docker run --rm --gpus all ubuntu nvidia-smi    # should show a table with your GPU
```

### Step 4: Get the workspace folder

🖥️ **HOST**

```bash
mkdir -p ~/dev/cora && cd ~/dev/cora
git clone git@github.com:C-O-R-A/cora_docker.git cora_ws
```

### Step 5: Download the repos and switch to `fix/package-deps`

🖥️ **HOST**

This setup needs the `fix/package-deps` branch of `cora_common` and
`cora_desktop`, **not** `main` (or the commit in `desktop.repos`). `main` misses
the `package.xml` fixes and the image build fails at `rosdep install`. See
[Local changes in cora_common and cora_desktop](#local-changes-in-cora_common-and-cora_desktop).

```bash
cd ~/dev/cora/cora_ws
vcs import src < desktop.repos
git -C src/cora_common switch fix/package-deps
git -C src/cora_desktop switch fix/package-deps
```

### Step 6: Run the setup script

🖥️ **HOST**

```bash
~/dev/cora/cora_ws/setup.sh
```

It leaves the repos from step 5 (and their branch) alone.

The script:

1. **Checks** Docker, Docker Compose, git, vcstool and your GitHub SSH access,
   and tells you exactly what to install if something is missing (marked ✘).
   Fix those items and run it again.
2. **Writes `.env`** with this laptop's settings: your user ID, the ID of the
   group that may use the GPU, and whether to use the NVIDIA GPU (detected
   automatically).
3. **Downloads the Cora repos** into `src/` (from `desktop.repos`).
4. **Builds the Docker image.** The first time this downloads about 6 GB and
   takes 5–10 minutes.

✅ Expected: it ends with `Setup complete. Next: ...`.

You can safely run it again at any time: it keeps an existing `.env`, skips
repos you already have (your branches and changes are left alone), and only
rebuilds the image if something changed. For the robot packages instead of the
desktop ones: `setup.sh robot.repos`.

> Want to know what it does under the hood, or do it by hand? See
> [Manual setup](#manual-setup-what-setupsh-does).

**Part 1 done.** You won't need these steps again on this laptop.

---

# Part 2: daily use

All `docker compose` commands must be run **in `~/dev/cora/cora_ws`**.

### Step 1: Start the container

🖥️ **HOST**

```bash
cd ~/dev/cora/cora_ws
docker compose up -d
```

This creates a container called `cora-dev` from the image and starts it in the
background (`-d` = detached). If it already exists and is running, nothing
happens, so it's always safe to run.

✅ Check: `docker compose ps` shows `cora-dev` with status `Up`.

> Run this from a terminal on your desktop, not over SSH. It needs your desktop
> session to give the container access to your screen.
>
> **After logging out and back in (or rebooting), run `docker compose up -d`
> once before working.** Your login gets a new screen-access key, and this
> recreates the container so it uses the new one. Without it, windows won't
> open (`Authorization required`).

### Step 2: Open a terminal inside the container

🖥️ **HOST**

```bash
docker compose exec dev bash
```

✅ The prompt changes to `cora@<laptop-name>:/ros_ws$`. You're now inside the
container, in the workspace folder. ROS is already loaded.

You can open as many container terminals as you like: run the same command in
a new host terminal tab.

**First time only:** check that windows can open:

📦 **CONTAINER**

```bash
xeyes
```

✅ A small window with eyes that follow your mouse appears. Close it.

### Step 3: Build the workspace

📦 **CONTAINER**

```bash
colcon build --symlink-install
source install/setup.bash
```

`colcon build` compiles all Cora packages into `build/` and `install/`. The
first build takes a few minutes; later builds only redo what changed.

`source install/setup.bash` makes the built packages available in *this*
terminal. New container terminals do this automatically.

✅ Expected: ends with `Summary: N packages finished` and no `failed` packages.

Rebuild whenever you change code. With `--symlink-install`, edits to Python
files, launch files and configs take effect without rebuilding. C++ changes and
new files always need a rebuild.

### Step 4: Launch the simulation

📦 **CONTAINER**

```bash
ros2 launch cora_gazebo gazebo.launch.py
```

✅ Gazebo opens with the world and the Cora robot, then RViz opens with MoveIt.
After about 30 seconds the CoDI node starts.

To load a different world:

```bash
ros2 launch cora_gazebo gazebo.launch.py gazebo_world:=/ros_ws/src/cora_desktop/cora_gazebo/worlds/<file>.sdf
```

### Step 5: Stop

- Stop the simulation: **Ctrl+C** in the launch terminal.
- Leave a container terminal: `exit` (the container keeps running).
- Stop the container, 🖥️ **HOST**:

  ```bash
  docker compose stop      # pause it; `docker compose up -d` starts it again
  docker compose down      # or remove it entirely; `docker compose up -d` recreates it in seconds
  ```

Neither command touches your code or your `build/`/`install/` folders; those
live on your laptop.

### Summary: a normal day

```bash
# 🖥️ HOST
cd ~/dev/cora/cora_ws
docker compose up -d
docker compose exec dev bash

# 📦 CONTAINER
colcon build --symlink-install      # after code changes
ros2 launch cora_gazebo gazebo.launch.py
```

## Working in VS Code

You can edit files with any editor on the host; they're the same files the
container sees. To also get terminals, code completion and debugging *inside*
the container, attach VS Code to it:

1. Install the **Dev Containers** extension (`ms-vscode-remote.remote-containers`).
2. Start the container: 🖥️ **HOST** `docker compose up -d`.
3. In VS Code: **Ctrl+Shift+P** → **Dev Containers: Attach to Running
   Container…** → pick **`/cora-dev`**.
4. In the new window: **File → Open Folder** → `/ros_ws`.

Terminals in that window (**Ctrl+`**) are container terminals, with ROS loaded.
Install extensions such as Python and C/C++ in that window. VS Code installs
them inside the container, and reinstalls them automatically if the container
is recreated.

> Always start the container with `docker compose up -d` first, rather than
> letting VS Code create it. That way you always get the same settings
> (display, GPU) as on the command line.

---

# Part 3: reference

## What's in this folder

```
~/dev/cora/cora_ws/
├── README.md              ← this file
├── HOW_IT_WORKS.md        ← explanation of Docker, compose, vcstool, colcon, X11...
├── setup.sh               ← one-time setup (Part 1, step 6)
├── Dockerfile             ← recipe for the image
├── .dockerignore          ← which files Docker may see while building the image
├── compose.yaml           ← how to start the container (display, network, folders)
├── compose.nvidia.yaml    ← extra settings for NVIDIA GPUs
├── .env                   ← your laptop's settings (written by setup.sh); not shared
├── .gitignore             ← keeps src/, build output and .env out of git
├── docker/cora.bashrc     ← loaded in every container terminal (sources ROS)
├── desktop.repos          ← which repos + versions to download, for desktop work
├── robot.repos            ← same, for the real robot
├── src/                   ← the downloaded repos (your code)
└── build/ install/ log/   ← created by colcon build
```

Inside the container, this whole folder is at `/ros_ws`.

## What's in the image

The `Dockerfile` starts from the official `osrf/ros:jazzy-desktop-full` image
(ROS 2 Jazzy, Gazebo Harmonic, RViz) and adds:

1. Tools: `sudo`, `git`, `nano`, and `glxinfo`/`xeyes` for testing the display.
2. A user `cora` with the same user ID as you, so files created in the container
   are owned by you on your laptop (not by `root`). It can use `sudo` without a
   password.
3. **CoDI**, the Cora communication library. It is pinned to one version
   (`CODI_REF` in the Dockerfile), because newer CoDI versions changed the API
   that our `cora_common` version uses. Update `CODI_REF` together with
   `cora_common`.
4. All ROS dependencies of the packages in `src/`, installed by `rosdep` from
   their `package.xml` files. This replaces the old `install.sh` scripts.

## Manual setup (what setup.sh does)

If you'd rather do Part 1, step 6 by hand, or want to see what the script
does. 🖥️ **HOST**, in `~/dev/cora/cora_ws`:

```bash
# 1. Machine settings: your user/group ID and the GPU render group
printf 'USER_UID=%s\nUSER_GID=%s\nRENDER_GID=%s\n' $(id -u) $(id -g) $(getent group render | cut -d: -f3) > .env

# 1b. Only with an NVIDIA GPU + NVIDIA Container Toolkit:
echo 'COMPOSE_FILE=compose.yaml:compose.nvidia.yaml' >> .env

# 2. Download the repos (no --recursive! see "Desktop vs. robot" below)
mkdir -p src
vcs import --skip-existing src < desktop.repos

# 3. Build the image
docker compose build
```

`docker compose build` is the same as
`docker build -t cora-dev:jazzy --build-arg USER_UID=... --build-arg USER_GID=... .`,
but takes the values from `.env`.

## When to rebuild the image

The image only contains dependencies, not your code. Rebuild it (🖥️ **HOST**:
`docker compose build`, then `docker compose up -d`) when:

- a `package.xml` gets a new dependency,
- the `Dockerfile` or `docker/cora.bashrc` changes,
- you want the latest ROS package updates: `docker compose build --pull --no-cache`.

**Not** needed for code changes; use `colcon build` in the container instead.

## Adding a dependency

1. Add it to the right `package.xml` using its **rosdep key**, e.g.
   `<exec_depend>python3-numpy</exec_depend>` (not `numpy`). Look keys up with
   `rosdep resolve <key>` in the container, or at <https://index.ros.org>. One
   invalid key makes the whole image build fail.
2. Rebuild the image (see above).

Don't `sudo apt install` things inside the container as a permanent fix. That
works until the container is recreated, and then it's gone (and teammates never
got it). It's fine for quickly trying something out.

## Updating the repos

🖥️ **HOST**, in `~/dev/cora/cora_ws`:

```bash
vcs status src                      # git status of all repos
vcs pull src                        # git pull in all repos that are on a branch
vcs import src < desktop.repos      # apply changed versions in desktop.repos
vcs export src --exact > snapshot.repos   # record the exact commits you're on
```

You still use normal `git` (commit, push, branches) inside each repo in `src/`.

`cora_common` is pinned to a commit, so it shows `HEAD detached at 161ee79`.
That is expected. Create a branch (`git switch -c my-branch`) before making
changes in it.

## Desktop vs. robot

| File | Contents | Use for |
|---|---|---|
| `desktop.repos` | `cora_common` @ `161ee79` (2026-07-11) + `cora_desktop` @ `main` | Laptop: simulation, MoveIt |
| `robot.repos` | `cora_common` @ `c2d6518` (2026-02-10) + `cora_robot` @ `main` | The robot's computer (ODrive/CAN hardware) |

These are the `cora_common` versions that `cora_desktop` and `cora_robot`
currently point to. Use one `.repos` file per workspace. If you import both,
the last one decides which `cora_common` you get.

Never use `vcs import --recursive` here. `cora_desktop` and `cora_robot` contain
`cora_common` as a git submodule. Without `--recursive` that submodule folder
stays empty, so there's only one `cora_common` (the top-level one) in the
workspace. With it, you'd get two copies of the same packages, and one would
silently replace the other.

## ROS networking

The container shares your laptop's network. By default ROS only talks to nodes
on your own laptop (`ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`), so you don't
see teammates' simulations on the same Wi-Fi. To talk to the real robot, add
this to `.env` and run `docker compose up -d`:

```
ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
ROS_DOMAIN_ID=<same number as the robot>
```

## Going back to the old setup

The old containers (`ros-jazzy`, `ros-jazzy-gpu`) and folders
(`~/dev/cora/src/docker_workspace`) are untouched. Don't run both setups at once
(ROS nodes would see each other). 🖥️ **HOST**:

```bash
cd ~/dev/cora/cora_ws && docker compose stop     # stop the new one
docker start ros-jazzy-gpu                        # start the old one
xhost +local:root
```

And back: `docker stop ros-jazzy-gpu`, then `docker compose up -d`.

## Local changes in cora_common and cora_desktop

`cora_common` and `cora_desktop` are **separate GitHub repos**
(`C-O-R-A/cora_common`, `C-O-R-A/cora_desktop`). To make this setup work, both
needed changes. They are pushed to a branch `fix/package-deps` in each repo
(`cora_common` commit `e9bbdd4`, `cora_desktop` commit `20c3c01`), not merged
into `main` yet.

### cora_common (based on commit `161ee79`)

Only `package.xml` files changed; no code. The image installs dependencies with
`rosdep` from these files, so every package now lists what it actually imports
or launches.

| File | Change | Why |
|---|---|---|
| `cora_moveit_config/package.xml` | Removed `<exec_depend>numpy</exec_depend>` | `numpy` is not a valid rosdep key (the right key is `python3-numpy`). This one line made `rosdep install`, and therefore the whole image build, fail. |
| `cora_moveit_config/package.xml` | Added `joint_state_broadcaster`, `joint_trajectory_controller`, `parallel_gripper_controller`, `hardware_interface`, `gz_ros2_control` | The controllers in `config/ros2_controllers.yaml` and the ros2_control plugins used by the xacros (Fake/Gazebo). Without them a fresh image may not have them installed. `odrive_ros2_control` (Real) lives in `cora_robot` and is deliberately not listed. |
| `cora_moveit/package.xml` | Added `moveit_py`, `moveit_servo`, `moveit_configs_utils`, `moveit_ros_move_group`, `controller_manager`, `robot_state_publisher`, `rviz2`, `tf2_ros`, `xacro`, `launch`, `launch_ros`, `rclpy`, `geometry_msgs`, `control_msgs`, `ament_index_python`, `python3-numpy`, `python3-yaml`, and the workspace packages `cora_msgs`, `cora_moveit_config`, `cora_moveit_cpp` | Python imports in `cora_moveit/*.py` and the nodes started by `launch/move.launch.py`. `moveit_py` and `moveit_servo` were missing, so a fresh image didn't have them. |
| `cora_codi/package.xml` | Added `ament_index_python`, `control_msgs`, `cora_msgs`, `geometry_msgs`, `lifecycle_msgs`, `moveit_msgs`, `tf2_ros`, `launch`, `launch_ros`, `moveit_configs_utils`, `python3-numpy` | Python imports in `cora_codi/codi.py` and `launch/codi.launch.py`. The `codi` Python library itself isn't in rosdep; the Dockerfile installs it with pip. |
| `cora_vision/package.xml` | Added `python3-scipy`, `geometry_msgs`, `lifecycle_msgs`, `tf2_ros`, plus a TODO comment about `cora_vision_msgs` | Python imports in `cora_vision/*.py`. |
| `cora_bringup/package.xml` | Added `cora_codi`, `cora_moveit` | The bringup launch files start nodes from these packages. |

Also showing as changed: four `__pycache__/*.pyc` files. Those are generated by
running the code, not real changes. Don't commit them (see the open issues below).

### cora_desktop (based on `main`, commit `4ce5497`)

| File | Change | Why |
|---|---|---|
| `cora_gazebo/package.xml` | Added `ament_index_python`, `launch`, `launch_ros`, `xacro`, `robot_state_publisher`, `moveit_configs_utils`, `ros_gz_sim`, `ros_gz_bridge`, `gz_ros2_control`, and the workspace packages `cora_bringup`, `cora_description`, `cora_gripper_1_description`, `cora_moveit_config` | Everything `launch/gazebo.launch.py` uses. The file listed no runtime dependencies at all, so rosdep installed none of the Gazebo integration. |
| `cora_gazebo/launch/gazebo.launch.py` | The `gazebo_world` argument now defaults to `cora_gazebo/worlds/main_world.sdf` instead of the string `"None"` | With `"None"` you had to pass `gazebo_world:=...` every time; now `ros2 launch cora_gazebo gazebo.launch.py` works on its own. |

### Next steps

1. Open a pull request from `fix/package-deps` to `main` in both repos.
2. In `desktop.repos`: point `cora_common` and `cora_desktop` to
   `fix/package-deps` (or to `main` once merged). Then Part 1, step 5 no
   longer needs the manual `git switch`.
3. Optionally update `cora_desktop`'s `cora_common` submodule to the same
   commit, so the two stay in sync.

## Open issues (still to fix)

Ordered by importance.

1. **CoDI node crashes ~30 s after launch** (`cora_common`). The simulation
   itself (Gazebo, RViz, MoveIt, controllers) works, but `codi_node` dies with
   `TypeError: 'NoneType' object cannot be interpreted as an integer` in
   `socket.bind`. Cause: the CoDI version in the image (`b475de3`) reads ports
   from a nested `ports:` section, but `cora_codi/config/server_params.yaml`
   lists them at the top level, so every port is `None`. Fix: nest them:
   ```yaml
   host: 0.0.0.0
   ports:
     video_port: 5000
     command_port: 5001
     states_port: 5002
     config_port: 5003
     vision_port: 5004
   ```
   (Or pin a CoDI version that matches the flat format; then also update the
   `CODI_REF` comment in the `Dockerfile`, which claims `b475de3` matches
   `cora_common 161ee79`.)
2. **The fixes above aren't merged and `desktop.repos` doesn't point to them.**
   That's why Part 1, step 5 switches to `fix/package-deps` by hand.
3. **`desktop.repos` and `robot.repos` pin different `cora_common` commits**
   (`161ee79` from 2026-07-11 vs `c2d6518` from 2026-02-10). One workspace can
   only hold one, and the `package.xml` fixes only exist on top of `161ee79`.
   `cora_robot` should be moved to the newer `cora_common` (and get the same
   kind of `package.xml` fixes) so both use one version.
4. **Old install scripts conflict with the Docker setup.** `cora_common/install.sh`
   and `cora_desktop/install.sh` run `pip install -r requirements.txt`, which
   installs CoDI *with* its dependencies: that can pull numpy 2.x (breaks ROS's
   Python modules, built against numpy 1.26) and `opencv-python` (bundles Qt,
   clashes with RViz/Gazebo). Don't run them; remove them or mark them as the
   old non-Docker setup. `requirements.txt` should also pin the CoDI commit.
5. **`__pycache__` files are committed in `cora_common`**, so `git status`
   shows changed `.pyc` files after every run. Harmless; ignore them
   or restore with `git checkout -- '*.pyc'`. Real fix: `git rm --cached` them
   and add `__pycache__/` to `cora_common`'s `.gitignore`.
6. **`cora_vision`** imports `cora_vision_msgs`, which no repo provides. The
   vision node can't run (it isn't part of the simulation launch).

## Troubleshooting

| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | You're not in the `docker` group yet: `sudo usermod -aG docker $USER`, then log out and in. |
| `no configuration file provided: not found` | You're not in `~/dev/cora/cora_ws`. `cd` there first. |
| `DISPLAY is not set` | Run `docker compose up -d` from a terminal on your desktop, not over SSH. |
| `xeyes` / Gazebo: `cannot open display` or `Authorization required` | You logged out and in since the container was started. 🖥️ **HOST**: run `docker compose up -d` again; it recreates the container with your new login. |
| `ros2: command not found` | You're on the host, not in the container. Run `docker compose exec dev bash` first. |
| `colcon build` fails with `Could not find a package configuration file provided by "ament_cmake"` | You ran `colcon build` on the host (prompt `you@laptop:~/dev/cora/cora_ws$`) instead of in the container (prompt `cora@laptop:/ros_ws$`). 🖥️ **HOST**: `rm -rf build install log` (the failed host build leaves these behind and they break the next build), then `docker compose exec dev bash` and build there. |
| `colcon build` fails with `The current CMakeCache.txt directory ... is different` | `build/` was created somewhere else (on the host, or in another container). 🖥️ **HOST**: `rm -rf build install log`, then build again in the container. |
| `package 'cora_...' not found` | The workspace isn't built or sourced. 📦 **CONTAINER**: `colcon build --symlink-install && source install/setup.bash`. |
| `vcs import` fails with `Permission denied (publickey)` | GitHub SSH key not set up (Part 1, step 2). |
| Image build fails at `rosdep install` with `Cannot locate rosdep definition for [xyz]` | `xyz` in a `package.xml` isn't a valid rosdep key. Find it with `grep -rn xyz src/*/*/package.xml` and fix it (see [Adding a dependency](#adding-a-dependency)). |
| Gazebo is slow / `glxinfo -B` shows `llvmpipe` | Software rendering. With NVIDIA: check that `.env` contains the `COMPOSE_FILE=...nvidia...` line, then `docker compose up -d`. With Intel/AMD: check that `RENDER_GID` in `.env` matches `getent group render`. |
| `container name "/cora-dev" is already in use` | A container with that name exists from an earlier attempt. `docker rm -f cora-dev`, then `docker compose up -d`. |
