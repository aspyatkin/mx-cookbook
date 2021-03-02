resource_name :mx_postfix
provides :mx_postfix

default_action :setup

property :fqdn, String, required: true

property :user, String, default: 'postfix'
property :group, String, default: 'postfix'

property :db_host, String, default: '127.0.0.1'
property :db_port, Integer, default: 5432
property :db_name, String, required: true
property :db_user, String, required: true
property :db_password, String, required: true
property :db_root_user, String, required: true
property :db_root_password, String, required: true

property :milter_host, String, required: true
property :milter_port, Integer, required: true

property :vlt_provider, Proc, default: -> { nil }
property :vlt_format, Integer, default: 2

property :postmaster, String, required: true
property :pflogsumm_report, Hash, default: {}

property :dh512_param_file, String, required: true
property :dh_param_file, String, required: true

action :setup do
  unless node.run_state.key?('mx')
    node.run_state['mx'] = {}
  end

  unless node.run_state['mx'].key?('postfix')
    node.run_state['mx']['postfix'] = {
      'user' => nil,
      'group' => nil,
    }
  end

  node.run_state['mx']['postfix']['user'] = new_resource.user
  node.run_state['mx']['postfix']['group'] = new_resource.group

  package 'telnet'
  package 'mailutils'
  package 'postfix'
  package 'postfix-pgsql'

  service 'postfix' do
    action [:enable, :start]
  end

  postgresql_user new_resource.db_user do
    password new_resource.db_password
    action :create
  end

  tls = ::ChefCookbook::TLS.new(node, vlt_provider: new_resource.vlt_provider, vlt_format: new_resource.vlt_format)

  tls_rsa_certificate new_resource.fqdn do
    vlt_provider new_resource.vlt_provider
    vlt_format new_resource.vlt_format
    action :deploy
  end

  if tls.has_ec_certificate?(new_resource.fqdn)
    tls_ec_certificate new_resource.fqdn do
      vlt_provider new_resource.vlt_provider
      vlt_format new_resource.vlt_format
      action :deploy
    end
  end

  postfix_dir = '/etc/postfix'

  grant_access_script = ::File.join(postfix_dir, 'postgres_grant_access.sql')

  template grant_access_script do
    cookbook 'mx'
    source 'postfix/postgres_grant_access.sql.erb'
    owner 'root'
    group node['root_group']
    mode '0640'
    variables(
      user: new_resource.db_user
    )
  end

  execute 'grant access to postfixadmin tables' do
    command "psql -h #{new_resource.db_host} -p #{new_resource.db_port} -U #{new_resource.db_root_user} -d #{new_resource.db_name} -f #{grant_access_script}"
    user 'root'
    group node['root_group']
    environment(
      'PGPASSWORD' => new_resource.db_root_password
    )
    sensitive true
    action :run
  end

  map_variables = {
    user: new_resource.db_user,
    password: new_resource.db_password,
    host: new_resource.db_host,
    port: new_resource.db_port,
    dbname: new_resource.db_name,
  }

  virtual_alias_maps = []

  postgres_virtual_alias_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_maps.cf')

  template postgres_virtual_alias_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_alias_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_maps}"

  postgres_virtual_alias_domain_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_maps.cf')

  template postgres_virtual_alias_domain_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_alias_domain_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_maps}"

  postgres_virtual_alias_domain_catchall_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_catchall_maps.cf')

  template postgres_virtual_alias_domain_catchall_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_alias_domain_catchall_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_catchall_maps}"

  virtual_mailbox_domains = []

  postgres_virtual_domain_maps = ::File.join(postfix_dir, 'postgres_virtual_domain_maps.cf')

  template postgres_virtual_domain_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_domain_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_mailbox_domains << "proxy:pgsql:#{postgres_virtual_domain_maps}"

  virtual_mailbox_maps = []

  postgres_virtual_mailbox_maps = ::File.join(postfix_dir, 'postgres_virtual_mailbox_maps.cf')

  template postgres_virtual_mailbox_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_mailbox_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_mailbox_maps << "proxy:pgsql:#{postgres_virtual_mailbox_maps}"

  postgres_virtual_alias_domain_mailbox_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_mailbox_maps.cf')

  template postgres_virtual_alias_domain_mailbox_maps do
    cookbook 'mx'
    source 'postfix/postgres_virtual_alias_domain_mailbox_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  virtual_mailbox_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_mailbox_maps}"

  postscreen_access = ::File.join(postfix_dir, 'postscreen_access.cidr')

  template postscreen_access do
    cookbook 'mx'
    source 'postfix/postscreen_access.cidr.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    sensitive true
    action :create_if_missing
    notifies :reload, 'service[postfix]', :delayed
  end

  template '/etc/postfix/main.cf' do
    cookbook 'mx'
    source 'postfix/main.cf.erb'
    mode '0644'
    variables(
      fqdn: new_resource.fqdn,
      rsa_certificate_entry: tls.rsa_certificate_entry(new_resource.fqdn),
      ecc_certificate_entry: tls.has_ec_certificate?(new_resource.fqdn) ? tls.ec_certificate_entry(new_resource.fqdn) : nil,
      virtual_mailbox_domains: virtual_mailbox_domains,
      virtual_mailbox_maps: virtual_mailbox_maps,
      virtual_alias_maps: virtual_alias_maps,
      milter_host: new_resource.milter_host,
      milter_port: new_resource.milter_port,
      postscreen_access: postscreen_access,
      dh512_param_file: new_resource.dh512_param_file,
      dh_param_file: new_resource.dh_param_file
    )
    action :create
    notifies :restart, 'service[postfix]', :delayed
  end

  submission_header_cleanup = ::File.join(postfix_dir, 'submission_header_cleanup')

  template submission_header_cleanup do
    cookbook 'mx'
    source 'postfix/submission_header_cleanup.erb'
    mode '0644'
    notifies :restart, 'service[postfix]', :delayed
    action :create
  end

  postgres_sender_login_maps = ::File.join(postfix_dir, 'postgres_sender_login_maps.cf')

  template postgres_sender_login_maps do
    cookbook 'mx'
    source 'postfix/postgres_sender_login_maps.cf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables map_variables
    sensitive true
    action :create
    notifies :reload, 'service[postfix]', :delayed
  end

  template '/etc/postfix/master.cf' do
    cookbook 'mx'
    source 'postfix/master.cf.erb'
    mode '0644'
    variables(
      sender_login_maps: postgres_sender_login_maps,
      submission_header_cleanup: submission_header_cleanup
    )
    action :create
    notifies :restart, 'service[postfix]', :delayed
  end

  package 'pflogsumm'

  cron 'send pflogsumm report' do
    command %(/usr/sbin/pflogsumm /var/log/mail.log.0 --problems-first --rej-add-from --verbose-msg-detail -q | /usr/bin/mail -s "Pflogsumm report" -a "From: #{new_resource.postmaster}" #{new_resource.pflogsumm_report['mailto']})
    minute new_resource.pflogsumm_report['minute']
    hour new_resource.pflogsumm_report['hour']
    day new_resource.pflogsumm_report['day']
    month new_resource.pflogsumm_report['month']
    weekday new_resource.pflogsumm_report['weekday']
    action new_resource.pflogsumm_report['enabled'] ? :create : :delete
  end
end
