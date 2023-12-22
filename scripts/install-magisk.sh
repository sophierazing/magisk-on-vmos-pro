#!/system/bin/sh
echo "开始安装Magisk"
echo "检测是否已安装Magisk"
if [ ! -f "/sbin/magisk" ]; then
  echo "未安装Magisk"
else
  echo "已安装Magisk"
  exit 1
fi
echo "检测权限"
if [ "$(whoami)" = "root" ]; then
  echo "正在使用Root权限执行脚本"
else
  echo "未使用Root权限执行脚本"
  exit 1
fi
echo "获取SDK/ABI"
#获取SDK
SDK=$(cat /system/build.prop | sed -n "s/^ro.build.version.sdk=//p" | head -n 1)
if [ -z "$SDK" ]; then
  echo "获取SDK失败" >&2
  exit 1
elif [ "$SDK" = "28" ]; then
  echo "正在使用Android 9.0" >&2
elif [ "$SDK" = "25" ]; then
  echo "正在使用Android 7.1.2" >&2
else
  echo "不支持当前Android版本"
  echo "请切换至受支持的Android 7.1.2/9.0" >&2
  #设置其他文件
  rm -rf "$(dirname "$0")/临时文件/"
  rm -f "$(dirname "$0")/安装Magisk.sh"
  exit 1
fi

#获取ABI
ABI=$(cat /system/build.prop | sed -n "s/^ro.product.cpu.abi=//p" | head -n 1)
if [ -z "$ABI" ]; then
  echo "获取ABI失败" >&2
  exit 1
elif [ "$ABI" = "arm64-v8a" ]; then
  echo "正在使用64位系统" >&2
else
  echo "不支持当前系统"
  echo "请切换至受支持的64位系统" >&2
  #设置其他文件
  rm -rf "$(dirname "$0")/临时文件/"
  rm -f "$(dirname "$0")/安装Magisk.sh"
  exit 1
fi
echo "检测是否已解压临时文件"
if [ -d "$(dirname "$0")/临时文件/" ]; then
  echo "已解压临时文件"
else
  echo "没有临时文件"
  echo "请确保已解压临时文件"
  #设置其他文件
  rm -f "$(dirname "$0")/安装Magisk.sh"
  exit 1
fi
echo "创建目录并设置权限"
mkdir -m 755 /sbin/.magisk/
mkdir -m 777 /sbin/.magisk/block/
mkdir -m 777 /sbin/.magisk/mirror/
mkdir -m 755 /data/adb/magisk/
mkdir -m 755 /data/adb/post-fs-data.d/
mkdir -m 755 /data/adb/service.d/
mkdir -m 755 /data/adb/load-module/
mkdir -m 755 /data/adb/load-module/backup/
mkdir -m 755 /data/adb/load-module/config/
echo "复制文件并设置权限"
#切换目录
cd "$(dirname "$0")/临时文件/files"

#创建文件
touch /sbin/.magisk/config
#设置权限
chmod 600 /sbin/.magisk/config

#复制文件到/sbin/
cp ./magisk32 /sbin/magisk32
cp ./magisk64 /sbin/magisk64
cp ./magiskinit /sbin/magiskinit
#设置权限
chmod 755 /sbin/magisk*
#链接目录
ln -s /data/adb/modules /sbin/.magisk/modules
#链接文件
ln -s /sbin/magisk64 /sbin/magisk
ln -s /sbin/magiskinit /sbin/magiskpolicy
ln -s /sbin/magisk /sbin/resetprop
ln -s /sbin/magiskpolicy /sbin/supolicy
ln -s /sbin/magisk /sbin/su

#复制文件到/data/adb/magisk/
cp -r ./* /data/adb/magisk/
#删除目录
rm -r /data/adb/magisk/other/
#设置权限
chmod 755 -R /data/adb/magisk/

#复制load-modules.sh
cp ./other/load-modules.sh /data/adb/load-module/load-modules.sh
cp ./other/load-module.sh /data/adb/post-fs-data.d/load-module.sh
#创建文件
touch /data/adb/load-module/config/load-list
#设置权限
chmod 755 /data/adb/load-module/load-modules.sh
chmod 755 /data/adb/post-fs-data.d/load-module.sh

#复制magisk.rc
cp ./other/magisk.rc /system/etc/init/magisk.rc
#设置权限
chmod 644 /system/etc/init/magisk.rc
echo "安装Magisk App"
pm install ./magisk.apk > /dev/null 2>&1
echo "启动Magisk守护进程"
#切换目录
cd /
#启动Magisk守护进程
/sbin/magisk --post-fs-data
/sbin/magisk --service
/sbin/magisk --boot-complete
echo "设置其他文件"
if [ ! -f "$(dirname "$0")/临时文件/scripts/install-magisk.sh" ]; then
  cp -f "$(dirname "$0")/安装Magisk.sh" "$(dirname "$0")/临时文件/scripts/install-magisk.sh"
fi
cp -f "$(dirname "$0")/临时文件/scripts/uninstall-magisk.sh" "$(dirname "$0")/卸载Magisk.sh"
cp -f "$(dirname "$0")/临时文件/scripts/tips.sh" "$(dirname "$0")/重新查看注意事项.sh"
echo -e "安装成功\n"
#执行文件
sh "$(dirname "$0")/重新查看注意事项.sh"
#删除文件
rm -f "$(dirname "$0")/安装Magisk.sh"
exit 0