# Cora development workspace

Build and run the Cora software (ROS 2 Jazzy, Gazebo, MoveIt 2) inside a Docker
container.

- **HOST:** a normal terminal on your laptop. Prompt: `you@laptop:~$`.
- **CONTAINER:** a terminal inside the container. Prompt: `cora@laptop:/ros_ws$`.

For background on how it all works, see [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

---

# Part 1: one-time setup

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
mkdir -p src
vcs import src < desktop.repos
git -C src/cora_desktop switch fix/package-deps
git -C src/cora_desktop submodule update --init --recursive
git -C src/cora_desktop/cora_common switch fix/package-deps
```

`cora_common` is a git submodule inside `cora_desktop`
(`src/cora_desktop/cora_common`), not a separate repo in `src/`. Run
`vcs import` only once: running it again switches the repos back to `main`.

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

You're inside the container when the prompt starts with `cora@` and the folder
is `/ros_ws`. Check with `ls /.dockerenv` (exists only in the container).

> `groups: cannot find name for group ID …` when the shell opens is harmless:
> it is your laptop's GPU group, which has no name inside the container.

### Step 1b (optional): Open the code in VS Code

🖥️ **HOST.** The container must be running (Step 1).

First time:

1. Install the **Dev Containers** extension (`ms-vscode-remote.remote-containers`).
2. Open the **Remote Explorer** (left sidebar), pick **Dev Containers** at the top.
3. Under **Other Containers**, right-click **cora** → **Attach in New Window**.
4. In the new window: **Open Folder** → `/ros_ws` → **OK**.

The bottom-left corner shows `Container cora-dev:jazzy`, and **Terminal → New
Terminal** opens a shell inside the container (you can close the
`docker compose exec` terminal).

Next times: **File → Open Recent** (Ctrl+R) → `/ros_ws [Container cora-dev…]`.

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
