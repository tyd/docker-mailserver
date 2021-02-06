SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for aliases
-- ----------------------------
DROP TABLE IF EXISTS aliases;
CREATE TABLE aliases (
  id int(10) unsigned NOT NULL AUTO_INCREMENT,
  alias varchar(255) NOT NULL,
  destination varchar(255) NOT NULL,
  enabled enum('Y','N') DEFAULT 'Y',
  PRIMARY KEY (id),
  UNIQUE KEY alias_2 (alias,destination),
  KEY alias (alias) USING HASH
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4;

-- ----------------------------
-- Records of aliases
-- ----------------------------
BEGIN;
INSERT INTO aliases VALUES (1, 'postmaster@localhost.localdomain', 'some.user@localhost.localdomain', 'Y');
INSERT INTO aliases VALUES (2, 'postmaster@localhost.otherdomain', 'some.other.user@localhost.otherdomain', 'Y');
COMMIT;

-- ----------------------------
-- Table structure for domains
-- ----------------------------
DROP TABLE IF EXISTS domains;
CREATE TABLE domains (
  domain varchar(255) NOT NULL,
  enabled enum('Y','N') DEFAULT 'Y',
  PRIMARY KEY (domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------
-- Records of domains
-- ----------------------------
BEGIN;
INSERT INTO domains VALUES ('localhost.localdomain', 'Y');
INSERT INTO domains VALUES ('localhost.otherdomain', 'Y');
INSERT INTO domains VALUES ('otherdomain.tld', 'Y');
COMMIT;

-- ----------------------------
-- Table structure for transport
-- ----------------------------
DROP TABLE IF EXISTS transport;
CREATE TABLE transport (
  domain varchar(255) NOT NULL,
  transport varchar(255) DEFAULT NULL,
  PRIMARY KEY (domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------
-- Records of transport
-- ----------------------------
BEGIN;
COMMIT;

-- ----------------------------
-- Table structure for users
-- ----------------------------
DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  email varchar(255) NOT NULL,
  password varchar(255) NOT NULL,
  quota int(10) unsigned DEFAULT 104857600,
  maildir text NOT NULL,
  enabled enum('Y','N') DEFAULT 'Y',
  PRIMARY KEY (id),
  KEY email (email) USING HASH
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4;

-- ----------------------------
-- Records of users
-- ----------------------------
BEGIN;
INSERT INTO users VALUES (1, 'some.user@localhost.localdomain', '{SHA256-CRYPT}$5$wWEjD23O$fYnOtDgJK.ggg.9W3avhACsqHr4lJ69WO2/dFGJeyf5', 104857600, '/var/mail/localhost.localdomain/some.user/', 'Y');
INSERT INTO users VALUES (2, 'some.other.user@localhost.otherdomain', '{SHA512-CRYPT}$6$jNm6XgoD$DAuV4JElD.wUUlYo48asokK/e3xHmAmE67r109CV1grxmYOwTkl3Lz7V5DcVeRA5u3GfPiLHLZGTch0TGueLG.', 104857600, '/var/mail/localhost.otherdomain/some.other.user/', 'Y');
INSERT INTO users VALUES (3, 'some.user.email@localhost.localdomain', '{SHA256-CRYPT}$5$wWEjD23O$fYnOtDgJK.ggg.9W3avhACsqHr4lJ69WO2/dFGJeyf5', 104857600, '/var/mail/localhost.localdomain/some.user.email/', 'Y');
INSERT INTO users VALUES (4, 'quotauser@otherdomain.tld', '{SHA256-CRYPT}$5$wWEjD23O$fYnOtDgJK.ggg.9W3avhACsqHr4lJ69WO2/dFGJeyf5', 10000, '/var/mail/otherdomain.tld/quotauser/', 'Y');
COMMIT;


SET FOREIGN_KEY_CHECKS = 1;
