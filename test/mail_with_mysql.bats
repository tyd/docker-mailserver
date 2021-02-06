load 'test_helper/common'

function setup() {
    run_setup_file_if_necessary
}

function teardown() {
    run_teardown_file_if_necessary
}

function setup_file() {

    docker run -d --name mysql_for_mail \
    -e MYSQL_ROOT_PASSWORD="my-secret-pw" \
    -e MYSQL_DATABASE="mail" \
    -e MYSQL_USER="mailserveradmin" \
    -e MYSQL_PASSWORD="mailserveradminpass" \
    mariadb:focal

    sleep 20

    docker exec -i mysql_for_mail \
    sh -c 'exec mysql -uroot -p"my-secret-pw" mail' < test/docker-mariadb/bootstrap/mail.sql

    local PRIVATE_CONFIG
    PRIVATE_CONFIG="$(duplicate_config_for_container .)"
    docker run -d --name mail_with_mysql \
    -v "${PRIVATE_CONFIG}":/tmp/docker-mailserver \
    -v "$(pwd)/test/test-files":/tmp/docker-mailserver-test:ro \
    -e ENABLE_MYSQL=1 \
    -e MYSQL_HOSTS="mysql" \
    -e MYSQL_DBNAME="mail" \
    -e MYSQL_USER="mailserveradmin" \
    -e MYSQL_PASSWORD="mailserveradminpass" \
    -e SPOOF_PROTECTION=1 \
    -e DOVECOT_TLS=no \
    -e ENABLE_QUOTAS=1 \
    -e REPORT_RECIPIENT=1 \
    -e POSTMASTER_ADDRESS=postmaster@localhost.localdomain \
    -e DMS_DEBUG=0 \
    --link mysql_for_mail:mysql \
    -h mail.my-domain.com -t "${NAME}"
    wait_for_smtp_port_in_container mail_with_mysql
}

function teardown_file() {
    docker rm -f mysql_for_mail mail_with_mysql
}

@test "first" {
  skip 'only used to call setup_file from setup'
}

# processes

# postfix
@test "checking postfix: mysql lookup works correctly" {
  run docker exec mail_with_mysql /bin/sh -c "postmap -q some.user@localhost.localdomain mysql:/etc/postfix/mysql-users.cf"
  assert_success
  assert_output "some.user@localhost.localdomain"
  run docker exec mail_with_mysql /bin/sh -c "postmap -q postmaster@localhost.localdomain mysql:/etc/postfix/mysql-aliases.cf"
  assert_success
  assert_output "some.user@localhost.localdomain"

  # Test of the user part of the domain is not the same as the uniqueIdentifier part in the mysql
  run docker exec mail_with_mysql /bin/sh -c "postmap -q some.user.email@localhost.localdomain mysql:/etc/postfix/mysql-users.cf"
  assert_success
  assert_output "some.user.email@localhost.localdomain"

  # Test email receiving from a other domain than the primary domain of the mailserver
  run docker exec mail_with_mysql /bin/sh -c "postmap -q some.other.user@localhost.otherdomain mysql:/etc/postfix/mysql-users.cf"
  assert_success
  assert_output "some.other.user@localhost.otherdomain"
  run docker exec mail_with_mysql /bin/sh -c "postmap -q postmaster@localhost.otherdomain mysql:/etc/postfix/mysql-aliases.cf"
  assert_success
  assert_output "some.other.user@localhost.otherdomain"
}

@test "checking postfix: mysql custom config files copied" {
run docker exec mail_with_mysql /bin/sh -c "grep '# config for mysql integration' /etc/postfix/mysql-users.cf"
assert_success
run docker exec mail_with_mysql /bin/sh -c "grep '# config for mysql integration' /etc/postfix/mysql-domains.cf"
assert_success
run docker exec mail_with_mysql /bin/sh -c "grep '# config for mysql integration' /etc/postfix/mysql-transports.cf"
assert_success
}

@test "checking postfix: mysql config overwrites success" {
  run docker exec mail_with_mysql /bin/sh -c "grep 'user = mailserveradmin' /etc/postfix/mysql-users.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'password = mailserveradminpass' /etc/postfix/mysql-users.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'dbname = mail' /etc/postfix/mysql-users.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'hosts = mysql' /etc/postfix/mysql-users.cf"
  assert_success

  run docker exec mail_with_mysql /bin/sh -c "grep 'user = mailserveradmin' /etc/postfix/mysql-domains.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'password = mailserveradminpass' /etc/postfix/mysql-domains.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'dbname = mail' /etc/postfix/mysql-domains.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'hosts = mysql' /etc/postfix/mysql-domains.cf"
  assert_success

  run docker exec mail_with_mysql /bin/sh -c "grep 'user = mailserveradmin' /etc/postfix/mysql-transports.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'password = mailserveradminpass' /etc/postfix/mysql-transports.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'dbname = mail' /etc/postfix/mysql-transports.cf"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "grep 'hosts = mysql' /etc/postfix/mysql-transports.cf"
  assert_success
}

# dovecot
@test "checking dovecot: mysql imap connection and authentication works" {
  run docker exec mail_with_mysql /bin/sh -c "nc -w 1 0.0.0.0 143 < /tmp/docker-mailserver-test/auth/imap-mysql-auth.txt"
  assert_success
}

@test "checking dovecot: mysql mail delivery works" {
  run docker exec mail_with_mysql /bin/sh -c "sendmail -f user@external.tld some.user@localhost.localdomain < /tmp/docker-mailserver-test/email-templates/test-email.txt"
  sleep 10
  run docker exec mail_with_mysql /bin/sh -c "ls -A /var/mail/localhost.localdomain/some.user/new | wc -l"
  assert_success
  assert_output 1
}

@test "checking dovecot: mysql mail delivery works for a different domain than the mailserver" {
  run docker exec mail_with_mysql /bin/sh -c "sendmail -f user@external.tld some.other.user@localhost.otherdomain < /tmp/docker-mailserver-test/email-templates/test-email.txt"
  sleep 10
  run docker exec mail_with_mysql /bin/sh -c "ls -A /var/mail/localhost.otherdomain/some.other.user/new | wc -l"
  assert_success
  assert_output 1
}

@test "checking dovecot: mysql config overwrites success" {
  run docker exec mail_with_mysql /bin/sh -c "grep 'driver         = mysql' /etc/dovecot/dovecot-sql.conf.ext"
  assert_success
}

@test "checking dovecot: postmaster address" {
  run docker exec mail_with_mysql /bin/sh -c "grep 'postmaster_address = postmaster@localhost.localdomain' /etc/dovecot/conf.d/15-lda.conf"
  assert_success
}

@test "checking dovecot: quota plugin is enabled" {
run docker exec mail_with_mysql /bin/sh -c "grep '\$mail_plugins quota' /etc/dovecot/conf.d/10-mail.conf"
assert_success
run docker exec mail_with_mysql /bin/sh -c "grep '\$mail_plugins imap_quota' /etc/dovecot/conf.d/20-imap.conf"
assert_success
run docker exec mail_with_mysql ls /etc/dovecot/conf.d/90-quota.conf
assert_success
run docker exec mail_with_mysql ls /etc/dovecot/conf.d/90-quota.conf.disab
assert_failure
}

@test "checking postfix: dovecot quota present in postconf" {
  run docker exec mail_with_mysql /bin/bash -c "postconf | grep 'check_policy_service inet:localhost:65265'"
  assert_success
}

@test "checking mysql quota: warn message received when quota exceeded" {
  # send some big emails
  run docker exec mail_with_mysql /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/quota-exceeded.txt"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/quota-exceeded.txt"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/quota-exceeded.txt"
  assert_success
  # check for quota warn message existence
  run repeat_until_success_or_timeout 20 sh -c "docker exec mail_with_mysql sh -c 'grep \"Subject: quota warning\" /var/mail/otherdomain.tld/quotauser/new/ -R'"
  assert_success

  run repeat_until_success_or_timeout 20 sh -c "docker logs mail_with_mysql | grep 'Quota exceeded (mailbox for user is full)'"
  assert_success

  # ensure only the first big message and the warn message are present (other messages are rejected: mailbox is full)
  run docker exec mail_with_mysql sh -c 'ls /var/mail/otherdomain.tld/quotauser/new/ | wc -l'
  assert_success
  assert_output "2"
}

@test "checking spoofing: rejects sender forging" {
  run docker exec mail_with_mysql /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/auth/mysql-smtp-auth-spoofed.txt | grep 'Sender address rejected: not owned by user'"
  assert_success
}

# ATTENTION: this test must come after "checking dovecot: mysql mail delivery works" since it will deliver an email which skews the count in said test, leading to failure
@test "checking spoofing: accepts sending as alias" {
  run docker exec mail_with_mysql /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/auth/mysql-smtp-auth-spoofed-alias.txt | grep 'End data with'"
  assert_success
}

@test "checking saslauthd: mysql smtp authentication" {
  run docker exec mail_with_mysql /bin/sh -c "nc -w 5 0.0.0.0 25 < /tmp/docker-mailserver-test/auth/sasl-mysql-smtp-auth.txt | grep 'Authentication successful'"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "openssl s_client -quiet -connect 0.0.0.0:465 < /tmp/docker-mailserver-test/auth/sasl-mysql-smtp-auth.txt | grep 'Authentication successful'"
  assert_success
  run docker exec mail_with_mysql /bin/sh -c "openssl s_client -quiet -starttls smtp -connect 0.0.0.0:587 < /tmp/docker-mailserver-test/auth/sasl-mysql-smtp-auth.txt | grep 'Authentication successful'"
  assert_success
}

#
# Pflogsumm delivery check
#

@test "checking pflogsum delivery" {
  # checking default sender is correctly set when env variable not defined
  run docker exec mail_with_mysql grep "mailserver-report@mail.my-domain.com" /etc/logrotate.d/maillog
  assert_success

  # checking default logrotation setup
  run docker exec mail_with_mysql grep "daily" /etc/logrotate.d/maillog
  assert_success
}

@test "last" {
  skip 'only used to call teardown_file from teardown'
}
