#
# base
#
FROM  ubuntu:14.04

#
# common-environment
#
ENV USER lofar
ENV INSTALLDIR /home/${USER}/opt

#
# environment
#
ENV DEBIAN_FRONTEND noninteractive
ENV PYTHON_VERSION 2.7

#
# versions
#
ENV CFITSIO_VERSION 3370
ENV WCSLIB_VERSION 4.25.1
ENV LOG4CPLUS_VERSION 1.1.x
ENV CASACORE_VERSION v2.0.3
ENV CASAREST_VERSION v1.3.1
ENV PYTHON_CASACORE_VERSION v2.0.0
ENV AOFLAGGER_VERSION v2.7.0
ENV LOFAR_VERSION 2_13_1

#
# set-uid
#
ENV UID 501

#
# set-build-options
#
ENV J 4

#
# base
#
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install sudo
RUN apt-get -y install git subversion wget
RUN apt-get -y install automake autotools-dev cmake make python-setuptools
RUN apt-get -y install  g++ gcc gfortran
RUN apt-get -y install libblas-dev libfftw3-dev python-dev liblapack-dev libpng-dev libxml2-dev python-numpy libreadline-dev libncurses-dev python-scipy liblog4cplus-dev
RUN apt-get -y install libboost-dev libboost-python-dev libboost-thread-dev libboost-system-dev libboost-filesystem-dev libboost-iostreams-dev libboost-signals-dev
RUN apt-get -y install bison bzip2 flex python-xmlrunner python-pip
RUN pip install pyfits pywcs python-monetdb

#
# setup-account
#
RUN getent group sudo &>/dev/null || groupadd sudo
RUN echo "useradd -m ${USERADD_FLAGS} ${USER}"
RUN useradd -m -u ${UID} ${USER}
# RUN usermod -a -G sudo ${USER}
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN sed -i 's/requiretty/!requiretty/g' /etc/sudoers

USER ${USER}

#
# install-cfitsio
#
RUN mkdir -p ${INSTALLDIR}/cfitsio/build
RUN cd ${INSTALLDIR}/cfitsio && wget --retry-connrefused ftp://anonymous@heasarc.gsfc.nasa.gov/software/fitsio/c/cfitsio${CFITSIO_VERSION}.tar.gz
RUN cd ${INSTALLDIR}/cfitsio && tar xf cfitsio${CFITSIO_VERSION}.tar.gz
RUN cd ${INSTALLDIR}/cfitsio/build && cmake -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/cfitsio/ ../cfitsio
RUN cd ${INSTALLDIR}/cfitsio/build && make -j ${J}
RUN cd ${INSTALLDIR}/cfitsio/build && make install

#
# install-casacore
#
RUN mkdir -p ${INSTALLDIR}/casacore/build
RUN cd ${INSTALLDIR}/casacore && git clone https://github.com/casacore/casacore.git src
RUN cd ${INSTALLDIR}/casacore/src && git pull
RUN mkdir -p ${INSTALLDIR}/casacore/data
RUN cd ${INSTALLDIR}/casacore/data && wget --retry-connrefused ftp://anonymous@ftp.astron.nl/outgoing/Measures/WSRT_Measures.ztar
RUN cd ${INSTALLDIR}/casacore/data && tar xf WSRT_Measures.ztar
RUN cd ${INSTALLDIR}/casacore/build && cmake -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/casacore/ -DDATA_DIR=${INSTALLDIR}/casacore/data -DCFITSIO_ROOT_DIR=${INSTALLDIR}/cfitsio/ -DBUILD_PYTHON=True -DUSE_OPENMP=True -DUSE_FFTW3=TRUE -DMODULE=ms -DCXX11=ON -DBUILD_TESTING=False ../src/
RUN cd ${INSTALLDIR}/casacore/build && make -j ${J}
# Rebuild for latest changes
RUN cd ${INSTALLDIR}/casacore/src && git pull 
RUN cd ${INSTALLDIR}/casacore/build && make -j ${J}
RUN cd ${INSTALLDIR}/casacore/build && make install

#
# install-python-casacore
#
RUN mkdir ${INSTALLDIR}/python-casacore
RUN cd ${INSTALLDIR}/python-casacore && git clone https://github.com/casacore/python-casacore
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && sed -i.bak -e '81,89d' setup.py
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && ./setup.py build_ext -I${INSTALLDIR}/casacore/include/ -L${INSTALLDIR}/casacore/lib/ -R${INSTALLDIR}/casacore/lib/

USER root
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && ./setup.py install

#
# install Jupyter
#
RUN apt-get -y install python-zmq
RUN apt-get remove -y python-pip python-setuptools python-pkg-resources
RUN wget https://bootstrap.pypa.io/get-pip.py && python get-pip.py
RUN pip install setuptools
RUN pip install jupyter

#
# copied from jupyter/minimal-notebook
#
USER root
RUN apt-get install -yq --no-install-recommends git vim wget build-essential ca-certificates bzip2 unzip libsm6 pandoc locales libxrender1
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
RUN locale-gen "en_US.UTF-8"
RUN wget --quiet https://github.com/krallin/tini/releases/download/v0.6.0/tini && echo "d5ed732199c36a1189320e6c4859f0169e950692f451c03e7854243b95f4234b *tini" | sha256sum -c - && mv tini /usr/local/bin/tini && chmod +x /usr/local/bin/tini
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV SHELL=/bin/bash
ENV NB_USER=${USER}
ENV NB_UID=1000
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

USER ${USER}
RUN mkdir /home/${USER}/work && mkdir /home/${USER}/.jupyter && mkdir /home/${USER}/.local

USER root
EXPOSE 8888/tcp
WORKDIR /home/${USER}/work

#
# install taql kernel
# 
RUN cd ${INSTALLDIR} && git clone https://github.com/tammojan/taql-jupyter
ENV PYTHONPATH /home/lofar/opt/taql-jupyter
RUN mkdir -p /usr/local/share/jupyter/kernels
RUN ln -s /home/lofar/opt/taql-jupyter/taql /usr/local/share/jupyter/kernels

RUN ln -s ${INSTALLDIR}/taql-jupyter/jupyter_notebook_config.py /home/${USER}/.jupyter/
ENV NB_USER=${USER}
RUN ln -s ${INSTALLDIR}/taql-jupyter/start-notebook.sh /usr/local/bin/
RUN ln -s ${INSTALLDIR}/taql-jupyter/LearnTaQL.ipynb /home/${NB_USER}/work
COPY demodata.tgz /home/${USER}/
RUN cd /home/${USER}/work && tar xf /home/${USER}/demodata.tgz
# CMD echo ""
# CMD cd ${INSTALLDIR}/taql-jupyter && git pull && cd /home/${USER}/work && start-notebook.sh /home/${NB_USER}/work/LearnTaQL.ipynb
RUN mkdir /home/${NB_USER}/.jupyter/custom
RUN ln -s ${INSTALLDIR}/taql-jupyter/custom.css /home/${NB_USER}/.jupyter/custom
RUN cp -r /home/lofar/opt/casacore/data/geodetic/Observatories /home/${USER}/work/
RUN cd ${INSTALLDIR}/taql-jupyter && git pull
RUN chown -R ${USER}:users /home/${NB_USER}/.jupyter
RUN chown -R ${USER}:users /home/${NB_USER}/.jupyter
RUN chown -R ${USER}:users /home/${NB_USER}/work
RUN chown -R ${USER}:users ${INSTALLDIR}/taql-jupyter

ENV PYTHONPATH /home/lofar/opt/taql-jupyter/taql

RUN mkdir -p /usr/local/share/data/casacore/
RUN cp -r /home/lofar/opt/casacore/data/* /usr/local/share/data/casacore/

USER ${USER}

