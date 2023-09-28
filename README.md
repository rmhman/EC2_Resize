# Resize EC2s - Hopefully Down to Save 💵 !

## Getting Started
Clone this GIT repo, and make sure you have your AWS creds set up with ```aws configure```.


## Update the Resize File
Inside the ```ec2_resize``` directory you will find a file named ```resize``` 
Add all your instance id's followed a single space and the instance type that you want to change to.
> **Example:**

        i-093d4efe5d98f7613 t3a.xlarge
        i-093d4efe5d98f7613 m4.xlarge


## Run the Script
From the directory with the script in it - run: ```./change_ec2_instance_type.sh```
