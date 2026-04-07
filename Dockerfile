FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${PATH}"
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# ── System packages ───────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Core
    curl wget unzip git jq flock \
    # Java (Android build requirement)
    openjdk-17-jdk \
    # Build tools
    build-essential \
    # Display / emulator
    xvfb x11-utils \
    libgl1-mesa-glx libgl1-mesa-dri \
    # Video
    ffmpeg \
    # Python (telegram bot)
    python3 python3-pip \
    # KVM tools
    qemu-kvm libvirt-dev \
    # GitHub CLI
    gh \
    # Misc
    procps lsof \
    && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI auth (token injected at runtime via env) ───────
# Handled in entrypoint, not baked in

# ── Android SDK ───────────────────────────────────────────────
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    cd /tmp && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
         -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools \
       ${ANDROID_HOME}/cmdline-tools/latest && \
    rm cmdline-tools.zip

RUN yes | sdkmanager --licenses > /dev/null 2>&1 && \
    sdkmanager \
      "platform-tools" \
      "emulator" \
      "build-tools;34.0.0" \
      "platforms;android-34" \
      "system-images;android-34;google_apis;x86_64"

# ── Create AVD ────────────────────────────────────────────────
RUN echo "no" | avdmanager create avd \
      -n Pixel_6_API_34 \
      -k "system-images;android-34;google_apis;x86_64" \
      -d "pixel_6" \
      --force

# ── Python deps (Telegram bot) ────────────────────────────────
RUN pip3 install python-telegram-bot==20.7 --break-system-packages

# ── Claude Code (native installer) ───────────────────────────
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

# ── Scripts ───────────────────────────────────────────────────
WORKDIR /agent
COPY scripts/ ./scripts/
COPY web/     ./web/
COPY bot/     ./bot/
COPY cron/    ./cron/
COPY config/  ./config/
RUN chmod +x ./scripts/*.sh ./scripts/roles/*.sh

HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3     CMD /agent/scripts/healthcheck.sh || exit 1

ENTRYPOINT ["/agent/scripts/entrypoint.sh"]
