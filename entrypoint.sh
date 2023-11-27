#!/bin/bash
mkdir -p $CHECKPOINT_RESTORE_FILES_DIR
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} -XX:+ExitOnOutOfMemoryError"

if [ -z "$(ls $CHECKPOINT_RESTORE_FILES_DIR/core-*.img 2>/dev/null)" ]; then
  echo "Save checkpoint to $CHECKPOINT_RESTORE_FILES_DIR" 1>&2
  java -XX:CRaCCheckpointTo=$CHECKPOINT_RESTORE_FILES_DIR org.springframework.boot.loader.launch.JarLauncher &
  sleep ${SLEEP_BEFORE_CHECKPOINT:-10}
  jcmd org.springframework.boot.loader.launch.JarLauncher JDK.checkpoint
  sleep ${SLEEP_AFTER_CHECKPOINT:-3}
else
  echo "Restore checkpoint from $CHECKPOINT_RESTORE_FILES_DIR" 1>&2
fi

(echo 128 > /proc/sys/kernel/ns_last_pid) 2>/dev/null || while [ $(cat /proc/sys/kernel/ns_last_pid) -lt 128 ]; do :; done
java -XX:CRaCRestoreFrom=$CHECKPOINT_RESTORE_FILES_DIR &
JAVA_PID=$!

stop_java_app() {
    kill -SIGTERM $JAVA_PID
}

trap stop_java_app SIGINT
wait $JAVA_PID
