#!/usr/bin/ksh
#
# Script to release a new version of mlctask 
# For MLCTASK the rollback is the same as a release
#

# Standard Script Environment SetUp
#
SCRIPT=$(basename $0)
DIRNAME=$(dirname $0)
SCRIPTBIN=$(cd $DIRNAME;pwd)
SCRIPTCFG=$(cd $SCRIPTBIN/../cfg;pwd)
SCRIPTUTILS=$(cd $SCRIPTBIN/utils;pwd)

. $SCRIPTBIN/common.ksh

LOGFILE=$LOGDIR/${SCRIPT%.ksh}.log

#
EnvName=$1
RELEASE=$2
if [[ -z $2 ]]
then
 fatal "You must provide the environment name and release identifier"
fi
CONF=$SCRIPTCFG/${EnvName}.kv


# Work out what app servers are installed on this server
thishostname=$(hostname)
applist=$(egrep "^mlc\.app\.server\.[1|2]=$thishostname" $CONF | awk -F"=" '{print $1}' | awk -F"." '{ printf "%s ", $4 }')
# Loop around the instance that should be on this server
for app in $applist
do
    MLCTASK=$(getProperty mlc.mlctask.home.directory.$app $CONF)
    MLCSHARED=$MLCTASK/shared
    MLCTASKTARGET=$MLCTASK/release/${RELEASE}
    MLCTASKLIVE=$MLCTASK/live

    if [[ ! -d $MLCTASKTARGET ]]
    then
      fatal "Invalid release directory: $MLCTASKTARGET"
    fi
    
    if [[ ! -L  $MLCTASKLIVE ]]
    then
      if [[ -a $MLCTASKLIVE ]] 
      then
        info "Previous release was not deployed with a symbolic link"
        info "Moving live to release directory $MLCTASK/release/pre_$RELEASE"
        mv $MLCTASKLIVE $MLCTASK/release/pre_$RELEASE 
      else
        info "No previous release deployed"
      fi
    else
      link_target=$(ls -ld $MLCTASKLIVE | awk ' { printf "%s\n",$NF }')
      info "removing link from: $MLCTASKLIVE to: $link_target"
      rm $MLCTASKLIVE
    fi
    
    info "linking $MLCTASKTARGET to $MLCTASKLIVE"
    ln -s $MLCTASKTARGET $MLCTASKLIVE
    if [[ "$app" -eq 2 ]] && [[ ! -d $MLCTASK/report_flags ]] 
    then
       mkdir $MLCTASK/report_flags
    fi
    if [[ ! -d $MLCSHARED ]] || [[ ! -d $MLCSHARED/logs ]] || [[ ! -d $MLCSHARED/logs/latest ]]
    then
      info "creating directory $MLCSHARED/logs/latest"
      mkdir -p $MLCSHARED/logs/latest
    fi
done
