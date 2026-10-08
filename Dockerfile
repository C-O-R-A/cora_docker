# Development image for the Cora workspace (ROS 2 Jazzy + Gazebo Harmonic + MoveIt 2).
#
# Build (host, in ~/dev/cora/cora_ws). Normally `docker compose build` does this:
#   docker build -t cora-dev:jazzy --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) .
#
# Only the package.xml files from src/ end up in the image (see .dockerignore);
# the code is bind-mounted at runtime. Rebuild the image when a package.xml
# changes or when this file changes, not when you edit code.

FROM osrf/ros:jazzy-desktop-full

# ---------------------------------------------------------------------------
# Build arguments: values you can override at build time
# ---------------------------------------------------------------------------
# Container user. The UID/GID must match your host user so files created in
# the bind-mounted workspace are owned by you, not root.
ARG USERNAME=cora
ARG USER_UID=1000
ARG USER_GID=1000
# CoDI version. b475de3 (2026-06-13) is the last version with the API used by
# cora_common 161ee79 (the commit pinned in desktop.repos). Update both together.
ARG CODI_REF=b475de33da0788e36580edb394c627d7ac8c9a48

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# 1. General tools, plus the Python libraries CoDI needs (from apt, not pip,
#    so they match the versions ROS is built against)
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      sudo git less nano bash-completion \
      mesa-utils x11-apps \
      python3-pip \
      python3-numpy python3-opencv python3-msgpack python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. Non-root user with the host's UID/GID and passwordless sudo
#    The base image already has a user "ubuntu" with UID 1000; remove it first.
# ---------------------------------------------------------------------------
RUN if id -u ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi \
    && if ! getent group "${USER_GID}" >/dev/null; then groupadd --gid "${USER_GID}" "${USERNAME}"; fi \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash \
         --groups video "${USERNAME}" \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

# ---------------------------------------------------------------------------
# 3. CoDI (not a ROS package, so rosdep can't install it)
#    --no-deps: its dependencies come from apt (step 1), except OpenCV: CoDI
#    imports cv2.typing (OpenCV >= 4.8) and Ubuntu 24.04 ships 4.6. The pip
#    "headless" build is used because the regular one bundles Qt, which clashes
#    with RViz/Gazebo. It shadows the apt cv2 for Python only.
#    --break-system-packages: Ubuntu 24.04 refuses system-wide pip installs by
#    default; acceptable here because the image is a throwaway environment.
#    The last line fails the build if CoDI can't be imported.
# ---------------------------------------------------------------------------
RUN pip install --no-cache-dir --no-deps --break-system-packages \
      "opencv-python-headless==4.10.0.84" \
      "git+https://github.com/C-O-R-A/CoDI.git@${CODI_REF}" \
    && python3 -c "import numpy, cv2; from codi import CoraServer; print('numpy', numpy.__version__, 'cv2', cv2.__version__)"

# ---------------------------------------------------------------------------
# 4. ROS dependencies of all packages in src/, resolved by rosdep from their
#    package.xml files. This replaces the apt list in install.sh.
#    This layer is rebuilt whenever a package.xml changes.
# ---------------------------------------------------------------------------
COPY src /tmp/cora_manifests
RUN apt-get update \
    && rosdep update --rosdistro "${ROS_DISTRO}" \
    && rosdep install --from-paths /tmp/cora_manifests --ignore-src -y --rosdistro "${ROS_DISTRO}" \
    && rm -rf /var/lib/apt/lists/* /tmp/cora_manifests

# ---------------------------------------------------------------------------
# 5. Shell setup for the user: source ROS and the workspace in every terminal
# ---------------------------------------------------------------------------
COPY docker/cora.bashrc /etc/cora.bashrc
RUN echo "source /etc/cora.bashrc" >> "/home/${USERNAME}/.bashrc"

USER ${USERNAME}
# rosdep's package cache is per user; give the user one too.
RUN rosdep update --rosdistro "${ROS_DISTRO}"

WORKDIR /ros_ws
CMD ["bash"]
