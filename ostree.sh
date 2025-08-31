#!/usr/bin/env bash
set -o errexit   # Sai se houver erro
set -o nounset   # Erro se usar variável não definida

# ========================================================
# [AMBIENTE]: DEFINIÇÃO DE OPÇÕES PADRÃO
# ========================================================
function AMBIENTE_DEFINIR_OPCOES {
    if [[ ${CLI_SILENCIOSO:-} != 1 ]]; then
        set -o xtrace  # Mostra os comandos sendo executados
    fi

    if [[ ! -d '/ostree' ]]; then
        # Não mexer nos discos se o sistema já estiver iniciado
        declare -g DISCO_DESTINO=${DISCO_DESTINO:="/dev/disk/by-id/${DISCO_SCSI}"}
        declare -g PARTICAO_BOOT=${PARTICAO_BOOT:="${DISCO_DESTINO}-part1"}
        declare -g PARTICAO_ROOT=${PARTICAO_ROOT:="${DISCO_DESTINO}-part2"}
        declare -g MONTAGEM_TEMP=${MONTAGEM_TEMP:='/tmp/chroot'}
    fi

    declare -g MONTAGEM_TEMP=${MONTAGEM_TEMP:='/'}
    declare -g ROOTFS_TEMP=${ROOTFS_TEMP:='/tmp/rootfs'}
    declare -g ARG_KERNEL=${ARG_KERNEL:='rootflags=subvol=@ rootfstype=btrfs'}
    declare -g LABEL_BOOT=${LABEL_BOOT:='SYS_BOOT'}
    declare -g LABEL_ROOT=${LABEL_ROOT:='SYS_ROOT'}
    declare -g OPT_NOMERGE=${OPT_NOMERGE='--no-merge'}
    declare -g REPO_NOME=${REPO_NOME:='raglinux'}

    if [[ -n ${FUSO_HORARIO:-} ]]; then
        timedatectl set-timezone ${FUSO_HORARIO}
        timedatectl set-ntp 1
    fi
    declare -g FUSO_HORARIO=${FUSO_HORARIO:='America/Sao_Paulo'}
    declare -g TECLADO=${TECLADO:='br-abnt2'}

    declare -g ARQUIVO_CONTAINER=${ARQUIVO_CONTAINER:="${0%/*}/Containerfile.raglinux:ostree/base"}
    declare -g SEM_CACHE_PODMAN=${SEM_CACHE_PODMAN:='0'}
    declare -g SEM_CACHE_PACMAN=${SEM_CACHE_PACMAN:='0'}
}

# ========================================================
# [AMBIENTE]: VERIFICA OSTREE LOCAL
# ========================================================
function AMBIENTE_VERIFICAR {
    if [[ ! -d '/ostree' ]]; then
        printf >&2 '\e[31m%s\e[0m\n' 'OSTree não encontrado em: /ostree'
        return 1
    fi
}

# ========================================================
# [AMBIENTE]: INSTALAR DEPENDÊNCIAS
# ========================================================
function AMBIENTE_INSTALAR_DEPENDENCIAS {
    # Ignora em OSTree (filesystem read-only)
    if ! AMBIENTE_VERIFICAR 2>/dev/null; then
        pacman --noconfirm --sync --needed "$@"
    fi
}

# ========================================================
# [DISCO]: CRIAR PARTIÇÕES GPT+UEFI
# ========================================================
function DISCO_CRIAR_LAYOUT {
    AMBIENTE_INSTALAR_DEPENDENCIAS parted
    mkdir -p ${MONTAGEM_TEMP}
    lsblk --noheadings --output='MOUNTPOINTS' | grep -w ${MONTAGEM_TEMP} | xargs -r umount --lazy --verbose

    if [[ -b "${PARTICAO_BOOT}" && -b "${PARTICAO_ROOT}" ]]; then
        echo "Partições já existem, pulando criação..."
        return 0
    fi

    parted -a optimal -s ${DISCO_DESTINO} -- \
        mklabel gpt \
        mkpart ${LABEL_BOOT} fat32 0% 257MiB \
        set 1 esp on \
        mkpart ${LABEL_ROOT} btrfs 257MiB 100%
}

# ========================================================
# [DISCO]: FORMATAR PARTIÇÕES
# ========================================================
function DISCO_FORMATAR {
    AMBIENTE_INSTALAR_DEPENDENCIAS dosfstools btrfs-progs
    mkfs.vfat -n ${LABEL_BOOT} -F 32 ${PARTICAO_BOOT}
    mkfs.btrfs -L ${LABEL_ROOT} -f ${PARTICAO_ROOT}
}

# ========================================================
# [DISCO]: MONTAR E CRIAR SUBVOLUMES
# ========================================================
function DISCO_MONTAR {
    mount ${PARTICAO_ROOT} ${MONTAGEM_TEMP}

    btrfs subvolume create ${MONTAGEM_TEMP}/@
    btrfs subvolume create ${MONTAGEM_TEMP}/@home
    btrfs subvolume create ${MONTAGEM_TEMP}/@var
    btrfs subvolume create ${MONTAGEM_TEMP}/@ostree

    umount ${MONTAGEM_TEMP}
    mount -o subvol=@ ${PARTICAO_ROOT} ${MONTAGEM_TEMP}

    mkdir -p ${MONTAGEM_TEMP}/{home,var,ostree}
    mount -o subvol=@home ${PARTICAO_ROOT} ${MONTAGEM_TEMP}/home
    mount -o subvol=@var ${PARTICAO_ROOT} ${MONTAGEM_TEMP}/var
    mount -o subvol=@ostree ${PARTICAO_ROOT} ${MONTAGEM_TEMP}/ostree

    mount --mkdir ${PARTICAO_BOOT} ${MONTAGEM_TEMP}/boot/efi
}

# ========================================================
# [OSTREE]: INICIALIZAÇÃO DO REPOSITÓRIO
# ========================================================
function OSTREE_CRIA_REPO {
    AMBIENTE_INSTALAR_DEPENDENCIAS ostree which
    ostree admin init-fs --sysroot="${MONTAGEM_TEMP}" --modern ${MONTAGEM_TEMP}
    ostree admin stateroot-init --sysroot="${MONTAGEM_TEMP}" ${REPO_NOME}
    ostree init --repo="${MONTAGEM_TEMP}/ostree/repo" --mode='bare'
    ostree config --repo="${MONTAGEM_TEMP}/ostree/repo" set sysroot.bootprefix 1
}

# ========================================================
# [OSTREE]: CRIAR ROOTFS COM PODMAN
# ========================================================
function OSTREE_CRIA_ROOTFS {
    if [[ $(df --output=fstype / | tail --lines 1) = 'overlay' ]]; then
        AMBIENTE_INSTALAR_DEPENDENCIAS fuse-overlayfs
        declare -x TMPDIR='/tmp/podman'
        local OPT_PODMAN_GLOBAL=(
            --root="${TMPDIR}/storage"
            --tmpdir="${TMPDIR}/tmp"
        )
    fi

    AMBIENTE_INSTALAR_DEPENDENCIAS podman

    if [[ ${SEM_CACHE_PACMAN} == 0 ]]; then
        mkdir -p "${TMPDIR:-}/var/cache/pacman"
        local OPT_PODMAN_BUILD=(
            --volume="${TMPDIR:-}/var/cache/pacman:${TMPDIR:-}/var/cache/pacman"
        )
    fi

    if [[ ${SEM_CACHE_PODMAN} == 1 ]]; then
        local OPT_PODMAN_BUILD=(
            ${OPT_PODMAN_BUILD[@]}
            --no-cache='1'
        )
    fi

    for TARGET in ${ARQUIVO_CONTAINER//,/ }; do
        local IMG=${TARGET%:*}
        local TAG=${TARGET#*:}
        podman ${OPT_PODMAN_GLOBAL[@]} build \
            ${OPT_PODMAN_BUILD[@]} \
            --file="${IMG}" \
            --tag="${TAG}" \
            --cap-add='SYS_ADMIN' \
            --build-arg="LABEL_BOOT=${LABEL_BOOT}" \
            --build-arg="LABEL_ROOT=${LABEL_ROOT}" \
            --build-arg="FUSO_HORARIO=${FUSO_HORARIO}" \
            --build-arg="TECLADO=${TECLADO}" \
            --pull='newer'
    done

    rm -rf ${ROOTFS_TEMP}
    mkdir -p ${ROOTFS_TEMP}
    podman ${OPT_PODMAN_GLOBAL[@]} export $(podman ${OPT_PODMAN_GLOBAL[@]} create ${TAG} bash) | tar -xC ${ROOTFS_TEMP}
}

# ========================================================
# [OSTREE]: AJUSTAR ESTRUTURA DE DIRETÓRIOS
# ========================================================
function OSTREE_AJUSTAR_LAYOUT {
    mv ${ROOTFS_TEMP}/etc ${ROOTFS_TEMP}/usr/

    rm -r ${ROOTFS_TEMP}/home
    ln -s var/home ${ROOTFS_TEMP}/home

    rm -r ${ROOTFS_TEMP}/mnt
    ln -s var/mnt ${ROOTFS_TEMP}/mnt

    rm -r ${ROOTFS_TEMP}/opt
    ln -s var/opt ${ROOTFS_TEMP}/opt

    rm -r ${ROOTFS_TEMP}/root
    ln -s var/roothome ${ROOTFS_TEMP}/root

    rm -r ${ROOTFS_TEMP}/srv
    ln -s var/srv ${ROOTFS_TEMP}/srv

    mkdir ${ROOTFS_TEMP}/sysroot
    ln -s sysroot/ostree ${ROOTFS_TEMP}/ostree

    rm -r ${ROOTFS_TEMP}/usr/local
    ln -s ../var/usrlocal ${ROOTFS_TEMP}/usr/local

    printf >&1 '%s\n' 'Criando tmpfiles'
    cat <<EOF >> ${ROOTFS_TEMP}/usr/lib/tmpfiles.d/ostree-0-integracao.conf
d /var/home 0755 root root -
d /var/lib 0755 root root -
d /var/log/journal 0755 root root -
d /var/mnt 0755 root root -
d /var/opt 0755 root root -
d /var/roothome 0700 root root -
d /var/srv 0755 root root -
d /var/usrlocal 0755 root root -
d /var/usrlocal/bin 0755 root root -
d /var/usrlocal/etc 0755 root root -
d /var/usrlocal/games 0755 root root -
d /var/usrlocal/include 0755 root root -
d /var/usrlocal/lib 0755 root root -
d /var/usrlocal/man 0755 root root -
d /var/usrlocal/sbin 0755 root root -
d /var/usrlocal/share 0755 root root -
d /var/usrlocal/src 0755 root root -
d /run/media 0755 root root -
EOF

    mv ${ROOTFS_TEMP}/var/lib/pacman ${ROOTFS_TEMP}/usr/lib/
    sed -i \
        -e 's|^#\(DBPath\s*=\s*\).*|\1/usr/lib/pacman|g' \
        -e 's|^#\(IgnoreGroup\s*=\s*\).*|\1modified|g' \
        ${ROOTFS_TEMP}/usr/etc/pacman.conf

    mkdir ${ROOTFS_TEMP}/usr/lib/pacmanlocal
    rm -r ${ROOTFS_TEMP}/var/*
}

# ========================================================
# [OSTREE]: CRIAR COMMIT
# ========================================================
function OSTREE_DEPLOY {
    ostree commit --repo="${MONTAGEM_TEMP}/ostree/repo" --branch="${REPO_NOME}/latest" --tree=dir="${ROOTFS_TEMP}"
    ostree admin deploy --sysroot="${MONTAGEM_TEMP}" --karg="root=LABEL=${LABEL_ROOT} rw ${ARG_KERNEL}" --os="${REPO_NOME}" ${OPT_NOMERGE} --retain ${REPO_NOME}/latest
}

# ========================================================
# [OSTREE]: REVER COMMIT
# ========================================================
function OSTREE_REVER {
    ostree admin undeploy --sysroot="${MONTAGEM_TEMP}" 0
}

# ========================================================
# [BOOTLOADER]: CONFIGURAR GRUB EFI
# ========================================================
function BOOTLOADER_CONFIG {
    grub-install --target='x86_64-efi' --efi-directory="${MONTAGEM_TEMP}/boot/efi" --boot-directory="${MONTAGEM_TEMP}/boot/efi/EFI" --bootloader-id="${REPO_NOME}" --removable ${PARTICAO_BOOT}

    local CAMINHO_SYS=$(ls -d ${MONTAGEM_TEMP}/ostree/deploy/${REPO_NOME}/deploy/* | head -n 1)

    rm -rfv ${CAMINHO_SYS}/boot/*
    mount --mkdir --rbind ${MONTAGEM_TEMP}/boot ${CAMINHO_SYS}/boot
    mount --mkdir --rbind ${MONTAGEM_TEMP}/ostree ${CAMINHO_SYS}/sysroot/ostree

    for i in /dev /proc /sys; do mount -o bind $i ${CAMINHO_SYS}${i}; done
    chroot ${CAMINHO_SYS} /bin/bash -c 'grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg'

    umount --recursive ${MONTAGEM_TEMP}
}

# ========================================================
# [CLI]: INTERPRETAÇÃO DE ARGUMENTOS
# ========================================================
function CLI_EXECUTAR {
    CLI_ARGS=$(getopt \
        --alternative \
        --options='b:,c:,d:,f:,k:,t:,m::,n::,q::' \
        --longoptions='base-os:,cmdline:,dev:,file:,keymap:,time:,merge::,no-cache::,no-pacman-cache::,no-podman-cache::,quiet::' \
        --name="${0##*/}" \
        -- "${@}"
    )

    eval set -- "${CLI_ARGS}"

    while [[ ${#} > 0 ]]; do
        CLI_ARG=${1:-}
        CLI_VAL=${2:-}

        case ${CLI_ARG} in
            '-b' | '--base-os') REPO_NOME=${CLI_VAL} ;;
            '-c' | '--cmdline') ARG_KERNEL=${CLI_VAL} ;;
            '-d' | '--dev') DISCO_SCSI=${CLI_VAL} ;;
            '-f' | '--file') ARQUIVO_CONTAINER=${CLI_VAL} ;;
            '-k' | '--keymap') TECLADO=${CLI_VAL} ;;
            '-t' | '--time') FUSO_HORARIO=${CLI_VAL} ;;
        esac

        [[ ${CLI_VAL@L} == 'true' ]] && CLI_VAL='1'
        [[ ${CLI_VAL@L} == 'false' ]] && CLI_VAL='0'
        case ${CLI_ARG} in
            '-m' | '--merge') OPT_NOMERGE=${CLI_VAL:-} ;;
            '-n' | '--no-cache') SEM_CACHE_PACMAN=${CLI_VAL:-1}; SEM_CACHE_PODMAN=${CLI_VAL:-1} ;;
            '--no-pacman-cache') SEM_CACHE_PACMAN=${CLI_VAL:-1} ;;
            '--no-podman-cache') SEM_CACHE_PODMAN=${CLI_VAL:-1} ;;
            '-q' | '--quiet') CLI_SILENCIOSO=${CLI_VAL:-1} ;;
        esac

        if [[ ${CLI_ARG} == '--' ]]; then
            case ${CLI_VAL} in
                'install')
                    AMBIENTE_DEFINIR_OPCOES
                    DISCO_CRIAR_LAYOUT
                    DISCO_FORMATAR
                    DISCO_MONTAR
                    OSTREE_CRIA_REPO
                    OSTREE_CRIA_ROOTFS
                    OSTREE_AJUSTAR_LAYOUT
                    OSTREE_DEPLOY
                    BOOTLOADER_CONFIG
                ;;
                'upgrade')
                    AMBIENTE_VERIFICAR || exit $?
                    AMBIENTE_DEFINIR_OPCOES
                    OSTREE_CRIA_ROOTFS
                    OSTREE_AJUSTAR_LAYOUT
                    OSTREE_DEPLOY
                ;;
                'revert')
                    AMBIENTE_VERIFICAR || exit $?
                    AMBIENTE_DEFINIR_OPCOES
                    OSTREE_REVER
                ;;
                *)
                    if [[ $(type -t ${CLI_VAL}) == 'function' ]]; then
                        AMBIENTE_DEFINIR_OPCOES
                        ${CLI_VAL}
                    fi
                ;;&
                * | 'help')
                    local AJUDA=(
                        'Uso:'
                        "  ${0##*/} <comando|funcao> [opcoes]"
                        'Comandos:'
                        '  install : (Criar deploy) : Particiona, formata e inicializa OSTree'
                        '  upgrade : (Atualizar deploy) : Cria novo commit OSTree'
                        '  revert  : (Reverter commit) : Restaura versão 0'
                        'Opções:'
                        '  -b, --base-os string      : (install/upgrade) : Nome do OS base. Padrão: raglinux'
                        '  -c, --cmdline string      : (install/upgrade) : Argumentos do kernel'
                        '  -d, --dev     string      : (install        ) : ID do disco para instalação'
                        '  -f, --file    stringArray : (install/upgrade) : Containerfile(s)'
                        '  -k, --keymap  string      : (install/upgrade) : Layout teclado'
                        '  -t, --time    string      : (install/upgrade) : Fuso horário host'
                        'Switches:'
                        '  -m, --merge               : (        upgrade) : Manter /etc existente'
                        '  -n, --no-cache            : (install/upgrade) : Ignora cache'
                        '      --no-pacman-cache     : (install/upgrade) : Ignora cache Pacman'
                        '      --no-podman-cache     : (install/upgrade) : Ignora cache Podman'
                        '  -q, --quiet               : (install/upgrade) : Reduz verbosidade'
                    )
                    printf >&1 '%s\n' "${AJUDA[@]}"

                    if [[ ${CLI_VAL} != 'help' && -n ${CLI_VAL} ]]; then
                        printf >&2 '\n%s\n' "${0##*/}: comando desconhecido '${CLI_VAL}'"
                        exit 127
                    fi
                ;;
            esac
            break
        fi

        shift 2
    done
}

CLI_EXECUTAR "${@}"
