#!/usr/bin/ksh
COB=$1
if [[ -z $1 ]] || [[ $(echo $1 | /usr/xpg4/bin/egrep -c '^[0-9]{1,2}/[0-9]{1,2}/20[0-9]{2}') -lt 1 ]]
then
  echo "Specify date : dd/mm/yyyy"
  exit 1
fi
dir=$(cd $(dirname $0);pwd)
pid=$$
. /mlc/apps/mlctask/mlctask_uat_05/live/etc/setENV.ksh
dates=$(echo "
BEGIN
DECLARE @SWAPDATE DATETIME 
DECLARE @FROMDATE DATETIME
DECLARE @offset int

SELECT @offset=1
SELECT @FROMDATE=convert(datetime, '$COB',103) 
while datepart(dw,dateadd(dd,-@offset,@FROMDATE)) in (1,7)
          or exists (select * from Calendar
                     where CalendarLabel like 'HOLIDAY%'
                     and CalendarDate = dateadd(dd,-@offset,@FROMDATE))
    begin
        select @offset = @offset + 1
    end
select @SWAPDATE=DATEADD(day,-@offset,@FROMDATE)

update dbo.Calendar set CalendarDate=@SWAPDATE where CalendarID=1
select convert(varchar,@SWAPDATE,112),  convert(varchar,@FROMDATE,112)
end

go " | isql -S$SYB_SERVER -U$SYB_USER -P$SYB_PWD -D$SYB_DB  | egrep " [0-9].*" | sed 's/^ //g')

prevdate=$(echo $dates |nawk '{ print $1 }')
cobdate=$(echo $dates |nawk '{ print $2 }')

server1=wfq-mlcap1
server2=wfq-mlcap2

echo "  
for sharedir in mlcfiles batch_reports logs input 
  do
    if [[ ! -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate ]]
    then
      mkdir -p /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate
    fi
    if [[ -L /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest ]]
    then
      rm /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest
    elif [[ -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest ]]
    then
      mv /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/save_latest_${prevdate}.${pid}
    fi
    ln -s /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest
    if [[ -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$cobdate ]]
    then
      mv /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$cobdate /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/save_${cobdate}.$pid
    fi
  done 
  if [[ -f /mlc/apps/mlctask/mlctask_uat_05/shared/Batch_Finished_mlcap1.txt ]]
  then
    rm /mlc/apps/mlctask/mlctask_uat_05/shared/Batch_Finished_mlcap1.txt
  fi

" > /tmp/server1_shared.ksh

  echo "
  for sharedir in mlcfiles batch_reports logs input 
  do
    if [[ ! -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate ]]
    then
      mkdir -p /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate
    fi
    if [[ -L /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest ]]
    then
      rm /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest
    elif [[ -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest ]]
    then
      mv /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/save_latest_${prevdate}.${pid}
    fi
    ln -s /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$prevdate /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/latest
    if [[ -d /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$cobdate ]]
    then
      mv /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/$cobdate /mlc/apps/mlctask/mlctask_uat_05/shared/\$sharedir/save_${cobdate}.$pid
    fi
  done
" > /tmp/server2_shared.ksh

if [[ $server1 = $(hostname) ]]
then
  ksh /tmp/server1_shared.ksh
else
  scp /tmp/server1_shared.ksh svcmlctaskq@wfq-mlcap1:/tmp/
  ssh svcmlctaskq@wfq-mlcap1 "ksh /tmp/server1_shared.ksh"
fi

if [[ $server2 = $(hostname) ]]
then
  ksh /tmp/server2_shared.ksh
else
  scp /tmp/server2_shared.ksh svcmlctaskq@wfq-mlcap2:/tmp/
  ssh svcmlctaskq@wfq-mlcap2 "ksh /tmp/server2_shared.ksh"
fi

if [[ -n $2 ]]
then
  cp $2/* /mlc/apps/mlctask/mlctask_uat_05/shared/mlcfiles/latest 
fi
cp $dir/FXrates.csv /mlc/apps/mlctask/mlctask_uat_05/shared/input/$prevdate/


