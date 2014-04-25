#!/usr/bin/ksh 
# 
# Draft script to manage mlc deployments
#
#
usage() {
echo ""
echo "Usage: mlcadmin -e <environment> -c <application> -a <action> [-r <release> ] [options]"
echo ""
echo "Where:  <app>       mlc"
echo "                    mlctask"
echo "                    mlcload"
echo "        <action>    stage 	- Create new release directory"
echo "                    config	- Configure new release with env specific content"
echo "                    release	- Release the configured new release"
echo "                    clean 	- Revert env specific content from provided target directory "
echo "                    rollback    - Repoint live to previous release "
echo "        <release>   		- release version"
}  

SCRIPT=$(basename $0)
DIRNAME=$(dirname $0)
SCRIPTBIN=$(cd $DIRNAME;pwd)
SCRIPTCFG=$(cd $SCRIPTBIN/../cfg;pwd)
SCRIPTUTILS=$(cd $SCRIPTBIN/utils;pwd)
CALLING_ARGS="$SCRIPT $*"
. $SCRIPTBIN/common.ksh

LOGFILE=$LOGDIR/${SCRIPT%.ksh}.log


while getopts ":e:c:a:r:b:dh" opt
do
    case $opt in
        e) EnvName=$OPTARG 
           ;;
        c) APP=$OPTARG 
           ;;
        a) ACTION=$OPTARG 
           ;;
        r) RELEASE=$OPTARG 
           ;;
        b) BRANCH="$OPTARG"
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
# Loops through the list of actions

for action in $(echo $ACTION | sed 's/,/ /g')
do
  case $action in
    stage)
       if [[ -n $RELEASE ]]
       then
         ARGS=release:$RELEASE 
       elif [[ -n $BRANCH ]]
       then
         ARGS=branch:$BRANCH
       else
         fatal "You need to specify either the branch or release"
       fi
     info "running ${APP}_${action}.ksh $ARGS"
     $SCRIPTBIN/${APP}_${action}.ksh $EnvName $ARGS
    ;;
    config|release|rollback|clean)
     info "running ${APP}_${action}.ksh $ARGS"
     $SCRIPTBIN/${APP}_${action}.ksh $EnvName $RELEASE
    ;;
    *)
      usage
      fatal "not a valid action: $ACTION"
    ;;
  esac
done
