#!/usr/bin/env perl
#
#
use warnings;
use strict;
use bytes;
use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

my $decoded_data;
my $encoded;
my $pointer = 0;
my $flattened_tree;
my $data_offset;
my $huff_tree;
my $bits_read = 1;
my $counter = 0;

while ($bits_read != 0 or length $encoded > 0) {
    my $chunk;

    $bits_read = read STDIN, $chunk, 2_048_000;

    if ($bits_read == 0 and length $encoded == 0) {
        exit;
    }

    for my $byte (split //, $chunk) {
        $encoded .= (sprintf "%08b", ord $byte);
    }

    $encoded =~ s/^(\d{8})//;
    my $size1 = bin2dec($1);

    $encoded =~ s/^(\d{8})//;
    my $size2 = bin2dec($1);
    my $size  = $size1+$size2;

    $encoded =~ s/^(\d{8})//;
    my $offset  = bin2dec($1);

    for (my $i=0;$i<$size;$i++) {
        $encoded =~ s/^(\d{8})//;
        $flattened_tree .= $1;
    }
    $flattened_tree =~ s/\d{$offset}$//;


    my $t0 = [gettimeofday];
    #uses GLOBAL $flattened_tree
    $huff_tree = return_tree();

    my $elapsed = tv_interval ( $t0 );
    print STDERR "making tree: $elapsed\n";

    $encoded =~ s/^(\d{8})//;
    $data_offset = bin2dec($1);

    $t0 = [gettimeofday];
    $encoded = decode($huff_tree, $encoded);
    $elapsed = tv_interval ( $t0 );
    print STDERR "decode data: $elapsed\n";

    print $decoded_data;

    $huff_tree = {};
    $decoded_data = '';
    $data_offset = undef;
    $flattened_tree = '';
    $counter++;
}

sub return_tree {
    my $node;
    if ($flattened_tree =~ /^1(\d)(\d{8})/) {
        if ($1 eq 0) {
            $node->{symbol} = chr bin2dec($2); 
        } elsif ($1 eq 1) {
            $node->{symbol} = ($1 . $2) if $1 == 1; 
        }
        $flattened_tree =~ s/^\d{10}//;
        return $node;
    } else {
        $flattened_tree =~ s/^(\d)//;
        $node->{left} = return_tree();
        $node->{right} = return_tree();
        return $node;
    }
}

sub decode {
    my $tree = shift;
    my $encoded_data = shift;

    my $node = $tree;
    while(length $encoded_data > 0) {
        if(defined $node->{symbol}) {
            if ($node->{symbol} eq 100000000) {
                $encoded_data =~ s/^\d{$data_offset}//;
                return $encoded_data;
            } else {
                $decoded_data .= $node->{symbol};
                $node = $tree;
            }
        }
        elsif ($encoded_data =~ /^0/) {
            $encoded_data =~ s/^0//;
            $node = $node->{left};
        }
        elsif($encoded_data =~ /^1/) {
            $encoded_data =~ s/^1//;
            $node = $node->{right};
        }
    }
}

sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}
