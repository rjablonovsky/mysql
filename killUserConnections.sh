#!/bin/bash
# Owner: jablonovskyr.dba
# Date Created: 2020-05-14
# Last Date Modified: 2020-05-14
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

param_list_excluded_dbusers="${1:-svcMONyogApp,svcGlobalVars,svcBackupRestore,nagios}"
list_excluded_dbusers=""
# retrieve list of excluded db users and clean it. Valid delimiters are " ", ",", ":", "|", "''"
IFS="|:', " read -r -a a <<< "${param_list_excluded_dbusers}"
read -r -a b <<< $(echo "${a[@]}")
# get proper SQL valid string for IN clause
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
WHERE TYPE = 'FOREGROUND' AND NAME = 'thread/sql/one_connection'
  AND PROCESSLIST_ID != connection_id() -- exclude current connection
  AND NOT(    PROCESSLIST_USER IN (${list_excluded_dbusers}) 
           OR PROCESSLIST_USER LIKE '%.dba' ) 
ORDER BY PROCESSLIST_TIME DESC, PROCESSLIST_ID; "
KILL_SQL_FILE=${SCRIPT_DIR}/killUserConnectionsProcess.sql

> "${LOG_FILE}"
> "${KILL_SQL_FILE}"

echo "BEGIN kill of MySQL user connections on ${LOCALHOST}:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"

mysql --login-path="${LOGIN_PATH_USER}" -e "${PROCESS_SQL}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"
awk 'NR>2 {print "kill "$1"; "}' "${LOG_FILE}" > "${KILL_SQL_FILE}" 2>>"${LOG_FILE}"
echo "SQL USED TO IDENTIFY PROCESSES TO KILL: ${PROCESS_SQL}" >> "${LOG_FILE}"

echo "BEGIN execute SQL file with kill processes commands:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"
mysql --login-path="${LOGIN_PATH_USER}" < "${KILL_SQL_FILE}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"

echo "END kill of MySQL user connections on ${LOCALHOST}:" $(date +%F_%H:%M:%S.%N) | tee -a "${LOG_FILE}"
