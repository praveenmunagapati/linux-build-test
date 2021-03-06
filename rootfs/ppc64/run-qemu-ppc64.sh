#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc64}

mach=$1
variant=$2

# machine specific information
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
# PATH_PPC=/opt/poky/1.6/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PREFIX=powerpc64-poky-linux-
ARCH=powerpc

PATH=${PATH_PPC}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_32="powerpc:qemu_ppc64_book3s_defconfig powerpc:qemu_ppc64_e5500_defconfig"
skip_34="powerpc:qemu_ppc64_e5500_defconfig"
skip_310="powerpc:qemu_ppc64_e5500_defconfig"
skip_312="powerpc:qemu_ppc64_e5500_defconfig"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    if [ "${fixup}" = "devtmpfs" ]
    then
        sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
        echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    elif [ "${fixup}" = "nosmp" ]
    then
        sed -i -e '/CONFIG_SMP/d' ${defconfig}
        echo "# CONFIG_SMP is not set" >> ${defconfig}
    elif [ "${fixup}" = "smp4" ]
    then
        sed -i -e '/CONFIG_SMP/d' ${defconfig}
        sed -i -e '/CONFIG_NR_CPUS/d' ${defconfig}
        echo "CONFIG_SMP=y" >> ${defconfig}
        echo "CONFIG_NR_CPUS=4" >> ${defconfig}
    elif [ "${fixup}" = "smp" ]
    then
        sed -i -e '/CONFIG_SMP/d' ${defconfig}
        echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local machine=$3
    local cpu=$4
    local console=$5
    local kernel=$6
    local rootfs=$7
    local reboot=$8
    local dt=$9
    local pid
    local retcode
    local qemu
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Restarting" "Boot successful" "Rebooting")
    local msg="${ARCH}:${machine}:${defconfig}"

    if [ -n "${fixup}" -a "${fixup}" != "devtmpfs" ]
    then
	msg="${msg}:${fixup}"
    fi

    if [ -n "${mach}" -a "${mach}" != "${machine}" ]
    then
	echo "Skipping ${msg} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${fixup}" != "${variant}" ]
    then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
        if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    dt_cmd=""
    if [ -n "${dt}" ]
    then
        dt_cmd="-machine ${dt}"
    fi

    case "${machine}" in
    mac99)
	# mac99 crashes with qemu v2.7(rc3).
	# v2.6 and v2.8 are ok.
	qemu=${QEMU}
	;;
    mpc8544ds)
	# mpc8544ds may crash with qemu v2.6.x+..v2.7
	qemu=${QEMU}
	;;
    *)
	# pseries works withs with v2.5.x+
	qemu=${QEMU}
	;;
    esac

    ${qemu} -M ${machine} -cpu ${cpu} -m 1024 \
    	-kernel ${kernel} -initrd $(basename ${rootfs}) \
	-nographic -vga none -monitor null -no-reboot \
	--append "rdinit=/sbin/init console=tty console=${console} doreboot" \
	${dt_cmd} > ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} ${reboot} waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_ppc64_book3s_defconfig nosmp mac99 ppc64 ttyS0 vmlinux \
	busybox-powerpc64.img manual
retcode=$?
runkernel qemu_ppc64_book3s_defconfig smp4 mac99 ppc64 ttyS0 vmlinux \
	busybox-powerpc64.img manual
retcode=$((${retcode} + $?))
runkernel pseries_defconfig devtmpfs pseries POWER8 hvc0 vmlinux \
	busybox-powerpc64.img auto
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig nosmp mpc8544ds e5500 ttyS0 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig smp mpc8544ds e5500 ttyS0 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))

exit ${retcode}
