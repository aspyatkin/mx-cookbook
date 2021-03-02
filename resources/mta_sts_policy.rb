resource_name :mx_mta_sts_policy
provides :mx_mta_sts_policy

property :mode, String, default: 'testing'
property :mx, Array, required: true
property :max_age, Integer, default: 86_400
property :basedir, String, default: '/opt/chef-mx-mta-sts'

default_action :create

action :create do
  directory new_resource.basedir do
    mode '0755'
    action :create
  end

  entry_basedir = ::File.join(new_resource.basedir, new_resource.name)

  directory entry_basedir do
    mode '0755'
    action :create
  end

  template ::File.join(entry_basedir, 'mta-sts.txt') do
    cookbook 'mx'
    source 'mta-sts/mta-sts.txt.erb'
    variables(
      mode: new_resource.mode,
      mx: new_resource.mx,
      max_age: new_resource.max_age
    )
    action :create
  end
end
