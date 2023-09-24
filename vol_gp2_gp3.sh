#! /bin/bash
logfile=logfile.txt
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec > >(tee -a "$logfile") 2>&1
date

source ./shared/logger.sh

function volgp2gp3() {
vols=("$@")
  for v in "${!vols[@]}"
    do
      date
      echo "Changing ${vols[v]} to gp3"
      aws ec2 modify-volume --volume-type gp3 --volume-id ${vols[v]}
    done
}


#insts=("i-38aa5d88" "i-a24a973d")
all_vols=`awk '{ print$1 }' gp2vols.txt`
readarray -t vols <<<  "$all_vols"
volgp2gp3 "${vols[@]}"
log-info "INFO: Change Type Completed!

"
