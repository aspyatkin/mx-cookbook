# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2021-09-17

### Added
- Add `db_maxconns` (default: 5) and `db_connect_timeout` (default: 5) properties to `mx_dovecot` resource.

## [0.4.0] - 2021-09-08

### Added
- Add new resource `mx_rspamd_multimap_entry` to configure Rspamd multimap module.

### Removed
- `mx_rspamd` no longer supports `postmaster` and `postmaster_score` properties. Multimap rules are configured now using a separate resource.

## [0.3.5] - 2021-05-14
### Added
- Rspamd configurable score for multimap rule (see `mx_rspamd` new resource property: `postmaster_score`).

## [0.3.4] - 2021-04-30
### Added
- Enable dovecot's `old_stats` plugin (see `mx_dovecot` new resopurce properties: `old_stats_enabled`, `old_stats_host`, `old_stats_port`, `old_stats_refresh` and `old_stats_track_cmds`).

## [0.3.3] - 2021-04-27
### Changed
- Enable extra addresses for SMTP From.

## [0.3.2] - 2021-04-19
### Changed
- Less strict `postgresql` and `php` dependencies.

## [0.3.1] - 2021-04-16
### Changed
- Remove `reject_unknown_client_hostname` from `smtpd_client_restrictions` in postfix.

## [0.3.0] - 2021-03-22
### Added
- Support pop3.
- Specify imap login options.
- Support IPv6 for MTA STS hosts.
- Rspamd multimap rule to whitelist messages from postmaster.

## [0.2.0] - 2021-03-02

### Added
- Implemented `mx_mta_sts_vhost` resource.

### Changed
- Harden SSL settings (Ciphers & Perfect forward secrecy).
- pflogsumm will now parse `/var/log/mail.log.0` (which should be created by logrotate).

## [0.1.0] - 2021-02-20

Draft version.

### Added
- Upload the cookbook to [Chef Supermarket](https://supermarket.chef.io/cookbooks/mx).
