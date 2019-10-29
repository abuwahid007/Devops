#!/bin/bash

# Author: Abdul Wahid
#Description:  Send SSL expiration report of TrustStore for application server [cacerts]
# Requirements: JDK setup and sendmail package

#set -x


env=$1
expiredays="60"

export KeyStore_pass="<your_cacerts_Password>"

cat << EOF

The script will check the expiration date.

EOF

export report_path="/opt/scripts/ssl_expire/jdk/cert/report"


if [ "${1}" == "" ];then
        echo "Instance should not be empty" ;
        echo "Please check the instance name and try again";
        exit 99 ;
fi

 sendmailexpire () {
(
echo "From: noreply@gmail.com"
echo "To: youremailaddress@gmail.com"
echo "MIME-Version: 1.0"
echo "Subject: SSL Expiration Report of ${env} [$(hostname)]"
echo "Content-Type: text/html"
cat $report_path/$IID/expire.html
) | /usr/sbin/sendmail -t
}

sendmailexpired () {
(
echo "From: noreply@gmail.com"
echo "To: youremailaddress@gmail.com"
echo "MIME-Version: 1.0"
echo "Subject: SSL Expiration Report of ${env} [$(hostname)]"
echo "Content-Type: text/html"
cat $report_path/$IID/expired.html
) | /usr/sbin/sendmail -t
}

passwordincorrect () {
(
echo "From: noreply@gmail.com"
echo "To: youremailaddress@gmail.com"
echo "MIME-Version: 1.0"
echo "Subject: InCorrect Keystore Password issued on $(hostname) for ${env}"
echo "Content-Type: text/html"
echo "Keystore Path: $cert_file ,Please verify the Keystore Password"
) | /usr/sbin/sendmail -t
}


IID=${1}

env=$IID

JVM_INSTANCE_PID=`ps -aef| grep -w ${IID} | grep -w [j]ava | awk '{print \$2}'`

if [[ "$?" != "0" ]]; then
        echo "ps Command failed."
        exit 99
elif [[ ${JVM_INSTANCE_PID} ]];then
        echo "PID available to proceed further"
else
    echo "No process is running for the instance. ${IID}, please check the instance exists or running in the $(hostname)"
        exit 99
fi

        echo "${IID} instance already running with the process ID: "${JVM_INSTANCE_PID}"."


JAVA_HOME=`ps aux |grep -w ${JVM_INSTANCE_PID} | grep [j]ava | awk '{print $11}' | sed 's@/bin/java@@g'`

if [ ! -d ${JAVA_HOME} ]; then
        echo "Java Home doesn't exits, please check the instance name and try again" ;
        exit 99 ;
fi


if [ ! -d $report_path/${IID}/ ] ; then
        mkdir -p $report_path/${IID}/ ;
fi

if [ -d $report_path/${IID}/ ] ; then
        rm -v  $report_path/${IID}/* ;
fi


export env_CERT_PATH=$(eval 'echo '${JAVA_HOME}/jre/lib/security)


if [ -f "${env_CERT_PATH}/cacerts" ];

        then

        cert_file="${env_CERT_PATH}/cacerts"

        else

        echo "Please check the configuration, cacerts file is missing"

        exit

fi


password=$($JAVA_HOME/jre/bin/keytool -list -v -keystore $cert_file -storepass ${KeyStore_pass} |grep "Password verification failed" |wc -l)

if [ ${password} == 1 ] ; then
        echo "Keystore Password Incorrect"
        passwordincorrect
        exit
        else
        echo "Keystore Password Accepted"
fi



if [[ -f $report_path/$IID/a.log || -f $report_path/$IID/b.log || -f $report_path/$IID/c.log ]]; then

rm -v $report_path/$IID/a.log $report_path/$IID/b.log $report_path/$IID/c.log

fi


ALIAS=$($JAVA_HOME/jre/bin/keytool -list -v -keystore $cert_file -storepass ${KeyStore_pass} | grep "Alias name:" | cut -d ":" -f2 | sed 's/ *$//g' >> $report_path/$IID/a.log)


echo "LIST OF DOMAINS"
cat $report_path/$IID/a.log

count=`cat $report_path/$IID/a.log |wc -l`

x=1
while [ $x -le $count ]
do
  echo "," >> $report_path/$IID/b.log
  x=$(( $x + 1 ))
done

paste $report_path/$IID/a.log $report_path/$IID/b.log | column -s $'\t' -t > $report_path/$IID/c.log


IFS=',' ;


for i in `cat $report_path/$IID/c.log`

do

alias=`echo $i | sed 's/  /,/g' | sed 's/,//g' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//'`

echo "$alias" > $report_path/$IID/echo.log


UNTIL=`$JAVA_HOME/jre/bin/keytool -list -v -keystore $cert_file -storepass ${KeyStore_pass} -alias "$(cat $report_path/$IID/echo.log | tail -n 1)" | grep "Valid from:" | head -n 1 | perl -ne 'if(/until: (.*?)\n/) { print "$1\n"; }'`


UNTIL_SECONDS=`date -d "$UNTIL" +%s`

UNTIL_DATE=`date -d "$UNTIL"`


commonname=$($JAVA_HOME/jre/bin/keytool -list -v -keystore $cert_file -storepass ${KeyStore_pass} -alias "$(cat $report_path/$IID/echo.log | tail -n 1)" | grep "Owner:" |head -n 1)

REMAINING_DAYS=$(( ($UNTIL_SECONDS -  $(date +%s)) / 60 / 60 / 24 ))


function deleteexpired()
{

if [ ${REMAINING_DAYS} -le 0 ];
then

cp -pvr $cert_file $cert_file-$(date +%F-%H-%M-%S)

$JAVA_HOME/jre/bin/keytool -delete -alias "$(cat $report_path/$IID/echo.log | tail -n 1)" -keystore $cert_file -storepass ${KeyStore_pass}

echo "certificate has been removed for alias name $i"

fi

}


if [ ${REMAINING_DAYS} -le 0 ]
then


echo "<tr><td align="center" bgcolor="#ece9d8">$i</td> <td align="center" bgcolor="#ece9d8">${UNTIL_DATE}</td> <td align="center" bgcolor="#ece9d8">$commonname</td><td align="center" bgcolor="#ece9d8">Expired</td></tr>" >> $report_path/$IID/expired.log


#deleteexpired

elif [ ${REMAINING_DAYS} -le $expiredays ]
then

echo "<tr><td align="center" bgcolor="#ece9d8">${i}</td> <td align="center" bgcolor="#ece9d8">${UNTIL_DATE}</td> <td align="center" bgcolor="#ece9d8">${commonname}</td> <td align="center" bgcolor="#ece9d8">Certificate will expire in ${REMAINING_DAYS} days</td><td align="center" bgcolor="#ece9d8"></td></tr>" >> $report_path/$IID/expire.log


else

echo certificate is ok

fi


done

if [ -f $report_path/$IID/expired.log ] ; then

EXPIRED=`cat $report_path/$IID/expired.log`

echo "<HTML><BODY>" > $report_path/$IID/expired.html
echo "

<TABLE style="width: "50%;"" BORDER="2" >
<tr><th colspan="1" scope="col">Alias Name</th><th colspan="1" scope="col">Date of Expiration</th><th colspan="1" scope="col">Certificate Details</th><th colspan="1" scope="col">Status</th></tr>
 "${EXPIRED}"
</table>

<p> Keystore Path = $cert_file </p>

" >> $report_path/$IID/expired.html

echo "</BODY></HTML>" >> $report_path/$IID/expired.html

sendmailexpired

fi

if [ -f $report_path/$IID/expire.log ] ; then

EXPIRE=`cat $report_path/$IID/expire.log`

echo "<HTML><BODY>" > $report_path/$IID/expire.html
echo "

<TABLE style="width: "50%;"" BORDER="2" >
<tr><th colspan="1" scope="col">Alias Name</th><th colspan="1" scope="col">Date of Expiration</th><th colspan="1" scope="col">Certificate Details</th><th colspan="1" scope="col">Status</th></tr>
 "${EXPIRE}"
</table>
<p> Keystore Path = $cert_file </p>

" >> $report_path/$IID/expire.html

echo "</BODY></HTML>" >> $report_path/$IID/expire.html

sendmailexpire

fi
