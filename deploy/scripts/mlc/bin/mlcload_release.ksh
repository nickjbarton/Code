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


MLCLOAD=$(getProperty mlc.mlcload.home.directory $CONF)
MLCLOADTARGET=$MLCLOAD/release/${RELEASE}
MLCLOADLIVE=$MLCLOAD/live

if [[ ! -d $MLCLOADTARGET ]]
then
      fatal "Invalid release directory: $MLCLOADTARGET"
fi
    
if [[ ! -L  $MLCLOADLIVE ]]
then
      if [[ -a $MLCLOADLIVE ]] 
      then
        info "Previous release was not deployed with a symbolic link"
        info "Moving live to release directory $MLCLOAD/release/pre_$RELEASE"
        mv $MLCLOADLIVE $MLCLOAD/release/pre_$RELEASE 
      else
        info "No previous release deployed"
      fi
else
      link_target=$(ls -ld $MLCLOADLIVE | awk ' { printf "%s\n",$NF }')
      info "removing link from: $MLCLOADLIVE to: $link_target"
      rm $MLCLOADLIVE
fi
    
info "linking $MLCLOADTARGET to $MLCLOADLIVE"
ln -s $MLCLOADTARGET $MLCLOADLIVE
