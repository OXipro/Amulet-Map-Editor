FROM ubuntu:24.04 AS builder

# Prevent interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships glibc 2.39. The host NVIDIA driver (615.x) EGL platform
# libraries need glibc >= 2.38. Ubuntu 22.04 (glibc 2.35) could not load them,
# so wx's EGL canvas fell back to Mesa llvmpipe and rendered on the CPU.
RUN apt-get update && apt-get install -y \
    python3.12-dev \
    python3.12-venv \
    python3-pip \
    git \
    libgtk-3-dev \
    wget \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v4.1.0/cmake-4.1.0-linux-x86_64.sh \
    && chmod +x cmake-4.1.0-linux-x86_64.sh \
    && ./cmake-4.1.0-linux-x86_64.sh --skip-license --prefix=/usr/local \
    && rm cmake-4.1.0-linux-x86_64.sh

RUN python3.12 -m venv /opt/build \
    && /opt/build/bin/pip install --upgrade pip
ARG wxpython=https://extras.wxpython.org/wxPython4/extras/linux/gtk3/ubuntu-24.04/wxpython-4.2.5-cp312-cp312-linux_x86_64.whl

# defaults to the latest version if no arg is given in build command.
ARG AMULET_VERSION=RELEASE
RUN if [ "$(echo "$AMULET_VERSION" | cut -c1-7)" = "CUSTOM:" ]; then \
        /opt/build/bin/pip wheel -w /wheels $wxpython "$(echo "$AMULET_VERSION" | cut -c8-)"; \
    elif [ "$AMULET_VERSION" = "RELEASE" ]; then \
        /opt/build/bin/pip wheel -w /wheels $wxpython amulet-map-editor; \
    elif [ "$AMULET_VERSION" = "BETA" ]; then \
        /opt/build/bin/pip wheel -w /wheels $wxpython "amulet-map-editor>=0b0"; \
    elif [ "$AMULET_VERSION" = "ALPHA" ]; then \
        /opt/build/bin/pip wheel -w /wheels $wxpython "amulet-map-editor>=0a0"; \
    else \
        /opt/build/bin/pip wheel -w /wheels $wxpython "amulet-map-editor==$AMULET_VERSION"; \
    fi

FROM ubuntu:24.04

# Prevent interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive

# glvnd dispatchers. libgl1 still pulls Mesa as a dependency; the EGL vendor
# is pinned to NVIDIA below so the canvas cannot fall back to llvmpipe.
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    libgtk-3-0t64 \
    dbus-x11 \
    libnotify4 \
    libsdl2-2.0-0 \
    libsm6 \
    libcurl4t64 \
    libsecret-1-0 \
    libpcre2-32-0 \
    xdg-utils \
    libopengl0 \
    libgl1 \
    libegl1 \
    libwayland-client0 \
    libwayland-cursor0 \
    libwayland-egl1 \
    libwayland-server0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
RUN python3.12 -m venv /opt/amulet \
    && /opt/amulet/bin/pip install --no-index --find-links=/wheels amulet-map-editor \
    && rm -rf /wheels

# Wayland EGL paints above any widget that overlaps the canvas. These files
# dock that UI beside the view when GDK_BACKEND=wayland.
COPY amulet_map_editor/programs/edit/edit.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/edit.py
COPY amulet_map_editor/programs/edit/api/canvas/edit_canvas.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/api/canvas/edit_canvas.py
COPY amulet_map_editor/programs/edit/api/ui/file.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/api/ui/file.py
COPY amulet_map_editor/programs/edit/api/ui/tool_manager.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/api/ui/tool_manager.py
COPY amulet_map_editor/programs/edit/api/ui/tool/base_operation_choice.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/api/ui/tool/base_operation_choice.py
COPY amulet_map_editor/programs/edit/plugins/tools/select.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/plugins/tools/select.py
COPY amulet_map_editor/programs/edit/plugins/tools/paste.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/plugins/tools/paste.py
COPY amulet_map_editor/programs/edit/plugins/tools/chunk.py \
    /opt/amulet/lib/python3.12/site-packages/amulet_map_editor/programs/edit/plugins/tools/chunk.py

# Fail closed on the NVIDIA ICD mounted at runtime, instead of silently
# falling back to Mesa software rendering. Mesa's libgbm only looks next to
# itself for backends; the proprietary GBM backend is mounted at /usr/lib/gbm.
ENV __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json \
    GBM_BACKENDS_PATH=/usr/lib/gbm:/usr/lib/x86_64-linux-gnu/gbm \
    NVIDIA_DRIVER_CAPABILITIES=all

ENTRYPOINT [ "/opt/amulet/bin/python", "-m", "amulet_map_editor" ]
