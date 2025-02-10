FROM debian:bullseye-slim

# Use "bash" as replacement for	"sh"
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

RUN apt-get update
RUN apt-get -y upgrade
RUN apt-get -y autoremove

RUN DEBIAN_FRONTEND=noninteractive apt-get -y install git tmux curl gcc g++ make cmake libuv1-dev libssl-dev libsodium-dev autoconf libnet1-dev libtool pastebinit python3 bash gdb dnsutils nano inetutils-ping net-tools sudo iproute2 build-essential
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN apt-get install -y clang

RUN git clone https://github.com/Raycoms/narwhal.git && cd /narwhal && git pull && cd benchmark
RUN cd narwhal/node && cargo build --quiet --release --features benchmark
EXPOSE 4000-6000
ADD ./server.sh /

ENTRYPOINT ["/bin/bash", "/server.sh"]
