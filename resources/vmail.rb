resource_name :mx_vmail
provides :mx_vmail

default_action :setup

property :user, String, required: true
property :uid, Integer, required: true
property :group, String, required: true
property :gid, Integer, required: true
property :basedir, String, required: true

action :setup do
  unless node.run_state.key?('mx')
    node.run_state['mx'] = {}
  end

  unless node.run_state['mx'].key?('vmail')
    node.run_state['mx']['vmail'] = {
      'user' => nil,
      'uid' => nil,
      'group' => nil,
      'gid' => nil,
      'mailbox_dir' => nil,
      'mailbox_trash_dir' => nil,
      'sieve_dir' => nil,
      'sieve_trash_dir' => nil,
      'sieve_global_dir' => nil,
    }
  end

  node.run_state['mx']['vmail']['user'] = new_resource.user
  node.run_state['mx']['vmail']['uid'] = new_resource.uid
  node.run_state['mx']['vmail']['group'] = new_resource.group
  node.run_state['mx']['vmail']['gid'] = new_resource.gid

  group new_resource.group do
    gid new_resource.gid
    system true
    action :create
  end

  user new_resource.user do
    uid new_resource.uid
    group new_resource.group
    shell '/bin/false'
    system true
    action :create
  end

  directory new_resource.basedir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  mailbox_dir = ::File.join(new_resource.basedir, 'mailboxes')
  node.run_state['mx']['vmail']['mailbox_dir'] = mailbox_dir

  directory mailbox_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  mailbox_trash_dir = ::File.join(mailbox_dir, '.trash')
  node.run_state['mx']['vmail']['mailbox_trash_dir'] = mailbox_trash_dir

  directory mailbox_trash_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  sieve_dir = ::File.join(new_resource.basedir, 'sieve')
  node.run_state['mx']['vmail']['sieve_dir'] = sieve_dir

  directory sieve_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  sieve_trash_dir = ::File.join(sieve_dir, '.trash')
  node.run_state['mx']['vmail']['sieve_trash_dir'] = sieve_trash_dir

  directory sieve_trash_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end

  sieve_global_dir = ::File.join(sieve_dir, 'global')
  node.run_state['mx']['vmail']['sieve_global_dir'] = sieve_global_dir

  directory sieve_global_dir do
    owner new_resource.user
    group new_resource.group
    mode '0770'
    action :create
  end
end
