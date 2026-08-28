FROM docker.io/cachyos/cachyos:latest

ENV LANG=en_US.UTF-8

RUN pacman -Syu --noconfirm && \
    pacman -S --needed --noconfirm \
        base-devel \
        git \
        sudo \
        wget \
        curl \
        jq \
        gnupg && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/builder/.gnupg && \
    chmod 700 /home/builder/.gnupg && \
    chown -R builder:builder /home/builder

RUN sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf && \
    sed -i 's/^COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q --threads=0 -)/' /etc/makepkg.conf

RUN printf '#!/bin/bash\nexec /usr/bin/pacman --ask 4 "$@"\n' > /usr/local/bin/pacman-for-makepkg && \
    chmod +x /usr/local/bin/pacman-for-makepkg

RUN rm -rf /etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*

USER builder
WORKDIR /src

CMD ["/bin/bash"]

LABEL maintainer="Monarch <https://monarchlinux.com>"
LABEL description="Monarch x86_64 package build environment"
LABEL version="2.0"
