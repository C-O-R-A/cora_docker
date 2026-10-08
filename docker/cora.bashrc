# Sourced from ~/.bashrc of the container user (see Dockerfile).

# ROS 2 itself
source /opt/ros/jazzy/setup.bash

# The Cora workspace, once it has been built with colcon
if [ -f /ros_ws/install/setup.bash ]; then
  source /ros_ws/install/setup.bash
fi

# Tab completion for colcon
if [ -f /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash ]; then
  source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
fi
