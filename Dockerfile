#
# base
#
FROM  ubuntu:16.04

#
# common-environment
#
ENV USER lofar
ENV INSTALLDIR /home/${USER}/opt

#
# environment
#
ENV DEBIAN_FRONTEND noninteractive

ENV DIRBASE taql-jupyter
ENV REPO_ORG tammojan
ENV REPO https://github.com/${REPO_ORG}/${DIRBASE}
ENV BRANCH binder

#
# set-build-options
#
ENV J 4

USER root
#
# base
#
RUN apt-get update
RUN apt-get upgrade -y

RUN apt-get -y install software-properties-common git curl python-pip 

RUN add-apt-repository -y ppa:kernsuite/kern-dev

RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash

RUN apt-get -y install git-lfs

#
# setup-account
#
RUN getent group sudo &>/dev/null || groupadd sudo
RUN echo "useradd -m ${USERADD_FLAGS} ${USER}"
RUN useradd -m ${USER}

RUN apt-get update
RUN apt-get install -y python-casacore

# Install jupyterhub
RUN apt-get install -yq python3-pip 
RUN python3 -m pip install jupyterhub notebook
RUN pip install --upgrade pipp
RUN pip install notebook

#
# install taql kernel
# 
USER ${USER}
RUN mkdir -p ${INSTALLDIR}
RUN mkdir -p /home/${USER}/work

RUN cd ${INSTALLDIR} && git clone ${REPO}
RUN cd ${INSTALLDIR}/${DIRBASE} && git checkout ${BRANCH} && \
    git lfs pull 
ENV PYTHONPATH /home/lofar/opt/${DIRBASE}
RUN mkdir -p /usr/local/share/jupyter/kernels
USER root
RUN ln -s /home/lofar/opt/${DIRBASE}/taql /usr/local/share/jupyter/kernels
USER ${USER}
RUN ln -s ${INSTALLDIR}/taql-jupyter/LearnTaQL.ipynb /home/${USER}/work
RUN cd /home/${USER}/work && tar xf /home/${USER}/opt/${DIRBASE}/demodata.tgz
RUN mkdir -p /home/${USER}/.jupyter/custom
RUN ln -s ${INSTALLDIR}/taql-jupyter/custom.css /home/${USER}/.jupyter/custom
RUN cp -r /usr/share/casacore/data/geodetic/Observatories /home/${USER}/work/
RUN cd ${INSTALLDIR}/taql-jupyter && git pull

ENV PYTHONPATH /home/${USER}/opt/taql-jupyter/taql


USER ${USER}

EXPOSE 8888/tcp
WORKDIR /home/${USER}/work
