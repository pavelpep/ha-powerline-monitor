ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}

# Build open-plc-utils, copy the two tools we use, then strip build deps.
RUN apk add --no-cache --virtual .build build-base linux-headers git \
 && apk add --no-cache mosquitto-clients iproute2 tcpdump \
 && git clone --depth 1 https://github.com/qca/open-plc-utils /tmp/oputils \
 && make -C /tmp/oputils \
 && cp /tmp/oputils/plc/plcstat /tmp/oputils/plc/plctool /usr/local/bin/ \
 && chmod +x /usr/local/bin/plcstat /usr/local/bin/plctool \
 && apk del .build \
 && rm -rf /tmp/oputils

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
