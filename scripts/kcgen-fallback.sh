#!/usr/bin/env bash
set -euo pipefail

USERNAME="nginx-deployer"
SUFFIX=$(openssl rand -hex 4)
CSR_NAME="kcgen-${USERNAME}-${SUFFIX}"
KUBECONFIG_OUT="${HOME}/.kube/${USERNAME}-kubeconfig.yaml"

# Temp dir holds the key and CSR on disk briefly; wiped on exit
TMP_WORKDIR=$(mktemp -d)
trap 'rm -rf "${TMP_WORKDIR}"' EXIT
KEY_FILE="${TMP_WORKDIR}/client.key"
CSR_FILE="${TMP_WORKDIR}/client.csr"

# 1. Generate ECDSA P-256 private key in PKCS#8 PEM format
#    matches Go's ecdsa.GenerateKey(elliptic.P256()) + x509.MarshalPKCS8PrivateKey
echo "Generating ECDSA P-256 private key..."
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "${KEY_FILE}" 2>/dev/null

# 2. Generate a CSR with CN=nginx-deployer
#    matches x509.CertificateRequest{Subject: pkix.Name{CommonName: username}}
echo "Generating CSR..."
openssl req -new -key "${KEY_FILE}" -subj "/CN=${USERNAME}" -out "${CSR_FILE}" 2>/dev/null

# 3. Submit the CSR to Kubernetes
#    matches submitCSR(): signerName kube-apiserver-client, usage client auth only
#    name format matches kcgen-<username>-<4-byte-hex-suffix>
CSR_B64=$(base64 -w 0 < "${CSR_FILE}")
echo "Submitting CSR ${CSR_NAME} to Kubernetes..."
kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
    - client auth
EOF

# 4. Approve the CSR
#    kubectl certificate approve patches .status.conditions the same way approveCSR() does
echo "Approving CSR..."
kubectl certificate approve "${CSR_NAME}"

# 5. Poll for the signed certificate — 2s interval, 30s deadline
#    matches getSignedCert(): checks csr.Status.Certificate every 2s up to 30s
echo "Waiting for signed certificate..."
DEADLINE=$((SECONDS + 30))
CLIENT_CERT_B64=""
while [ "${SECONDS}" -lt "${DEADLINE}" ]; do
    CLIENT_CERT_B64=$(kubectl get csr "${CSR_NAME}" \
        -o jsonpath='{.status.certificate}' 2>/dev/null || true)
    if [ -n "${CLIENT_CERT_B64}" ]; then
        break
    fi
    sleep 2
done

if [ -z "${CLIENT_CERT_B64}" ]; then
    echo "Error: timed out waiting for certificate from CSR ${CSR_NAME}" >&2
    exit 1
fi
echo "Signed certificate obtained"

# 6. Retrieve cluster CA and server URL
#    matches genKubeConfig(): CA from kube-root-ca.crt ConfigMap in kube-system
#    server comes from the active kubeconfig (same as restConfig.Host)
echo "Retrieving cluster CA and server URL..."
CA_CERT_B64=$(kubectl get configmap kube-root-ca.crt -n kube-system \
    -o jsonpath='{.data.ca\.crt}' | base64 -w 0)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Base64-encode the private key for embedding in the kubeconfig
CLIENT_KEY_B64=$(base64 -w 0 < "${KEY_FILE}")

# 7. Write the kubeconfig
#    matches genKubeConfig() + clientcmd.Write(): same cluster/context/user structure
#    0600 matches os.WriteFile(path, data, 0600)
echo "Writing kubeconfig to ${KUBECONFIG_OUT}..."
cat > "${KUBECONFIG_OUT}" <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT_B64}
    server: ${SERVER}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: ${USERNAME}
  name: kubernetes
current-context: kubernetes
kind: Config
preferences: {}
users:
- name: ${USERNAME}
  user:
    client-certificate-data: ${CLIENT_CERT_B64}
    client-key-data: ${CLIENT_KEY_B64}
EOF

chmod 0600 "${KUBECONFIG_OUT}"
echo "Successfully wrote kubeconfig to ${KUBECONFIG_OUT}"
