##################################
# Magisk app internal scripts
##################################

run_delay() {
  (sleep $1; $2)&
}

env_check() {
  for file in busybox magiskboot magiskinit util_functions.sh boot_patch.sh; do
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
  [ "$API" = 28 ] && [ "$API" = 25 ] && exit
}

run_installer(){
  # Default permissions
  umask 022

  # Detect Android version/architecture
  api_level_arch_detect

  MAGISKTMP="$ROOTFS"/sbin

  ui_print "- Extracting Magisk files"
  mkdir -p "$MAGISKTMP"/.magisk/block/ 2>/dev/null
  mkdir "$MAGISKTMP"/.magisk/mirror/ 2>/dev/null
  mkdir "$MAGISKTMP"/.magisk/worker/ 2>/dev/null

  touch "$MAGISKTMP"/.magisk/config 2>/dev/null

  cp -f ./magisk32 "$MAGISKTMP"/magisk32 2>/dev/null
  cp -f ./magisk64 "$MAGISKTMP"/magisk64 2>/dev/null
  cp -f ./magiskpolicy "$MAGISKTMP"/magiskpolicy
  cp -f ./magiskinit "$MAGISKTMP"/magiskinit

  set_perm "$MAGISKTMP"/magisk32 0 0 0755 2>/dev/null
  set_perm "$MAGISKTMP"/magisk64 0 0 0755 2>/dev/null
  set_perm "$MAGISKTMP"/magiskpolicy 0 0 0755
  set_perm "$MAGISKTMP"/magiskinit 0 0 0750

  [ ! -L "$MAGISKTMP"/.magisk/modules ] && ln -s "$NVBASE"/modules "$MAGISKTMP"/.magisk/modules

  if [ "$IS64BIT" = true ]; then
    ln -sf "$MAGISKTMP"/magisk64 "$MAGISKTMP"/magisk
  else
    ln -sf "$MAGISKTMP"/magisk32 "$MAGISKTMP"/magisk
  fi
  ln -sf "$MAGISKTMP"/magisk "$MAGISKTMP"/resetprop
  ln -sf "$MAGISKTMP"/magiskpolicy "$MAGISKTMP"/supolicy

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

  mkdir -p "$MAGISKBIN"/chromeos/ 2>/dev/null
  mkdir "$NVBASE"/post-fs-data.d/ 2>/dev/null
  mkdir "$NVBASE"/service.d/ 2>/dev/null

  for file in $(ls ./magisk*); do cp -f ./$file "$MAGISKBIN"/$file; done

  if [ "$IS64BIT" = true ]; then
    cp -f ./busybox-original "$MAGISKBIN"/busybox
  else
    cp -f ./busybox "$MAGISKBIN"/busybox
  fi
  cp -f ./stub.apk "$MAGISKBIN"/stub.apk
  cp -r ./*.sh "$MAGISKBIN"/
  cp -r ./chromeos/* "$MAGISKBIN"/chromeos/

  set_perm_recursive "$MAGISKBIN"/ 0 0 0755 0755

  mkdir -p "$NVBASE"/load-module/backup/ 2>/dev/null
  mkdir "$NVBASE"/load-module/config/ 2>/dev/null

  [ ! -d "/cache/" ] && mkdir -m 770 /cache/

  cat << 'EOF' > "$NVBASE"/post-fs-data.d/load-modules.sh
#!/system/bin/sh
#默认权限
umask 022
#基础变量
rootfs="$(dir="$(cat /init_shell.sh | xargs -n 1 | grep "init" | sed "s|/init||")"; [ -d "$dir" ] && echo "$dir" || echo "$(echo "$dir" | sed "s|user/0|data|")")"
#数据目录
bin="$rootfs"/data/adb/load-module
#加载列表
list="$bin"/config/load-list
#清理列表
sed -i "/^$/d" "$list"
#恢复更改
for module in $(cat "$list"); do
  #检测状态
  [ ! -f "$module"/update -a ! -f "$module"/skip_mount -a ! -f "$module"/disable -a ! -f "$module"/remove ] && continue
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
  #删除配置
  [ -f "$module"/remove ] && rm -f "$bin"/config/load-"$(basename "$module")"-list
  #修改文件
  sed -i "s|$module||" "$list"
done
#并行运行
{
  #等待加载
  while [ -z "$(cat "$rootfs"/cache/magisk.log | grep "* Loading modules")" ]; do sleep 0.0; done
  #加载模块
  for module in "$rootfs"/data/adb/modules/*; do
    #检测状态
    [ -f "$module"/disable ] && continue
    #修改属性
    for prop in $(cat "$module"/system.prop 2>/dev/null); do
      echo "$prop" | sed "s/=/ /" | xargs setprop 2>/dev/null
    done
    #检测状态
    [ "$(cat "$list" | grep "$module")" -o -f "$module"/skip_mount -o ! -d "$module"/system/ -o ! -f "$bin"/config/load-"$(basename "$module")"-list ] && continue
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
      #加载配置
      config="$(cat "$bin"/config/load-"$(basename "$module")"-list | grep "$rootfs"/system/"$target"= | sed "s/=/\n/" | grep -v "$rootfs"/system/"$target")"
      #检查类型
      if [ -f "$module"/system/"$target" ]; then
        #备份文件
        if [ "$config" = "backup" ]; then
          #检查文件
          [ -f "$bin"/backup/system/"$target" ] && continue
          #创建目录
          mkdir -p "$bin"/backup/system/"$(dirname "$target")" 2>/dev/null
          #复制文件
          cp -p "$rootfs"/system/"$target" "$bin"/backup/system/"$target" || continue
          #修改文件
          echo -e "cp -fp $bin/backup/system/$target $rootfs/system/$target\nrm $bin/backup/system/$target" >> $bin/backup/remove-"$(basename "$module")".sh
        elif [ "$config" = "remove" ]; then
          #修改文件
          echo "rm -f $rootfs/system/$target" >> $bin/backup/remove-"$(basename "$module")".sh
        else
          continue
        fi
        #复制文件
        cp -fp "$module"/system/"$target" "$rootfs"/system/"$target"
      elif [ -d "$module"/system/"$target" ]; then
        #检查目录
        [ -d /system/"$target" -a "$config" != "remove" ] && continue
        #创建目录
        mkdir "$rootfs"/system/"$target" 2>/dev/null
        #修改文件
        echo "rm -rf $rootfs/system/$target" >> $bin/backup/remove-"$(basename "$module")".sh
      fi
    done
    #修改文件
    echo "$module" >> "$list"
  done
  #重启服务
  if [ "$restart" ]; then
    #启动服务
    setprop ctl.start zygote
    setprop ctl.start zygote_secondary
  fi
} &
EOF

  touch "$NVBASE"/load-module/config/load-list 2>/dev/null

  set_perm "$NVBASE"/post-fs-data.d/load-modules.sh 0 0 0755

  [ "$API" = 28 ] && TRIGGER=nonencrypted || TRIGGER=boot

  cat << EOF > "$ROOTFS"/system/etc/init/magisk.rc
on post-fs-data
    start logd
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --post-fs-data

on property:vold.decrypt=trigger_restart_framework
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --service

on $TRIGGER
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --service

on property:sys.boot_completed=1
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --boot-complete

on property:init.svc.zygote=stopped
    exec u:r:magisk:s0 0 0 -- /sbin/magisk --zygote-restart
EOF

  ui_print "- Launch Magisk Daemon"
  cd /
  export MAGISKTMP=/sbin

  /sbin/magisk --post-fs-data
  /sbin/magisk --service
  /sbin/magisk --boot-complete
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
  magisk --remove-modules -n

  for scripts in "$NVBASE"/load-module/backup/remove-*.sh; do sh $scripts; done

  ui_print "- Removing Magisk files"
  rm -rf \
"$ROOTFS"/sbin/*magisk* "$ROOTFS"/sbin/su* "$ROOTFS"/sbin/resetprop "$ROOTFS"/sbin/.magisk \
"$ROOTFS"/cache/*magisk* "$ROOTFS"/cache/unblock "$ROOTFS"/data/*magisk* "$ROOTFS"/data/cache/*magisk* \
"$ROOTFS"/data/property/*magisk* "$ROOTFS"/data/Magisk.apk "$ROOTFS"/data/busybox "$ROOTFS"/data/custom_ramdisk_patch.sh \
"$NVBASE"/*magisk* "$NVBASE"/load-module "$NVBASE"/post-fs-data.d "$NVBASE"/service.d \
"$NVBASE"/modules* "$ROOTFS"/data/local/tmp/busybox "$ROOTFS"/data/unencrypted/magisk "$ROOTFS"/metadata/magisk \
"$ROOTFS"/persist/magisk "$ROOTFS"/mnt/vendor/persist/magisk "$ROOTFS"/system/etc/init/magisk.rc

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
