#!/usr/bin/perl
#
# Created by:   Nick Barton
#
# Description:  Utility to extract value from an environment KV file. Any embedded keys in 
#               the value will also be resolved.
#
#
 
 
use strict;
 
my $verbose = 0;
 
sub usage(){ 
  print "Usage: getProperty.pl <config file> <property key>\n";
  exit;
}
 
if ( $#ARGV < 1 ) {
  usage();
}
 
my $file_conf = $ARGV[0];
my $key = $ARGV[1];
my $line_number = "0";
my $error;
 
my %tab;
 
open(FILE_CONF, "< $file_conf") || die "Can't open $file_conf\n"; 
while(<FILE_CONF>) {
  my $line = $_;  
  $line =~ s/(^\s*|\s*$|\n|\r)//g;
  if ( $line =~ /(.*?)(=)(.*)/ ) {
    %tab = (%tab, "$1", "$3");
  }
 
}
my $line = $tab{$key};
while($line =~ /\$\{(.*?)\}/g) {
   if ( $tab{$1} ) {
   $line =~ s/\$\{($1)\}/$tab{$1}/;
   }
}

print "$line" ;
