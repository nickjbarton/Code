#!usr/bin/ksh -a
#
# Common Functions
#

DIRNAME=$(dirname $0)
SCRIPTBIN=$(cd $DIRNAME;pwd) 
SCRIPTCFG=$(cd $SCRIPTBIN/../cfg;pwd) 
LOGDIR=$SCRIPTBIN/../log
[[ -d $LOGDIR ]] || mkdir $LOGDIR

SVNHOME="$HOME/svnkit"


getProperty() {
  key=$1
  file=$2

  value=$(perl $SCRIPTBIN/utils/getProperty.pl $file $key)
  echo $value
}

logIt () {
  type=$1
  shift
  message=$*
  date=$(date "+%Y/%m/%d %H:%M:%S")

  echo "$SCRIPT [$date] {$type} $message"
  [[ -n $LOGFILE ]] && echo "$SCRIPT [$date] {$type} $message" >> $LOGFILE
}

info() {
  logIt INFO $1
} 

warn() {
  logIt WARN $1
} 

fatal() {
  logIt FATAL $1
  exit 1
} 

svnco () {
   source=$1
   target=$2
   $SVNHOME/bin/jsvn co $source $target  
   if [[ $? -ne 0 ]]
   then
     fatal "Failed to checkout $source"
   fi
}
