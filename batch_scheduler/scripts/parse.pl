#!/usr/bin/perl
#
# Created by:   Nick Barton
#
# Description:  Utility to Replace ${VAR} from the "XML FILE", using value
#               from the "CONFIG FILE" and output in a file or screen. If the 
#               key is not present leave the variable in place. 
#
#
#
#
# Changes:
#      13/05/2013 - First version
#
#
#
 
 
use strict;
 
my $verbose = 0;
 
sub usage(){ 
  print "Usage: parse.pl <config file> <xml file> [<out file>]\n";
  exit;
}
 
if ( $#ARGV < 1 ) {
  usage();
}
 
my $file_conf = $ARGV[0];
my $file_xml = $ARGV[1];
my $file_out = "";
my $line_number = "0";
my $error;
 
if ( $#ARGV == 2 ) {
  $file_out = $ARGV[2];
  open ("FILE_OUT", ">$file_out");  
}
 
my %tab;
 
open(FILE_CONF, "< $file_conf") || die "Can't open $file_conf\n"; 
while(<FILE_CONF>) {
  my $line = $_;  
  $line =~ s/(^\s*|\s*$|\n|\r)//g;
  if ( $line =~ /(.*?)(=)(.*)/ ) {
    %tab = (%tab, "$1", "$3");
  }
 
}
 
open(FILE, "< $file_xml") || die "Can't open $file_xml\n";
 
while(<FILE>) {
      $line_number++;
      my $line = $_;
      while($line =~ /\$\{(.*?)\}/g) {
        my $key = $1;
        if ( $tab{$1} ) {
          $line =~ s/\$\{($1)\}/$tab{$1}/;
          if ( $verbose ) {
            print "line ${line_number} - updating $1 by $tab{$1}\n";
          }
          
        } else {
          $key =~ /\$\{(.*?)$/g;
          if ( $tab{$1} ) {
             $line =~ s/\$\{($1)\}/$tab{$1}/;
             if ( $verbose ) {
               print "line ${line_number} - updating $1 by $tab{$1}\n"; 
             }
          } else {

             if ( $verbose ) {
               print "line ${line_number} - NOT updating $1 by $tab{$1}\n";
             } 
          }
            if ( $error ){
              $error="${error}line ${line_number} \$\{$1\} NOT updated because missing in ${file_conf}\n";
            }
          } 
      }
      if ( $file_out ){
    print FILE_OUT "$line";
      } else {
        print $line;
      }
}
 
if ( $error ) {
  print "${error}\n#End of report\n";
}
 
close FILE_OUT;
