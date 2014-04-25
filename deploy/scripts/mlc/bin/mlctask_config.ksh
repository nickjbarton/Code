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
thishostname=$(hostname)
# Limit mlctask to servers 1 and 2
applist=$(egrep "^mlc\.app\.server\.[1|2]=$thishostname" $CONF | awk -F"=" '{print $1}' | awk -F"." '{ printf "%s ", $4 }')
for app in $applist
do
  MLCTASK=$(getProperty mlc.mlctask.home.directory.$app $CONF)
  MLCTASKLIVE=$MLCTASK/release/${RELEASE}
  if [[ ! -d $MLCTASKLIVE ]]
  then
    fatal "Invalid release directory"
  fi
  for file in $(find $MLCTASKLIVE -type f -name "*.template")
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
  done
  # Hardcode this as setENV.ksh is also run as the mlcload user
  chmod g+x $MLCTASKLIVE/etc/setENV.ksh
done
