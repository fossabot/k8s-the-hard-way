#!/usr/bin/env bash

vagrant ssh master -c '''
sudo mkdir -p /etc/kubernetes/config
kube_stable=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
wget -q --https-only --timestamping \\
  "https://storage.googleapis.com/kubernetes-release/release/${kube_stable}/bin/linux/amd64/kube-apiserver" \\
  "https://storage.googleapis.com/kubernetes-release/release/${kube_stable}/bin/linux/amd64/kube-controller-manager" \\
  "https://storage.googleapis.com/kubernetes-release/release/${kube_stable}/bin/linux/amd64/kube-scheduler" \\
  "https://storage.googleapis.com/kubernetes-release/release/${kube_stable}/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
sudo mkdir -p /var/lib/kubernetes/

sudo cp /vagrant/certs/ca.pem /vagrant/certs/ca-key.pem /vagrant/certs/kubernetes-key.pem /vagrant/certs/kubernetes.pem \
  /vagrant/certs/service-account-key.pem /vagrant/certs/service-account.pem \
  /vagrant/encryption-config.yaml /var/lib/kubernetes/

INTERNAL_IP=$(ip address show | grep \"inet 10.240\" | sed -e \"s/^.*inet //\" -e \"s/\/.*$//\" | tr -d \"\n\" 2>/dev/null)

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service >/dev/null
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\\\
  --advertise-address=${INTERNAL_IP} \\\\
  --allow-privileged=true \\\\
  --apiserver-count=1 \\\\
  --audit-log-maxage=30 \\\\
  --audit-log-maxbackup=3 \\\\
  --audit-log-maxsize=100 \\\\
  --audit-log-path=/var/log/audit.log \\\\
  --authorization-mode=Node,RBAC \\\\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\\\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\\\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\\\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\\\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --etcd-servers=https://10.240.0.10:2379 \\\\
  --event-ttl=1h \\\\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\\\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\\\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\\\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --kubelet-https=true \\\\
  --runtime-config=api/all=true \\\\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\\\
  --service-cluster-ip-range=172.16.11.0/24 \\\\
  --service-node-port-range=30000-32767 \\\\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\\\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\\\
  --v=2 \\\\
  --requestheader-client-ca-file=/var/lib/kubernetes/ca.pem \\\\
  --requestheader-allowed-names=front-proxy-client \\\\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\\\
  --requestheader-group-headers=X-Remote-Group \\\\
  --requestheader-username-headers=X-Remote-User \\\\
  --proxy-client-cert-file=/var/lib/kubernetes/kubernetes.pem \\\\
  --proxy-client-key-file=/var/lib/kubernetes/kubernetes-key.pem
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp  /vagrant/kubeconfigs/kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service >/dev/null
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\\\
  --address=0.0.0.0 \\\\
  --cluster-cidr=10.200.0.0/16 \\\\
  --cluster-name=kubernetes \\\\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\\\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\\\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\\\
  --leader-elect=true \\\\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\\\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\\\
  --service-cluster-ip-range=172.16.11.0/24 \\\\
  --use-service-account-credentials=true \\\\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp /vagrant/kubeconfigs/kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml >/dev/null
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: \"/var/lib/kubernetes/kube-scheduler.kubeconfig\"
leaderElection:
  leaderElect: true
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service >/dev/null
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\\\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\\\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler

sudo apt-get -qq update
sudo apt-get -qq install -y nginx > /dev/null

cat > kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF

sudo mv kubernetes.default.svc.cluster.local \\
  /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
sudo systemctl restart nginx
sudo systemctl enable nginx
kubectl get componentstatuses --kubeconfig /vagrant/kubeconfigs/admin.kubeconfig
curl -H \"Host: kubernetes.default.svc.cluster.local\" -i http://127.0.0.1/healthz

cat <<EOF | kubectl apply --kubeconfig /vagrant/kubeconfigs/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: \"true\"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - \"\"
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - \"*\"
  - apiGroups:
      - \"metrics.k8s.io\"
    resources:
      - \"*\"
    verbs:
      - \"*\"
EOF

cat <<EOF | kubectl apply --kubeconfig /vagrant/kubeconfigs/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: \"\"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
'''

KUBERNETES_PUBLIC_ADDRESS=$(vagrant ssh master -c "ip address show | grep 'inet 10.240' | sed -e 's/^.*inet //' -e 's/\/.*$//'| tr -d '\n'" 2>/dev/null)

curl -s --cacert certs/ca.pem https://${KUBERNETES_PUBLIC_ADDRESS}:6443/version
