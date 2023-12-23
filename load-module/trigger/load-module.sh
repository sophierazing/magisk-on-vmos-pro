#!/system/bin/sh
#删除文件
rm -f /data/adb/continue-magisk
#加载模块
/system/bin/sh /data/adb/load-module/load-modules.sh &
#等待加载
while [ ! -f "/data/adb/continue-magisk" ]; do sleep 0.0; done
#删除文件
rm /data/adb/continue-magisk
exit 0