##################################
# Magisk app internal scripts
##################################

run_delay() {
  (sleep $1; $2)&
}

env_check() {
  for file in magiskboot magiskinit util_functions.sh boot_patch.sh; do
    [ -f "$MAGISKBIN/$file" ] || return 1
  done
  if [ "$2" -ge 25000 ]; then
    [ -f "$MAGISKBIN/magiskpolicy" ] || return 1
  fi
  grep -xqF "MAGISK_VER='$1'" "$MAGISKBIN/util_functions.sh" || return 3
  grep -xqF "MAGISK_VER_CODE=$2" "$MAGISKBIN/util_functions.sh" || return 3
  return 0
}

cp_readlink() {
  if [ -z $2 ]; then
    cd $1
  else
    cp -af $1/. $2
    cd $2
  fi
  for file in *; do
    if [ -L $file ]; then
      local full=$(readlink -f $file)
      rm $file
      cp -af $full $file
    fi
  done
  chmod -R 755 .
  cd /
}

fix_env() {
  # Cleanup and make dirs
  rm -rf $MAGISKBIN/*
  mkdir -p $MAGISKBIN 2>/dev/null
  chmod 700 $NVBASE
  cp_readlink $1 $MAGISKBIN
  rm -rf $1
  chown -R 0:0 $MAGISKBIN
}

direct_install() {
  echo "- Flashing new boot image"
  flash_image $1/new-boot.img $2
  case $? in
    1)
      echo "! Insufficient partition size"
      return 1
      ;;
    2)
      echo "! $2 is read only"
      return 2
      ;;
  esac

  rm -f $1/new-boot.img
  fix_env $1
  run_migrations
  copy_preinit_files

  return 0
}

check_install(){
  # Detect Android version/architecture
  api_level_arch_detect

  # Check Android version
  [ "$API" != 28 ] && [ "$API" != 25 ] && exit

  # Check architecture
  [ "$IS64BIT" != true ] && exit
}

run_installer(){
  # Default permissions
  umask 022

  # Detect Android version
  api_level_arch_detect

  MAGISKTMP=/sbin

  ui_print "- Extracting Magisk files"
  for dir in block busybox mirror worker; do
    mkdir -p "$MAGISKTMP"/.magisk/"$dir"/ 2>/dev/null
  done

  touch "$MAGISKTMP"/.magisk/config 2>/dev/null

  for file in magisk32 magisk64 magiskpolicy magiskinit; do
    cp -f ./"$file" "$MAGISKTMP"/"$file" 2>/dev/null

    set_perm "$MAGISKTMP"/"$file" 0 0 0755 2>/dev/null
  done

  set_perm "$MAGISKTMP"/magiskinit 0 0 0750

  [ ! -L "$MAGISKTMP"/.magisk/modules ] && ln -s "$NVBASE"/modules "$MAGISKTMP"/.magisk/modules

  ln -sf "$MAGISKTMP"/magisk64 "$MAGISKTMP"/magisk
  ln -sf "$MAGISKTMP"/magisk "$MAGISKTMP"/resetprop
  ln -sf "$MAGISKTMP"/magiskpolicy "$MAGISKTMP"/supolicy

  if [ ! -f "$MAGISKTMP"/kauditd ]; then
    rm -f "$MAGISKTMP"/su

    cat << 'EOF' > "$MAGISKTMP"/su
#!/system/bin/sh
if [ "$(id -u)" = "0" ]; then
  /sbin/magisk "su" "2000" "-c" "exec "/sbin/magisk" "su" "$@"" || /sbin/magisk "su" "10000"
elif [ "$(id -u)" = "10000" ]; then
  echo "Permission denied"
else
  /sbin/magisk "su" "$@"
fi
EOF

    set_perm "$MAGISKTMP"/su 0 0 0755
  else
    ln -sf "$MAGISKTMP"/magisk "$MAGISKTMP"/su
  fi

  cp -f ./unzip "$MAGISKTMP"/.magisk/busybox/unzip
  cp -f ./awk "$MAGISKTMP"/.magisk/busybox/awk

  set_perm "$MAGISKTMP"/.magisk/busybox/unzip 0 0 0755
  set_perm "$MAGISKTMP"/.magisk/busybox/awk 0 0 0755

  for dir in magisk/chromeos load-module/backup modules post-fs-data.d service.d; do
    mkdir -p "$NVBASE"/"$dir"/ 2>/dev/null
  done

  for file in $(ls ./magisk* ./*.sh) stub.apk; do
    cp -f ./"$file" "$MAGISKBIN"/"$file"
  done

  cp -r ./chromeos/* "$MAGISKBIN"/chromeos/

  set_perm_recursive "$MAGISKBIN"/ 0 0 0755 0755

  cat << 'EOF' > "$NVBASE"/load-module/load-modules.sh
#!/system/bin/sh
#默认权限
umask 022
#数据目录
bin=/data/adb/load-module
#获取输入
if [ -z "$@" ]; then
  exit 1
elif [ "$@" = --post-fs-data ]; then
  #执行文件
  for scripts in /data/adb/post-fs-data.d/*; do
    PATH=/sbin/.magisk/busybox:"$PATH" sh "$scripts" > /dev/null 2>&1
  done
  #更新模块
  for module in /data/adb/modules/*; do
    #检测状态
    if [ -f "$module"/update ]; then
      #模块目录
      dir="$(echo "$module" | sed "s/modules/modules_update/")"
      #检测目录
      if [ -d "$dir" ]; then
        #删除文件
        rm -rf "$module"
        #复制文件
        mv -f "$dir" "$module"
      else
        #删除文件
        rm -f "$module"/update
      fi
    elif [ -f "$module"/remove ]; then
      #执行文件
      PATH=/sbin/.magisk/busybox:"$PATH" sh "$module"/uninstall.sh > /dev/null 2>&1
      #删除文件
      rm -rf "$module"
    else
      #检测状态
      [ ! -f "$module"/skip_mount -a ! -f "$module"/disable ] && continue
    fi
    #重启服务
    if [ -z "$restart" ]; then
      #停止服务
      setprop ctl.stop zygote
      setprop ctl.stop zygote_secondary
      #启用重启
      restart=true
    fi
    #执行文件
    sh "$bin"/backup/remove-"$(basename "$module")".sh > /dev/null 2>&1
    #删除文件
    rm -f "$bin"/backup/remove-"$(basename "$module")".sh
  done
  #删除目录
  rm -rf /data/adb/modules_update/
  #执行文件
  for module in /data/adb/modules/*; do
    #检测状态
    [ -f "$module"/disable ] && continue
    #重启服务
    if [ -z "$restart" ]; then
      #停止服务
      setprop ctl.stop zygote
      setprop ctl.stop zygote_secondary
      #启用重启
      restart=true
    fi
    #执行文件
    PATH=/sbin/.magisk/busybox:"$PATH" sh "$module"/post-fs-data.sh > /dev/null 2>&1
  done
  #加载模块
  for module in /data/adb/modules/*; do
    #检测状态
    [ -f "$module"/disable ] && continue
    #修改属性
    for prop in $(cat "$module"/system.prop 2>/dev/null); do
      echo "$prop" | sed "s/=/ /" | xargs setprop 2>/dev/null
    done
    #检测状态
    [ ! -f "$bin"/backup/remove-"$(basename "$module")".sh -o -f "$module"/skip_mount -o ! -d "$module"/system/ ] && continue
    #重启服务
    if [ -z "$restart" ]; then
      #停止服务
      setprop ctl.stop zygote
      setprop ctl.stop zygote_secondary
      #启用重启
      restart=true
    fi
    #切换目录
    cd "$module"/system
    #加载文件
    for file in $(find); do
      #目标文件
      target="$(echo "$file" | sed "s/..//")"
      #检查类型
      if [ -f "$module"/system/"$target" ]; then
        #备份文件
        if [ -f /system/"$target" ]; then
          #检查文件
          [ -f "$bin"/backup/system/"$target" ] && continue
          #创建目录
          mkdir -p "$bin"/backup/system/"$(dirname "$target")" 2>/dev/null
          #复制文件
          mv /system/"$target" "$bin"/backup/system/"$target" || continue
          #修改文件
          echo -e "mv -f $bin/backup/system/$target /system/$target" >> "$bin"/backup/remove-"$(basename "$module")".sh
        else
          #修改文件
          echo "rm -f /system/$target" >> "$bin"/backup/remove-"$(basename "$module")".sh
        fi
        #复制文件
        cp -fp "$module"/system/"$target" /system/"$target"
      elif [ -d "$module"/system/"$target" ]; then
        #检查目录
        [ -d /system/"$target" ] && continue
        #创建目录
        mkdir /system/"$target"
        #修改文件
        echo "rm -rf /system/$target" >> "$bin"/backup/remove-"$(basename "$module")".sh
      fi
    done
  done
  #重启服务
  if [ "$restart" ]; then
    #启动服务
    setprop ctl.start zygote
    setprop ctl.start zygote_secondary
  fi
elif [ "$@" = --service ]; then
  #执行文件
  for scripts in /data/adb/service.d/*; do
    #执行文件
    PATH=/sbin/.magisk/busybox:"$PATH" sh "$scripts" > /dev/null 2>&1 &
  done
  for module in /data/adb/modules/*; do
    #检测状态
    [ -f "$module"/disable ] && continue
    #执行文件
    PATH=/sbin/.magisk/busybox:"$PATH" sh "$module"/service.sh > /dev/null 2>&1 &
  done
fi
exit 0
EOF

  set_perm "$NVBASE"/load-module/load-modules.sh 0 0 0755

  [ "$API" = 28 ] && TRIGGER=nonencrypted || TRIGGER=boot

  cat << EOF > /system/etc/init/magisk.rc
on post-fs-data
    start logd
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --post-fs-data
    #加载模块
    exec u:r:magisk:s0 0 0 -- /system/bin/sh /data/adb/load-module/load-modules.sh --post-fs-data

on property:vold.decrypt=trigger_restart_framework
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --service
    #执行文件
    exec u:r:magisk:s0 0 0 -- /system/bin/sh /data/adb/load-module/load-modules.sh --service

on $TRIGGER
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --service
    #执行文件
    exec u:r:magisk:s0 0 0 -- /system/bin/sh /data/adb/load-module/load-modules.sh --service

on property:sys.boot_completed=1
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --boot-complete

on property:init.svc.zygote=stopped
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --zygote-restart
EOF

  set_perm /system/etc/init/magisk.rc 0 0 0644

  ui_print "- Launch Magisk Daemon"
  cd /
  export MAGISKTMP

  "$MAGISKTMP"/magisk --post-fs-data
  "$MAGISKTMP"/magisk --service
  "$MAGISKTMP"/magisk --boot-complete
}

run_uninstaller() {
  # Default permissions
  umask 022

  if echo $MAGISK_VER | grep -q '\.'; then
    PRETTY_VER=$MAGISK_VER
  else
    PRETTY_VER="$MAGISK_VER($MAGISK_VER_CODE)"
  fi
  print_title "Magisk $PRETTY_VER Uninstaller"

  ui_print "- Removing modules"
  for module in "$NVBASE"/modules/*; do
    dir="$(echo "$module" | sed "s/modules/modules_update/")"

    [ ! -d "$dir" ] && dir="$module"

    sh "$dir"/uninstall.sh > /dev/null 2>&1
    sh "$NVBASE"/load-module/backup/remove-"$(basename "$module")".sh > /dev/null 2>&1
  done

  ui_print "- Removing Magisk files"
  rm -rf \
/sbin/*magisk* /sbin/su* /sbin/resetprop /sbin/kauditd \
/sbin/.magisk /cache/*magisk* /cache/unblock /data/*magisk* \
/data/cache/*magisk* /data/property/*magisk* /data/Magisk.apk /data/busybox \
/data/custom_ramdisk_patch.sh "$NVBASE"/*magisk* "$NVBASE"/load-module "$NVBASE"/post-fs-data.d \
"$NVBASE"/service.d "$NVBASE"/modules* /data/unencrypted/magisk /metadata/magisk \
/persist/magisk /mnt/vendor/persist/magisk /system/etc/init/magisk.rc /system/etc/init/kauditd.rc

  ui_print "- Done"
}

restore_imgs() {
  [ -z $SHA1 ] && return 1
  local BACKUPDIR=/data/magisk_backup_$SHA1
  [ -d $BACKUPDIR ] || return 1

  get_flags
  find_boot_image

  for name in dtb dtbo; do
    [ -f $BACKUPDIR/${name}.img.gz ] || continue
    local IMAGE=$(find_block $name$SLOT)
    [ -z $IMAGE ] && continue
    flash_image $BACKUPDIR/${name}.img.gz $IMAGE
  done
  [ -f $BACKUPDIR/boot.img.gz ] || return 1
  flash_image $BACKUPDIR/boot.img.gz $BOOTIMAGE
}

post_ota() {
  cd $NVBASE
  cp -f $1 bootctl
  rm -f $1
  chmod 755 bootctl
  ./bootctl hal-info || return
  SLOT_NUM=0
  [ $(./bootctl get-current-slot) -eq 0 ] && SLOT_NUM=1
  ./bootctl set-active-boot-slot $SLOT_NUM
  cat << EOF > post-fs-data.d/post_ota.sh
/data/adb/bootctl mark-boot-successful
rm -f /data/adb/bootctl
rm -f /data/adb/post-fs-data.d/post_ota.sh
EOF
  chmod 755 post-fs-data.d/post_ota.sh
  cd /
}

add_hosts_module() {
  # Do not touch existing hosts module
  [ -d $NVBASE/modules/hosts ] && return
  cd $NVBASE/modules
  mkdir -p hosts/system/etc
  cat << EOF > hosts/module.prop
id=hosts
name=Systemless Hosts
version=1.0
versionCode=1
author=Magisk
description=Magisk app built-in systemless hosts module
EOF
  magisk --clone /system/etc/hosts hosts/system/etc/hosts
  touch hosts/update
  cd /
}

adb_pm_install() {
  local tmp=/data/local/tmp/temp.apk
  cp -f "$1" $tmp
  chmod 644 $tmp
  su 2000 -c pm install -g $tmp || pm install -g $tmp || su 1000 -c pm install -g $tmp
  local res=$?
  rm -f $tmp
  if [ $res = 0 ]; then
    appops set "$2" REQUEST_INSTALL_PACKAGES allow
  fi
  return $res
}

check_boot_ramdisk() {
  # Create boolean ISAB
  ISAB=true
  [ -z $SLOT ] && ISAB=false

  # Override system mode to true
  SYSTEMMODE=true
  return 1
}

check_encryption() {
  if $ISENCRYPTED; then
    if [ $SDK_INT -lt 24 ]; then
      CRYPTOTYPE="block"
    else
      # First see what the system tells us
      CRYPTOTYPE=$(getprop ro.crypto.type)
      if [ -z $CRYPTOTYPE ]; then
        # If not mounting through device mapper, we are FBE
        if grep ' /data ' /proc/mounts | grep -qv 'dm-'; then
          CRYPTOTYPE="file"
        else
          # We are either FDE or metadata encryption (which is also FBE)
          CRYPTOTYPE="block"
          grep -q ' /metadata ' /proc/mounts && CRYPTOTYPE="file"
        fi
      fi
    fi
  else
    CRYPTOTYPE="N/A"
  fi
}

##########################
# Non-root util_functions
##########################

mount_partitions() {
  [ "$(getprop ro.build.ab_update)" = "true" ] && SLOT=$(getprop ro.boot.slot_suffix)
  # Check whether non rootfs root dir exists
  SYSTEM_AS_ROOT=false
  grep ' / ' /proc/mounts | grep -qv 'rootfs' && SYSTEM_AS_ROOT=true

  LEGACYSAR=false
  grep ' / ' /proc/mounts | grep -q '/dev/root' && LEGACYSAR=true
}

get_flags() {
  KEEPVERITY=$SYSTEM_AS_ROOT
  ISENCRYPTED=false
  [ "$(getprop ro.crypto.state)" = "encrypted" ] && ISENCRYPTED=true
  KEEPFORCEENCRYPT=$ISENCRYPTED
  if [ -n "$(getprop ro.boot.vbmeta.device)" -o -n "$(getprop ro.boot.vbmeta.size)" ]; then
    PATCHVBMETAFLAG=false
  elif getprop ro.product.ab_ota_partitions | grep -wq vbmeta; then
    PATCHVBMETAFLAG=false
  else
    PATCHVBMETAFLAG=true
  fi
  [ -z $RECOVERYMODE ] && RECOVERYMODE=false
}

run_migrations() { return; }

grep_prop() { return; }

#############
# Initialize
#############

app_init() {
  mount_partitions
  RAMDISKEXIST=false
  check_boot_ramdisk && RAMDISKEXIST=true
  get_flags
  run_migrations
  SHA1=$(grep_prop SHA1 $MAGISKTMP/.magisk/config)
  check_encryption
}

export BOOTMODE=true
