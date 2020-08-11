# creates a mashup Alpine Dockerfile with Consul and Apache HTTP Server

cd "$( dirname "${BASH_SOURCE[0]}")"

# fetch Dockerfile and docker-entrypoint.sh for consul:1.8.0 (FROM alpine:3.9)
curl https://raw.githubusercontent.com/hashicorp/docker-consul/f15bee814fdec35c2b101b54a1afceaed4496973/0.X/Dockerfile > Dockerfile
curl https://raw.githubusercontent.com/hashicorp/docker-consul/f15bee814fdec35c2b101b54a1afceaed4496973/0.X/docker-entrypoint.sh > consul-entrypoint.sh
curl https://raw.githubusercontent.com/docker-library/httpd/f5ef4cc849a4ea7ed56e797b86ad06ccf9f93a9a/2.4/alpine/httpd-foreground > httpd-foreground
chmod u+x consul-entrypoint.sh httpd-foreground

# replace base image by Alpine version 3.12 with Apache HTTP Server preinstalled
sed -i '' 's/FROM alpine:.*/FROM httpd:2.4.43-alpine/g' Dockerfile

# enforce use of system's standard DNS resolver code (i.e. not Docker? see [1])
sed -i '' 's|RUN set -eux .*$|# hadolint ignore=DL3003,DL3018,DL4006\
&\
    mkdir /root/.gnupg \&\& \\\
    chmod 700 /root/.gnupg \&\& \\\
    echo standard-resolver >> /root/.gnupg/dirmngr.conf \&\& \\\
    echo disable-ipv6 >> /root/.gnupg/dirmngr.conf \&\& \\|g' Dockerfile

# try GPG up to 5 times before accepting failure (gnupg>2.1.16-2 DNS is broken)
sed -Ei '' 's/gpg --keyserver [^\]*/n=0; until [ "\$n" -ge 5 ]; do &break; n=\$((n+1)); pkill dirmngr; done \&\&  /g' Dockerfile

#sed -Ei '' 's/--no-cache [^&]+/&supervisor /g' Dockerfile
#sed -i '' 's/consul version$/& \&\& \\\
#    apk add --no-cache supervisor/g' Dockerfile

#perl -0777 -i -pe 's|(COPY \S+).*|\1 consul-entrypoint.sh /usr/local/bin/\
#ENTRYPOINT ["docker-entrypoint.sh"]\
#|gms' Dockerfile
sed -Ei '' 's|(COPY [^ ]+).*|STOPSIGNAL SIGTERM\
\1 consul-entrypoint.sh /usr/local/bin/|g' Dockerfile

#ADD supervisord.conf /etc/\
#ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]|gms' Dockerfile

#ADD supervisord.conf /etc/
#ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]

# humor hadolint DL4000 (MAINTAINER is deprecated)
sed -i '' '/^MAINTAINER/d' Dockerfile

#[1] https://jackgruber.github.io/2019-06-07-gnupg-cannot-connect-to-keyserver/
# http://btcinfo.sdf.org/library/gentoo/gentoo-docker-images/stage3.Dockerfile
# https://github.com/tianon/gosu/issues/22
