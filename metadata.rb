name 'mx'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
version '0.0.1'
description 'Install and configure a mail server'

recipe 'ngx::default', 'Install and configure a mail server'

source_url 'https://github.com/aspyatkin/mx-cookbook' if respond_to?(:source_url)

supports 'ubuntu'
