name 'mx'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
version '0.4.1'
description 'Install and configure a mail server'

source_url 'https://github.com/aspyatkin/mx-cookbook'

supports 'ubuntu'

depends 'ngx', '~> 2.2'
depends 'tls', '~> 4.1'
depends 'postgresql', '>= 7.1'
depends 'php', '>= 4.0'
depends 'ark', '~> 5.1'

gem 'bcrypt'
