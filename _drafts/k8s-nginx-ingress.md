---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Using the Kubernetes NGINX ingress
category: Kubernetes
---

# {{ page.title }}

This article is a simple hands-on step-by-step guide about settings up
the NGINX ingress on a K8S cluster.  For our tests, I'll be using a
Minikube cluster on an Arch Linux system, plus Helm for installing
charts.

## Setting up Minikube

Arch provided packages for all the needed tools, so we can simply
install them via:

    sudo pacman -S --needed --noconfirm minikube kubectl helm

In case another distribution is in use, you can get the latest binaries from
their release pages:
* [Helm][helm-releases]
* [Kubectl][kubectl-releases]
* [Minikube][minikube-releases]

This is epsecially important if your distro comes with older versions of
these tools, as some options have been deprecated in recent releases).
As a rule, I will use command switches which are non-deprecated in the
latest releases available in Arch at the time of writing:

```
$ minikube version
minikube version: v1.15.1
commit: 23f40a012abb52eff365ff99a709501a61ac5876-dirty

$ kubectl version --client=true
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.4", GitCommit:"d360454c9bcd1634cf4cc52d1867af5491dc9c5f", GitTreeState:"archive", BuildDate:"2020-11-25T13:19:56Z", GoVersion:"go1.15.5", Compiler:"gc", Platform:"linux/amd64"}

$ helm version
version.BuildInfo{Version:"v3.4.1", GitCommit:"c4e74854886b2efe3321e185578e6db9be0a6e29", GitTreeState:"clean", GoVersion:"go1.15.4"}
```

Of course, components which have version relationships must be able to
interwork.  `kubectl` and the K8S API server have [version
constraints][kubectl-apiserver-version] with respect to one another, so
one cannot simply choose random versions. To keep it simple, we will ask
Minikube to install a K8S cluster following the same version as our
local `kubectl`.

_NOTE: some terminal output snippets produced by `minikube` contain
emojis. Be sure to have a font that can render them on your system. On
Arch Linux, installing `noto-fonts-emoji` from the AUR suffices._

_NOTE: I will assume that the Minikube kvm2 backend can work on the
local system. If not so, Minikube will be unable to create the VM. You
can either switch to a different driver or install the required
packages. I won't get into this setup because it wouldn't fit the
intended length of this article and would be distro-specific. Arch users
may refer to [this ArchWiki page][archwiki-libvirt]. OpenSUSE users may
refer to [this page][opensuse-libvirt]._

```sh
$ K8S_VERSION=$(kubectl version --client=true | sed -E 's/.*GitVersion:"([^"]+)".*/\1/')
$ echo $K8S_VERSION 
v1.19.4
$ minikube  start --driver=kvm2 --kubernetes-version="$K8S_VERSION"
😄  minikube v1.15.1 on Arch 
✨  Using the kvm2 driver based on user configuration
💾  Downloading driver docker-machine-driver-kvm2:
    > docker-machine-driver-kvm2.sha256: 65 B / 65 B [-------] 100.00% ? p/s 0s
    > docker-machine-driver-kvm2: 13.56 MiB / 13.56 MiB  100.00% 557.48 KiB p/s
💿  Downloading VM boot image ...
    > minikube-v1.15.0.iso.sha256: 65 B / 65 B [-------------] 100.00% ? p/s 0s
    > minikube-v1.15.0.iso: 181.00 MiB / 181.00 MiB [] 100.00% 9.23 MiB p/s 20s
👍  Starting control plane node minikube in cluster minikube
💾  Downloading Kubernetes v1.19.4 preload ...
    > preloaded-images-k8s-v6-v1.19.4-docker-overlay2-amd64.tar.lz4: 486.35 MiB
🔥  Creating kvm2 VM (CPUs=2, Memory=4000MB, Disk=20000MB) ...
🐳  Preparing Kubernetes v1.19.4 on Docker 19.03.13 ...
🔎  Verifying Kubernetes components...
🌟  Enabled addons: storage-provisioner, default-storageclass
🏄  Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default
```

At this point, the cluster is up but the NGINX ingress is not installed
by default. This is true in general for Mminikube clusters as well as
for clusters installed via `kubeadm`. Other cluster deployment methods
may install it automatically.

As a convenience, Minikube can automatically install the ingress with a
single command. but this is not the way we are going to do it, because
it cannot be used for a real, bare metal, cluster setup. For reference,
this is the command that enable Minikube's ingress addon (don't run
it!):

```sh
$ minikube addons enable ingress
🔎  Verifying ingress addon...
🌟  The 'ingress' addon is enabled
```

Well, if you _did_ run it... you can simply turn it off with:

```sh
$ minikube addons disable ingress
🌑  "The 'ingress' addon is disabled
```

## Install the NGINX ingress

Now, back to the manual installation. The [official ingress install
guide][install-ingress-with-helm] describes how to install the ingress
using its Helm chart. However, following those commands without
customizing the chart values configure the ingress to expect an external
LoadBalancer, which we don't want to use. Also, it creates A deployment
resource by default.

What we want to do, instead, is create a DaemonSet so that each worker
gets its own ingress pod handling its incoming traffic. Also, that pods
should listen on ports 80 and 443 on the host itself, rather than
expecting an external LB to do it.

Thankfully, we can set a couple of values to tell the chart to do
exactly that:

* `controller.hostPort.enabled` can be set to true to have the ingress
  listen on host ports directly;
* `controller.kind` can be set to `DaemonSet` to override the default
  resource type.

```sh
$ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
"ingress-nginx" has been added to your repositories

$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
Update Complete. ⎈Happy Helming!⎈

$ helm install -n ingress-nginx --create-namespace ingress-nginx \
    --set controller.hostPort.enabled=true \
    --set controller.kind=DaemonSet \
    ingress-nginx/ingress-nginx
NAME: ingress-nginx
LAST DEPLOYED: Fri Nov 27 22:25:11 2020
NAMESPACE: ingress-nginx
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace ingress-nginx get services -o wide -w ingress-nginx-controller'
[redacted for brevity]
```

## Deploy a test service to act as our traffic target

While we wait for the ingress to come up, we need some service to act as
the target of out traffic.  For this, we can use a ready-made Docker
image providing a simple static website: `prakhar1989/static-site`.

Let' create a deployment for this image, as well as a ClusterIP service
that exposes it inside the cluster:

```sh
$ kubectl create deployment static-site --image=prakhar1989/static-site
deployment.apps/static-site created

$ kubectl create service clusterip static-site --tcp=80:80
service/static-site created
```

Let's test the image is running and the service working by accessing it
via a port forward:

```sh
kubectl port-forward service/static-site 8080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

Point your browser to [http://localhost:8080](http://localhost:8080) and
you should see the site homepage saying _Hello Docker_.

Press `^C` to stop `kubectl`.

## Access the service via the ingress

At this point we should be ready to create our
[ingress][k8s-ref-ingress] resource, which will tell the ingress
controller how to forward incoming HTTP requests to our services. First,
let's do it over plain HTTP: write the following YAML to a file named
`ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: static-site
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - http:
        paths:
          - path: /static-site
            pathType: Prefix
            backend:
              service:
                name: static-site
                port:
                  number: 80
```

Then, apply it:

```sh
$ kubectl apply -f ingress.yaml
ingress.networking.k8s.io/static-site created
```

At this point, the ingress is mapping all requests whose paths start
with `/static-site` to our service, while stripping that prefix from the
URL.  To check that it's working, ask Minikube for the VM address (don't
copy the one from the example below as yours will likely be different):

```sh
$ minikube ip
192.168.39.231
```

and point your browser to `http://<output of minikube ip>/static_site`.
You should see the same page as before.

Let's break down the ingress definition. First, it comes with two
annotations:
* `kubernetes.io/ingress.class: "nginx"` controls the association
  between this ingress resource and an ingress controller, which will be
  responsible for routing the requests related to the paths specified in
  the resource. Since we can have multiple ingress controllers in a
  cluster, it is important to explicitly establish a bond between
  ingress resources and controllers.  This annotation clarifies that the
  traffic pertaining to this ingress resource should be handled by the
  ingress controller identified by the `nginx` class. The NGINX ingress
  Helm chart marked the installed ingress controller with this class for
  us, so we can simply refer to it in our resources.
* `nginx.ingress.kubernetes.io/rewrite-target: /` controls URL
  rewriting. Requests coming to the ingress controller for our static
  site will be rooted under `/static-site`, but the web-server running
  inside the image we deployed earlier does not know anything about this
  prefix, it expects pages to sit under `/`. So we must strip the prefix
  from the path before forwarding the request to the pod. This
  annotations tells the controller do that.

The `spec` part defined the mapping between incoming HTTP requests and
the services that should handle them. There is a single path in the
rules, which configures all URL's starting with `/static-site` to be
forwarded to the service called `static-site` and more precisely to its
port 80.  All other paths does not have a rule, and will be handled by
the _default backend_ defined by the ingress controller. For the NGINX
ingress, this will simply return an error 404.

### Filter on host names

The previous ingress resource only matched incoming requests to services
using the URL path component. The host name used in the URL, and thus
sent in the request using the `Host` header, was not involved in
selecting a backend. So, as long as the path matches the specified
prefix, out `static-site` service will get the traffic for all host
names. We can check for this using curl:

```sh
# Access the page using the IP as the hostname, effectively sending
# a Host header set to the Minikube IP. The actual response is discarded
to have a better view of curl debug lines.
$ curl --noproxy \* -v -s http://$(minikube ip)/static-site > /dev/null
*   Trying 192.168.39.231:80...
* Connected to 192.168.39.231 (192.168.39.231) port 80 (#0)
> GET /static-site HTTP/1.1
> Host: 192.168.39.231
> User-Agent: curl/7.73.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Sat, 28 Nov 2020 13:21:39 GMT
< Content-Type: text/html
< Content-Length: 2041
< Connection: keep-alive
< Last-Modified: Sun, 03 Jan 2016 04:32:16 GMT
< ETag: "5688a450-7f9"
< Accept-Ranges: bytes
< 
{ [2041 bytes data]
* Connection #0 to host 192.168.39.231 left intact

# This time we use curl --resolve option to force a
# chosen hostname to resolve to the Minikube IP. Due to the use of an
# hostname in the URL, the Host header is set to static-site.local
$ curl --noproxy \* -v -s --resolve static-site.local:80:$(minikube ip) \
  http://static-site.local/static-site > /dev/null
>   http://static-site.local/static-site > /dev/null
* Added static-site.local:80:192.168.39.231 to DNS cache
* Hostname static-site.local was found in DNS cache
*   Trying 192.168.39.231:80...
* Connected to static-site.local (192.168.39.231) port 80 (#0)
> GET /static-site HTTP/1.1
> Host: static-site.local
> User-Agent: curl/7.73.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Sat, 28 Nov 2020 13:24:53 GMT
< Content-Type: text/html
< Content-Length: 2041
< Connection: keep-alive
< Last-Modified: Sun, 03 Jan 2016 04:32:16 GMT
< ETag: "5688a450-7f9"
< Accept-Ranges: bytes
< 
{ [2041 bytes data]
* Connection #0 to host static-site.local left intact
```

As can be seen, the `Host` header is different in the two calls, but the
response was still a 200 with a payload of 2041 bytes in both cases.  In
the second test, we used `curl`'s `--resolve` option which causes the
hostname `static-site.local` to resolve to the Minikube IP withoutu the
need to patch `/etc/hosts` or add a DNS entry.

Of course, NGINX can perform request filtering based on hostnames. We
just have to add an `host` field to our rules in the ingress definition.
If we want our site to only be available as `static-site.local`, we
pacth the resource as follows:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: static-site
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: static-site.local
      http:
        paths:
          - path: /static-site
            pathType: Prefix
            backend:
              service:
                name: static-site
                port:
                  number: 80
```

Let's update the cluster:

```sh
$ kubectl apply -f ingress.yaml
ingress.networking.k8s.io/static-site configured
```

and now repeat out tests with `curl`:

```sh
$ curl --noproxy \* -v -s http://$(minikube ip)/static-site > /dev/null
*   Trying 192.168.39.231:80...
* Connected to 192.168.39.231 (192.168.39.231) port 80 (#0)
> GET /static-site HTTP/1.1
> Host: 192.168.39.231
> User-Agent: curl/7.73.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 404 Not Found
< Date: Sat, 28 Nov 2020 13:33:02 GMT
< Content-Type: text/html
< Content-Length: 146
< Connection: keep-alive
< 
{ [146 bytes data]
* Connection #0 to host 192.168.39.231 left intact

curl --noproxy \* -v -s --resolve static-site.local:80:$(minikube ip) \
  http://static-site.local/static-site > /dev/null
>   http://static-site.local/static-site > /dev/null
* Added static-site.local:80:192.168.39.231 to DNS cache
* Hostname static-site.local was found in DNS cache
*   Trying 192.168.39.231:80...
* Connected to static-site.local (192.168.39.231) port 80 (#0)
> GET /static-site HTTP/1.1
> Host: static-site.local
> User-Agent: curl/7.73.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Sat, 28 Nov 2020 13:33:48 GMT
< Content-Type: text/html
< Content-Length: 2041
< Connection: keep-alive
< Last-Modified: Sun, 03 Jan 2016 04:32:16 GMT
< ETag: "5688a450-7f9"
< Accept-Ranges: bytes
< 
{ [2041 bytes data]
* Connection #0 to host static-site.local left intact
```

Note that this time the request containing the IP in the URL returned
404, because the ingress is no longer matching the IP with the service.

### Adding TLS

Until now, we have used plain HTTP both between the client and the
ingress and between the ingress and the target service. NGINX can do
_TLS temrination_, meaning it receives HTTPS requests, perform TLS
handshake, and then forward the plain HTTP request to the final service.
This way, there is a single point where certificates and key must be
provisioned: the ingress controller itself. Services can run over plain
HTTP, while all external traffic, which terminates at the ingress, is
secured.

Before we can enable TLS, we must prepare a certificate. This step must
be performed with care because the ingress seems to be picky about the
certificates it accepts. In particular, it refuses certificates
that use the common name to identify the expected host name of the
server. It pretends that certificates also contain at least one subject
alternative name, even if the only one is identical to the common name.
We will first generate an "invalid" certificate without any SAN's, to
trigger the error, then, we'll create a good certificate with a SAN to
rectify the situation.

### The "bad" certificate

Let's issue a self-signed certificate with OpenSSL:

```sh
$ openssl req -new -x509 -nodes -newkey rsa:2048 -out tls.crt -keyout tls.key \
  -subj '/C=IT/O=Local test/CN=static-site.local'
Generating a RSA private key
.....................................................................................................................+++++
..............+++++
writing new private key to 'tls.key'
-----
```

For the ingress controller to be able to read out certificate and key,
we must load them to our cluster. We must use a secret for this
purpouse, which will then be referenced from the ingress resource.
`kubectl` provides a shortcut command to create a well-formed secret
suitable for use with TLS:

```sh
$ kubectl create secret tls static-site --cert=tls.crt --key tls.key
secret/static-site created

$ kubectl get -o yaml secrets/static-site
```

In order to enable TLS for our ingress, we must edit the resource to add
a `tls` object:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: static-site
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
spec:
  # This is the new stuff
  tls:
    - hosts:
        - static-site.local
      secretName: static-site
  # End new stuff
  rules:
    - host: static-site.local
      http:
        paths:
          - path: /static-site
            pathType: Prefix
            backend:
              service:
                name: static-site
                port:
                  number: 80
```

```sh
$ kubectl apply -f ingress.yaml
ingress.networking.k8s.io/static-site configured
```

Note that the new `tls` object is a list, where each entry defines:
* `hosts`: a list of expected host names to which the certificate
  applies. We have set it to be equal to the `host` field inside our
  only rule;
* `secretName`: the name of a secret that hold the certificate and key
  for server-side TLS. It's set to the name of the secret we created
  earlier.

As soon as the new ingress is applied, the controller reconfigures
itself to enable TLS. However, if we now dump the logs of the ingress
controller pod:

```sh
$ POD_NAME=$(kubectl get pods -n ingress-nginx | tail -n 1 | cut -d " " -f 1)
$ kubectl logs -n ingress-nginx "$POD_NAME" | grep -i 'Common Name'
W1128 14:04:04.781934       6 controller.go:1180] Unexpected error validating SSL certificate "default/static-site" for server "static-site.local": x509: certificate relies on legacy Common Name field, use SANs or temporarily enable Common Name matching with GODEBUG=x509ignoreCN=0
```

Note the error message about the lacks of subject alternative names. The
certificate has been rejected.

<!-- Links -->
[helm-releases]: https://github.com/helm/helm/releases
[minikube-releases]: https://github.com/kubernetes/minikube/releases
[kubectl-releases]: https://github.com/kubernetes/kubectl/releases
[install-ingress-with-helm]: https://kubernetes.github.io/ingress-nginx/deploy/#using-helm
[kubectl-apiserver-version]: https://kubernetes.io/docs/setup/release/version-skew-policy/#kubectl
[archwiki-libvirt]: https://wiki.archlinux.org/index.php/Libvirt
[k8s-ref-ingress]: https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.19/#ingress-v1-networking-k8s-io
[opensuse-libvirt]: https://doc.opensuse.org/documentation/leap/virtualization/html/book.virt/cha-vt-installation.html#sec-vt-installation-kvm
