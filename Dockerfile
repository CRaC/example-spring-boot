FROM azul/zulu-openjdk:21-jdk-crac-latest as builder
WORKDIR application

ADD ./.mvn .mvn/
ADD ./mvnw mvnw
ADD ./pom.xml pom.xml
ADD ./src src/
ADD ./.git .git/
RUN ./mvnw -V clean package -DskipTests --no-transfer-progress && \
    cp target/*.jar application.jar && \
    java -Djarmode=layertools -jar application.jar extract

FROM azul/zulu-openjdk:21-jdk-crac-latest
WORKDIR application

COPY --from=builder application/dependencies/ ./
COPY --from=builder application/spring-boot-loader/ ./
COPY --from=builder application/snapshot-dependencies/ ./
COPY --from=builder application/application/ ./
COPY entrypoint.sh ./

ENTRYPOINT ["/application/entrypoint.sh"]
