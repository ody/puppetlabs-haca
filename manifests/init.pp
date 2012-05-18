# == Class: haca
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
class haca {

  # Install and enable Corosync configuration.
  class { 'corosync':
    enable_secauth    => true,
    bind_address      => $::ipaddress,
    multicast_address => '239.1.1.2',
    authkey           => '/var/lib/puppet/ssl/certs/ca.pem',
  }
  corosync::service { 'pacemaker':
    version => '0',
    notify  => Service['corosync'],
  }

  Service <| title == 'xinetd' |> { restart => '/etc/init.d/xinetd restart && sleep 1 && /etc/init.d/xinetd restart' }

  service { 'apache2': enable => false }
  if $::ca_master {
    if $::ca_master == $::clientcert {
      include haca::primary
    } else {
      include haca::secondary
    }
  } else {
    notify { 'skipping':
      message => 'No cluster master has been elected so we are skipping resource management dependant on that relationship being established.  If you are setting up for the first time or just wish to temporarily override you can do some by prepending the puppet agent command with FACTER_ca_master=$desired_master_node'
    }
  }
}
