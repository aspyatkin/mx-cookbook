name 'mx'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
version '0.3.0'
description 'Install and configure a mail server'

source_url 'https://github.com/aspyatkin/mx-cookbook'

supports 'ubuntu'

depends 'ngx', '~> 2.2'
depends 'tls', '~> 4.1'
depends 'postgresql', '~> 8.2'
depends 'php', '~> 8.0'
depends 'ark', '~> 5.1'

gem 'bcrypt'
