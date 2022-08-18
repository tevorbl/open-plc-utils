#!/bin/bash
#
# Interrogate a network to find the details of the Powerline
# HomePlug wall adapters in the network.
#
# inspired by blog at:
# https://fitzcarraldoblog.wordpress.com/2021/04/23/using-open-plc-utils-in-linux-with-powerline-homeplug-adapters/
# ... and subjected to constant tinkering ...
#
# It uses open-plc-utils tools:
# https://github.com/qca/open-plc-utils
#
# See https://github.com/qca/open-plc-utils/blob/master/README for
# instructions on how to install (and uninstall) the tools.
# Therefore this script is limited to the chipsets that open-plc-utils supports:
# https://github.com/qca/open-plc-utils/blob/master/plc/chipset.h
#
# The command int6k supports legacy chipsets INT6000, INT6300 and INT6400.
# The command plctool supports QCA6410, QCA7000 and QCA7420 devices.
# The command amptool supports chipsets AR7400 and QCA7450.
#
# NETGEAR XAVB1301-100UKS uses AR6405. NETGEAR XAVB5221-100UKS uses QCA7420.
# TP-Link TL-PA4010, TL-PA4010P and TL-PA4020P use QCA7420.
#
echo "================================================================================"
# Specify the interface on this PC connected to a HomePlug device:
# assuming only one ethernet interface here
IP_ADDRESS=$(hostname --all-ip-addresses)

# PLC variable is understood by all tools to specify the ethernet interface
export PLC=$(ip -br a | grep $IP_ADDRESS | cut -d ' ' -f1)
echo
echo "The Ethernet interface on this PC is: " $PLC "( "$IP_ADDRESS")"
echo
echo "================================================================================"
echo
#
# Step 1. Send VS_SW_VER to local device to determine its MAC address and device type.
#
# find correct tool for device chipset
# the idea here is that each tool returns data if it recognises the chipset,
# otherwise it returns nothing.
if [ $( int6k -i $PLC -qI local | wc -l ) -ge 2 ]; then
    CHIPSETCMD=int6k
elif [ $( plctool -i $PLC -qI local | wc -l ) -ge 2 ]; then
    CHIPSETCMD=plctool
elif [ $( amptool -i $PLC -qI local | wc -l ) -ge 2 ]; then
    CHIPSETCMD=amptool
else
    echo "unable to determine chipset tool for local HomePlug wall adapter - quitting"
    exit
fi

MAC=$( $CHIPSETCMD -i $PLC -qr local | awk -F ' ' '{print $2}' )
#echo MAC is \"$MAC\"


echo "Details for the HomePlug wall adapter connected to this computer:"
echo
$CHIPSETCMD -mq $MAC
$CHIPSETCMD -qI $MAC
echo
CHIPSET=$( $CHIPSETCMD -qr $MAC | awk -F ' ' '{print $3}' )
echo "Local Chipset:" $CHIPSET

echo
echo "================================================================================"
#
# Step 2. Send VS_NW_INFO (int6k -m or plctool -m, depending on device type)
# to local MAC address to find MAC addresses of the other devices.
#
$CHIPSETCMD -qm $MAC | grep MAC | cut -d " " -f3 > maclist.txt

#
# Step 3. Send VS_NW_INFO (int6k -m or plctool -m, depending on device type) to
# each device to determine the device type and full PHY Rate.
#
echo
echo "Details for the other HomePlug wall adapters in the network"
echo "(adapters in Power Saving Mode are not shown):"
while read -r MAC
do
    echo
    CHIPSETCMD=
    # find correct tool for remote device chipset
    if [ $( int6k -i $PLC -qI $MAC | wc -l ) -ge 2 ]; then
        CHIPSETCMD=int6k
    elif [ $( plctool -i $PLC -qI $MAC | wc -l ) -ge 2 ]; then
        CHIPSETCMD=plctool
    elif [ $( amptool -i $PLC -qI $MAC | wc -l ) -ge 2 ]; then
        CHIPSETCMD=amptool
    else
        echo "unable to determine chipset tool for remote HomePlug $MAC"
    fi

    # report data for the remote device
    if [ -n "$CHIPSETCMD" ]; then
        $CHIPSETCMD -mq $MAC
        $CHIPSETCMD -qI $MAC
        echo
        CHIPSET=$( $CHIPSETCMD -qr $MAC | awk -F ' ' '{print $3}' )
        echo "Remote Chipset:" $CHIPSET
    fi
    echo
    echo "--------------------------------------------------------------------------------"
done <maclist.txt

rm maclist.txt

echo
echo "Some of the abbreviations are listed below, but refer to the open-plc-utils"
echo "documentation for more details. (Also see http://www.homeplug.org/ for"
echo "detailed HomePlug specifications)"
echo
echo "BDA   Bridged Destination Address"
echo "CCo   Central Coordinator"
echo "DAK   Device Access Key"
echo "MDU   Multiple Dwelling Unit"
echo "NID   Network Identifier"
echo "NMK   Network Membership Key"
echo "PIB   Parameter Information Block"
echo "SNID  Short Network Identifier"
echo "STA   Station"
echo "TEI   Terminal Equipment Identifier"
echo
exit

################# end of homeplug.sh ##################################
