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
RUN usermod -a -G sudo ${USER}
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
RUN mkdir -p ${INSTALLDIR}/casacore/data
RUN cd ${INSTALLDIR}/casacore && git clone --branch masktql https://github.com/gervandiepen/casacore.git src
RUN cd ${INSTALLDIR}/casacore/data && wget --retry-connrefused ftp://anonymous@ftp.astron.nl/outgoing/Measures/WSRT_Measures.ztar
RUN cd ${INSTALLDIR}/casacore/data && tar xf WSRT_Measures.ztar
RUN cd ${INSTALLDIR}/casacore/build && cmake -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/casacore/ -DDATA_DIR=${INSTALLDIR}/casacore/data -DCFITSIO_ROOT_DIR=${INSTALLDIR}/cfitsio/ -DBUILD_PYTHON=True -DUSE_OPENMP=True -DUSE_FFTW3=TRUE -DMODULE=ms -DCXX11=ON ../src/
RUN cd ${INSTALLDIR}/casacore/build && make -j ${J}
RUN cd ${INSTALLDIR}/casacore/build && make install

#
# install-python-casacore
#
RUN mkdir ${INSTALLDIR}/python-casacore
RUN cd ${INSTALLDIR}/python-casacore && git clone https://github.com/casacore/python-casacore
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && sed -i.bak -e '54,62d' setup.py
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && ./setup.py build_ext -I${INSTALLDIR}/casacore/include/ -L${INSTALLDIR}/casacore/lib/ -R${INSTALLDIR}/casacore/lib/
RUN cd ${INSTALLDIR}/python-casacore/python-casacore && sudo ./setup.py install

#
# install Jupyter
#
RUN sudo apt-get -y install python-zmq
RUN sudo pip install jupyter

#
# entrypoint
#
ENTRYPOINT /bin/bash --init-file /usr/bin/init.sh

