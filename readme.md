# 🚀 Spring Boot + Docker + Kubernetes + Helm — Complete Guide 

> **Goal:** Deploy a simple Java "Hello World" web app to Kubernetes using Helm charts.  
> This document explains **what each tool is**, **why we use it**, and **every step we took**.

---

## 📚 Table of Contents

1. [The Big Picture — How All the Tools Connect](#1-the-big-picture)
2. [What We Built — Project Structure](#2-what-we-built)
3. [Step 1 — Spring Boot App (the application)](#3-step-1--spring-boot-app)
4. [Step 2 — Docker (packaging the app)](#4-step-2--docker)
5. [Step 3 — Kubernetes (running the app at scale)](#5-step-3--kubernetes)
6. [Step 4 — Helm (deploying to Kubernetes)](#6-step-4--helm)
7. [Step 5 — Minikube (local Kubernetes cluster)](#7-step-5--minikube)
8. [Complete Deployment Commands — Step by Step](#8-complete-deployment-commands)
9. [How to Verify It's Working](#9-how-to-verify)
10. [Useful Day-to-Day Commands](#10-useful-commands)

---

## 1. The Big Picture

Before diving in, here is how all the tools connect together:

```
┌──────────────────────────────────────────────────────────────────────┐
│                        YOUR MACHINE                                  │
│                                                                      │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────────────────┐│
│  │ Spring Boot │───▶│    Docker    │───▶│       Kubernetes         ││
│  │  Java App   │    │  Container   │    │  (managed by minikube)   ││
│  │  (the code) │    │  (the box)   │    │  (the cluster manager)   ││
│  └─────────────┘    └──────────────┘    └──────────────────────────┘│
│                                                    ▲                  │
│                                                    │                  │
│                                              ┌─────────┐             │
│                                              │  Helm   │             │
│                                              │(deploys)│             │
│                                              └─────────┘             │
└──────────────────────────────────────────────────────────────────────┘
```

| Tool | What it does | Real-world analogy |
|---|---|---|
| **Spring Boot** | Writes the actual web app | The food you cook |
| **Docker** | Packages the app + all its dependencies into one portable unit | Putting the food in a lunchbox |
| **Kubernetes** | Runs, scales, and manages your Docker containers | A restaurant kitchen with many stations |
| **Minikube** | A mini Kubernetes cluster that runs on your laptop | A practice kitchen at home |
| **Helm** | Deploys and configures your app in Kubernetes | A recipe card for the kitchen |

---

## 2. What We Built

```
Helm_chart_test/
│
├── pom.xml                          ← Maven: tells Java HOW to build the app
├── Dockerfile                       ← Instructions to build a Docker image
├── .dockerignore                    ← Files to exclude from Docker build
├── .gitignore                       ← Files to exclude from Git
│
├── src/
│   └── main/
│       ├── java/com/example/helloworld/
│       │   ├── HelloWorldApplication.java    ← Main entry point (@SpringBootApplication)
│       │   └── HelloWorldController.java     ← REST API endpoints (GET /hello)
│       └── resources/
│           └── application.properties        ← Config: port=8080
│
└── helm/
    └── helloworld/                  ← The Helm Chart (deployment package)
        ├── Chart.yaml               ← Chart name, version metadata
        ├── values.yaml              ← Default configuration values
        └── templates/
            ├── _helpers.tpl         ← Helper functions (like macros)
            ├── deployment.yaml      ← Kubernetes Deployment template
            ├── service.yaml         ← Kubernetes Service template
            └── NOTES.txt            ← Instructions shown after install
```

---

## 3. Step 1 — Spring Boot App

### What is Spring Boot?
Spring Boot is a Java framework that makes it easy to build web APIs (REST APIs). Instead
of writing hundreds of lines of configuration, Spring Boot auto-configures everything for you.

### What we wrote

**`HelloWorldController.java`** — This is the core of our app:
```java
@RestController                   // Tell Spring: this class handles HTTP requests
public class HelloWorldController {

    @GetMapping("/hello")         // When someone calls GET /hello...
    public String hello() {
        return "Hello, World! 🌍 — Running inside Kubernetes via Helm";  // ...return this
    }
}
```

**`application.properties`** — Simple config:
```properties
server.port=8080             # App listens on port 8080
management.endpoints.web.exposure.include=health  # Expose /actuator/health
```

The `/actuator/health` endpoint is important — **Kubernetes uses it to know if your app is alive**.

### How we built it
```bash
mvn clean install
```
This compiles the Java code and packages it into a single fat JAR file:
```
target/helloworld-1.0.0.jar   ← Everything the app needs, in one file (~20MB)
```

---

## 4. Step 2 — Docker

### What is Docker?
Docker packages your app + Java runtime + all dependencies into a single **image** — a
portable, self-contained unit that runs identically everywhere.

Without Docker, you'd have to ensure Java 21 is installed on every server.
With Docker, the image already contains Java — you just ship the image.

```
WITHOUT DOCKER                          WITH DOCKER
──────────────────────────────────      ──────────────────────────────────
Server needs:                           Image contains:
  - Java 21 installed                     - Java 21 ✓
  - Correct version                       - Your JAR ✓
  - Right config                          - Config ✓
  - Your JAR uploaded                   
  (And this must match exactly)         Just run the image → works everywhere
```

### What we wrote — `Dockerfile`

We used a **multi-stage build** (2 steps in one Dockerfile):

```dockerfile
# ── STAGE 1: BUILD ──────────────────────────────────────────
# Use a big Maven image (has Java + Maven) to compile the code
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B    # Download all dependencies first (for caching)

COPY src ./src
RUN mvn clean package -DskipTests   # Compile and package into a JAR

# ── STAGE 2: RUNTIME ────────────────────────────────────────
# Use a TINY Alpine Linux image with just the Java runtime (no Maven needed)
FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app
COPY --from=build /app/target/helloworld-1.0.0.jar app.jar  # Only copy the JAR

RUN addgroup -S appgroup && adduser -S appuser -G appgroup   # Non-root user (security)
USER appuser

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Why 2 stages?**
- Stage 1 (Maven image) = ~700MB — needed only to build
- Stage 2 (Alpine JRE) = ~150MB — the final image you ship

The final Docker image is **~4x smaller** because we discard all the build tools.

### How we built the Docker image
```bash
docker build -t helloworld:latest .
```
- `-t helloworld:latest` = name the image `helloworld` with tag `latest`
- `.` = use current directory as context (reads `Dockerfile`)

```bash
# Test the image locally (without Kubernetes)
docker run -d -p 8080:8080 --name hw-test helloworld:latest
curl http://localhost:8080/hello
# → Hello, World! 🌍 — Running inside Kubernetes via Helm
docker stop hw-test && docker rm hw-test
```

---

## 5. Step 3 — Kubernetes

### What is Kubernetes?
Kubernetes (K8s) is a system that **manages containers at scale**. It answers questions like:
- What if my container crashes? → Kubernetes auto-restarts it
- What if I need 10 copies of my app? → Kubernetes creates 10 pods
- How do users reach my app? → Kubernetes routes traffic via Services

### Key Kubernetes Concepts

**Pod** — The smallest unit. Contains one or more Docker containers.
```
Pod
└── helloworld container (running helloworld:latest)
```

**Deployment** — Manages pods. Says "I want 1 replica of helloworld running at all times".
```
Deployment
└── ReplicaSet (ensures 1 pod always exists)
    └── Pod → helloworld container
```

**Service** — A stable network endpoint that routes traffic to your pods.
```
User → Service (port 30080) → Pod (port 8080)
```

**Why not just run docker directly on a server?**
- Docker runs one container. Kubernetes runs 100s with auto-healing, load balancing, and rolling updates.

### Kubernetes YAML vs Helm

Without Helm, you'd write raw YAML and apply it manually:
```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```
The problem: values like image name, replica count, ports are hardcoded in those files.
If you want to change anything, you edit the file and re-apply.

**That's exactly why Helm exists.**

---

## 6. Step 4 — Helm

### What is Helm?
Helm is the **package manager for Kubernetes** — similar to how you use `brew` on Mac or
`apt` on Ubuntu to install software.

Instead of applying raw YAML, Helm lets you:
1. **Template** your Kubernetes YAML (use variables instead of hardcoded values)
2. **Install** everything in one command
3. **Upgrade** with one command (rollback too!)
4. **Track releases** — Helm remembers what version is deployed

### How Helm Works — The Flow

```
                 ┌─────────────────────────────────┐
values.yaml ────▶│                                 │
                 │     Helm Template Engine         │──▶ Final YAML ──▶ kubectl apply
--set flags ────▶│  (merges values into templates) │
                 │                                 │
                 └─────────────────────────────────┘
                          ▲
                   templates/*.yaml
```

### Our Helm Chart Files Explained

#### `Chart.yaml` — Metadata
```yaml
name: helloworld          # Name of the chart
version: 0.1.0            # Chart version (the deployment packaging)
appVersion: "1.0.0"       # App version (your Spring Boot app version)
```

#### `values.yaml` — The Control Panel
This is the most important file. **Every configurable thing lives here:**
```yaml
replicaCount: 1           # How many pods to run

image:
  repository: helloworld  # Docker image name
  tag: latest             # Docker image tag
  pullPolicy: IfNotPresent # Use local image if available

service:
  type: NodePort          # Expose externally via a node port
  port: 80                # Port the Service listens on
  targetPort: 8080        # Port the Spring Boot app listens on
  nodePort: 30080         # External port (accessible from outside the cluster)

resources:
  requests:
    memory: "256Mi"       # Guaranteed memory
    cpu: "250m"           # Guaranteed CPU (250 millicores = 0.25 cores)
  limits:
    memory: "512Mi"       # Maximum memory before pod is killed
    cpu: "500m"           # Maximum CPU
```

To change any of these at deploy time:
```bash
helm install helloworld-release helm/helloworld --set replicaCount=3
```

#### `templates/deployment.yaml` — Kubernetes Deployment Template
Instead of hardcoded values, we use `{{ .Values.xxx }}` placeholders:
```yaml
replicas: {{ .Values.replicaCount }}           # Reads from values.yaml → 1
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"  # helloworld:latest
```

When you run `helm install`, Helm fills in all the `{{ }}` placeholders and sends the
final YAML to Kubernetes.

**Health probes in the Deployment:**
```yaml
livenessProbe:           # "Is the app alive?"
  httpGet:
    path: /actuator/health   # Kubernetes calls this endpoint
    port: 8080
  initialDelaySeconds: 30    # Wait 30s before first check (startup time)
  periodSeconds: 10          # Check every 10s
  failureThreshold: 3        # Restart pod after 3 consecutive failures

readinessProbe:          # "Is the app ready to receive traffic?"
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 20    # Start checking after 20s
```

- **Liveness**: If this fails → Kubernetes **restarts** the pod
- **Readiness**: If this fails → Kubernetes **stops routing traffic** to the pod

#### `templates/service.yaml` — Kubernetes Service Template
```yaml
type: NodePort           # Makes the app accessible from outside the cluster
port: 80                 # Inside cluster
targetPort: 8080         # Container port (Spring Boot)
nodePort: 30080          # Outside the cluster — this is how you reach the app
```

#### `templates/_helpers.tpl` — Reusable Functions
These are Go template functions that generate consistent names and labels:
```
helloworld.fullname  → "helloworld-release"
helloworld.labels    → standard K8s labels (app name, version, chart, etc.)
```

#### `templates/NOTES.txt` — Post-Install Instructions
This is what gets printed after `helm install` runs — it shows you how to access the app.

---

## 7. Step 5 — Minikube

### What is Minikube?
Minikube runs a **real Kubernetes cluster** on your laptop, inside a Docker container.
Perfect for learning and local testing.

```
Your Mac
└── Docker (already installed)
    └── Minikube container (runs a full K8s cluster inside)
        └── Your helloworld pod
```

### Why Minikube Instead of a Real Cluster?
- Real clusters (AWS EKS, GKE) cost money
- Minikube is free, instant, and local
- Everything you learn here works exactly the same on real clusters

### NodePort Note on Docker Driver
On Mac, when Minikube uses the Docker driver, NodePorts are **not directly accessible**
from your Mac. You need to use:

```bash
# Option 1: port-forward (easiest)
kubectl port-forward svc/helloworld-release 9090:80
curl http://localhost:9090/hello

# Option 2: minikube tunnel (advanced)
minikube tunnel   # run in a separate terminal
curl http://localhost/hello
```

---

## 8. Complete Deployment Commands

Here is the **exact sequence of every command we ran**, in order:

### Build Phase

```bash
# 1. Build the Spring Boot JAR
cd /Users/rajkumarmyakala/Helm_chart_test
mvn clean install
# → target/helloworld-1.0.0.jar created

# 2. Build the Docker image (multi-stage build)
docker build -t helloworld:latest .
# → helloworld:latest image created locally
```

### Cluster Setup

```bash
# 3. Install minikube (one-time setup)
brew install minikube

# 4. Start Kubernetes cluster (uses Docker as the VM driver)
minikube start --driver=docker
# → Kubernetes v1.35.1 running inside Docker

# 5. Load our local Docker image INTO minikube's environment
minikube image load helloworld:latest
# → Image now available inside the cluster
# (Kubernetes can't see your local Docker images by default)
```

### Helm Deployment

```bash
# 6. Deploy the app using Helm
helm install helloworld-release helm/helloworld
#    └── "helloworld-release" = the release name (you can pick any name)
#    └── "helm/helloworld"    = path to the Helm chart directory

# Helm does this internally:
#   a) Reads values.yaml for defaults
#   b) Fills in templates/deployment.yaml and templates/service.yaml
#   c) Calls kubectl apply on the resulting YAML
#   d) Prints NOTES.txt
```

### Verify & Access

```bash
# 7. Check pods are running
kubectl get pods
# NAME                                  READY   STATUS    RESTARTS   AGE
# helloworld-release-684bc45d77-vgqw8   1/1     Running   0          23s

# 8. Check the service was created
kubectl get svc
# NAME                 TYPE        CLUSTER-IP     PORT(S)
# helloworld-release   NodePort    10.110.31.34   80:30080/TCP

# 9. Port-forward to access the app
kubectl port-forward svc/helloworld-release 9090:80

# 10. Hit the endpoint!
curl http://localhost:9090/hello
# → Hello, World! 🌍 — Running inside Kubernetes via Helm  ✅
```

---

## 9. How to Verify

### Check pod status
```bash
kubectl get pods
# 1/1 means: 1 container running out of 1 total — healthy!
```

### Check pod logs (Spring Boot startup output)
```bash
kubectl logs deployment/helloworld-release
# You'll see the Spring Boot banner and "Started HelloWorldApplication in X seconds"
```

### Describe a pod (full details)
```bash
kubectl describe pod <pod-name>
# Shows: image used, events, probe results, resource usage
```

### Check Helm release status
```bash
helm list
# NAME                CHART              STATUS    REVISION
# helloworld-release  helloworld-0.1.0   deployed  1

helm status helloworld-release
# Full status + the NOTES.txt output
```

### Preview what Helm would deploy (without actually deploying)
```bash
helm template helloworld-release helm/helloworld
# Prints the final Kubernetes YAML after template substitution
# Great for debugging or reviewing before deploying
```

---

## 10. Useful Commands

### Scaling
```bash
# Scale to 3 replicas (3 pods)
helm upgrade helloworld-release helm/helloworld --set replicaCount=3
kubectl get pods   # See 3 pods now running
```

### Rolling Update (new image version)
```bash
# 1. Build new image with a version tag
docker build -t helloworld:v2 .
minikube image load helloworld:v2

# 2. Upgrade the Helm release to use new image
helm upgrade helloworld-release helm/helloworld --set image.tag=v2

# 3. Watch the rolling update happen (old pods replaced one by one)
kubectl get pods -w
```

### Rollback
```bash
helm rollback helloworld-release 1   # Roll back to revision 1
helm history helloworld-release      # See all revisions
```

### Teardown
```bash
# Remove the app from Kubernetes
helm uninstall helloworld-release

# Stop minikube
minikube stop

# Delete minikube cluster completely
minikube delete
```

---

## Summary — Why Each Tool Exists

| Problem | Solution | Tool |
|---|---|---|
| I need to write a web API | Framework with auto-config | Spring Boot |
| App needs Java installed everywhere | Put Java inside the app package | Docker |
| Need to manage many containers | Automated container orchestration | Kubernetes |
| Installing K8s is complex locally | Single-node cluster on laptop | Minikube |
| K8s YAML is repetitive and hardcoded | Templated package manager for K8s | Helm |

The whole point of this stack: **write code once, describe deployment once in Helm,
and deploy identically to your laptop, staging, or production** with the same single command.
