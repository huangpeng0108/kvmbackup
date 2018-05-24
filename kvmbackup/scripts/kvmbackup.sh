#!/bin/bash
HOSTNAME=`hostname`
DATE="/bin/date"
CONF_FILE=`dirname $0`/"../conf/kvm.conf"
SCRIPT_PREFIX="kvmlvm"
DATE_FORMATED=`$DATE "+%Y%m%d_%H%M%S"`
PREFIX="$DATE_FORMATED"_"$HOSTNAME"
PREFIX_BACKUP="$DATE_FORMATED"_"$HOSTNAME"


#function useage
function useage()
{
echo "usage $0:[-t [test]] -h help"
}

#function getopts 
function get_opts()
{
 # "-h | --help                        -- display help (this)"
 # "t | --test                        -- just test"
TEST=0
while getopts h:p:t OPTION
do
   case  $OPTION in 
     t) TEST=1
     ;;
     p) PREFIX=$OPTARG
     ;;
     h) useage
     exit 0
     ;;
     ?)
     useage 
     exit 0
     ;;
   esac
done
}


check_root(){
     if [ $((UID)) -ne 0 ]; then
        echo "You need to run this script as ROOT" >&2
        exit 1
    fi

}


binary_check() {
        if [ -z "$1" ]; then
                echo "missing argument" >&2
                exit 1
        fi
        if [ ! -e "$1" -o ! -x "$1" ]; then
                echo "'$1' is not a valid binary, please correct the binary definition" >&2
                exit 1
        fi
}

function check_work_env()
{
LVCREATE="/sbin/lvcreate"               # to create the snapshot
LVREMOVE="/sbin/lvremove"               # to remove the snapshot
VGDISPLAY="/sbin/vgdisplay"     # to check on the available disk space for the snapshot
LVDISPLAY="/sbin/lvdisplay"     # to check on the available disk space for the snapshot
LVS="/sbin/lvs"                                 # to provide a list of detailed info for the VG and LV
MOUNT="/bin/mount"
UMOUNT="/bin/umount"
DATE="/bin/date"
SENDMAIL="/usr/sbin/sendmail"
NFSSTAT="/usr/sbin/nfsstat"

binary_check $LVCREATE
binary_check $LVREMOVE
binary_check $VGDISPLAY
binary_check $LVDISPLAY
binary_check $MOUNT
binary_check $UMOUNT
binary_check $SENDMAIL
binary_check $DATE
binary_check $NFSSTAT
}

function set_work_env()
{
 if [ -f "$CONF_FILE" -a -r "$CONF_FILE" ]; then
    source $CONF_FILE
 elif [ ! -f "$CONFIG_FILE" ] ; then
   echo "config file $CONF_FILE not found" >&2
   exit 1
  elif [ -s "$CONF_FILE" -o ! -r "$CONF_FILE" -o ! -f "$CONF_FILE" -o -z "$CONF_FILE" ]; then
    echo "$CONF_FILE is invalid - check permissions / content / path" >&2
   exit 2
else
   echo "no config found" >&2
   exit 2
fi 
}



#add / to the end of dir path
function file_add_slash()
{
local FILE_NAME="$1"
NEW_FILE=`echo $FILE_NAME | sed 's#/$##g'`"/"
echo $NEW_FILE
}

#remove dir path end /
function file_remove_slash()
{
local FILE_NAME="$1"
NEW_FILE=`echo $FILE_NAME | sed 's#/$##g'`
echo $NEW_FILE
}


#check enviroment 
function check_param()
{
  if [ -z "$SCRIPT_PREFIX" ]; then
     echo "Missing script prefix" >&2
     exit 2
   fi

  if [ -z "$MAIL_REPORT_ADDRESS" ]; then
     echo "Missing mail report address" >&2
     exit 2
   fi

  if [ -z "$NFS_SERVER" ]; then
     echo "Missing nfs server ip address" >&2
     exit 2
   fi

  if [ -z "$NFS_RDIR" ]; then
     echo "Missing nfs remote dir" >&2
     exit 2
   fi

  if [ -z "$NFS_LDIR" ]; then
     echo "Missing nfs local mount dir" >&2
     exit 2
   fi
  if [ ${NFS_RDIR:0:1} != '/' ]; then
      echo "Need FULL PATH for nfs remote dir" >&2
      exit 2
   fi
  if [ ${NFS_LDIR:0:1} != '/' ]; then
      echo "Need FULL PATH for nfs local dir" >&2
      exit 2
   fi

}


function check_nfsmount()
{
MOUNT_COUNT=`$NFSSTAT -m | grep -v Flags | grep "$NFS_LDIR from $NFS_SERVER:$NFS_RDIR" | wc -l`
[ $? -ne 0 ] &&echo "get nfsstat error" >&2 &&return 1
if [ $MOUNT_COUNT -ge 1 ] ; then
  echo "$NFS_SERVER:$NFS_RDIR has mount on $NFS_LDIR" 
  return 0
else 
   echo "$NFS_SERVER:$NFS_RDIR have not mount on $NFS_LDIR"
   return 1
fi
}

function mount_nfs()
{
mkdir -p $NFS_LDIR
check_nfsmount
if [ "$?" -eq 0 ]; then
   echo "nfs already $NFS_SERVER:$NFS_RDIR mount on $NFS_LDIR do nothing"
else
  echo "begin mount nfs $NFS_SERVER:$NFS_RDIR on $NFS_LDIR"
  $MOUNT -t nfs $NFS_SERVER:$NFS_RDIR  $NFS_LDIR
  if [ "$?" -eq 0 ] ; then
    echo "mount $NFS_SERVER:$NFS_RDIR on $NFS_LDIR success"
  else
    echo "mount $NFS_SERVER:$NFS_RDIR on $NFS_LDIR failed" >&2
    exit 1
  fi
fi
mkdir -p $NFS_LDIR/$HOSTNAME
check_nfs_perm
}

function check_nfs_perm()
{
if [ ! -d $NFS_LDIR/$HOSTNAME ];then
    mkdir -p $NFS_LDIR/$HOSTNAME
    [ $? -ne 0 ] && echo "create directory $NFS_LDIR/$HOSTNAME failed" >&2 && exit 1
 ## Check for writable destination
  if [ ! -w "$NFS_LDIR/$HOSTNAME" ]; then
     echo "$NFS_LDIR/$HOSTNAME" folder is not writable, check permissions" >&2
     echo "current owner UID: $UID" >&2
     echo "current PWD: $PWD" >&2
     echo " user@host:~$ ls -la "$NFS_LDIR/$HOSTNAME" >&2
     ls -la "$NFS_LDIR/$HOSTNAME" >&2
     exit 2
   fi
fi
# write check
mkdir -p $NFS_LDIR/$HOSTNAME && echo `hostname` >$NFS_LDIR/$HOSTNAME/$HOSTNAME && rm -f $NFS_LDIR/$HOSTNAME/$HOSTNAME
if [ $? -ne 0 ] ; then
   echo "no permission on $NFS_SERVER:$NFS_RDIR " >&2
   exit 1
fi

}

function umount_nfs()
{
$UMOUNT $NFS_LDIR
if [ $? -eq 0 ] ; then
 echo "umount $NFS_LDIR success"
else
  echo "umount $NFS_LDIR failed" >&2
  $UMOUNT -f $NFS_LDIR
  $UMOUNT -l $NFS_LDIR
  exit 1
fi
/bin/rmdir $NFS_LDIR
[ $? -ne 0 ] && echo "remove $NFS_LDIR failed" >&2 && exit 1

}

function checklvm()
{
   if [ -z "$KVM_VG" ]; then
      echo "Missing volume groupe (VG) - please configure KVM_VG" >&2
      exit 1
   fi
   if [ -z "$KVM_LV" ]; then
      echo "Missing logical volume (LV) - please configure KVM_LV" >&2
      exit 1
   fi
   if [ -z "$SNAP_SIZE" ]; then
      echo "Snapshot size is NOT properly defined - please reconfigure SNAP_SIZE" >&2
      exit 1
   fi
   if [ -z "$SNAP_MOUNT" ]; then
      echo "Snapshot mount point is NOT properly defined - please reconfigure SNAP_MOUNT" >&2
      exit 1
   fi
   if [  -z "$VMS_BACKUP" ] ; then
      echo "Missing backup VMS_BACKUP">&2
      exit 2
   fi

	VG_EXIST=`$VGDISPLAY $KVM_VG | grep "VG UUID"| wc -l`
	if [  $((VG_EXIST)) -lt 1 ]; then
		echo "$KVM_VG is not a valid Volume Group" >&2
		echo "Select one of the following :" >&2
		echo >&2
		$VGDISPLAY -s >&2
		echo >&2
		exit 1
	fi

	# only 1 line output if not existing
	LV_EXIST=`$LVDISPLAY /dev/$KVM_VG/$KVM_LV | grep "LV UUID" | wc -l`	
	if [  $((LV_EXIST)) -lt 1 ]; then
		echo "$KVM_LV is not a valid Logical Volume in $KVM_VG Volume Group" >&2
		echo "Select one of the following :" >&2
		echo >&2
		$LVS >&2
		echo >&2
		exit 1
	fi
        SNAP_MOUNT=`file_add_slash $SNAP_MOUNT`${KVM_LV}-"snapshot"
        SNAP_NAME=${KVM_LV}-snapshot
}

function get_lv_mount_point(){
    LVMOUNT=`cat /proc/mounts | grep "/dev/${KVM_VG}/${KVM_LV}"| awk '{print $2}'`
    [ -z "$LVMOUNT" ] && LVMOUNT=`cat /proc/mounts | grep "/dev/mapper/${KVM_VG}-${KVM_LV}"| awk '{print $2}'`
    if [ -z "$LVMOUNT" ] ; then 
       VG_NEW=`echo ${KVM_VG} | sed 's/-/--/g'`
       LVMOUNT=`cat /proc/mounts | grep "/dev/mapper/${VG_NEW}-${KVM_LV}"| awk '{print $2}'`
    fi
    [ -z "$LVMOUNT" ] && echo "get lv /dev/${KVM_VG}/${KVM_LV}  mount point failed ">&2 && exit 1
}


function stop_snapshot(){
    cd /tmp
   mount_count=`cat /proc/mounts | grep $SNAP_MOUNT | wc -l`
   if  [ $mount_count -ge 1 ] ; then
       echo "Unmounting LVM snapshot..."
        $UMOUNT $SNAP_MOUNT
        if [ $? -ne 0 ]; then
            echo "Unmount $SNAP_MOUNT error !" >&2
                exit 1
            else
                [ -d $SNAP_MOUNT ] && /bin/rmdir $SNAP_MOUNT
                echo "Unmount $SNAP_MOUNT success"
        fi
    fi
   [ -f /dev/$KVM_VG/$SNAP_NAME ] && snapshot_count=1 || snapshot_count=0
#   snapshot_count=`$LVDISPLAY /dev/$KVM_VG/$SNAP_NAME | grep "LV UUID" | wc -l`
   if [ $snapshot_count -ge 1 ] ; then
        echo "Removing LVM snapshot..."
        $LVREMOVE -f /dev/$KVM_VG/$SNAP_NAME
        if [ $? -ne 0 ]; then
                echo "LVM remove /dev/$KVM_VG/$SNAP_NAME error  !" >&2
                exit 1
        else
                echo "LVM /dev/$KVM_VG/$SNAP_NAME snapshot removed."
        fi
   fi
    [ -b /dev/$KVM_VG/$SNAP_NAME ] && $LVREMOVE -f /dev/$KVM_VG/$SNAP_NAME
}

function start_snapshot()
{
   $LVCREATE --snapshot --size=$SNAP_SIZE --name $SNAP_NAME /dev/$KVM_VG/$KVM_LV
     echo "Mounting LVM snapshot..."
     if [ ! -d "$SNAP_MOUNT" ]; then
         mkdir -p $SNAP_MOUNT
         if [ $? -ne 0 ]; then
            echo "Impossible to create snapshot mount point: $SNAP_MOUNT" >&2
              echo "create snap snapshot error" >&2
              echo "backup failed"

            exit 1
         fi
      fi
      $MOUNT /dev/$KVM_VG/$SNAP_NAME $SNAP_MOUNT
        if [ $? -ne 0 ]; then
                echo "Mount error !" >&2
                echo "create snap snapshot error" >&2
                echo "backup failed "
                exit 1
        else
                echo "Mounted /dev/$KVM_VG/$SNAP_NAME at $SNAP_MOUNT"
        fi

}

function get_vm_lists(){
#VMLISTS is the vm to backup
#VMS_BACKUP is the vm you given
#VMS_ALL is the vm running in host
    VMLISTS=""
    VMS_BACKUP=`echo ${VMS_BACKUP} | sed 's/,/ /g' | sed 's/;/ /g'`
    VMS_ALL=`/usr/bin/virsh list | grep "running" | awk '{print $2}' | sed 's/\n/ /g'`
    [ $? -ne 0 ] && echo "get vm list failed,please check " >&2&& exit 1
    [ -z "${VMS_ALL}" ] && echo "VM not found on host `hostname`" >&2 && exit 1
    [ -z "${VMS_BACKUP}" ] && echo "the VM to backup not given `hostname`" >&2 && exit 1
    #VM_ARR is the VM ALL ARR
    #获取主机上所有的vm 列表
    VM_ARR=""
    for VM in ${VMS_ALL}
    do 
      VM_ARR="$VM ""${VM_ARR}"
    done
    VMS_ALL=${VM_ARR}
    #如果不备份全部的vm 则判断给出的vm是否存在
    if [ "${VMS_BACKUP}" != "all" ] ; then
      for VM_BACKUP in ${VMS_BACKUP}
       do
          for VM_ALL in ${VMS_ALL}
          do
             #如果给出的vmlist 中有vm 添加到vmlist
             if [ ! -z "${VM_BACKUP}" ] && [ ! -z "${VM_ALL}" ] ; then
              [ "${VM_ALL}" == "${VM_BACKUP}" ] && VMLISTS="${VM_ALL} ""${VMLISTS}"
             fi
           done
        done
    else
        VMLISTS=${VMS_ALL}
    fi

    if [ -z "${VMLISTS}" ] ; then
       exit 1
    fi
}

function get_file_lists()
{
#给出虚拟机名字,获取虚拟机的文件
   local  VMNAME=`echo $1 |sed 's/^[][ ]*//g'`
   local VMFILES=""
   #虚拟机名字不存在则返回1
   [ -z "$VMNAME" ]  && echo "VMNAME not given" >&2 && return 1
   #获取虚拟机文件名字
   #判断虚拟机是否存在
    vmcount=`virsh list | awk '{print $2}' | grep "^${VMNAME}$" | wc -l`
    [ ${vmcount} -ne 1 ] && echo "Error vmname: $VMNAME given error">&2 &&return 1
    VMFILES=""
    for file in `virsh domblklist $VMNAME  | awk '$2 ~/\.img/||$2 ~/\.qcow2/ {print $2}' | sed 's/\n/ /g'`
    do
     VMFILES="${file} ""${VMFILES}" 
    done
    echo "$VMFILES"
}

function snap_full_path()
{
#FILE_NAME the file name of the vm; S_MOUNT the snapshot mountpoint ; L_MOUNT the lvm mount point
local FILE_NAME=$1
local L_MOUNT=$2
local S_MOUNT=$3
[ -z "${FILE_NAME}" ] && echo "get snap full path error;FILE_NAME is NULL" >&2 && return 1
[ -z "${S_MOUNT}" ] && echo "get snap full path error;SNAP MOUNT  is NULL" >&2 && return 1
[ -z "${L_MOUNT}" ] && echo "get snap full path error;LOCAL_MOUNT is NULL" >&2 && return 1
FILE_NAME=`echo ${FILE_NAME} | sed "s#^$L_MOUNT#$S_MOUNT#"`
echo ${FILE_NAME}
}

function snap_data_path()
{
#FILE_NAME the file name of the vm; S_MOUNT the snapshot mountpoint ; L_MOUNT the lvm mount point
local FILE_NAME=$1
local L_MOUNT=$2
local S_MOUNT=$3
local KVM_DATA_DIR=""
[ -z "${FILE_NAME}" ] && echo "get snap full path error;FILE_NAME is NULL" >&2 && return 1
[ -z "${S_MOUNT}" ] && echo "get snap full path error;SNAP MOUNT  is NULL" >&2 && return 1
[ -z "${L_MOUNT}" ] && echo "get snap full path error;LOCAL_MOUNT is NULL" >&2 && return 1
KVM_DATA_DIR=`dirname $(echo ${FILE_NAME} | sed "s#^$L_MOUNT##")`
echo ${KVM_DATA_DIR}

}

function local_backup()
{
#STATUS check 1 表示成功，0 表示失败 
STATUS=1
echo "Begin Backup VMList:${VMLISTS} at `date "+%Y-%m-%d_%H:%M:%S"`" 
get_lv_mount_point
#虚拟机备份开始
for VM in ${VMLISTS}
do
   local FAILED_LISTS=""
   local FILE_LISTS=""
   if [ -f /etc/libvirt/qemu/${VM}.xml ]; then
      config_file="/etc/libvirt/qemu/${VM}.xml"
      FILE_LISTS=${config_file}
   else
      STATUS=0
      FAILED_LISTS="/etc/libvirt/qemu/${VM}.xml"
    fi
    vmfiles=`get_file_lists ${VM}`
    #如果vmfiles 获取不到，获取有问题
    if  [ $? -ne 0 ] || [ -z "${vmfiles}" ]; then
           echo "get VM ${VM} file lists failed" >&2 
           STATUS=0
           continue
    else
       echo "begin backup ${VM};config ${config_file},vmfiles ${vmfiles} at `date "+%Y-%m-%d_%H:%M:%S"`"
    fi
    for file in ${vmfiles}
     do
          local snap_path=`snap_full_path $file ${LVMOUNT} $SNAP_MOUNT`
          #check snap file path if exits add to filelists
          if [ $? -ne 0 ] ; then 
             echo "backup err on ${VM};get snapshot path error" >&2
             STATUS=0
             continue

          fi
          if [ -z "${snap_path}" ] ; then
             echo "backup err on ${VM};get snapshot path error" >&2
             STATUS=0
             continue
          fi
          if [  -f "${snap_path}" ] ; then
             FILE_LISTS="${snap_path} ""${FILE_LISTS}"       
          else 
              echo "vm file not found ${snap_path} on ${VM}" >&2
              FAILED_LIST="${snap_path} ""${FAILED_LIST}"
              STATUS=0
         fi
      done
#check file list exits
if  [ -z "${FILE_LISTS}" ] ; then 
     echo "get vm ${VM}; file list failed;failedlist ${FAILED_LISTS}" >&2
     STATUS=0
     continue
else
    mkdir -p "$NFS_LDIR"/"$HOSTNAME"
    if [ "${TEST}" -eq 0 ] ;then
       /bin/tar -czf "$NFS_LDIR"/"$HOSTNAME"/"${PREFIX}_""${SCRIPT_PREFIX}_""${VM}".tar.gz ${FILE_LISTS}
    else
      echo "begin test backup ${VM} at `date "+%Y-%m-%d_%H:%M:%S"`"
      echo  "bin/tar -cvzf  $NFS_LDIR"/"$HOSTNAME"/"${PREFIX}_""${SCRIPT_PREFIX}_""${VM}".tar.gz ${FILE_LISTS}
    fi
    if [ $? -eq 0 ] ; then
       echo "end backup vm ${VM} success,filelists ${FILE_LISTS} at `date "+%Y-%m-%d_%H:%M:%S"`"
    else
       echo "end backup vm ${VM} failed,filelists ${vmfiles} at `date "+%Y-%m-%d_%H:%M:%S"`" >&2 
       STATUS=0
    fi
fi

done
echo "end backup all VM,VMlist:${VMLISTS} at `date "+%Y-%m-%d_%H:%M:%S"`"
   if [ "${STATUS}" -eq 0 ] ; then 
       echo "backup vm on host has error,please check" >&2 && return 1
   else
        echo "backup all vm on host success,vmlist ${VMLISTS}" 
   fi
}
function backup_exit()
{
   if [ "${STATUS}" -eq 1 ] ; then 
       exit 0
   else
       exit 1
   fi
}

#获取配置选择，是否是测试
get_opts $@
#检查是否已root身份运行的,不是的话，退出
check_root
#检查命令是否存在
check_work_env
#设置工作环境，一些配置选项
set_work_env
#检查配置参数是否存在
check_param
#检查lvm的合法性
checklvm
#停止快照
stop_snapshot
#挂载nfs文件系统
#获取lvm的挂载点
get_lv_mount_point
#获取vm 列表
get_vm_lists
# get vmlist failed
if [ $? -ne 0 ] ; then
   echo "get vm lists failed" >&2 
   exit  1
fi
#判断vmlist 是否为空
if [ -z "${VMLISTS}" ] ; then
   echo "the vmlist given not found">&2
   exit 1
fi

#挂载nfs文件系统,并检查文件权限
mount_nfs
#开始快照
start_snapshot
#开始备份
local_backup
#停止快照
stop_snapshot
#卸载nfs文件系统
umount_nfs
backup_exit
