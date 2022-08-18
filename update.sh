#!/bin/sh

# update homeplug firmware
#
# usage ./update file1 file2
# where file1 & file2 are pib & nvm file, optional, in any order
#
# New firmware needs to be correctly configured for the local homeplug device
# (specifically its MAC, DAK & NMK values
#  - or in plain english, the address, password & network id)
# This script reads these existing values from the local device and
# insets them into the new firmware before programming it into the device.
#
# written for tp-link av600 or similar devices,
# probably needs changing for other systems.
#
# based on this blog:
# https://fitzcarraldoblog.wordpress.com/2020/07/22/updating-the-powerline-adapters-in-my-home-network
#
# reference:
#  Qualcomm Atheros Open Powerline Toolkit, chapter 5
#  (available in the download, at .../docbook/index.html)
#

# uncomment the following line to dry-run the update comamnds
DRYRUN=echo

if [ -z "$1" ]; then
    echo usage:
    echo "  $0 file1 file2"
    echo "  where file1 & file2 are pib & nvm file, optional, in any order"
    if [ -n "$DRYRUN" ] ; then
        echo "comment out variable DRYRUN near top of file to write update device"
    else
        echo "uncomment variable DRYRUN near top of file to dry run without updating device"
    fi
    exit
fi


# get the interface on this PC connected to a HomePlug device:
export PLC=$(plcdevs | awk 'NF>3 {print $1}')
if [ -z "$PLC" ]; then
    echo "no homeplug device found - quitting"
    exit
fi

if [ $( int6k -i $PLC -qI local | wc -l ) -ge 2 ]; then
    echo support for this device is not implemented, but probably could be.
    echo this script needs to use int6k & friends
    exit
elif [ $( amptool -i $PLC -qI local | wc -l ) -ge 2 ]; then
    echo support for this device is not implemented, but probably could be.
    echo this script needs to use amptool & friends
    exit
elif [ $( plctool -i $PLC -qI local | wc -l ) -ge 2 ]; then
    echo "the local device uses chipset $(plctool -i $PLC -qr local | awk -F ' ' '{print $3}')"
else
    echo "unable to determine chipset for local HomePlug wall adapter - quitting"
    exit
fi


# get files from command line

if chkpib -q $1; then
    NEWPIBNAME=$1
    echo using pib file $NEWPIBNAME
    NEWPIB=$(mktemp -t XXXXXX.pib)
    cp $NEWPIBNAME $NEWPIB
    chkpib -mv $NEWPIB > $NEWPIB.txt
elif chknvm -q $1; then
    NEWNVMNAME=$1
    echo using nvm file $NEWNVMNAME
    NEWNVM=$(mktemp -t XXXXXX.nvm)
    cp $NEWNVMNAME $NEWNVM
    chknvm -mv $NEWNVM > $NEWNVM.txt
else
    echo $1 is not a pib or nvm file - quitting
    exit
fi


if [ -n "$2" ]; then
    if chkpib -q $2; then
        if [ -n "$NEWPIBNAME" ]; then
            echo cannot have $NEWPIBNAME and $2 both pib files - quitting
            exit
        fi
        NEWPIBNAME=$2
        echo using pib file $NEWPIBNAME
        NEWPIB=$(mktemp -t XXXXXX.pib)
        cp $NEWPIBNAME $NEWPIB
        chkpib -mv $NEWPIB > $NEWPIB.txt
    elif chknvm -q $2; then
        if [ -n "$NEWNVMNAME" ]; then
            echo cannot have $NEWNVMNAME and $2 both nvm files - quitting
            exit
        fi
        NEWNVMNAME=$2
        echo using nvm file $NEWNVMNAME
        NEWNVM=$(mktemp -t XXXXXX.nvm)
        cp $NEWNVMNAME $NEWNVM
        chknvm -mv $NEWNVM > $NEWNVM.txt
    else
        echo $2 is not a valid file - quitting
        exit
    fi
fi


# get MAC address
export MAC=$(plctool -i $PLC -qr | cut -d ' ' -f2)

echo
echo "The Ethernet interface on this PC is $PLC"
echo "The homeplug device MAC address is $MAC"
echo
echo "================================================================================"
echo




# check the pib

if [ -n "$NEWPIB" ]; then
    # read pib from attached device, save it to $DEVPIB
    DEVPIB=$(mktemp -t XXXXXX.pib)
    plctool -i $PLC -p $DEVPIB $MAC

    chkpib -mv $DEVPIB > $DEVPIB.txt
    if [ ! $? ]; then
        echo unable to read parameter information block from device - quitting
        exit
    fi

    echo device has pib
    grep 'Build Description' $DEVPIB.txt


    PIBOPT="-P $NEWPIB"
    if [ "$(grep "Build Version String" $NEWPIB.txt)" = "$(grep "Build Version String" $DEVPIB.txt)" ]; then
        echo $NEWPIBNAME is already programmed into the device
        read  -p  'update PIB anyway? (y/N) '
        #echo reply is \"$REPLY\"
        if [ "$REPLY" = 'y' ] || [ "$REPLY" = 'Y' ]; then
            echo updating device PIB ...
        else
            PIBOPT=""
        fi
    fi

    if [ -n "$PIBOPT" ]; then
        # use modpib() to preserve MAC, DAK & NMK
        # -M mac, -D DAK, -N NMK

        echo MAC is $MAC

        DAK=$(grep DAK $DEVPIB.txt | cut -d ' ' -f2)
        echo DAK is $DAK

        NMK=$(grep NMK $DEVPIB.txt | cut -d ' ' -f2)
        echo NMK is $NMK

        modpib -D $DAK -M $MAC -N $NMK $NEWPIB
        if [ ! $? ]; then
            echo "unable to modify pib - quitting"
            exit
        fi
        #chkpib -mv $NEWPIB > $NEWPIB.txt; kdiff3 --L1 "new" --L2 "existing" $NEWPIB.txt $DEVPIB.txt

        echo successfully generated a new pib for the device
    fi
fi

if [ -n "$NEWNVMNAME" ]; then
    echo -n "existing nvm version is "
    plcstat -i $PLC -t | awk '/LOC/ {print $NF}'

    echo -n "new nvm version is "
    grep -i "Build Version String" $NEWNVM.txt | sed -e 's/[[:space:]]*Build Version String:[[:space:]]*//'
    NVMOPT="-N $NEWNVM"
fi


if [ -n "$NVMOPT" ] || [ -n "$PIBOPT" ]; then
    read  -p  'procede updating homeplug device? (y/N) '
    #echo reply is \"$REPLY\"
    if [ "$REPLY" = 'y' ] || [ "$REPLY" = 'Y' ]; then
        echo updating device ...
    else
        echo quitting
        exit
    fi

    if [ -n "$DRYRUN" ]; then
        echo
        echo "this is a dry run"
        echo "edit variable DRYRUN near top of file $0 to update your device"
        echo
    fi

    if [ -z "$NVMOPT" ] ; then
        echo updating pib only
    elif [ -z "$PIBOPT" ] ; then
        echo updating nvm only
    else
        echo updating pib and nvm
    fi

    $DRYRUN plctool -i $PLC $PIBOPT $NVMOPT $MAC

    # from man plctool:
    # The previous command does not replace existing PIB values.
    # Instead, it appends the new PIB values to the end of the old PIB.
    # To replace existing PIB values, write the same PIB again.
    #
    # from trial & error:
    # the above command resets if there is no PIB.  It doesn't reset if there is,
    # but will reset after a second write of the PIB.
    #
    if [ -n "$PIBOPT" ]; then
        $DRYRUN plctool -i $PLC $PIBOPT $MAC
    fi

    # the device has now reset, wait for it to start up again
    $DRYRUN plcwait -i $PLC -sy

    echo
    echo view \& check result
    $DRYRUN plctool -i $PLC -I $MAC

fi

rm -rf $NEWPIB $NEWPIB.txt $NEWNVM $NEWNVM.txt $DEVPIB $DEVPIB.txt

exit

################## end of update.sh ##################
