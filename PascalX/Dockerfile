# Start from Ubuntu
FROM ubuntu:20.04

# Copy over PascalX
COPY . /PascalX

# Install dependencies
RUN mkdir -p /PascalX/build/lib
ENV DEBIAN_FRONTEND="noninteractive"
RUN apt-get update && apt-get install -y python3 python3-dev python3-setuptools python3-pip g++ make libboost-all-dev wget unzip libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev libopenjp2-7-dev libtiff5-dev libwebp-dev libimagequant-dev libxcb1-dev
RUN echo "/PascalX/build/lib" > /etc/ld.so.conf.d/pascalx.conf

RUN pip3 install "pillow>=6.2.0,<11.0" "matplotlib==3.5.0"

# Build
RUN cd /PascalX && make all && ldconfig && make test
RUN cd /PascalX/python/ && python3 setup.py install

# Install jupyter
RUN pip3 install jupyter

