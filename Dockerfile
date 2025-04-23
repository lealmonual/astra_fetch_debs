FROM registry.astralinux.ru/library/astra/ubi18:1.8.1uu1

LABEL Name=astrafetchdebs Version=0.0.1

# Disable certificate checking and package signature verification
ENV DEBIAN_FRONTEND=noninteractive
# Disable certificate verification
RUN echo 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99verify-peer.conf \
    && echo 'Acquire::https::Verify-Host "false";' >> /etc/apt/apt.conf.d/99verify-peer.conf \
    # Disable apt-key warnings
    && echo 'APT::Key::VerifyRelease "false";' > /etc/apt/apt.conf.d/99no-check-valid-until \
    # Disable signature verification
    && echo 'APT::Get::AllowUnauthenticated "true";' > /etc/apt/apt.conf.d/99allow-unauth \
    # Proceed without verification
    && echo 'Acquire::AllowInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99allow-unauth

#COPY ./sources.list /etc/apt/sources.list

COPY fetchdebs.sh /usr/local/bin/fetchdebs.sh

RUN chmod a+x /usr/local/bin/fetchdebs.sh

RUN apt-get -y update && \
    apt-get -y install dpkg-dev apt-utils

WORKDIR /fetcheddebs

ENTRYPOINT [ "/usr/local/bin/fetchdebs.sh" ]
