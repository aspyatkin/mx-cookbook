# frozen_string_literal: true

resource_name :mx_rspamd_multimap_entry
provides :mx_rspamd_multimap_entry

property :rspamd_dir, String, default: '/etc/rspamd'
property :rspamd_multimap_resource_name, String, default: 'default'
property :map_data, Array, default: []
property :entry_properties, Hash, default: {}

default_action :create

action :create do
  service 'rspamd' do
    action :nothing
  end

  map_file_name = ::File.join(new_resource.rspamd_dir, 'local.d', "#{new_resource.name}.map")

  template map_file_name do
    cookbook 'mx'
    source 'rspamd/data.map.erb'
    owner 'root'
    group node['root_group']
    mode '0644'
    variables(data: new_resource.map_data)
    action :create
    notifies :reload, 'service[rspamd]', :delayed
  end

  unless new_resource.map_data.empty?
    with_run_context :root do
      cur_res = new_resource
      entry_data = {
        name: cur_res.name,
        map: map_file_name
      }.merge(cur_res.entry_properties)

      edit_resource(:mx_rspamd_multimap, cur_res.rspamd_multimap_resource_name) do
        rspamd_dir cur_res.rspamd_dir
        entries(entries + [entry_data])
        action :nothing
        delayed_action :configure
      end
    end
  end
end
