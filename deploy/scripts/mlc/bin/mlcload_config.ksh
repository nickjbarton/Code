#!/usr/bin/ksh 
#
# Script to configure the mlctask suite of scripts
# 
SCRIPT=$(basename $0)
DIRNAME=$(dirname $0)
SCRIPTBIN=$(cd $DIRNAME;pwd)
SCRIPTCFG=$(cd $SCRIPTBIN/../cfg;pwd)
SCRIPTUTILS=$(cd $SCRIPTBIN/utils;pwd)

. $SCRIPTBIN/common.ksh

LOGFILE=$LOGDIR/${SCRIPT%.ksh}.log

EnvName=$1
RELEASE=$2
if [[ -z $2 ]]
then
 fatal "You must provide the environment name and release identifier"
fi
CONF=${SCRIPTCFG}/${EnvName}.kv

# Work out what app servers are installed on this server
MLCLOAD=$(getProperty mlc.mlcload.home.directory $CONF)
MLCLOADLIVE=$MLCLOAD/release/${RELEASE}
if [[ ! -d $MLCLOADLIVE ]]
then
  fatal "Invalid release directory"
fi
for file in $(find $MLCLOADLIVE -type f -name "*.template")
do
      typeset SOURCE=$file
      typeset TARGET=$(echo $file | sed 's/\.template$//g;s/\/templates\//\//g')
      info "parsing $(basename $SOURCE) to $(basename $TARGET)"
      echo perl $SCRIPTUTILS/parse.pl $CONF $SOURCE $TARGET 
      perl $SCRIPTUTILS/parse.pl $CONF $SOURCE $TARGET && info "$(basename $TARGET) complete"
      if [[ "${TARGET##*\.}" = "ksh" ]]
      then
        chmod 744 $TARGET 
      fi
	  if [[ "$(basename $TARGET)" = "monitor" ]]
	  then
	    chmod 755 $TARGET
	  fi
done
