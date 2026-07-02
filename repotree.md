takehome-kubeadm-webapp/
  README.md
  docs/
    design.md
    validation.md

  terraform/
    main.tf
    providers.tf
    variables.tf
    outputs.tf
    networking.tf
    security-groups.tf
    ec2.tf
    nlb.tf
    templates/
      inventory.ini.tftpl

  ansible/
    site.yml
    inventory.ini
    group_vars/
      all.yml
    roles/
      common/
      containerd/
      kubeadm/
      control-plane/
      worker/

  scripts/
    bootstrap-cilium.sh
    bootstrap-argocd.sh
    create-csr-user.sh
    verify.sh

  platform/
    root-app.yaml
    gateway-api/
    traefik/
    cert-manager/
    issuers/
    gateway/

  charts/
    nginx-site/
      Chart.yaml
      values.yaml
      templates/
        deployment.yaml
        service.yaml
        httproute.yaml
        configmap.yaml
        _helpers.tpl

  environments/
    manual-values.yaml
    gitops-values.yaml

  rbac/
    nginx-manual-role.yaml
    nginx-manual-rolebinding.yaml
