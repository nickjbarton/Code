package parse;
use strict;
use warnings;
use Exporter;

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( parseFile );

# these are exported by default.
our @EXPORT = qw( parseFile );

sub parseFile {


my $file_conf = shift(@_);
my $file_xml = shift(@_);
my @overridekvs = splice(@_); 
my $file_out = "";
my $line_number = "0";
my $error;
my %tab;
my @Output;

open(FILE_CONF, "< $file_conf") || die "Can't open $file_conf\n";
while(<FILE_CONF>) {
  my $line = $_;
  $line =~ s/(^\s*|\s*$|\n|\r)//g;
  if ( $line =~ /(.*?)(=)(.*)/ ) {
    %tab = (%tab, "$1", "$3");
  }

}
if (@overridekvs) {
  foreach (@overridekvs) {
    (my $newkey,my $newvalue)=split("=",$_);
    print "Adding $newkey=$newvalue\n";
    %tab = (%tab, "$newkey","$newvalue"); 
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

        } else {
          $key =~ /\$\{(.*?)$/g;
          if ( $tab{$1} ) {
             $line =~ s/\$\{($1)\}/$tab{$1}/;
          } 
            if ( $error ){
              $error="${error}line ${line_number} \$\{$1\} NOT updated because missing in ${file_conf}\n";
            }
          }
      }
      push(@Output,$line);
  }
    return @Output; 
}
