FROM ubuntu:20.04

# Set environment variables to avoid interaction
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Chicago

# Install system dependencies
RUN apt-get clean all && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev python3-setuptools openjdk-11-jre curl \
    g++ make libboost-all-dev wget unzip \
    libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev \
    libopenjp2-7-dev libtiff5-dev libwebp-dev libimagequant-dev libxcb1-dev \
    libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev  \
    libfreetype6-dev libcairo2-dev libpng-dev libtiff5-dev libjpeg-dev g++ dirmngr gnupg libraqm-dev libharfbuzz-dev libfribidi-dev && \
    apt-get clean all && \
    apt-get purge && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install R from CRAN (stable version for Ubuntu 20.04)
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /usr/share/keyrings/cran-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] https://cloud.r-project.org/bin/linux/ubuntu focal-cran40/" > /etc/apt/sources.list.d/r-project.list \
    && apt-get update && apt-get install -y \
    r-base \
    && apt-get clean

# Install R packages including WebGestaltR
RUN R -e "install.packages('BiocManager', repos='http://cran.rstudio.com/')" \
    && R -e "install.packages(c('systemfonts', 'svglite'), repos='http://cran.rstudio.com/')" \
    && R -e "BiocManager::install(c('WebGestaltR','stringr','optparse'))"

# Install Python packages
RUN pip3 install --upgrade pip
RUN pip3 install "pillow>=6.2.0,<=9.0.0" "matplotlib==3.5.0"
RUN pip3 install "pybind11" "numpy==1.20.3" "pandas==2.0.3" "jupyter" "statsmodels"

# Install PascalX dependencies
RUN mkdir -p /PascalX/build/lib && echo "/PascalX/build/lib" > /etc/ld.so.conf.d/pascalx.conf
COPY ./PascalX /PascalX
RUN cd /PascalX && make all && ldconfig && make test && cd python/ && python3 setup.py install

# Install Nextflow
RUN curl -s https://get.nextflow.io | bash && mv nextflow /usr/local/bin/

ADD scripts /app/scripts/

WORKDIR /app

ENTRYPOINT ["python3", "/app/scripts/main.py"]
