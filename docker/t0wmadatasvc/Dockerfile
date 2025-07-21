FROM registry.cern.ch/cmsweb/dmwm-base:pypi-20250716-stable
MAINTAINER Valentin Kuznetsov vkuznet@gmail.com

RUN sudo apt update -y && sudo apt install -y \
  build-essential \
  libmariadb-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENV USER=_t0wmadatasvc
ENV WDIR=/data
ENV HDIR=/home/$USER
ADD install.sh $WDIR/install.sh

# add new user
RUN useradd ${USER} && install -o ${USER} -d ${WDIR}
# add user to sudoers file
RUN echo "%$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# start the setup
RUN mkdir -p $WDIR
RUN mkdir -p $HDIR
RUN sudo chown -R $USER:$USER $WDIR
RUN sudo chown -R $USER:$USER $HDIR

# switch to user
USER ${USER}
WORKDIR ${WDIR}

# pass env variable to the build
ARG CMSK8S
ENV CMSK8S=$CMSK8S

# install
RUN $WDIR/install.sh

# run the service
ADD run.sh $WDIR/run.sh
ADD monitor.sh $WDIR/monitor.sh
ADD config.py $WDIR/config.py

USER $USER
WORKDIR $WDIR

ENV PATH="$PATH:${HDIR}/.local/bin/"
ENV PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}/etc/secrets:/home/_t0wmadatasvc/.local/lib/python3.12/site-packages"

CMD ["./run.sh"]
