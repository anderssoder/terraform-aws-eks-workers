kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: configmap-updater
rules:
  - apiGroups: [""]
    resources: 
    - configmaps
    verbs: 
    - create
    - update
    - get
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: configmap-updater
subjects:
  - kind: User
    name: system:serviceaccount:kube-system:default
  - kind: Group
    name: system:nodes
roleRef:
  kind: ClusterRole
  name: configmap-updater
  apiGroup: rbac.authorization.k8s.io