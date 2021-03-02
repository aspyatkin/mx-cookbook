# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

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
