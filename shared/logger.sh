#! /bin/bash

log() {
    echo -e "$1"
}

log-error() {
    # Red
    echo -e "\e[31m$1\e[39m"
}

log-warn() {
    # Yellow
    echo -e "\e[93m$1\e[39m"
}

log-info() {
    # Blue
    echo -e "\e[94m$1\e[39m"
}
