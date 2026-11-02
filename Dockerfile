# Builds the QQ image. Start the container with compose.yaml, not with this file.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
COPY QQ.deb /tmp/QQ.deb
# libasound2: sound output.
# libgbm1: buffer allocation for GPU drawing.
# fonts-noto-cjk: Chinese fonts. The container cannot use the fonts of the host.
# libx11-xcb1: QQ starts as a background process with no window if this package is absent.
# libegl1, libgl1-mesa-dri: OpenGL and the Mesa drivers.
RUN apt-get update \
 && apt-get install -y --no-install-recommends /tmp/QQ.deb \
 && apt-get install -y --no-install-recommends libasound2 libgbm1 \
      libegl1 libgl1-mesa-dri libx11-xcb1 \
      fonts-noto-cjk fontconfig ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists /tmp/QQ.deb \
 && mkdir -p /home/qq \
 && chown 65534:65534 /home/qq
# This file does not set a user. compose.yaml sets the user to uid 65534.
ENV HOME=/home/qq \
    QT_ACCESSIBILITY=0
# --no-sandbox: Chrome normally uses a setuid helper to build its sandbox. That helper
# cannot work when the container has no capabilities. The container is the sandbox: it has
# no capabilities, a seccomp filter, its own namespaces, and a read-only root file system.
# --disable-dev-shm-usage: use /tmp instead of /dev/shm for shared memory.
# --ozone-platform=x11: use XWayland. QQ does not create a Wayland window on GNOME. A test
# with the XDG protocol shows no xdg_toplevel object.
# --disable-crash-reporter: crash reports would go to Tencent with your internet traffic.
ENTRYPOINT ["/opt/QQ/qq", "--no-sandbox", "--disable-dev-shm-usage", "--ozone-platform=x11", "--disable-crash-reporter"]
