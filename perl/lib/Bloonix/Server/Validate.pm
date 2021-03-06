package Bloonix::Server::Validate;

use strict;
use warnings;
use Params::Validate qw();
use Sys::Hostname;
use Bloonix::Config;

sub config {
    my ($class, $config_file) = @_;
    my $config = Bloonix::Config->parse($config_file);
    return $class->main($config);
}

sub main {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        proc_manager => {
            type => Params::Validate::HASHREF
        },
        server_status => {
            type => Params::Validate::HASHREF,
            default => {}
        },
        tcp_server => {
            type => Params::Validate::HASHREF,
            default => {}
        },
        timezone => {
            type => Params::Validate::SCALAR,
            default => "Europe/Berlin"
        },
        user => {
            type => Params::Validate::SCALAR,
            default => "bloonix"
        },
        group => {
            type => Params::Validate::SCALAR,
            default => "bloonix"
        },
        hostname => {
            type => Params::Validate::SCALAR,
            default => Sys::Hostname::hostname()
        },
        elasticsearch => {
            type => Params::Validate::HASHREF,
            default => { }
        },
        database => {
            type => Params::Validate::HASHREF
        },
        logger => {
            type => Params::Validate::HASHREF,
            optional => 1
        },
        elasticsearch_roll_forward => {
            type => Params::Validate::SCALAR,
            default => "/var/log/bloonix/elasticsearch-roll-forward.json"
        },
        smsgateway => {
            type => Params::Validate::HASHREF,
            optional => 1
        },
        email => {
            type => Params::Validate::HASHREF,
            optional => 1
        },
        notifications => {
            type => Params::Validate::HASHREF,
            optional => 1
        },
        redirect_remote_agent_timeouts => {
            type => Params::Validate::HASHREF,
            default => { }
        },
        allow_from => {
            type => Params::Validate::SCALAR | Params::Validate::ARRAYREF,
            default => [ ]
        },
    });

    if ($opts{allow_from} && ref($opts{allow_from}) ne "ARRAY") {
        $opts{allow_from} =~ s/\s//g;
        $opts{allow_from} = [ split /,/, $opts{allow_from} ];
    }

    if ($opts{email}) {
        $opts{notifications}{mail} = delete $opts{email};
    }

    if ($opts{smsgateway}) {
        $opts{notifications}{sms} = delete $opts{smsgateway};
    }

    $class->notifications($opts{notifications});
    $opts{redirect_remote_agent_timeouts} = $class->redirect_remote_agent_timeouts($opts{redirect_remote_agent_timeouts});

    $opts{elasticsearch_roll_forward} = {
        filename => $opts{elasticsearch_roll_forward},
        filelock => 0,
        reopen => 1,
        autoflush => 1,
        mode => "append"
    };

    if (!$opts{proc_manager}{lockfile}) {
        $opts{proc_manager}{lockfile} = "/var/lib/bloonix/ipc/server.%P.lock";
    }

    $opts{tcp_server} = $class->tcp_server($opts{tcp_server});
    $opts{server_status} = $class->server_status($opts{server_status});

    return \%opts;
}

sub tcp_server {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        host => {
            type => Params::Validate::SCALAR,
            optional => 1
        },
        port => {
            type => Params::Validate::SCALAR,
            default => 5460
        },
        use_ssl => {
            type => Params::Validate::SCALAR,
            default => 1
        },
        ssl_key_file => {
            type => Params::Validate::SCALAR,
            default => "/etc/bloonix/server/pki/server.key"
        },
        ssl_cert_file => {
            type => Params::Validate::SCALAR,
            default => "/etc/bloonix/server/pki/server.cert"
        },
        mode => {
            type => Params::Validate::SCALAR,
            default => "failover"
        },
        force_ipv4 => {
            type => Params::Validate::SCALAR,
            regex => qr/^(yes|1|no|0)\z/,
            default => "no"
        }
    });

    if ($opts{host}) {
        $opts{localaddr} = delete $opts{host};
    }

    $opts{localport} = delete $opts{port};
    $opts{auto_connect} = 1;
    $opts{listen} = 1;

    return \%opts;
}

sub server_status {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        enabled => {
            type => Params::Validate::SCALAR,
            default => "yes",
            regex => qr/^(0|1|no|yes)\z/
        },
        allow_from => {
            type => Params::Validate::SCALAR,
            default => "127.0.0.1"
        },
        authkey => {
            type => Params::Validate::SCALAR,
            optional => 1
        }
    });

    # deprecated
    delete $opts{location};

    if ($opts{enabled} eq "no") {
        $opts{enabled} = 0;
    }

    $opts{allow_from} =~ s/\s//g;

    return \%opts;
}

sub notifications {
    my ($class, $notification) = @_;

    $notification->{mail} = $class->mail($notification->{mail} // {});

    if ($notification->{sms}) {
        $notification->{sms} = $class->sms($notification->{sms});
    }
}

sub mail {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        sendmail => {
            type => Params::Validate::SCALAR,
            default => "/usr/sbin/sendmail -t -oi -oem"
        },
        from => {
            type => Params::Validate::SCALAR,
            default => 'bloonix@localhost'
        },
        bcc => {
            type => Params::Validate::SCALAR,
            optional => 1
        },
        subject => {
            type => Params::Validate::SCALAR,
            default => "*** STATUS %s FOR %h (%a) ***"
        },
    });

    return \%opts;
}

sub sms {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        command => {
            type => Params::Validate::SCALAR
        },
        response => {
            type => Params::Validate::SCALAR,
            default => ""
        },
        failover_command => {
            type => Params::Validate::SCALAR,
            optional => 1
        },
        failover_response => {
            type => Params::Validate::SCALAR,
            default => ""
        }
    });

    return \%opts;
}

sub redirect_remote_agent_timeouts {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        sms_to => {
            type => Params::Validate::SCALAR,
            default => ""
        },
        mail_to => {
            type => Params::Validate::SCALAR,
            default => ""
        }
    });

    # deprecated
    delete $opts{sms_to};

    return \%opts;
}

sub request {
    my $self = shift;

    my %opts = Params::Validate::validate(@_, {
        action => {
            type => Params::Validate::SCALAR,
            regex => qr/^(get-services|post-service-data)\z/
        },
        whoami => {
            type => Params::Validate::SCALAR,
            regex => qr/^[\w\-]+\z/,
            default => "agent"
        },
        version => {
            type => Params::Validate::SCALAR,
            regex => qr/^\d+\.\d+\z/
        },
        host_id => {
            type => Params::Validate::SCALAR,
            regex => qr/^[a-z0-9\-\.]+\z/,
            optional => 1
        },
        hostid => {
            type => Params::Validate::SCALAR,
            regex => qr/^[a-z0-9\-\.]+\z/,
            optional => 1
        },
        agent_id => {
            type => Params::Validate::SCALAR,
            default => "localhost"
        },
        agentid => {
            type => Params::Validate::SCALAR,
            optional => 1
        },
        password => {
            type => Params::Validate::SCALAR,
            optional => 1
        },
        data => {
            type => Params::Validate::HASHREF,
            optional => 1
        },
        facts => {
            type => Params::Validate::HASHREF,
            default => { }
        }
    });

    if (defined $opts{hostid}) {
        $opts{host_id} = $opts{hostid};
    }
    if ($opts{host_id} =~ /^(\d+)(\.(all|remote|localhost|intranet)){0,3}\z/) {
        $opts{host_id} = $1;
    }
    if ($opts{agentid}) {
        $opts{agent_id} = $opts{agentid};
    }
    if ($opts{agent_id} eq "0" || $opts{agent_id} eq "local") {
        $opts{agent_id} = "localhost";
    }
    if ($opts{agent_id} eq "9000") {
        $opts{agent_id} = "remote";
    }

    if (!defined $opts{host_id}) {
        die "missing host id in agent request";
    }

    return \%opts;
}

sub argv {
    my $class = shift;

    my %opts = Params::Validate::validate(@_, {
        config_file => {
            type => Params::Validate::SCALAR,
            default => "/etc/bloonix/server/main.conf"
        },
        pid_file => {
            type => Params::Validate::SCALAR,
            default => "/var/run/bloonix/bloonix-server.pid"
        }
    });

    return \%opts;
}

1;
