#!/usr/bin/perl

use POSIX qw(strftime);
use Time::Local;
use File::Basename;
use Sys::Hostname; 
use Getopt::Long;
use Switch;
use parse;

my $ignoretimes=0;
my $commandline = join " ", $0, @ARGV;
GetOptions ('usage|help|?' => \&usage,
            'debug!' => \$debug,
            'schedule=s' => \$schedFile,
            'envFile=s' => \$envFile,
            'action=s' => \$action,
            'options:s' => \$options, 
            'variables:s' => \$variables, 
            'jobid=i' => \$jobid, 
            'assumetime=s' => \$assumetime, 
            'ignoretimes!' => \$ignoretimes 
			'continueonerror!' => \$continueonerror );

print ("DEBUG: Command line options:
        schedule=$schedFile
        envFile=$envFile
        options=$options
        variables=$variables
        jobid=$jobid
        assumetime=$assumetime
        ignoretimes=$ignoretimes\n
		continueonerror=$continueonerror") if ($debug);



switch ($action){
 case(run) {
    if ( !-e $envFile || $schedFile eq '' ) {
      print "USAGE: You must provide a valid environment config file and a schedule file when action=run\n"; 
      &usage;
    } 
 }
 case(restart) { 
   if ($jobid eq '') {
      print "USAGE: You must provide a jobid when restarting a job\n";
      &usage;
   } 
 }
 else { 
   print "USAGE: You must provide an action to perform\n";
   &usage; 
 }
}

my $q=0;
my $j=0;
our %Queue;
my $id;
my $scheddep;
my $schedtime;
my $jobdir="jobs";
my $nowstart = time;

sub usage {
  print "usage:\n";
  print "./sched.pl --action=run --schedule={schedule file} --envFile={environment file} [--ignoretimes] [--assumetime=HH:MM] [--variables=var.name.1=VAR1,var.name.2=VAR2]\n";
  print "./sched.pl --action=restart --jobid={jobid} [--ignoretimes] [--options=[failed={complete|torun},running={complete|torun}]]\n\n";
  print "\t--assumetime=HH:MM\t\t Specify the time (HH:MM) that the scheduler should use as the 'starttime' of the schedule.\n";
  print "\t--action=ACTION\t\t Specify the ACTION the scheduler should take: run or restart.\n";
  print "\t--envFile=FILE\t\t Specify the environment file (FILE) to use to parse the schedule for environment specific commands.\n";
  print "\t--ignoretimes\t\t Ignore the time dependencies in the schedule when running.\n";
  print "\t--jobid=ID\t\t Specify the jobid (ID) - (only for --action=restart).\n";
  print "\t\t\t\t\t The script will look in jobs/\$jobid/current_status for the last known state of the schedule and\n";
  print "\t\t\t\t\t will use the timestamp contained in jobs/\$jobid/now as the start time of the schedule when\n";
  print "\t\t\t\t\t calculating the schedule time dependencies.\n";
  print "\t--options=OPTIONS\t Specify the OPTIONS to use when restarting a failed job.(only for --action=restart).\n";
  print "\t\t\t\t Valid options are:\n";
  print "\t\t\t\t\t failed=complete or failed=torun\n";
  print "\t\t\t\t\t running=complete or running=torun\n";
  print "\t\t\t\t these will cause the script to mark the command that failed, or was still running when the system died,\n";
  print "\t\t\t\t as complete or schedule it to rerun.\n";
  print "\t--schedule=FILE\t\t Specify the schedule file (FILE) to use. (only for --action=run).\n";
  print "\t--variables=var.name=VAR Specify a comma seperated list of Key=Values to be used when parsing schedules or scripts.\n";
  print "\n";

  exit 0;
}

sub newjob {
  # Checks for and creates an numerically incrementing directory
  if ( ! -e $jobdir ) {
    mkdir $jobdir or die;
  }

  opendir(DIR, $jobdir) or die $!;
  while (my $file = readdir(DIR)) {
    if ($file =~ m/^[0-9]*/) {
      push(@jobs,$file);
    }
  }
  closedir(DIR);

  @jobs = sort {$b <=> $a} @jobs;
  $jobnum=$jobs[0] + 1 ;
  $newdirname="$jobdir/$jobnum";
  mkdir $newdirname;
  return $jobnum;
}

sub getTimeStart {
  # Accepts $time - The time of the schedule
  #         $now  - the time now (incluing any offset)
  # Assumes + 1 day if $time is less than now
  # Returns schedule time since epoch
  use constant ONE_DAY => 24 * 60 * 60;
  my $time=$_[0];
  my $now=$_[1];
  my $runtime;
  # First split the schedule time into hours and mins
  (my $schedhour, my $schedmin) = split(":",$time);

  # Get now back into hours mins secs etc
  (my $sec,my $min,my $hour,my $mday,my $mon,my $year) = localtime($now);

  # Have a go at setting the schedule time (since epoch) as today + schedule hours and mins
  my $testschedtime = timelocal((0,$schedmin,$schedhour,$mday,$mon,$year));
  # Simply see if the testschedule time is less than now, if it is add one day in seconds
  if ($testschedtime < $now ) {
    $runtime = $testschedtime + ONE_DAY;
  } else {
    $runtime = $testschedtime;
  }
  return $runtime;
}

sub interupt {
  # Handle interupts - treat like a failure
  # Loop until all jobs are complete
  $SIG{'INT' } = sub { die };
  logit("An interupt has been received, check if jobs are running",$logfile,"ERROR");
  while (true) {
    $jobstatus=check_running;
    $failed=true;
  
    if ($jobstatus eq "complete") {
      logit("All jobs complete",$logfile,"INFO");
      display_status;
      exit 0;
    }
    logit("We have failed jobs, waiting for runs to complete",$logfile,"ERROR");
    $jobstatus=&check_running;
    if ($jobstatus ne "running" ) {
      logit("We have waited for all the jobs to complete",$logfile,"ERROR");
      write_status($statusfile);
      display_status;
      exit 1
    }
    &iterate_schedule; 
    sleep 5;
  }
}

sub GetRunSched {
  # This fuction produces the full batch schedule from $schedFile
  # It initiates the parsing of files for environment specific details
  # and returns a hash of arrays containing ALL job schedule information
  my $schedFile=$_[0];
  my $envFile=$_[1];
  my $id;
  my %Queue;
  my $scheddep;
  my $schedtime;
  my $dependency;
  my $status;
  my $j=0;
  my $schedDir = dirname($schedFile); 
  my $thishost = hostname; 
  my $thisuser = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);

  open(my $schedfh, "<", "$schedFile") or die "Can't open $schedFile";
  while (<$schedfh>) {
     my @scripts;
     $_ =~ s/\n|\s+,|\s+$//g;
     (my $id, my $scheddep , my $schedtime , my $schedule) = split(",",$_);

     if ( $scheddep ne "-" ) {
       print "DEBUG: $schedule has dependency : $scheddep\n" if ($debug);
       $dependency = "";
       foreach $tmp (split("\\|",$scheddep)) {
         print "DEBUG: processing dependency: $tmp\n" if ($debug);
         $dependency = $dependency . "|" . $deps{$tmp};  
         print "DEBUG: $tmp maps to $deps{$tmp}\n" if ($debug);
       }
       $dependency =~ s/^\|//g;
       print "DEBUG: dependency is $dependency\n" if ($debug);
     } else {
       $dependency = $scheddep; 
     }
     print "processing $schedule \n";
     $j=0;
     @overridekvs=split(",",$variables);
     push(@overridekvs,'env.file.name=' . $envFile);
     print "DEBUG: Calling parse.pm with the parameters $envFile, $schedDir  /  $schedule\n" if  ($debug);
     my @scripts=&parseFile($envFile,$schedDir . "/" . $schedule,@overridekvs);
     foreach (@scripts) {
        next if ( $_ =~ /^#/);
        print "DEBUG: processing line $_\n" if ($debug);
        # if its the first job of the scheule, then this needs the external dependency
        # if not then set to the previous job
        ($cmdtime, $user, $host, $command) = split(",",$_);
        if ( $user eq $thisuser && $host eq $thishost ) {
          $thescript = $command;
        } else {  
          $thescript="ssh $user\@$host $command";
        }
        if ( $j != 0 ) { 
          $dependency = $q - 1;
          $status = "wait";
          $schedtime = $cmdtime;
        } elsif ( $dependency == "-" ) {
          $status = "torun"; 
        } else {
          $status = "wait";
        }
        $thescript =~ s/\n|\s+,|\s+$//g;
        print "DEBUG: adding to schedule: $schedule, $schedtime, $dependency, $status, $thescript" if ($debug);
        $Queue{$q}=[ $schedule, $schedtime, $dependency, $status, $thescript] ; 
        $last=$q;
        $q++;
        $j++;
    }
    $deps{$id}=$last; 
  } 
  close($schedfh);
  return %Queue; 
}


sub check_running {
  # Check if we still have jobs to run
    $jobstatus = "checking";
    STATUS:for $key ( sort {$a<=>$b} keys %Queue ) {
      print ("DEBUG: " . ${Queue{$key}}[4]," is ", ${Queue{$key}}[3], " \n") if ($debug);
      if ( ${Queue{$key}}[3] eq "running" || ${Queue{$key}}[3] eq "scheduled" || ${Queue{$key}}[3] eq "torun" ) {
        $jobstatus = "running";
        last STATUS;
      }
    }
    if ( $jobstatus eq "checking" ) {
      return "complete";
    } else {
      return "running";
    }
}

sub write_status {
  # Commit the current status to disk (in case a restart is necessary)
  $file=$_[0];
  if ($file ne "" ) {
    open($statusfh, ">", $file) or die "Can't open $file\n"; 
    for $key ( sort {$a<=>$b} keys %Queue ) {
    ($runschedule, $runtimedep, $rundep, $runstatus, $command) = @{$Queue{$key}};
     print $statusfh "$key,$runschedule,$runtimedep,$rundep,$runstatus,$command\n";
    }
    close ($statusfh);
  }
}

sub logit {
  $message=$_[0];
  $logfile=$_[1];
  $type=$_[2];
  $type =~ tr/a-z/A-Z/;
  $message =~ s/\n//g;
  ($sec,$min,$hour,$mday,$mon,$year) = localtime;
  $mon=$mon + 1;
  $year=$year + 1900;
  open($logfh, ">>", $logfile) or die "Can't open $logfile";
  printf $logfh ("%02d/%02d/%d %02d:%02d:%02d [%s] %s\n", $mday,$mon,$year,$hour,$min,$sec,$type,$_[0]);
  printf ("%02d/%02d/%d %02d:%02d:%02d [%s] %s\n", $mday,$mon,$year,$hour,$min,$sec,$type,$_[0]) if ($debug || $type eq "ERROR");
  close($logfh);
}

sub display_status {
    for $key ( sort {$a<=>$b} keys %Queue ) {
    ($runschedule, $runtimedep, $rundep, $runstatus, $command, $thepid) = @{$Queue{$key}};
    $string="$key,$runschedule,$runtimedep,$rundep,$runstatus,$command,$thepid";
    $string =~ s/,$//g;
    print  "$string\n";
    }

}

sub iterate_schedule {
  # Iterate through all the jobs in the schedule
  for $key ( sort {$a<=>$b} keys %Queue ) {
    ($runschedule, $runtimedep, $rundep, $runstatus, $command , $cmdpid) = @{$Queue{$key}};

    # Run any commands that are set to torun, unless we have a failure to contend with
    if ( $runstatus eq "torun" || $runstatus eq "scheduled" && ! $failed  ) {
       if ( $runtimedep ne "-" && $ignoretimes ne 1 ) {
	    print "DEBUG: Checking time dependency ($runtimedep)\n" if ($debug);
            $starttime=&getTimeStart($runtimedep,$nowstart);
            # if we simulate a different start time offset will be non zero
            $actualnow = time - $offset;
            (my $sec,my $min,my $hour,my $mday,my $mon,my $year) = localtime($actualnow);
            print "Assumed time is $hour:$min\n" if ($debug && $assumetime);
            if ( $actualnow < $starttime) {
	        print "DEBUG: Time dependency ($runtimedep) not met - next;\n" if ($debug);
                logit("Waiting until $runtimedep for $command",$logfile,"INFO");
                ${Queue{$key}}[3] = "scheduled";
                &write_status($statusfile); 
                next;
            }
       } 
       $command =~ s/\$\{.*}//g;
       logit("running $command",$logfile,"INFO");
       @cmd = split(" ",$command); 
       $script=$cmd[0];
       if ( $script =~ /.template$/ ) {
         $script =~ s/.template$//g;
         open($newscriptfh, ">", $script) or die; 
         print "DEBUG: Calling parse.pm with the parameters $envFile, $cmd[0]\n" if  ($debug);
         @newfilecontent=&parseFile($envFile,$cmd[0]);
         foreach $line (@newfilecontent) {
            print $newscriptfh "$line"; 
         }
         close($newscriptfh);
         system("chmod +x $script");
         $cmd[0]=$script;
       }

       # Here we fork a new process, run the command and record the pid
       my $pid = fork();
       if ($pid == -1) {
         die "Failed to fork process $command";
       } elsif ($pid == 0) {
         exec @cmd,$p or die "failed to fork command";
       }
       ${Queue{$key}}[3] = "running";
       ${Queue{$key}}[5] = $pid;
    } elsif ($runstatus eq "wait") {
         print "DEBUG: $command status is wait. Checking dependencies....\n"  if ($debug);
         if ( $rundep ne "-" ) {
            print "DEBUG: There are dependencies\n" if ($debug);
            @deps = split("\\|", $rundep); 
            $ready = "ready"; 
            DEPS:foreach $dep ( @deps ) { 
              $depstatus=${Queue{$dep}}[3];  
              print "DEBUG: Checking on dependency $dep. Status is $depstatus\n" if ($debug);
              if ( $depstatus ne "complete" ) {
                  $ready = "notready";
                  last DEPS; 
                }
            } 
            print "DEBUG: The status of this job is $ready\n" if ($debug);
            if ( $ready eq "ready" && ! $failed ) {
               ${Queue{$key}}[3] = "torun"; 
            }
         } else {
           print "DEBUG: No dependencies, setting to run\n" if ($debug);
           ${Queue{$key}}[3] = "torun";
         }
    } elsif ($runstatus eq "running" ) {
      my $runpid;
      my $procs;
	  # Here we check to see if the process is complete (it should be defunct if its completed)
      $runpid = ${Queue{$key}}[5];
      $procs = `/usr/bin/ps -p $runpid | grep -v "defunct" |wc -l `;
      $procs =~ s/ |\n//g;
      if ($procs == 1 ) {
        logit("$command has completed, checking return code",$logfile,"INFO");
        # Waitpid terminates the fork grabs the return code
        waitpid($runpid,0);
        $rc = $?;
        if ( $rc != 0 && $continueonerror ne 1 ) { 
          logit("Failed to execute $command (rc=$rc)",$logfile,"ERROR");
          ${Queue{$key}}[3]="failed";
          $failed=true;
          return;
        }
        ${Queue{$key}}[3]="complete"; 
      }
    }
    &write_status($statusfile)
  }
}

#Main section

if ( $action eq "restart" ) {
  # We are restarting a schedule, so we do things a bit differently
  $replacefailed="complete";
  $replacerunning="torun";
  @opts=split("," ,$options);
  # First, find out what to do with jobs that have failed or were still running 
  foreach $flag ( @opts ) {
    ($key, $value) = split("=",$flag);  
    if ( $key eq "failed" ) {
      $replacefailed=$value; 
    } elsif ( $key eq "running" ) {
      $replacerunning = $value;
    }
  }
  # Read the last status (current_status) and reset failed an running flags
  $schedFile="$jobdir/$jobid/current_status"; 
  $nowFile="$jobdir/$jobid/now"; 
  open (my $nowfh, "<", "$nowFile") or die "Can't open $nowFile";
  $nowstart=readline($nowfh);
  open(my $schedfh, "<", "$schedFile") or die "Can't open $schedFile";
  $logfile="$jobdir/$jobid/schedule.log";
  logit("Job restart called with the following options:",$logfile,"INFO");
  logit("options=$options",$logfile,"INFO");
  logit("jobid=$jobid",$logfile,"INFO");
  logit("ignoretimes=$ignoretimes",$logfile,"INFO");

  while (<$schedfh>) {
    $line=$_;
    $line =~ s/\n//g;
    # 
    $line =~ s/running/$replacerunning/g;
    $line =~ s/failed/$replacefailed/g;
    ($id, $runschedule, $runtimedep, $rundep, $runstatus, $command) = split(",",$line);
    $Queue{$id}=[$runschedule, $runtimedep, $rundep, $runstatus, $command];
  }
  close($schedfh);
  &display_status;
} else {
  # We are running a new schedule so create a new run queue, create new job directory fo status and output
  %Queue = &GetRunSched($schedFile,$envFile);
  $jobid = &newjob;
  $nowfile="$jobdir/$jobid/now";
  open(my $nowfh, ">", "$nowfile") or die "Can't open $nowfile\n";
  print $nowfh "$nowstart";
  close($nowfh);
  $startschedule="$jobdir/$jobid/starting_status";
  print "JOB:$jobid Running the following schedule\n";
  &display_status;
  &write_status($startschedule);
}

if ($assumetime) {
  # Sets the start time to the assumetime and calculates an offset
  (my $newhour, my $newmin) = split(":",$assumetime);
  (my $sec,my $min,my $hour,my $mday,my $mon,my $year) = localtime($nowstart);
  my $newtime = timelocal((0,$newmin,$newhour,$mday,$mon,$year));
  # We have the new time since epoch, so calculate the offset and set start time to the new time
  $offset=$nowstart - $newtime;
  my $nowstart = $newtime;
  (my $sec,my $min,my $hour,my $mday,my $mon,my $year) = localtime($nowstart);
  printf("%s %2d:%2d %2d/%2d/%4d %s\n", "Assumed start time is ", $hour,$min,$mday,$mon,$year + 1900 ," and offset is $offset") if ($debug);
  
}

$logfile="$jobdir/$jobid/schedule.log";
$statusfile="$jobdir/$jobid/current_status";
logit($commandline,$logfile,"INFO");
my $r = 0;
my %run;
my $failed;

print "Sleeping for 30 seconds, in case you change your mind\n";
sleep 30;

# Trap interupts and call the interupt function (unless we are debugging)
$SIG{'INT' } = 'interupt';#  unless ($debug);

while ( true ) {

  # Checking status
  if ( $r > 0 && ! $failed ) {
    $jobstatus=&check_running;
    if ($jobstatus eq "complete") {
      logit("All jobs complete",$logfile,"INFO");
      exit 0;
    }
  }

  if ($failed) {
    logit("We have failed jobs, waiting for runs to complete",$logfile,"ERROR");
    $jobstatus=&check_running;
    if ($jobstatus ne "running" ) {
      logit("We have waited for all the jobs to complete",$logfile,"ERROR");
      write_status($statusfile);
      exit 1 
    }
  }
  # We have got through the status check, now loop through the queue and process jobs
  logit("Entering run $jobid iteration $r",$logfile,"INFO");
  &iterate_schedule;
  logit("Completing run $jobid iteration $r",$logfile,"INFO");
  # Catch any fails that may have slipped through the net.
  # Adjust the sleep time depening on the state of the jobs
  for $key ( sort {$a<=>$b} keys %Queue ) {
        $sleep = 30;
        ($runschedule, $runtimedep, $rundep, $runstatus, $command) = @{$Queue{$key}};
        logit("$key,$runschedule,$runtimedep,$rundep,$runstatus,$command",$logfile,"INFO");
        if ( $runstatus eq failed ) { 
           $failed=true;
           $sleep=10; 
           last;
        }
        if ( $runstatus eq "torun" || $runstatus eq "running" && $sleep > 20) {
          $sleep=20; 
        }
      }
  sleep $sleep;
  $r++; 
  print "." if (!$debug);
  # End of loop
}
