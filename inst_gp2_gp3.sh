#! /bin/bash
logfile=logfile.txt
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec > >(tee -a "$logfile") 2>&1
date

source ./shared/logger.sh

function changegp2gp3() {
inst=("$@")
for i in "${!inst[@]}"
  do
  echo "${inst[i]}"
  declare -a vols=()
  all_vols=`aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=${inst[i]} |jq -r '.Volumes[].VolumeId'`
  readarray -t vols <<< "$all_vols"
  echo
    for v in "${!vols[@]}"
      do
      date
      echo "Changing ${vols[v]} to gp3"
      aws ec2 modify-volume --volume-type gp3 --volume-id ${vols[v]}
      done
  done
}


#insts=("i-38aa5d88" "i-a24a973d")
all_insts=`awk '{ print$1 }' resize`
readarray -t insts <<<  "$all_insts"
changegp2gp3 "${insts[@]}"
log-info "INFO: Change Type Completed!

"
