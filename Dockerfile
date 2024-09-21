FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

#ARG CURA_DOWNLOAD=https://github.com/Ultimaker/Cura/releases/download/4.8.0/Ultimaker_Cura-4.8.0.AppImage
ARG CURA_DOWNLOAD=https://github.com/Ultimaker/Cura/releases/download/5.8.1/UltiMaker-Cura-5.8.1-linux-X64.AppImage
ARG NOVNC_DOWNLOAD=https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.zip

# === Cura Download dependencies =====================
RUN     apt-get update \
    &&  apt-get install -y --no-install-recommends \
            curl \
            ca-certificates

# AppImages typically require FUSE (Filesystem in Userspace) to run because they mount themselves as a filesystem when
# executed. Inside a Docker container, FUSE is generally not available by default, and adding FUSE support can be
# complex, as it requires special privileges and configurations.
RUN     mkdir -p /opt/cura
RUN     curl -L -o /opt/cura/cura.AppImage ${CURA_DOWNLOAD}
RUN     chmod +x /opt/cura/cura.AppImage
RUN     /opt/cura/cura.AppImage --appimage-extract
RUN     mv squashfs-root /opt/cura/extracted
RUN     chmod 777 -R /opt/cura/

# === Code dependencies =====================================================
RUN     apt-get update \
    &&  apt-get install -y --no-install-recommends \
            xvfb \
            x11vnc \
            openbox \
            net-tools \
            python3 \
            python3-pip \
            python3-fastapi \
            python3-jinja2 \
            python3-multipart \
            python3-uvicorn \
            libfontconfig1 \
            fontconfig \
            libqt5widgets5 \
            libqt5gui5 \
            libqt5core5a \
            qt5-gtk-platformtheme \
            thunar \
            libgtk-3-0 \
            libglib2.0-bin \
            dbus-x11 \
            gvfs \
            gvfs-backends \
            unzip

# Force Qt to use software rendering:
ENV LIBGL_ALWAYS_SOFTWARE=1

# Set environment variables for Qt and X11
ENV QT_X11_NO_MITSHM=1
ENV QT_QPA_PLATFORM=xcb
ENV QT_DEBUG_PLUGINS=1
#ENV LD_LIBRARY_PATH=/opt/cura/extracted/usr/lib:$LD_LIBRARY_PATH
ENV QT_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/qt5/plugins


# === Cura dependencies ==============================================================================================
RUN     apt-get update \
    &&  apt-get install -y --no-install-recommends \
            python3-numpy \
            libxkbcommon-x11-0 \
            libxcb-xinerama0 \
            libegl1 \
            libgl1 \
            libgl1-mesa-dev \
            libgl1-mesa-dri \
            libglu1-mesa \
            libgles2 \
            libgles2-mesa-dev \
            libglu1 \
            libglu1-mesa-dev \
            mesa-utils \
            mesa-utils-bin \
            libxcb1 \
            libxcb-xinerama0 \
            libxcb-icccm4 \
            libxcb-image0 \
            libxcb-keysyms1 \
            libxcb-randr0 \
            libxcb-render0 \
            libxcb-shape0 \
            libxcb-shm0 \
            libxcb-sync1 \
            libxcb-xfixes0 \
            libxcb-xkb1 \
            libxkbcommon-x11-0 \
            qtbase5-dev \
            libxkbcommon-x11-0 \
            libx11-xcb1 \
            libfontconfig1 \
            libdbus-1-3 \
            libqt5core5a \
            libqt5gui5 \
            libqt5widgets5 \
            libx11-xcb1 \
            libxcb1 \
            libxcb-xinerama0 \
            libxcb-icccm4 \
            libxcb-image0 \
            libxcb-keysyms1 \
            libxcb-randr0 \
            libxcb-render0 \
            libxcb-shape0 \
            libxcb-shm0 \
            libxcb-sync1 \
            libxcb-xfixes0 \
            libxcb-xkb1 \
            libxkbcommon-x11-0


RUN pip3 install --break-system-packages pyserial

# === NOVNC ==========================================================================================================
ENV NOVNC_DIR=/opt/novnc
RUN     mkdir -p ${NOVNC_DIR} \
    &&  curl -L -o /opt/novnc.zip ${NOVNC_DOWNLOAD} \
    &&  unzip /opt/novnc.zip -d ${NOVNC_DIR} \
    &&  mv /opt/novnc/noVNC-*/* /opt/novnc/ \
    &&  chmod 777 -R ${NOVNC_DIR}/ \
    &&  rm /opt/novnc.zip

# === APPLICATION CONFIG =============================================================================================
# Set environment variables for Qt and X11
ENV STL_DIR="/opt/stl-files"
ENV HOME="/home/user"
ENV USER="user"
ENV USER_ID="1000"
ENV GROUP_ID="1000"
ENV RESOLUTION_X="1920"
ENV RESOLUTION_Y="1080"

ENV XDG_RUNTIME_DIR="/tmp/runtime-user"
ENV XDG_CONFIG_HOME="/home/user/.config"
ENV XDG_DATA_HOME="/home/user/.local/share"

RUN     mkdir -p $XDG_RUNTIME_DIR \
    &&  chmod -R 777 $XDG_RUNTIME_DIR \
    &&  mkdir -p $XDG_CONFIG_HOME \
    &&  chmod -R 777 $XDG_CONFIG_HOME \
    &&  mkdir -p $XDG_DATA_HOME \
    &&  chmod -R 777 $XDG_DATA_HOME \
    &&  mkdir -p /tmp/.X11-unix \
    &&  chmod -R 777 /tmp/.X11-unix \
    &&  mkdir -p /run/media/${USER} \
    &&  chmod -R 777 /run/media/${USER} \
    &&  mkdir -p $HOME \
    &&  chmod -R 777 $HOME \
    &&  mkdir -p $STL_DIR \
    &&  chmod -R 777 $STL_DIR \
    &&  mkdir -p /opt/app \
    &&  chmod -R 777 /opt/app

WORKDIR /opt/app

# Copy the application code
ADD cura_docker_web_service /opt/app/cura_docker_web_service
ADD templates /opt/app/templates
ADD LICENSE .
ADD README.md .

CMD ["python3", "-m", "cura_docker_web_service.main"]
