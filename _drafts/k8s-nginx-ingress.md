---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Using the Kubernetes NGINX ingress
category: Kubernetes
---

# {{ page.title }}

This article is a simple hands-on step-by-step guide about settings up the
NGINX ingress on a K8S cluster.  For our tests, I'll be using a Minikube
cluster on an Arch Linux system, plus Helm for installing charts. Arch provided
packages for all the needed tools, so we can simply install them via:

    sudo pacman -S --needed --noconfirm minikube kubectl helm

In case another distribution is in use, you can get the latest binaries from
their release pages:
* [Helm][helm-releases]
* [Kubectl][kubectl-releases]
* [Minikube][minikube-releases]

This is epsecially important if your distro comes with older
versions of these tools, as some options have been deprecated in recent
releases). As a rule, I will use command switches which are non-deprecated in
the latest releases available in Arch at the time of writing:

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
constraints][kubectl-apiserver-version] with respect to one another, so one
caanot simply choose random versions. To keep it simple, we will ask Minikube
to install a K8S cluster following the same version as our local `kubectl`.

_NOTE: some terminal output snippets produced by `minikube` contain emojis. Be
sure to have a font that can render them on your system. On Arch Linux,
installing `noto-fonts-emoji` from the AUR suffices._

_NOTE: I will assume that the Minikube kvm2 backend can work on the local
system. If not so, Minikube will be unable to create the VM. You can either
switch to a different driver or install the required packages. I won't get into
this setup because it wouldn't fit the intended length of this article and
would be distro-specific. Arch users may refer to [this ArchWiki
page][archwiki-libvirt]._

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

At this point, the cluster is up but the NGINX ingress is not installed by
default. This is true in general for Mminikube clusters as well as for clusters
installed via `kubeadm`. Other cluster deployment methods may install it
automatically.

As a convenience, Minikube can automatically install the ingress with a single
command. but this is not the way we are going to do it, because it cannot be
used for a real, bare metal, cluster setup. For reference, this is the command
that enable Minikube's ingress addon (don't run it!):

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

Now, back to the manual installation. The [official ingress install
guide][install-ingress-with-helm] describes how to install the ingress using
its Helm chart. However, following those commands left me with a situation
where the ingress pod was running but listening on two high valued TCP ports on
the VM host, instead of using the well known 80 and 443 ports. This was
rectified by setting a value when installing the chart:

```sh
$ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
"ingress-nginx" has been added to your repositories

$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
Update Complete. ⎈Happy Helming!⎈

$ helm install -n ingress-nginx --create-namespace ingress-nginx \
    --set controller.hostPort.enabled=true ingress-nginx/ingress-nginx
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

Wait for the ingress to get ready. Meanwhile, we need some service to act as
the target of out traffic. For this, we can use a ready-made Docker image
providing a simple static website: `prakhar1989/static-site`.

Let' create a deployment for this image, as well as a ClusterIP service that
exposes it inside the cluster:

```sh
$ kubectl create deployment static-site --image=prakhar1989/static-site
deployment.apps/static-site created

$ kubectl create service clusterip static-site --tcp=80:80
service/static-site created
```

Let's test the image is running and the service working by accessing it via a
port forward:

```sh
kubectl port-forward service/static-site 8080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

Point your browser to [http://localhost:8080](http://localhost:8080) and you
should see the site homepage saying _Hello Docker_.

Press `^C` to stop `kubectl`.

At this point we should be ready to create our [ingress][k8s-ref-ingress]
resource, which will tell the ingress controller how to forward incoming HTTP
requests to our services. First, let's do it over plain HTTP: write the
following YAML to a file named `ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: static-site
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
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

At this point, the ingress is mapping all requests whose paths start with
`/static-site` to our service, while stripping that prefix from the URL.  To
check that it's working, ask Minikube for the VM address (don't copy the one
from the example below as yours will likely be different):

```sh
$ minikube ip
192.168.39.231
```

and point your browser to `http://`_`<output of minikube ip>`_`/static_site`. You
should see the same page as before.

[helm-releases]: https://github.com/helm/helm/releases
[minikube-releases]: https://github.com/kubernetes/minikube/releases
[kubectl-releases]: https://github.com/kubernetes/kubectl/releases
[install-ingress-with-helm]: https://kubernetes.github.io/ingress-nginx/deploy/#using-helm
[kubectl-apiserver-version]: https://kubernetes.io/docs/setup/release/version-skew-policy/#kubectl
[archwiki-libvirt]: https://wiki.archlinux.org/index.php/Libvirt
[k8s-ref-ingress]: https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.19/#ingress-v1-networking-k8s-io
