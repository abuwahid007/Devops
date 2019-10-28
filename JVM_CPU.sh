#!/bin/bash
#Author: Abdul Wahid 
#Description: Shell script to analysis the JVM thread which is causing high CPU. 
#
set -x

JVM_INSTANCE_NAME=$1

#PATH to store the logs.
LOG_DIR="/opt/${JVM_INSTANCE_NAME}/backups"
HOST_NAME=$(/bin/hostname)
SUFFICS1=$(/bin/date +%F-%H-%M)
DTF="$(date '+%F')"
export today=`date +%a' '%b'-'%d'@'%H:%M`
logpath=${LOG_DIR}
THRESHOLD_LIMIT_CPU="150" #Depends upon your needs.

#checking if the instance is valid


if [[ ( $1 == "" || $2 == "" ) ]]; then
        echo "Instance and email id should not be empty" ;
        echo "Please pass the instance name and emaild id as argument and try again";
        exit 99 ;
fi


function delete_lock(){
JVM_INSTANCE_NAME=$1
        if [ -f "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock" ]
                then
                rm -v "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock"
                echo "Removed lock file"
        fi
}
function create_lock(){
JVM_INSTANCE_NAME=$1
        if [ ! -f "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock" ]
                then
                touch "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock" ;
                echo $today > ${LOG_DIR}/${JVM_INSTANCE_NAME}.lock
                echo "created lock file to suspend the duplicate thread script"
        fi
}

function check_lock(){
JVM_INSTANCE_NAME=$1

        if [ -f "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock" ]
                then
                echo "Exist the script since the previous Script is currently in progress"
                exit
        else
        create_lock $JVM_INSTANCE_NAME
        fi

}

function check_lock_age() {
JVM_INSTANCE_NAME=$1

        if [ $(find "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock" -type f -mmin +15 | wc -l 2>/dev/null) == 1 ]; then

        echo "Lock file is blocked the existing script to execute and it will be removed"

        rm -v "${LOG_DIR}/${JVM_INSTANCE_NAME}.lock"

        fi

}



function logfolder()
{
        if [ !  -d $LOG_DIR/ ];then
        mkdir ${LOG_DIR}
        fi
}

function check_log_files()
{
for i in ${JVM_INSTANCE_NAME}
        do
        if [[ -s $logpath/${i}-*-${SUFFICS1}*.log || $logpath/${i}-*-${SUFFICS1}*.csv || $logpath/${i}-cpu-threads-ids.log || $logpath/${i}-cpu-threads-${SUFFICS1}.csv ]];then
        gzip -vf $logpath/${i}-*-${SUFFICS1}*.* 2> /dev/null;
        fi
done
}

function check_process_status()
{

        JVM_PID=`ps -aef| grep -w ${JVM_INSTANCE_NAME} | grep -w [j]ava | awk '{print $2}'`

        if [ -z $JVM_PID ]; then
                echo "${JVM_INSTANCE_NAME} Instance Offline, Script exit by remove lock file"
                delete_lock ${JVM_INSTANCE_NAME}
                exit 1
        fi

}

function check_cpu_usage()
{
JVM_INSTANCE_NAME=$1
        cpu_usage=`top -b -p "${JVM_PID}" -n 1 | sed '/^s*$/d' | tail -n 1 | awk '{print $9}'`
                cpu_usage1="${cpu_usage/.*}"

                check_process_status

                if [ "${cpu_usage1}" -ge ${THRESHOLD_LIMIT_CPU} ]; then
                       echo "DATE:- [$(date)] CPU usage is ${cpu_usage1} and script will check the cpu usage after 2 minutes"
                sleep 2m
                        count=1
                        while [ $count -lt 5 ]; do

                        cpu_usage=`top -b -p "${JVM_PID}" -n 1 | sed '/^s*$/d' | tail -n 1 | awk '{print $9}'`
                        cpu_usage1="${cpu_usage/.*}"

                                check_process_status

                                if [ "${cpu_usage1}" -ge ${THRESHOLD_LIMIT_CPU} ]; then
                                count=$(expr "$count" + 1)
                                echo "DATE:- [$(date)] Count=$count, CPU usage of the instance is ${cpu_usage1} and script will check the cpu usage after 2 minutes"
                                check_process_status
                                sleep 2m

                                        if [ $count -ge 5  ];  then
                                                echo "DATE:- $(date) Count=$count, CPU usage is more than threshold even after 10 minutes of interval"
                                        fi

                        else
                                compress_dumps
                                delete_lock ${JVM_INSTANCE_NAME}
                                exit 1
                                fi
                        done
                else
                echo "please check the cpu usage once again , since it is below ${THRESHOLD_LIMIT_CPU} .. i.e ${cpu_usage1} so no use of taking dumps now"
                delete_lock ${JVM_INSTANCE_NAME}
                        exit
             fi
}



function Thread_dump()
{

JVM_INSTANCE_NAME=$1
        if [ -f ${JSTACK_PATH} ]; then
                echo "taking thread dump for instance $JVM_INSTANCE_NAME"
                       su jboss -c  "${JSTACK_PATH} ${JVM_PID}" >> $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.log
                                echo "Thread dump taken succesfully"
        else
                echo "${JSTACK_PATH} file require to take thread dump, please verify this and try once again"
                exit
        fi
}

function compress_dumps()
{
for i in ${JVM_INSTANCE_NAME}
                do
                                if [[ -f $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.log || $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.html ]]; then
                                gzip -v $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.log 2> /dev/null;
                                fi
                done
}

#check the CPU usage finally to send an email

function cpu_check()
{

SUM=0;

for i in `cat $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.csv  |awk '{print $2}' | grep -v "%CPU" | cut -d. -f1`; do echo "SUM : ${SUM} "; SUM=$((${SUM} + ${i})); echo "+ ${i}: ${SUM}"; done

if [ "${SUM}" -ge ${THRESHOLD_LIMIT_CPU} ]; then
                        echo "Current cpu usage of the instance is ${SUM} and proceed further to send email notification"
                else
                        echo "CPU usage is below ${THRESHOLD_LIMIT_CPU} .. i.e ${SUM} so no use of taking dumps now"
                        exit
                fi

}

# check if the instance is already running

echo "Checking if the instance is running..."

JVM_PID=`ps -aef| grep -w ${JVM_INSTANCE_NAME} | grep -w [j]ava | awk '{print $2}'`


if [[ "$?" != "0" ]]; then
        echo "ps Command failed."
        exit 99
elif [[ ${JVM_PID} ]];then
        echo "PID available to proceed further"
else
    echo "No process is running for the instance. ${JVM_INSTANCE_NAME}, please check the instance exists or running in the $(hostname)"
        exit 99
fi

        echo "TOMCAT: ${JVM_INSTANCE_NAME} instance already running with the process ID: "${JVM_PID}"."

JSTACK_PATH=`ps aux |grep -w ${JVM_PID} | grep [j]ava | awk '{print $11}' | sed 's@bin/java@bin/jstack@g'`

echo $JSTACK_PATH
if [ ! -f "${JSTACK_PATH}" ];then
        echo " ${JSTACK_PATH} JMAP PATH missing,please correct it and try again"
fi

#Executing Functions

        check_lock_age ${JVM_INSTANCE_NAME}
        check_lock ${JVM_INSTANCE_NAME}
        logfolder
        check_log_files
        check_cpu_usage $JVM_INSTANCE_NAME
        Thread_dump $JVM_INSTANCE_NAME

echo "Capture the CPU usage per threads"

top -H -p "${JVM_PID}" -b -n 1 | head -n 30 | grep -v top |grep -v "Cpu(s)" |grep -v Mem |grep -v Swap | grep -v '^[[:space:]]*$' | grep -v "${JVM_PID}" | awk '{print $1,$9}' > $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids.log


cat $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids.log | grep -v PID | awk '{print $1}' > $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids1.log

echo "Converting the Thread PID from Decimal to Hexadecimal Format"

echo "NID's" > $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids2.log
x=0
for i in `cat $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids1.log`
do
threads=`grep -i "$(printf "%x\n" $i )" $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.log`

nid="$(printf "%x\n" $i )"
x=`expr $x + 1`

echo "0x$nid">> $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids2.log

done

#Import the Nid's data into the .csv file.

paste $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids.log $logpath/$JVM_INSTANCE_NAME-cpu-threads-ids2.log | column -s $'\t' -t > $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.csv

cpu_check

echo "Converting the CSV file into HTML file in Table format"

awk 'BEGIN{print "<table style=width:20% border=2> <TR><TH COLSPAN=2> CPU USAGE PER THREADS </TH> <TH COLSPAN=3> TOTAL CPU = '${SUM}' </TH></TR> "}; {print "<tr>";for(i=1;i<=NF;i++)print "<td align=center bgcolor=#ece9d8>" $i"</td>";print "</tr>"} END{print "</table>"}' $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.csv >> $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.html

cat $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.html

cd $logpath

compress_dumps

mutt -e 'set realname="FROMADDRESS" use_from=yes from="emailaddress@domain.com" content_type=text/html' -s "Total CPU of ${JVM_INSTANCE_NAME} instance is ${SUM} as of ${today} [$(hostname)]"  -a $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.log.gz -- ${2} < $logpath/$JVM_INSTANCE_NAME-thread-dump-cpu-${SUFFICS1}.html


delete_lock ${JVM_INSTANCE_NAME}

exit 0
