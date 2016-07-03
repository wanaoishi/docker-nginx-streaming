FROM buildpack-deps:jessie

RUN apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62
RUN echo "deb http://nginx.org/packages/mainline/debian/ jessie nginx" >> /etc/apt/sources.list && \
    echo "deb-src http://nginx.org/packages/mainline/debian/ jessie nginx" >> /etc/apt/sources.list

ENV NGINX_VERSION 1.9.6
ENV RTMP_VERSION 1.1.7
ENV VOD_VERSION 1.4
ENV php_conf /etc/php5/cgi/php.ini 
ENV fpm_conf /etc/php5/fpm/php-fpm.conf

RUN mkdir -p /usr/src/nginx
WORKDIR /usr/src/nginx

# Download nginx source
RUN apt-get update && \
    apt-get install -y ca-certificates dpkg-dev apt-utils && \
    apt-get source nginx=${NGINX_VERSION}-1~jessie && \
    apt-get build-dep -y nginx=${NGINX_VERSION}-1~jessie && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}/debian/modules/

# Download RTMP module
RUN curl -L https://github.com/arut/nginx-rtmp-module/archive/v${RTMP_VERSION}.tar.gz | tar xz && \
    ln -s nginx-rtmp-module-${RTMP_VERSION} nginx-rtmp-module

# Download VOD module
RUN curl -L https://github.com/kaltura/nginx-vod-module/archive/${VOD_VERSION}.tar.gz | tar xz && \
    ln -s nginx-vod-module-${VOD_VERSION} nginx-vod-module

# Add modules to build nginx debian rules
ENV RTMP_MODULE_SOURCE "\\\/usr\\\/src\\\/nginx\\\/nginx-${NGINX_VERSION}\\\/debian\\\/modules\\\/nginx-rtmp-module-${RTMP_VERSION}"
ENV VOD_MODULE_SOURCE "\\\/usr\\\/src\\\/nginx\\\/nginx-${NGINX_VERSION}\\\/debian\\\/modules\\\/nginx-vod-module-${VOD_VERSION}"
RUN sed -ri "s/--with-ipv6/--with-ipv6 --add-module=${RTMP_MODULE_SOURCE} --add-module=${VOD_MODULE_SOURCE}/" \
        /usr/src/nginx/nginx-${NGINX_VERSION}/debian/rules

# Build nginx debian package
WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}
RUN dpkg-buildpackage -b

# Install nginx
WORKDIR /usr/src/nginx
RUN dpkg -i nginx_${NGINX_VERSION}-1~jessie_amd64.deb

# Add rtmp config wildcard inclusion
RUN mkdir -p /etc/nginx/rtmp.d && \
    printf "\nrtmp {\n\tinclude /etc/nginx/rtmp.d/*.conf;\n}\n" >> /etc/nginx/nginx.conf

# Install ffmpeg / aac
RUN echo 'deb http://www.deb-multimedia.org jessie main non-free' >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --force-yes deb-multimedia-keyring && \
    apt-get update && \
    apt-get install -y --force-yes \
        ffmpeg \
        mplayer mencoder \
        libimage-exiftool-perl \
        ruby git openssl

WORKDIR /usr/local/src
RUN git clone https://github.com/unnu/flvtool2.git && \
    cd /usr/local/src/flvtool2*/ && \
    ruby setup.rb config --prefix=/usr/local/ && ruby setup.rb setup && ruby setup.rb install


RUN apt-get install -y php5-fpm \
    php5-common \
    php5-cli php5-cgi \
    php5-mysql \
    php5-mcrypt \
    php5-gd \
    php5-intl \
    php5-memcache \
    php5-sqlite \
    php5-pgsql \
    php5-xmlrpc \
    php5-xsl \
    php5-curl \
    php-file \
    php5-json \
    php-fdomdocument && \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer


RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${php_conf} && \
    sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 5000M/g" ${php_conf} && \
    sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 5000M/g" ${php_conf} && \
    sed -i -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" ${php_conf} && \
    sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" ${fpm_conf} && \
    sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${fpm_conf} && \
    sed -i -e "s/pm.max_children = 4/pm.max_children = 4/g" ${fpm_conf} && \
    sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" ${fpm_conf} && \
    sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" ${fpm_conf} && \
    sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" ${fpm_conf} && \
    sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" ${fpm_conf} && \
    sed -i -e "s/user = nobody/user = nginx/g" ${fpm_conf} && \
    sed -i -e "s/group = nobody/group = nginx/g" ${fpm_conf} && \
    sed -i -e "s/;listen.mode = 0660/listen.mode = 0666/g" ${fpm_conf} && \
    sed -i -e "s/;listen.owner = nobody/listen.owner = nginx/g" ${fpm_conf} && \
    sed -i -e "s/;listen.group = nobody/listen.group = nginx/g" ${fpm_conf} && \
    sed -i -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" ${fpm_conf}


# Cleanup
RUN apt-get purge -yqq dpkg-dev && \
    apt-get autoremove -yqq && \
    apt-get clean -yqq && \
    rm -rf /usr/src/nginx

# Forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

VOLUME ["/var/cache/nginx", "/usr/share/nginx/html"]

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
