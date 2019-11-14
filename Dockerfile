## -*- docker-image-name: "zavpyj/osm-tiles" -*-

##
# The OpenStreetMap Tile Server
#
# This creates an image containing the OpenStreetMap tile server stack as
# described at
# <https://switch2osm.org/manually-building-a-tile-server-18-04-lts/>.
#  

FROM phusion/baseimage:0.11
MAINTAINER Xavier Guille <xguille@hotmail.com>

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# Set the locale. This affects the encoding of the Postgresql template
# databases.
ENV LANG C.UTF-8
RUN update-locale LANG=C.UTF-8
RUN date

# Update cache and install dependencies
RUN apt-get update -y && apt-get install -y \
    apache2 \
    apache2-dev \
    autoconf \
    build-essential \
    bzip2 \
    cmake \
    curl \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    g++ \
    gdal-bin \
    git-core \
    libagg-dev \
    libboost-all-dev \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-system-dev \
    libbz2-dev \
    libcairo-dev \
    libcairomm-1.0-dev \
    libexpat1-dev \
    libfreetype6-dev \
    libgdal-dev \
    libgeos++-dev \
    libgeos-dev \
    libgeotiff-epsg \
    libicu-dev \
    liblua5.1-dev \
    liblua5.2-dev \
    libmapnik-dev \
    libpq-dev \
    libproj-dev \
    libprotobuf-c0-dev \
    libtiff5-dev \
    libtool \
    libxml2-dev \
    lua5.1 \
    lua5.2 \
    make \
    mapnik-utils \
    munin \
    munin-node \
    nodejs \
    npm \
    postgis \
    postgresql \
    postgresql-10-postgis-2.4 \
    postgresql-10-postgis-scripts \
    postgresql-contrib \
    protobuf-c-compiler \
    python-mapnik \
    sudo \
    tar \
    ttf-unifont \
    unzip \
    wget \
    zlib1g-dev

# Avoid munin cron tasks and associated logs
RUN rm -f /etc/cron.d/munin /etc/cron.d/munin-node /etc/cron.d/sysstat

# Install osm2pgsql
ENV OSM2PGSQL_VERSION 1.0.0
RUN git clone --depth 1 --branch ${OSM2PGSQL_VERSION} https://github.com/openstreetmap/osm2pgsql.git /tmp/osm2pgsql && \
    cd /tmp/osm2pgsql && \
    mkdir build && cd build && cmake .. && \
    make && make install && \
    cd /tmp && rm -rf /tmp/osm2pgsql

# Install CartoCSS
RUN npm install -g carto@1.2.0

# Install mod_tile and renderd
#We rely on the last commit of the switch2osm's branch at the time of this Dockerfile
ENV MOD_TILE_VERSION aa3d8edd778220e8e701e56d8bc7f16286060520
ENV MOD_TILE_PARALLEL_BUILD 4
RUN cd /tmp && git clone --branch switch2osm https://github.com/SomeoneElseOSM/mod_tile.git && \
    cd /tmp/mod_tile && \
    git reset --hard $MOD_TILE_VERSION && \
    ./autogen.sh && \
    ./configure && \
    make -j $MOD_TILE_PARALLEL_BUILD && \
    make install && \
    make install-mod_tile && \
    ldconfig && \
    # Build to meta2tile utility and copy onto system path
    cd extra && \
    make && \
    cp meta2tile /usr/local/bin && \
    # Tidy up
    cd /tmp && rm -rf /tmp/mod_tile

RUN cp -p /usr/local/etc/renderd.conf /usr/local/etc/renderd.conf.orig
COPY ./build/renderd.conf /usr/local/etc/

# Create the files required for the mod_tile system to run
RUN mkdir /var/run/renderd && chown www-data: /var/run/renderd
RUN mkdir /var/lib/mod_tile && chown www-data /var/lib/mod_tile

# Replace default apache index page with Leaflet demo
COPY ./build/index.html /var/www/html/

# Configure mod_tile
COPY ./build/mod_tile.load /etc/apache2/mods-available/
COPY ./build/mod_tile.conf /etc/apache2/mods-available/
RUN a2enmod mod_tile

# Ensure the webserver user can connect to the gis database
RUN sed -i -e 's/local   all             all                                     peer/local gis www-data peer/' /etc/postgresql/10/main/pg_hba.conf

# Tune postgresql
COPY ./build/postgresql.conf.sed /tmp/
RUN sed --file /tmp/postgresql.conf.sed --in-place /etc/postgresql/10/main/postgresql.conf

# Define the application logging logic
COPY ./build/syslog-ng.conf /etc/syslog-ng/conf.d/local.conf
RUN rm -rf /var/log/postgresql

# Create a `postgresql` `runit` service
COPY ./build/service/postgresql /etc/service/postgresql/

# Create an `apache2` `runit` service
COPY ./build/service/apache2 /etc/service/apache2/

# Create a `renderd` `runit` service
COPY ./build/service/renderd /etc/service/renderd/

# Expose the webserver and database ports
EXPOSE 80 5432

# Set the osm2pgsql import cache size in MB. Used in `run import` and `run importappend`.
ENV OSM_IMPORT_CACHE 40

# Add the README
COPY ./README.md /usr/local/share/doc/

# Add the help file
COPY ./build/help.txt /usr/local/share/doc/run/

RUN rm -Rf /var/lib/postgresql/10/main

# Correct the Error: could not open temporary statistics file "/var/run/postgresql/10-main.pg_stat_tmp/global.tmp": No such file or directory
RUN mkdir -p /var/run/postgresql/10-main.pg_stat_tmp
RUN chown postgres:postgres /var/run/postgresql/10-main.pg_stat_tmp -R

#Add the perl script to render only an extract of the map
COPY ./build/render_list_geo.pl /opt/
RUN chmod +x /opt/render_list_geo.pl

# Configure mod_rewrite
COPY ./build/rewrite.conf /etc/apache2/mods-available/
COPY ./build/000-default.conf /etc/apache2/sites-available/

# Add the entrypoint
COPY ./build/run.sh /usr/local/sbin/run
RUN chmod +x /usr/local/sbin/run /etc/service/renderd/* /etc/service/apache2/* /etc/service/postgresql/*
ENTRYPOINT ["/sbin/my_init", "--", "/usr/local/sbin/run"]

# Default to showing the usage text
CMD ["help"]

# Clean up APT
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
