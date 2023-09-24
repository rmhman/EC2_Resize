#!/bin/bash
logfile=logfile.txt
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec > >(tee -a "$logfile") 2>&1
date
###############################################################################
#
# function change_ec2_instance_type
#
# This function changes the instance type of the specified Amazon EC2 instance.
#
# Parameters:
#   -i   [string, mandatory] The instance ID of the instance whose type you
#                            want to change.
#   -t   [string, mandatory] The instance type to switch the instance to.
#   -f   [switch, optional]  If set, the function doesn't pause and ask before
#                            stopping the instance.
#   -r   [switch, optional]  If set, the function restarts the instance after
#                            changing the type.
#   -v   [switch, optional]  Enable verbose logging.
#   -h   [switch, optional]  Displays this help.
#
# Example:
#      The following example converts the specified instance to type "t2.micro"
#      without pausing to ask permission. It automatically restarts the
#      instance after changing the type.
#
#      change_ec2_instance_type -i i-123456789012 -t t2.micro -f -r
#
# Returns:
#      0 if successful
#      1 if it fails
###############################################################################

# Import the general_purpose functions.
source ./shared/awsdocs_general.sh
source ./shared/logger.sh

###############################################################################
# function instance-exists
#
# This function checks to see if the specified instance already exists. If it
# does, it sets two global parameters to return the running state and the
# instance type.
#
# Input parameters:
#       $1 - The id of the instance to check
#
# Returns:
#       0 if the instance already exists
#       1 if the instance doesn't exist
#     AND:
#       Sets two global variables:
#            EXISTING_STATE - Contains the running/stopped state of the instance.
#            EXISTING_TYPE  - Contains the current type of the instance.
###############################################################################
function get_instance_info {

    # Declare local variables.
    local INSTANCE_ID RESPONSE

    # This function accepts a single parameter.
    INSTANCE_ID=$1

    # The following --filters parameter causes server-side filtering to limit
    # results to only the records that match the specified ID. The --query
    # parameter causes CLI client-side filtering to include only the values of
    # the InstanceType and State.Code fields.

    RESPONSE=$(aws ec2 describe-instances \
                   --query 'Reservations[*].Instances[*].[State.Name, InstanceType]' \
                   --filters Name=instance-id,Values="$INSTANCE_ID" \
                   --output text \
               )

    if [[ $? -ne 0 ]] || [[ -z "$RESPONSE" ]]; then
        # There was no response, so no such instance.
        return 1        # 1 in Bash script means error/false
    fi

    # If we got a response, the instance exists.
    # Retrieve the values of interest and set them as global variables.
    EXISTING_STATE=$(echo "$RESPONSE" | cut -f 1 )
    EXISTING_TYPE=$(echo "$RESPONSE" | cut -f 2 )

    return 0        # 0 in Bash script means no error/true
}


function change_ec2_instance_type {

    function usage() (
        echo ""
        echo "This function changes the instance type of the specified instance."
        echo "Parameter:"
        echo "  -i  Specify the instance ID whose type you want to modify."
        echo "  -t  Specify the instance type to convert the instance to."
        echo "  -f  If the instance was originally running, this option prevents"
        echo "      the script from asking permission before stopping the instance."
        echo "  -r  Start instance after changing the type."
        echo "  -v  Enable verbose logging."
        echo ""
    )

    local FORCE RESTART REQUESTED_TYPE INSTANCE_ID VERBOSE OPTION RESPONSE ANSWER
    local OPTIND OPTARG # Required to use getopts command in a function.

    # Set default values.
    FORCE=false
    RESTART=false
    REQUESTED_TYPE=""
    INSTANCE_ID=""
    VERBOSE=false

    # Retrieve the calling parameters.
    while getopts "i:t:frvh" OPTION; do
        case "${OPTION}"
        in
            i)  INSTANCE_ID="${OPTARG}";;
            t)  REQUESTED_TYPE="${OPTARG}";;
            f)  FORCE=true;;
            r)  RESTART=true;;
            v)  VERBOSE=true;;
            h)  usage; return 0;;
            \?) echo "Invalid parameter"; usage; return 1;;
        esac
    done

    if [[ -z "$INSTANCE_ID" ]]; then
        log-error "ERROR: You must provide an instance ID with the -i parameter.\n"
        usage
        return 1
    fi

    if [[ -z "$REQUESTED_TYPE" ]]; then
        log-error "ERROR: You must provide an instance type with the -t parameter.\n"
        usage
        return 1
    fi

    iecho "Parameters: "
    iecho "    Instance ID:   $INSTANCE_ID"
    iecho "    Requests type: $REQUESTED_TYPE"
    iecho "    Force stop:    $FORCE"
    iecho "    Restart:       $RESTART"
    iecho "    Verbose:       $VERBOSE"
    iecho ""

    # Check that the specified instance exists.
    iecho -n "Confirming that instance $INSTANCE_ID exists..."
    get_instance_info "$INSTANCE_ID"
    # If the instance doesn't exist, the function returns an error code <> 0.
    if [[ ${?} -ne 0 ]]; then
        log-error "\nERROR: I can't find the instance \"$INSTANCE_ID\" in the current AWS account.\n"
        return 1
    fi
    # Function get_instance_info has returned two global values:
    #   $EXISTING_TYPE  -- The instance type of the specified instance
    #   $EXISTING_STATE -- Whether the specified instance is running

    iecho "confirmed $INSTANCE_ID exists."
    iecho "      Current type: $EXISTING_TYPE"
    iecho "      Current state code: $EXISTING_STATE"

    # Are we trying to change the instance to the same type?
    if [[ "$EXISTING_TYPE" == "$REQUESTED_TYPE" ]]; then
        log-info "INFO: Instance type is already type: $REQUESTED_TYPE.\n"
        return 1
    fi

    # Check if the instance is currently running.
    # 16="running"
    if [[ "$EXISTING_STATE" == "running" ]]; then
        # If it is, we need to stop it.
        # Do we have permission to stop it?
        # If -f (FORCE) was set, we do.
        # If not, we need to ask the user.
        if [[ $FORCE == false ]]; then
            while true; do
                echo ""
                echo "The instance $INSTANCE_ID is currently running. It must be stopped to change the type."
                read -r -p "ARE YOU SURE YOU WANT TO STOP THE INSTANCE? (Y or N) " ANSWER
                case $ANSWER in
                    [yY]* )
                        break;;
                    [nN]* )
                        echo "Aborting."
                        exit;;
                    * )
                        echo "Please answer Y or N."
                        ;;
                esac
            done
        else
            iecho "Forcing stop of instance without prompt because of -f."
        fi

        # stop the instance
        iecho -n "Attempting to stop instance $INSTANCE_ID..."
        RESPONSE=$( aws ec2 stop-instances \
                        --instance-ids "$INSTANCE_ID" )

        if [[ ${?} -ne 0 ]]; then
            log-error "ERROR - AWS reports that it's unable to stop instance $INSTANCE_ID.\n$RESPONSE"
            return 1
        fi
        iecho "request accepted."
    else
        iecho "Instance is not in running state, so not requesting a stop."
    fi;

    # Wait until stopped.
    iecho "Waiting for $INSTANCE_ID to report 'stopped' state..."
    aws ec2 wait instance-stopped \
        --instance-ids "$INSTANCE_ID"
    if [[ ${?} -ne 0 ]]; then
        log-error "\nERROR - AWS reports that Wait command failed.\n$RESPONSE"
        return 1
    fi
    iecho "stopped."

    # Change the type - command produces no output.
    iecho "Attempting to change type from $EXISTING_TYPE to $REQUESTED_TYPE..."
    RESPONSE=$(aws ec2 modify-instance-attribute \
                   --instance-id "$INSTANCE_ID" \
                   --instance-type "{\"Value\":\"$REQUESTED_TYPE\"}"
              )
    if [[ ${?} -ne 0 ]]; then
        log-error "ERROR - AWS reports that it's unable to change the instance type for instance $INSTANCE_ID from $EXISTING_TYPE to $REQUESTED_TYPE.\n$RESPONSE"
        return 1
    fi
    iecho "changed."

    # Restart if asked
    if [[ "$RESTART" == "true" ]]; then

        iecho "Requesting to restart instance $INSTANCE_ID..."
        RESPONSE=$(aws ec2 start-instances \
                        --instance-ids "$INSTANCE_ID" \
                   )
        if [[ ${?} -ne 0 ]]; then
            log-error "ERROR - AWS reports that it's unable to restart instance $INSTANCE_ID.\n$RESPONSE"
            return 1
        fi
        iecho "started."
        iecho "Waiting for instance $INSTANCE_ID to report 'running' state..."
        RESPONSE=$(aws ec2 wait instance-running \
                       --instance-ids "$INSTANCE_ID" )
        if [[ ${?} -ne 0 ]]; then
            log-error "ERROR - AWS reports that Wait command failed.\n$RESPONSE"
            return 1
        fi

        iecho "running."

    else
        iecho "Restart was not requested with -r."
    fi
}


all_insts=`awk '{ print$1 }' resize`
readarray -t insts <<<  "$all_insts"

all_types=`awk '{ print$2 }' resize`
readarray -t types <<<  "$all_types"

if [ "${#insts[@]}" == "${#types[@]}" ]
then
for i in "${!insts[@]}"
  do
    change_ec2_instance_type -fvr -i ${insts[i]} -t ${types[i]}
  date
  done
else
log-error "
ERROR: Make sure you have a type specified for each instance! (You must have the same number of rows in each column)
"
exit 1
fi
log-info "
INFO: Change Type Completed!

"
