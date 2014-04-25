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


while getopts ":e:c:a:s:r:dp:h" opt
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
        p) PARSEENV=$OPTARG
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
  mlcbase|mlcscripts|mlcconfig)
     APPSUITE="mlc"
     APPSCRIPT="mlcadmin.ksh"
     ;;
  *)
     fatal "Invalid Application"
     ;;
esac

# Set environment file
CONFDIR=$(cd ${SCRIPTBIN}/../envs/${APPSUITE};pwd)
BASEDIR=$(cd ${SCRIPTBIN}/..;pwd)
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

TARGETUSER=$(getProperty mlc.app.base.unix.user $CONF)
DEPLOYINSTALLDIR=/home/$TARGETUSER
TARGETDIR=$(getProperty mlc.app.base.directory $CONF)/mlc/$(getProperty mlc.env.name $CONF)
BACKUPDIR=$(getProperty mlc.app.base.directory $CONF)/mlc/TeamCityBackup/$(getProperty mlc.env.name $CONF)_${APP}_${RELEASE}_$(date '+%Y%m%d%H%M%S')

RSYNC=~/utils/rsync
# Introducing the -c option to use checksums only to detect changes. This will reduce the changes picked up because
# the templating process updates the time stamps.
RSYNC_OPTIONS="-p -c -av  --rsync-path=~/utils/rsync"
# Backup all changes
RSYNC_BACKUP="-b --backup-dir=${BACKUPDIR}"
RSYNC_EXCLUDES="--exclude=*/.svn --exclude=*\.template"

if [[ $DODEPLOY = "true" ]]
then
    info "Starting deployment section of script"
    servers=$(nawk -F= '$1 ~ /mlc\.app\.server\./ { print $2 }' $CONF | sort -u )
    for server in ${servers}
    do
      ssh -o "StrictHostKeyChecking=no" $TARGETUSER@${server} true
      if [[ $? -ne 0 ]]
      then
        fatal "Failed to connect to the server - is ssh enabled?"
      else
       info "Copying utilities to $TARGETUSER@${server}"
       scp -r ~/utils $TARGETUSER@${server}:~/
      fi    
    done


    numservers=$(echo $servers | wc -w)
    info "$EnvName contains $numservers servers"
    count=1
    until [[ $count -gt $numservers ]]
    do
      (
        info "unzipping  ${APP}_mlcap${count}.tgz"
        [[ -d "$BASEDIR/mlcap${count}/${APP}" ]] || mkdir -p $BASEDIR/mlcap${count}/${APP}
        gunzip -c $BASEDIR/${APP}_mlcap${count}.tgz | \
              (cd $BASEDIR/mlcap${count}/${APP}; tar xf -)
      ) &
      count=$(($count + 1))
    done
    info "waiting for unzipping to complete"
    wait

    # Parsing section
    if [[ ${APP} != "mlcbase" ]]
    then
     if [[ -n "$PARSEENV" ]]
     then
         warn "Parsing ${EnvName} using $PARSEENV"
         PARSECONF=${CONFDIR}/${PARSEENV}.kv
     else
         PARSECONF=$CONF
     fi 
     count=1
     until [[ $count -gt $numservers ]]
     do
       for file in $(find $BASEDIR/mlcap${count}/${APP}  -type f -name "*.template");
       do
          typeset SOURCE=$file;
          typeset TARGET=$(echo $file | sed 's/\.template$//g;s/\/templates\//\//g')
          typeset tgtfile=$(basename $TARGET)
          perl $SCRIPTUTILS/parse.pl $PARSECONF $SOURCE $TARGET
       done
       count=$(($count + 1))
     done
    fi
 
    # Deploy
    count=1
    until [[ $count -gt $numservers ]]
    do
      host=$(getProperty mlc.app.server.$count $CONF)
      info "Syncing files to ${host}"
      $RSYNC $RSYNC_OPTIONS $RSYNC_BACKUP $RSYNC_EXCLUDES $BASEDIR/mlcap${count}/${APP}/*  ${TARGETUSER}@${host}:${TARGETDIR} 
      if [[ $? -ne 0 ]]
      then
        fatal "failed to copy to $host" 
      fi
      info "setting permissions"
      ssh ${TARGETUSER}@${host} "cd ${TARGETDIR};ksh chmods.ksh"
	  info "Copying backup into TeamCity"
      ssh ${TARGETUSER}@${host} "cd $(dirname ${BACKUPDIR});tar cvf - $(basename ${BACKUPDIR})" | gzip -c - > backup.tgz
      count=$(($count + 1))
    done
fi

if [[ $DOCONFIG = "true" ]]
then
  true
fi

if [[ $DORELEASE = "true" ]]
then
 true
fi

