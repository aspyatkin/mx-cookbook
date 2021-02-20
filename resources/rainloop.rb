resource_name :mx_rainloop
provides :mx_rainloop

default_action :setup

property :user, String, default: 'rainloop'
property :group, String, default: 'rainloop'

property :url_template, String, default: 'https://github.com/RainLoop/rainloop-webmail/releases/download/v%<version>s/rainloop-community-%<version>s.zip'
property :version, String, default: '1.15.0'
property :checksum, String, default: 'cbfa285d015e923a32440a64be0085347e96ad40fe40758864bb2fcc26cdad5e'

property :php_fpm_pool_max_children, Integer, default: 5
property :php_fpm_pool_start_servers, Integer, default: 2
property :php_fpm_pool_min_spare_servers, Integer, default: 1
property :php_fpm_pool_max_spare_servers, Integer, default: 3
property :php_fpm_pool_max_requests, Integer, default: 100
property :php_fpm_pool_memory_limit, String, default: '64M'

property :fqdn, String, required: true
property :listen, [String, NilClass]
property :default_server, [true, false], default: false
property :access_log_options, String, default: 'combined'
property :error_log_options, String, default: 'error'
property :hsts_max_age, Integer, default: 15_724_800
property :ocsp_stapling, [true, false], default: true
property :enable_setup_page, [true, false], default: false

property :vlt_provider, Proc, default: -> { nil }
property :vlt_format, Integer, default: 2

action :setup do
  group new_resource.group do
    system true
    action :create
  end

  user new_resource.user do
    group new_resource.group
    shell '/bin/bash'
    system true
    action :create
  end

  package 'unzip'
  package 'php-curl'

  ark new_resource.name do
    url format(new_resource.url_template, version: new_resource.version)
    version new_resource.version
    checksum new_resource.checksum
    owner new_resource.user
    group new_resource.group
    append_env_path false
    strip_components 0
    action :install
  end

  php_fpm_sock = ::File.join('/var/run', "php-fpm-#{new_resource.name}.sock")

  php_fpm_pool new_resource.name do
    listen php_fpm_sock
    user new_resource.user
    group new_resource.group
    process_manager 'dynamic'
    max_children new_resource.php_fpm_pool_max_children
    start_servers new_resource.php_fpm_pool_start_servers
    min_spare_servers new_resource.php_fpm_pool_min_spare_servers
    max_spare_servers new_resource.php_fpm_pool_max_spare_servers
    additional_config(
      'pm.max_requests' => new_resource.php_fpm_pool_max_requests,
      'listen.mode' => '0666',
      'php_admin_flag[log_errors]' => 'on',
      'php_value[date.timezone]' => 'UTC',
      'php_value[expose_php]' => 'off',
      'php_value[display_errors]' => 'off',
      'php_value[memory_limit]' => new_resource.php_fpm_pool_memory_limit
    )
  end

  vhost_vars = {
    fqdn: new_resource.fqdn,
    listen: new_resource.listen,
    default_server: new_resource.default_server,
    access_log_options: new_resource.access_log_options,
    error_log_options: new_resource.error_log_options,
    root: ::File.join(node['ark']['prefix_root'], new_resource.name),
    fastcgi_pass: "unix:#{php_fpm_sock}",
    hsts_max_age: new_resource.hsts_max_age,
    ocsp_stapling: new_resource.ocsp_stapling,
    certificate_entries: [],
  }

  tls_rsa_certificate new_resource.fqdn do
    vlt_provider new_resource.vlt_provider
    vlt_format new_resource.vlt_format
    action :deploy
  end

  tls = ::ChefCookbook::TLS.new(node, vlt_provider: new_resource.vlt_provider, vlt_format: new_resource.vlt_format)
  vhost_vars[:certificate_entries] << tls.rsa_certificate_entry(new_resource.fqdn)

  if tls.has_ec_certificate?(new_resource.fqdn)
    tls_ec_certificate new_resource.fqdn do
      vlt_provider new_resource.vlt_provider
      vlt_format new_resource.vlt_format
      action :deploy
    end

    vhost_vars[:certificate_entries] << tls.ec_certificate_entry(new_resource.fqdn)
  end

  nginx_vhost new_resource.name do
    cookbook 'mx'
    template 'rainloop/nginx.vhost.erb'
    variables(lazy do
      vhost_vars.merge(
        access_log: ::File.join(
          node.run_state['nginx']['log_dir'],
          "#{new_resource.name}-access.log"
        ),
        error_log: ::File.join(
          node.run_state['nginx']['log_dir'],
          "#{new_resource.name}-error.log"
        )
      )
    end)
    action :enable
  end
end
