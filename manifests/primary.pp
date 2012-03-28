# == Class: haca::primary
#
# Full description of class haca here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if it
#   has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should not be used in preference to class parameters  as of
#   Puppet 2.6.)
#
# === Examples
#
#  class { haca:
#    servers => [ 'pool.ntp.org', 'ntp.local.company.com' ]
#  }
#
# === Authors
#
# Author Name <author@domain.com>
#
# === Copyright
#
# Copyright 2011 Your name here, unless otherwise noted.
#
class haca::primary {

  # Setup stunnel for authentication and encryption of our sensitive certificate
  # authority data.
  include stunnel
  Stunnel::Tun {
    require => Package[$stunnel::data::package],
    notify  => Service[$stunnel::data::service],
  }
  stunnel::tun { 'rsyncd':
    chroot  => '/var/lib/stunnel4/rsyncd',
    user    => 'pe-puppet',
    group   => 'pe-puppet',
    client  => false,
    accept  => '1873',
    connect => '873',
  }

  # Install and enable Corosync configuration for VIP and Apache management.
  class { 'corosync':
    enable_secauth    => true,
    bind_address      => '0.0.0.0',
    multicast_address => '239.1.1.2',
  }
  corosync::service { 'pacemaker':
    version => '0',
    notify  => Service['corosync'],
  }

  cs_property { 'no-quorum_policy':
    value => 'ignore',
    require => Corosync::Service['pacemaker'],
  }
  cs_property { 'stonith-enabled':
    value => 'false',
    require => Corosync::Service['pacemaker'],
  }
  cs_property { 'resource-stickiness':
    value => '100',
    require => Corosync::Service['pacemaker'],
  }

  cs_primitive { 'ca_vip':
    primitive_class => 'ocf',
    primitive_type  => 'IPaddr2',
    provided_by     => 'heartbeat',
    parameters      => { 'ip' => '172.16.210.100', 'cidr_netmask' => '32' },
    operations      => { 'monitor' => { 'interval' => '30s' } },
  }
  # I really really wished we used symlinks a la debian in PE so a could more
  # easily select what I wanted to run on a specific machine.
  cs_primitive { 'pe_ca_service':
    primitive_class => 'lsb',
    primitive_type  => 'pe-httpd',
    provided_by     => 'heartbeat',
    operations      => { 'monitor' => '10s' },
    require         => Cs_primitive['ca_vip'],
  }
  cs_colocation { 'vip_ca_service':
    primitives => [ 'ca_vip', 'pe_ca_service' ],
    require    => Cs_primitive[[ 'pe_ca_service', 'ca_vip' ]],
  }
  cs_order { 'vip_service':
    first   => 'ca_vip',
    second  => 'pe_ca_service',
    require => Cs_colocation['vip_ca_service'],
  }

  Cs_primitive['ca_vip'] -> Class['rsync::server']

  # Set up our rsync module for obtaining the certifate athority data.
  include rsync
  class { 'rsync::server': address => '172.16.210.100' }
  rsync::server::module { 'ca':
    path           => '/etc/puppetlabs/puppet/ssl/ca',
    read_only      => true,
    write_only     => false,
    list           => true,
    uid            => 'pe-puppet',
    gid            => 'pe-puppet',
    incoming_chmod => false,
    outgoing_chmod => false,
    lock_file      => '/var/run/rsyncd.lock',
    notify         => Service['rsync'],
  }
}
