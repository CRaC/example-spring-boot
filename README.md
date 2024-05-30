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

## Preparing a container image

1. After building the project locally create an image to be checkpointed.
```
docker build -f Dockerfile.checkpoint -t example-spring-boot-checkpoint .
```

2.  Start a (detached) container that will be checkpointed. Note that we're mounting `target/cr` into the container.
```
docker run -d --rm -v $(pwd)/target/cr:/cr --cap-add=CHECKPOINT_RESTORE --cap-add=SYS_PTRACE -p 8080:8080 --name example-spring-boot-checkpoint example-spring-boot-checkpoint
```

3. Validate that the container is up and running (here you could also perform any warm-up)
```
curl localhost:8080
Greetings from Spring Boot!
```

4. Checkpoint the running container
```
docker exec -it example-spring-boot-checkpoint jcmd example-spring-boot JDK.checkpoint
```

5. Build another container image by adding the data from `target/cr` on top of the previous image and adjusting entrypoint:
```
docker build -f Dockerfile.restore -t example-spring-boot .
```

6. (Optional) Start the application in the restored container and validate that it works
```
docker run -it --rm -p 8080:8080 example-spring-boot
# In another terminal
curl localhost:8080
```
