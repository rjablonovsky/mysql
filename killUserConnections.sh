#!/bin/bash
# Owner: jablonovskyr.dba
# Date Created: 2020-05-14
# Last Date Modified: 2020-06-17
# Primary Function: kill all user connections to mysql server
# Log Location: The same as the script directory,  file - killUserConnections.log
# Support files: The same as the script directory, file - killUserConnectionsProcess.sql
# Details: The script will kill all user/application connections to mysql server.
#          Excluded are by default: system, administration, maintenance, monitoring and dba users
#          In string parameter passed to script could be specified list of excluded users. String have to be enclosed in ""
#          Valid delimiters in string are " ", ",", ":", "|", "'"
#          Script is expected to be run directly before or as part of backup script(s)
#          Expected error message type on application side: ERROR 2013 (HY000): Lost connection to MySQL server during query
# Example: default - /usr/local/dba/scripts/killUserConnections.sh
#          kill backup processes too - /usr/local/dba/scripts/killUserConnections.sh "svcMONyogApp,svcGlobalVars,nagios"
#          Usage in crontab - 05 0 * * * /usr/local/dba/scripts/killUserConnections.sh "svcMONyogApp,svcGlobalVars,nagios" > /dev/null 2>&1
#

errcode=0
param_list_excluded_dbusers="${1:-svcMONyogApp,svcGlobalVars,svcBackupRestore,nagios}"
list_email="${2:-rjablonov@gmail.com}" # list should be comma delimited. List is not cleaned or validated!
send_email_flag="${3:-0}" # 0 - never. It is default, 1 - when db process(es) were killed, 2 - always
list_excluded_dbusers=""
# retrieve list of excluded db users and clean it. Valid delimiters are " ", ",", ":", "|", "''"
IFS="|:', " read -r -a a <<< "${param_list_excluded_dbusers}"
read -r -a b <<< $(echo "${a[@]}")
# get SQL valid string for IN clause
list_excluded_dbusers="'${b[0]}'"
for ((i=1;i<${#b[@]};i++)); do
  list_excluded_dbusers="${list_excluded_dbusers},'${b[i]}'"
done

SCRIPT_DIR="/usr/local/dba/scripts"
DATETIME=$(date +"%Y%m%d%H%M%S")
LOCALHOST=$(hostname)
LOG_FILE=${SCRIPT_DIR}/killUserConnections.log
LOGIN_PATH_USER=backupAcct
PROCESS_SQL=" 
SELECT PROCESSLIST_ID, PROCESSLIST_USER, PROCESSLIST_DB, PROCESSLIST_STATE, 
       PROCESSLIST_HOST, PROCESSLIST_COMMAND, PROCESSLIST_TIME 
FROM performance_schema.threads 
WHERE PROCESSLIST_ID != connection_id() -- exclude current connection 
  AND TYPE = 'FOREGROUND' AND NAME = 'thread/sql/one_connection' 
  AND NOT(    PROCESSLIST_USER IN (${list_excluded_dbusers}) 
           OR PROCESSLIST_USER LIKE '%.dba' ) 
ORDER BY PROCESSLIST_TIME DESC, PROCESSLIST_ID; "
KILL_SQL_FILE=${SCRIPT_DIR}/killUserConnectionsProcess.sql

> "${LOG_FILE}"
> "${KILL_SQL_FILE}"

echo "BEGIN kill of MySQL user connections on ${LOCALHOST}:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"

# SQL sanity check:
mysql --login-path="${LOGIN_PATH_USER}" -e "explain ${PROCESS_SQL}" > /dev/null 2>>"${LOG_FILE}"; errcode=$?
if [ $errcode -ne 0 ]; then printf "%s" "${PROCESS_SQL}" >> "${LOG_FILE}"; echo "ERROR IN SQL: ${LOG_FILE}"; exit $errcode; fi
# Execute SQL:
mysql --login-path="${LOGIN_PATH_USER}" -e "${PROCESS_SQL}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"
awk 'NR>2 {print "kill "$1"; "}' "${LOG_FILE}" > "${KILL_SQL_FILE}" 2>>"${LOG_FILE}"
echo "SQL USED TO IDENTIFY PROCESSES TO KILL: ${PROCESS_SQL}" >> "${LOG_FILE}"

echo "BEGIN execute SQL file with kill processes commands:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"
mysql --login-path="${LOGIN_PATH_USER}" < "${KILL_SQL_FILE}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"

echo "END kill of MySQL user connections on ${LOCALHOST}:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"

# send email based on flag
if [ $send_email_flag -eq 1 ]; then 
  # send email only if file $KILL_SQL_FILE is not empty
  if [ -s "${KILL_SQL_FILE}" ]; then 
    cat "${LOG_FILE}"  | mail -s "MySQL connections terminated on ${LOCALHOST} by script killUserConnection.sh" "${list_email}"
  fi
# send email with notification
elif [ $send_email_flag -eq 2 ]; then 
  cat "${LOG_FILE}"  | mail -s "on ${LOCALHOST} script killUserConnection.sh was executed" "${list_email}"
fi
