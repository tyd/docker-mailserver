FROM docker.io/debian:buster-slim

ARG VCS_VER
ARG VCS_REF
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.version=${VCS_VER}
LABEL org.opencontainers.image.revision=${VCS_REF}
LABEL org.opencontainers.image.title="docker-mailserver"
LABEL org.opencontainers.image.vendor="The Docker Mailserver Organization"
LABEL org.opencontainers.image.authors="The Docker Mailserver Organization on GitHub"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.description="A fullstack but simple mail server (SMTP, IMAP, LDAP, Antispam, Antivirus, etc.). Only configuration files, no SQL database."
LABEL org.opencontainers.image.url="https://github.com/docker-mailserver"
LABEL org.opencontainers.image.documentation="https://github.com/docker-mailserver/docker-mailserver/blob/master/README.md"
LABEL org.opencontainers.image.source="https://github.com/docker-mailserver/docker-mailserver"

ENV ENABLE_POSTGREY=0
ENV FETCHMAIL_POLL=300
ENV ONE_DIR=0
ENV POSTGREY_AUTO_WHITELIST_CLIENTS=5
ENV POSTGREY_DELAY=300
ENV POSTGREY_MAX_AGE=35
ENV POSTGREY_TEXT="Delayed by Postgrey"
ENV SASLAUTHD_MECHANISMS=pam
ENV SASLAUTHD_MECH_OPTIONS=""
ENV VIRUSMAILS_DELETE_DELAY=7

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Install Basic Software ––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

RUN \
  apt-get -qq --fix-missing update && \
  apt-get -y dist-upgrade >/dev/null && \
  apt-get -y install apt-utils &>/dev/null && \
  apt-get -y install postfix >/dev/null && \
  apt-get -y --no-install-recommends install \
  # A - D
  altermime amavisd-new apt-transport-https arj binutils bzip2 \
  dovecot-core dovecot-imapd dovecot-ldap dovecot-lmtpd \
  dovecot-managesieved dovecot-mysql dovecot-pop3d dovecot-sieve dovecot-solr \
  dumb-init ca-certificates cabextract clamav clamav-daemon cpio curl \
  # E - O
  ed fail2ban fetchmail file gamin gnupg gzip iproute2 iptables \
  locales logwatch lhasa libdate-manip-perl liblz4-tool \
  libmail-spf-perl libnet-dns-perl libsasl2-modules lrzip lzop \
  netcat-openbsd nomarch opendkim opendkim-tools opendmarc \
  # P - Z
  pax pflogsumm postgrey p7zip-full postfix-ldap postfix-mysql postfix-pcre \
  postfix-policyd-spf-python postsrsd pyzor \
  razor rpm2cpio rsyslog sasl2-bin spamassassin supervisor \
  unrar-free unzip whois xz-utils >/dev/null && \
  # cleanup
  apt-get -qq autoclean && \
  apt-get -qq clean && \
  rm -rf /var/lib/apt/lists/* && \
  c_rehash 2>/dev/null

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– ClamAV & FeshClam –––––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

RUN \
  echo '0 */6 * * * clamav /usr/bin/freshclam --quiet' > /etc/cron.d/clamav-freshclam && \
  chmod 644 /etc/clamav/freshclam.conf && \
  freshclam && \
  sed -i 's/Foreground false/Foreground true/g' /etc/clamav/clamd.conf && \
  mkdir /var/run/clamav && \
  chown -R clamav:root /var/run/clamav && \
  rm -rf /var/log/clamav/

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Dovecot & MkCert ––––––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/dovecot/auth-passwdfile.inc target/dovecot/??-*.conf /etc/dovecot/conf.d/
COPY target/dovecot/sieve/ /etc/dovecot/sieve/
COPY target/dovecot/dovecot-purge.cron /etc/cron.d/dovecot-purge.disabled
RUN chmod 0 /etc/cron.d/dovecot-purge.disabled
WORKDIR /usr/share/dovecot

# hadolint ignore=SC2016,SC2086,SC2069
RUN \
  sed -i -e 's/include_try \/usr\/share\/dovecot\/protocols\.d/include_try \/etc\/dovecot\/protocols\.d/g' /etc/dovecot/dovecot.conf && \
  sed -i -e 's/#mail_plugins = \$mail_plugins/mail_plugins = \$mail_plugins sieve/g' /etc/dovecot/conf.d/15-lda.conf && \
  sed -i -e 's/^.*lda_mailbox_autocreate.*/lda_mailbox_autocreate = yes/g' /etc/dovecot/conf.d/15-lda.conf && \
  sed -i -e 's/^.*lda_mailbox_autosubscribe.*/lda_mailbox_autosubscribe = yes/g' /etc/dovecot/conf.d/15-lda.conf && \
  sed -i -e 's/^.*postmaster_address.*/postmaster_address = '${POSTMASTER_ADDRESS:="postmaster@domain.com"}'/g' /etc/dovecot/conf.d/15-lda.conf && \
  sed -i 's/#imap_idle_notify_interval = 2 mins/imap_idle_notify_interval = 29 mins/' /etc/dovecot/conf.d/20-imap.conf && \
  # adapt mkcert for Dovecot community repo
  sed -i 's/CERTDIR=.*/CERTDIR=\/etc\/dovecot\/ssl/g' /usr/share/dovecot/mkcert.sh && \
  sed -i 's/KEYDIR=.*/KEYDIR=\/etc\/dovecot\/ssl/g' /usr/share/dovecot/mkcert.sh && \
  sed -i 's/KEYFILE=.*/KEYFILE=\$KEYDIR\/dovecot.key/g' /usr/share/dovecot/mkcert.sh && \
  sed -i 's/RANDFILE.*//g' /usr/share/dovecot/dovecot-openssl.cnf && \
  mkdir /etc/dovecot/ssl && \
  chmod 755 /etc/dovecot/ssl && \
  ./mkcert.sh 2>&1 >/dev/null && \
  mkdir -p /usr/lib/dovecot/sieve-pipe /usr/lib/dovecot/sieve-filter /usr/lib/dovecot/sieve-global && \
  chmod 755 -R /usr/lib/dovecot/sieve-pipe /usr/lib/dovecot/sieve-filter /usr/lib/dovecot/sieve-global

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– MySQL ––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––
COPY target/dovecot/dovecot-sql.conf.ext /etc/dovecot
COPY \
  target/postfix/mysql-aliases.cf \
  target/postfix/mysql-domains.cf \
  target/postfix/mysql-transports.cf \
  target/postfix/mysql-users.cf \
  /etc/postfix/

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– LDAP & Spamassassin's Cron ––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/dovecot/dovecot-ldap.conf.ext /etc/dovecot
COPY \
  target/postfix/ldap-users.cf \
  target/postfix/ldap-groups.cf \
  target/postfix/ldap-aliases.cf \
  target/postfix/ldap-domains.cf \
  /etc/postfix/

# hadolint ignore=SC2016
RUN \
  sed -i -r 's/^(CRON)=0/\1=1/g' /etc/default/spamassassin && \
  sed -i -r 's/^\$INIT restart/supervisorctl restart amavis/g' /etc/spamassassin/sa-update-hooks.d/amavisd-new

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Scripts & Miscellaneous –––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY \
  ./target/bin/* \
  ./target/scripts/*.sh \
  ./target/docker-configomat/configomat.sh \
  /usr/local/bin/

RUN \
  chmod +x /usr/local/bin/* && \
  rm -rf /usr/share/locale/* && \
  rm -rf /usr/share/man/* && \
  rm -rf /usr/share/doc/* && \
  touch /var/log/auth.log && \
  update-locale && \
  rm /etc/postsrsd.secret && \
  rm /etc/cron.daily/00logwatch

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– PostSRSD, Postgrey & Amavis –––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/postsrsd/postsrsd /etc/default/postsrsd
COPY target/postgrey/postgrey /etc/default/postgrey
COPY target/postgrey/postgrey.init /etc/init.d/postgrey
RUN \
  chmod 755 /etc/init.d/postgrey && \
  mkdir /var/run/postgrey && \
  chown postgrey:postgrey /var/run/postgrey

COPY target/amavis/conf.d/* /etc/amavis/conf.d/
RUN \
  sed -i -r 's/#(@|   \\%)bypass/\1bypass/g' /etc/amavis/conf.d/15-content_filter_mode && \
  adduser clamav amavis >/dev/null && \
  adduser amavis clamav >/dev/null && \
  # no syslog user in Debian compared to Ubuntu
  adduser --system syslog >/dev/null && \
  useradd -u 5000 -d /home/docker -s /bin/bash -p "$(echo docker | openssl passwd -1 -stdin)" docker >/dev/null && \
  echo "0 4 * * * /usr/local/bin/virus-wiper" | crontab - && \
  chmod 644 /etc/amavis/conf.d/*

# overcomplication necessary for CI
RUN for _ in {1..10}; do su - amavis -c "razor-admin -create" ; sleep 3 ; \
  if su - amavis -c "razor-admin -register" &>/dev/null; then { EC=0 ; break ; } ; \
  else EC=${?} ; fi ; done ; (exit ${EC})

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Fail2Ban, DKIM & DMARC ––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/fail2ban/jail.conf /etc/fail2ban/jail.conf
COPY target/fail2ban/filter.d/postfix-sasl.conf /etc/fail2ban/filter.d/postfix-sasl.conf
RUN mkdir /var/run/fail2ban

COPY target/opendkim/opendkim.conf /etc/opendkim.conf
COPY target/opendkim/default-opendkim /etc/default/opendkim

COPY target/opendmarc/opendmarc.conf /etc/opendmarc.conf
COPY target/opendmarc/default-opendmarc /etc/default/opendmarc
COPY target/opendmarc/ignore.hosts /etc/opendmarc/ignore.hosts

RUN \
  # switch iptables and ip6tables to legacy for Fail2Ban
  update-alternatives --set iptables /usr/sbin/iptables-legacy && \
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Fetchmail, Postfix & Let'sEncrypt –––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/fetchmail/fetchmailrc /etc/fetchmailrc_general
COPY target/postfix/main.cf target/postfix/master.cf /etc/postfix/
COPY target/shared/ffdhe4096.pem /etc/postfix/shared/ffdhe4096.pem
COPY \
  target/postfix/header_checks.pcre \
  target/postfix/sender_header_filter.pcre \
  target/postfix/sender_login_maps.pcre \
  /etc/postfix/maps/

RUN \
  : >/etc/aliases && \
  sed -i 's/START_DAEMON=no/START_DAEMON=yes/g' /etc/default/fetchmail && \
  mkdir /var/run/fetchmail && chown fetchmail /var/run/fetchmail && \
  curl -s https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem >/etc/ssl/certs/lets-encrypt-x3-cross-signed.pem

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Logs ––––––––––––––––––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

RUN \
  sed -i -r "/^#?compress/c\compress\ncopytruncate" /etc/logrotate.conf && \
  mkdir -p /var/log/mail && \
  chown syslog:root /var/log/mail && \
  touch /var/log/mail/clamav.log && \
  chown -R clamav:root /var/log/mail/clamav.log && \
  touch /var/log/mail/freshclam.log && \
  chown -R clamav:root /var/log/mail/freshclam.log && \
  sed -i -r 's|/var/log/mail|/var/log/mail/mail|g' /etc/rsyslog.conf && \
  sed -i -r 's|;auth,authpriv.none|;mail.none;mail.error;auth,authpriv.none|g' /etc/rsyslog.conf && \
  sed -i -r 's|LogFile /var/log/clamav/|LogFile /var/log/mail/|g' /etc/clamav/clamd.conf && \
  sed -i -r 's|UpdateLogFile /var/log/clamav/|UpdateLogFile /var/log/mail/|g' /etc/clamav/freshclam.conf && \
  sed -i -r 's|/var/log/clamav|/var/log/mail|g' /etc/logrotate.d/clamav-daemon && \
  sed -i -r 's|invoke-rc.d.*|/usr/bin/supervisorctl signal hup clamav >/dev/null \|\| true|g' /etc/logrotate.d/clamav-daemon && \
  sed -i -r 's|/var/log/clamav|/var/log/mail|g' /etc/logrotate.d/clamav-freshclam && \
  sed -i -r '/postrotate/,/endscript/d' /etc/logrotate.d/clamav-freshclam && \
  sed -i -r 's|/var/log/mail|/var/log/mail/mail|g' /etc/logrotate.d/rsyslog && \
  sed -i -r '/\/var\/log\/mail\/mail.log/d' /etc/logrotate.d/rsyslog && \
  # prevent syslog logrotate warnings
  sed -i -e 's/\(printerror "could not determine current runlevel"\)/#\1/' /usr/sbin/invoke-rc.d && \
  sed -i -e 's/^\(POLICYHELPER=\).*/\1/' /usr/sbin/invoke-rc.d && \
  # prevent syslog warning about imklog permissions
  sed -i -e 's/^module(load=\"imklog\")/#module(load=\"imklog\")/' /etc/rsyslog.conf && \
  # prevent email when /sbin/init or init system is not existing
  sed -i -e 's|invoke-rc.d rsyslog rotate > /dev/null|/usr/bin/supervisorctl signal hup rsyslog >/dev/null|g' /usr/lib/rsyslog/rsyslog-rotate

# –––––––––––––––––––––––––––––––––––––––––––––––
# ––– Supervisord & Start –––––––––––––––––––––––
# –––––––––––––––––––––––––––––––––––––––––––––––

COPY target/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY target/supervisor/conf.d/* /etc/supervisor/conf.d/

WORKDIR /

EXPOSE 25 587 143 465 993 110 995 4190

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
