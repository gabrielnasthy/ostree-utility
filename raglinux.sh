#!/usr/bin/env bash
set -o errexit # Exit on non-zero status
set -o nounset # Error on unset variables

# [ENVIRONMENT]: OVERRIDE DEFAULTS
function ENV_CREATE_OPTS {
    if [[ ${CLI_QUIET:-} != 1 ]]; then
        set -o xtrace # Print executed commands while performing tasks
    fi

    if [[ ! -d '/ostree' ]]; then
        # Do not touch disks in a booted system:
        declare -g OSTREE_DEV_DISK=${OSTREE_DEV_DISK:="/dev/disk/by-id/${OSTREE_DEV_SCSI}"}
        declare -g OSTREE_DEV_BOOT=${OSTREE_DEV_BOOT:="${OSTREE_DEV_DISK}-part1"}
        declare -g OSTREE_DEV_ROOT=${OSTREE_DEV_ROOT:="${OSTREE_DEV_DISK}-part2"}
        declare -g OSTREE_SYS_ROOT=${OSTREE_SYS_ROOT:='/tmp/chroot'}
    fi

    declare -g OSTREE_SYS_ROOT=${OSTREE_SYS_ROOT:='/'}
    declare -g OSTREE_SYS_TREE=${OSTREE_SYS_TREE:='/tmp/rootfs'}
    declare -g OSTREE_SYS_KARG=${OSTREE_SYS_KARG:=''}
    declare -g OSTREE_SYS_BOOT_LABEL=${OSTREE_SYS_BOOT_LABEL:='SYS_BOOT'}
    declare -g OSTREE_SYS_ROOT_LABEL=${OSTREE_SYS_ROOT_LABEL:='SYS_ROOT'}
    declare -g OSTREE_OPT_NOMERGE=${OSTREE_OPT_NOMERGE='--no-merge'}
    declare -g OSTREE_REP_NAME=${OSTREE_REP_NAME:='archlinux'}

    # Timezone and Keymap are now hardcoded in Containerfile.base
    # and no longer need to be set here.

    declare -g PODMAN_OPT_BUILDFILE=${PODMAN_OPT_BUILDFILE:="${0%/*}/Containerfile.base:ostree/base","${0%/*}/Containerfile.host.example:ostree/host"}
    declare -g PODMAN_OPT_NOCACHE=${PODMAN_OPT_NOCACHE:='0'}
    declare -g PACMAN_OPT_NOCACHE=${PACMAN_OPT_NOCACHE:='0'}
}


# [ENVIRONMENT]: OSTREE CHECK
function ENV_VERIFY_LOCAL {
    if [[ ! -d '/ostree' ]]; then
        printf >&2 '\e[31m%s\e[0m\n' 'OSTree could not be found in: /ostree'
        return 1
    fi
}

# [ENVIRONMENT]: BUILD DEPENDENCIES
function ENV_CREATE_DEPS {
    # Skip in OSTree as filesystem is read-only
    if ! ENV_VERIFY_LOCAL 2>/dev/null; then
        pacman --noconfirm --sync --needed $@
    fi
}

# [DISK]: PARTITIONING (GPT+UEFI) for Btrfs
function DISK_CREATE_LAYOUT {
    ENV_CREATE_DEPS parted
    mkdir -p ${OSTREE_SYS_ROOT}
    lsblk --noheadings --output='MOUNTPOINTS' | grep -w ${OSTREE_SYS_ROOT} | xargs -r umount --lazy --verbose
    parted -a optimal -s ${OSTREE_DEV_DISK} -- \
        mklabel gpt \
        mkpart ${OSTREE_SYS_BOOT_LABEL} fat32 0% 257MiB \
        set 1 esp on \
        mkpart ${OSTREE_SYS_ROOT_LABEL} btrfs 257MiB 100%
}

# [DISK]: FILESYSTEM (ESP+Btrfs) with Subvolumes
function DISK_CREATE_FORMAT {
    ENV_CREATE_DEPS dosfstools btrfs-progs
    mkfs.vfat -n ${OSTREE_SYS_BOOT_LABEL} -F 32 ${OSTREE_DEV_BOOT}
    mkfs.btrfs -L ${OSTREE_SYS_ROOT_LABEL} -f ${OSTREE_DEV_ROOT}

    # Create Btrfs subvolumes for root and home
    mount ${OSTREE_DEV_ROOT} ${OSTREE_SYS_ROOT}
    btrfs subvolume create ${OSTREE_SYS_ROOT}/@
    btrfs subvolume create ${OSTREE_SYS_ROOT}/@home
    umount ${OSTREE_SYS_ROOT}
}

# [DISK]: BUILD DIRECTORY with Btrfs Subvolumes
function DISK_CREATE_MOUNTS {
    # Mount root subvolume
    mount -o compress=zstd,subvol=@ ${OSTREE_DEV_ROOT} ${OSTREE_SYS_ROOT}
    # Mount boot partition
    mount --mkdir ${OSTREE_DEV_BOOT} ${OSTREE_SYS_ROOT}/boot/efi
    # Mount home subvolume
    mkdir -p ${OSTREE_SYS_ROOT}/home
    mount -o compress=zstd,subvol=@home ${OSTREE_DEV_ROOT} ${OSTREE_SYS_ROOT}/home
}

# [OSTREE]: FIRST INITIALIZATION
function OSTREE_CREATE_REPO {
    ENV_CREATE_DEPS ostree which
    ostree admin init-fs --sysroot="${OSTREE_SYS_ROOT}" --modern ${OSTREE_SYS_ROOT}
    ostree admin stateroot-init --sysroot="${OSTREE_SYS_ROOT}" ${OSTREE_REP_NAME}
    ostree init --repo="${OSTREE_SYS_ROOT}/ostree/repo" --mode='bare'
    ostree config --repo="${OSTREE_SYS_ROOT}/ostree/repo" set sysroot.bootprefix 1
}

# [OSTREE]: BUILD ROOTFS
function OSTREE_CREATE_ROOTFS {
    # Add support for overlay storage driver in LiveCD
    if [[ $(df --output=fstype / | tail --lines 1) = 'overlay' ]]; then
        ENV_CREATE_DEPS fuse-overlayfs
        declare -x TMPDIR='/tmp/podman'
        local PODMAN_OPT_GLOBAL=(
            --root="${TMPDIR}/storage"
            --tmpdir="${TMPDIR}/tmp"
        )
    fi

    # Install Podman
    ENV_CREATE_DEPS podman

    # Copy Pacman package cache into /var by default (
