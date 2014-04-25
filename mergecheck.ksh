#!/usr/bin/ksh 
if [[ -z "$1" ]] 
then
 echo "Please supply branch path. e.g. /mlctask/branches/<branch>"
 exit 1
fi
svnfull=$1
svnsrc=${svnfull#*//*/}
if [[ ${svnfull%%/*} = "svn:" ]]
then
  svnurl=$(echo $svnfull | nawk -F'/' 'OFS="/" { print $1,$2,$3}' ) 
else
  svnurl=http://fmd-a8-2886.markets.global.lloydstsb.com/svn
fi
release=$(basename $svnsrc)
target=$release

if [[ $release = "trunk" ]]
then
  svnbranches="${svnurl}/$(dirname $svnsrc)/branches"
else
  svnbranches="${svnurl}/$(dirname $svnsrc)"
fi


svn info ${svnurl}/${svnsrc} > /dev/null 2>&1
if [[ $? -ne 0 ]]
then
  echo "Failed to find repo path ${svnurl}/${svnsrc}"
  exit 1
fi

set -A mergeinfo $(svn propget svn:mergeinfo ${svnurl}/${svnsrc} | sed 's/.*\///g;') 
svn list $svnbranches | while read branch 
do 
    branch=${branch%%/}
    [[ $branch = $release ]] && continue
    echo "Processing branch: $branch"
    thismerge=""
    source=$(svn log --verbose --stop-on-copy ${svnbranches}/$branch |\
        egrep "^ *A /.*from" | tail -1 | sed  's/.*(from .*\///g;s/:.*$//g')
    ##echo "$branch was branched from $source"
    if [[ "$source" = "$release" ]]
    then
      lastupdated=$( svn info ${svnbranches}/$branch | sed '/Last Changed Rev:/!d;s/Last Changed Rev: //g') 
      
      ##echo "$branch is from $source and was last updated in repo version: $lastupdated"
      ##echo "starting loop of merge info"
      merged=false
      for m in ${mergeinfo[@]} 
      do 
        thisbranch=${m%%:*}
        thisversion=${m##*:}
        if [[ "$thisbranch" = "$branch" ]]
        then   
          thismerge=$(echo $thisversion | sed 's/.*-//g')
          ##echo "$branch has been merged in repo version $thismerge and was last updated repo version $lastupdated"
          if [[ $lastupdated -gt $thismerge  ]] 
          then 
            ##echo "$thismerge is greater than or equal to $lastupdated: include this branch"
            merged=false
            break
          else
            merged=true
            ##echo "$branch was merged to $release in repo version $thismerge"
            break
          fi 
        else
           merged=false   
        fi
      done
      if [[ $merged = "false" ]]
      then
        echo "Including $branch in merge"
        branched="$branched $branch"
      fi 
    fi

done
if [[ -n "$branched" ]]
then
  [[ -d $target ]] && rm -r $target 
  svn co ${svnurl}/${svnsrc} $target  > /dev/null 
  errorflag=false
  for merge in $branched
  do
    conflict=""
    echo "Merging $merge into $release"
    conflict=$(svn merge --accept postpone ${svnbranches}/$merge $target | egrep  "conflicts: [0-9]")
    if [[ -n $conflict ]]
    then
      errorflag=true
      mergesource="$mergesource $merge"
    fi
  done
  if [[ $errorflag = "true" ]]
  then
    echo "Merge Conflicts in $mergesource"
    #echo "##teamcity[message text='Merge Conflicts in $mergesource' errorDetails='$(svn status $target | tail -1)' status='ERROR']"
    svn status $target 
    echo "##teamcity[buildStatus status='FAILURE' text='Merge Conflicts in $mergesource']"
  else
    echo "No merge conflicts. List of changes:"
    svn status $target 
    echo "##teamcity[message text='No Merge Conflicts in $release']"
  fi
fi

