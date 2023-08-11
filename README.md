# Magisk On System

#### 介绍
在不修改boot或recovery的情况下，通过修改/system实现root
感谢Magisk Delta，Enmmmmm

#### 软件架构
软件架构说明


#### 安装教程

1.  前往Release页面下载对应架构对应版本的zip文件
2.  将其解压至/system/etc/init
3.  adb shell su chmod 777 -R /system/etc/init/magisk.rc
4.  adb shell su chmod 777 -R /system/etc/init/magisk
5.  adb shell su pm install /system/etc/init/magisk.apk
6.  重启以后打开Magisk APP检测root权限

#### 使用说明

注：该方法需要操作system分区，如无法操作system分区，请不要使用此方案

#### 参与贡献

1. 早茶光
2. Enmmmm
