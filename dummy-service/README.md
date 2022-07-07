# Dummy Service

## 🧭 Prerequisites

* Docker daemon
* maven cli installed
* kubectl cli installed
* kind installed (or Minikube) and local kubernetes cluster running


## 🔧 Build

#### Lightweight container

```shell
./mvnw spring-boot:build-image # Using Cloud Native Buildpacks
```

#### Native executable

```shell
./mvnw package -Pnative # Using GraalVM native build tools 
```

## 🚀 Run

#### Lightweight container

```shell
docker run --rm dummy-service:0.0.1-SNAPSHOT
```

#### Native executable

```shell
target/spring-native-kubernetes-example
```

## 🔎 Check performance

