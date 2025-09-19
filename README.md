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
  > If you're on a Mac with Apple silicon (M1, M2, M3, etc), use `Dockerfile.checkpoint-aarch64` instead.

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

## Checkpoint as Dockerfile build step

In order to perform a checkpoint in a container we need those extra capabilites mentioned in the commands above. Regular `docker build ...` does not include these and therefore it is not possible to do the checkpoint as a build step - unless we create a docker buildx builder that will include these. See [Dockerfile reference](https://docs.docker.com/reference/dockerfile/#run---security) for more details. Note that you require a recent version of Docker BuildKit to do so.

```
docker buildx create --buildkitd-flags '--allow-insecure-entitlement security.insecure' --name privileged-builder
docker buildx build --load --builder privileged-builder --allow=security.insecure -f Dockerfile.privileged -t example-spring-boot .
```

Now you can start the example as before with
```
docker run -it --rm -p 8080:8080 example-spring-boot
```

The most important part of the Dockerfile is invoking the checkpoint with `RUN --security=insecure`. Also, when creating your own Dockerfiles don't forget to enable the experimental syntax using `# syntax=docker/dockerfile:1.3-labs`.

## Building and running in Google Cloud

It is possible to build the image in Google Cloud Build and later create a service in Google Cloud Run, with a minor modification of the steps above. Start with logging in and creating a repository for the images:

```sh
gcloud auth login
export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
# Setup default region
gcloud config set artifacts/location us-west1
gcloud config set run/region us-west1
gcloud artifacts repositories create crac-examples --repository-format=docker
```

You might need to use service accounts to perform the builds and deploy service; create these through IAM & Admin console and add necessary roles:
* cloud-build: 'Cloud Build Service Account', 'Cloud Build WorkerPool User', 'Service Account User'
* cloud-run: 'Cloud Run Admin', 'Service Account User'

We present two ways to perform the build: `cloudbuild-builder.yaml` uses the single Dockerfile steps shown above, performing the checkpoint in a BuildKit builder. You can also apply the steps from 'Preparing a container image' directly, with several modifications as used in `cloudbuild-direct.yaml`. The main difference vs. local build is that in Cloud Build the commands are executed from a container that provides access to the Docker server where it runs: volume mounts and port mapping works differently. Here is a list of differences:

* For checkpoint image we don't mount `target/cr` directly, but use a named volume `cr`. After checkpoint we need to copy the image out to pass it to restoring image Docker build.
* Ports are not bound to localhost; checkpoint container must use network `cloudbuild` and we connect to the container using its name as hostname.
* We use `--privileged` rather than fine-grained list of capabilities; Docker version used in Cloud Build does not allow capability `CHECKPOINT_RESTORE`.

You can submit the build(s) using these commands:
```sh
gcloud builds submit --config cloudbuild-builder.yaml --service-account=projects/$PROJECT_ID/serviceAccounts/cloud-builder@$PROJECT_ID.iam.gserviceaccount.com
gcloud builds submit --config cloudbuild-direct.yaml --service-account=projects/$PROJECT_ID/serviceAccounts/cloud-builder@$PROJECT_ID.iam.gserviceaccount.com
```

When the build completes, you can create the service in Cloud Run:

```sh
gcloud run deploy example-spring-boot-direct  \
    --image=us-west1-docker.pkg.dev/$PROJECT_ID/crac-examples/example-spring-boot-direct  \
    --execution-environment=gen2 --allow-unauthenticated \
    --service-account=cloud-runner@$PROJECT_ID.iam.gserviceaccount.com
```

Note that we're using Second generation Execution environment; our testing shows that it is not possible to restore in First generation. Now you can test your deployment:

```sh
export URL=$(gcloud run services describe example-spring-boot-direct --format 'value(status.address.url)')
curl $URL
Greetings from Spring Boot!
```

## Preparing checkpoint and running in Kubernetes

One way to run in Kubernetes is to perform the checkpoint locally or as part of Docker build, as we have done in the previous examples. Here we will show you how to do it end-to-end inside Kubernetes.

Let's begin by starting a new Minikube cluster. We will create a new namespace `example` and use this for the demo:

```bash
minikube start
eval $(minikube docker-env)
kubectl create ns example
kubectl config set-context --current --namespace=example
```

Now we can build an image using `Dockerfile.k8s`, based on `example-spring-boot-checkpoint` - that image hosts a built application. We will add the `netcat` utility and two scripts:
* `checkpoint.sh` starts the application with `-XX:CRaCCheckpointTo=...` and `netcat` server listening on port 1111. When somebody connects to this port, the checkpoint via `jcmd` will be triggered.
* `restore-or-start.sh` will check the presence of checkpoint image files and either restores from this image, or fallbacks to a regular application startup.

```bash
docker build -f Dockerfile.checkpoint -t example-spring-boot-checkpoint .
docker build -f Dockerfile.k8s -t example-spring-boot-k8s .
```

Now we can apply resources from `k8s.yaml`: this hosts a PersistentVolumeClaim representing a storage (in Minikube this is bound automatically to a PersistentVolume), a Deployment that will create the application using the `restore-or-start.sh` script, and a Job that will create the checkpoint image. You can apply that now and observe that this has created two pods:

```bash
kubectl apply -f k8s.yaml
kubectl get po
```
```
NAME                                 READY   STATUS    RESTARTS   AGE
create-checkpoint-fsfs4              2/2     Running   0          4s
example-spring-boot-68b69cc8-bbxnx   1/1     Running   0          4s
```

When you explore application logs (`kubectl logs example-spring-boot-68b69cc8-bbxnx`) you will find that the application is started normally; the checkpoint image was not created yet. The other pod, though, hosts two containers: one running `checkpoint.sh` and the other warming the application up using `siege`, and then triggering the checkpoint through connection on port 1111 (this is not a built-in feature, remember that we use `netcat` in the background).

After a while the job completes:

```bash
kubectl get job
NAME                STATUS     COMPLETIONS   DURATION   AGE
create-checkpoint   Complete   1/1           19s        44m
```

And now you can rollout a new deployment, this time restoring the application from the checkpoint image:

```bash
kubectl rollout restart deployment/example-spring-boot
```

After a short moment that application is back up:

```
NAME                                   READY   STATUS      RESTARTS   AGE
create-checkpoint-fsfs4                0/2     Completed   0          95s
example-spring-boot-79b98966db-ml2pj   1/1     Running     0          15s
```

In the logs you can see that it performed the restore:

```
2024-09-30T07:52:11.858Z  INFO 129 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Restarting Spring-managed lifecycle beans after JVM restore
2024-09-30T07:52:11.866Z  INFO 129 --- [Attach Listener] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2024-09-30T07:52:11.868Z  INFO 129 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Spring-managed lifecycle restart completed (restored JVM running for 45 ms)
```

At last, let's verify that the application responds to our requests. You should get the "Greetings from Spring Boot!" reply:

```bash
kubectl expose deployment example-spring-boot --type=NodePort --port=8080
URL=$(minikube service example-spring-boot -n example --url)
curl $URL
```
