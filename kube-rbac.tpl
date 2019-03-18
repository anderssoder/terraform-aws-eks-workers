kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-extensions
rules:
  - apiGroups: [""]
    resources: 
    - nodes
    verbs:
    - get
    - patch
    - update
  - apiGroups: [""]
    resources: 
    - configmaps
    verbs: 
    - create
    - update
    - get
    - patch
  - apiGroups: ["extensions"]
    resources:
    - replicasets
    verbs:
    - get
  - apiGroups: ["extensions"]
    resources:
    - daemonsets
    verbs:
    - get
  - apiGroups: ["batch"]
    resources:
    - jobs
    verbs:
    - get
  - apiGroups: [""]
    resources:
    - replicationcontrollers
    verbs:
    - get
  - apiGroups: [""]
    resources:
    - pods/eviction
    verbs:
    - create
  - apiGroups: [""]
    resources:
    - pods
    verbs:
    - get
  - nonResourceURLs: ["*"]
    verbs: ["*"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-extensions
subjects:
  - kind: User
    name: system:serviceaccount:kube-system:default
  - kind: Group
    name: system:nodes
roleRef:
  kind: ClusterRole
  name: node-extensions
  apiGroup: rbac.authorization.k8s.io