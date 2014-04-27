#!/usr/bin/ksh -x
mlcfiles1=$1
mlcfiles2=$2
[[ -z "$mlcfiles2" ]] && mlcfiles2=$mlcfiles1
dir=$(cd $(dirname $0);pwd)
. /mlc/apps/mlctask/mlctask_uat_05/live/etc/setENV.ksh

if [[ -d "$mlcfiles1" ]]
then
  cp $mlcfiles1/* $MLCINPUT/
fi
ssh $APP2_MLCTASKUSER@$APP2_SERVER "if [[ -d \"$mlcfiles2\" ]] ; then cp $mlcfiles2/* $APP2_MLCFILES; fi"

scp $dir/TransactionDetails_RTLIM.txt  $APP2_MLCTASKUSER@$APP2_SERVER:$APP2_BATCH_REPORTS_DIR
