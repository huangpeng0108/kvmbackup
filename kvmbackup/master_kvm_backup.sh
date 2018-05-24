#!/bin/bash
logger "KVM Backup Script - started..."
#
HOSTNAME=`hostname`
DATE="/bin/date"
SENDMAIL="/usr/sbin/sendmail"
#备份脚本位置
BACKUP_SCRIPT=`dirname $0`/scripts/kvmbackup.sh

#配置文件
CONF_FILE=`dirname $0`"/conf/kvm.conf"
DATE_FORMATED=`$DATE "+%y%m%d_%H%M%S"`
DATE_FORMATED1=`$DATE "+%y-%m-%d_%H:%M:%S"`
PREFIX="$DATE_FORMATED"_"$HOSTNAME"
#日志文件
LOG_DIR=`dirname $0`/logs
OUTPUT_LOG="$LOG_DIR"/"$PREFIX"_kvmbackup.log
ERROR_LOG="$LOG_DIR"/"$PREFIX"_kvmbackup.error
MAIL_REPORT_FILE="$LOG_DIR"/mail_report.txt
#备份状态 0 表示失败，1表示成功
FIND="/usr/bin/find"
BAK_STATUS=0
#log 文件过期时间
AGE="+2"


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
while getopts h:t OPTION
do
   case  $OPTION in 
     t) TEST=1
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
check_root(){
     if [ $((UID)) -ne 0 ]; then
        echo "You need to run this script as ROOT" >&2
        exit 1
    fi
}

function check_param()
{
  if [ -z "$MAIL_REPORT_ADDRESS" ]; then
     echo "Missing mail report address" >&2
     exit 2
   fi
   if [ -z "$LOG_DIR" ]; then
     echo "Missing log dir" >&2
     exit 2
   fi
    if [ -z "$OUTPUT_LOG" ]; then
     echo "Missing output log" >&2
     exit 2
   fi
    if [ -z "$ERROR_LOG" ]; then
     echo "Missing error log file" >&2
     exit 2
   fi
    if [ -z "$MAIL_REPORT_FILE" ]; then
     echo "Missing mail report file" >&2
     exit 2
   fi
     if [ -z "$BACKUP_SCRIPT" ]; then
     echo "Missing backup script file" >&2
     exit 2
   fi
   if [ -z "$PREFIX" ]; then
     echo "Missing backup prefix" >&2
     exit 2
   fi


}

#
## Check FOLDER
check_folder(){
  folder="$1"
  # Get the Value of Variable whose name is a Variable 
  # e.g: AA=aaa; BB=AA; echo ${!BB} will display 'aaa'
  if [ -z "${!folder}" ] 
  then
    echo "$folder: missing value - correct the script" >&2
    exit 2
  else
    # check if the folder exists
    if [ ! -d "${!folder}" ]; then
          # if not creates it
          mkdir -p "${!folder}"
          # if creation fails
      if [ $? -ne 0 ]; then 
            echo "permission issue - have not write permission for $folder" >&2
            exit 2
          fi
        fi 
  fi 
   if [ ! -w "${!folder}" ] ; then
      echo "$folder not have write permission" >&2
      exit 2
   fi
}

function prepare_email_header()
{
[ "$BAK_STATUS" -ne 1 ] && BK_STATUS="FAILED" || BK_STATUS="-- OK"
cat > "$MAIL_REPORT_FILE" << EOF
To: $MAIL_REPORT_ADDRESS
Subject: $BK_STATUS [$HOSTNAME] kvm backup report -$DATE_FORMATED1

EOF

}
function prepare_email_subcontent()
{
  echo "######################################################"    >> "$MAIL_REPORT_FILE"
  echo "Backup Summary:"                                           >> "$MAIL_REPORT_FILE"
  echo "######################################################"    >> "$MAIL_REPORT_FILE"
 if  [ -s "${OUTPUT_LOG}" ] ; then
     echo "-- Logs:"                                               >> "$MAIL_REPORT_FILE"
     cat "${OUTPUT_LOG}"                                           >>"$MAIL_REPORT_FILE"
 fi
   if  [ -s "${ERROR_LOG}" ] ; then
     echo "-- Errors:"                                             >> "$MAIL_REPORT_FILE"
     cat "${ERROR_LOG}"                                            >>"$MAIL_REPORT_FILE"
 fi

}

function send_email () {
  prepare_email_header
  prepare_email_subcontent
 cat "$MAIL_REPORT_FILE" | $SENDMAIL $MAIL_REPORT_ADDRESS
}

function clean_backup_log()
{
if [ -z "$LOG_DIR" ] ; then
   echo "Missing log dir" 
   exit 1
fi
if [ -z "$AGE" ] ; then
   echo "Missing parameter age time"
   exit 1
fi

if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] ; then
   $FIND "$LOG_DIR"  \( -name '*.error' -o -name '*.log' \) -ctime $AGE -exec rm -rf '{}' ';'
   if [ $? -eq 0 ]; then
     echo  `basename $0` " - clean up log successful"
  else 
     echo  "Clean up log error"
  fi

fi 

}

check_root
get_opts $@
#设置工作环境
set_work_env
check_param
#检查日志文件是否有可写权限
check_folder LOG_DIR

if [ -f  "$BACKUP_SCRIPT" -a -r "$BACKUP_SCRIPT" ] ; then
#TEST 为0为备份，1为测试
   if [ "$TEST" -eq 0 ] ; then
       sh $BACKUP_SCRIPT -p "$PREFIX" >"${OUTPUT_LOG}" 2>"${ERROR_LOG}" 
    else 
       sh $BACKUP_SCRIPT -p "$PREFIX" -t >"${OUTPUT_LOG}" 2>"${ERROR_LOG}"
   fi
#BAK_STATUS 设置1 为成功 0为失败
  if [ $? -eq 0 ] ; then
  BAK_STATUS=1
  else
  BAK_STATUS=0
  fi   
 send_email
else
  BAK_STATUS=0
  echo "backup script $BACKUP_SCRIPT not found,please check file!" 2>"${ERROR_LOG}"
  send_email 
fi
clean_backup_log
