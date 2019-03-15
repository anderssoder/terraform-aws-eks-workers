kind: Deployment
apiVersion: apps/v1
metadata:
  name: kube-node-drainer-asg-status-updater
  namespace: kube-system
  labels:
    k8s-app: kube-node-drainer-asg-status-updater
spec:
  selector:
    matchLabels:
      k8s-app: kube-node-drainer-asg-status-updater
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: kube-node-drainer-asg-status-updater
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
        iam.amazonaws.com/role: ${aws_iam_role_arn}
    spec:
      priorityClassName: system-node-critical
      initContainers:
      - name: hyperkube
        image: ${hyperkubeimage}
        command:
        - /bin/cp
        - -f
        - /hyperkube
        - /workdir/hyperkube
        volumeMounts:
        - mountPath: /workdir
          name: workdir
      containers:
      - name: main
        image: ${aws_cli_image}
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        command:
        - /bin/sh
        - -xec
        - |
          metadata() { curl -s -S -f http://169.254.169.254/2016-09-02/"$1"; }
          asg()      { aws --region="$${REGION}" autoscaling "$@"; }

          # Hyperkube binary is not statically linked, so we need to use
          # the musl interpreter to be able to run it in this image
          # See: https://github.com/kubernetes-incubator/kube-aws/pull/674#discussion_r118889687
          kubectl() { /lib/ld-musl-x86_64.so.1 /opt/bin/hyperkube kubectl "$@"; }

          REGION=$(metadata dynamic/instance-identity/document | jq -r .region)
          [ -n "$${REGION}" ]

          # Not customizable, for now
          POLL_INTERVAL=10

          # Keeps a comma-separated list of instances that need to be drained. Sets '-'
          # to force the ConfigMap to be updated in the first iteration.
          instances_to_drain='-'

          # Instance termination detection loop
          while sleep $${POLL_INTERVAL}; do

            # Fetch the list of instances being terminated by their respective ASGs
            updated_instances_to_drain=$(asg describe-auto-scaling-groups | jq -r '[.AutoScalingGroups[] | select((.Tags[].Key | contains("EKS")) and (.Tags[].Key | contains("kubernetes.io/cluster/${cluster_name}"))) | .Instances[] | select(.LifecycleState == "Terminating:Wait") | .InstanceId] | sort | join(",")')

            # Have things changed since last iteration?
            if [ "$${updated_instances_to_drain}" == "$${instances_to_drain}" ]; then
            continue
            fi
            instances_to_drain="$${updated_instances_to_drain}"

            # Update ConfigMap to reflect current ASG state
            echo "{\"apiVersion\": \"v1\", \"kind\": \"ConfigMap\", \"metadata\": {\"name\": \"kube-node-drainer-status\"}, \"data\": {\"asg\": \"$${instances_to_drain}\"}}" | kubectl -n kube-system apply -f -
          done
        volumeMounts:
        - mountPath: /opt/bin
          name: workdir
      volumes:
        - name: workdir
          emptyDir: {}