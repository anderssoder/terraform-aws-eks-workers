kind: DaemonSet
apiVersion: extensions/v1beta1
metadata:
  name: kube-node-drainer-asg-ds
  namespace: kube-system
  labels:
    k8s-app: kube-node-drainer-asg-ds
spec:
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: kube-node-drainer-asg-ds
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      tolerations:
      - operator: Exists
        effect: NoSchedule
      - operator: Exists
        effect: NoExecute
      - operator: Exists
        key: CriticalAddonsOnly
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
          metadata() { wget -O - -q http://169.254.169.254/2016-09-02/"$1"; }
          asg()      { aws --region="${REGION}" autoscaling "$@"; }

          # Hyperkube binary is not statically linked, so we need to use
          # the musl interpreter to be able to run it in this image
          # See: https://github.com/kubernetes-incubator/kube-aws/pull/674#discussion_r118889687
          kubectl() { /lib/ld-musl-x86_64.so.1 /opt/bin/hyperkube kubectl "$@"; }

          INSTANCE_ID=$(metadata meta-data/instance-id)
          REGION=$(metadata dynamic/instance-identity/document | jq -r .region)
          [ -n "\$${REGION}" ]

          while sleep 30; do
            STATE=$(asg describe-auto-scaling-instances --region "\$${REGION}" --instance-ids "\$${INSTANCE_ID}" | jq -r '.AutoScalingInstances[].LifecycleState')
            if [ ! "\$${STATE}" = Terminating:Wait ]; then
            continue
            fi
            echo Node is in Terminating:Wait state, draining it

            if ! kubectl drain --ignore-daemonsets=true --delete-local-data=true --force=true --timeout=60s "\$${NODE_NAME}"; then
            echo Not all pods on this host can be evicted, will try again
            continue
            fi

            echo All evictable pods are gone, notifying AutoScalingGroup that instance \$${INSTANCE_ID} can be shutdown
            ASG_NAME=$(asg describe-auto-scaling-instances --instance-ids "\$${INSTANCE_ID}" | jq -r '.AutoScalingInstances[].AutoScalingGroupName')
            HOOK_NAME=$(asg describe-lifecycle-hooks --auto-scaling-group-name "\$${ASG_NAME}" | jq -r '.LifecycleHooks[].LifecycleHookName' | grep -i nodedrainer)

            echo Sending notification to ASG_NAME=\$${ASG_NAME} HOOK_NAME=\$${HOOK_NAME}
            asg complete-lifecycle-action --lifecycle-action-result CONTINUE --instance-id "\$${INSTANCE_ID}" --lifecycle-hook-name "\$${HOOK_NAME}" --auto-scaling-group-name "\$${ASG_NAME}"

            # sleep 5 mins + 1 mins, expecting that instance will be shut down in this time
            sleep 300
          done
        volumeMounts:
        - mountPath: /opt/bin
          name: workdir
      volumes:
      - name: workdir
        emptyDir: {}