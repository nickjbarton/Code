#!/usr/bin/ksh
mlcfiles=$1

dir=$(cd $(dirname $0);pwd)
. /mlc/apps/mlctask/mlctask_uat_05/live/etc/setENV.ksh
. /mlc/apps/mlctask/mlctask_uat_05/live/etc/CommonFunctions.ksh
echo "Getting current date from DB and rolling forward"
date=$(echo "
select  convert(varchar,CalendarDate,103) from Calendar where CalendarID=1
go " | isql -S$SYB_SERVER -U$SYB_USER -P$SYB_PWD -D$SYB_DB  | egrep " [0-9].*" | sed 's/^ //g')

#date=$(callSQL "SELECT TO_CHAR(CalendarDate, 'DD/MM/YYYY') FROM Calendar WHERE CalendarID=1;")

echo "Purging all engines"

cd $MLC_LTS_LAUNCH_PATH
./launchmlc.sh -lts $dir/lts_purge_all_engines.xml

if [[ $? -ne 0 ]]
then
  echo "Failed to purge engines, you will need to manually do this"
  exit 1
fi

echo "Creating Engine for $date" 
cd $dir
sed "s#@DATE@#$date#g;s#@HOME@#/mlc/apps/mlctask/mlctask_uat_05#g" lts_create_rtlim_engine.xml.template > lts_create_rtlim_engine.xml
if [[ $? -ne 0 ]]
then
  echo "Failed to parse file"
  exit 1
fi
cd $MLC_LTS_LAUNCH_PATH
./launchmlc.sh -lts $dir/lts_create_rtlim_engine.xml
echo "Engine prepared, sleeping for 30 seconds"
sleep 30
rm $BATCH_REPORTS_DIR/*.go
for file in TMLCOB05_createEngineB2RTFeed.go TMLCOB05_flushEngineB1.go TMLCOB05_rtlimShiftDate.go TMLCOB05_startSS.go TMLCOB05_stopSS.go
do
 [[ -f $BATCH_REPORTS_DIR/$file ]] && rm $BATCH_REPORTS_DIR/$file
done
for file in TMLCOB05_startSS.go TMLCOB05_stopSS.go
do
  touch $BATCH_REPORTS_DIR/$file
done
if [[ -d "$mlcfiles" ]]
then
  cp $mlcfiles/* $MLCINPUT/
fi
