# Cora development workspace

Build and run the Cora software (ROS 2 Jazzy, Gazebo, MoveIt 2) inside a Docker
container.

- **HOST:** a normal terminal on your laptop. Prompt: `you@laptop:~$`.
- **CONTAINER:** a terminal inside the container. Prompt: `cora@laptop:/ros_ws$`.

For background on how it all works, see [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

**On Windows 11?** Do [Step 0](#step-0-windows-11-only-wsl2-and-ubuntu) first.
After that, "HOST" means the **Ubuntu (WSL) terminal**, never PowerShell, and
the rest of this README applies as written.

---

# Part 1: one-time setup

### Step 0 (Windows 11 only): WSL2 and Ubuntu

The container needs a Linux kernel. On Windows, WSL2 provides one, and WSLg
shows Gazebo and RViz as normal Windows windows.

1. Update your GPU driver from the vendor's website (NVIDIA, AMD or Intel).
   Current drivers include WSL GPU support.
2. In **PowerShell (as administrator)**:

   ```powershell
   wsl --install -d Ubuntu-24.04
   ```

   Reboot if asked. Ubuntu then opens and asks for a new username and password.
3. In **PowerShell**, make sure WSL is up to date, then check that it lists
   a `WSLg version`:

   ```powershell
   wsl --update
   wsl --version
   ```

4. From now on, work in the **Ubuntu** terminal (Start menu → Ubuntu 24.04).
   Check that it shows windows:

   ```bash
   sudo apt update && sudo apt install -y x11-apps
   xeyes                             # a window with eyes opens on Windows
   ```

Things that differ from a Linux laptop:

- **Docker:** install Docker Engine *inside Ubuntu* as in Step 1. Docker
  Desktop isn't needed. If you already have it, turn off its WSL integration
  for Ubuntu-24.04 (Settings → Resources → WSL integration), otherwise `docker`
  talks to Docker Desktop instead.
- **SSH key (Step 2):** WSL doesn't see your Windows keys; make a new one in
  Ubuntu.
- **Skip Step 3 (NVIDIA).** In WSL, every GPU (NVIDIA included) works through
  `compose.wsl.yaml`, which `setup.sh` turns on automatically.
- **Keep the workspace inside WSL** (`~/dev/cora`), never under `/mnt/c/...`:
  files on the Windows drives are slow and break file permissions. To edit the
  code from Windows, use VS Code with the "WSL" extension (run `code .` in the
  workspace), or open `\\wsl$\Ubuntu-24.04\home\<you>` in Explorer.
- **Laptop with two GPUs?** If Gazebo runs on the integrated GPU, add
  `MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA` (or `AMD`) to `.env` after setup.
- **Real robot:** WSL's default network blocks the multicast ROS 2 uses to
  find other machines. Create `%UserProfile%\.wslconfig` in Windows containing

  ```ini
  [wsl2]
  networkingMode=mirrored
  ```

  then run `wsl --shutdown` in PowerShell. USB devices (e.g. the ODrive) must
  be attached to WSL with [usbipd-win](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

### Step 1: Install Docker, git and vcstool

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

### Step 2: Check your GitHub SSH key

🖥️ **HOST**

```bash
ssh -T git@github.com             # prints "Hi <your-username>! ..."
```

If you get `Permission denied (publickey)`, set up a key:
<https://docs.github.com/en/authentication/connecting-to-github-with-ssh>.

### Step 3 (NVIDIA GPU only): NVIDIA Container Toolkit

🖥️ **HOST.** Install the NVIDIA driver and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), then check:

```bash
docker run --rm --gpus all ubuntu nvidia-smi    # shows your GPU
```

### Step 4: Get the workspace

🖥️ **HOST**

```bash
mkdir -p ~/dev/cora && cd ~/dev/cora
git clone git@github.com:C-O-R-A/cora_docker.git cora_ws
```

### Step 5: Download the repos

🖥️ **HOST.** Use the `fix/package-deps` branch of `cora_common` and
`cora_desktop`, not `main`: `main` is missing dependency fixes and the image
build fails.

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

It checks the prerequisites, writes `.env` and builds the Docker image (first
time: ~6 GB download, 5–10 minutes). If something is marked ✘, fix it and run
it again.

It ends with `Setup complete`.

---

# Part 2: running it

Run these from a terminal on your desktop (not over SSH), so windows can open.

### Step 1: Start the container

🖥️ **HOST**

```bash
cd ~/dev/cora/cora_ws
docker compose up -d
docker compose exec dev bash
```

Run `docker compose up -d` again after every login or reboot.

### Step 2: Build

📦 **CONTAINER**

```bash
colcon build --symlink-install
source install/setup.bash
```

Ends with `Summary: N packages finished`. Rebuild after code changes.

### Step 3: Launch the simulation

📦 **CONTAINER**

```bash
ros2 launch cora_gazebo gazebo.launch.py
```

Gazebo opens with the Cora robot, then RViz with MoveIt.

> Known issue: the CoDI node crashes about 30 seconds after launch. The rest of
> the simulation keeps working.

### Step 4: Stop

- Simulation: **Ctrl+C**
- Container terminal: `exit`
- Container, 🖥️ **HOST**: `docker compose stop`
