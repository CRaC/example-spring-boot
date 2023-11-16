# example-spring-boot

This is an example of Spring Boot [Getting Started](https://github.com/spring-guides/gs-spring-boot/tree/main/initial) modified to work on OpenJDK CRaC, which consists only in using Spring Boot 3.2+ and adding the `org.crac:crac` dependency (version `1.4.0` or later).

## Building

Use Maven to build
```
./mvnw package
```

## Running

Please refer to [README](https://github.com/CRaC/docs#users-flow) for details.

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
