FROM phusion/baseimage:0.11

ADD circonus.list /etc/apt/sources.list.d/circonus.list

RUN curl 'https://keybase.io/circonuspkg/pgp_keys.asc?fingerprint=14ff6826503494d85e62d2f22dd15eba6d4fa648' | apt-key add -

RUN apt-get -y update \
  && apt-get -y install nginx \
  python-dev \
  python-flup \
  python-pip \
  python-ldap \
  circonus-platform-library-flatcc \
  expect \
  git \
  memcached \
  sqlite3 \
  libffi-dev \
  libcairo2 \
  libcairo2-dev \
  python-cairo \
  python-rrdtool \
  pkg-config \
  && rm -rf /var/lib/apt/lists/*

# choose a timezone at build-time
# use `--build-arg CONTAINER_TIMEZONE=Europe/Brussels` in `docker build`
ARG CONTAINER_TIMEZONE
ENV DEBIAN_FRONTEND noninteractive

RUN if [ ! -z "${CONTAINER_TIMEZONE}" ]; \
    then ln -sf /usr/share/zoneinfo/$CONTAINER_TIMEZONE /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata; \
    fi

# fix python dependencies (LTS Django)
RUN python -m pip install --upgrade pip && \
  pip install django==1.11.15

# install useful 3rd paty modules
RUN pip install fadvise && \
  pip install msgpack-python

ARG version=1.1.5
ARG graphite_version=${version}

ARG graphite_repo=https://github.com/graphite-project/graphite-web.git

# install graphite
RUN git clone -b ${graphite_version} --depth 1 ${graphite_repo} /usr/local/src/graphite-web
WORKDIR /usr/local/src/graphite-web
RUN pip install -r requirements.txt \
  && python ./setup.py install

# install irondb plugin
RUN git clone https://github.com/circonus-labs/graphite-irondb /usr/local/src/graphite-irondb
WORKDIR /usr/local/src/graphite-irondb
RUN  python setup.py build \
  && python setup.py install

# config graphite
ADD conf/opt/graphite/conf/*.conf /opt/graphite/conf/
ADD conf/opt/graphite/webapp/graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
# ADD conf/opt/graphite/webapp/graphite/app_settings.py /opt/graphite/webapp/graphite/app_settings.py
WORKDIR /opt/graphite/webapp
RUN mkdir -p /var/log/graphite/ \
  && PYTHONPATH=/opt/graphite/webapp django-admin.py collectstatic --noinput --settings=graphite.settings

# config nginx
RUN rm /etc/nginx/sites-enabled/default
ADD conf/etc/nginx/nginx.conf /etc/nginx/nginx.conf
ADD conf/etc/nginx/sites-enabled/graphite-statsd.conf /etc/nginx/sites-enabled/graphite-statsd.conf

# init django admin
ADD conf/usr/local/bin/django_admin_init.exp /usr/local/bin/django_admin_init.exp
ADD conf/usr/local/bin/manage.sh /usr/local/bin/manage.sh
RUN chmod +x /usr/local/bin/manage.sh && /usr/local/bin/django_admin_init.exp

# logging support
RUN mkdir -p /var/log/carbon /var/log/graphite /var/log/nginx
ADD conf/etc/logrotate.d/graphite-statsd /etc/logrotate.d/graphite-statsd

# daemons
ADD conf/etc/service/graphite/run /etc/service/graphite/run
ADD conf/etc/service/nginx/run /etc/service/nginx/run

# default conf setup
ADD conf /etc/graphite-statsd/conf
ADD conf/etc/my_init.d/01_conf_init.sh /etc/my_init.d/01_conf_init.sh

# cleanup
RUN apt-get clean\
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# defaults
EXPOSE 80 8080
VOLUME ["/opt/graphite/conf", "/opt/graphite/storage", "/opt/graphite/webapp/graphite/functions/custom", "/etc/nginx", "/etc/logrotate.d", "/var/log"]
WORKDIR /
ENV HOME /root

CMD ["/sbin/my_init"]
