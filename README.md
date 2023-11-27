# example-spring-boot

This is an example of Spring Boot [Getting Started](https://github.com/spring-guides/gs-spring-boot/tree/main/initial) modified to work on OpenJDK CRaC, which consists only in using Spring Boot 3.2+ and adding the `org.crac:crac` dependency (version `1.4.0` or later).

## Building

Use Maven to build
```
./mvnw package
```

## Running

Please refer to [README](https://github.com/CRaC/docs#users-flow) for details.

If you see an error, you may have to update your `criu` permissions with
```
sudo chown root:root $JAVA_HOME/lib/criu
sudo chmod u+s $JAVA_HOME/lib/criu
```

### Preparing the image
1. Run the [JDK](README.md#JDK) in the checkpoint mode
```
$JAVA_HOME/bin/java -XX:CRaCCheckpointTo=cr -jar target/example-spring-boot-0.0.1-SNAPSHOT.jar
```
2. Warm-up the instance
```
siege -c 1 -r 100000 -b http://localhost:8080
```
3. Request checkpoint
```
jcmd target/example-spring-boot-0.0.1-SNAPSHOT.jar JDK.checkpoint
```

### Restoring

```
$JAVA_HOME/bin/java -XX:CRaCRestoreFrom=cr
```

## Docker image

### Building

Create a Docker image using the provided [`Dockerfile`](./Dockerfile) with the following command:

```
docker build -t example-spring-boot .
```

### Running

Run the built Docker image with the following command:

```
docker run -p 8080:8080 \
  --cap-add CHECKPOINT_RESTORE \
  --cap-add NET_ADMIN \
  --cap-add SYS_PTRACE \
  --cap-add SYS_ADMIN \
  -v /tmp/crac:/var/crac \
  -e CHECKPOINT_RESTORE_FILES_DIR=/var/crac \
  --rm \
  example-spring-boot
```

The following logs will be outputted. A Checkpoint is created 10 seconds after the application starts. This time can be changed with the `SLEEP_BEFORE_CHECKPOINT` environment variable in [`entrypoint.sh`](./entrypoint.sh).

```
  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::                (v3.2.0)

2023-11-27T07:51:47.375Z  INFO 8 --- [           main] com.example.springboot.Application       : Starting Application v0.0.1-SNAPSHOT using Java 21.0.1 with PID 8 (/application/BOOT-INF/classes started by root in /application)
2023-11-27T07:51:47.378Z  INFO 8 --- [           main] com.example.springboot.Application       : No active profile set, falling back to 1 default profile: "default"
2023-11-27T07:51:48.138Z  INFO 8 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
2023-11-27T07:51:48.146Z  INFO 8 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
2023-11-27T07:51:48.146Z  INFO 8 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.16]
2023-11-27T07:51:48.176Z  INFO 8 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
2023-11-27T07:51:48.177Z  INFO 8 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 747 ms
2023-11-27T07:51:48.459Z  INFO 8 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2023-11-27T07:51:48.471Z  INFO 8 --- [           main] com.example.springboot.Application       : Started Application in 1.433 seconds (process running for 1.673)
Picked up JAVA_TOOL_OPTIONS:  -XX:+ExitOnOutOfMemoryError
8:
2023-11-27T07:51:57.048Z  INFO 8 --- [Attach Listener] jdk.crac                                 : Starting checkpoint
CR: Checkpoint ...
/application/entrypoint.sh: line 13:     8 Killed                  java -XX:CRaCCheckpointTo=$CHECKPOINT_RESTORE_FILES_DIR org.springframework.boot.loader.launch.JarLauncher
2023-11-27T07:52:00.491Z  INFO 8 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Restarting Spring-managed lifecycle beans after JVM restore
2023-11-27T07:52:00.494Z  INFO 8 --- [Attach Listener] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2023-11-27T07:52:00.495Z  INFO 8 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Spring-managed lifecycle restart completed (restored JVM running for 30 ms)
```

Stop the docker with Ctrl+C, and run the same image again with the same command. This time, logs like the following will be outputted due to the restore. You can see that the JVM starts very quickly.

```
Restore checkpoint from /var/crac
2023-11-27T07:52:19.196Z  INFO 8 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Restarting Spring-managed lifecycle beans after JVM restore
2023-11-27T07:52:19.199Z  INFO 8 --- [Attach Listener] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2023-11-27T07:52:19.200Z  INFO 8 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Spring-managed lifecycle restart completed (restored JVM running for 32 ms)
```
