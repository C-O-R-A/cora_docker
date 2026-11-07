# Cora development workspace

Build and run the Cora software (ROS 2 Jazzy, Gazebo Harmonic, MoveIt 2) on
your laptop.

For background on how it all works, see [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

## Which setup do I need?

ROS 2 Jazzy only runs on **Ubuntu 24.04**. Pick the row that matches your laptop:

| Your laptop | What you do | Instructions |
|---|---|---|
| **Ubuntu 24.04** | Install ROS 2 Jazzy directly. No Docker. | [A. Ubuntu 24.04](#a-ubuntu-2404-native-ros-2) |
| **Windows 11** | Install Ubuntu 24.04 in WSL2, then do A inside it. | [B. Windows 11](#b-windows-11-wsl2--ubuntu-2404) → [A](#a-ubuntu-2404-native-ros-2) |
| **Another Ubuntu** (e.g. 26.04) | Run ROS 2 inside an Ubuntu 24.04 Docker container. | [C. Other Ubuntu](#c-other-ubuntu-versions-docker) |

Contents:

- [A. Ubuntu 24.04: native ROS 2](#a-ubuntu-2404-native-ros-2)
- [B. Windows 11: WSL2 + Ubuntu 24.04](#b-windows-11-wsl2--ubuntu-2404)
- [C. Other Ubuntu versions: Docker](#c-other-ubuntu-versions-docker)
- [Working with the real robot](#working-with-the-real-robot)
- [Troubleshooting](#troubleshooting)

> **Branches:** use the `fix/package-deps` branch of `cora_desktop` and
> `cora_common`, not `main`. `main` is missing dependency fixes, so `rosdep`
> and the build fail. The steps below switch to it for you.

---

# A. Ubuntu 24.04: native ROS 2

Everything runs directly on your Ubuntu 24.04 install (or in Ubuntu 24.04 in
WSL, if you came from [B](#b-windows-11-wsl2--ubuntu-2404)). Run all commands in
a normal terminal.

## One-time setup

### A1. Install ROS 2 Jazzy and the build tools

This follows the [official install guide](https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html).

```bash
# Enable the Ubuntu "universe" repository
sudo apt update && sudo apt install -y software-properties-common curl
sudo add-apt-repository -y universe

# Add the ROS 2 apt repository
ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo $VERSION_CODENAME)_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

# ROS 2 Jazzy (includes RViz and Gazebo Harmonic) and the build tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y ros-jazzy-desktop-full \
  python3-rosdep python3-colcon-common-extensions python3-vcstool git

# rosdep: only needed once per computer
sudo rosdep init
rosdep update
```

Check: `ls /opt/ros` prints `jazzy`.

### A2. Check your GitHub SSH key

```bash
ssh -T git@github.com             # prints "Hi <your-username>! ..."
```

If you get `Permission denied (publickey)`, set up a key:
<https://docs.github.com/en/authentication/connecting-to-github-with-ssh>.

### A3. Get the workspace and the code

```bash
mkdir -p ~/dev/cora && cd ~/dev/cora
git clone git@github.com:C-O-R-A/cora_docker.git cora_ws
cd cora_ws

# Download cora_desktop into src/ and switch to the fixed branch
vcs import src < desktop.repos
git -C src/cora_desktop switch fix/package-deps

# cora_common is a git submodule of cora_desktop
git -C src/cora_desktop submodule update --init --recursive
git -C src/cora_desktop/cora_common switch fix/package-deps
```

Use `robot.repos` instead of `desktop.repos` for the real-robot packages.

### A4. Install the dependencies

```bash
cd ~/dev/cora/cora_ws
source /opt/ros/jazzy/setup.bash

# ROS packages that the code needs (MoveIt, ros2_control, ...), read from package.xml
rosdep install --from-paths src --ignore-src -y --rosdistro jazzy

# Python libraries for CoDI
sudo apt install -y python3-pip python3-numpy python3-opencv python3-msgpack python3-yaml

# CoDI itself (not a ROS package, so rosdep can't install it)
pip install --user --no-deps --break-system-packages \
  "opencv-python-headless==4.10.0.84" \
  "git+https://github.com/C-O-R-A/CoDI.git@b475de33da0788e36580edb394c627d7ac8c9a48"

# Check that CoDI works
python3 -c "from codi import CoraServer; print('CoDI OK')"
```

About the `pip` line:

- `--user` installs into `~/.local`, so the Python packages that come with
  Ubuntu are left alone.
- `--break-system-packages` is still needed, because Ubuntu 24.04 blocks
  `pip install` by default.
- The pinned OpenCV is needed because CoDI requires OpenCV 4.8 or newer, and
  Ubuntu 24.04 ships 4.6.
- The CoDI commit must match the `cora_common` version. See the comment in the
  `Dockerfile`, and update both together.

### A5. Load ROS automatically in every terminal

```bash
cat >> ~/.bashrc <<'EOF'

# --- Cora / ROS 2 Jazzy ---
source /opt/ros/jazzy/setup.bash
if [ -f ~/dev/cora/cora_ws/install/setup.bash ]; then
  source ~/dev/cora/cora_ws/install/setup.bash
fi
# Keep your ROS nodes on this computer (see "Working with the real robot")
export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
EOF
```

Close the terminal and open a new one.

## Daily use

### Build

```bash
cd ~/dev/cora/cora_ws
colcon build --symlink-install
source install/setup.bash
```

It ends with `Summary: N packages finished`. Rebuild after code changes.

### Launch the simulation

```bash
ros2 launch cora_gazebo gazebo.launch.py
```

Gazebo opens with the Cora robot, then RViz with MoveIt.

> Known issue: the CoDI node crashes about 30 seconds after launch. The rest of
> the simulation keeps working.

### Stop

Press **Ctrl+C** in the terminal that runs the simulation.

### Updating

When a `package.xml` changes (new dependencies), run the `rosdep install`
line from [A4](#a4-install-the-dependencies) again, then rebuild.

---

# B. Windows 11: WSL2 + Ubuntu 24.04

WSL2 runs a real Ubuntu 24.04 inside Windows. WSLg shows Gazebo and RViz as
normal Windows windows. You install Ubuntu once, then follow
[A](#a-ubuntu-2404-native-ros-2) inside it.

### B1. Update your GPU driver

Get the latest driver from your GPU vendor's website (NVIDIA, AMD or Intel).
Recent drivers include GPU support for WSL.

### B2. Install WSL and Ubuntu 24.04

In **PowerShell (as administrator)**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if asked. Ubuntu then opens and asks for a new username and password.
These are only for Ubuntu and don't have to match your Windows login.

### B3. Update WSL

In **PowerShell**:

```powershell
wsl --update
wsl --version          # must list a "WSLg version"
```

### B4. Check that Linux windows work

Open **Ubuntu 24.04** from the Start menu. From now on, type all commands in
this Ubuntu terminal, never in PowerShell.

```bash
sudo apt update && sudo apt install -y x11-apps
xeyes                  # a window with eyes opens on your Windows desktop
```

### B5. Continue with A

Follow [A. Ubuntu 24.04: native ROS 2](#a-ubuntu-2404-native-ros-2) from
step A1, in the Ubuntu terminal.

### Good to know on Windows

- **Keep the workspace inside WSL** (`~/dev/cora`), never under `/mnt/c/...`.
  Files on the Windows drives are slow and break file permissions.
- **Editing the code from Windows:** install VS Code with the "WSL" extension
  and run `code .` in the workspace. You can also open
  `\\wsl$\Ubuntu-24.04\home\<you>` in Explorer.
- **SSH key (A2):** WSL can't see the SSH keys you have in Windows. Create a
  new key in Ubuntu.
- **Laptop with two GPUs?** If Gazebo runs on the integrated GPU, add
  `export MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA` (or `AMD`) to `~/.bashrc`.
- **Real robot and USB devices:** see
  [Working with the real robot](#working-with-the-real-robot).
- **Prefer Docker?** Docker also works in WSL. Follow
  [C](#c-other-ubuntu-versions-docker) in the Ubuntu terminal. Notes for that
  setup:
  - Install Docker Engine inside Ubuntu. If you have Docker Desktop, turn off
    its WSL integration for Ubuntu-24.04 (Settings → Resources → WSL
    integration).
  - Skip step C3 (NVIDIA). In WSL, every GPU works through `compose.wsl.yaml`,
    which `setup.sh` turns on automatically.

---

# C. Other Ubuntu versions: Docker

ROS 2 Jazzy can't be installed on Ubuntu versions other than 24.04. This setup
runs Ubuntu 24.04 with ROS 2 in a Docker container instead. Your code stays on
your laptop and is shared with the container. You edit it with your normal
tools, and build and run it in the container.

Two kinds of terminal are used:

- 🖥️ **HOST:** a normal terminal on your laptop. Prompt: `you@laptop:~$`.
- 📦 **CONTAINER:** a terminal inside the container. Prompt: `cora@laptop:/ros_ws$`.

## One-time setup

### C1. Install Docker, git and vcstool

🖥️ **HOST.** Install Docker Engine: <https://docs.docker.com/engine/install/ubuntu/>
(not the Snap package, not Docker Desktop). Then:

```bash
sudo usermod -aG docker $USER
sudo apt install git python3-vcstool
```

Log out and back in, then check:

```bash
docker run --rm hello-world       # prints "Hello from Docker!"
```

### C2. Check your GitHub SSH key

🖥️ **HOST**

```bash
ssh -T git@github.com             # prints "Hi <your-username>! ..."
```

If you get `Permission denied (publickey)`, set up a key:
<https://docs.github.com/en/authentication/connecting-to-github-with-ssh>.

### C3. NVIDIA GPU only: NVIDIA Container Toolkit

🖥️ **HOST.** Skip this step for Intel or AMD graphics. Install the NVIDIA driver
and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html),
then check:

```bash
docker run --rm --gpus all ubuntu nvidia-smi    # shows your GPU
```

### C4. Get the workspace and the code

🖥️ **HOST**

```bash
mkdir -p ~/dev/cora && cd ~/dev/cora
git clone git@github.com:C-O-R-A/cora_docker.git cora_ws
cd cora_ws

vcs import src < desktop.repos
git -C src/cora_desktop switch fix/package-deps
git -C src/cora_desktop submodule update --init --recursive
git -C src/cora_desktop/cora_common switch fix/package-deps
```

### C5. Run the setup script

🖥️ **HOST**

```bash
~/dev/cora/cora_ws/setup.sh
```

The script:

- checks the prerequisites,
- writes `.env` with this laptop's settings,
- builds the Docker image. The first build downloads about 6 GB and takes
  5–10 minutes.

If it marks something with ✘, fix that and run the script again. It ends with
`Setup complete`.

## Daily use

Run these from a terminal on your desktop (not over SSH), so windows can open.

### Start the container

🖥️ **HOST**

```bash
cd ~/dev/cora/cora_ws
docker compose up -d
docker compose exec dev bash
```

Run `docker compose up -d` again after every login or reboot. To open more
container terminals, run `docker compose exec dev bash` in another host
terminal.

### Build

📦 **CONTAINER**

```bash
colcon build --symlink-install
source install/setup.bash
```

It ends with `Summary: N packages finished`. Rebuild after code changes.

### Launch the simulation

📦 **CONTAINER**

```bash
ros2 launch cora_gazebo gazebo.launch.py
```

Gazebo opens with the Cora robot, then RViz with MoveIt.

> Known issue: the CoDI node crashes about 30 seconds after launch. The rest of
> the simulation keeps working.

### Stop

- Simulation: **Ctrl+C**
- Container terminal: `exit`
- Container: 🖥️ **HOST** `docker compose stop`

### Updating

When a `package.xml` or the `Dockerfile` changes, rebuild the image with
🖥️ **HOST** `docker compose build`, then run `docker compose up -d`. You don't
need to rebuild the image after code changes. Running `colcon build` is enough.

---

# Working with the real robot

By default, ROS 2 only finds nodes on your own computer
(`ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`). This keeps your simulation from
mixing with your teammates' on the same Wi-Fi. To talk to the robot, connect
to its network and change the setting to `SUBNET`. Everyone on that network
must also use the same `ROS_DOMAIN_ID` (default `0`).

- **Native (A):** in `~/.bashrc`, change `LOCALHOST` to `SUBNET`, then open a
  new terminal.
- **Docker (C):** add `ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET` to `.env`, then
  run `docker compose up -d`.
- **Windows (B), extra steps:**
  - WSL's default network blocks the multicast traffic ROS 2 uses to find
    other machines. Create `%UserProfile%\.wslconfig` in Windows with this
    content, then run `wsl --shutdown` in PowerShell and reopen Ubuntu:

    ```ini
    [wsl2]
    networkingMode=mirrored
    ```

  - If the robot's nodes still don't show up in `ros2 node list`, allow the
    traffic through Windows Firewall.
  - USB devices (e.g. the ODrive) must be attached to WSL with
    [usbipd-win](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

---

# Troubleshooting

| Problem | Fix |
|---|---|
| `rosdep` says a package can't be found | Check you are on the `fix/package-deps` branches (`git -C src/cora_desktop branch --show-current`). |
| `ros2: command not found` | Open a new terminal, or run `source /opt/ros/jazzy/setup.bash`. |
| `Package 'cora_gazebo' not found` | Build first, then run `source install/setup.bash`. |
| `No module named 'codi'` | Run the `pip install` line from [A4](#a4-install-the-dependencies) again. |
| No windows open (WSL) | In PowerShell: `wsl --update`, then `wsl --shutdown`, and reopen Ubuntu. |
| Gazebo is very slow (WSL) | Update the GPU driver in Windows. `glxinfo -B` (from `mesa-utils`) should show `D3D12`, not `llvmpipe`. |
| Can't see the robot's nodes | See [Working with the real robot](#working-with-the-real-robot). |
