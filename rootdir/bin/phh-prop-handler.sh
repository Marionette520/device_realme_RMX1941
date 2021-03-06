#!/system/bin/sh
set -o pipefail

display_usage() {
    echo -e "\nUsage:\n ./phh-prop-handler.sh [prop]\n"
}

if [ "$#" -ne 1 ]; then
    display_usage
    exit 1
fi

prop_value=$(getprop "$1")

xiaomi_toggle_dt2w_proc_node() {
    DT2W_PROC_NODES=("/proc/touchpanel/wakeup_gesture"
        "/proc/tp_wakeup_gesture"
        "/proc/tp_gesture")
    for node in "${DT2W_PROC_NODES[@]}"; do
        [ ! -f "${node}" ] && continue
        echo "Trying to set dt2w mode with /proc node: ${node}"
        echo "$1" >"${node}"
        [[ "$(cat "${node}")" -eq "$1" ]] # Check result
        return
    done
    return 1
}

xiaomi_toggle_dt2w_event_node() {
    for ev in $(
        cd /sys/class/input || return
        echo event*
    ); do
        isTouchscreen=false
        if getevent -p /dev/input/$ev |grep -e 0035 -e 0036|wc -l |grep -q 2;then
            isTouchscreen=true
        fi
        [ ! -f "/sys/class/input/${ev}/device/device/gesture_mask" ] &&
            [ ! -f "/sys/class/input/${ev}/device/wake_gesture" ] &&
            ! $isTouchscreen && continue
        echo "Trying to set dt2w mode with event node: /dev/input/${ev}"
        if [ "$1" -eq 1 ]; then
            # Enable
            sendevent /dev/input/"${ev}" 0 1 5
            return
        else
            # Disable
            sendevent /dev/input/"${ev}" 0 1 4
            return
        fi
    done
    return 1
}


restartAudio() {
    setprop ctl.restart audioserver
    audioHal="$(getprop |sed -nE 's/.*init\.svc\.(.*audio-hal[^]]*).*/\1/p')"
    setprop ctl.restart "$audioHal"
    setprop ctl.restart vendor.audio-hal-2-0
    setprop ctl.restart audio-hal-2-0
}

if [ "$1" == "persist.sys.phh.xiaomi.dt2w" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if ! xiaomi_toggle_dt2w_proc_node "$prop_value"; then
        # Fallback to event node method
        xiaomi_toggle_dt2w_event_node "$prop_value"
    fi
    exit $?
fi

if [ "$1" == "persist.sys.phh.oppo.dt2w" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo 1 >/proc/touchpanel/double_tap_enable
    exit
fi

if [ "$1" == "persist.sys.phh.oppo.gaming_mode" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" >/proc/touchpanel/game_switch_enable
    exit
fi

if [ "$1" == "persist.sys.phh.oppo.usbotg" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" >/sys/class/power_supply/usb/otg_switch
    exit
fi

if [ "$1" == "persist.sys.phh.disable_audio_effects" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        resetprop_phh ro.audio.ignore_effects true
    else
        resetprop_phh --delete ro.audio.ignore_effects
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.caf.audio_policy" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        umount /vendor/etc/audio
        umount /vendor/etc/audio
        if [ -f /vendor/etc/audio/audio_policy_configuration.xml ];then
            mount /vendor/etc/audio/audio_policy_configuration.xml /vendor/etc/audio_policy_configuration.xml
        elif [ -f /vendor/etc/audio_policy_configuration_base.xml ];then
            mount /vendor/etc/audio_policy_configuration_base.xml /vendor/etc/audio_policy_configuration.xml
        fi
    else
        umount /vendor/etc/audio_policy_configuration.xml
        mount /mnt/phh/empty_dir /vendor/etc/audio
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.vsmart.dt2w" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        echo 0 > /sys/class/vsm/tp/gesture_control
    else
        echo > /sys/class/vsm/tp/gesture_control
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.backlight.scale" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        if [ -f /sys/class/leds/lcd-backlight/max_brightness ];then
            setprop persist.sys.qcom-brightness "$(cat /sys/class/leds/lcd-backlight/max_brightness)"
        elif [ -f /sys/class/backlight/panel0-backlight/max_brightness ];then
            setprop persist.sys.qcom-brightness "$(cat /sys/class/backlight/panel0-backlight/max_brightness)"
        fi
    else
        setprop persist.sys.qcom-brightness -1
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.qin.dt2w" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" > /sys/devices/platform/soc/soc:ap-apb/70800000.i2c/i2c-3/3-0038/fts_gesture_mode
    exit
fi

#root
if [ "$1" == "persist.sys.phh.root" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]] || [ -d /sbin/.magisk ]; then
        exit 1
    fi

    if [[ "$prop_value" == "true" ]]; then
        umount -nfl /system/xbin
        cp -r --preserve=all /system/xbin /mnt/phh/xbin
        cp --preserve=all /system/phh/xbin/* /mnt/phh/xbin
        mount /mnt/phh/xbin /system/xbin
        setprop ctl.start zerodaemon
        pm install -r /system/phh/phh.superuser.apk
    else
        pm uninstall -k me.phh.superuser
        setprop ctl.stop zerodaemon
        umount -nfl /system/xbin
        rm -rf /mnt/phh/xbin /data/su
    fi
    exit
fi

#safetynet
if [ "$1" == "persist.sys.phh.safetynet" ]; then
    if [[ "$prop_value" != "true" ]]; then
        exit 1
    fi

    if [ ! -f /data/adb/phh/secure ]; then
        mkdir -p /data/adb/phh
        cp /system/phh/secure.sh /data/adb/phh/secure
    fi
    /system/bin/sh /data/adb/phh/secure
    exit
fi

#autorun
if [ "$1" == "persist.sys.phh.autorun" ]; then
    if [[ "$prop_value" != "true" ]]; then
        exit 1
    fi

    if [ ! -f /data/adb/phh/run ]; then
        mkdir -p /data/adb/phh
        touch /data/adb/phh/run
    fi
    /system/bin/sh /data/adb/phh/run
    exit
fi

#nolog
if [ "$1" == "persist.sys.phh.nolog" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == "true" ]]; then
        setprop ctl.stop logd
        setprop ctl.stop traced
        setprop ctl.stop traced_probes
    else
        setprop ctl.start traced_probes
        setprop ctl.start traced
        setprop ctl.start logd
    fi
    exit
fi
