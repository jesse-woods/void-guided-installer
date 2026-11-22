#!/bin/bash
#-
# Copyright (c) 2012-2015 Juan Romero Pardines <xtraeme@gmail.com>.
#               2012 Dave Elusive <davehome@redthumb.info.tm>.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-

# Make sure we don't inherit these from env.
SOURCE_DONE=
HOSTNAME_DONE=
KEYBOARD_DONE=
LOCALE_DONE=
TIMEZONE_DONE=
ROOTPASSWORD_DONE=
USERLOGIN_DONE=
USERPASSWORD_DONE=
USERNAME_DONE=
USERGROUPS_DONE=
USERACCOUNT_DONE=
BOOTLOADER_DONE=
PARTITIONS_DONE=
NETWORK_DONE=
FILESYSTEMS_DONE=
MIRROR_DONE=
GUIDED_DISK=
GUIDED_DISK_DETAILS=
GUIDED_ENCRYPTION=
GUIDED_SWAP_GIB=0
GUIDED_STARTED=
GUIDED_SWAP_PARTUUID=
GUIDED_MAPPER_OPEN=
GUIDED_LUKS_UUID=

TARGETDIR=/mnt/target
LOG=/dev/tty8
CONF_FILE=$(mktemp -t vinstall-conf-XXXXXXXX || exit 1)
ANSWER=$(mktemp -t vinstall-XXXXXXXX || exit 1)
TARGET_SERVICES=$(mktemp -t vinstall-sv-XXXXXXXX || exit 1)
TARGET_FSTAB=$(mktemp -t vinstall-fstab-XXXXXXXX || exit 1)

trap "DIE" INT TERM QUIT

# disable printk
if [ -w /proc/sys/kernel/printk ]; then
    echo 0 >/proc/sys/kernel/printk
fi

# Detect if this is an EFI system.
if [ -e /sys/firmware/efi/systab ]; then
    EFI_SYSTEM=1
    EFI_FW_BITS=$(cat /sys/firmware/efi/fw_platform_size)
    if [ $EFI_FW_BITS -eq 32 ]; then
        EFI_TARGET=i386-efi
    else
        EFI_TARGET=x86_64-efi
    fi
fi

# dialog colors
BLACK="\Z0"
RED="\Z1"
GREEN="\Z2"
YELLOW="\Z3"
BLUE="\Z4"
MAGENTA="\Z5"
CYAN="\Z6"
WHITE="\Z7"
BOLD="\Zb"
REVERSE="\Zr"
UNDERLINE="\Zu"
RESET="\Zn"

# Properties shared per widget.
MENULABEL="${BOLD}Use UP and DOWN keys to navigate \
menus. Use TAB to switch between buttons and ENTER to select.${RESET}"
MENUSIZE="14 60 0"
INPUTSIZE="8 60"
MSGBOXSIZE="8 70"
YESNOSIZE="$INPUTSIZE"
WIDGET_SIZE="10 70"

DIALOG() {
    : >"$ANSWER"
    dialog --colors --keep-tite --no-shadow --no-mouse \
        --backtitle "${BOLD}${WHITE}Void Linux installation -- https://www.voidlinux.org (@@MKLIVE_VERSION@@)${RESET}" \
        --cancel-label "Back" --aspect 20 "$@" 2>$ANSWER
    return $?
}

INFOBOX() {
    # Note: dialog --infobox and --keep-tite don't work together
    dialog --colors --no-shadow --no-mouse \
        --backtitle "${BOLD}${WHITE}Void Linux installation -- https://www.voidlinux.org (@@MKLIVE_VERSION@@)${RESET}" \
        --title "${TITLE}" --aspect 20 --infobox "$@"
}

DIE() {
    rval=$1
    [ -z "$rval" ] && rval=0
    clear
    rm -f "$ANSWER" "$TARGET_FSTAB" "$TARGET_SERVICES"
    # reenable printk
    if [ -w /proc/sys/kernel/printk ]; then
        echo 4 >/proc/sys/kernel/printk
    fi
    umount_filesystems
    rm -f "$CONF_FILE"
    exit $rval
}

set_option() {
    if grep -Eq "^${1} .*" $CONF_FILE; then
        sed -i -e "/^${1} .*/d" $CONF_FILE
    fi
    echo "${1} ${2}" >>$CONF_FILE
}

get_option() {
    grep -E "^${1} .*" $CONF_FILE | sed -e "s|^${1} ||"
}

# ISO-639 language names for locales
iso639_language() {
    case "$1" in
    aa)  echo "Afar" ;;
    af)  echo "Afrikaans" ;;
    an)  echo "Aragonese" ;;
    ar)  echo "Arabic" ;;
    ast) echo "Asturian" ;;
    be)  echo "Belarusian" ;;
    bg)  echo "Bulgarian" ;;
    bhb) echo "Bhili" ;;
    br)  echo "Breton" ;;
    bs)  echo "Bosnian" ;;
    ca)  echo "Catalan" ;;
    cs)  echo "Czech" ;;
    cy)  echo "Welsh" ;;
    da)  echo "Danish" ;;
    de)  echo "German" ;;
    el)  echo "Greek" ;;
    en)  echo "English" ;;
    es)  echo "Spanish" ;;
    et)  echo "Estonian" ;;
    eu)  echo "Basque" ;;
    fi)  echo "Finnish" ;;
    fo)  echo "Faroese" ;;
    fr)  echo "French" ;;
    ga)  echo "Irish" ;;
    gd)  echo "Scottish Gaelic" ;;
    gl)  echo "Galician" ;;
    gv)  echo "Manx" ;;
    he)  echo "Hebrew" ;;
    hr)  echo "Croatian" ;;
    hsb) echo "Upper Sorbian" ;;
    hu)  echo "Hungarian" ;;
    id)  echo "Indonesian" ;;
    is)  echo "Icelandic" ;;
    it)  echo "Italian" ;;
    iw)  echo "Hebrew" ;;
    ja)  echo "Japanese" ;;
    ka)  echo "Georgian" ;;
    kk)  echo "Kazakh" ;;
    kl)  echo "Kalaallisut" ;;
    ko)  echo "Korean" ;;
    ku)  echo "Kurdish" ;;
    kw)  echo "Cornish" ;;
    lg)  echo "Ganda" ;;
    lt)  echo "Lithuanian" ;;
    lv)  echo "Latvian" ;;
    mg)  echo "Malagasy" ;;
    mi)  echo "Maori" ;;
    mk)  echo "Macedonian" ;;
    ms)  echo "Malay" ;;
    mt)  echo "Maltese" ;;
    nb)  echo "Norwegian Bokmål" ;;
    nl)  echo "Dutch" ;;
    nn)  echo "Norwegian Nynorsk" ;;
    oc)  echo "Occitan" ;;
    om)  echo "Oromo" ;;
    pl)  echo "Polish" ;;
    pt)  echo "Portuguese" ;;
    ro)  echo "Romanian" ;;
    ru)  echo "Russian" ;;
    sk)  echo "Slovak" ;;
    sl)  echo "Slovenian" ;;
    so)  echo "Somali" ;;
    sq)  echo "Albanian" ;;
    st)  echo "Southern Sotho" ;;
    sv)  echo "Swedish" ;;
    tcy) echo "Tulu" ;;
    tg)  echo "Tajik" ;;
    th)  echo "Thai" ;;
    tl)  echo "Tagalog" ;;
    tr)  echo "Turkish" ;;
    uk)  echo "Ukrainian" ;;
    uz)  echo "Uzbek" ;;
    wa)  echo "Walloon" ;;
    xh)  echo "Xhosa" ;;
    yi)  echo "Yiddish" ;;
    zh)  echo "Chinese" ;;
    zu)  echo "Zulu" ;;
    *)   echo "$1" ;;
    esac
}

# ISO-3166 country codes for locales
iso3166_country() {
    case "$1" in
    AD) echo "Andorra" ;;
    AE) echo "United Arab Emirates" ;;
    AL) echo "Albania" ;;
    AR) echo "Argentina" ;;
    AT) echo "Austria" ;;
    AU) echo "Australia" ;;
    BA) echo "Bosnia and Herzegovina" ;;
    BE) echo "Belgium" ;;
    BG) echo "Bulgaria" ;;
    BH) echo "Bahrain" ;;
    BO) echo "Bolivia" ;;
    BR) echo "Brazil" ;;
    BW) echo "Botswana" ;;
    BY) echo "Belarus" ;;
    CA) echo "Canada" ;;
    CH) echo "Switzerland" ;;
    CL) echo "Chile" ;;
    CN) echo "China" ;;
    CO) echo "Colombia" ;;
    CR) echo "Costa Rica" ;;
    CY) echo "Cyprus" ;;
    CZ) echo "Czech Republic" ;;
    DE) echo "Germany" ;;
    DJ) echo "Djibouti" ;;
    DK) echo "Denmark" ;;
    DO) echo "Dominican Republic" ;;
    DZ) echo "Algeria" ;;
    EC) echo "Ecuador" ;;
    EE) echo "Estonia" ;;
    EG) echo "Egypt" ;;
    ES) echo "Spain" ;;
    FI) echo "Finland" ;;
    FO) echo "Faroe Islands" ;;
    FR) echo "France" ;;
    GB) echo "Great Britain" ;;
    GE) echo "Georgia" ;;
    GL) echo "Greenland" ;;
    GR) echo "Greece" ;;
    GT) echo "Guatemala" ;;
    HK) echo "Hong Kong" ;;
    HN) echo "Honduras" ;;
    HR) echo "Croatia" ;;
    HU) echo "Hungary" ;;
    ID) echo "Indonesia" ;;
    IE) echo "Ireland" ;;
    IL) echo "Israel" ;;
    IN) echo "India" ;;
    IQ) echo "Iraq" ;;
    IS) echo "Iceland" ;;
    IT) echo "Italy" ;;
    JO) echo "Jordan" ;;
    JP) echo "Japan" ;;
    KE) echo "Kenya" ;;
    KR) echo "Korea, Republic of" ;;
    KW) echo "Kuwait" ;;
    KZ) echo "Kazakhstan" ;;
    LB) echo "Lebanon" ;;
    LT) echo "Lithuania" ;;
    LU) echo "Luxembourg" ;;
    LV) echo "Latvia" ;;
    LY) echo "Libya" ;;
    MA) echo "Morocco" ;;
    MG) echo "Madagascar" ;;
    MK) echo "Macedonia" ;;
    MT) echo "Malta" ;;
    MX) echo "Mexico" ;;
    MY) echo "Malaysia" ;;
    NI) echo "Nicaragua" ;;
    NL) echo "Netherlands" ;;
    NO) echo "Norway" ;;
    NZ) echo "New Zealand" ;;
    OM) echo "Oman" ;;
    PA) echo "Panama" ;;
    PE) echo "Peru" ;;
    PH) echo "Philippines" ;;
    PL) echo "Poland" ;;
    PR) echo "Puerto Rico" ;;
    PT) echo "Portugal" ;;
    PY) echo "Paraguay" ;;
    QA) echo "Qatar" ;;
    RO) echo "Romania" ;;
    RU) echo "Russian Federation" ;;
    SA) echo "Saudi Arabia" ;;
    SD) echo "Sudan" ;;
    SE) echo "Sweden" ;;
    SG) echo "Singapore" ;;
    SI) echo "Slovenia" ;;
    SK) echo "Slovakia" ;;
    SO) echo "Somalia" ;;
    SV) echo "El Salvador" ;;
    SY) echo "Syria" ;;
    TH) echo "Thailand" ;;
    TJ) echo "Tajikistan" ;;
    TN) echo "Tunisia" ;;
    TR) echo "Turkey" ;;
    TW) echo "Taiwan" ;;
    UA) echo "Ukraine" ;;
    UG) echo "Uganda" ;;
    US) echo "United States of America" ;;
    UY) echo "Uruguay" ;;
    UZ) echo "Uzbekistan" ;;
    VE) echo "Venezuela" ;;
    YE) echo "Yemen" ;;
    ZA) echo "South Africa" ;;
    ZW) echo "Zimbabwe" ;;
    *)  echo "$1" ;;
    esac
}

show_disks() {
    local dev size sectorsize gbytes

    # IDE
    for dev in $(ls /sys/block|grep -E '^hd'); do
        if [ "$(cat /sys/block/$dev/device/media)" = "disk" ]; then
            # Find out nr sectors and bytes per sector;
            echo "/dev/$dev"
            size=$(cat /sys/block/$dev/size)
            sectorsize=$(cat /sys/block/$dev/queue/hw_sector_size)
            gbytes="$(($size * $sectorsize / 1024 / 1024 / 1024))"
            echo "size:${gbytes}GB;sector_size:$sectorsize"
        fi
    done
    # SATA/SCSI and Virtual disks (virtio)
    for dev in $(ls /sys/block|grep -E '^([sv]|xv)d|mmcblk|nvme'); do
        echo "/dev/$dev"
        size=$(cat /sys/block/$dev/size)
        sectorsize=$(cat /sys/block/$dev/queue/hw_sector_size)
        gbytes="$(($size * $sectorsize / 1024 / 1024 / 1024))"
        echo "size:${gbytes}GB;sector_size:$sectorsize"
    done
    # cciss(4) devices
    for dev in $(ls /dev/cciss 2>/dev/null|grep -E 'c[0-9]d[0-9]$'); do
        echo "/dev/cciss/$dev"
        size=$(cat /sys/block/cciss\!$dev/size)
        sectorsize=$(cat /sys/block/cciss\!$dev/queue/hw_sector_size)
        gbytes="$(($size * $sectorsize / 1024 / 1024 / 1024))"
        echo "size:${gbytes}GB;sector_size:$sectorsize"
    done
}

guided_supported() {
    [ "$EFI_TARGET" = x86_64-efi ] && [ "$(xbps-uhelper arch)" = x86_64 ]
}

# Allow existing partitions, but keep mounted, swap, mapped, RAID and live
# media devices out of the erase-disk menu. Recheck before changing the disk.
guided_disk_details() {
    local disk=$1 details devno bytes diskseq signatures mounted_btrfs
    [ -b "$disk" ] || return 1
    # A mounted multi-device Btrfs filesystem may report only one mount source.
    mounted_btrfs=$(findmnt -rn -t btrfs -o UUID || :)
    details=$(lsblk --json --bytes --paths --output \
        NAME,TYPE,RO,SIZE,MOUNTPOINTS,MAJ:MIN,FSTYPE,UUID -- "$disk" |
        jq -er --arg mounted_btrfs "$mounted_btrfs" '
            ($mounted_btrfs | split("\n")) as $active_btrfs |
            .blockdevices | select(length == 1) | .[0]
            | select(.type == "disk" and .ro == false and .size >= 8589934592)
            | select(all(recurse(.children[]?);
                (.type == "disk" or .type == "part") and
                (all(.mountpoints[]?; . == null or . == "")) and
                (.fstype != "iso9660" and .fstype != "udf") and
                (.fstype != "btrfs" or (.uuid as $uuid | $active_btrfs | index($uuid) == null))))
            | "\(.["maj:min"]) \(.size)"
        ') || return 1
    read -r devno bytes <<<"$details"
    diskseq=$(cat "/sys/dev/block/$devno/diskseq") || return 1
    signatures=$(wipefs --no-act --noheadings --output TYPE -- "$disk") || return 1
    if grep -Eq '(^|[[:space:]])(iso9660|udf)($|[[:space:]])' <<<"$signatures"; then
        return 1
    fi
    printf '%s:%s %s\n' "$devno" "$diskseq" "$bytes"
}

menu_guided_storage() {
    local disk details bytes encryption swap_gib=0 max_swap
    local -a choices=()
    while read -r disk; do
        guided_disk_details "$disk" >/dev/null 2>&1 || continue
        choices+=("$disk" "$(lsblk -dno SIZE,MODEL,TRAN -- "$disk")")
    done < <(lsblk -dnpo NAME)
    if [ "${#choices[@]}" -eq 0 ]; then
        DIALOG --msgbox "No eligible disk. Guided needs a writable disk of at least 8 GiB with nothing mounted or active on it." ${MSGBOXSIZE}
        return 1
    fi
    DIALOG --title " Guided whole-disk installation " --menu \
        "Select the disk to erase. All existing partitions on it will be replaced at installation." \
        ${MENUSIZE} "${choices[@]}" || return 1
    disk=$(cat "$ANSWER")
    details=$(guided_disk_details "$disk" 2>>"$LOG") || return 1
    bytes=${details##* }

    DIALOG --title " Disk encryption " --menu \
        "Encryption protects Btrfs and swap. The EFI partition and /boot are unencrypted." \
        ${MENUSIZE} "LUKS2" "Unlock with a passphrase at boot" "None" "Install without encryption" ||
        return 1
    encryption=$(cat "$ANSWER")

    max_swap=$((bytes / (1024 * 1024 * 1024) - 8))
    if (( max_swap > 0 )); then
        DIALOG --title " Swap partition " --menu \
            "A swap partition is optional. Hibernation is not configured." ${MENUSIZE} \
            "None" "Install without swap" "Partition" "Choose a size in GiB" || return 1
        if [ "$(cat "$ANSWER")" = Partition ]; then
            local default_swap=4
            (( max_swap >= default_swap )) || default_swap=$max_swap
            while true; do
                DIALOG --inputbox "Swap size in GiB (1 to $max_swap):" \
                    ${INPUTSIZE} "$default_swap" || return 1
                swap_gib=$(cat "$ANSWER")
                if [[ "$swap_gib" =~ ^[1-9][0-9]{0,8}$ ]] && (( swap_gib <= max_swap )); then
                    break
                fi
                DIALOG --msgbox "Enter a whole number between 1 and $max_swap." ${MSGBOXSIZE}
            done
        fi
    fi

    GUIDED_DISK=$disk
    GUIDED_DISK_DETAILS=$details
    GUIDED_ENCRYPTION=$encryption
    GUIDED_SWAP_GIB=$swap_gib
}

guided_error() {
    DIALOG --msgbox "$1
See $LOG for details." ${MSGBOXSIZE}
    DIE 1
}

guided_partition_table() {
    printf '%s\n' 'label: gpt' \
        'size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' \
        'size=2GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4'
    if (( GUIDED_SWAP_GIB > 0 )); then
        if [ "$GUIDED_ENCRYPTION" = LUKS2 ]; then
            printf 'size=%sGiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n' "$GUIDED_SWAP_GIB"
        else
            printf 'size=%sGiB, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F\n' "$GUIDED_SWAP_GIB"
        fi
    fi
    if [ "$GUIDED_ENCRYPTION" = LUKS2 ]; then
        printf '%s\n' 'type=CA7D7CCB-63ED-4C53-861C-1742536059CC'
    else
        printf '%s\n' 'type=0FC63DAF-8483-4772-8E79-3D69D8477DE4'
    fi
}

guided_filesystems() {
    local disk=$GUIDED_DISK details efi boot swap root root_device device number third fourth
    local passphrase repeated root_uuid boot_uuid efi_uuid swap_uuid
    local mapper=/dev/mapper/void-root

    if [ "$GUIDED_ENCRYPTION" = LUKS2 ]; then
        # Route the result through a pipe and draw dialog directly on the terminal.
        passphrase=$(DIALOG --output-fd 3 --passwordbox \
            "Enter the passphrase for the encrypted system:" ${INPUTSIZE} \
            3>&1 >/dev/tty </dev/tty) || return 1
        repeated=$(DIALOG --output-fd 3 --passwordbox \
            "Re-enter the encryption passphrase:" ${INPUTSIZE} \
            3>&1 >/dev/tty </dev/tty) || return 1
        if [ -z "$passphrase" ] || [ "$passphrase" != "$repeated" ]; then
            DIALOG --msgbox "Enter the same non-empty passphrase twice." ${MSGBOXSIZE}
            return 1
        fi
        unset repeated
        if [ -e "$mapper" ] || cryptsetup status void-root >/dev/null 2>&1; then
            guided_error "The void-root mapping is already in use."
        fi
    fi
    if mountpoint -q "$TARGETDIR"; then
        guided_error "The installer mount point is already in use."
    fi
    if ! details=$(guided_disk_details "$disk" 2>>"$LOG") ||
        [ "$details" != "$GUIDED_DISK_DETAILS" ]; then
        guided_error "The selected disk changed or is no longer eligible."
    fi

    GUIDED_STARTED=1
    GUIDED_LUKS_UUID=
    GUIDED_SWAP_PARTUUID=
    TITLE="Check $LOG for details ..."
    INFOBOX "Creating the Btrfs layout on $disk ..." 8 65
    guided_partition_table |
        sfdisk --lock=yes --wipe always --wipe-partitions always -- "$disk" >>"$LOG" 2>&1 ||
        guided_error "Failed to replace the partition table on $disk."
    udevadm settle >>"$LOG" 2>&1 || guided_error "Failed to settle partition devices."
    while read -r device number; do
        case "$number" in
            1) efi=$device;;
            2) boot=$device;;
            3) third=$device;;
            4) fourth=$device;;
        esac
    done < <(lsblk -nrpo NAME,PARTN -- "$disk")
    root=$third
    if (( GUIDED_SWAP_GIB > 0 )); then
        swap=$third
        root=$fourth
    fi
    if ! [ -b "$efi" ] || ! [ -b "$boot" ] || ! [ -b "$root" ] ||
        { (( GUIDED_SWAP_GIB > 0 )) && ! [ -b "$swap" ]; }; then
        guided_error "Could not find all new partitions on $disk."
    fi

    mkfs.vfat -F32 "$efi" >>"$LOG" 2>&1 &&
        mkfs.ext4 -F "$boot" >>"$LOG" 2>&1 ||
        guided_error "Failed to format the EFI or boot partition."

    root_device=$root
    if [ "$GUIDED_ENCRYPTION" = LUKS2 ]; then
        printf '%s' "$passphrase" |
            cryptsetup luksFormat --batch-mode --type luks2 --pbkdf argon2id \
                --key-file - "$root" >>"$LOG" 2>&1 ||
            guided_error "Failed to format encrypted root."
        printf '%s' "$passphrase" |
            cryptsetup open --key-file - "$root" void-root >>"$LOG" 2>&1 ||
            guided_error "Failed to unlock encrypted root."
        GUIDED_MAPPER_OPEN=1
        unset passphrase
        GUIDED_LUKS_UUID=$(cryptsetup luksUUID "$root" 2>>"$LOG") ||
            guided_error "Failed to read the LUKS identifier."
        root_device=$mapper
    fi

    mkfs.btrfs -f "$root_device" >>"$LOG" 2>&1 &&
        mkdir -p "$TARGETDIR" &&
        mount -t btrfs -o subvolid=5 "$root_device" "$TARGETDIR" >>"$LOG" 2>&1 &&
        btrfs subvolume create "$TARGETDIR/@" "$TARGETDIR/@home" \
            "$TARGETDIR/@snapshots" >>"$LOG" 2>&1 &&
        umount "$TARGETDIR" >>"$LOG" 2>&1 &&
        mount -t btrfs -o subvol=@ "$root_device" "$TARGETDIR" >>"$LOG" 2>&1 &&
        mkdir -p "$TARGETDIR/boot" "$TARGETDIR/home" "$TARGETDIR/.snapshots" &&
        mount -t ext4 "$boot" "$TARGETDIR/boot" >>"$LOG" 2>&1 &&
        mkdir -p "$TARGETDIR/boot/efi" &&
        mount -t vfat "$efi" "$TARGETDIR/boot/efi" >>"$LOG" 2>&1 &&
        mount -t btrfs -o subvol=@home "$root_device" "$TARGETDIR/home" >>"$LOG" 2>&1 &&
        mount -t btrfs -o subvol=@snapshots "$root_device" "$TARGETDIR/.snapshots" >>"$LOG" 2>&1 &&
        chmod 0750 "$TARGETDIR/.snapshots" ||
        guided_error "Failed to create or mount the new filesystems."

    root_uuid=$(blkid -s UUID -o value "$root_device") &&
        boot_uuid=$(blkid -s UUID -o value "$boot") &&
        efi_uuid=$(blkid -s UUID -o value "$efi") ||
        guided_error "Failed to read the new filesystem identifiers."
    cat >"$TARGET_FSTAB" <<EOF ||
UUID=$root_uuid / btrfs defaults,subvol=@ 0 0
UUID=$boot_uuid /boot ext4 defaults 0 2
UUID=$efi_uuid /boot/efi vfat defaults,umask=0077 0 2
UUID=$root_uuid /home btrfs defaults,subvol=@home 0 0
UUID=$root_uuid /.snapshots btrfs defaults,subvol=@snapshots 0 0
EOF
        guided_error "Failed to write the filesystem table."

    if (( GUIDED_SWAP_GIB > 0 )); then
        if [ "$GUIDED_ENCRYPTION" = LUKS2 ]; then
            # runit will open plain dm-crypt with a new random key and run mkswap at boot.
            GUIDED_SWAP_PARTUUID=$(blkid -s PARTUUID -o value "$swap") ||
                guided_error "Failed to read the swap partition identifier."
            printf '/dev/mapper/void-swap none swap defaults 0 0\n' >>"$TARGET_FSTAB" ||
                guided_error "Failed to write encrypted swap settings."
        else
            mkswap "$swap" >>"$LOG" 2>&1 &&
                swap_uuid=$(blkid -s UUID -o value "$swap") &&
                printf 'UUID=%s none swap defaults 0 0\n' "$swap_uuid" >>"$TARGET_FSTAB" ||
                guided_error "Failed to create the swap partition."
        fi
    fi
}

configure_guided_boot() {
    local keymap
    local -a dracut_args=(--force --regenerate-all --no-hostonly --add-drivers ahci --add btrfs)
    if [ -n "$GUIDED_LUKS_UUID" ]; then
        keymap=$(get_option KEYMAP)
        if [ -z "$keymap" ] && [ -f /etc/vconsole.conf ]; then
            keymap=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf)
        fi
        keymap=${keymap:-us}
        [[ "$keymap" =~ ^[[:alnum:]_.+-]+$ ]] || guided_error "Invalid boot keymap."

        printf 'void-root UUID=%s none luks\n' "$GUIDED_LUKS_UUID" >"$TARGETDIR/etc/crypttab" &&
            mkdir -p "$TARGETDIR/etc/dracut.conf.d" &&
            printf '%s\n' 'add_dracutmodules+=" crypt btrfs i18n "' \
                'install_items+=" /etc/crypttab "' \
                >"$TARGETDIR/etc/dracut.conf.d/90-void-encrypted-root.conf" &&
            printf 'KEYMAP=%s\n' "$keymap" >"$TARGETDIR/etc/vconsole.conf" &&
            printf '\nGRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rd.luks.uuid=%s rd.vconsole.keymap=%s"\n' \
                "$GUIDED_LUKS_UUID" "$keymap" >>"$TARGETDIR/etc/default/grub" ||
            guided_error "Failed to write encrypted boot settings."

        if [ -n "$GUIDED_SWAP_PARTUUID" ]; then
            printf 'void-swap /dev/disk/by-partuuid/%s /dev/urandom swap,cipher=aes-xts-plain64,size=512\n' \
                "$GUIDED_SWAP_PARTUUID" >>"$TARGETDIR/etc/crypttab" ||
                guided_error "Failed to configure encrypted swap."
        fi
    fi

    INFOBOX "Building initramfs for the installed system ..." 4 65
    chroot "$TARGETDIR" dracut "${dracut_args[@]}" >>"$LOG" 2>&1 ||
        guided_error "Failed to build the installed system's initramfs."
}

get_partfs() {
    # Get fs type from configuration if available. This ensures
    # that the user is shown the proper fs type if they install the system.
    local part="$1"
    local default="${2:-none}"
    local fstype=$(grep "MOUNTPOINT ${part} " "$CONF_FILE"|awk '{print $3}')
    echo "${fstype:-$default}"
}

show_partitions() {
    local dev fstype fssize p part

    set -- $(show_disks)
    while [ $# -ne 0 ]; do
        disk=$(basename $1)
        shift 2
        # ATA/SCSI/SATA
        for p in /sys/block/$disk/$disk*; do
            if [ -d $p ]; then
                part=$(basename $p)
                fstype=$(lsblk -nfr /dev/$part|awk '{print $2}'|head -1)
                [ "$fstype" = "iso9660" ] && continue
                [ "$fstype" = "crypto_LUKS" ] && continue
                [ "$fstype" = "LVM2_member" ] && continue
                fssize=$(lsblk -nr /dev/$part|awk '{print $4}'|head -1)
                echo "/dev/$part"
                echo "size:${fssize:-unknown};fstype:$(get_partfs "/dev/$part")"
            fi
        done
    done
    # Device Mapper
    for p in /dev/mapper/*; do
        part=$(basename $p)
        [ "${part}" = "live-rw" ] && continue
        [ "${part}" = "live-base" ] && continue
        [ "${part}" = "control" ] && continue

        fstype=$(lsblk -nfr $p|awk '{print $2}'|head -1)
        fssize=$(lsblk -nr $p|awk '{print $4}'|head -1)
        echo "${p}"
        echo "size:${fssize:-unknown};fstype:$(get_partfs "$p")"
    done
    # Software raid (md)
    for p in $(ls -d /dev/md* 2>/dev/null|grep '[0-9]'); do
        part=$(basename $p)
        if cat /proc/mdstat|grep -qw $part; then
            fstype=$(lsblk -nfr /dev/$part|awk '{print $2}')
            [ "$fstype" = "crypto_LUKS" ] && continue
            [ "$fstype" = "LVM2_member" ] && continue
            fssize=$(lsblk -nr /dev/$part|awk '{print $4}')
            echo "$p"
            echo "size:${fssize:-unknown};fstype:$(get_partfs "$p")"
        fi
    done
    # cciss(4) devices
    for part in $(ls /dev/cciss 2>/dev/null|grep -E 'c[0-9]d[0-9]p[0-9]+'); do
        fstype=$(lsblk -nfr /dev/cciss/$part|awk '{print $2}')
        [ "$fstype" = "crypto_LUKS" ] && continue
        [ "$fstype" = "LVM2_member" ] && continue
        fssize=$(lsblk -nr /dev/cciss/$part|awk '{print $4}')
        echo "/dev/cciss/$part"
        echo "size:${fssize:-unknown};fstype:$(get_partfs "/dev/cciss/$part")"
    done
    if [ -e /sbin/lvs ]; then
        # LVM
        lvs --noheadings|while read lvname vgname perms size; do
            echo "/dev/mapper/${vgname}-${lvname}"
            echo "size:${size};fstype:$(get_partfs "/dev/mapper/${vgname}-${lvname}" lvm)"
        done
    fi
}

menu_filesystems() {
    local dev fstype fssize mntpoint reformat

    while true; do
        DIALOG --ok-label "Change" --cancel-label "Done" \
            --title " Select the partition to edit " --menu "$MENULABEL" \
            ${MENUSIZE} $(show_partitions)
        [ $? -ne 0 ] && return

        dev=$(cat $ANSWER)
        DIALOG --title " Select the filesystem type for $dev " \
            --menu "$MENULABEL" ${MENUSIZE} \
            "btrfs" "Oracle's Btrfs" \
            "ext2" "Linux ext2 (no journaling)" \
            "ext3" "Linux ext3 (journal)" \
            "ext4" "Linux ext4 (journal)" \
            "f2fs" "Flash-Friendly Filesystem" \
            "swap" "Linux swap" \
            "vfat" "FAT32" \
            "xfs" "SGI's XFS"
        if [ $? -eq 0 ]; then
            fstype=$(cat $ANSWER)
        else
            continue
        fi
        if [ "$fstype" != "swap" ]; then
            DIALOG --inputbox "Please specify the mount point for $dev:" ${INPUTSIZE}
            if [ $? -eq 0 ]; then
                mntpoint=$(cat $ANSWER)
            elif [ $? -eq 1 ]; then
                continue
            fi
        else
            mntpoint=swap
        fi
        DIALOG --yesno "Do you want to create a new filesystem on $dev?" ${YESNOSIZE}
        if [ $? -eq 0 ]; then
            reformat=1
        elif [ $? -eq 1 ]; then
            reformat=0
        else
            continue
        fi
        fssize=$(lsblk -nr $dev|awk '{print $4}')
        set -- "$fstype" "$fssize" "$mntpoint" "$reformat"
        if [ -n "$1" -a -n "$2" -a -n "$3" -a -n "$4" ]; then
            local bdev=$(basename $dev)
            local ddev=$(basename $(dirname $dev))
            if [ "$ddev" != "dev" ]; then
                sed -i -e "/^MOUNTPOINT \/dev\/${ddev}\/${bdev} .*/d" $CONF_FILE
            else
                sed -i -e "/^MOUNTPOINT \/dev\/${bdev} .*/d" $CONF_FILE
            fi
            echo "MOUNTPOINT $dev $1 $2 $3 $4" >>$CONF_FILE
        fi
    done
    FILESYSTEMS_DONE=1
}

menu_partitions() {
    DIALOG --title " Select the disk to partition " \
        --menu "$MENULABEL" ${MENUSIZE} $(show_disks)
    if [ $? -eq 0 ]; then
        local device=$(cat $ANSWER)

        DIALOG --title " Select the software for partitioning " \
            --menu "$MENULABEL" ${MENUSIZE} \
            "cfdisk" "Easy to use" \
            "fdisk" "More advanced"
        if [ $? -eq 0 ]; then
            local software=$(cat $ANSWER)

            DIALOG --title "Modify Partition Table on $device" --msgbox "\n
${BOLD}${software} will be executed in disk $device.${RESET}\n\n
For BIOS systems, MBR or GPT partition tables are supported. To use GPT\n
on PC BIOS systems, an empty partition of 1MB must be added at the first\n
2GB of the disk with the partition type \`BIOS Boot'.\n
${BOLD}NOTE: you don't need this on EFI systems.${RESET}\n\n
For EFI systems, GPT is mandatory and a FAT32 partition with at least 100MB\n
must be created with the partition type \`EFI System'. This will be used as\n
the EFI System Partition. This partition must have the mountpoint \`/boot/efi'.\n\n
At least 1 partition is required for the rootfs (/). For this partition,\n
at least 2GB is required, but more is recommended. The rootfs partition\n
should have the partition type \`Linux Filesystem'. For swap, RAM*2\n
should be enough and the partition type \`Linux swap' should be used.\n\n
${BOLD}WARNING: /usr is not supported as a separate partition.${RESET}\n
${RESET}\n" 23 80
            if [ $? -eq 0 ]; then
                while true; do
                    clear; $software $device; PARTITIONS_DONE=1
                    break
                done
            else
                return
            fi
        fi
    fi
}

menu_keymap() {
    local _keymaps="$(find /usr/share/kbd/keymaps/ -type f -iname "*.map.gz" -printf "%f\n" | sed 's|.map.gz||g' | sort)"
    local _KEYMAPS=

    for f in ${_keymaps}; do
        _KEYMAPS="${_KEYMAPS} ${f} -"
    done
    while true; do
        DIALOG --title " Select your keymap " --menu "$MENULABEL" 14 70 14 ${_KEYMAPS}
        if [ $? -eq 0 ]; then
            set_option KEYMAP "$(cat $ANSWER)"
            loadkeys "$(cat $ANSWER)"
            KEYBOARD_DONE=1
            break
        else
            return
        fi
    done
}

set_keymap() {
    local KEYMAP=$(get_option KEYMAP)

    if [ -f /etc/vconsole.conf ]; then
        sed -i -e "s|KEYMAP=.*|KEYMAP=$KEYMAP|g" $TARGETDIR/etc/vconsole.conf
    else
        sed -i -e "s|#\?KEYMAP=.*|KEYMAP=$KEYMAP|g" $TARGETDIR/etc/rc.conf
    fi
}

menu_locale() {
    local _locales="$(grep -E '\.UTF-8' /etc/default/libc-locales|awk '{print $1}'|sed -e 's/^#//')"
    local LOCALES ISO639 ISO3166
    local TMPFILE=$(mktemp -t vinstall-XXXXXXXX || exit 1)
    INFOBOX "Scanning locales ..." 4 60
    for f in ${_locales}; do
        eval $(echo $f | awk 'BEGIN { FS="." } \
            { FS="_"; split($1, a); printf "ISO639=%s ISO3166=%s\n", a[1], a[2] }')
        echo "$f|$(iso639_language $ISO639) ($(iso3166_country $ISO3166))|" >> $TMPFILE
    done
    clear
    # Sort by ISO-639 language names
    LOCALES=$(sort -t '|' -k 2 < $TMPFILE | xargs | sed -e's/| /|/g')
    rm -f $TMPFILE
    while true; do
        (IFS="|"; DIALOG --title " Select your locale " --menu "$MENULABEL" 18 70 18 ${LOCALES})
        if [ $? -eq 0 ]; then
            set_option LOCALE "$(cat $ANSWER)"
            LOCALE_DONE=1
            break
        else
            return
        fi
    done
}

set_locale() {
    if [ -f $TARGETDIR/etc/default/libc-locales ]; then
        local LOCALE="$(get_option LOCALE)"
        : "${LOCALE:=C.UTF-8}"
        sed -i -e "s|LANG=.*|LANG=$LOCALE|g" $TARGETDIR/etc/locale.conf
        # Uncomment locale from /etc/default/libc-locales and regenerate it.
        sed -e "/${LOCALE}/s/^\#//" -i $TARGETDIR/etc/default/libc-locales
        echo "Running xbps-reconfigure -f glibc-locales ..." >$LOG
        chroot $TARGETDIR xbps-reconfigure -f glibc-locales >$LOG 2>&1
    fi
}

menu_timezone() {
    local areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)

    local area locations location
    while (IFS='|'; DIALOG ${area:+--default-item|"$area"} --title " Select area " --menu "$MENULABEL" 19 51 19 $(printf '%s||' "${areas[@]}")); do
        area=$(cat $ANSWER)
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort)
        if (IFS='|'; DIALOG --title " Select location (${area}) " --menu "$MENULABEL" 19 51 19 $(printf '%s||' "${locations[@]//_/ }")); then
            location=$(tr ' ' '_' < $ANSWER)
            set_option TIMEZONE "$area/$location"
            TIMEZONE_DONE=1
            return 0
        else
            continue
        fi
    done
    return 1
}

set_timezone() {
    local TIMEZONE="$(get_option TIMEZONE)"

    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${TARGETDIR}/etc/localtime"
}

menu_hostname() {
    while true; do
        DIALOG --inputbox "Set the machine hostname:" ${INPUTSIZE}
        if [ $? -eq 0 ]; then
            set_option HOSTNAME "$(cat $ANSWER)"
            HOSTNAME_DONE=1
            break
        else
            return
        fi
    done
}

set_hostname() {
    local hostname="$(get_option HOSTNAME)"
    echo "${hostname:-void}" > $TARGETDIR/etc/hostname
}

menu_rootpassword() {
    local _firstpass _secondpass _again _desc

    while true; do
        if [ -z "${_firstpass}" ]; then
            _desc="Enter the root password"
        else
            _again=" again"
        fi
        DIALOG --insecure --passwordbox "${_desc}${_again}" ${INPUTSIZE}
        if [ $? -eq 0 ]; then
            if [ -z "${_firstpass}" ]; then
                _firstpass="$(cat $ANSWER)"
            else
                _secondpass="$(cat $ANSWER)"
            fi
            if [ -n "${_firstpass}" -a -n "${_secondpass}" ]; then
                if [ "${_firstpass}" != "${_secondpass}" ]; then
                    INFOBOX "Passwords do not match! Please enter again." 6 60
                    unset _firstpass _secondpass _again
                    sleep 2 && clear && continue
                fi
                set_option ROOTPASSWORD "${_firstpass}"
                ROOTPASSWORD_DONE=1
                break
            fi
        else
            return
        fi
    done
}

set_rootpassword() {
    echo "root:$(get_option ROOTPASSWORD)" | chroot $TARGETDIR chpasswd -c SHA512
}

menu_useraccount() {
    local _firstpass _secondpass _desc _again
    local _groups _status _group _checklist
    local _preset _userlogin

    while true; do
        _preset=$(get_option USERLOGIN)
        [ -z "$_preset" ] && _preset="void"
        DIALOG --inputbox "Enter a primary login name:" ${INPUTSIZE} "$_preset"
        if [ $? -eq 0 ]; then
            _userlogin="$(cat $ANSWER)"
            # based on useradd(8) § Caveats
            if [ "${#_userlogin}" -le 32 ] && [[ "${_userlogin}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
                set_option USERLOGIN "${_userlogin}"
                USERLOGIN_DONE=1
                break
            else
                INFOBOX "Invalid login name! Please try again." 6 60
                unset _userlogin
                sleep 2 && clear && continue
            fi
        else
            return
        fi
    done

    while true; do
        _preset=$(get_option USERNAME)
        [ -z "$_preset" ] && _preset="Void User"
        DIALOG --inputbox "Enter a display name for login '$(get_option USERLOGIN)' :" \
            ${INPUTSIZE} "$_preset"
        if [ $? -eq 0 ]; then
            set_option USERNAME "$(cat $ANSWER)"
            USERNAME_DONE=1
            break
        else
            return
        fi
    done

    while true; do
        if [ -z "${_firstpass}" ]; then
            _desc="Enter the password for login '$(get_option USERLOGIN)'"
        else
            _again=" again"
        fi
        DIALOG --insecure --passwordbox "${_desc}${_again}" ${INPUTSIZE}
        if [ $? -eq 0 ]; then
            if [ -z "${_firstpass}" ]; then
                _firstpass="$(cat $ANSWER)"
            else
                _secondpass="$(cat $ANSWER)"
            fi
            if [ -n "${_firstpass}" -a -n "${_secondpass}" ]; then
                if [ "${_firstpass}" != "${_secondpass}" ]; then
                    INFOBOX "Passwords do not match! Please enter again." 6 60
                    unset _firstpass _secondpass _again
                    sleep 2 && clear && continue
                fi
                set_option USERPASSWORD "${_firstpass}"
                USERPASSWORD_DONE=1
                break
            fi
        else
            return
        fi
    done

    _groups="wheel,audio,video,floppy,cdrom,optical,kvm,users,xbuilder"
    while true; do
        _desc="Select group membership for login '$(get_option USERLOGIN)':"
        for _group in $(cat /etc/group); do
            _gid="$(echo ${_group} | cut -d: -f3)"
            _group="$(echo ${_group} | cut -d: -f1)"
            _status="$(echo ${_groups} | grep -w ${_group})"
            if [ -z "${_status}" ]; then
                _status=off
            else
                _status=on
            fi
            # ignore the groups of root, existing users, and package groups
            if [[ "${_gid}" -ge 1000 || "${_group}" = "_"* || "${_group}" =~ ^(root|nogroup|chrony|dbus|lightdm|polkitd)$ ]]; then
                continue
            fi
            if [ -z "${_checklist}" ]; then
                _checklist="${_group} ${_group}:${_gid} ${_status}"
            else
                _checklist="${_checklist} ${_group} ${_group}:${_gid} ${_status}"
            fi
        done
        DIALOG --no-tags --checklist "${_desc}" 20 60 18 ${_checklist}
        if [ $? -eq 0 ]; then
            set_option USERGROUPS $(cat $ANSWER | sed -e's| |,|g')
            USERGROUPS_DONE=1
            break
        else
            return
        fi
    done
}

set_useraccount() {
    [ -z "$USERACCOUNT_DONE" ] && return
    chroot $TARGETDIR useradd -m -G "$(get_option USERGROUPS)" \
        -c "$(get_option USERNAME)" "$(get_option USERLOGIN)"
    echo "$(get_option USERLOGIN):$(get_option USERPASSWORD)" | \
        chroot $TARGETDIR chpasswd -c SHA512
}

menu_bootloader() {
    while true; do
        DIALOG --title " Select the disk to install the bootloader" \
            --menu "$MENULABEL" ${MENUSIZE} $(show_disks) none "Manage bootloader otherwise"
        if [ $? -eq 0 ]; then
            set_option BOOTLOADER "$(cat $ANSWER)"
            BOOTLOADER_DONE=1
            break
        else
            return
        fi
    done
    while true; do
        DIALOG --yesno "Use a graphical terminal for the boot loader?" ${YESNOSIZE}
        if [ $? -eq 0 ]; then
            set_option TEXTCONSOLE 0
            break
        elif [ $? -eq 1 ]; then
            set_option TEXTCONSOLE 1
            break
        else
            return
        fi
    done
}

set_bootloader() {
    local dev=$(get_option BOOTLOADER) grub_args=
    [ -n "$GUIDED_DISK" ] && dev=$GUIDED_DISK

    if [ "$dev" = "none" ]; then return; fi

    # Check if it's an EFI system via efivars module.
    if [ -n "$EFI_SYSTEM" ]; then
        grub_args="--target=$EFI_TARGET --efi-directory=/boot/efi --bootloader-id=void_grub --recheck"
    fi
    echo "Running grub-install $grub_args $dev..." >$LOG
    chroot $TARGETDIR grub-install $grub_args $dev >$LOG 2>&1
    if [ $? -ne 0 ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to install GRUB to $dev!\nCheck $LOG for errors." ${MSGBOXSIZE}
        DIE 1
    fi
    echo "Running grub-mkconfig on $TARGETDIR..." >$LOG
    chroot $TARGETDIR grub-mkconfig -o /boot/grub/grub.cfg >$LOG 2>&1
    if [ $? -ne 0 ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR${RESET}: \
failed to run grub-mkconfig!\nCheck $LOG for errors." ${MSGBOXSIZE}
        DIE 1
    fi
}

test_network() {
    # Reset the global variable to ensure that network is accessible for this test.
    NETWORK_DONE=

    rm -f otime && \
        xbps-uhelper fetch https://repo-default.voidlinux.org/current/otime >$LOG 2>&1
    local status=$?
    rm -f otime

    if [ "$status" -eq 0 ]; then
        DIALOG --msgbox "Network is working properly!" ${MSGBOXSIZE}
        NETWORK_DONE=1
        return 1
    fi
    if [ "$1" = "nm" ]; then
        DIALOG --msgbox "Network Manager is enabled but network is inaccessible, please set it up externally with nmcli, nmtui, or the Network Manager tray applet." ${MSGBOXSIZE}
    else
        DIALOG --msgbox "Network is inaccessible, please set it up properly." ${MSGBOXSIZE}
    fi
}

configure_wifi() {
    local dev="$1" ssid enc pass _wpasupconf=/etc/wpa_supplicant/wpa_supplicant.conf

    DIALOG --form "Wireless configuration for ${dev}\n(encryption type: wep, wpa, or sae)" 0 0 0 \
        "SSID:" 1 1 "" 1 16 32 0 \
        "Encryption:" 2 1 "" 2 16 4 3 \
        "Password:" 3 1 "" 3 16 63 0 || return 1
    readarray -t values <<<$(cat $ANSWER)
    ssid="${values[0]}"; enc="${values[1]}"; pass="${values[2]}"

    if [ -z "$ssid" ]; then
        DIALOG --msgbox "Invalid SSID." ${MSGBOXSIZE}
        return 1
    elif [ -z "$enc" ] || [[ "$enc" != "wep" && "$enc" != "wpa" && "$enc" != "sae" ]]; then
        DIALOG --msgbox "Invalid encryption type (possible values: wep, wpa, or sae)." ${MSGBOXSIZE}
        return 1
    elif [ -z "$pass" ]; then
        DIALOG --msgbox "Invalid AP password." ${MSGBOXSIZE}
    fi

    # reset the configuration to the default, if necessary
    # otherwise backup the configuration
    if [ -f ${_wpasupconf}.orig ]; then
        cp -f ${_wpasupconf}.orig ${_wpasupconf}
    else
        cp -f ${_wpasupconf} ${_wpasupconf}.orig
    fi
    if [ "$enc" = "wep" ]; then
        cat << EOF >> ${_wpasupconf}
network={
  ssid="$ssid"
  wep_key0="$pass"
  wep_tx_keyidx=0
  auth_alg=SHARED
}
EOF
    elif [ "$enc" = "sae" ]; then
        cat << EOF >> ${_wpasupconf}
network={
    ssid="$ssid"
    key_mgmt=SAE
    sae_password="$pass"
    ieee80211w=2
}
EOF
    else
        wpa_passphrase "$ssid" "$pass" >> ${_wpasupconf}
    fi

    sv restart wpa_supplicant
    configure_net_dhcp $dev
    return $?
}

configure_net() {
    local dev="$1" rval

    DIALOG --yesno "Do you want to use DHCP for $dev?" ${YESNOSIZE}
    rval=$?
    if [ $rval -eq 0 ]; then
        configure_net_dhcp $dev
    elif [ $rval -eq 1 ]; then
        configure_net_static $dev
    fi
}

iface_setup() {
    ip addr show dev $1 | grep -q -e 'inet ' -e 'inet6 '
    return $?
}

configure_net_dhcp() {
    local dev="$1"

    iface_setup $dev
    if [ $? -eq 1 ]; then
        sv restart dhcpcd 2>&1 | tee $LOG | \
            DIALOG --progressbox "Initializing $dev via DHCP..." ${WIDGET_SIZE}
        if [ $? -ne 0 ]; then
            DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} failed to run dhcpcd. See $LOG for details." ${MSGBOXSIZE}
            return 1
        fi
        export -f iface_setup
        timeout 10s bash -c "while true; do iface_setup $dev; sleep 0.25; done"
        if [ $? -eq 1 ]; then
            DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} DHCP request failed for $dev. Check $LOG for errors." ${MSGBOXSIZE}
            return 1
        fi
    fi
    test_network
    if [ $? -eq 1 ]; then
        set_option NETWORK "${dev} dhcp"
    fi
}

configure_net_static() {
    local ip gw dns1 dns2 dev=$1

    DIALOG --form "Static IP configuration for $dev:" 0 0 0 \
        "IP address:" 1 1 "192.168.0.2" 1 21 20 0 \
        "Gateway:" 2 1 "192.168.0.1" 2 21 20 0 \
        "DNS Primary" 3 1 "8.8.8.8" 3 21 20 0 \
        "DNS Secondary" 4 1 "8.8.4.4" 4 21 20 0 || return 1

    set -- $(cat $ANSWER)
    ip=$1; gw=$2; dns1=$3; dns2=$4
    echo "running: ip link set dev $dev up" >$LOG
    ip link set dev $dev up >$LOG 2>&1
    if [ $? -ne 0 ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} Failed to bring $dev interface." ${MSGBOXSIZE}
        return 1
    fi
    echo "running: ip addr add $ip dev $dev" >$LOG
    ip addr add $ip dev $dev >$LOG 2>&1
    if [ $? -ne 0 ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} Failed to set ip to the $dev interface." ${MSGBOXSIZE}
        return 1
    fi
    ip route add default via $gw >$LOG 2>&1
    if [ $? -ne 0 ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} failed to setup your gateway." ${MSGBOXSIZE}
        return 1
    fi
    echo "nameserver $dns1" >/etc/resolv.conf
    echo "nameserver $dns2" >>/etc/resolv.conf
    test_network
    if [ $? -eq 1 ]; then
        set_option NETWORK "${dev} static $ip $gw $dns1 $dns2"
    fi
}

menu_network() {
    local dev addr f DEVICES

    if [ -e /var/service/NetworkManager ]; then
        test_network nm
        return
    fi

    for f in $(ls /sys/class/net); do
        [ "$f" = "lo" ] && continue
        addr=$(cat /sys/class/net/$f/address)
        DEVICES="$DEVICES $f $addr"
    done
    DIALOG --title " Select the network interface to configure " \
        --menu "$MENULABEL" ${MENUSIZE} ${DEVICES}
    if [ $? -eq 0 ]; then
        dev=$(cat $ANSWER)
        if $(echo $dev|egrep -q "^wl.*" 2>/dev/null); then
            configure_wifi $dev
        else
            configure_net $dev
        fi
    fi
}

validate_useraccount() {
    # don't check that USERNAME has been set because it can be empty
    local USERLOGIN=$(get_option USERLOGIN)
    local USERPASSWORD=$(get_option USERPASSWORD)
    local USERGROUPS=$(get_option USERGROUPS)

    if [ -n "$USERLOGIN" ] && [ -n "$USERPASSWORD" ] && [ -n "$USERGROUPS" ]; then
        USERACCOUNT_DONE=1
    fi
}

validate_filesystems() {
    local mnts dev size fstype mntpt mkfs rootfound fmt
    local usrfound efi_system_partition
    local bootdev=$(get_option BOOTLOADER)

    unset TARGETFS
    mnts=$(grep -E '^MOUNTPOINT .*' $CONF_FILE)
    set -- ${mnts}
    while [ $# -ne 0 ]; do
        fmt=""
        dev=$2; fstype=$3; size=$4; mntpt="$5"; mkfs=$6
        shift 6

        if [ "$mntpt" = "/" ]; then
            rootfound=1
        elif [ "$mntpt" = "/usr" ]; then
            usrfound=1
        elif [ "$fstype" = "vfat" -a "$mntpt" = "/boot/efi" ]; then
            efi_system_partition=1
        fi
        if [ "$mkfs" -eq 1 ]; then
            fmt="NEW FILESYSTEM: "
        fi
        if [ -z "$TARGETFS" ]; then
            TARGETFS="${fmt}$dev ($size) mounted on $mntpt as ${fstype}\n"
        else
            TARGETFS="${TARGETFS}${fmt}${dev} ($size) mounted on $mntpt as ${fstype}\n"
        fi
    done
    if [ -z "$rootfound" ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
the mount point for the root filesystem (/) has not yet been configured." ${MSGBOXSIZE}
        return 1
    elif [ -n "$usrfound" ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
/usr mount point has been configured but is not supported, please remove it to continue." ${MSGBOXSIZE}
        return 1
    elif [ -n "$EFI_SYSTEM" -a "$bootdev" != "none" -a -z "$efi_system_partition" ]; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
The EFI System Partition has not yet been configured, please create it\n
as FAT32, mountpoint /boot/efi and at least with 100MB of size." ${MSGBOXSIZE}
        return 1
    fi
    FILESYSTEMS_DONE=1
}

create_filesystems() {
    local mnts dev mntpt fstype fspassno mkfs size rv uuid

    # truncate to avoid doubling up
    : >"$TARGET_FSTAB"

    mnts=$(grep -E '^MOUNTPOINT .*' $CONF_FILE | sort -k 5)
    set -- ${mnts}
    while [ $# -ne 0 ]; do
        dev=$2; fstype=$3; mntpt="$5"; mkfs=$6
        shift 6

        # swap partitions
        if [ "$fstype" = "swap" ]; then
            swapoff $dev >/dev/null 2>&1
            if [ "$mkfs" -eq 1 ]; then
                mkswap $dev >$LOG 2>&1
                if [ $? -ne 0 ]; then
                    DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to create swap on ${dev}!\ncheck $LOG for errors." ${MSGBOXSIZE}
                    DIE 1
                fi
            fi
            swapon $dev >$LOG 2>&1
            if [ $? -ne 0 ]; then
                DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to activate swap on $dev!\ncheck $LOG for errors." ${MSGBOXSIZE}
                DIE 1
            fi
            # Add entry for target fstab
            uuid=$(blkid -o value -s UUID "$dev")
            echo "UUID=$uuid none swap defaults 0 0" >>$TARGET_FSTAB
            continue
        fi

        if [ "$mkfs" -eq 1 ]; then
            case "$fstype" in
            btrfs) MKFS="mkfs.btrfs -f"; modprobe btrfs >$LOG 2>&1;;
            ext2) MKFS="mke2fs -F"; modprobe ext2 >$LOG 2>&1;;
            ext3) MKFS="mke2fs -F -j"; modprobe ext3 >$LOG 2>&1;;
            ext4) MKFS="mke2fs -F -t ext4"; modprobe ext4 >$LOG 2>&1;;
            f2fs) MKFS="mkfs.f2fs -f"; modprobe f2fs >$LOG 2>&1;;
            vfat) MKFS="mkfs.vfat -F32"; modprobe vfat >$LOG 2>&1;;
            xfs) MKFS="mkfs.xfs -f -i sparse=0"; modprobe xfs >$LOG 2>&1;;
            esac
            TITLE="Check $LOG for details ..."
            INFOBOX "Creating filesystem $fstype on $dev for $mntpt ..." 8 60
            echo "Running $MKFS $dev..." >$LOG
            $MKFS $dev >$LOG 2>&1; rv=$?
            if [ $rv -ne 0 ]; then
                DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to create filesystem $fstype on $dev!\ncheck $LOG for errors." ${MSGBOXSIZE}
                DIE 1
            fi
        fi
        # Mount rootfs the first one.
        [ "$mntpt" != "/" ] && continue
        mkdir -p $TARGETDIR
        echo "Mounting $dev on $mntpt ($fstype)..." >$LOG
        mount -t $fstype $dev $TARGETDIR >$LOG 2>&1
        if [ $? -ne 0 ]; then
            DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to mount $dev on ${mntpt}! check $LOG for errors." ${MSGBOXSIZE}
            DIE 1
        fi
        # Add entry to target fstab
        uuid=$(blkid -o value -s UUID "$dev")
        if [ "$fstype" = "f2fs" -o "$fstype" = "btrfs" -o "$fstype" = "xfs" ]; then
            fspassno=0
        else
            fspassno=1
        fi
        echo "UUID=$uuid $mntpt $fstype defaults 0 $fspassno" >>$TARGET_FSTAB
    done

    # mount all filesystems in target rootfs
    mnts=$(grep -E '^MOUNTPOINT .*' $CONF_FILE | sort -k 5)
    set -- ${mnts}
    while [ $# -ne 0 ]; do
        dev=$2; fstype=$3; mntpt="$5"
        shift 6
        [ "$mntpt" = "/" -o "$fstype" = "swap" ] && continue
        mkdir -p ${TARGETDIR}${mntpt}
        echo "Mounting $dev on $mntpt ($fstype)..." >$LOG
        mount -t $fstype $dev ${TARGETDIR}${mntpt} >$LOG 2>&1
        if [ $? -ne 0 ]; then
            DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
failed to mount $dev on $mntpt! check $LOG for errors." ${MSGBOXSIZE}
            DIE
        fi
        # Add entry to target fstab
        uuid=$(blkid -o value -s UUID "$dev")
        if [ "$fstype" = "f2fs" -o "$fstype" = "btrfs" -o "$fstype" = "xfs" ]; then
            fspassno=0
        else
            fspassno=2
        fi
        echo "UUID=$uuid $mntpt $fstype defaults 0 $fspassno" >>$TARGET_FSTAB
    done
}

mount_filesystems() {
    for f in sys proc dev; do
        [ ! -d $TARGETDIR/$f ] && mkdir $TARGETDIR/$f
        echo "Mounting $TARGETDIR/$f..." >$LOG
        if [ -n "$GUIDED_DISK" ]; then
            mount --rbind "/$f" "$TARGETDIR/$f" --make-rslave >>"$LOG" 2>&1 ||
                guided_error "Failed to bind-mount /$f."
        else
            mount --rbind /$f $TARGETDIR/$f >$LOG 2>&1
        fi
    done
}

umount_filesystems() {
    if [ -n "$GUIDED_STARTED" ]; then
        if mountpoint -q "$TARGETDIR"; then
            umount -R "$TARGETDIR" >>"$LOG" 2>&1 || return 1
        fi
        if [ -n "$GUIDED_MAPPER_OPEN" ]; then
            cryptsetup close void-root >>"$LOG" 2>&1 || return 1
            GUIDED_MAPPER_OPEN=
        fi
        GUIDED_STARTED=
        return 0
    fi
    [ -n "$GUIDED_DISK" ] && return 0
    local mnts="$(grep -E '^MOUNTPOINT .* swap .*$' $CONF_FILE | sort -r -k 5)"
    set -- ${mnts}
    while [ $# -ne 0 ]; do
        local dev=$2; local fstype=$3
        shift 6
        if [ "$fstype" = "swap" ]; then
            echo "Disabling swap space on $dev..." >$LOG
            swapoff $dev >$LOG 2>&1
            continue
        fi
    done
    echo "Unmounting $TARGETDIR..." >$LOG
    umount -R $TARGETDIR >$LOG 2>&1
}

log_and_count() {
    local progress whole tenth
    while read line; do
        echo "$line" >$LOG
        copy_count=$((copy_count + 1))
        progress=$((1000 * copy_count / copy_total))
        if [ "$progress" != "$copy_progress" ]; then
            whole=$((progress / 10))
            tenth=$((progress % 10))
            printf "Progress: %d.%d%% (%d of %d files)\n" $whole $tenth $copy_count $copy_total
            copy_progress=$progress
        fi
    done
}

copy_rootfs() {
    local tar_in="--create --one-file-system --xattrs"
    TITLE="Check $LOG for details ..."
    if [ -n "$GUIDED_DISK" ]; then
        INFOBOX "Copying the live system to the target disk ..." 4 65
        local -a copy_status
        {
            tar $tar_in -C / --exclude=./dev --exclude=./proc --exclude=./sys \
                --exclude=./run --exclude=./mnt/target -f - . |
                tar --extract --xattrs --xattrs-include='*' --preserve-permissions -f - -C "$TARGETDIR"
            copy_status=("${PIPESTATUS[@]}")
        } >>"$LOG" 2>&1
        # Exit 1 on creation means a file changed in the running live system.
        if [ "${copy_status[0]}" -gt 1 ] || [ "${copy_status[1]}" -ne 0 ]; then
            guided_error "Failed to copy the live system."
        fi
        mkdir -p "$TARGETDIR"/{dev,proc,sys,run} ||
            guided_error "Failed to create target mount points."
        return
    fi
    INFOBOX "Counting files, please be patient ..." 4 60
    copy_total=$(tar ${tar_in} -v -f /dev/null / 2>/dev/null | wc -l)
    export copy_total copy_count=0 copy_progress=
    clear
    tar ${tar_in} -f - / 2>/dev/null | \
        tar --extract --xattrs --xattrs-include='*' --preserve-permissions -v -f - -C $TARGETDIR | \
        log_and_count | \
        DIALOG --title "${TITLE}" \
            --progressbox "Copying live image to target rootfs." 5 60
    if [ $? -ne 0 ]; then
        DIE 1
    fi
    unset copy_total copy_count copy_percent
}

guided_desktop_profile() {
    GUIDED_DESKTOP_PACKAGES=()
    GUIDED_DISPLAY_MANAGER=
    case "$1" in
        Base|"") return 0;;
        Plasma)
            GUIDED_DESKTOP_PACKAGES=(kde5 konsole dolphin)
            GUIDED_DISPLAY_MANAGER=sddm
            ;;
        Xfce)
            GUIDED_DESKTOP_PACKAGES=(xfce4 xfce4-terminal lightdm-gtk-greeter network-manager-applet)
            GUIDED_DISPLAY_MANAGER=lightdm
            ;;
        GNOME)
            GUIDED_DESKTOP_PACKAGES=(gnome)
            GUIDED_DISPLAY_MANAGER=gdm
            ;;
        LXQt)
            GUIDED_DESKTOP_PACKAGES=(lxqt qterminal network-manager-applet)
            GUIDED_DISPLAY_MANAGER=sddm
            ;;
        *) return 1;;
    esac
    GUIDED_DESKTOP_PACKAGES+=(
        "$GUIDED_DISPLAY_MANAGER" dbus NetworkManager xorg-minimal xorg-input-drivers
        xorg-video-drivers xauth dejavu-fonts-ttf mesa-dri pipewire wireplumber alsa-pipewire
    )
}

guided_check_repository() (
    local dir
    dir=$(mktemp -d) || return 1
    trap 'rm -f "$dir/otime"; rmdir "$dir"' EXIT
    cd "$dir" && xbps-uhelper fetch https://repo-default.voidlinux.org/current/otime >>"$LOG" 2>&1
)

configure_guided_network_profile() {
    if [ -z "$GUIDED_DISPLAY_MANAGER" ]; then
        [ -n "$(get_option NETWORK)" ] || enable_service dhcpcd
        return
    fi

    enable_service dbus
    enable_service "$GUIDED_DISPLAY_MANAGER"
    if [ -z "$(get_option NETWORK)" ]; then
        disable_service dhcpcd
        disable_service wpa_supplicant
        enable_service NetworkManager
    fi
    mkdir -p "$TARGETDIR/etc/xdg/autostart" "$TARGETDIR/etc/pipewire/pipewire.conf.d" &&
        ln -sf /usr/share/applications/pipewire.desktop "$TARGETDIR/etc/xdg/autostart/" &&
        ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf \
            "$TARGETDIR/etc/pipewire/pipewire.conf.d/" ||
        guided_error "Failed to configure desktop audio."
}

install_packages() {
    local _grub= _arch
    local -a packages=(base-system) status

    if [ -n "$GUIDED_DISK" ] || [ "$(get_option BOOTLOADER)" != none ]; then
        if [ -n "$EFI_SYSTEM" ]; then
            if [ $EFI_FW_BITS -eq 32 ]; then
                _grub="grub-i386-efi"
            else
                _grub="grub-x86_64-efi"
            fi
        else
            _grub="grub"
        fi
    fi

    [ -z "$_grub" ] || packages+=("$_grub")
    if [ -n "$GUIDED_DISK" ]; then
        packages+=(btrfs-progs)
        [ "$GUIDED_ENCRYPTION" != LUKS2 ] || packages+=(cryptsetup)
        packages+=("${GUIDED_DESKTOP_PACKAGES[@]}")
    fi

    mkdir -p $TARGETDIR/var/db/xbps/keys $TARGETDIR/usr/share
    cp -a /usr/share/xbps.d $TARGETDIR/usr/share/
    cp /var/db/xbps/keys/*.plist $TARGETDIR/var/db/xbps/keys
    if [ -n "$MIRROR_DONE" ]; then
        mkdir -p $TARGETDIR/etc
        cp -a /etc/xbps.d $TARGETDIR/etc
    fi
    mkdir -p $TARGETDIR/boot/grub

    _arch=$(xbps-uhelper arch)

    stdbuf -oL env XBPS_ARCH="$_arch" \
        xbps-install -r "$TARGETDIR" -SyU "${packages[@]}" 2>&1 | tee -a "$LOG" | \
        DIALOG --title "Installing system packages..." --programbox 24 80
    status=("${PIPESTATUS[@]}")
    if [ "${status[0]}" -ne 0 ] || [ "${status[2]}" -ne 0 ]; then
        DIALOG --msgbox "Package installation failed. See $LOG for details." ${MSGBOXSIZE}
        DIE 1
    fi
    xbps-reconfigure -r "$TARGETDIR" -f base-files >>"$LOG" 2>&1 || DIE 1
    stdbuf -oL chroot "$TARGETDIR" xbps-reconfigure -a 2>&1 | tee -a "$LOG" | \
        DIALOG --title "Configuring system packages..." --programbox 24 80
    status=("${PIPESTATUS[@]}")
    if [ "${status[0]}" -ne 0 ] || [ "${status[2]}" -ne 0 ]; then
        DIALOG --msgbox "Package configuration failed. See $LOG for details." ${MSGBOXSIZE}
        DIE 1
    fi
}

menu_services() {
    local sv _status _checklist=""
    # filter out services that probably shouldn't be messed with
    local sv_ignore='^(agetty-(tty[1-9]|generic|serial|console)|udevd|sulogin)$'
    find $TARGETDIR/etc/runit/runsvdir/default -mindepth 1 -maxdepth 1 -xtype d -printf '%f\n' | \
        grep -Ev "$sv_ignore" | sort -u > "$TARGET_SERVICES"
    while true; do
        while read -r sv; do
            if [ -n "$sv" ]; then
                if grep -qx "$sv" "$TARGET_SERVICES" 2>/dev/null; then
                    _status=on
                else
                    _status=off
                fi
                _checklist+=" ${sv} ${sv} ${_status}"
            fi
        done < <(find $TARGETDIR/etc/sv -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -Ev "$sv_ignore" | sort -u)
        DIALOG --no-tags --checklist "Select services to enable:" 20 60 18 ${_checklist}
        if [ $? -eq 0 ]; then
            comm -13 "$TARGET_SERVICES" <(cat "$ANSWER" | tr ' ' '\n') | while read -r sv; do
                enable_service "$sv"
            done
            comm -23 "$TARGET_SERVICES" <(cat "$ANSWER" | tr ' ' '\n') | while read -r sv; do
                disable_service "$sv"
            done
            break
        else
            return
        fi
    done
}

enable_service() {
    ln -sf "/etc/sv/$1" "$TARGETDIR/etc/runit/runsvdir/default/$1"
}

disable_service() {
    rm -f "$TARGETDIR/etc/runit/runsvdir/default/$1"
}

menu_install() {
    local source desktop swap_summary encryption_summary
    source=$(get_option SOURCE)
    ROOTPASSWORD_DONE="$(get_option ROOTPASSWORD)"
    BOOTLOADER_DONE="$(get_option BOOTLOADER)"

    if [ -z "$ROOTPASSWORD_DONE" ]; then
        DIALOG --msgbox "${BOLD}The root password has not been configured, \
please do so before starting the installation.${RESET}" ${MSGBOXSIZE}
        return 1
    elif guided_supported && [ -z "$GUIDED_DISK" ]; then
        DIALOG --msgbox "Select a target and storage options in Guided first." ${MSGBOXSIZE}
        return 1
    elif [ -z "$GUIDED_DISK" ] && [ -z "$BOOTLOADER_DONE" ]; then
        DIALOG --msgbox "${BOLD}The disk to install the bootloader has not been \
configured, please do so before starting the installation.${RESET}" ${MSGBOXSIZE}
        return 1
    fi

    # Validate filesystems after making sure bootloader is done,
    # so that specific checks can be made based on the selection
    if [ -n "$GUIDED_DISK" ]; then
        if [ "$source" = net ]; then
            desktop=$(get_option DESKTOP)
            if ! guided_desktop_profile "${desktop:-Base}"; then
                DIALOG --msgbox "Choose a desktop or Base under Source." ${MSGBOXSIZE}
                return 1
            fi
            if ! guided_check_repository; then
                DIALOG --msgbox "Cannot reach Void's repository. Connect from the live system or choose Local under Source." ${MSGBOXSIZE}
                return 1
            fi
            desktop="${desktop:-Base} (download)"
        else
            desktop="Live ISO (offline)"
        fi
        encryption_summary="Unencrypted Btrfs"
        [ "$GUIDED_ENCRYPTION" != LUKS2 ] || encryption_summary="LUKS2-encrypted Btrfs"
        swap_summary="No swap"
        if (( GUIDED_SWAP_GIB > 0 )); then
            swap_summary="$GUIDED_SWAP_GIB GiB swap partition"
            [ "$GUIDED_ENCRYPTION" != LUKS2 ] || swap_summary="$swap_summary (encrypted)"
        fi
        TARGETFS="ERASE $GUIDED_DISK ($(lsblk -dno SIZE,MODEL,TRAN -- "$GUIDED_DISK"))\nReplace the entire partition table and all existing partitions.\n$encryption_summary for /, /home and /.snapshots\n$swap_summary\nSystem: $desktop"
    else
        validate_filesystems || return 1
    fi

    if [ -z "$GUIDED_DISK" ] && [ -z "$FILESYSTEMS_DONE" ]; then
        DIALOG --msgbox "${BOLD}Required filesystems were not configured, \
please do so before starting the installation.${RESET}" ${MSGBOXSIZE}
        return 1
    fi

    # Validate useraccount. All parameters must be set (name, password, login name, groups).
    validate_useraccount

    if [ -z "$USERACCOUNT_DONE" ]; then
        DIALOG --yesno "${BOLD}The user account is not set up properly.${RESET}\n\n
${BOLD}${RED}WARNING: no user will be created. You will only be able to login \
with the root user in your new system.${RESET}\n\n
${BOLD}Do you want to continue?${RESET}" 10 60 || return
    fi

    local -a confirmation=()
    [ -z "$GUIDED_DISK" ] || confirmation=(--defaultno)
    DIALOG "${confirmation[@]}" --yesno "${BOLD}The following operations will be executed:${RESET}\n\n
${BOLD}${TARGETFS}${RESET}\n
${BOLD}${RED}WARNING: data on partitions will be COMPLETELY DESTROYED for new \
filesystems.${RESET}\n\n
${BOLD}Do you want to continue?${RESET}" 20 80 || return
    unset TARGETFS

    # Create and mount filesystems
    if [ -n "$GUIDED_DISK" ]; then
        guided_filesystems || return 1
    else
        create_filesystems
    fi

    # check if there are any files in the root partition, ignoring lost+found
    if find "$TARGETDIR" -xdev -not -name 'lost+found' -not -type d | read; then
        DIALOG --msgbox "${BOLD}${RED}ERROR:${RESET} \
Root partition not empty! Aborting..." ${MSGBOXSIZE}
        DIE 1
    fi

    SOURCE_DONE="$(get_option SOURCE)"
    # If source not set use defaults.
    if [ "$(get_option SOURCE)" = "local" -o -z "$SOURCE_DONE" ]; then
        copy_rootfs
        . /etc/default/live.conf
        rm -f $TARGETDIR/etc/motd
        rm -f $TARGETDIR/etc/issue
        rm -f $TARGETDIR/usr/sbin/void-installer
        [ -z "$GUIDED_DISK" ] || rm -f "$TARGETDIR/usr/bin/void-installer"
        # Remove modified sddm.conf to let sddm use the defaults.
        rm -f $TARGETDIR/etc/sddm.conf
        # Remove live user.
        echo "Removing $USERNAME live user from targetdir ..." >$LOG
        chroot $TARGETDIR userdel -r $USERNAME >$LOG 2>&1
        rm -f $TARGETDIR/etc/sudoers.d/99-void-live
        sed -i "s,GETTY_ARGS=\"--noclear -a $USERNAME\",GETTY_ARGS=\"--noclear\",g" $TARGETDIR/etc/sv/agetty-tty1/conf
        TITLE="Check $LOG for details ..."
        # mount required fs
        mount_filesystems
        if [ -z "$GUIDED_DISK" ]; then
            INFOBOX "Rebuilding initramfs for target ..." 4 60
            echo "Rebuilding initramfs for target ..." >$LOG
            chroot $TARGETDIR dracut --no-hostonly --add-drivers "ahci" --force >>$LOG 2>&1
        fi
        INFOBOX "Removing temporary packages from target ..." 4 60
        echo "Removing temporary packages from target ..." >$LOG
        TO_REMOVE="dialog xtools-minimal xmirror"
        # only remove espeakup and brltty if it wasn't enabled in the live environment
        if ! [ -e "/var/service/espeakup" ]; then
            TO_REMOVE+=" espeakup"
        fi
        if ! [ -e "/var/service/brltty" ]; then
            TO_REMOVE+=" brltty"
        fi
        if [ -z "$GUIDED_DISK" ] && [ "$(get_option BOOTLOADER)" = none ]; then
            TO_REMOVE+=" grub-x86_64-efi grub-i386-efi grub"
        fi
        # uninstall separately to minimise errors
        for pkg in $TO_REMOVE; do
            xbps-remove -r $TARGETDIR -Ry "$pkg" >>$LOG 2>&1
        done
        if [ -d "$TARGETDIR/mnt/target" ]; then
            rmdir "$TARGETDIR/mnt/target"
        fi
    else
        # mount required fs
        mount_filesystems
        # network install, use packages.
        install_packages
    fi

    INFOBOX "Applying installer settings..." 4 60

    # copy target fstab.
    install -Dm644 $TARGET_FSTAB $TARGETDIR/etc/fstab
    # Mount /tmp as tmpfs.
    echo "tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0" >> $TARGETDIR/etc/fstab


    # set up keymap, locale, timezone, hostname, root passwd and user account.
    set_keymap
    set_locale
    set_timezone
    set_hostname
    set_rootpassword
    set_useraccount

    # Copy /etc/skel files for root.
    cp $TARGETDIR/etc/skel/.[bix]* $TARGETDIR/root

    NETWORK_DONE="$(get_option NETWORK)"
    # network settings for target
    if [ -n "$NETWORK_DONE" ]; then
        local net="$(get_option NETWORK)"
        set -- ${net}
        local _dev="$1" _type="$2" _ip="$3" _gw="$4" _dns1="$5" _dns2="$6"
        if [ -z "$_type" ]; then
            # network type empty??!!!
            :
        elif [ "$_type" = "dhcp" ]; then
            if $(echo $_dev|egrep -q "^wl.*" 2>/dev/null); then
                cp /etc/wpa_supplicant/wpa_supplicant.conf $TARGETDIR/etc/wpa_supplicant
                enable_service wpa_supplicant
            fi
            enable_service dhcpcd
        elif [ -n "$_dev" -a "$_type" = "static" ]; then
            # static IP through dhcpcd.
            mv $TARGETDIR/etc/dhcpcd.conf $TARGETDIR/etc/dhcpcd.conf.orig
            echo "# Static IP configuration set by the void-installer for $_dev." \
                >$TARGETDIR/etc/dhcpcd.conf
            echo "interface $_dev" >>$TARGETDIR/etc/dhcpcd.conf
            echo "static ip_address=$_ip" >>$TARGETDIR/etc/dhcpcd.conf
            echo "static routers=$_gw" >>$TARGETDIR/etc/dhcpcd.conf
            echo "static domain_name_servers=$_dns1 $_dns2" >>$TARGETDIR/etc/dhcpcd.conf
            enable_service dhcpcd
        fi
    fi

    if [ -d $TARGETDIR/etc/sudoers.d ]; then
        USERLOGIN="$(get_option USERLOGIN)"
        if [ -z "$(echo $(get_option USERGROUPS) | grep -w wheel)" -a -n "$USERLOGIN" ]; then
            # enable sudo for primary user USERLOGIN who is not member of wheel
            echo "# Enable sudo for login '$USERLOGIN'" > "$TARGETDIR/etc/sudoers.d/$USERLOGIN"
            echo "$USERLOGIN ALL=(ALL:ALL) ALL" >> "$TARGETDIR/etc/sudoers.d/$USERLOGIN"
        else
            # enable the sudoers entry for members of group wheel
            echo "%wheel ALL=(ALL:ALL) ALL" > "$TARGETDIR/etc/sudoers.d/wheel"
        fi
        unset USERLOGIN
    fi

    # clean up polkit rule - it's only useful in live systems
    rm -f $TARGETDIR/etc/polkit-1/rules.d/void-live.rules

    # enable text console for grub if chosen
    if [ "$(get_option TEXTCONSOLE)" = "1" ]; then
        sed -i $TARGETDIR/etc/default/grub \
            -e 's|#\(GRUB_TERMINAL_INPUT\).*|\1=console|' \
            -e 's|#\(GRUB_TERMINAL_OUTPUT\).*|\1=console|'
    fi

    if [ -n "$GUIDED_DISK" ]; then
        configure_guided_boot
    fi

    if [ -n "$GUIDED_DISK" ] && [ "$source" = net ]; then
        configure_guided_network_profile
    fi

    # install bootloader.
    set_bootloader

    # menu for enabling services
    menu_services

    sync && sync && sync

    # unmount all filesystems.
    if ! umount_filesystems && [ -n "$GUIDED_DISK" ]; then
        guided_error "Failed to unmount the target or close the encrypted mapping."
    fi

    # installed successfully.
    DIALOG --yesno "${BOLD}Void Linux has been installed successfully!${RESET}\n
Do you want to reboot the system?" ${YESNOSIZE}
    if [ $? -eq 0 ]; then
        shutdown -r now
    else
        return
    fi
}

menu_source() {
    local src= choice

    if guided_supported; then
        DIALOG --title " Select installation profile " --menu \
            "Local copies the live system. The other choices download from Void's repositories." \
            ${MENUSIZE} \
            "Local" "Live ISO desktop, offline" \
            "Base" "Console only" \
            "Plasma" "KDE Plasma desktop" \
            "Xfce" "Xfce desktop" \
            "GNOME" "GNOME desktop" \
            "LXQt" "Lightweight Qt desktop" || return 1
        choice=$(cat "$ANSWER")
        if [ "$choice" = Local ]; then
            set_option DESKTOP Local
            set_option SOURCE local
        else
            set_option DESKTOP "$choice"
            set_option SOURCE net
        fi
        SOURCE_DONE=1
        return
    fi

    DIALOG --title " Select installation source " \
        --menu "$MENULABEL" 8 70 0 \
        "Local" "Packages from ISO image" \
        "Network" "Base system only, downloaded from official repository"
    case "$(cat $ANSWER)" in
        "Local") src="local";;
        "Network") src="net";
            if [ -z "$NETWORK_DONE" ]; then
                if test_network; then
                    menu_network
                fi
            fi;;
        *) return 1;;
    esac
    SOURCE_DONE=1
    set_option SOURCE $src
}

menu_mirror() {
    xmirror 2>$LOG && MIRROR_DONE=1
}

menu() {
    local AFTER_HOSTNAME arch after_useraccount=BootLoader
    local -a storage_entries=(
        "BootLoader" "Set disk to install bootloader"
        "Partition" "Partition disk(s)"
        "Filesystems" "Configure filesystems and mount points"
    )
    arch=$(xbps-uhelper arch)
    if guided_supported; then
        storage_entries=("Guided" "Set disk, encryption, and swap")
        after_useraccount=Guided
    fi
    if [ -z "$DEFITEM" ]; then
        DEFITEM="Keyboard"
    fi

    if [[ "$arch" = *-musl ]]; then
        AFTER_HOSTNAME="Timezone"
        DIALOG --default-item $DEFITEM \
            --extra-button --extra-label "Settings" \
            --title " Void Linux installation menu " \
            --menu "$MENULABEL" 10 70 0 \
            "Keyboard" "Set system keyboard" \
            "Network" "Set up the network" \
            "Source" "Set source installation" \
            "Mirror" "Select XBPS mirror" \
            "Hostname" "Set system hostname" \
            "Timezone" "Set system time zone" \
            "RootPassword" "Set system root password" \
            "UserAccount" "Set primary user name and password" \
            "BootLoader" "Set disk to install bootloader" \
            "Partition" "Partition disk(s)" \
            "Filesystems" "Configure filesystems and mount points" \
            "Install" "Start installation with saved settings" \
            "Exit" "Exit installation"
    else
        AFTER_HOSTNAME="Locale"
        DIALOG --default-item $DEFITEM \
            --extra-button --extra-label "Settings" \
            --title " Void Linux installation menu " \
            --menu "$MENULABEL" 10 70 0 \
            "Keyboard" "Set system keyboard" \
            "Network" "Set up the network" \
            "Source" "Set source installation" \
            "Mirror" "Select XBPS mirror" \
            "Hostname" "Set system hostname" \
            "Locale" "Set system locale" \
            "Timezone" "Set system time zone" \
            "RootPassword" "Set system root password" \
            "UserAccount" "Set primary user name and password" \
            "${storage_entries[@]}" \
            "Install" "Start installation with saved settings" \
            "Exit" "Exit installation"
    fi

    if [ $? -eq 3 ]; then
        local settings
        settings=$(mktemp -t vinstall-settings-XXXXXXXX) || return 1
        sed -E 's/^(ROOTPASSWORD|USERPASSWORD) .*/\1 <-hidden->/' "$CONF_FILE" >"$settings"
        DIALOG --title "Saved settings for installation" --textbox "$settings" 14 60
        rm -f "$settings"
        return
    fi

    case $(cat $ANSWER) in
        "Keyboard") menu_keymap && [ -n "$KEYBOARD_DONE" ] && DEFITEM="Network";;
        "Network") menu_network && [ -n "$NETWORK_DONE" ] && DEFITEM="Source";;
        "Source") menu_source && [ -n "$SOURCE_DONE" ] && DEFITEM="Mirror";;
        "Mirror") menu_mirror && [ -n "$MIRROR_DONE" ] && DEFITEM="Hostname";;
        "Hostname") menu_hostname && [ -n "$HOSTNAME_DONE" ] && DEFITEM="$AFTER_HOSTNAME";;
        "Locale") menu_locale && [ -n "$LOCALE_DONE" ] && DEFITEM="Timezone";;
        "Timezone") menu_timezone && [ -n "$TIMEZONE_DONE" ] && DEFITEM="RootPassword";;
        "RootPassword") menu_rootpassword && [ -n "$ROOTPASSWORD_DONE" ] && DEFITEM="UserAccount";;
        "UserAccount") menu_useraccount && [ -n "$USERLOGIN_DONE" ] && [ -n "$USERPASSWORD_DONE" ] \
               && DEFITEM="$after_useraccount";;
        "BootLoader") menu_bootloader && [ -n "$BOOTLOADER_DONE" ] && DEFITEM="Partition";;
        "Guided") menu_guided_storage && DEFITEM="Install";;
        "Partition") GUIDED_DISK=; menu_partitions && [ -n "$PARTITIONS_DONE" ] && DEFITEM="Filesystems";;
        "Filesystems") GUIDED_DISK=; menu_filesystems && [ -n "$FILESYSTEMS_DONE" ] && DEFITEM="Install";;
        "Install") menu_install;;
        "Exit") DIE;;
        *) DIALOG --yesno "Abort Installation?" ${YESNOSIZE} && DIE
    esac
}

if ! command -v dialog >/dev/null; then
    echo "ERROR: missing dialog command, exiting..."
    exit 1
fi

if [ "$(id -u)" != "0" ]; then
   echo "void-installer must run as root" 1>&2
   exit 1
fi

#
# main()
#
DIALOG --title "${BOLD}${RED} Enter the void ... ${RESET}" --msgbox "\n
Welcome to the Void Linux installation. A simple and minimal \
Linux distribution made from scratch and built from the source package tree \
available for XBPS, a new alternative binary package system.\n\n
The installation should be pretty straightforward. If you are in trouble \
please join us at ${BOLD}#voidlinux${RESET} on ${BOLD}irc.libera.chat${RESET}.\n\n
${BOLD}https://www.voidlinux.org${RESET}\n\n" 16 80

while true; do
    menu
done

exit 0
# vim: set ts=4 sw=4 et:
