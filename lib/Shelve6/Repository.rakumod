use Cro::HTTP::Response;
use JSON::Fast;

use Shelve6::Logging;
use Shelve6::Server;
use Shelve6::Store;
use X::Shelve6::ClientError;

unit class Shelve6::Repository;

has Str $!name;
has Str $!base-url;
has Shelve6::Server $!server;
has Shelve6::Store $!store;

my $log = Shelve6::Logging.new('repo');

method configure(%options) {
    # XXX validate and more options
    $!name = %options<name>;
}

method register-server($server) {
    $!server = $server;
    $!server.register-repo($!name, self);
    $!base-url = $!server.base-url;
}

method register-store($store) {
    $!store = $store;
}

method start() {
    $log.debug("Setting up repository '$!name', reachable under '$!base-url/repos/$!name'");
}

method stop() {
}

method put($filename, $blob) {
    # a bit primitive, but there you go for now
    my $proc = run(<tar --list -z -f - >, :out, :in);
    $proc.in.write($blob);
    $proc.in.close;
    my $out = $proc.out.slurp-rest();
    my $meta-membername;
    for $out.lines -> $l {
        # XXX ends-with? should be complete match
        if $l.ends-with('META6.json') || $l.ends-with('META6.info') {
            $meta-membername = $l;
        }
    }
    if ! defined $meta-membername {
        my $msg = "Artifact '$filename' seems to not contain a META6.json or .info, refusing";
        $log.warn($msg);
        die X::Shelve6::ClientError.new(code => 403, message => $msg);
    }
    
    $proc = run(qqw{tar --get --to-stdout -z -f - $meta-membername}, :out, :in);
    $proc.in.write($blob);
    $proc.in.close;
    my $meta-json = $proc.out.slurp-rest();
    try {
        my $parsed = from-json($meta-json);
        # XXX in the future also perform pluggable checks on it
    }
    if $! {
        my $msg = "Artifact '$filename' has malformed metadata, refusing";
        $log.warn($msg);
        die X::Shelve6::ClientError.new(code => 403, message => $msg);
    }
    $!store.put($!name, $filename, $blob, $meta-json);
}

method get-package-list() {
    # XXX cache the list?
    my $packages = $!store.list-artifacts($!name);
    my @result-list;
    for $packages -> $p {
        my $meta-json = $!store.get-meta($!name, $p);
        my $meta = from-json($meta-json);
        $meta{"source-url"} = "$!base-url/repos/$!name/$p";
        @result-list.push($meta);
    }
    $log.debug("fetch of package list from repo '$!name' with {@result-list.elems} entries");
    return @result-list;
}

method get-file($fname) {
    if $!store.artifact-exists($!name, $fname) {
        $log.debug("fetch of artifact '$fname' from repo '$!name'");
        return $fname;
    }
    else {
        $log.debug("attempt to fetch non-existing artifact '$fname' from repo '$!name'");
        return Any;
    }
}
