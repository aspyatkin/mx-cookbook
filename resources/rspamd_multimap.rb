# frozen_string_literal: true

resource_name :mx_rspamd_multimap
provides :mx_rspamd_multimap

property :rspamd_dir, String, default: '/etc/rspamd'
property :entries, Array, default: []

default_action :configure

action :configure do
  service 'rspamd' do
    action :nothing
  end

  template ::File.join(new_resource.rspamd_dir, 'local.d', 'multimap.conf') do
    cookbook 'mx'
    source 'rspamd/multimap.conf.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(entries: new_resource.entries)
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end
end
