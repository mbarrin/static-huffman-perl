#!/usr/bin/env perl
#
#
use warnings;
use strict;
use bytes;
use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

my $eof = 1;
my $code;
my %codebook;
my $flattened;

my $bits_read = 1;

my $counter =0;

while ($bits_read != 0) {
    my $chunk;
    my @data;
    my %contents;

    $bits_read = read STDIN, $chunk, 2_048_000;

    if ($bits_read == 0) {;} 
    else {
        for my $byte (split //sm, $chunk) {
            $contents{$byte}++;
            push @data, $byte;
        }
        
        $chunk = undef;

        #assigns the value 256 to mark the end of a chunk
        $contents{"100000000"} = 1;
        
        my $t0 = [gettimeofday];

        my $huff_tree = make_tree(%contents);
        %contents = ();

        my $elapsed = tv_interval ( $t0 );
        print STDERR "making tree: $elapsed\n";

        #fills GLOBAL %codebook
        $t0 = [gettimeofday];
        build_codebook($huff_tree);
        $elapsed = tv_interval ( $t0 );
        print STDERR "builing codebook: $elapsed\n";

        #fills GLOBAL $flattened
        $t0 = [gettimeofday];
        flatten_tree($huff_tree);
        $elapsed = tv_interval ( $t0 );
        print STDERR "flatten tree: $elapsed\n";

        $t0 = [gettimeofday];
        my $encoded_data = encode(\%codebook,\@data);
        $elapsed = tv_interval ( $t0 );
        print STDERR "encode data:  $elapsed\n";

        $t0 = [gettimeofday];
        print add_headers($flattened);
        $elapsed = tv_interval ( $t0 );
        print STDERR "adding headers:  $elapsed\n";
        print $encoded_data;

        $flattened = undef;
        %codebook = ();
        $counter++;
    }
}

sub add_headers {
    my $tree = shift;

    my $header;
    my ($byte1, $byte2);
    my $byte3 = 0;

    while ((length $tree) % 8 != 0) {
        $byte3++;
        $tree .= '0';
    }
    
    if (((length $tree) / 8) > 255) {
        $byte1 = 255;
        $byte2 = (length $tree)/8 - 255;
    } else {
        $byte1 = (length $tree)/8;
        $byte2 = 0;
    }

    $header .= chr $byte1;
    $header .= chr $byte2;
    $header .= chr $byte3;

    my $bitbuff;
    for my $bit (split //, $tree) {
        $bitbuff .= $bit;
        if (length $bitbuff > 7) {
            $bitbuff =~ s/^(\d{8})//;
            $header .= chr bin2dec($1);
        }
    }
    return $header;
}

sub flatten_tree {
    my $node = shift;
    
    #As the tree is traversed, if the node is not a leaf then a 0 is added and
    #the flatten function is called on the node to the left and the node
    #to the right.
    #If the node is a leaf node then a 1 is added and then the value of the
    #node. As there is the need for a end of chunk marker which is 9bits all the
    #values are stored as 0padded 9bit representations
    my $bitbuff;
    if (defined $node->{symbol}) {
        $flattened .= '1';
        if ($node->{symbol} =~ /100000000/) {
            $flattened .= $node->{symbol};
        } else {
            $flattened .= sprintf "%09b", ord $node->{symbol};
        }
    } else {
        $flattened .= '0';
        flatten_tree($node->{left},$flattened);
        flatten_tree($node->{right},$flattened);
    }
}

sub encode {
    my ($codebook,$data) = @_; 

    #Each byte is replaced by its code book replacement. When this value is
    #a byte or above the bytes value is stored.
    #Each chunk is marked with an eof
    my $encode;
    my $bitbuff;
    my $counter = 0;
    for my $byte (@$data) {
        $bitbuff .= $codebook->{$byte};
        if (length $bitbuff > 7) {
            $bitbuff =~ s/^(\d{8})//;
            $encode .= chr bin2dec($1);
        }
    }

    #pseudo eof
    $bitbuff .= $codebook->{100000000};

    while ((length $bitbuff) % 8 != 0) {
        $bitbuff .= '0';
        $counter++;
    }
    #print STDERR "\$counter: $counter\n";

    while (length $bitbuff > 0) {
        $bitbuff =~ s/^(\d{8})//;
        $encode .= chr bin2dec($1);
    }

    $encode = (chr($counter) . $encode);
    return $encode;
}


sub build_codebook {
    my $node = shift;

    if (defined $node->{left}) {
        $code .= '0';
        build_codebook($node->{left});
    }
    if (defined $node->{right}) {
        $code .= '1';
        build_codebook($node->{right});;
    }

    if (defined $node->{symbol}) {
        $codebook{$node->{symbol}} = $code;
    }
    $code =~ s/\d$//;
}

sub make_tree {
    my (%contents) = @_;
    
    #print STDERR Dumper \%contents;
    my @leaves;
    my $leaf;
    my @nodes;

    #hack for numerical sorting by value
    foreach my $code (sort { $contents{$a} <=> $contents{$b} } keys %contents) {
        my $leaf->{symbol} = $code;
        $leaf->{weight} = $contents{$code};
        push @leaves, $leaf;
    }
   
    #creates the intitial node from the first 2 leaves
    my $left = shift @leaves;
    my $right = shift @leaves;
    
    push @nodes, make_node($left, $right);

    my ($leaf1,$leaf2,$node1,$node2);

    while (scalar @leaves != 0 or scalar @nodes != 1) {

        $leaf1 = shift @leaves;
        $leaf2 = shift @leaves;
        $node1 = shift @nodes;
        $node2 = shift @nodes;

        if (not defined $leaf2 and not defined $node2) {
            push @nodes, make_node($leaf1,$node1);
            return $nodes[0] if scalar @nodes == 1;
        } 
        elsif (not defined $leaf1 and not defined $leaf2) {
            my $tmp = make_node($node1,$node2);
            push @nodes, $tmp; 
            my $length =  scalar @nodes;
            return $nodes[0] if $length == 1;
        }
        elsif (not defined $leaf2) {
            if ($leaf1->{weight} < $node2->{weight}) {
                push @nodes, make_node($node1, $leaf1);
                unshift @nodes, $node2;
            } else {
                push @nodes, make_node($node1, $node2);
                unshift @leaves, $leaf1;
            }
        }
        elsif (not defined $node2) {
            if ($node1->{weight} < $leaf2->{weight}) {
                push @nodes, make_node($leaf1, $node1);
                unshift @leaves, $leaf2;
            } else {
                push @nodes, make_node($leaf1, $leaf2);
                unshift @nodes, $node1;
            }
        }
        elsif ($leaf1->{weight} <= $node2->{weight} and $node1->{weight} <= $leaf2->{weight}) {
            push @nodes, make_node($leaf1,$node1);
            unshift @nodes, $node2;
            unshift @leaves, $leaf2;
        }
        elsif ($leaf1->{weight} < $node2->{weight}) {
            push @nodes, make_node($leaf1,$leaf2);
            unshift @nodes, $node2;
            unshift @nodes, $node1;
        }
        elsif ($node1->{weight} < $leaf2->{weight}) {
            push @nodes, make_node($node1,$node2);
            unshift @leaves, $leaf2;
            unshift @leaves, $leaf1;
        }

    }
}

sub make_node {
    my ($left, $right) = @_;

    my $node;
    $node->{left} = $left;
    $node->{right} = $right;
    $node->{weight} = $left->{weight} + $right->{weight};

    return $node;
}

sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}
