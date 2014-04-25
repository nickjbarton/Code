#!/usr/bin/ksh 
# 
# Draft script to manage mlc deployments
#
#
usage() {
echo ""
echo "Usage: mlcdeploy -e <environment> -c <application> -a <action> -s <source>  [options]"
echo ""
echo "Where:  <app>       mlc"
echo "                    mlctask"
echo "                    mlcload"
echo "        <actions>   stage 	- Create new release directory"
echo "                    config	- Configure new release with env specific content"
echo "                    release	- Release the configured new release"
echo "                    clean 	- Revert env specific content from provided target directory "
echo "                    rollback      - Repoint live to previous release "
echo "        <release>   		- release version"
}  

SCRIPT=$(basename $0)
DIRNAME=$(dirname $0)
SCRIPTBIN=$(cd $DIRNAME;pwd)
SCRIPTUTILS=$(cd $SCRIPTBIN/utils;pwd)
CALLING_ARGS="$SCRIPT $*"
. $SCRIPTBIN/common.ksh

LOGFILE=$LOGDIR/${SCRIPT%.ksh}.log


while getopts ":e:c:a:s:r:dh" opt
do
    case $opt in
        e) EnvName=$OPTARG 
           ;;
        c) APP=$OPTARG 
           ;;
        a) ACTION=$OPTARG 
           ;;
        s) SOURCEDIR=$OPTARG 
           ;;
        r) RELEASE=$OPTARG 
           ;;
        d) DEBUG="true"
           ;;
        h) usage
           ;;
        *) usage 
           fatal "Invalid argument: $opt";;
    esac
done
shift $(($OPTIND - 1))


if [[ -z "$ACTION" ]] || [[ -z EnvName ]]
then
  usage
  fatal "Incorrect syntax : $CALLING_ARGS"
fi

# First workout what we are deploying and the scripts that need to be run
# ToDo: Could we derive this from the env name?
case $APP in
  mlc|mlctask|mlcload)
     APPSUITE="mlc"
     APPSCRIPT="mlcadmin.ksh"
     ;;
  *)
     fatal "Invalid Application"
     ;;
esac

# Set environment file
CONFDIR=$(cd ${SCRIPTBIN}/../envs/${APPSUITE};pwd)
CONF=${CONFDIR}/${EnvName}.kv
if [[ ! -f $CONF ]]
then
  fatal "Failed to find configuration file - $CONF"
fi

for action in $(echo $ACTION | sed 's/,/ /g')
do
  case $action in
    deploy)
      info "Script will $action $APP"
      DODEPLOY=true
    ;;
    config)
      info "Script will $action $APP"
      DOCONFIG=true
    ;;
    release)
      info "Script will $action $APP"
      DORELEASE=true
    ;;
    rollback)
     info "Script will $action $APP"
     ROLLBACK=true
    ;;
    *)
      usage
      fatal "not a valid action: $ACTION"
    ;;
  esac
done

TARGETUSER=$(getProperty ${APPSUITE}.${APP}.unix.user $CONF)
DEPLOYINSTALLDIR=/home/$TARGETUSER/${EnvName}_Auto

# Get the artifacts to the target location
# Assuming naming convention  <app suite>_<component>_
APP1SERVER=$(getProperty mlc.app.server.1 $CONF)
APP2SERVER=$(getProperty mlc.app.server.2 $CONF)
case $APP in
      mlctask)
         APP1DIR=$(getProperty mlc.mlctask.home.directory.1 $CONF)
         APP2DIR=$(getProperty mlc.mlctask.home.directory.2 $CONF)
         if [[ $APP1SERVER = $APP2SERVER ]] || [[ $APP2SERVER = "" ]]
         then
           SERVERLIST=$APP1SERVER
         else
           SERVERLIST=$APP1SERVER,$APP2SERVER
         fi
         SRCTARGETLIST="${SOURCEDIR-.}/mlcap1/*:$APP1SERVER:$APP1DIR/release/$RELEASE ${SOURCEDIR-.}/mlcap2/*:$APP2SERVER:$APP2DIR/release/$RELEASE"
      ;;
      *)
         SERVERLIST=$APP1SERVER
         APPDIR=$(getProperty mlc.${APP}.home.directory $CONF)
         SRCTARGETLIST="${SOURCEDIR-.}/${APPSUITE}_${APP}/*:$APP1SERVER:$APPDIR/release/$RELEASE" 
      ;;
esac


if [[ $DODEPLOY = "true" ]]
then
  # Deployment section of code 

  # Push deployment scripts
  for target in $(echo $SERVERLIST | sed 's/,/ /g')
  do
    info "Pushing out deployment scripts"
    ssh -o "StrictHostKeyChecking=no" $TARGETUSER@$target "[[ -d $DEPLOYINSTALLDIR ]] || mkdir -p $DEPLOYINSTALLDIR"
    if [[ $? -ne 0 ]]
    then
        fatal "Failed to establish ssh connection to $TARGETUSER@$target or failed to make directory $DEPLOYINSTALLDIR"
    fi
    ssh -o "StrictHostKeyChecking=no" $TARGETUSER@$target "[[ -d $DEPLOYINSTALLDIR/cfg ]] || mkdir -p $DEPLOYINSTALLDIR/cfg"
    if [[ $? -ne 0 ]]
    then
        fatal "Failed to establish ssh connection to $TARGETUSER@$target or failed to make directory $DEPLOYINSTALLDIR/cfg"
    fi
    scp -pr ${SOURCEDIR-.}/mlc/bin $TARGETUSER@$target:$DEPLOYINSTALLDIR/
    if [[ $? -ne 0 ]]
    then
        fatal "Failed to copy deployment scripts to target server"
    fi
    scp -pr ${CONFDIR}/* $TARGETUSER@$target:$DEPLOYINSTALLDIR/cfg/
    if [[ $? -ne 0 ]]
    then
        fatal "Failed to copy configuration files to target server"
    fi
  done
  


  for srctarget in $SRCTARGETLIST
  do
      targetserversdir=${srctarget#*:} 
      targetlistcomma=${targetserversdir%%:*}
      targetdir=${targetserversdir##*:}
      targetlist=$(echo $targetlistcomma | sed 's/,/ /g')
      src=${srctarget%%:*}

      for target in $targetlist
      do 
         info "Executing ssh $TARGETUSER@$target [[ -d $targetdir ]] || mkdir -p $targetdir"
         ssh $TARGETUSER@$target "[[ -d "$targetdir" ]] || mkdir -p $targetdir"
         if [[ $? -ne 0 ]] 
         then
            fatal "Failed to establish ssh connection to $TARGETUSER@$target or failed to make directory $targetdir"
         fi
         info "Executing rsyncFiles to $TARGETUSER@$target:$targetdir/"
         rsyncFiles "$src" $TARGETUSER@$target:$targetdir/
         info "Deployment of $APP - $src complete to $TARGETUSER@$target:$targetdir"
      done
  done 
  info "Deployment of $APP release: $RELEASE complete"
fi

if [[ $DOCONFIG = "true" ]]
then
  for server in $(echo $SERVERLIST | sed 's/,/ /g')
  do
    info "Running configuration of $APP - release: $RELEASE on $server"
    ssh $TARGETUSER@$server "$DEPLOYINSTALLDIR/bin/$APPSCRIPT -e ${EnvName} -c $APP -a config -r $RELEASE"    
    if [[ $? -eq 0 ]]
    then
      info "$APP configuration complete on $server"
    else
      fatal "Failed to run configuration of $APP"
    fi
  done
fi

if [[ $DORELEASE = "true" ]]
then
  for server in $(echo $SERVERLIST | sed 's/,/ /g')
  do
    info "Running release of $APP - release: $RELEASE on $server"
    ssh $TARGETUSER@$server "$DEPLOYINSTALLDIR/bin/$APPSCRIPT -e ${EnvName} -c $APP -a release -r $RELEASE"    
    if [[ $? -eq 0 ]]
    then
      info "$APP release complete on $server"
    else
      fatal "Failed to run release of $APP: $RELEASE"
    fi
  done
fi

