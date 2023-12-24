#!/system/bin/sh
#######################################################################################
# Magisk On System Installer
#######################################################################################

############
# Functions
############

# Pure bash dirname implementation
getdir() {
  case "$1" in
    */*)
      dir=${1%/*}
      if [ -z $dir ]; then
        echo "/"
      else
        echo $dir
      fi
    ;;
    *) echo "." ;;
  esac
}

#################
# Initialization
#################

# Check Magisk State
[ -f "$ROOTFS/sbin/magisk" ] && exit

if [ -z $SOURCEDMODE ]; then
  # Switch to the location of the script file
  cd "$(getdir "${BASH_SOURCE:-$0}")"
  # Load utility functions
  . ./util_functions.sh
fi

chmod -R 755 .

#########
# Installer
#########

ui_print "- Extracting Magisk files"

mkdir -m 755 $ROOTFS/sbin/.magisk/
mkdir -m 777 $ROOTFS/sbin/.magisk/block/
mkdir -m 777 $ROOTFS/sbin/.magisk/mirror/
mkdir -m 777 $ROOTFS/sbin/.magisk/worker/

mkdir -m 755 $ROOTFS/data/adb/magisk/
mkdir -m 755 $ROOTFS/data/adb/magisk/chromeos/
mkdir -m 755 $ROOTFS/data/adb/post-fs-data.d/
mkdir -m 755 $ROOTFS/data/adb/service.d/

mkdir -m 755 $ROOTFS/data/adb/load-module/
mkdir -m 755 $ROOTFS/data/adb/load-module/backup/
mkdir -m 755 $ROOTFS/data/adb/load-module/config/

touch $ROOTFS/sbin/.magisk/config

cp ./magisk32 $ROOTFS/sbin/magisk32
cp ./magisk64 $ROOTFS/sbin/magisk64
cp ./magiskpolicy $ROOTFS/sbin/magiskpolicy
cp ./magiskinit $ROOTFS/sbin/magiskinit

chmod 755 $ROOTFS/sbin/magisk*
chmod 750 $ROOTFS/sbin/magiskinit

ln -s $ROOTFS/data/adb/modules $ROOTFS/sbin/.magisk/modules

ln -s $ROOTFS/sbin/magisk64 $ROOTFS/sbin/magisk
ln -s $ROOTFS/sbin/magisk $ROOTFS/sbin/resetprop
ln -s $ROOTFS/sbin/magiskpolicy $ROOTFS/sbin/supolicy
ln -s $ROOTFS/sbin/magisk $ROOTFS/sbin/su

cp ./busybox-o $ROOTFS/data/adb/magisk/busybox
cp ./magisk32 $ROOTFS/data/adb/magisk/magisk32
cp ./magisk64 $ROOTFS/data/adb/magisk/magisk64
cp ./magiskpolicy $ROOTFS/data/adb/magisk/magiskpolicy
cp ./magiskinit $ROOTFS/data/adb/magisk/magiskinit
cp ./magiskboot $ROOTFS/data/adb/magisk/magiskboot
cp ./addon.d.sh $ROOTFS/data/adb/magisk/addon.d.sh
cp ./installer.sh $ROOTFS/data/adb/magisk/installer.sh
cp ./util_functions.sh $ROOTFS/data/adb/magisk/util_functions.sh
cp ./stub.apk $ROOTFS/data/adb/magisk/stub.apk
cp -r ./chromeos/* $ROOTFS/data/adb/magisk/chromeos/

chmod 755 -R $ROOTFS/data/adb/magisk/

echo '#!/system/bin/sh\n#加载列表\nlist=/data/adb/load-module/config/load-list\n#清理列表\nsed -i "/^$/d" $list\n#删除文件\nfor module in $(cat $list); do\n  #检测状态\n  [ ! -f "$module/update" -a ! -f "$module/skip_mount" -a ! -f "$module/disable" -a ! -f "$module/remove" ] && continue\n  #重启服务\n  [ -z "$restart" ] && stop zygote && stop zygote_secondary && restart=true\n  #执行文件\n  sh /data/adb/load-module/backup/remove-$(basename $module).sh > /dev/null 2>&1\n  #删除文件\n  rm -f /data/adb/load-module/backup/remove-$(basename $module).sh\n  #修改文件\n  sed -i "s|$module||" $list\ndone\n#创建文件\ntouch /data/adb/continue-magisk\n#等待加载\nwhile [ -z "$(cat /cache/magisk.log | grep "* Loading modules")" ]; do sleep 0.0; done\n#加载文件\nfor module in /data/adb/modules/*; do\n  #检测状态\n  [ -f "$module/disable" ] && continue\n  #修改属性\n  for prop in $(cat "$module/system.prop"); do\n    echo "$prop" | sed "s/=/ /" | xargs setprop\n  done\n  #检测状态\n  [ "$(cat $list | grep "$module")" ] || [ -f "$module/skip_mount" ] || [ ! -d "$module/system/" ] && continue\n  #重启服务\n  [ -z "$restart" ] && stop zygote && stop zygote_secondary && restart=true\n  #切换目录\n  cd "$module/system"\n  #加载文件\n  for file in $(find); do\n    #目标文件\n    target=$(echo "$file" | sed "s/..//")\n    #检查类型\n    if [ -f "$module/system/$target" ]; then\n      #备份文件\n      if [ -f "/system/$target" ]; then\n        #检查文件\n        [ -f "/data/adb/load-module/backup/system/$target" ] && continue\n        #创建目录\n        mkdir -p "/data/adb/load-module/backup/system/$(dirname "$target")" > /dev/null 2>&1\n        #复制文件\n        cp -p "/system/$target" "/data/adb/load-module/backup/system/$target" || continue\n        #修改文件\n        echo -e "cp -p /data/adb/load-module/backup/system/$target /system/$target\nrm /data/adb/load-module/backup/system/$target" >> /data/adb/load-module/backup/remove-$(basename $module).sh\n      else\n        #修改文件\n        echo "rm -f /system/$target" >> /data/adb/load-module/backup/remove-$(basename $module).sh\n      fi\n      #复制文件\n      cp -fp "$module/system/$target" "/system/$target"\n    elif [ -d "$module/system/$target" ]; then\n      #检查目录\n      [ -d "/system/$target" ] && continue\n      #创建目录\n      mkdir -m 755 "/system/$target"\n      #修改文件\n      echo "rm -rf /system/$target" >> /data/adb/load-module/backup/remove-$(basename $module).sh\n    fi\n  done\n  #修改文件\n  echo "$module" >> $list\ndone\n#重启服务\n[ "$restart" ] && start zygote && start zygote_secondary\nexit 0' > $ROOTFS/data/adb/load-module/load-modules.sh
echo '#删除文件\nrm -f /data/adb/continue-magisk\n#加载模块\n/system/bin/sh /data/adb/load-module/load-modules.sh &\n#等待加载\nwhile [ ! -f "/data/adb/continue-magisk" ]; do sleep 0.0; done\n#删除文件\nrm /data/adb/continue-magisk\nexit 0' > $ROOTFS/data/adb/post-fs-data.d/load-module.sh

touch $ROOTFS/data/adb/load-module/config/load-list

chmod 755 $ROOTFS/data/adb/load-module/load-modules.sh
chmod 755 $ROOTFS/data/adb/post-fs-data.d/load-module.sh

echo -e 'on post-fs-data\n    start logd\n    exec - 0 0 -- /sbin/magisk --post-fs-data\n\non nonencrypted\n    exec - 0 0 -- /sbin/magisk --service\n\non property:vold.decrypt=trigger_restart_framework\n    exec - 0 0 -- /sbin/magisk --service\n\non property:sys.boot_completed=1\n    exec - 0 0 -- /sbin/magisk --boot-complete\n\non property:init.svc.zygote=restarting\n    exec - 0 0 -- /sbin/magisk --zygote-restart\n\non property:init.svc.zygote=stopped\n    exec - 0 0 -- /sbin/magisk --zygote-restart' > $ROOTFS/system/etc/init/magisk.rc

chmod 644 $ROOTFS/system/etc/init/magisk.rc

ui_print "- Run Magisk Daemon"

cd /
export MAGISKTMP=/sbin

/sbin/magisk --post-fs-data
/sbin/magisk --service
/sbin/magisk --boot-complete