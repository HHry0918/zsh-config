#!/bin/bash

########################################################################################
# MM utils
GOT_ARGS=false
TARGET_CHIP="mm6108"
get_args() {
    if [ "$GOT_ARGS" = false ]; then
        MORSE_REPO_DIR="$HOME/work"
        FPGA_REL_REPO_DIR="$MORSE_REPO_DIR/fpga-releases"
        IS_FPGA=false

        if [ "$1" = "fpga" ]; then
            MORSE_REPO_DIR="$FPGA_REL_REPO_DIR"
            IS_FPGA=true
        fi
        echo "IS_FPGA"
        echo "$IS_FPGA"

        TARGET_ID="banff"
        TARGET_REV="banffc"
        if [ "$IS_FPGA" = true ]; then
            TARGET_ID="eaglecrest"
            TARGET_REV="eaglecrestb"
        fi
        MORSE_FIRMWARE_DIR="$MORSE_REPO_DIR/morse_firmware"

        TARGET_DIR="$MORSE_FIRMWARE_DIR/targets/$TARGET_ID/$TARGET_REV"

        DRIVER_PATH="$MORSE_REPO_DIR/morse_buildroot/output/build/morse-mod-custom"
        FW_PATH="$TARGET_DIR/build"
        MCTRL_PATH="$MORSE_REPO_DIR/morse_buildroot/output/build/morse-ctrl-custom"

        REMOTE_USER="root"
        REMOTE_DRIVER_PATH='"/lib/modules/$(uname -r)/extra"'
        REMOTE_FW_PATH="/lib/firmware/morse"
        REMOTE_MCTRL_PATH="/usr/bin"

        GOT_ARGS=true
    fi
}

copy_hal_dir_to_fw() {
    echo "Copy hal to $MORSE_FIRMWARE_DIR"
    cp -r "$FPGA_REL_REPO_DIR/hal" "$MORSE_FIRMWARE_DIR/targets/$TARGET_ID/$TARGET_REV"
}

########################################################################################
# Deploy
deploy_fw() {
    get_args "$1"
    if [ $# = 0 ]; then
        echo "ERR: Please specify a target"
    else
        for TARGET in "$@"; do
            if [ "$TARGET" = "fpga" ]; then
                continue
            fi

            if [ "$IS_FPGA" = true ]; then
                echo "FW: Remove previous binaries in ${TARGET}:${REMOTE_FW_PATH}"
                ssh "$REMOTE_USER"@"$TARGET" "rm -rf $REMOTE_FW_PATH/*"
                TARGET_CHIP="mm8108"
            fi

            echo "FW: copying to ${TARGET}:${REMOTE_FW_PATH}/"
            rsync -vrPE --rsh=ssh "$FW_PATH"/"$TARGET_CHIP.bin" "$REMOTE_USER"@"$TARGET":"$REMOTE_FW_PATH"/
            rsync -vrPE --rsh=ssh "$FW_PATH"/"bcf_default.bin" "$REMOTE_USER"@"$TARGET":"$REMOTE_FW_PATH"/
        done
        echo "Firmware deployed"
    fi
}

deploy_driver() {
    get_args "$1"
    if [ $# = 0 ]; then
        echo "ERR: Please specify a target"
    else

        for TARGET in "$@"; do
            if [ "$TARGET" = "fpga" ]; then
                continue
            fi

            if [ "$IS_FPGA" = true ]; then
                echo "DRIVER: Remove previous kernel object in ${TARGET}:${REMOTE_DRIVER_PATH}"
                ssh "$REMOTE_USER"@"$TARGET" "rm -rf $REMOTE_DRIVER_PATH/*"
                ssh "$REMOTE_USER"@"$TARGET" "mkdir $REMOTE_DRIVER_PATH/dot11ah"
            fi

            echo "DRIVER: copying to ${TARGET}:${REMOTE_DRIVER_PATH}"
            rsync -vrPE --rsh=ssh "$DRIVER_PATH"/morse.ko "$REMOTE_USER"@"$TARGET":"$REMOTE_DRIVER_PATH/"
            rsync -vdPE --rsh=ssh "$DRIVER_PATH"/dot11ah/dot11ah.ko "$REMOTE_USER"@"$TARGET":"$REMOTE_DRIVER_PATH/dot11ah"
        done
        echo "Driver deployed"
    fi
}

deploy_mctrl() {
    get_args "$1"
    if [ $# = 0 ]; then
        echo "ERR: Please specify a target"
    else

        for TARGET in "$@"; do
            if [ "$TARGET" = "fpga" ]; then
                continue
            fi
            echo "MCTRL: copying to ${TARGET}:${REMOTE_MCTRL_PATH}"
            rsync -vrPE --rsh=ssh "$MCTRL_PATH"/morsectrl "$REMOTE_USER"@"$TARGET":"$REMOTE_MCTRL_PATH"/morsectrl
            rsync -vrPE --rsh=ssh "$MCTRL_PATH"/morse_cli "$REMOTE_USER"@"$TARGET":"$REMOTE_MCTRL_PATH"/morse_cli
        done
        echo "Morsectrl deployed"
    fi
}

deploy_all() {
    get_args "$1"
    deploy_fw "$@" &&
        deploy_driver "$@" &&
        deploy_mctrl "$@"
}

########################################################################################
# Build
build_fw() {
    get_args "$1"
    FPGA_ARG=""
    if [ "$IS_FPGA" = true ]; then
        FPGA_ARG=" FPGA_BUILD=1 -C $FW_PATH"
        copy_hal_dir_to_fw
    fi
    pushd "$TARGET_DIR"
    echo "Cur Dir:"
    echo "$(pwd)"
    echo
    trap exit_build INT
    make clean
    make rom-clean
    echo "make -j8 $FPGA_ARG"
    make -j8 "$FPGA_ARG" && popd
}

build_driver() {
    get_args "$1"
    pushd "$MORSE_REPO_DIR"/morse_buildroot
    trap exit_build INT
    make morse-mod-dirclean morse-mod-rebuild && popd
}

build_mctrl() {
    get_args "$1"
    pushd "$MORSE_REPO_DIR"/morse_buildroot
    trap exit_build INT
    make morse-ctrl-rebuild && popd
}

exit_build() {
    trap - INT
    popd
}

build_all() {
    get_args "$1"
    build_fw && build_driver && build_mctrl
}

########################################################################################
# Update
update_fw() {
    get_args "$1"
    build_fw && deploy_fw "$@"
}

update_driver() {
    get_args "$1"
    build_driver && deploy_driver "$@"
}

update_mctrl() {
    get_args "$1"
    build_mctrl && deploy_mctrl "$@"
}

update_all() {
    get_args "$1"
    build_all && deploy_all "$@"
}

########################################################################################
# VPN utils
VPN_PROFILE="$HOME/VPN/profile-606.ovpn"
connect_vpn() {
    openvpn3 session-start --config "$VPN_PROFILE"
}

check_vpn() {
    echo "Check VPN sessions list"
    openvpn3 sessions-list
}

disconnect_vpn() {
    ACTIVE_SESSIONS=$(openvpn3 sessions-list | grep -i 'path' | awk '{p=index($0, ":");print $2}')
    echo $ACTIVE_SESSIONS
    for instance in $ACTIVE_SESSIONS; do
        openvpn3 session-manage --disconnect --session-path ${instance}
    done 
    openvpn3 session-manage --disconnect --config "$VPN_PROFILE"
}
