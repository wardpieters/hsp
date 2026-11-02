use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use MIME::Base64 qw(decode_base64);
use PVE::Cluster;
use PVE::INotify;
use PVE::LXC::Config;

# Invoked over SSH with base64 JSON, never shell-interpolated configuration values.
my ($payload, $operation) = @ARGV;
die "Expected apply or remove operation\n" unless defined($operation) && $operation =~ /\A(?:apply|remove)\z/;
my $input = decode_json(decode_base64($payload // ''));
my $vmid = $input->{vm_id};
die "Invalid CT ID\n" unless defined($vmid) && $vmid =~ /\A[0-9]+\z/ && $vmid >= 100 && $vmid <= 999999999;
die "SSH host does not match configured Proxmox node\n"
    unless ($input->{node_name} // '') eq PVE::INotify::nodename();
my $entries = $input->{entries};
die "Expected LXC entries\n" unless ref($entries) eq 'ARRAY';
for my $entry (@$entries) {
    die "Invalid LXC entry\n" unless ref($entry) eq 'ARRAY' && @$entry == 2;
    my ($key, $value) = @$entry;
    die "Unsupported LXC key\n" unless defined($key) &&
        $key =~ /\A(?:lxc\.mount\.entry|lxc\.cgroup2\.[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)\z/;
    die "Expected single-line LXC value\n" unless defined($value) && !ref($value) &&
        $value =~ /\A\S(?:.*\S)?\z/ && $value !~ /[\r\n\x00]/;
}

PVE::LXC::Config->lock_config($vmid, sub {
    PVE::Cluster::cfs_update();
    my $conf;
    eval { $conf = PVE::LXC::Config->load_config($vmid); };
    if (my $error = $@) {
        # An externally deleted container has no raw entries left to remove.
        return if $operation eq 'remove' && $error =~ /Configuration file '[^']+' does not exist/;
        die $error;
    }
    PVE::LXC::Config->check_lock($conf);
    my $old = $conf->{lxc} // [];
    my %owned = map { encode_json($_) => 1 } @$entries;
    my @next;
    if ($operation eq 'remove') {
        @next = grep { !$owned{encode_json($_)} } @$old;
    } else {
        @next = @$old;
        my %present = map { encode_json($_) => 1 } @next;
        for my $entry (@$entries) {
            push @next, $entry unless $present{encode_json($entry)}++;
        }
    }
    return if encode_json($old) eq encode_json(\@next);
    if (@next) { $conf->{lxc} = \@next; }
    else { delete $conf->{lxc}; }
    PVE::LXC::Config->write_config($vmid, $conf);
});
