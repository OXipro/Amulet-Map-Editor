#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

docker build -t amulet-editor .

xhost +local:docker
trap 'xhost -local:docker >/dev/null 2>&1 || true' EXIT

# wx's GL canvas is EGL. On this Wayland session the NVIDIA X11/Xwayland
# EGL platform does not come up, so hand GTK the real Wayland socket.
# /dev/dri is required for nvidia-drm_gbm to allocate the window buffers.
# The NVIDIA EGL vendor is forced, so Mesa cannot take the context.
auth_args=()
if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY}" ]]; then
  auth_args=(-e "XAUTHORITY=${XAUTHORITY}" -v "${XAUTHORITY}:${XAUTHORITY}:ro")
fi

gui_args=(-e GDK_BACKEND=x11)
if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
  gui_args=(
    -e GDK_BACKEND=wayland
    -e WAYLAND_DISPLAY
    -e XDG_RUNTIME_DIR
    -v "${XDG_RUNTIME_DIR}:${XDG_RUNTIME_DIR}"
  )
fi

docker run -it --rm \
  -e DISPLAY \
  -e HOME=/home/oxipro \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
  -e __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json \
  -e GBM_BACKENDS_PATH=/usr/lib/gbm:/usr/lib/x86_64-linux-gnu/gbm \
  "${auth_args[@]}" \
  "${gui_args[@]}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  --gpus all \
  --device /dev/dri \
  --network=host \
  --user "$(id -u):$(id -g)" \
  -v /home/oxipro:/home/oxipro \
  amulet-editor
