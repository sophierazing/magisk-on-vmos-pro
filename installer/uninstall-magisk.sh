#!/system/bin/sh
echo "开始卸载Magisk"
echo "检测是否已安装Magisk"
if [ ! -f "/sbin/magisk" ]; then
  echo "未安装Magisk"
  exit 1
else
  echo "已安装Magisk"
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
  rm -f "$(dirname "$0")/卸载Magisk.sh"
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
  rm -f "$(dirname "$0")/卸载Magisk.sh"
  exit 1
fi
echo "检测是否已解压临时文件"
if [ -d "$(dirname "$0")/临时文件/" ]; then
  echo "已解压临时文件"
else
  echo "没有临时文件"
  echo "请确保已解压临时文件"
  #设置其他文件
  rm -f "$(dirname "$0")/卸载Magisk.sh"
  exit 1
fi
echo "删除目录"
#卸载模块
for module in /data/adb/modules/*; do
  #模块目录
  dir=$(echo "$module" | sed "s/modules/modules_update/")
  #检测目录
  [ ! -d "$dir" ] && dir=$module
  #执行文件
  sh $dir/uninstall.sh > /dev/null 2>&1
  sh /data/adb/load-module/backup/remove-$(basename $dir).sh > /dev/null 2>&1
done

#删除/sbin/.magisk/目录
rm -rf /sbin/.magisk/

#删除/data/adb/内的目录
rm -rf /data/adb/load-module/
rm -r /data/adb/magisk/
rm -rf /data/adb/modules/
rm -rf /data/adb/modules_update/
rm -r /data/adb/post-fs-data.d/
rm -r /data/adb/service.d/
echo "删除文件"
#删除/sbin/内的文件
rm /sbin/magisk*
rm /sbin/su*
rm /sbin/resetprop

#删除magisk.db
rm -f /data/adb/magisk.db

#删除magisk.log
rm -f /cache/magisk.log*

#删除magisk.rc
rm -f /system/etc/init/magisk.rc
echo "卸载Magisk App"
pm uninstall com.topjohnwu.magisk > /dev/null 2>&1
echo "设置其他文件"
rm -f "$(dirname "$0")/重新查看注意事项.sh"
cp -f "$(dirname "$0")/临时文件/scripts/install-magisk.sh" "$(dirname "$0")/安装Magisk.sh"
echo "卸载成功"
#删除文件
rm -f "$(dirname "$0")/卸载Magisk.sh"
exit 0