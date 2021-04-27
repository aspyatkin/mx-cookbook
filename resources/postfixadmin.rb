resource_name :mx_postfixadmin
provides :mx_postfixadmin

default_action :setup

property :user, String, default: 'postfixadmin'
property :group, String, default: 'postfixadmin'

property :url_template, String, default: 'https://github.com/postfixadmin/postfixadmin/archive/postfixadmin-%<version>s.tar.gz'
property :version, String, default: '3.3.5'
property :checksum, String, default: '675c6278b14db4efa35d264c4c28abc9b5f131f31f2d52f74c46a1d3dcaff97d'

property :db_host, String, default: '127.0.0.1'
property :db_port, Integer, default: 5432
property :db_name, String, required: true
property :db_locale, String, required: true
property :db_user, String, required: true
property :db_password, String, required: true

property :setup_password, String, required: true
property :setup_password_salt, String, required: true

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

property :conf, Hash, default: {}

property :vmail_state, Hash, required: true

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

  ark new_resource.name do
    url format(new_resource.url_template, version: new_resource.version)
    version new_resource.version
    checksum new_resource.checksum
    owner new_resource.user
    group new_resource.group
    action :install
  end

  postgresql_user new_resource.db_user do
    password new_resource.db_password
    action :create
  end

  postgresql_database new_resource.db_name do
    locale new_resource.db_locale
    owner new_resource.db_user
    action :create
  end

  mailbox_postdeletion_path = '/usr/local/bin/postfixadmin-mailbox-postdeletion'

  template mailbox_postdeletion_path do
    cookbook 'mx'
    source 'postfixadmin/mailbox-postdeletion.sh.erb'
    owner 'root'
    group node['root_group']
    mode '0755'
    variables(
      mailbox_dir: new_resource.vmail_state['mailbox_dir'],
      mailbox_trash_dir: new_resource.vmail_state['mailbox_trash_dir'],
      sieve_dir: new_resource.vmail_state['sieve_dir'],
      sieve_trash_dir: new_resource.vmail_state['sieve_trash_dir']
    )
    action :create
  end

  domain_postdeletion_path = '/usr/local/bin/postfixadmin-domain-postdeletion'

  template domain_postdeletion_path do
    cookbook 'mx'
    source 'postfixadmin/domain-postdeletion.sh.erb'
    owner 'root'
    group node['root_group']
    mode '0755'
    variables(
      mailbox_dir: new_resource.vmail_state['mailbox_dir'],
      mailbox_trash_dir: new_resource.vmail_state['mailbox_trash_dir'],
      sieve_dir: new_resource.vmail_state['sieve_dir'],
      sieve_trash_dir: new_resource.vmail_state['sieve_trash_dir']
    )
    action :create
  end

  file "/etc/sudoers.d/#{new_resource.user}" do
    owner 'root'
    group node['root_group']
    content "#{new_resource.user} ALL=(#{new_resource.vmail_state['user']}) NOPASSWD: #{mailbox_postdeletion_path}, #{domain_postdeletion_path}\n"
    mode '0440'
    action :create
  end

  template 'postfixadmin configuration' do
    cookbook 'mx'
    path "#{node['ark']['prefix_root']}/#{new_resource.name}/config.local.php"
    source 'postfixadmin/config.local.php.erb'
    owner new_resource.user
    group new_resource.group
    mode '0640'
    variables(
      database_type: 'pgsql',
      database_host: new_resource.db_host,
      database_port: new_resource.db_port,
      database_user: new_resource.db_user,
      database_password: new_resource.db_password,
      database_name: new_resource.db_name,
      setup_password: ::ChefCookbook::Mx::Postfixadmin.setup_password(
        new_resource.setup_password,
        new_resource.setup_password_salt
      ),
      vmail_user: new_resource.vmail_state['user'],
      mailbox_postdeletion_path: mailbox_postdeletion_path,
      domain_postdeletion_path: domain_postdeletion_path,
      conf: new_resource.conf
    )
    sensitive true
    action :create
  end

  postfixadmin_templates_dir = ::File.join(
    node['ark']['prefix_root'],
    new_resource.name,
    'templates_c'
  )

  directory postfixadmin_templates_dir do
    owner new_resource.user
    group new_resource.group
    recursive false
    mode '0700'
    action :create
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
    root: ::File.join(node['ark']['prefix_root'], new_resource.name, 'public'),
    fastcgi_pass: "unix:#{php_fpm_sock}",
    hsts_max_age: new_resource.hsts_max_age,
    ocsp_stapling: new_resource.ocsp_stapling,
    enable_setup_page: new_resource.enable_setup_page,
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
    template 'postfixadmin/nginx.vhost.erb'
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

  postfixadmin_dir = '/etc/postfixadmin'

  directory postfixadmin_dir do
    owner new_resource.user
    group new_resource.group
    recursive false
    mode '0700'
    action :create
  end

  create_extra_tables_script = ::File.join(postfixadmin_dir, 'create_extra_tables.sql')

  template create_extra_tables_script do
    cookbook 'mx'
    source 'postfixadmin/create_extra_tables.sql.erb'
    owner new_resource.user
    group new_resource.group
    mode '0640'
  end

  execute 'create postfixadmin extra tables' do
    command "psql -h #{new_resource.db_host} -p #{new_resource.db_port} -U #{new_resource.db_user} -d #{new_resource.db_name} -f #{create_extra_tables_script}"
    user new_resource.user
    group new_resource.group
    environment(
      'PGPASSWORD' => new_resource.db_password
    )
    sensitive true
    action :run
  end
end
