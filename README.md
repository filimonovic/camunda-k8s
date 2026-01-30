# camunda-k8s

1. PRIPREMA ELASTICSEARCH KLASTERA
1.1 Kreiranje korisnika i prava
Na vašem eksternom Elasticsearch klasteru (3 noda), treba da kreirate:
bash
# Kreiranje korisnika za Camunda
curl -X POST "https://your-es-cluster:9200/_security/user/camunda_user" \
  -H "Content-Type: application/json" \
  -u elastic:your_password \
  -d '{
    "password" : "camunda_strong_password",
    "roles" : [ "camunda_role" ],
    "full_name" : "Camunda Platform User"
  }'

# Kreiranje role sa potrebnim pravima
curl -X POST "https://your-es-cluster:9200/_security/role/camunda_role" \
  -H "Content-Type: application/json" \
  -u elastic:your_password \
  -d '{
    "cluster": ["monitor", "manage_index_templates"],
    "indices": [
      {
        "names": ["zeebe-*", "operate-*", "tasklist-*", "optimize-*"],
        "privileges": ["all"]
      }
    ]
  }'
1.2 SSL Certifikat (ako koristite HTTPS)
Ako Elasticsearch koristi self-signed sertifikat:
bash# 
Izvucite sertifikat iz Elasticsearch
openssl s_client -showcerts -connect your-es-host:9200 </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > elastic.crt

# Kreirajte JKS keystore
keytool -import -alias elasticsearch -keystore externaldb.jks \
  -storetype jks -file elastic.crt -storepass changeit -noprompt

# Kreirajte Kubernetes secret
kubectl create secret generic elastic-jks \
  -n camunda-platform \
  --from-file=externaldb.jks
1.3 Kreiranje Kubernetes Secreta za Elasticsearch kredencijale
bashkubectl create secret generic elasticsearch-credentials \
  -n camunda-platform \
  --from-literal=username=camunda_user \
  --from-literal=password=camunda_strong_password
2. PRIPREMA POSTGRESQL
2.1 Kreiranje baza podataka
sql-- Za Keycloak
CREATE DATABASE keycloak;
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD 'keycloak_strong_password';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;

-- Za Identity (ako koristite eksterni PostgreSQL za Identity)
CREATE DATABASE identity;
CREATE USER identity_user WITH ENCRYPTED PASSWORD 'identity_strong_password';
GRANT ALL PRIVILEGES ON DATABASE identity TO identity_user;

-- Za Web Modeler (ako koristite)
CREATE DATABASE webmodeler;
CREATE USER webmodeler_user WITH ENCRYPTED PASSWORD 'webmodeler_strong_password';
GRANT ALL PRIVILEGES ON DATABASE webmodeler TO webmodeler_user;
2.2 Kreiranje Kubernetes Secrets za PostgreSQL
bash# Secret za Keycloak
kubectl create secret generic pg-keycloak-secret \
  -n camunda-platform \
  --from-literal=username=keycloak_user \
  --from-literal=password=keycloak_strong_password

# Secret za Identity (ako je potrebno)
kubectl create secret generic pg-identity-secret \
  -n camunda-platform \
  --from-literal=username=identity_user \
  --from-literal=password=identity_strong_password
3. PRIPREMA KEYCLOAK
3.1 Konfiguracija Keycloak-a da koristi PostgreSQL
Ako već imate Keycloak deployed, proverite da je konfigurisan sa PostgreSQL. Ako postavljate novi Keycloak:
yaml# keycloak-values.yaml za vaš Keycloak Helm chart
postgresql:
  enabled: false  # Koristite eksterni PostgreSQL

externalDatabase:
  host: "your-postgresql-host"
  port: 5432
  database: "keycloak"
  user: "keycloak_user"
  existingSecret: "pg-keycloak-secret"
  existingSecretPasswordKey: "password"
3.2 Kreiranje admin korisnika za Camunda Identity
U Keycloak Admin Console:

Kreirajte admin korisnika (npr. camunda-admin)
Ovaj korisnik će biti korišćen od strane Camunda Identity komponente da kreira realm i klijente

Ili putem CLI:
bashkubectl exec -it keycloak-0 -n camunda-platform -- /opt/keycloak/bin/kcadm.sh \
  config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin_password

kubectl exec -it keycloak-0 -n camunda-platform -- /opt/keycloak/bin/kcadm.sh \
  create users \
  -r master \
  -s username=camunda-admin \
  -s enabled=true
3.3 Kreiranje Secret-a za Keycloak admin pristup
bashkubectl create secret generic keycloak-admin-credentials \
  -n camunda-platform \
  --from-literal=admin-user=camunda-admin \
  --from-literal=admin-password=camunda_admin_strong_password
4. CAMUNDA PLATFORM HELM VALUES.YAML
Sada kreirajte svoj values.yaml za Camunda Platform:
yaml# values.yaml za Camunda Platform
global:
  # Elasticsearch konfiguracija
  elasticsearch:
    enabled: true
    external: true
    auth:
      username: ""  # Prazno jer koristimo existingSecret
      password: ""
      existingSecret: elasticsearch-credentials
      existingSecretKey: password
    url:
      protocol: https  # ili http ako nemate SSL
      host: "your-elasticsearch-host"
      port: 9200
    # Ako koristite self-signed sertifikat
    tls:
      enabled: true
      existingSecret: elastic-jks
  
  # Identity i Auth konfiguracija
  identity:
    auth:
      enabled: true
      publicIssuerUrl: "https://your-keycloak-url/auth/realms/camunda-platform"
      issuerBackendUrl: "http://keycloak-service.camunda-platform.svc.cluster.local:8080/auth/realms/camunda-platform"
      tokenUrl: "https://your-keycloak-url/auth/realms/camunda-platform/protocol/openid-connect/token"
      jwksUrl: "https://your-keycloak-url/auth/realms/camunda-platform/protocol/openid-connect/certs"
    
    keycloak:
      url:
        protocol: http
        host: keycloak-service.camunda-platform.svc.cluster.local
        port: 8080
        contextPath: "/auth"
      realm: "camunda-platform"
      auth:
        adminUser: "camunda-admin"
        existingSecret: keycloak-admin-credentials
        existingSecretKey: admin-password
  
  # Ingress konfiguracija (OpenShift Route)
  ingress:
    enabled: true
    className: ""  # OpenShift koristi routes
    host: "camunda.your-domain.com"
    tls:
      enabled: true
      secretName: "camunda-tls-secret"

# Disable unutrašnji Elasticsearch
elasticsearch:
  enabled: false

# Identity konfiguracija
identity:
  enabled: true
  # Ako koristite eksterni PostgreSQL za Identity
  externalDatabase:
    enabled: true
    host: "your-postgresql-host"
    port: 5432
    database: "identity"
    existingSecret: pg-identity-secret
    existingSecretPasswordKey: password

# Keycloak konfiguracija - disable ako koristite eksterni
identityKeycloak:
  enabled: true
  postgresql:
    enabled: false  # Koristite eksterni PostgreSQL
  externalDatabase:
    host: "your-postgresql-host"
    port: 5432
    database: "keycloak"
    user: "keycloak_user"
    existingSecret: pg-keycloak-secret
    existingSecretPasswordKey: password

# Zeebe konfiguracija za produkciju
zeebe:
  clusterSize: 3
  partitionCount: 3
  replicationFactor: 3
  
  retention:
    enabled: true
    minimumAge: 30d
    policyName: "zeebe-record-retention-policy"
  
  resources:
    requests:
      cpu: "1"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"

zeebe-gateway:
  replicas: 2
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1"
      memory: "2Gi"

# Operate konfiguracija
operate:
  enabled: true
  replicas: 2
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1"
      memory: "2Gi"

# Tasklist konfiguracija
tasklist:
  enabled: true
  replicas: 2
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1"
      memory: "2Gi"

# Optimize konfiguracija
optimize:
  enabled: true
  resources:
    requests:
      cpu: "1"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"

# Connectors
connectors:
  enabled: true
  replicas: 1

# Web Modeler (opciono)
webModeler:
  enabled: false
  # Ako ga omogućite:
  # restapi:
  #   externalDatabase:
  #     host: "your-postgresql-host"
  #     database: "webmodeler"
  #     existingSecret: pg-webmodeler-secret
5. OPENSHIFT SPECIFIČNA PODEŠAVANJA
Za OpenShift, potrebno je dodati Security Context podešavanja:
yaml# openshift-values.yaml
# Append ovo na vaš values.yaml ili napravite overlay

# Disable default security contexts zbog OpenShift SCC
identity:
  keycloak:
    containerSecurityContext:
      runAsUser: null
    podSecurityContext:
      fsGroup: null
      runAsUser: null
    postgresql:
      primary:
        containerSecurityContext:
          runAsUser: null
        podSecurityContext:
          fsGroup: null
          runAsUser: null
6. INSTALACIJA
bash# Dodajte Camunda Helm repo
helm repo add camunda https://helm.camunda.io
helm repo update

# Instalirajte Camunda Platform
helm install camunda-platform camunda/camunda-platform \
  --namespace camunda-platform \
  --values values.yaml \
  --values openshift-values.yaml \
  --version 10.x.x  # Koristite najnoviju verziju
7. POST-INSTALACIJA PROVERA
bash# Proverite podove
kubectl get pods -n camunda-platform

# Proverite Elasticsearch konekciju
kubectl logs -n camunda-platform deployment/camunda-operate | grep -i elasticsearch

# Proverite Keycloak realm kreiranje
kubectl logs -n camunda-platform deployment/camunda-identity | grep -i keycloak

# Proverite route/ingress
oc get routes -n camunda-platform  # Za OpenShift
8. KEYCLOAK VERIFIKACIJA
Nakon instalacije, u Keycloak Admin Console proverite:

Realm: camunda-platform je kreiran
Clients: Kreirani su klijenti za sve Camunda komponente:

operate
tasklist
optimize
zeebe
connectors


Users: Možete dodati korisnike i dodeliti im role

9. PRODUKCIONI BEST PRACTICES

Backup: Konfigurišite backup za Elasticsearch i PostgreSQL
Monitoring: Postavite Prometheus monitoring
Resource Limits: Podesite na osnovu load testova
High Availability: Koristite multiple replike za sve komponente
TLS: Omogućite TLS komunikaciju između svih komponenti
Network Policies: Restriktujte mrežni pristup između podova

Ovo bi trebalo da vam pruži kompletan setup za produkciono okruženje. Prilagodite vrednosti prema vašim specifičnim zahtevima i resursima.
