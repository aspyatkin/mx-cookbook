resource_name :mx_rspamd
provides :mx_rspamd

default_action :setup

property :password, String, required: true

property :fqdn, String, required: true
property :listen, [String, NilClass]
property :default_server, [true, false], default: false
property :access_log_options, String, default: 'combined'
property :error_log_options, String, default: 'error'
property :hsts_max_age, Integer, default: 15_724_800
property :ocsp_stapling, [true, false], default: true

property :milter_host, String, default: '127.0.0.1'
property :milter_port, Integer, default: 11_332

property :normal_host, String, default: '127.0.0.1'
property :normal_port, Integer, default: 11_333

property :controller_host, String, default: '127.0.0.1'
property :controller_port, Integer, default: 11_334

property :dkim_domain_selector_map, Hash, default: {}

property :vlt_provider, Proc, default: -> { nil }
property :vlt_format, Integer, default: 2

property :redis_host, String, required: true
property :redis_port, Integer, required: true

property :user, String, default: '_rspamd'
property :group, String, default: '_rspamd'

property :nameservers, Array, required: true
property :postmaster, String, required: true
property :postmaster_score, Float, default: -15.0

action :setup do
  unless node.run_state.key?('mx')
    node.run_state['mx'] = {}
  end

  unless node.run_state['mx'].key?('rspamd')
    node.run_state['mx']['rspamd'] = {
      'milter_host' => nil,
      'milter_port' => nil,
    }
  end

  node.run_state['mx']['rspamd']['milter_host'] = new_resource.milter_host
  node.run_state['mx']['rspamd']['milter_port'] = new_resource.milter_port

  apt_repository 'rspamd' do
    uri 'http://rspamd.com/apt-stable/'
    components ['main']
    key 'https://rspamd.com/apt-stable/gpg.key'
    action :add
  end

  package 'rspamd'

  service 'rspamd' do
    action [:enable, :start]
  end

  rspamd_dir = '/etc/rspamd'

  template ::File.join(rspamd_dir, 'local.d', 'options.inc') do
    cookbook 'mx'
    source 'rspamd/options.inc.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      nameservers: new_resource.nameservers
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  package 'expect'

  template '/usr/local/bin/rspamd-genpw' do
    cookbook 'mx'
    source 'rspamd/genpw.sh.erb'
    owner 'root'
    group node['root_group']
    mode '0755'
    action :create
  end

  template '/usr/local/bin/rspamd-checkpw' do
    cookbook 'mx'
    source 'rspamd/checkpw.sh.erb'
    owner 'root'
    group node['root_group']
    mode '0755'
    action :create
  end

  worker_controller_inc = ::File.join(rspamd_dir, 'local.d', 'worker-controller.inc')

  template worker_controller_inc do
    cookbook 'mx'
    source 'rspamd/worker-controller.inc.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      host: new_resource.controller_host,
      port: new_resource.controller_port,
      password: new_resource.password
    )
    sensitive true
    action :create
    notifies :reload, 'service[rspamd]', :delayed
    not_if { ::ChefCookbook::Mx::Rspamd.checkpw?(new_resource.password, worker_controller_inc) }
  end

  template ::File.join(rspamd_dir, 'local.d', 'worker-normal.inc') do
    cookbook 'mx'
    source 'rspamd/worker-normal.inc.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      host: new_resource.normal_host,
      port: new_resource.normal_port
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'worker-proxy.inc') do
    cookbook 'mx'
    source 'rspamd/worker-proxy.inc.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      host: new_resource.milter_host,
      port: new_resource.milter_port
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'logging.inc') do
    cookbook 'mx'
    source 'rspamd/logging.inc.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'milter_headers.conf') do
    cookbook 'mx'
    source 'rspamd/milter_headers.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'classifier-bayes.conf') do
    cookbook 'mx'
    source 'rspamd/classifier-bayes.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      redis_host: new_resource.redis_host,
      redis_port: new_resource.redis_port
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  dkim_dir = '/var/lib/rspamd/dkim'

  directory dkim_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  dkim_data = []

  new_resource.dkim_domain_selector_map.each do |domain, selector|
    dkim_domain_dir = ::File.join(dkim_dir, domain)

    directory dkim_domain_dir do
      owner new_resource.user
      group new_resource.group
      mode '0770'
      action :create
    end

    dkim_domain_private_key = ::File.join(dkim_domain_dir, "#{selector}.key")
    dkim_domain_public_key = ::File.join(dkim_domain_dir, "#{selector}.txt")

    dkim_data << {
      domain: domain,
      selector: selector,
      path: dkim_domain_private_key,
    }

    execute "generate DKIM key for domain #{domain} with selector #{selector}" do
      command "rspamadm dkim_keygen -b 2048 -s #{selector} -k #{dkim_domain_private_key} > #{dkim_domain_public_key}"
      user new_resource.user
      group new_resource.group
      action :run
      not_if { ::File.exist?(dkim_domain_private_key) && ::File.exist?(dkim_domain_public_key) }
    end

    execute "#{dkim_domain_private_key} change permissions" do
      command "chmod 440 #{dkim_domain_private_key}"
      action :run
      not_if { ::ChefCookbook::Mx::Rspamd.check_file_permissions(dkim_domain_private_key, '0440') }
    end

    execute "#{dkim_domain_public_key} change permissions" do
      command "chmod 440 #{dkim_domain_public_key}"
      action :run
      not_if { ::ChefCookbook::Mx::Rspamd.check_file_permissions(dkim_domain_public_key, '0440') }
    end
  end

  template ::File.join(rspamd_dir, 'local.d', 'dkim_signing.conf') do
    cookbook 'mx'
    source 'rspamd/dkim_signing.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      dkim_data: dkim_data
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'arc.conf') do
    cookbook 'mx'
    source 'rspamd/dkim_signing.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      dkim_data: dkim_data
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  local_wl_postmaster_map = ::File.join(rspamd_dir, 'local.d', 'local_wl_postmaster.map')

  template local_wl_postmaster_map do
    cookbook 'mx'
    source 'rspamd/local_wl_postmaster.map.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      postmaster: new_resource.postmaster
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  template ::File.join(rspamd_dir, 'local.d', 'multimap.conf') do
    cookbook 'mx'
    source 'rspamd/multimap.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(
      local_wl_postmaster_map: local_wl_postmaster_map,
      score: new_resource.postmaster_score
    )
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  vhost_vars = {
    fqdn: new_resource.fqdn,
    listen: new_resource.listen,
    default_server: new_resource.default_server,
    access_log_options: new_resource.access_log_options,
    error_log_options: new_resource.error_log_options,
    hsts_max_age: new_resource.hsts_max_age,
    ocsp_stapling: new_resource.ocsp_stapling,
    certificate_entries: [],
    controller_host: new_resource.controller_host,
    controller_port: new_resource.controller_port,
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
    template 'rspamd/nginx.vhost.erb'
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
